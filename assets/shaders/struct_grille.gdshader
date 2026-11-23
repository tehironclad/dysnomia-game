shader_type spatial;

// Perforated steel speaker grille / louvre mesh. Box-projected in world space, holes are
// anti-aliased and fade to an average tone at distance so they never shimmer.

uniform vec3 metal_color : source_color = vec3(0.09, 0.09, 0.1);
uniform vec3 hole_color : source_color = vec3(0.005, 0.005, 0.006);
uniform float pitch = 0.035;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wn);
	vec2 uv = (an.x > an.y && an.x > an.z ? wp.zy : (an.y > an.z ? wp.xz : wp.xy)) / pitch;
	uv.x += step(0.5, fract(uv.y * 0.5)) * 0.5;  // Staggered rows
	float d = length(fract(uv) - 0.5);
	float w = fwidth(d) * 1.2;
	float hole = 1.0 - smoothstep(0.3 - w, 0.3 + w, d);
	float far = clamp((fwidth(uv.x) - 0.3) * 2.0, 0.0, 1.0);
	hole = mix(hole, 0.28, far);
	ALBEDO = mix(metal_color, hole_color, hole);
	ROUGHNESS = mix(0.45, 0.95, hole);
	METALLIC = 0.6 * (1.0 - hole);
}
