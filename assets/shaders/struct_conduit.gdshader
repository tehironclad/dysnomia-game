shader_type spatial;

// Power conduit / cable: dark rubber sheath with energy pulses travelling along UV.y (metres).
// energy and flow_speed are driven by territory charge; flash spikes on META.Beat.

uniform vec3 flow_color : source_color = vec3(0.3, 0.8, 1.0);
uniform float flow_speed = 1.0;
uniform float energy = 2.0;
uniform float pulse_spacing = 2.5;
uniform float flash = 0.0;
uniform vec3 sheath : source_color = vec3(0.035, 0.035, 0.04);

void fragment() {
	float d = UV.y / pulse_spacing - TIME * flow_speed;
	float pulse = pow(1.0 - fract(d), 6.0);
	// Thin glowing core stripe running the full length
	float stripe = smoothstep(0.1, 0.0, abs(UV.x - 0.5) - 0.06);
	float e = (pulse * 0.9 + 0.12) * stripe + pulse * 0.25;
	ALBEDO = sheath;
	ROUGHNESS = 0.55;
	METALLIC = 0.1;
	EMISSION = flow_color * e * energy + flow_color * flash * 3.0 * stripe;
}
