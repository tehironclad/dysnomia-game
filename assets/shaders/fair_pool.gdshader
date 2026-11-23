shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;
// Fake pool of light on the ground under lamps/stalls (MultiMesh quads, instance color).
// Cheap stand-in for dozens of real lights; `energy` fades to 0 by day.

uniform float energy = 1.0;

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float f = clamp(1.0 - r, 0.0, 1.0);
	f = f * f * (0.6 + 0.4 * f);
	ALBEDO = COLOR.rgb * f * energy;
}
