shader_type spatial;

// Spacecraft skin for the passenger shuttle: painted panels with recessed seams and
// fastener rows, black heat-shield tiles on downward-facing surfaces, streaky wear and
// soot near the underside. Box-projected in world space (the craft is static).

uniform vec3 base_color : source_color = vec3(0.86, 0.86, 0.84);
uniform float panel = 1.15;       // Panel size (m)
uniform float tiles = 1.0;        // 1 = heat tiles on the underside
uniform float grime = 1.0;

varying vec3 wp;
varying vec3 wn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float seam(vec2 uv, float s, float w) {
	vec2 g = abs(fract(uv / s) - 0.5) * s;
	return 1.0 - smoothstep(0.0, w, min(0.5 * s - g.x, 0.5 * s - g.y));
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wn);
	vec2 uv = an.x > an.y && an.x > an.z ? wp.zy : (an.y > an.z ? wp.xz : wp.xy);
	// Staggered panels: every other row offset by half a panel
	vec2 puv = uv;
	puv.x += step(0.5, fract(puv.y / panel * 0.5)) * panel * 0.5;
	float s = seam(puv, panel, 0.03);
	// Fastener rows just inside the seams
	vec2 f = fract(puv / 0.09);
	float rivet = step(length(f - 0.5), 0.18) * (1.0 - smoothstep(0.0, 0.05, min(abs(fract(puv.x / panel) - 0.03), abs(fract(puv.y / panel) - 0.03))));
	vec2 pid = floor(puv / panel);
	vec3 col = base_color * (0.88 + 0.12 * hash(pid));
	float rough = 0.38 + 0.12 * hash(pid + 3.0);
	float metal = 0.25;
	// Heat-shield tiles where the skin faces down
	float under = smoothstep(-0.15, -0.45, wn.y) * tiles;
	if (under > 0.0) {
		vec2 tuv = uv / 0.22;
		vec2 tid = floor(tuv);
		float tg = seam(uv, 0.22, 0.012);
		vec3 tile = vec3(0.05 + 0.03 * hash(tid)) * (1.0 - tg * 0.6);
		col = mix(col, tile, under);
		rough = mix(rough, 0.85, under);
		metal = mix(metal, 0.0, under);
		s *= 1.0 - under;
	}
	// Streaky wear: vertical streaks + soot creeping up from the belly
	float streak = noise(vec2(uv.x * 3.0, wp.y * 0.35)) * noise(vec2(uv.x * 11.0, wp.y * 0.8));
	float soot = (1.0 - smoothstep(-0.7, 0.4, wn.y)) * noise(uv * 1.3);
	col *= 1.0 - grime * (streak * 0.22 + soot * 0.25);
	col *= 1.0 - s * 0.75 - rivet * 0.35;
	ALBEDO = col;
	ROUGHNESS = rough + s * 0.2;
	METALLIC = metal;
}
