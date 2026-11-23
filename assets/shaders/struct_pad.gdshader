shader_type spatial;

// Spaceport ground surfaces. Concrete PBR (Poly Haven brushed_concrete) with painted markings,
// all procedural in local XZ metres so nothing is a separate decal (no z-fighting).
// mode 0: landing pad (touchdown ring, target, pad number, blast scorch, gear skid marks)
// mode 1: apron slab (expansion joints, taxi line, hazard border, oil stains)
// mode 2: plaza slab (joints, hazard border, stains — no taxi markings)

uniform int mode = 0;
uniform sampler2D concrete_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.35;
uniform float pad_radius = 8.0;
uniform vec2 half_size = vec2(17.0, 11.0);
uniform int pad_number = 7;
uniform vec3 paint_yellow : source_color = vec3(0.95, 0.66, 0.06);
uniform vec3 paint_white : source_color = vec3(0.88, 0.88, 0.85);
uniform vec3 accent : source_color = vec3(0.2, 0.8, 1.0);
uniform float accent_glow = 0.6;
uniform float seed = 0.0;

varying vec3 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2; }
float band(float x, float a, float b, float aa) { return smoothstep(a - aa, a, x) * (1.0 - smoothstep(b, b + aa, x)); }
float box2(vec2 p, vec2 c, vec2 h) { vec2 d = abs(p - c) - h; return step(max(d.x, d.y), 0.0); }

float seg7(vec2 p, int d) {
	// p in a 1 x 1.8 cell. Segments: a top, b top-right, c bottom-right, d bottom, e bottom-left, f top-left, g middle.
	int m[10] = int[10](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);
	int bits = m[clamp(d, 0, 9)];
	float t = 0.16;
	float r = 0.0;
	if ((bits & 1) != 0) r += box2(p, vec2(0.5, 1.7), vec2(0.4, t * 0.5));
	if ((bits & 2) != 0) r += box2(p, vec2(0.92, 1.3), vec2(t * 0.5, 0.42));
	if ((bits & 4) != 0) r += box2(p, vec2(0.92, 0.5), vec2(t * 0.5, 0.42));
	if ((bits & 8) != 0) r += box2(p, vec2(0.5, 0.1), vec2(0.4, t * 0.5));
	if ((bits & 16) != 0) r += box2(p, vec2(0.08, 0.5), vec2(t * 0.5, 0.42));
	if ((bits & 32) != 0) r += box2(p, vec2(0.08, 1.3), vec2(t * 0.5, 0.42));
	if ((bits & 64) != 0) r += box2(p, vec2(0.5, 0.9), vec2(0.4, t * 0.5));
	return clamp(r, 0.0, 1.0);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 p = lp.xz;
	vec2 tuv = p * tex_scale;
	vec3 base = texture(concrete_albedo, tuv).rgb * vec3(0.78, 0.77, 0.76);
	vec3 arm = texture(concrete_arm, tuv).rgb;
	NORMAL_MAP = texture(concrete_normal, tuv).rgb;
	float rough = arm.g;
	// Large-scale grime variation so the slab is not uniform
	float grime = fbm(p * 0.15);
	base *= 0.75 + 0.35 * grime;

	float wear = smoothstep(0.35, 0.75, fbm(p * 1.7 + 13.0)); // paint chipping mask
	vec3 paint = vec3(0.0);
	float paint_a = 0.0;
	vec3 emis = vec3(0.0);
	float r = length(p);

	if (mode == 0) {
		float R = pad_radius;
		// Outer yellow safety band + dashed white ring
		float yb = band(r, R - 1.05, R - 0.7, 0.02);
		float ang = atan(p.y, p.x);
		float dash = step(0.5, fract(ang * 24.0 / 6.2831853));
		float wd = band(r, R - 1.5, R - 1.32, 0.02) * dash;
		// Touchdown circle and target cross
		float tc = band(r, 3.3, 3.65, 0.02);
		float cross_ = (box2(p, vec2(0.0), vec2(2.4, 0.12)) + box2(p, vec2(0.0), vec2(0.12, 2.4))) * step(0.9, r);
		float dot_c = band(r, 0.0, 0.45, 0.02);
		// Alignment chevrons at the 4 cardinal points
		float chev = 0.0;
		for (int i = 0; i < 4; i++) {
			if (i == 1) continue; // +Z carries the pad number instead
			float a = float(i) * 1.5707963;
			vec2 q = vec2(cos(a) * p.x + sin(a) * p.y, -sin(a) * p.x + cos(a) * p.y);
			q.x -= 5.4;
			chev += step(abs(abs(q.y) * 0.9 + q.x), 0.18) * step(abs(q.y), 0.75);
		}
		// Pad number near the +Z edge, upright for someone approaching from +Z
		vec2 np = vec2(p.x, 5.0 - p.y) / 0.75 + vec2(1.1, 0.9);
		float num = 0.0;
		if (np.x > 0.0 && np.x < 2.2 && np.y > 0.0 && np.y < 1.8) {
			int d0 = pad_number / 10;
			int d1 = pad_number - d0 * 10;
			num = np.x < 1.0 ? seg7(np, d0) : seg7(np - vec2(1.2, 0.0), d1);
		}
		float yellow = clamp(yb + chev, 0.0, 1.0);
		float white = clamp(wd + tc + cross_ + num, 0.0, 1.0);
		paint = mix(paint_white, paint_yellow, yellow);
		paint_a = clamp(yellow + white, 0.0, 1.0);
		// Accent-lit inlay ring that glows with territory charge
		float inlay = band(r, R - 0.42, R - 0.3, 0.015);
		emis += accent * inlay * accent_glow;
		emis += accent * dot_c * accent_glow * 0.6;
		// Blast scorch: dark radial soot with streaks
		float streak = noise(vec2(ang * 6.0, r * 0.3)) * 0.6 + 0.4;
		float scorch = smoothstep(4.8, 0.5, r) * streak * (0.6 + 0.4 * fbm(p * 0.8));
		base *= 1.0 - scorch * 0.75;
		paint_a *= 1.0 - scorch * 0.6;
		// Gear skid marks (4 rubbery patches at landing-leg radius)
		for (int i = 0; i < 4; i++) {
			float a = 0.785398 + float(i) * 1.5707963;
			vec2 c = vec2(cos(a), sin(a)) * 4.0;
			float sk = smoothstep(0.9, 0.2, length((p - c) * vec2(1.0, 0.6))) * noise(p * 5.0);
			base *= 1.0 - sk * 0.5;
		}
	} else {
		// Expansion joints every 4 m
		vec2 j = abs(fract(p / 4.0 + 0.5) - 0.5) * 4.0;
		float joint = smoothstep(0.04, 0.0, min(j.x, j.y));
		base *= 1.0 - joint * 0.55;
		// Hazard border around the slab
		vec2 e = half_size - abs(p);
		float edge = min(e.x, e.y);
		float hz = band(edge, 0.15, 0.75, 0.02);
		float diag = step(0.5, fract((p.x + p.y) * 0.9));
		// Taxi line: centre line along X out of the pad, ending in a hold-short bar
		float taxi = box2(p, vec2(0.0), vec2(half_size.x - 1.2, 0.1)) * step(pad_radius + 0.4, abs(p.x));
		float hold = box2(vec2(abs(p.x), p.y), vec2(pad_radius + 1.2, 0.0), vec2(0.12, 1.6))
			+ box2(vec2(abs(p.x), p.y), vec2(pad_radius + 1.6, 0.0), vec2(0.06, 1.6));
		// Walkway: white dashed lane to the control hut side
		float walk = box2(p, vec2(0.0, half_size.y - 2.2), vec2(half_size.x - 2.0, 0.05)) * step(0.5, fract(p.x * 0.5));
		if (mode == 2) { taxi = 0.0; hold = 0.0; walk = 0.0; }
		paint = mix(paint_yellow, vec3(0.03), hz * diag);
		paint = mix(paint, paint_white, clamp(walk, 0.0, 1.0));
		paint_a = clamp(hz + taxi + hold + walk, 0.0, 1.0);
		// Oil and fuel stains
		float oil = smoothstep(0.72, 0.85, fbm(p * 0.45 + 7.0));
		base *= 1.0 - oil * 0.45;
		rough = mix(rough, 0.35, oil);
	}
	paint_a *= 1.0 - wear * 0.55;
	vec3 col = mix(base, paint * (0.85 + 0.15 * grime), paint_a);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.6, paint_a);
	METALLIC = 0.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	EMISSION = emis;
}
