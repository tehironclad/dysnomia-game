shader_type spatial;
render_mode cull_disabled;
// Bunting pennants (mode 0) and helium balloons (mode 1), MultiMesh with instance colors.
// INSTANCE_CUSTOM.x = phase. Motion is slow and floaty: low gravity, thin air.

uniform float mode = 0.0;

varying float v_string;

void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	if (mode < 0.5) {
		float k = clamp(-VERTEX.y / 0.36, 0.0, 1.0);
		VERTEX.z += sin(TIME * 1.1 + ph * 6.0) * 0.07 * k;
		VERTEX.x += sin(TIME * 0.8 + ph * 4.0) * 0.02 * k;
		v_string = 0.0;
	} else {
		v_string = 1.0 - step(1.06, VERTEX.y);
		float h = clamp(VERTEX.y / 1.5, 0.0, 1.0);
		VERTEX.x += sin(TIME * 0.6 + ph * 6.28) * 0.14 * h;
		VERTEX.z += cos(TIME * 0.45 + ph * 4.0) * 0.12 * h;
		VERTEX.y += sin(TIME * 0.8 + ph * 3.0) * 0.05 * h;
	}
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (mode < 0.5) {
		ALBEDO = c;
		ROUGHNESS = 0.85;
		BACKLIGHT = c * 0.6;
	} else {
		ALBEDO = mix(c, vec3(0.8), v_string);
		ROUGHNESS = mix(0.16, 0.7, v_string);
		SPECULAR = 0.7;
		CLEARCOAT = 1.0 - v_string;
		CLEARCOAT_ROUGHNESS = 0.1;
		BACKLIGHT = c * 0.45 * (1.0 - v_string);
		RIM = 0.3;
		RIM_TINT = 0.6;
	}
}
