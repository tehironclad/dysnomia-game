shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;

// Fake light pool on the ground under a lamp: additive radial falloff. Per-instance tint
// (rgb = colour, a = strength) lets every pool share one material.
// `night` (0..1, set by the buildings from the time of day) fades pools out in daylight.

uniform float night = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float f = clamp(1.0 - r, 0.0, 1.0);
	f = f * f * (0.6 + 0.4 * f);
	// Slight dithering noise to avoid banding
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = tint.rgb * f * tint.a * night * 0.55 + (n - 0.5) * 0.004;
}
