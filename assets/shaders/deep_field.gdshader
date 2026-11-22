// Deep Field: a territory's (or identity's) Julia set z ↦ z^D + c, drawn as
// luminous distance-estimate filaments on black. GPU twin of render() in the
// Entropy site's lib/deep-field.js and of scripts/deepfield/julia.gd (the CPU
// reference the tests check against). Every input is a chain-derived number:
// set them with DeepFieldView.apply_params(DeepField.params(...)).
shader_type canvas_item;

uniform vec2 c = vec2(-0.75, 0.1);
uniform int power = 2;
uniform vec3 color : source_color = vec3(0.5, 0.8, 1.0);
uniform vec3 color2 : source_color = vec3(1.0, 0.6, 0.9);
uniform float hue = 0.0;
// 0 glow · 1 duo · 2 bands · 3 ember · 4 gilded · 5 prism
uniform int style = 0;
uniform int max_iter = 160;
uniform bool mirror = false;      // draw c̄ (the Cone to c's Rod)
uniform float phase = 0.0;        // band animation
// View: z = center + R(angle) · q · scale, q ∈ [-1,1] on the short side.
uniform vec2 center = vec2(0.0);
uniform float view_scale = 1.5;   // = extent for the standard framing
uniform float view_angle = 0.0;   // = rotation for the standard framing
uniform float aspect = 1.0;       // rect width / height
uniform float intensity = 1.0;    // overall brightness (e.g. lit by activity)

const float TAU_ = 6.28318530718;
const vec3 GOLD = vec3(1.0, 0.78, 0.4);

vec3 color_of(float t) {
	return vec3(0.55) + 0.45 * cos(TAU_ * (vec3(t) + vec3(0.0, 0.33, 0.67)));
}

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	if (aspect >= 1.0) { q.x *= aspect; } else { q.y /= aspect; }
	float ca = cos(view_angle);
	float sa = sin(view_angle);
	vec2 z = center + vec2(q.x * ca - q.y * sa, q.x * sa + q.y * ca) * view_scale;
	// complex units per pixel (the JS uses 2·extent / min(w, h))
	float px = max(length(dFdx(z)), length(dFdy(z)));
	px = max(px, 1e-7);

	vec2 cr = mirror ? vec2(c.x, -c.y) : c;
	float D = float(power);
	vec2 dz = vec2(1.0, 0.0);
	float m = 0.0;
	float trap = 1e9;
	float trap_a = 0.0;
	int i = 0;
	for (; i < 256; i++) {
		if (i >= max_iter) { break; }
		vec2 zp = vec2(1.0, 0.0);              // z^(D-1)
		for (int e = 1; e < 6; e++) {
			if (e >= power) { break; }
			zp = cmul(zp, z);
		}
		dz = D * cmul(zp, dz);
		z = cmul(zp, z) + cr;
		m = dot(z, z);
		if (m < trap) { trap = m; trap_a = atan(z.y, z.x); }
		if (m > 1e4) { break; }
	}

	vec3 rgb;
	if (i >= max_iter) {
		// inside the filled set: dark, tinted by the orbit trap
		float v = 0.07 * exp(-trap * 3.0);
		if (style == 3) {
			float qq = exp(-sqrt(trap) * 4.0);
			rgb = color2 * (v + 0.5 * qq);
		} else if (style == 5) {
			vec3 hc = color_of(hue + trap_a / TAU_ + sqrt(trap) * 1.5);
			float st = pow(max(0.0, cos(sqrt(trap) * 46.0)), 10.0) * 0.55 + 0.14 * exp(-trap * 3.0);
			rgb = hc * st;
		} else if (style == 4) {
			float gq = 0.14 * exp(-trap * 2.0) + 0.42 * pow(max(0.0, cos(sqrt(trap) * 34.0)), 14.0);
			rgb = GOLD * gq + color * 0.05;
		} else {
			rgb = color * v;
		}
	} else {
		float rr = sqrt(m);
		float de = 0.5 * rr * log(rr) / length(dz);
		float core = exp(-de / (px * 1.6));
		float halo = exp(-de / (px * 22.0));
		float wm = core * 0.55;
		float nu = float(i) + 1.0 - log(log(rr)) / log(D);
		vec3 A = color;
		vec3 B = color;
		if (style == 1) { B = color2; }
		else if (style == 4) { A = GOLD; B = color; }
		else if (style == 5) {
			A = color_of(hue + nu * 0.05);
			B = color_of(hue + nu * 0.05 + 0.18 + 0.06 * sin(atan(z.y, z.x) * 2.0));
		}
		float ph = phase + hue * TAU_;
		float hg;
		if (style == 2) {
			float band = 0.5 + 0.5 * cos(nu * 1.6 + ph);
			hg = halo * 0.22 + 0.42 * pow(band, 4.0) * exp(-de / (px * 140.0));
		} else if (style == 4) {
			float band = 0.5 + 0.5 * cos(nu * 2.4 + ph);
			hg = halo * 0.4 + 0.3 * pow(band, 3.0) * exp(-de / (px * 160.0)) + 0.05 * exp(-de / (px * 600.0));
		} else if (style == 5) {
			float band = 0.5 + 0.5 * cos(nu * 1.25 + ph);
			hg = halo * 0.5 + 0.42 * pow(band, 2.0) * exp(-de / (px * 260.0)) + 0.1 * exp(-de / (px * 900.0));
		} else {
			hg = halo * 0.3;
		}
		rgb = (A * (1.0 - wm) + wm) * core + B * hg;
	}
	COLOR = vec4(min(rgb * intensity, vec3(1.0)), 1.0);
}
