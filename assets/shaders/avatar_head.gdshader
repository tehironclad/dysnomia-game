shader_type spatial;
// A creature head (AvatarHeads) baked into one mesh, one surface, one material shared by
// every head: the parts' colours ride the vertex colour (linear), roughness and metallic
// ride UV (x, y) and emission energy rides UV2.x. `grey` greys every part by its own
// luminance (an offline / ghost avatar); a second shared material carries grey = 1.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float grey : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_pbr;

void vertex() {
	v_pbr = vec3(UV.x, UV.y, UV2.x);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, vec3(lum, lum, lum * 1.05), grey);
	ALBEDO = c;
	ROUGHNESS = v_pbr.x;
	METALLIC = v_pbr.y;
	EMISSION = c * v_pbr.z;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
