shader_type spatial;

// Retro moon-travel / gig poster art: banded sky, a ringed planet (Eris over Dysnomia),
// mountain silhouettes and a printed border, aged paper grain. Title is a Label3D on top.
uniform vec3 sky_top : source_color = vec3(0.1, 0.1, 0.3);
uniform vec3 sky_low : source_color = vec3(0.95, 0.5, 0.3);
uniform vec3 ink : source_color = vec3(0.08, 0.05, 0.1);
uniform vec3 paper : source_color = vec3(0.92, 0.86, 0.72);
uniform float variant = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	// Print border
	vec2 e = min(uv, 1.0 - uv);
	float border = step(min(e.x, e.y), 0.05);
	// Art window (upper ~70%)
	float art_y = uv.y / 0.72;
	vec3 col = paper;
	if (uv.y < 0.72) {
		float band = floor(art_y * 7.0) / 7.0;       // posterised gradient
		col = mix(sky_top, sky_low, band);
		// Planet with a ring
		vec2 pc = vec2(0.62 - variant * 0.25, 0.32);
		float r = length((uv - pc) * vec2(1.0, 1.4));
		col = mix(col, mix(sky_low, vec3(1.0, 0.95, 0.8), 0.5), smoothstep(0.17, 0.16, r));
		float ring = abs(((uv.y - pc.y) * 1.4 + (uv.x - pc.x) * 0.35) / 0.02);
		col = mix(col, vec3(1.0, 0.9, 0.7), step(ring, 1.0) * step(0.15, r) * step(r, 0.3) * 0.8);
		// Mountains
		float h1 = 0.55 + 0.08 * sin(uv.x * 9.0 + variant * 4.0) + 0.05 * sin(uv.x * 23.0);
		float h2 = 0.62 + 0.05 * sin(uv.x * 14.0 + 1.3 + variant);
		col = mix(col, ink * 1.8 + sky_top * 0.3, step(h1, uv.y));
		col = mix(col, ink, step(h2, uv.y));
		// Little cantina light on the ridge
		col += vec3(1.0, 0.7, 0.3) * smoothstep(0.012, 0.0, length(uv - vec2(0.3 + variant * 0.3, h2 - 0.01)));
	}
	col = mix(col, ink, border * 0.9);
	// Paper grain + fold wear
	col *= 0.85 + 0.15 * noise(uv * 220.0);
	col *= 1.0 - 0.1 * smoothstep(0.004, 0.0, abs(uv.y - 0.5));
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
