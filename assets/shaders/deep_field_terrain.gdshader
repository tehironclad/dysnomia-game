// Deep Field ground: dark land whose glowing filaments are the territory's own
// Julia set, computed per pixel from the world position (world space, so the
// pattern never slides with the camera). Heights come from JuliaHeightfield;
// this shader only adds the light. Every uniform is a chain-derived number
// (DeepField.params of QING.Entropy() + address) or a fixed constant.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec2 c = vec2(-0.75, 0.1);
uniform int power = 2;
uniform float extent = 1.5;
uniform float rotation = 0.0;
uniform float half_size = 256.0;     // metres from centre to edge
uniform vec3 color : source_color = vec3(0.5, 0.8, 1.0);
uniform vec3 color2 : source_color = vec3(1.0, 0.6, 0.9);
uniform float hue = 0.0;
uniform int style = 0;               // 0 glow · 1 duo · 2 bands · 3 ember · 4 gilded · 5 prism
uniform int max_iter = 96;
// How brightly the land is lit; driven by the territory's shared activity (WP 2.5).
uniform float glow = 1.0;
uniform float lit_bands = 2.0;       // escape bands lit around the set (grows with activity)
uniform float phase = 0.0;

varying vec3 world_pos;

const float TAU_ = 6.28318530718;
const vec3 GOLD = vec3(1.0, 0.78, 0.4);
const vec3 GROUND = vec3(0.032, 0.040, 0.062);   // a shade under #0b0e16

vec3 color_of(float t) {
	return vec3(0.55) + 0.45 * cos(TAU_ * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

// Fine regolith grain: value noise on world position (visual only).
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// world → complex plane (JuliaHeightfield.world_to_z)
	vec2 u = world_pos.xz / half_size * extent;
	float ca = cos(rotation);
	float sa = sin(rotation);
	vec2 z = vec2(u.x * ca - u.y * sa, u.x * sa + u.y * ca);
	float mpu = half_size / extent;      // metres per complex unit

	float D = float(power);
	vec2 dz = vec2(1.0, 0.0);
	float m = 0.0;
	float trap = 1e9;
	int i = 0;
	for (; i < 256; i++) {
		if (i >= max_iter) { break; }
		vec2 zp = vec2(1.0, 0.0);
		for (int e = 1; e < 6; e++) {
			if (e >= power) { break; }
			zp = cmul(zp, z);
		}
		dz = D * cmul(zp, dz);
		z = cmul(zp, z) + c;
		m = dot(z, z);
		trap = min(trap, m);
		if (m > 1e4) { break; }
	}

	float grain = 0.75 + 0.5 * (vnoise(world_pos.xz * 1.7) * 0.6 + vnoise(world_pos.xz * 0.23) * 0.4);
	vec3 albedo = GROUND * grain;
	vec3 light = vec3(0.0);
	float ph = phase + hue * TAU_;
	if (i >= max_iter) {
		// on the filled set: the plateau. Faint contour lines of the orbit trap
		// (the set's interior dynamics) on every style; stronger per style.
		float st = sqrt(trap);
		float v = exp(-trap * 3.0);
		vec3 tint = color2;
		if (style == 4) { tint = GOLD; }
		else if (style == 5) { tint = color_of(hue + st * 1.5); }
		float contour = pow(max(0.0, cos(st * 28.0)), 24.0);
		float rings = 0.0;
		if (style == 4) { rings = pow(max(0.0, cos(st * 34.0)), 14.0); }
		if (style == 5) { rings = pow(max(0.0, cos(st * 46.0)), 10.0); }
		if (style == 3) { rings = 0.5 * exp(-st * 4.0); }
		albedo = GROUND * 1.15 * grain;
		light = tint * (0.025 * v + 0.10 * contour + 0.28 * rings) * glow;
	} else {
		float rr = sqrt(m);
		float de_m = 0.5 * rr * log(rr) / length(dz) * mpu;   // distance to the set, metres
		float nu = float(i) + 1.0 - log(log(rr)) / log(D);
		float core = exp(-de_m / 0.5);
		float halo = exp(-de_m / 5.0);
		vec3 A = color;
		vec3 B = color;
		if (style == 1) { B = color2; }
		else if (style == 4) { A = GOLD; }
		else if (style == 5) { A = color_of(hue + nu * 0.05); B = color_of(hue + nu * 0.05 + 0.18); }
		float band = 0.5 + 0.5 * cos(nu * 1.6 + ph);
		// escape bands near the set light up as the territory's activity grows (WP 2.5)
		float near_set = 1.0 - smoothstep(lit_bands, lit_bands + 1.5, max(0.0, float(max_iter) - nu) * 0.15);
		float bands;
		if (style == 2 || style == 4 || style == 5) { bands = pow(band, 4.0) * 0.30 * exp(-de_m / 40.0); }
		else { bands = pow(band, 6.0) * 0.10 * exp(-de_m / 25.0); }
		light = (A * core * 0.9 + B * halo * 0.22 + B * bands * near_set) * glow;
		albedo = mix(GROUND * grain, A * 0.2, core * 0.4);
	}
	ALBEDO = albedo;
	ROUGHNESS = 0.92;
	SPECULAR = 0.05;
	EMISSION = light;
}
