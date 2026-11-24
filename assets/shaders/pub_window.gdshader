shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

// Side window pane: dark, reflective night glass with a faint starfield and horizon hint,
// a touch of frost at the edges, and only a low cyan glow — never a white panel.
uniform vec3 glass_tint : source_color = vec3(0.03, 0.05, 0.08);
uniform vec3 glow_tint : source_color = vec3(0.2, 0.8, 1.0);
uniform float glow = 0.05;
uniform vec2 size_m = vec2(1.5, 1.45);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 m = UV * size_m;
	vec3 col = glass_tint;
	// Horizon hint: slightly lighter band low in the pane
	col += vec3(0.04, 0.05, 0.07) * smoothstep(0.55, 0.95, UV.y) * (1.0 - smoothstep(0.95, 1.0, UV.y));
	// Sparse stars in the upper pane
	vec2 g = m * 38.0;
	vec2 id = floor(g);
	float st = step(0.965, hash(id)) * smoothstep(0.35, 0.0, length(fract(g) - 0.5));
	st *= 1.0 - smoothstep(0.35, 0.7, UV.y);
	// Frost creeping in from the frame
	vec2 e = min(UV, 1.0 - UV);
	float frost = (1.0 - smoothstep(0.0, 0.09, min(e.x, e.y))) * (0.6 + 0.4 * hash(floor(m * 90.0)));
	ALBEDO = col + frost * 0.05;
	ROUGHNESS = mix(0.06, 0.5, frost);
	METALLIC = 0.4;
	SPECULAR = 0.9;
	ALPHA = 0.9;
	EMISSION = glow_tint * glow + vec3(0.8, 0.9, 1.0) * st * 0.9 + glow_tint * frost * 0.03;
}
