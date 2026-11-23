// The Void's sky: near-black space, a slow violet/ice nebula (fbm noise) and a
// fine star field. Visual only — the Void is the same for everyone.
shader_type sky;

uniform vec3 deep : source_color = vec3(0.004, 0.003, 0.012);
uniform vec3 neb_a : source_color = vec3(0.32, 0.10, 0.55);
uniform vec3 neb_b : source_color = vec3(0.10, 0.45, 0.65);
uniform float drift_speed = 0.004;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
	return n;
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float t = TIME * drift_speed;
	float n = fbm(d * 2.2 + vec3(t, 0.0, -t));
	float n2 = fbm(d * 4.5 - vec3(0.0, t * 2.0, 0.0));
	float neb = smoothstep(0.45, 0.85, n) * 0.55 + smoothstep(0.5, 0.9, n2) * 0.25;
	vec3 col = deep + mix(neb_a, neb_b, smoothstep(0.3, 0.8, n2)) * neb * 0.35;
	// Stars: a hashed cell per direction, a few bright.
	vec3 sp = d * 380.0;
	float h = hash13(floor(sp));
	float star = step(0.9965, h) * (0.4 + 0.6 * hash13(floor(sp) + 7.0));
	col += vec3(star) * 0.9;
	// A faint glow band below: the abyss.
	col += neb_a * 0.06 * smoothstep(0.0, -0.8, d.y);
	COLOR = col;
}
