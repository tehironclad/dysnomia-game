shader_type spatial;
// Upsilon Rocket hull on a lathed mesh (UV.x = angle 0..1, local Y = height in metres):
// painted panels with seams, a red/white roll-pattern checker band, livery pinstripes and
// engine soot streaks creeping up from the skirt.

uniform vec3 base_color : source_color = vec3(0.90, 0.89, 0.86);
uniform vec3 livery : source_color = vec3(0.80, 0.08, 0.14);
uniform float checker_lo = 12.0;
uniform float checker_hi = 18.0;
uniform float checker_cell = 1.5;
uniform float soot_h = 7.0;
uniform float scorch = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float ang = UV.x;
	float y = lp.y;
	vec3 c = base_color;
	float in_band = step(checker_lo, y) * step(y, checker_hi);
	float chk = mod(floor(ang * 8.0) + floor((y - checker_lo) / checker_cell), 2.0);
	c = mix(c, livery, in_band * chk);
	float pin = step(abs(y - (checker_lo - 0.7)), 0.12) + step(abs(y - (checker_hi + 0.7)), 0.12)
		+ step(abs(y - 3.2), 0.35);
	c = mix(c, livery, clamp(pin, 0.0, 1.0));
	float fy = fract(y / 2.4);
	float sy = 1.0 - smoothstep(0.003, 0.01, min(fy, 1.0 - fy));
	float fa = fract(ang * 16.0);
	float sa = 1.0 - smoothstep(0.004, 0.014, min(fa, 1.0 - fa));
	float seam = max(sy, sa);
	c *= 1.0 - seam * 0.5;
	float streak = 0.5 + 0.5 * sin(ang * 6.28318 * 23.0 + sin(ang * 40.0) * 2.0);
	float soot = (1.0 - smoothstep(0.0, soot_h * (0.7 + 0.5 * streak), y)) * (0.5 + 0.5 * scorch);
	c = mix(c, vec3(0.05, 0.045, 0.04), soot * (0.6 + 0.35 * streak));
	ALBEDO = c;
	ROUGHNESS = clamp(mix(0.3, 0.85, soot) + seam * 0.25, 0.0, 1.0);
	METALLIC = 0.2;
	CLEARCOAT = 0.6 * (1.0 - soot);
	CLEARCOAT_ROUGHNESS = 0.2;
}
