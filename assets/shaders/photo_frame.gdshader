shader_type canvas_item;
// Photo mode frame overlays.
// 0=None, 1=FilmStrip, 2=Polaroid, 3=EVA Helmet
// Renders decorative borders/frames around the viewport.

uniform int frame_mode : hint_range(0, 3) = 0;

void fragment() {
	vec2 uv = UV;
	vec4 col = vec4(0.0, 0.0, 0.0, 0.0);

	if (frame_mode == 1) {
		// Film Strip — black bars top/bottom with sprocket holes
		float bar_height = 0.08;
		if (uv.y < bar_height || uv.y > 1.0 - bar_height) {
			col = vec4(0.02, 0.02, 0.02, 0.95);
			// Sprocket holes
			float hole_spacing = 0.08;
			float hole_x = mod(uv.x, hole_spacing);
			float hole_cx = hole_spacing * 0.5;
			float hole_dist = length(vec2(hole_x - hole_cx, 0.0));
			if (hole_dist < 0.012) {
				col = vec4(0.0, 0.0, 0.0, 0.0);  // Transparent holes
			}
		}
		// Film grain border lines
		if (abs(uv.y - bar_height) < 0.002 || abs(uv.y - (1.0 - bar_height)) < 0.002) {
			col = vec4(0.6, 0.55, 0.45, 0.8);
		}
	} else if (frame_mode == 2) {
		// Polaroid — thick white border at bottom, thin on sides/top
		float border_side = 0.04;
		float border_top = 0.04;
		float border_bottom = 0.15;  // Thick Polaroid bottom strip
		if (uv.x < border_side || uv.x > 1.0 - border_side ||
			uv.y < border_top || uv.y > 1.0 - border_bottom) {
			col = vec4(0.95, 0.93, 0.90, 0.95);  // Off-white
		}
		// Inner shadow line
		if ((uv.x > border_side - 0.003 && uv.x < border_side + 0.003) ||
			(uv.x > 1.0 - border_side - 0.003 && uv.x < 1.0 - border_side + 0.003) ||
			(uv.y > border_top - 0.003 && uv.y < border_top + 0.003) ||
			(uv.y > 1.0 - border_bottom - 0.003 && uv.y < 1.0 - border_bottom + 0.003)) {
			col = vec4(0.7, 0.68, 0.65, 0.5);
		}
	} else if (frame_mode == 3) {
		// EVA Helmet — curved visor overlay with HUD markings
		vec2 center = uv - vec2(0.5);
		float dist = length(center);
		// Visor edge curve (elliptical)
		float edge_dist = length(center * vec2(1.0, 1.3));
		float edge = smoothstep(0.58, 0.65, edge_dist);
		if (edge > 0.01) {
			col = vec4(0.08, 0.08, 0.12, edge * 0.9);
		}
		// Inner reflection streak (curved highlight on visor glass)
		float reflect_angle = atan(center.y, center.x);
		float reflect_dist = length(center * vec2(0.9, 1.1));
		if (reflect_dist > 0.3 && reflect_dist < 0.45 &&
			reflect_angle > 0.3 && reflect_angle < 1.2) {
			float reflect_alpha = (1.0 - abs(reflect_dist - 0.375) / 0.075) * 0.08;
			col = vec4(0.6, 0.7, 0.9, reflect_alpha);
		}
		// Corner bracket HUD markers
		float bracket_size = 0.12;
		float bracket_width = 0.003;
		// Top-left bracket
		if ((uv.x < bracket_size && abs(uv.y - 0.08) < bracket_width) ||
			(uv.y < 0.08 + bracket_size && abs(uv.x - 0.03) < bracket_width && uv.y > 0.08)) {
			col = vec4(0.3, 0.8, 0.4, 0.5);
		}
		// Top-right bracket
		if ((uv.x > 1.0 - bracket_size && abs(uv.y - 0.08) < bracket_width) ||
			(uv.y < 0.08 + bracket_size && abs(uv.x - 0.97) < bracket_width && uv.y > 0.08)) {
			col = vec4(0.3, 0.8, 0.4, 0.5);
		}
		// Bottom-left bracket
		if ((uv.x < bracket_size && abs(uv.y - 0.92) < bracket_width) ||
			(uv.y > 0.92 - bracket_size && abs(uv.x - 0.03) < bracket_width && uv.y < 0.92)) {
			col = vec4(0.3, 0.8, 0.4, 0.5);
		}
		// Bottom-right bracket
		if ((uv.x > 1.0 - bracket_size && abs(uv.y - 0.92) < bracket_width) ||
			(uv.y > 0.92 - bracket_size && abs(uv.x - 0.97) < bracket_width && uv.y < 0.92)) {
			col = vec4(0.3, 0.8, 0.4, 0.5);
		}
	}

	COLOR = col;
}
