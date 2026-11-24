shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Grand Fair fireworks, fully on the GPU (no loops): a MultiMesh of spark quads.
// Instance origin = burst centre, instance color = spark colour,
// INSTANCE_CUSTOM.xyz = direction (0..1 encoded), .w = burst phase (0..1).
// Each shell climbs from the ground, bursts into a slow lunar-gravity shell, fades.

uniform float period = 9.0;
uniform float climb = 1.6;       // seconds from launch to burst
uniform float rise = 55.0;       // metres climbed before the burst
uniform float speed = 16.0;
uniform float gravity = 1.6;     // the Moon is gentle — sparks hang in the air
uniform float life = 3.6;
uniform float energy = 5.0;      // set from FairKit.apply_night (0 by day)
uniform float spark_size = 0.32;

varying float v_fade;
varying float v_core;

void vertex() {
	vec3 dir = INSTANCE_CUSTOM.xyz * 2.0 - 1.0;
	float t = mod(TIME + INSTANCE_CUSTOM.w * period, period);
	vec3 off;
	float size = spark_size;
	if (t < climb) {
		float u = t / climb;
		off = vec3(0.0, -rise * (1.0 - u) * (1.0 - u), 0.0);
		v_fade = (INSTANCE_ID % 64 == 0) ? 0.8 : 0.0;   // one spark per shell draws the climbing trail
		v_core = 1.0;
		size *= 0.8;
	} else {
		float s = t - climb;
		float r = speed * (1.0 - exp(-s * 1.3)) / 1.3 + 0.4;
		off = dir * r + vec3(0.0, -0.5 * gravity * s * s, 0.0);
		float u2 = clamp(s / life, 0.0, 1.0);
		v_fade = (1.0 - u2) * (1.0 - u2) * (1.0 + 0.6 * exp(-s * 6.0));
		v_core = exp(-s * 2.0);
		size *= 1.0 + 0.8 * exp(-s * 3.0);
	}
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + off;
	vec4 cv = VIEW_MATRIX * vec4(centre, 1.0);
	cv.xy += VERTEX.xy * size * step(0.001, v_fade);
	POSITION = PROJECTION_MATRIX * cv;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	a = a * a;
	vec3 c = mix(COLOR.rgb, vec3(1.0, 0.95, 0.85), v_core * 0.35);
	ALBEDO = c * a * v_fade * energy;
}
