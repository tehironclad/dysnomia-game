shader_type spatial;
render_mode cull_disabled;
// Striped canvas with a scalloped trailing edge (UV.y = 1). Colors are per instance so
// every stall and the carousel canopy share one material.

instance uniform vec3 color_a : source_color = vec3(0.78, 0.08, 0.12);
instance uniform vec3 color_b : source_color = vec3(0.95, 0.92, 0.86);
instance uniform float stripes = 8.0;
uniform float night = 0.0;

void fragment() {
	float s = step(0.5, fract(UV.x * stripes));
	vec3 c = mix(color_a, color_b, s);
	float edge = 0.9 + 0.085 * abs(sin(UV.x * stripes * 3.14159265));
	if (UV.y > edge) {
		discard;
	}
	// Canvas weave + sun-bleached grime toward the edge
	float weave = 0.94 + 0.06 * sin(UV.x * 820.0) * sin(UV.y * 610.0);
	float grime = 1.0 - 0.12 * smoothstep(0.6, 0.95, UV.y);
	ALBEDO = c * weave * grime;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.6;
	// Lamps inside the stall shine through the canvas at night
	EMISSION = c * night * 0.18;
}
