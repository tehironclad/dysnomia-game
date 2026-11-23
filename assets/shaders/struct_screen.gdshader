shader_type spatial;
render_mode cull_back;

// Animated control-room display for territory structures. Values come from chain state.
// mode 0: three bar meters (value_a/b/c)  1: oscilloscope (amplitude = value_a, rate = value_b)
// mode 2: radar sweep (blip count ~ value_b)  3: scrolling data log (density ~ value_a)
// mode 4: vertical segmented VU meter (level = value_a, peak flicker)
// mode 5: club visualiser — spectrum bars in a cyan/violet/magenta gradient (energy = value_a)

uniform int mode = 0;
uniform vec3 accent : source_color = vec3(0.2, 0.9, 1.0);
uniform float value_a : hint_range(0.0, 1.0) = 0.5;
uniform float value_b : hint_range(0.0, 1.0) = 0.5;
uniform float value_c : hint_range(0.0, 1.0) = 0.5;
uniform float brightness = 2.2;
uniform float flash = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }

vec3 bar_meters(vec2 uv) {
	vec3 col = vec3(0.0);
	float vals[3] = float[3](value_a, value_b, value_c);
	vec3 cols[3] = vec3[3](accent, vec3(1.0, 0.55, 0.15), vec3(0.35, 1.0, 0.45));
	for (int i = 0; i < 3; i++) {
		float x0 = 0.1 + float(i) * 0.29;
		if (uv.x > x0 && uv.x < x0 + 0.2) {
			float v = vals[i] * (0.96 + 0.04 * sin(TIME * 7.0 + float(i) * 2.0));
			float y = 1.0 - uv.y;
			float seg = step(0.25, fract(y * 18.0));
			float lit = step(y, 0.08 + v * 0.82) * step(0.08, y);
			col += cols[i] * lit * seg;
			col += cols[i] * 0.07 * seg * step(0.08, y) * step(y, 0.9);
			// Tick at peak
			col += cols[i] * smoothstep(0.012, 0.0, abs(y - (0.08 + v * 0.82))) * 1.5;
		}
	}
	return col;
}

vec3 scope(vec2 uv) {
	float amp = 0.08 + value_a * 0.3;
	float f = 6.0 + value_b * 18.0;
	float t = TIME * (1.5 + value_b * 4.0);
	float w = sin(uv.x * f + t) * amp + sin(uv.x * f * 2.7 - t * 1.3) * amp * 0.35;
	float d = abs(uv.y - 0.5 - w);
	vec3 col = accent * smoothstep(0.03, 0.0, d) * 1.6 + accent * smoothstep(0.12, 0.0, d) * 0.25;
	vec2 g = abs(fract(uv * vec2(10.0, 6.0)) - 0.5);
	col += accent * 0.08 * step(0.47, max(g.x, g.y));
	return col;
}

vec3 radar(vec2 uv) {
	vec2 p = (uv - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) return vec3(0.0);
	float a = atan(p.y, p.x);
	float sweep = mod(TIME * 1.4, 6.2831853);
	float da = mod(sweep - a + 6.2831853, 6.2831853);
	vec3 col = accent * exp(-da * 3.0) * 0.6;
	col += accent * 0.25 * smoothstep(0.02, 0.0, abs(fract(r * 4.0) - 0.5) - 0.48);
	col += accent * 0.2 * smoothstep(0.015, 0.0, min(abs(p.x), abs(p.y)));
	for (int i = 0; i < 6; i++) {
		if (float(i) > value_b * 6.0 + 1.0) break;
		vec2 bp = vec2(hash(vec2(float(i), 1.0)), hash(vec2(float(i), 2.0))) * 1.4 - 0.7;
		float ba = atan(bp.y, bp.x);
		float age = mod(sweep - ba + 6.2831853, 6.2831853);
		col += vec3(1.0, 0.8, 0.3) * smoothstep(0.05, 0.0, length(p - bp)) * exp(-age * 0.6) * 2.0;
	}
	return col;
}

vec3 data_log(vec2 uv) {
	float rows = 14.0;
	float scroll = TIME * (0.6 + value_a * 1.5);
	float row = floor(uv.y * rows + scroll);
	float fy = fract(uv.y * rows + scroll);
	float cols = 28.0;
	float cx = floor(uv.x * cols);
	float fx = fract(uv.x * cols);
	float len = 6.0 + hash(vec2(row, 3.0)) * 20.0 * (0.4 + value_a * 0.6);
	float on = step(cx, len) * step(0.35, hash(vec2(cx, row)));
	float glyph = step(0.2, fy) * step(fy, 0.75) * step(0.15, fx) * step(fx, 0.85);
	vec3 c = mix(accent, vec3(1.0, 0.7, 0.2), step(0.85, hash(vec2(row, 9.0))));
	return c * on * glyph * 0.9;
}

vec3 vu(vec2 uv) {
	float y = 1.0 - uv.y;
	float lvl = clamp(value_a * (0.85 + 0.15 * sin(TIME * 9.0 + seed)) + 0.05 * sin(TIME * 23.0 + seed * 2.0), 0.0, 1.0);
	float seg = step(0.3, fract(y * 16.0)) * step(0.12, uv.x) * step(uv.x, 0.88);
	vec3 c = mix(vec3(0.2, 1.0, 0.4), vec3(1.0, 0.8, 0.1), smoothstep(0.55, 0.7, y));
	c = mix(c, vec3(1.0, 0.15, 0.1), smoothstep(0.82, 0.9, y));
	return c * seg * (step(y, lvl) + 0.06);
}

vec3 visual(vec2 uv) {
	float bars = 32.0;
	float bx = floor(uv.x * bars);
	float fx = fract(uv.x * bars);
	float t = TIME;
	float lvl = 0.25 + 0.55 * value_a * (0.5 + 0.5 * sin(t * (2.0 + hash(vec2(bx, 1.0)) * 5.0) + bx * 0.7));
	lvl *= 0.75 + 0.25 * pow(0.5 + 0.5 * sin(t * 6.2832 * (1.4 + value_b)), 6.0);
	lvl = clamp(lvl + 0.15 * sin(bx * 0.4 + t * 1.3), 0.05, 0.98);
	float y = 1.0 - uv.y;
	float seg = step(0.22, fract(y * 24.0)) * step(0.12, fx) * step(fx, 0.88);
	vec3 c = mix(vec3(0.2, 0.9, 1.0), vec3(0.65, 0.3, 1.0), smoothstep(0.0, 0.6, y));
	c = mix(c, vec3(1.0, 0.25, 0.7), smoothstep(0.6, 1.0, y));
	float lit = step(y, lvl) * seg;
	float peak = smoothstep(0.02, 0.0, abs(y - lvl - 0.03)) * step(0.12, fx) * step(fx, 0.88);
	// Soft rings behind the bars
	vec2 p = (uv - 0.5) * vec2(2.0, 1.2);
	float ring = smoothstep(0.03, 0.0, abs(fract(length(p) * 3.0 - t * 0.6) - 0.5) - 0.46) * 0.25;
	return c * (lit + peak * 1.5) + vec3(0.25, 0.6, 1.0) * ring * value_a;
}

void fragment() {
	vec2 uv = UV;
	vec3 col;
	if (mode == 0) col = bar_meters(uv);
	else if (mode == 1) col = scope(uv);
	else if (mode == 2) col = radar(uv);
	else if (mode == 3) col = data_log(uv);
	else if (mode == 4) col = vu(uv);
	else col = visual(uv);
	// CRT-ish scanlines + vignette + faint backlight
	float scan = 0.82 + 0.18 * sin(uv.y * 360.0);
	vec2 v = uv - 0.5;
	float vig = 1.0 - dot(v, v) * 1.6;
	col = (col * scan + accent * 0.025) * vig;
	col += accent * flash * 0.8;
	ALBEDO = vec3(0.01);
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	EMISSION = col * brightness;
}
