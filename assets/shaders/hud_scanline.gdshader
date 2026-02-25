shader_type canvas_item;

// Subtle holographic scanline overlay for HUD panels.
// Creates moving horizontal lines and a slight noise texture
// that gives panels an EVA suit display aesthetic.

uniform float scanline_spacing : hint_range(1.0, 10.0) = 4.0;
uniform float scanline_alpha : hint_range(0.0, 0.3) = 0.04;
uniform float noise_alpha : hint_range(0.0, 0.2) = 0.02;
uniform float scroll_speed : hint_range(0.0, 50.0) = 8.0;
uniform vec4 tint_color : source_color = vec4(0.3, 0.8, 1.0, 0.05);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float pixel_y = uv.y * 1080.0; // Approximate screen height

	// Scrolling scanlines
	float scanline = step(0.5, fract((pixel_y + TIME * scroll_speed) / scanline_spacing));
	float line_alpha = scanline * scanline_alpha;

	// Static noise grain
	float noise_val = hash(uv * 500.0 + TIME * 0.1);
	float grain = noise_val * noise_alpha;

	// Combine: scanlines + noise + tint
	COLOR = vec4(tint_color.rgb, line_alpha + grain + tint_color.a);
}
