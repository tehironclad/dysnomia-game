shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Creature PBR shader — supports organic flesh, chitinous armor, and bioluminescent veins.
// Mode 0: Organic (Stalker/Burrower) — subsurface scattering, fleshy texture
// Mode 1: Chitinous (Crawler) — hard faceted shell, iridescent
// Mode 2: Translucent (Floater) — jellyfish-like translucency
// Mode 3: Bioluminescent accent — glowing vein overlay

uniform int creature_mode : hint_range(0, 3) = 0;
uniform vec3 base_color : source_color = vec3(0.4, 0.25, 0.2);
uniform vec3 accent_glow : source_color = vec3(0.2, 0.8, 0.4);
uniform float glow_intensity : hint_range(0.0, 3.0) = 0.5;
uniform float health_factor : hint_range(0.0, 1.0) = 1.0;
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float death_dissolve : hint_range(0.0, 1.0) = 0.0;

// ─── Noise ───────────────────────────────────────────────────────
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Voronoi for vein patterns
float voronoi_dist(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_d = 1.0;
	float second_d = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 nb = vec2(float(x), float(y));
			vec2 cell = vec2(hash21(i + nb), hash21((i + nb) * 1.7 + 0.5));
			float d = length(nb + cell - f);
			if (d < min_d) { second_d = min_d; min_d = d; }
			else if (d < second_d) { second_d = d; }
		}
	}
	return second_d - min_d;
}

void fragment() {
	vec3 wp = VERTEX;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	// ── Death dissolve ──
	if (death_dissolve > 0.01) {
		float noise_val = value_noise(wp.xz * 3.0 + wp.y * 2.0);
		if (noise_val < death_dissolve) {
			discard;
		}
		// Edge glow near dissolve boundary
		float edge = smoothstep(death_dissolve, death_dissolve + 0.08, noise_val);
		if (edge < 1.0) {
			EMISSION = accent_glow * (1.0 - edge) * 4.0;
		}
	}

	// ── Bioluminescent veins (Voronoi) ──
	float vein_scale = 4.0;
	vec2 vein_uv = wp.xz * vein_scale + wp.y * 1.5;
	float veins = voronoi_dist(vein_uv);
	float vein_glow = smoothstep(0.0, 0.06, veins);
	vein_glow = 1.0 - vein_glow; // Invert: thin lines glow
	// Animate: pulse along veins
	float vein_pulse = sin(length(wp) * 3.0 - TIME * 2.0) * 0.5 + 0.5;
	vein_glow *= vein_pulse;

	// ── Mode: Organic Flesh ──
	if (creature_mode == 0) {
		float flesh_noise = value_noise(wp.xz * 5.0 + wp.y * 3.0);
		float flesh_detail = value_noise(wp.xz * 15.0);
		ALBEDO = base_color * (0.8 + flesh_noise * 0.3 + flesh_detail * 0.1);
		ROUGHNESS = 0.65 + flesh_noise * 0.15;
		METALLIC = 0.0;
		SPECULAR = 0.4;
		// Subsurface via BACKLIGHT
		BACKLIGHT = base_color * 0.25 * health_factor;
		// Vein emission
		EMISSION = accent_glow * vein_glow * glow_intensity * 0.5;
	}

	// ── Mode: Chitinous Shell ──
	else if (creature_mode == 1) {
		float chitin_noise = value_noise(wp.xz * 8.0);
		ALBEDO = base_color * (0.7 + chitin_noise * 0.3);
		ROUGHNESS = 0.2 + chitin_noise * 0.15;
		METALLIC = 0.25;
		SPECULAR = 0.7;
		// Iridescent shift based on view angle
		float iridescence = fresnel * 0.3;
		ALBEDO += vec3(iridescence * 0.2, iridescence * 0.1, -iridescence * 0.1);
		// Armor plate lines
		float plate_line = fract(wp.y * 6.0);
		float plate_gap = smoothstep(0.0, 0.03, plate_line) * smoothstep(1.0, 0.97, plate_line);
		ALBEDO *= 0.5 + plate_gap * 0.5;
		AO = plate_gap * 0.6 + 0.4;
		EMISSION = accent_glow * vein_glow * glow_intensity * 0.3;
	}

	// ── Mode: Translucent (Floater/Jellyfish) ──
	else if (creature_mode == 2) {
		float trans_noise = value_noise(wp.xz * 4.0 + TIME * 0.3);
		ALBEDO = base_color * (0.5 + trans_noise * 0.5);
		ROUGHNESS = 0.1;
		METALLIC = 0.0;
		SPECULAR = 0.6;
		// Translucency via BACKLIGHT
		BACKLIGHT = base_color * 0.6;
		// Depth-based absorption (thicker = darker)
		float depth_abs = clamp(length(VERTEX) * 0.15, 0.0, 0.6);
		ALBEDO *= 1.0 - depth_abs;
		// Strong vein glow
		EMISSION = accent_glow * vein_glow * glow_intensity;
		// Pulsing rim
		EMISSION += accent_glow * fresnel * 0.5 * (sin(TIME * 2.0) * 0.3 + 0.7);
	}

	// ── Mode: Pure bioluminescent ──
	else {
		ALBEDO = base_color * 0.3;
		ROUGHNESS = 0.5;
		EMISSION = accent_glow * glow_intensity * (0.5 + vein_glow * 0.5);
	}

	// ── Damage flash overlay ──
	if (damage_flash > 0.01) {
		EMISSION += vec3(1.0, 0.2, 0.1) * damage_flash * 2.0;
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.3, 0.2), damage_flash * 0.4);
	}

	// ── Normal map ──
	float eps = 0.05;
	vec2 nm_uv = wp.xz * 6.0;
	float h_c = value_noise(nm_uv);
	float h_r = value_noise(nm_uv + vec2(eps, 0.0));
	float h_u = value_noise(nm_uv + vec2(0.0, eps));
	NORMAL_MAP = normalize(vec3((h_c - h_r) / eps, 1.0, (h_c - h_u) / eps)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.4;
}
