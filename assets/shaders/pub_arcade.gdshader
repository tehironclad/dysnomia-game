shader_type spatial;
render_mode unshaded, cull_back;

// Holo-arcade attract screen: parallax starfield, marching invader rows, scanlines.
uniform vec3 tint : source_color = vec3(0.3, 1.0, 0.6);
uniform float energy = 1.8;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 45758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col = vec3(0.0, 0.01, 0.03);
	// Stars
	for (int l = 1; l < 4; l++) {
		float fl = float(l);
		vec2 g = uv * vec2(18.0, 24.0) * fl;
		g.y += t * fl * 1.5;
		vec2 id = floor(g);
		float s = step(0.93, hash(id + fl)) * smoothstep(0.25, 0.0, length(fract(g) - 0.5));
		col += s * vec3(0.7, 0.8, 1.0) / fl;
	}
	// Invader grid
	vec2 iv = uv * vec2(8.0, 10.0) + vec2(sin(t * 0.8) * 0.8, 0.0);
	vec2 cell = fract(iv);
	vec2 cid = floor(iv);
	if (cid.y >= 1.0 && cid.y <= 3.0) {
		vec2 px = floor(cell * 6.0);
		float body = step(1.0, px.x) * step(px.x, 4.0) * step(1.0, px.y) * step(px.y, 3.0);
		float legs = step(4.0, px.y) * (step(abs(px.x - 1.0), 0.1) + step(abs(px.x - 4.0), 0.1));
		float eyes = step(2.0, px.y) * step(px.y, 2.0) * (step(abs(px.x - 2.0), 0.1) + step(abs(px.x - 3.0), 0.1));
		float frame = step(0.5, fract(t * 1.2));
		col += (body - eyes + legs * frame) * mix(tint, vec3(1.0, 0.3, 0.6), cid.y / 4.0) * 1.2;
	}
	// Player ship and shot
	float ship_x = 0.5 + 0.3 * sin(t * 1.3);
	col += smoothstep(0.04, 0.02, length((uv - vec2(ship_x, 0.9)) * vec2(1.0, 2.0))) * tint * 1.5;
	float shot_y = 0.85 - fract(t * 0.9) * 0.7;
	col += smoothstep(0.006, 0.0, abs(uv.x - ship_x)) * step(abs(uv.y - shot_y), 0.03) * vec3(1.0, 1.0, 0.6) * 2.0;
	// Scanlines + vignette
	col *= 0.75 + 0.25 * sin(uv.y * 600.0);
	col *= 1.0 - 0.5 * length(uv - 0.5);
	ALBEDO = col * energy;
	EMISSION = col * energy;
}
