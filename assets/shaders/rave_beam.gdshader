shader_type spatial;
// Light through haze (RaveHall): laser beams and spot cones as additive glows that fade along their
// length and soften at the edges (seen side-on). Colour per instance (MultiMesh COLOR); alpha in
// COLOR.a is the beam's strength. `cone` 1 = a spot cone (a unit-height cylinder, its top at the
// light), 0 = a laser box (a unit box along −Z from +0.5, the emitter, to −0.5).

render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float strength = 1.6;
uniform float cone = 0.0;
uniform float fade_start = 0.0;

varying float along;

void vertex() {
	along = cone > 0.5 ? clamp(0.5 - VERTEX.y, 0.0, 1.0) : clamp(0.5 - VERTEX.z, 0.0, 1.0);
}

void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = cone > 0.5 ? pow(face, 1.6) : 1.0;
	float fade = 1.0 - smoothstep(fade_start, 1.0, along);
	if (cone > 0.5) {
		fade *= fade * smoothstep(0.0, 0.06, along) * 1.4;
	}
	ALBEDO = COLOR.rgb * strength * COLOR.a * soft * fade;
}
