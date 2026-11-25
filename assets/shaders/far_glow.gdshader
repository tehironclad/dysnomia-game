shader_type spatial;
// The fair's far stand-ins (FarProxy): every plain glow (neon, lamp lenses, sign faces) of a
// group drawn as ONE surface. Per vertex: COLOR.rgb = the emission colour (sRGB), COLOR.a = the
// albedo as a share of it, UV2 = (emission energy, roughness). Materials animated at runtime
// (FarProxy.KEEP_META) keep their own surface instead.

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 e = to_linear(COLOR.rgb);
	ALBEDO = e * COLOR.a;
	ROUGHNESS = UV2.y;
	EMISSION = e * UV2.x;
}
