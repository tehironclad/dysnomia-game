shader_type canvas_item;

// Circular mask with soft edge and optional border glow
uniform vec4 border_color : source_color = vec4(0.4, 0.3, 0.7, 0.6);
uniform float border_width : hint_range(0.0, 0.05) = 0.02;

void fragment() {
	vec2 center = UV - 0.5;
	float dist = length(center) * 2.0; // 0 at center, 1 at edge

	// Circular mask
	float alpha = 1.0 - smoothstep(0.92, 1.0, dist);

	// Border ring
	float border = smoothstep(0.88, 0.90, dist) * (1.0 - smoothstep(0.95, 1.0, dist));

	vec4 col = texture(TEXTURE, UV);
	col.a *= alpha;
	col.rgb = mix(col.rgb, border_color.rgb, border * border_color.a);

	COLOR = col;
}
