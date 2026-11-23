// A skyline tower's facade: dark metal with a grid of windows (1.4 m wide,
// one per 3 m floor). How many windows are lit follows the territory's energy
// (its Epibar total); which ones is a fixed hash of the window, so the city
// looks the same to everyone. Trim lines mark each floor.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.5, 0.8, 1.0);
uniform float energy = 0.5;       // 0..1 (Development.energy_of)
uniform float seed = 0.0;
uniform float flash = 0.0;        // the tower just grew

varying vec3 lpos;
varying vec3 lnrm;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	lpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz;
	lnrm = NORMAL;
}

void fragment() {
	vec3 n = abs(lnrm);
	// Facade coordinates: horizontal along the face, vertical up.
	float u = n.x > 0.5 ? lpos.z : lpos.x;
	float v = lpos.y;
	vec2 cell = vec2(floor(u / 1.4), floor(v / 3.0));
	vec2 f = vec2(fract(u / 1.4), fract(v / 3.0));
	float window = step(0.18, f.x) * step(f.x, 0.82) * step(0.3, f.y) * step(f.y, 0.82);
	float lit = step(h21(cell + seed + (n.x > 0.5 ? 17.0 : 0.0)), 0.08 + energy * 0.82);
	float trim = 1.0 - step(0.035, f.y);
	vec3 base = vec3(0.045, 0.05, 0.065);
	float roof = step(0.5, lnrm.y);
	ALBEDO = mix(base, vec3(0.02, 0.025, 0.035), window);
	METALLIC = 0.6;
	ROUGHNESS = mix(0.35, 0.08, window);
	vec3 warm = mix(vec3(1.0, 0.82, 0.55), tint, 0.35);
	vec3 e = warm * window * lit * (0.45 + 0.4 * h21(cell * 1.7 + seed)) * (1.0 - roof);
	e += tint * trim * 0.6 * (1.0 - roof);
	e += tint * flash * 1.5;
	EMISSION = e;
}
