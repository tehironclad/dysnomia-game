shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Ground circle shader for monument base.
// Procedural concentric rings with rotating radial lines.

uniform vec3 accent_color : source_color = vec3(0.5, 0.7, 1.0);
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform float circle_radius : hint_range(1.0, 10.0) = 5.0;

void fragment() {
	// UV centered at (0.5, 0.5), remap to (-1, 1)
	vec2 uv = (UV - 0.5) * 2.0;
	float dist = length(uv);

	// Discard outside unit circle
	if (dist > 1.0) {
		discard;
	}

	// Concentric rings (4 rings)
	float rings = sin(dist * 4.0 * 3.14159 * 2.0) * 0.5 + 0.5;
	rings = smoothstep(0.4, 0.6, rings);

	// Radial lines (12 lines, slowly rotating)
	float angle = atan(uv.y, uv.x);
	float rotation = TIME * 0.15;
	float radial = sin((angle + rotation) * 12.0) * 0.5 + 0.5;
	radial = smoothstep(0.6, 0.8, radial);

	// Combine rings and radials
	float pattern = max(rings * 0.6, radial * 0.4);

	// Edge fade — smooth falloff near outer edge
	float edge_fade = smoothstep(1.0, 0.7, dist);

	// Center fade — slightly dimmer at very center
	float center_fade = smoothstep(0.0, 0.15, dist);

	// Power boost
	float power_factor = 0.3 + territory_power * 0.7;

	// Final
	float alpha = pattern * edge_fade * center_fade * power_factor * 0.25;
	ALBEDO = accent_color;
	ALPHA = alpha;
}
