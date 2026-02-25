shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Energy tesseract wireframe shader — volumetric glow with inner energy core.
// Additive blend, power-driven intensity, chromatic aberration on edges.

uniform vec3 accent_color : source_color = vec3(0.5, 0.7, 1.0);
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.5, 3.0) = 1.5;

// ─── Noise ───────────────────────────────────────────────────────
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash31(i);
	float b = hash31(i + vec3(1.0, 0.0, 0.0));
	float c = hash31(i + vec3(0.0, 1.0, 0.0));
	float d = hash31(i + vec3(1.0, 1.0, 0.0));
	float e = hash31(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash31(i + vec3(1.0, 0.0, 1.0));
	float g = hash31(i + vec3(0.0, 1.0, 1.0));
	float h = hash31(i + vec3(1.0, 1.0, 1.0));

	float mix_a = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	float mix_b = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
	return mix(mix_a, mix_b, f.z);
}

// FBM for energy core
float energy_fbm(vec3 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		val += amp * value_noise_3d(p);
		p *= 2.1;
		amp *= 0.5;
	}
	return val;
}

void fragment() {
	// ── Base pulse ──
	float pulse = sin(TIME * pulse_speed) * 0.15 + 0.85;
	float fast_pulse = sin(TIME * pulse_speed * 3.0) * 0.08 + 0.92;
	float power_boost = 0.4 + territory_power * 1.6;

	// ── Edge proximity (wireframe thickness via UV derivative) ──
	// For ImmediateMesh lines, the geometry is already wireframe.
	// This shader enhances the visual glow of those lines.

	// ── Inner energy core: animated 3D noise ──
	// Sample in object space — the vertex positions from the ImmediateMesh
	vec3 energy_pos = VERTEX * 0.3 + vec3(TIME * 0.2, TIME * -0.15, TIME * 0.1);
	float energy = energy_fbm(energy_pos);
	float energy2 = energy_fbm(energy_pos * 1.5 + vec3(3.7, 1.2, 2.8));
	// Combine into turbulent pattern
	float core_energy = smoothstep(0.3, 0.7, energy) * smoothstep(0.25, 0.65, energy2);
	core_energy *= 0.6 + territory_power * 0.8;

	// ── Chromatic aberration on edges ──
	// Shift color channels slightly based on view angle
	float view_dot = abs(dot(normalize(VERTEX), VIEW));
	float chroma_shift = (1.0 - view_dot) * 0.3;

	vec3 color_r = accent_color + vec3(chroma_shift, -chroma_shift * 0.5, -chroma_shift);
	vec3 color_b = accent_color + vec3(-chroma_shift, -chroma_shift * 0.5, chroma_shift);
	vec3 chroma_color = mix(color_r, color_b, smoothstep(0.3, 0.7, view_dot));

	// ── Depth-based glow thickness ──
	// Lines closer to camera are brighter (perspective emphasis)
	float depth_factor = 1.0 / (1.0 + length(VERTEX) * 0.05);

	// ── Traveling energy wave along edges ──
	float edge_wave = sin(length(VERTEX) * 4.0 - TIME * 2.5) * 0.5 + 0.5;
	edge_wave = smoothstep(0.3, 0.8, edge_wave);

	// ── Final composition ──
	vec3 line_color = chroma_color * power_boost * pulse;
	vec3 core_color = accent_color * core_energy * 0.8 * fast_pulse;
	vec3 wave_color = accent_color * edge_wave * 0.4 * territory_power;

	ALBEDO = (line_color + core_color + wave_color) * depth_factor;

	// Alpha: base visibility + power + core energy
	float base_alpha = 0.35 + territory_power * 0.45;
	float core_alpha = core_energy * 0.3;
	float wave_alpha = edge_wave * 0.15 * territory_power;
	ALPHA = (base_alpha + core_alpha + wave_alpha) * pulse;
}
