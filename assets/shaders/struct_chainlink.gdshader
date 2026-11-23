shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, shadows_disabled;

// Galvanised chain-link mesh. UV in metres (u along the fence, v up). Wires are
// anti-aliased with fwidth and fade to a flat semi-transparent sheen at distance,
// so the fence never shimmers.

uniform vec3 wire_color : source_color = vec3(0.55, 0.57, 0.58);
uniform float cell = 0.1;
uniform float wire = 0.1;   // fraction of the cell
uniform float far_alpha = 0.32;

void fragment() {
	vec2 uv = UV / cell;
	vec2 r = vec2(uv.x + uv.y, uv.x - uv.y) * 0.7071;
	vec2 f = abs(fract(r) - 0.5);
	float d = 0.5 - max(f.x, f.y);           // distance to nearest wire (cell units)
	float w = fwidth(d) * 1.5;
	float a = 1.0 - smoothstep(wire * 0.5 - w, wire * 0.5 + w, d);
	float far = clamp((fwidth(uv.x) - 0.25) * 2.0, 0.0, 1.0);
	a = mix(a, far_alpha, far);
	ALBEDO = wire_color * (0.85 + 0.15 * sin(UV.x * 0.7));
	METALLIC = 0.8;
	ROUGHNESS = 0.45;
	ALPHA = a;
}
