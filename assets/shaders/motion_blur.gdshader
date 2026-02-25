shader_type canvas_item;

// Directional motion blur — samples along velocity vector
uniform vec2 velocity_uv = vec2(0.0, 0.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	if (intensity < 0.01) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
		return;
	}

	vec2 blur_dir = velocity_uv * intensity * 0.02;

	// 5-tap directional blur
	vec4 color = vec4(0.0);
	color += texture(screen_texture, SCREEN_UV - blur_dir * 2.0) * 0.10;
	color += texture(screen_texture, SCREEN_UV - blur_dir * 1.0) * 0.20;
	color += texture(screen_texture, SCREEN_UV)                   * 0.40;
	color += texture(screen_texture, SCREEN_UV + blur_dir * 1.0) * 0.20;
	color += texture(screen_texture, SCREEN_UV + blur_dir * 2.0) * 0.10;

	COLOR = color;
}
