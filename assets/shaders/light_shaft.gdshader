shader_type spatial;
// A soft column of light (the Heart's shaft): additive, brightest along the
// silhouette's middle, fading at its edges and with height, with a slow drift
// of brighter bands running up. Reads as light in the air, not a solid tube.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color = vec3(0.5, 0.82, 1.0);
uniform float intensity = 0.5;
uniform float height = 20.0;   // the mesh's height (local), for the fade
uniform float fade_power = 1.8;
uniform float band_rate = 0.6; // bands drifting up per second (energy)

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	float y = clamp(local_y / height + 0.5, 0.0, 1.0);
	float fade = pow(1.0 - y, fade_power) * smoothstep(0.0, 0.05, y);
	float bands = 0.8 + 0.2 * sin(local_y * 0.45 - TIME * band_rate * 6.2832);
	ALBEDO = color * intensity * core * fade * bands;
}
