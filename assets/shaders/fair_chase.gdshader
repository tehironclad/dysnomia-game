shader_type spatial;
render_mode cull_back;
// A stage's chase-bulb frame (FairFx), one MultiMesh: instance colour = the bulb's colour,
// its alpha = emission energy / 16 (0 = an unlit bulb, a dull painted glass).
// `night` follows FairKit.apply_night() (day ≈ 0.57 of the night energy, as the glow materials).

uniform float night : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float e = COLOR.a * 16.0;
	float lit = step(0.001, e);
	ALBEDO = COLOR.rgb * mix(1.0, 0.6, lit);
	ROUGHNESS = mix(0.4, 0.3, lit);
	METALLIC = mix(0.2, 0.0, lit);
	EMISSION = COLOR.rgb * e * mix(0.57, 1.0, night);
}
