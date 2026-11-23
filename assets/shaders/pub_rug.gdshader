shader_type spatial;

// Woven rug: bordered kilim pattern with worn fibres. Colors come from the pub palette.
uniform vec3 base_color : source_color = vec3(0.35, 0.08, 0.06);
uniform vec3 pattern_color : source_color = vec3(0.85, 0.6, 0.25);
uniform vec3 border_color : source_color = vec3(0.08, 0.09, 0.15);
uniform vec2 size_m = vec2(2.6, 3.2);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 m = UV * size_m;                       // metres
	vec2 e = min(m, size_m - m);                // distance to edge
	float edge = min(e.x, e.y);
	vec3 col = base_color;
	// Borders
	float b1 = step(edge, 0.22);
	float b2 = step(0.26, edge) * step(edge, 0.3);
	// Diamond medallions in the field
	vec2 q = (m - size_m * 0.5);
	vec2 cellp = fract(q / 0.55) - 0.5;
	float diamond = step(abs(cellp.x) + abs(cellp.y), 0.32) - step(abs(cellp.x) + abs(cellp.y), 0.2);
	float centre = step(abs(q.x) * 0.9 + abs(q.y) * 0.7, 0.55) - step(abs(q.x) * 0.9 + abs(q.y) * 0.7, 0.42);
	col = mix(col, pattern_color, clamp(diamond * 0.7 + centre, 0.0, 1.0) * step(0.32, edge));
	col = mix(col, border_color, b1);
	col = mix(col, pattern_color, b2);
	// Zig-zag in the outer border
	float zz = step(abs(fract(max(m.x, m.y) * 4.0 + edge * 4.0) - 0.5), 0.12) * step(0.05, edge) * b1;
	col = mix(col, pattern_color * 0.8, zz);
	// Fibre + wear
	float fib = noise(m * vec2(180.0, 30.0)) * 0.25 + noise(m * 6.0) * 0.25;
	col *= 0.75 + fib;
	float wear = smoothstep(0.6, 0.0, length(q / size_m)) * 0.15;
	col = mix(col, col * 1.2 + 0.03, wear);
	ALBEDO = col;
	ROUGHNESS = 0.97;
	// Fringe tassels at the short ends
	if (e.y < 0.04) {
		ALBEDO = vec3(0.75, 0.7, 0.6) * (0.6 + 0.4 * step(0.5, fract(m.x * 40.0)));
	}
}
