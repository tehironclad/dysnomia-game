// Deep Field sky over a territory. No TIME: the sky only re-renders when a
// uniform changes (the day/night update), not every frame.
// - stars: hashed per direction, seeded from the territory's address;
// - Eris: fixed in the sky (Dysnomia is tidally locked), true angular size,
//   lit by the far sun with a real terminator;
// - the sun: a point (96 AU away it is "just another star"), brightest one;
// - "you are here": the Mandelbrot set drawn faintly across the sky, with this
//   territory's c marked; its Julia set is the ground underfoot.
shader_type sky;


uniform float star_seed = 0.0;
uniform vec3 eris_dir = vec3(0.35, 0.42, -0.84);
uniform float eris_radius_deg = 1.8;          // half of the ~3.6° disc
uniform vec3 eris_color : source_color = vec3(0.72, 0.70, 0.68);
uniform vec2 c = vec2(-0.75, 0.1);            // this territory's parameter
uniform vec3 mark_color : source_color = vec3(0.66, 0.9, 1.0);
uniform vec3 field_dir = vec3(-0.55, 0.62, 0.55);
uniform float field_span_deg = 70.0;          // angular width of the drawn complex plane
uniform float field_strength = 0.18;
uniform vec3 base_color : source_color = vec3(0.0118, 0.0157, 0.0275);  // #030407
// A faint nebula: its colours are the territory's own two Deep Field colours and
// its shape is seeded by the address (star_seed), so every territory's sky differs.
uniform vec3 neb_a : source_color = vec3(0.3, 0.15, 0.5);
uniform vec3 neb_b : source_color = vec3(0.1, 0.4, 0.6);
uniform float neb_strength = 0.16;

float n_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float n_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(n_hash(i), n_hash(i + vec3(1, 0, 0)), f.x), mix(n_hash(i + vec3(0, 1, 0)), n_hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(n_hash(i + vec3(0, 0, 1)), n_hash(i + vec3(1, 0, 1)), f.x), mix(n_hash(i + vec3(0, 1, 1)), n_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float n_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * n_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

const float PI_ = 3.14159265359;

float hash13(vec3 p) {
	p = fract(p * 0.1031 + star_seed * 0.0137);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 stars(vec3 d) {
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 180.0 : 420.0;
		vec3 g = d * scale;
		vec3 cell = floor(g);
		float h = hash13(cell + float(layer) * 17.0);
		float thresh = layer == 0 ? 0.991 : 0.996;
		if (h > thresh) {
			vec3 jitter = vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 4.1)) - 0.5;
			vec3 sp = normalize(cell + 0.5 + jitter * 0.7);
			float dist = length(normalize(g) - sp) * scale;
			float b = (h - thresh) / (1.0 - thresh);
			float tint = hash13(cell + 9.9);
			vec3 sc = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.86, 0.7), tint);
			col += sc * b * exp(-dist * dist * 14.0) * (layer == 0 ? 1.2 : 0.6);
		}
	}
	return col;
}

// Mandelbrot exterior distance-estimate glow, in the plane centred on c.
float mandel_glow(vec2 p, float px) {
	vec2 z = vec2(0.0);
	vec2 dz = vec2(0.0);
	float m = 0.0;
	for (int i = 0; i < 64; i++) {
		dz = 2.0 * vec2(z.x * dz.x - z.y * dz.y, z.x * dz.y + z.y * dz.x) + vec2(1.0, 0.0);
		z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + p;
		m = dot(z, z);
		if (m > 1e4) {
			float r = sqrt(m);
			float de = 0.5 * r * log(r) / length(dz);
			return exp(-de / (px * 2.0)) * 0.8 + exp(-de / (px * 18.0)) * 0.25;
		}
	}
	return 0.06;   // inside: a faint fill
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = base_color + stars(d);
	vec3 so = vec3(mod(star_seed, 97.0), mod(star_seed * 0.37, 89.0), mod(star_seed * 0.11, 83.0));
	float n1 = n_fbm(d * 2.0 + so);
	float n2 = n_fbm(d * 4.3 - so * 0.5);
	float neb = smoothstep(0.5, 0.88, n1) * 0.7 + smoothstep(0.55, 0.92, n2) * 0.3;
	col += mix(neb_a, neb_b, smoothstep(0.35, 0.8, n2)) * neb * neb_strength * smoothstep(-0.05, 0.25, d.y);

	// "You are here": project directions around field_dir onto the complex plane.
	vec3 f = normalize(field_dir);
	vec3 right = normalize(cross(f, vec3(0.0, 1.0, 0.0)));   // screen-right when facing f
	vec3 up = cross(right, f);
	float cosang = dot(d, f);
	if (cosang > 0.0) {
		vec2 t = vec2(dot(d, right), dot(d, up)) / cosang;      // gnomonic projection
		float half_span = tan(radians(field_span_deg * 0.5));
		vec2 q = t / half_span;                                   // [-1,1] across the span
		if (max(abs(q.x), abs(q.y)) < 1.2) {
			vec2 p = vec2(-0.6, 0.0) + q * 1.6;                     // the whole set in view
			float px = 1.6 * 2.0 / 300.0;
			float fade = 1.0 - smoothstep(0.85, 1.2, max(abs(q.x), abs(q.y)));
			col += mark_color * mandel_glow(p, px) * field_strength * fade;
			// the marker: this territory's c
			float dc = length(p - c);
			float ring = exp(-pow((dc - 0.035) / 0.006, 2.0)) + exp(-dc * dc / 0.00008) * 1.5;
			col += mark_color * ring * 0.9 * fade;
		}
	}

	// Eris: a lit sphere with a terminator from the sun direction.
	vec3 e = normalize(eris_dir);
	float rad = radians(eris_radius_deg);
	float ang = acos(clamp(dot(d, e), -1.0, 1.0));
	if (ang < rad * 1.02) {
		vec3 er = normalize(cross(e, vec3(0.0, 1.0, 0.0)));
		vec3 eu = cross(er, e);
		vec2 s = vec2(dot(d, er), dot(d, eu)) / sin(rad);
		float r2 = dot(s, s);
		if (r2 < 1.0) {
			vec3 nrm = normalize(s.x * er + s.y * eu - sqrt(1.0 - r2) * e);
			float lit = max(0.0, dot(nrm, LIGHT0_DIRECTION));
			col = eris_color * (0.015 + lit * 0.9);
		}
	}

	// The sun: a hot point; LIGHT0 is the directional light.
	if (LIGHT0_ENABLED) {
		float sd = acos(clamp(dot(d, LIGHT0_DIRECTION), -1.0, 1.0));
		col += vec3(1.0, 0.96, 0.9) * (exp(-sd * sd / 0.00002) * 4.0 + exp(-sd / 0.01) * 0.05);
	}
	COLOR = col;
}
