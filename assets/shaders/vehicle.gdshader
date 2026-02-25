shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Vehicle PBR shader — brushed metal, panel lines, running lights, dust accumulation.
// Used for Rover, Hoverbike, and Tank.

uniform vec3 base_color : source_color = vec3(0.65, 0.65, 0.68);
uniform vec3 accent_color : source_color = vec3(0.3, 0.5, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.6;
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform float speed_factor : hint_range(0.0, 1.0) = 0.0; // Vehicle speed for running lights
uniform float dust_amount : hint_range(0.0, 1.0) = 0.0; // Dust accumulation

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

void fragment() {
	vec3 wp = VERTEX;
	vec3 n_abs = abs(NORMAL);
	vec3 bw = pow(n_abs, vec3(3.0));
	bw /= (bw.x + bw.y + bw.z);

	// ── Brushed metal: anisotropic directional noise ──
	vec2 brush_uv = wp.xz * bw.y + wp.xy * bw.z + wp.yz * bw.x;
	brush_uv *= 40.0;
	// Stretch noise in one direction for brushing effect
	float brush = value_noise(vec2(brush_uv.x * 6.0, brush_uv.y * 0.8));
	float brush_fine = value_noise(vec2(brush_uv.x * 12.0, brush_uv.y * 1.5));

	vec3 metal_color = base_color * (0.9 + brush * 0.1 + brush_fine * 0.05);
	float metal_rough = base_roughness - brush * 0.1 + brush_fine * 0.05;

	// ── Panel lines (darkened grooves at regular intervals) ──
	float panel_x = fract(wp.x * 3.0);
	float panel_z = fract(wp.z * 3.0);
	float panel_y = fract(wp.y * 4.0);
	float groove_x = smoothstep(0.0, 0.02, panel_x) * smoothstep(1.0, 0.98, panel_x);
	float groove_z = smoothstep(0.0, 0.02, panel_z) * smoothstep(1.0, 0.98, panel_z);
	float groove_y = smoothstep(0.0, 0.025, panel_y) * smoothstep(1.0, 0.975, panel_y);
	float panels = groove_x * groove_z * groove_y;
	metal_color *= 0.6 + panels * 0.4;

	// ── Running lights (emission strips with animated scroll) ──
	float light_uv = wp.x * 10.0 + wp.z * 3.0;
	float light_scroll = TIME * 3.0 * speed_factor;
	float running_light = sin(light_uv - light_scroll) * 0.5 + 0.5;
	running_light = smoothstep(0.75, 0.9, running_light);
	running_light *= speed_factor; // Only visible when moving

	// Power-driven accent lights along edges
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float power_rim = fresnel * territory_power * 0.3;

	// ── Dust accumulation layer ──
	// Dust settles on top-facing and lower surfaces
	float dust_mask = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0); // More dust on top
	dust_mask += clamp(1.0 - wp.y * 2.0, 0.0, 0.5); // More at bottom (road grime)
	dust_mask = clamp(dust_mask * dust_amount, 0.0, 0.8);
	vec3 dust_color = vec3(0.45, 0.40, 0.35); // Regolith dust
	metal_color = mix(metal_color, dust_color, dust_mask);
	metal_rough = mix(metal_rough, 0.85, dust_mask);

	ALBEDO = metal_color;
	ROUGHNESS = clamp(metal_rough, 0.1, 0.95);
	METALLIC = mix(base_metallic, 0.05, dust_mask); // Dust kills metallic
	SPECULAR = 0.5;

	// ── Emission ──
	vec3 light_emission = accent_color * running_light * 1.5;
	vec3 rim_emission = accent_color * power_rim;
	EMISSION = light_emission + rim_emission;

	// ── Normal map from brushing ──
	float eps = 0.02;
	float h_c = value_noise(brush_uv);
	float h_r = value_noise(brush_uv + vec2(eps, 0.0));
	float h_u = value_noise(brush_uv + vec2(0.0, eps));
	NORMAL_MAP = normalize(vec3((h_c - h_r) / eps * 0.5, 1.0, (h_c - h_u) / eps * 0.5)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.3;

	// ── AO in panel grooves ──
	AO = panels * 0.7 + 0.3;
	AO_LIGHT_AFFECT = 0.6;
}
