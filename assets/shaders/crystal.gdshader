shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Crystal mineral formations — hexagonal prisms with internal glow.
// Refraction approximation, faceted specular, inner light.

uniform vec3 crystal_color = vec3(0.4, 0.55, 0.75);
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;

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
	// Faceted surface — low roughness, high metallic for glassy look
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	// Internal veins — procedural noise gives crystal inclusions
	vec2 crystal_uv = VERTEX.xy * 8.0 + VERTEX.z * 5.0;
	float veins = value_noise(crystal_uv);
	float vein_line = smoothstep(0.4, 0.5, veins) * smoothstep(0.6, 0.5, veins);

	// Surface color — transparent/translucent crystal body
	vec3 body_col = crystal_color * (0.6 + veins * 0.4);

	// Height-based darkening (base is embedded in rock)
	float height_fade = smoothstep(-0.1, 0.3, UV.y);
	body_col *= (0.4 + height_fade * 0.6);

	ALBEDO = body_col;
	ROUGHNESS = 0.08 + (1.0 - height_fade) * 0.3;
	METALLIC = 0.4 + fresnel * 0.3;
	SPECULAR = 0.8;

	// Internal glow — energy from territory power
	float glow_pulse = sin(TIME * 2.0 + VERTEX.y * 8.0) * 0.5 + 0.5;
	float inner_glow = territory_power * (0.3 + glow_pulse * 0.4 + vein_line * 0.5);

	// Fresnel rim glow — catches light at edges
	float rim_glow = fresnel * (0.3 + territory_power * 0.5);

	EMISSION = crystal_color * (inner_glow + rim_glow) * 1.5;

	// Subsurface scattering approximation — light passes through thin crystals
	BACKLIGHT = crystal_color * territory_power * 0.3;
}
