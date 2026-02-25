shader_type canvas_item;

// Helmet visor HUD overlay — bezel vignette, compass strip, O2/health bars, breathing pulse
uniform float heading : hint_range(0.0, 360.0) = 0.0;
uniform float health : hint_range(0.0, 1.0) = 1.0;
uniform float oxygen : hint_range(0.0, 1.0) = 1.0;
uniform float time_elapsed : hint_range(0.0, 99999.0) = 0.0;
uniform float enabled : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	if (enabled < 0.5) {
		COLOR = vec4(0.0);
		return;
	}

	vec2 uv = UV;
	vec2 center = uv - 0.5;
	float dist = length(center);
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	// ── Visor bezel vignette (rounded rectangle darkening at edges) ──
	vec2 abs_c = abs(center);
	// Soft rounded rect distance
	float rx = smoothstep(0.38, 0.50, abs_c.x);
	float ry = smoothstep(0.32, 0.48, abs_c.y);
	float bezel = max(rx, ry);
	// Corner rounding
	float corner = smoothstep(0.45, 0.55, length(max(abs_c - vec2(0.35, 0.30), 0.0)));
	bezel = max(bezel, corner);

	// Breathing pulse — subtle scale oscillation
	float breath = 1.0 + sin(time_elapsed * 1.57) * 0.003; // Very subtle
	bezel *= breath;

	// Base visor tint (very dark, semi-transparent edges)
	vec4 visor_color = vec4(0.0, 0.0, 0.0, bezel * 0.85);

	// ── Compass strip at top ──
	float compass_alpha = 0.0;
	if (uv.y < 0.06 && uv.y > 0.02 && uv.x > 0.25 && uv.x < 0.75) {
		float strip_x = (uv.x - 0.25) / 0.50; // 0..1 across strip
		float compass_pos = mod(heading / 360.0 + strip_x - 0.5, 1.0);

		// Tick marks every 45 degrees
		float tick_angle = compass_pos * 360.0;
		float nearest_45 = mod(tick_angle, 45.0);
		float tick = 1.0 - smoothstep(0.0, 3.0, min(nearest_45, 45.0 - nearest_45));

		// Cardinal labels — brighter at N/S/E/W
		float nearest_90 = mod(tick_angle, 90.0);
		float cardinal = 1.0 - smoothstep(0.0, 5.0, min(nearest_90, 90.0 - nearest_90));

		// Center indicator line
		float center_line = 1.0 - smoothstep(0.0, 0.005, abs(strip_x - 0.5));

		// Fade at edges of strip
		float strip_fade = smoothstep(0.0, 0.08, strip_x) * smoothstep(1.0, 0.92, strip_x);

		float brightness = (tick * 0.3 + cardinal * 0.5 + center_line * 0.8) * strip_fade;
		compass_alpha = brightness * 0.6;
		visor_color.rgb += vec3(0.4, 0.6, 0.9) * compass_alpha;
	}

	// ── Health bar (bottom-left) ──
	if (uv.y > 0.92 && uv.y < 0.96 && uv.x > 0.05 && uv.x < 0.25) {
		float bar_x = (uv.x - 0.05) / 0.20;
		float bar_y = (uv.y - 0.92) / 0.04;

		// Bar background
		float bar_bg = 0.15;
		// Filled portion
		float filled = step(bar_x, health);
		// Color: green→yellow→red
		vec3 bar_color = mix(vec3(0.9, 0.2, 0.1), vec3(0.2, 0.9, 0.3), health);
		bar_color = mix(bar_color, vec3(0.9, 0.8, 0.1), step(0.3, health) * step(health, 0.6));

		float bar_alpha = max(bar_bg, filled * 0.5);
		vec3 final_bar = mix(vec3(0.1), bar_color, filled);
		visor_color.rgb += final_bar * bar_alpha;
		visor_color.a = max(visor_color.a, bar_alpha);
	}

	// ── O2 bar (bottom-right) ──
	if (uv.y > 0.92 && uv.y < 0.96 && uv.x > 0.75 && uv.x < 0.95) {
		float bar_x = (uv.x - 0.75) / 0.20;
		float bar_y = (uv.y - 0.92) / 0.04;

		float bar_bg = 0.15;
		float filled = step(bar_x, oxygen);
		vec3 bar_color = vec3(0.3, 0.6, 0.95); // Cyan/blue for O2

		float bar_alpha = max(bar_bg, filled * 0.5);
		vec3 final_bar = mix(vec3(0.1), bar_color, filled);
		visor_color.rgb += final_bar * bar_alpha;
		visor_color.a = max(visor_color.a, bar_alpha);
	}

	// ── Scanline overlay (very subtle) ──
	float scanline = sin(uv.y / SCREEN_PIXEL_SIZE.y * 0.5) * 0.5 + 0.5;
	visor_color.a += scanline * 0.02;

	COLOR = visor_color;
}
