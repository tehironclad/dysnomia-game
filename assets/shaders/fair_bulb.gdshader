shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
// Carnival bulb (MultiMesh). Instance color = bulb tint, INSTANCE_CUSTOM.x = chase phase.
// `energy` is driven by FairKit.apply_night(); glow does the rest.

uniform float energy = 3.0;
uniform float chase_speed = 0.55;
uniform float chase_depth = 0.55;

varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	float ph = fract(TIME * chase_speed + v_phase);
	float on = smoothstep(0.0, 0.12, ph) * (1.0 - smoothstep(0.55, 0.68, ph));
	on = mix(1.0, on, chase_depth);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 c = COLOR.rgb;
	// Hot filament core reads whiter, glass edge keeps the tint
	vec3 lit = mix(c, vec3(1.0, 0.95, 0.85), facing * facing * 0.45);
	ALBEDO = lit * energy * (0.25 + 0.75 * on) * (0.55 + 0.45 * facing);
}
