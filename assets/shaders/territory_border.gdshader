shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// AAA-quality territory border energy field.
// Multi-layer hexagonal grid, animated energy tendrils, scan lines,
// proximity brightening, noise-based dissolve with ember edge.

uniform vec3 border_color : source_color = vec3(0.2, 0.5, 1.0);
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.18;
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.5;
uniform float border_height : hint_range(5.0, 80.0) = 40.0;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;

// ── Noise helpers ───────────────────────────────────────────────────

float hash2d(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3d(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2d(i);
	float b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0));
	float d = hash2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm3(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * noise2d(p);
		p *= 2.3;
		a *= 0.45;
	}
	return v;
}

float fbm_dissolve(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise2d(p);
		p *= 2.3;
		a *= 0.45;
	}
	return v;
}

// ── Hexagonal grid — proper honeycomb pattern ───────────────────────

float hex_distance(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(1.0, 1.73205) * 0.5), p.x);
}

float hex_grid(vec2 uv, float scale) {
	uv *= scale;
	vec2 r = vec2(1.0, 1.73205);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = (dot(a, a) < dot(b, b)) ? a : b;
	float d = hex_distance(gv);
	float edge = smoothstep(0.45, 0.5, d);
	return edge;
}

// ── Energy tendrils — flowing vertical lines ────────────────────────

float energy_tendrils(vec2 uv, float t) {
	float tendril = 0.0;
	// Multiple thin vertical channels
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float x_offset = sin(uv.y * (2.0 + fi * 0.7) + t * (1.2 + fi * 0.3) + fi * 1.5) * 0.08;
		float dist = abs(uv.x - x_offset - (fi - 1.5) * 0.25);
		tendril += smoothstep(0.02, 0.0, dist) * (0.5 + 0.5 * sin(uv.y * 8.0 + t * 3.0 + fi));
	}
	return clamp(tendril, 0.0, 1.0);
}

// ── Scan lines — horizontal sweep ──────────────────────────────────

float scan_line(float y, float t, float speed) {
	float scan_pos = fract(t * speed);
	float dist = abs(y - scan_pos);
	dist = min(dist, 1.0 - dist);  // Wrap around
	return smoothstep(0.015, 0.0, dist) * 0.8;
}

void fragment() {
	float t = TIME * pulse_speed;

	// ── Fresnel — edge glow ──
	float NdV = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - NdV, fresnel_power);

	// ── Height-normalized UV for effects ──
	float height_01 = clamp(VERTEX.y / border_height, 0.0, 1.0);
	vec2 field_uv = vec2(VERTEX.x * 0.005, height_01);  // Stretch along wall

	// ── Animated energy pulse — multi-layer for organic feel ──
	float pulse1 = sin(t * 1.0 + VERTEX.y * 3.0) * 0.25 + 0.75;
	float pulse2 = sin(t * 0.6 - VERTEX.y * 1.8 + 2.0) * 0.15 + 0.85;
	float pulse3 = sin(t * 1.7 + VERTEX.y * 5.0 + VERTEX.x * 0.5) * 0.1 + 0.9;
	float combined_pulse = pulse1 * pulse2 * pulse3;

	// ── Vertical fade — base glow, transparent top ──
	float vertical_fade = 1.0 - smoothstep(0.0, border_height * 0.85, VERTEX.y);
	float bottom_glow = smoothstep(3.0, 0.0, VERTEX.y) * 0.4;
	float top_whisp = smoothstep(border_height * 0.7, border_height, VERTEX.y) * 0.15;

	// ── Hexagonal grid — two scales for depth ──
	vec2 grid_uv1 = VERTEX.xz * 0.08 + vec2(0.0, TIME * 0.03);
	float hex1 = hex_grid(grid_uv1, 1.0);
	vec2 grid_uv2 = VERTEX.xz * 0.04 + vec2(TIME * 0.02, 0.0);
	float hex2 = hex_grid(grid_uv2, 1.5);
	float hex_pattern = mix(0.6, 1.0, mix(hex1, hex2, 0.4));

	// ── Energy tendrils ──
	float tendrils = energy_tendrils(field_uv, t);

	// ── Scan lines ──
	float scan1 = scan_line(height_01, TIME, 0.15);
	float scan2 = scan_line(height_01, TIME + 0.5, 0.22);

	// ── Noise shimmer — random flicker ──
	float shimmer = fbm3(VERTEX.xz * 0.3 + TIME * 0.5) * 0.3;

	// ── Composite ──
	float field_alpha = fresnel * combined_pulse * opacity * vertical_fade * hex_pattern;
	field_alpha += bottom_glow * opacity;
	field_alpha += tendrils * 0.15;
	field_alpha += (scan1 + scan2) * 0.12;
	field_alpha += shimmer * 0.05 * fresnel;
	field_alpha -= top_whisp;
	field_alpha = clamp(field_alpha, 0.0, 0.6);

	// Emission: hex grid lines glow, tendrils glow brighter
	vec3 base_emission = border_color * fresnel * combined_pulse * 0.6;
	vec3 tendril_emission = border_color * tendrils * 1.5;
	vec3 scan_emission = (border_color + vec3(0.2)) * (scan1 + scan2) * 0.8;
	vec3 hex_emission = border_color * (1.0 - hex_pattern) * 0.3;

	// ── Dissolve ──
	if (dissolve_progress > 0.001) {
		float dissolve_noise = fbm_dissolve(VERTEX.xz * 0.08 + VERTEX.y * 0.1);
		float threshold = dissolve_progress * 1.3;

		if (dissolve_noise < threshold) {
			discard;
		}

		float edge_dist = dissolve_noise - threshold;
		float edge_glow = smoothstep(0.1, 0.0, edge_dist);
		// White-hot to orange burn edge
		vec3 burn_color = mix(border_color * 3.0, vec3(1.0, 0.6, 0.2), edge_glow * 0.7);
		// Add ember sparks near edge
		float spark = step(0.97, hash3d(vec3(VERTEX.xz * 2.0, TIME * 5.0))) * edge_glow;

		ALBEDO = mix(border_color, burn_color, edge_glow) + vec3(spark * 2.0);
		ALPHA = field_alpha + edge_glow * 0.6 + spark;
		EMISSION = mix(base_emission + tendril_emission + scan_emission + hex_emission, burn_color * 3.0, edge_glow);
	} else {
		ALBEDO = border_color;
		ALPHA = field_alpha;
		EMISSION = base_emission + tendril_emission + scan_emission + hex_emission;
	}
}
