// The landmark supertall's curtain wall: blue-silver glass in 4 m floors with
// vertical mullions every 1.6 m, slab edges lit in the territory colour, and
// lit windows. How many windows are lit follows the territory's energy (its
// Epibar total); which ones is a fixed hash of the window, so the tower looks
// the same to every viewer. Floors line up across segments (world height);
// the horizontal facade coordinate runs along each face (object space), so
// twisted and turned segments keep straight mullions.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.5, 0.8, 1.0);
uniform float energy = 0.5;       // 0..1 (Development.energy_of)
uniform float seed = 0.0;
uniform float base_y = 0.0;       // world height of the plaza (floor 0)
uniform float crown_y = 1000.0;   // world height where the crown lights start

varying vec3 opos;
varying vec3 onrm;
varying float wy;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - base_y;
}

void fragment() {
	vec2 nf = onrm.xz;
	float side = step(0.5, length(nf));
	vec2 t = length(nf) > 0.001 ? normalize(vec2(-nf.y, nf.x)) : vec2(1.0, 0.0);
	float u = dot(opos.xz, t);
	float v = wy;
	vec2 cell = vec2(floor(u / 1.6), floor(v / 4.0));
	vec2 f = vec2(fract(u / 1.6), fract(v / 4.0));
	float mullion = 1.0 - step(0.06, f.x) * step(f.x, 0.94);
	float slab = 1.0 - step(0.06, f.y);
	float glass = (1.0 - mullion) * (1.0 - slab);
	float face = floor(atan(nf.y, nf.x) * 2.0) + 7.0;
	// Lit windows come in floors (whole floors on, a few dark rooms in them)
	float floor_on = step(h21(vec2(cell.y * 0.37 + face, seed)), 0.05 + energy * 0.55);
	float lit = floor_on * step(h21(cell + seed + face * 13.0), 0.72);
	// Sky reflection: lighter glass higher up, with a soft vertical gradient
	float sky = clamp(v / 400.0, 0.0, 1.0);
	vec3 g = mix(vec3(0.06, 0.08, 0.12), vec3(0.14, 0.19, 0.27), sky);
	vec3 frame = vec3(0.22, 0.23, 0.27);
	ALBEDO = mix(frame, g, glass);
	METALLIC = mix(0.85, 0.7, glass);
	ROUGHNESS = mix(0.4, 0.06, glass);
	vec3 warm = mix(vec3(1.0, 0.86, 0.62), tint, 0.25);
	vec3 e = warm * glass * lit * (0.14 + 0.16 * h21(cell * 1.7 + seed)) * side;
	// The glass carries a faint sheen of the territory colour so the mass reads at night
	e += tint * glass * 0.035 * (0.6 + sky) * side;
	// Vertical light fins every 6.4 m and a lit slab every fourth floor (antialiased)
	float fu = u / 6.4;
	float fin = 1.0 - smoothstep(0.0, fwidth(fu) * 1.5 + 0.004, abs(fract(fu + 0.5) - 0.5));
	float fv = v / 16.0;
	float band = 1.0 - smoothstep(0.0, fwidth(fv) * 1.5 + 0.004, abs(fract(fv + 0.5) - 0.5));
	e += tint * (fin * 0.55 + band * (0.3 + 0.4 * energy)) * side;
	// The crown: brighter bands toward the top
	float crown = step(crown_y - base_y, v);
	e += tint * crown * side * (0.5 + 0.5 * step(0.5, fract(v / 8.0)));
	// The lobby: the first two floors glow
	e += warm * step(v, 8.0) * glass * 0.3 * side;
	EMISSION = e;
}
