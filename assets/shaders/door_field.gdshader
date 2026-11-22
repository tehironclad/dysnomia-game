// The Room's door: a thin field across the opening. Closed = visible lattice
// (admission needed: a cover charge is set); open = fades away. UV-space, so
// it never slides with the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec3 color : source_color = vec3(0.66, 0.9, 1.0);
uniform float closed = 1.0;   // 1 closed … 0 open

void fragment() {
	vec2 uv = UV * vec2(6.0, 4.0);
	vec2 g = abs(fract(uv + vec2(0.0, TIME * 0.05)) - 0.5);
	float line = smoothstep(0.47, 0.5, max(g.x, g.y));
	float edge = smoothstep(0.42, 0.5, abs(UV.x - 0.5)) + smoothstep(0.42, 0.5, abs(UV.y - 0.5));
	float shimmer = 0.5 + 0.5 * sin(TIME * 1.7 + UV.y * 9.0);
	float a = (line * 0.55 + 0.06 + edge * 0.4) * (0.75 + 0.25 * shimmer) * closed;
	ALBEDO = color * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
