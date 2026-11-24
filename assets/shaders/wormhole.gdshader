shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// The wormhole's mouth: a swirl falling into a bright core (RocketVoyage).

uniform float radius = 150.0;
varying vec2 p;

void vertex() {
	p = VERTEX.xz / radius;
}

void fragment() {
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 5.0 + 9.0 / (r + 0.08) - TIME * 3.0) * 0.5 + 0.5;
	float core = smoothstep(0.35, 0.0, r);
	float rim = smoothstep(1.0, 0.75, r);
	vec3 deep = vec3(0.25, 0.1, 0.6);
	vec3 bright = vec3(0.65, 0.85, 1.0);
	vec3 c = mix(deep, bright, swirl * (1.0 - r)) * rim + vec3(1.0) * core * 1.5;
	ALBEDO = c;
	ALPHA = clamp(rim * (0.55 + 0.45 * swirl) + core, 0.0, 1.0);
}
