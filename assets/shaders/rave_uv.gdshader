shader_type spatial;
// Blacklight paint on the arcade's walls and ceiling (RaveHall): near-black surfaces carrying
// fluorescent patterns that glow under UV, breathing with the beat, and the mirror ball's spots
// sweeping over them. The pattern and the palette come from the territory (RaveStyle).

uniform vec3 c1 : source_color = vec3(0.3, 0.9, 1.0);
uniform vec3 c2 : source_color = vec3(1.0, 0.3, 0.8);
uniform vec3 c3 : source_color = vec3(1.0, 0.85, 0.3);
uniform vec3 base : source_color = vec3(0.02, 0.012, 0.035);
uniform float beats = 0.0;
uniform float energy = 1.0;
uniform int pattern = 0;  // 0 stripes, 1 splatter, 2 hypobar, 3 circuit
uniform float glow = 1.0;
uniform vec3 ball = vec3(0.0, 4.4, -2.0);  // the mirror ball
uniform float ball_turn = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 pick(float h) {
	return h < 0.34 ? c1 : (h < 0.67 ? c2 : c3);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// The surface's own 2D coordinates: walls use (along, up), the ceiling (x, z).
	vec3 n = abs(wnorm);
	vec2 p = n.y > 0.5 ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
	float b = floor(beats);
	float ph = fract(beats);
	float kick = exp(-ph * 4.0);
	vec3 em = vec3(0.0);
	if (pattern == 0) {
		float s = fract((p.x + p.y) * 0.45);
		float band = smoothstep(0.06, 0.0, abs(s - 0.5) - 0.04);
		em = pick(hash2(vec2(floor((p.x + p.y) * 0.45), 1.0))) * band;
	} else if (pattern == 1) {
		vec2 cell = floor(p * 1.3);
		vec2 f = fract(p * 1.3) - 0.5 + (vec2(hash2(cell), hash2(cell + 3.0)) - 0.5) * 0.5;
		float r = 0.12 + 0.22 * hash2(cell + 9.0);
		float blob = smoothstep(r, r - 0.04, length(f)) * step(0.45, hash2(cell + 1.0));
		em = pick(hash2(cell + 5.0)) * blob;
	} else if (pattern == 2) {
		// Hypobar columns: an equaliser of bars, each its own height, jumping on the beat.
		float col = floor(p.x * 1.6);
		float f = fract(p.x * 1.6);
		float h = 0.6 + 2.6 * hash2(vec2(col, b)) * (0.5 + 0.5 * energy);
		float bar = step(0.15, f) * step(f, 0.85) * step(p.y, h) * step(0.15, p.y);
		float cap = smoothstep(0.08, 0.0, abs(p.y - h)) * step(0.15, f) * step(f, 0.85);
		em = mix(c1, c2, clamp(p.y / 3.5, 0.0, 1.0)) * bar * 0.55 + c3 * cap * 1.5;
	} else {
		vec2 g = abs(fract(p * 0.8) - 0.5);
		float trace = smoothstep(0.02, 0.0, min(g.x, g.y)) * step(0.5, hash2(floor(p * 0.8)));
		vec2 nodes = fract(p * 0.8) - 0.5;
		float node = smoothstep(0.09, 0.05, length(nodes)) * step(0.6, hash2(floor(p * 0.8) + 2.0));
		float pulse = step(0.5, fract(hash2(floor(p * 0.8)) + beats * 0.25));
		em = c1 * trace * (0.4 + 0.6 * pulse) + c2 * node * 1.5;
	}
	em *= glow * (0.5 + 0.35 * energy + 0.45 * kick * energy);
	// Mirror-ball spots: a grid of light on the sphere of directions round the ball, turning.
	vec3 d = normalize(wpos - ball);
	float az = atan(d.z, d.x) + ball_turn;
	float el = asin(clamp(d.y, -1.0, 1.0));
	vec2 sg = vec2(az * 17.0, el * 17.0);
	vec2 sf = fract(sg) - 0.5;
	float spot = smoothstep(0.15, 0.06, length(sf)) * step(0.7, hash2(floor(sg)));
	spot *= (1.0 - smoothstep(0.15, 0.55, d.y)) * (n.y > 0.5 ? 0.35 : 1.0);  // mostly on the walls
	em += mix(vec3(1.0), pick(hash2(floor(sg) + 4.0)), 0.5) * spot * 0.75 * energy;
	ALBEDO = base;
	ROUGHNESS = 0.8;
	EMISSION = em;
}
