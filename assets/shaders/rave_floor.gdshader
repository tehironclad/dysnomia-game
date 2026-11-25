shader_type spatial;
// The arcade's floor under blacklight (RaveHall): a dance floor of glowing tiles that change on every
// beat, and round it a dark carpet flecked with fluorescent paint. One mesh, one draw call. Driven by
// the beat clock (RaveMusic); the palette and patterns come from the territory (RaveStyle).

uniform vec3 c1 : source_color = vec3(0.3, 0.9, 1.0);
uniform vec3 c2 : source_color = vec3(1.0, 0.3, 0.8);
uniform vec3 c3 : source_color = vec3(1.0, 0.85, 0.3);
uniform vec4 dance = vec4(-6.0, -6.4, 6.0, 1.6);  // x0, z0, x1, z1 (metres)
uniform vec2 dj = vec2(0.0, -8.0);
uniform float beats = 0.0;  // the beat clock, fractional
uniform float energy = 1.0;  // the song's section: 1 drop … 0.35 break
uniform int pattern = 0;  // 0 checker, 1 ripple, 2 sparkle, 3 bars
uniform float tile = 1.0;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 pick(float h) {
	return h < 0.34 ? c1 : (h < 0.67 ? c2 : c3);
}

void fragment() {
	vec2 p = wpos.xz;
	float b = floor(beats);
	float ph = fract(beats);
	float kick = exp(-ph * 5.0);
	vec3 col = vec3(0.012, 0.008, 0.02);
	vec3 em = vec3(0.0);
	bool on_floor = p.x > dance.x && p.x < dance.z && p.y > dance.y && p.y < dance.w;
	if (on_floor) {
		vec2 t = floor((p - dance.xy) / tile);
		vec2 f = fract((p - dance.xy) / tile);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float on = 0.0;
		if (pattern == 0) {
			on = mod(t.x + t.y + b, 2.0) < 1.0 ? 1.0 : 0.12;
		} else if (pattern == 1) {
			float d = length(t + 0.5 - (dj - dance.xy) / tile);
			on = fract(d * 0.22 - beats * 0.5) < 0.32 ? 1.0 : 0.1;
		} else if (pattern == 2) {
			on = hash2(t + b * 1.37) > 0.55 ? 1.0 : 0.08;
		} else {
			on = mod(t.x + b, 4.0) < 1.0 || mod(t.y - b, 4.0) < 1.0 ? 1.0 : 0.1;
		}
		vec3 c = pick(hash2(t * 0.7 + floor(b / 4.0) * 3.1));
		float inset = smoothstep(0.03, 0.07, edge);
		float rim = smoothstep(0.1, 0.05, edge) * inset;
		em = c * (on * (0.55 + 1.2 * kick) * energy * inset + rim * 0.5);
		col = mix(vec3(0.02), c * 0.08, on);
	} else {
		// Carpet: fluorescent flecks on near-black, a faint grid of paint.
		vec2 cell = floor(p * 9.0);
		float h = hash2(cell);
		if (h > 0.94) {
			vec2 fc = fract(p * 9.0) - 0.5;
			float dot_ = smoothstep(0.32, 0.12, length(fc));
			em = pick(hash2(cell + 7.0)) * dot_ * (0.45 + 0.25 * kick);
		}
		vec2 g = abs(fract(p * 0.5) - 0.5);
		float line = smoothstep(0.012, 0.0, min(g.x, g.y));
		em += c1 * line * 0.12;
	}
	ALBEDO = col;
	ROUGHNESS = 0.35;
	METALLIC = 0.2;
	EMISSION = em;
}
