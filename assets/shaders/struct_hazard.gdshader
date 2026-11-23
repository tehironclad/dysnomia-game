shader_type spatial;

// Worn diagonal hazard stripes in object space — works on any box/cylinder face without UVs.

uniform float stripe_freq = 3.0;
uniform vec3 color_a : source_color = vec3(0.95, 0.68, 0.05);
uniform vec3 color_b : source_color = vec3(0.04, 0.04, 0.04);

varying vec3 obj_pos;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	obj_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = fract((obj_pos.x + obj_pos.y + obj_pos.z) * stripe_freq * 0.5);
	float band = smoothstep(0.48, 0.52, s);
	vec3 col = mix(color_a, color_b, band);
	// Scuffs and grime
	float n = noise(obj_pos * 6.0) * 0.6 + noise(obj_pos * 23.0) * 0.4;
	float scuff = smoothstep(0.62, 0.8, n);
	col = mix(col, vec3(0.32, 0.3, 0.28), scuff * 0.7);
	col *= 0.8 + 0.2 * noise(obj_pos * 2.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.9, scuff);
	METALLIC = 0.15 + scuff * 0.4;
}
