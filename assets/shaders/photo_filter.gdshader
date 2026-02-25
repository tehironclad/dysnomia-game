shader_type canvas_item;
// Photo mode color filters.
// 7 filter modes selected via uniform int:
// 0=None, 1=Sepia, 2=HighContrast, 3=Cool, 4=Warm, 5=Noir, 6=Infrared
// Also includes vignette effect.

uniform int filter_mode : hint_range(0, 6) = 0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;

	// Apply filter based on mode
	if (filter_mode == 1) {
		// Sepia — warm vintage tones
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		col = vec3(
			grey * 1.2 + 0.05,
			grey * 0.95 + 0.02,
			grey * 0.7
		);
	} else if (filter_mode == 2) {
		// High Contrast — boosted saturation and contrast
		col = (col - 0.5) * 1.6 + 0.5;
		float sat = 1.4;
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(grey), col, sat);
		col = clamp(col, 0.0, 1.0);
	} else if (filter_mode == 3) {
		// Cool — blue tint
		col.r *= 0.85;
		col.g *= 0.92;
		col.b = col.b * 1.15 + 0.03;
		col = clamp(col, 0.0, 1.0);
	} else if (filter_mode == 4) {
		// Warm — orange/golden tint
		col.r = col.r * 1.12 + 0.03;
		col.g *= 1.02;
		col.b *= 0.82;
		col = clamp(col, 0.0, 1.0);
	} else if (filter_mode == 5) {
		// Noir — desaturated with crushed blacks and bright highlights
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		grey = (grey - 0.3) * 1.5 + 0.3;  // Crush blacks
		grey = clamp(grey, 0.0, 1.0);
		col = vec3(grey);
	} else if (filter_mode == 6) {
		// Infrared — inverted luminance with false color
		float grey = dot(col, vec3(0.299, 0.587, 0.114));
		float inv = 1.0 - grey;
		col = vec3(
			inv * 0.8 + col.r * 0.3,
			inv * 0.2 + col.g * 0.1,
			grey * 0.6 + col.b * 0.4
		);
		col = clamp(col, 0.0, 1.0);
	}

	// Vignette — darkens edges of screen
	if (vignette_strength > 0.01) {
		vec2 center = SCREEN_UV - vec2(0.5);
		float dist = length(center) * 2.0;
		float vig = 1.0 - smoothstep(0.4, 1.4, dist) * vignette_strength;
		col *= vig;
	}

	COLOR = vec4(col, 1.0);
}
