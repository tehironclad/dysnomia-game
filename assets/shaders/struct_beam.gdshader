shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// Soft light shaft for floodlights / beacons. Fades toward the silhouette edges (fresnel)
// and along its length (UV.y: 0 at the source end of a CylinderMesh, 1 at the far end).

uniform float night = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.7, 1.0);

void fragment() {
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float along = 1.0 - UV.y;
	float f = pow(edge, 2.5) * along * along;
	float dust = 0.85 + 0.15 * sin(UV.y * 40.0 + TIME * 0.7);
	ALBEDO = tint.rgb * f * tint.a * night * 0.18 * dust;
}
