shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Vertical beam shader for monument beacon pillar.
// Thin translucent column that fades at top and bottom.

uniform vec3 accent_color : source_color = vec3(0.5, 0.7, 1.0);
uniform float beam_opacity : hint_range(0.0, 0.3) = 0.06;
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Normalized vertical position (0 = bottom, 1 = top)
	float v = UV.y;

	// Fade at top and bottom
	float fade_bottom = smoothstep(0.0, 0.08, v);
	float fade_top = smoothstep(1.0, 0.85, v);
	float fade = fade_bottom * fade_top;

	// Subtle vertical scroll animation
	float scroll = sin(v * 20.0 - TIME * 1.5) * 0.5 + 0.5;
	scroll = mix(0.7, 1.0, scroll);

	// Power boost
	float power_boost = 1.0 + territory_power * 2.0;

	// Final color
	ALBEDO = accent_color * scroll * power_boost;
	ALPHA = beam_opacity * fade * scroll;
}
