shader_type spatial;
// The fair's far stand-ins (FarProxy): every plain paint of a group drawn as ONE surface.
// Per vertex: COLOR.rgb = the paint's albedo (sRGB, as authored), COLOR.a = its clearcoat,
// UV2 = (roughness, metallic). What StandardMaterial3D would draw for that paint, minus nothing
// visible from past FarProxy.BEGIN_M.

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb);
	ROUGHNESS = UV2.x;
	METALLIC = UV2.y;
	CLEARCOAT = COLOR.a;
	CLEARCOAT_ROUGHNESS = 0.15;
}
