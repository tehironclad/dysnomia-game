shader_type spatial;
render_mode unshaded, cull_back;

// Jukebox front: glowing arch with rising bubble tubes and a slow rainbow sweep.
uniform vec3 tint_a : source_color = vec3(1.0, 0.35, 0.6);
uniform vec3 tint_b : source_color = vec3(0.2, 0.8, 1.0);
uniform float energy = 2.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	// Arch outline (u: 0..1 across, v: 0 top .. 1 bottom)
	vec2 c = vec2(0.5, 0.42);
	float r = length((uv - c) * vec2(1.0, 1.25));
	float arch = smoothstep(0.47, 0.44, r) - smoothstep(0.40, 0.37, r);
	float side = (step(uv.y, 0.98) * step(0.42, uv.y)) * (smoothstep(0.08, 0.06, abs(uv.x - 0.06)) + smoothstep(0.08, 0.06, abs(uv.x - 0.94)));
	float tubes = clamp(arch + side, 0.0, 1.0);
	// Bubbles drifting up the tubes
	float bubbles = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float y = fract(-t * (0.12 + 0.03 * fi) + fi * 0.17);
		float x = (mod(fi, 2.0) < 1.0) ? 0.06 : 0.94;
		bubbles += smoothstep(0.022, 0.0, length((uv - vec2(x, 0.42 + y * 0.56)) * vec2(1.0, 1.6)));
	}
	vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (uv.y * 0.8 - t * 0.15 + vec3(0.0, 0.33, 0.67)));
	vec3 tube_col = mix(tint_a, rainbow, 0.55);
	// Inner window: record stack silhouette + speaker grille
	float inner = smoothstep(0.37, 0.35, r) * step(uv.y, 0.62);
	float grille = step(0.62, uv.y) * step(uv.y, 0.95) * step(0.15, uv.x) * step(uv.x, 0.85);
	float holes = step(0.5, fract(uv.x * 28.0)) * step(0.5, fract(uv.y * 30.0));
	vec3 col = vec3(0.02);
	col += inner * mix(vec3(0.25, 0.12, 0.05), tint_b * 0.6, 0.5 + 0.5 * sin(uv.y * 40.0 + t * 2.0));
	col += grille * (0.06 + 0.1 * holes) * tint_b;
	col += tubes * tube_col * energy;
	col += bubbles * vec3(1.0, 0.95, 0.8) * energy;
	ALBEDO = col;
	EMISSION = col;
}
