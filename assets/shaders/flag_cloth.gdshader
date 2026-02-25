shader_type spatial;
render_mode cull_disabled;
// Flag cloth waving animation.
// Vertex sine wave displacement creates a fabric ripple effect.
// Applied to the QuadMesh flag surface.

uniform vec3 flag_color : source_color = vec3(0.8, 0.3, 0.2);
uniform float wave_speed : hint_range(0.5, 4.0) = 2.0;
uniform float wave_amplitude : hint_range(0.0, 0.15) = 0.08;
uniform float wave_frequency : hint_range(1.0, 8.0) = 4.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.75;

void vertex() {
	// Wave displacement based on UV.x (flag extends in X from pole)
	// More displacement further from the pole (UV.x = 0 at pole, 1 at tip)
	float wave_mask = UV.x * UV.x;  // Quadratic: more wave at the tip
	float wave = sin(UV.x * wave_frequency * PI + TIME * wave_speed) * wave_amplitude * wave_mask;
	wave += sin(UV.x * wave_frequency * 0.7 * PI + TIME * wave_speed * 1.3 + 1.0) * wave_amplitude * 0.4 * wave_mask;
	// Vertical ripple for secondary wave
	wave += sin(UV.y * 3.0 * PI + TIME * wave_speed * 0.8) * wave_amplitude * 0.2 * wave_mask;
	VERTEX.z += wave;
	// Slight Y displacement for drape effect
	VERTEX.y -= abs(wave) * 0.3;
}

void fragment() {
	ALBEDO = flag_color;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	// Double-sided: flip normal for back face
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
