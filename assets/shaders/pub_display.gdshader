shader_type spatial;
render_mode unshaded;

// Back-wall display screen — scrolling stats with glitch effect
uniform vec3 base_color : source_color = vec3(0.1, 0.15, 0.25);
uniform vec3 text_color : source_color = vec3(0.3, 0.7, 0.9);
uniform float time : hint_range(0.0, 99999.0) = 0.0;
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV;

	// Scrolling horizontal scan line
	float scan_y = fract(time * 0.15);
	float scan = 1.0 - smoothstep(0.0, 0.02, abs(uv.y - scan_y));

	// Horizontal line grid (simulated text rows)
	float row_freq = 12.0;
	float row = step(0.4, fract(uv.y * row_freq));
	float row_scroll = fract(uv.x + time * 0.08 + floor(uv.y * row_freq) * 0.3);

	// Simulated character blocks
	float char_freq = 30.0;
	float char_block = step(0.3, fract(row_scroll * char_freq));
	float text_brightness = row * char_block * 0.6;

	// Territory power indicator bar at bottom
	float power_bar = 0.0;
	if (uv.y > 0.90) {
		float bar_fill = step(uv.x, territory_power);
		power_bar = bar_fill * 0.8;
	}

	// Glitch effect (periodic horizontal shift)
	float glitch_seed = sin(time * 73.1) * cos(time * 41.3);
	float glitch = 0.0;
	if (glitch_seed > 0.92) {
		float shift = sin(uv.y * 50.0 + time * 100.0) * 0.1;
		glitch = step(0.5, fract(uv.x + shift)) * 0.3;
	}

	vec3 color = base_color;
	color += text_color * text_brightness;
	color += text_color * scan * 0.3;
	color += vec3(0.2, 0.8, 0.4) * power_bar;
	color += vec3(0.5, 0.8, 1.0) * glitch;

	// CRT-like vignette
	float vignette = 1.0 - length(uv - 0.5) * 0.6;
	color *= vignette;

	ALBEDO = color;
	EMISSION = color * 0.5;
}
