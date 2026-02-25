shader_type canvas_item;

// Chromatic aberration — radial RGB channel offset, triggered by damage/Beat/speed
uniform float strength : hint_range(0.0, 0.05) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	if (strength < 0.0001) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
		return;
	}

	vec2 center = SCREEN_UV - 0.5;
	float dist = length(center);

	// Radial offset — stronger at edges
	vec2 offset_dir = normalize(center + 0.0001) * strength * dist;

	float r = texture(screen_texture, SCREEN_UV + offset_dir).r;
	float g = texture(screen_texture, SCREEN_UV).g;
	float b = texture(screen_texture, SCREEN_UV - offset_dir).b;

	COLOR = vec4(r, g, b, 1.0);
}
