shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Searchlight shaft on a lathed cone (UV.y = 0 at the lamp, 1 at the far end).
// Soft edges from the view angle; fades with distance along the beam.

uniform vec3 beam_color : source_color = vec3(0.75, 0.9, 1.0);
uniform float energy = 0.5;

void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 3.0);
	float along = pow(1.0 - UV.y, 1.8);
	ALBEDO = beam_color * edge * along * energy;
}
