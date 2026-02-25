shader_type spatial;
render_mode unshaded, cull_disabled;

// Neon sign — pulsing emission with flicker effect
uniform vec3 sign_color : source_color = vec3(0.8, 0.3, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 2.5;
uniform float time : hint_range(0.0, 99999.0) = 0.0;

void fragment() {
	// Base glow
	float glow = intensity;

	// Gentle pulse
	glow *= 0.85 + 0.15 * sin(time * 2.5);

	// Occasional flicker
	float flicker_seed = sin(time * 47.3) * sin(time * 31.7);
	if (flicker_seed > 0.95) {
		glow *= 0.3; // Brief dim
	}

	ALBEDO = sign_color * glow;
	EMISSION = sign_color * glow;
}
