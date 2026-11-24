shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Outfits (Outfits / OutfitTailor). The Quaternius garment atlases are
// re-coloured from a mask (tools/outfit_masks.gd): R light cloth, G leather,
// B metal, A fabric detail ÷ 2. Per-vertex COLOR says which part a vertex
// belongs to: r = below the waist, g = footwear, b = accent piece (hood,
// pauldrons). Tailored pieces (textured = false) carry a slot index in
// COLOR.r × 15 instead: 0 main, 1 light, 2 bottom, 3 leather, 4 boots,
// 5 metal, 6 accent, 7 skin, 8 trim (glows).

uniform bool textured = true;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec3 col_main : source_color = vec3(0.2);
uniform vec3 col_light : source_color = vec3(0.8);
uniform vec3 col_bottom : source_color = vec3(0.15);
uniform vec3 col_leather : source_color = vec3(0.1);
uniform vec3 col_boots : source_color = vec3(0.05);
uniform vec3 col_metal : source_color = vec3(0.6);
uniform vec3 col_accent : source_color = vec3(0.5);
uniform vec3 col_skin : source_color = vec3(0.7, 0.5, 0.4);
uniform vec3 col_trim : source_color = vec3(0.45, 0.85, 1.0);
uniform float trim_energy = 1.8;
uniform float grey = 0.0;

vec3 slot_color(int s) {
	if (s == 0) return col_main;
	if (s == 1) return col_light;
	if (s == 2) return col_bottom;
	if (s == 3) return col_leather;
	if (s == 4) return col_boots;
	if (s == 5) return col_metal;
	if (s == 6) return col_accent;
	if (s == 7) return col_skin;
	return col_trim;
}

void fragment() {
	vec3 c;
	float rough = 0.75;
	float metal = 0.0;
	if (textured) {
		vec4 m = texture(mask_tex, UV);
		vec3 orm = texture(orm_tex, UV).rgb;
		float lower = COLOR.r;
		float boots = COLOR.g;
		float accent = COLOR.b;
		vec3 cloth = mix(mix(col_main, col_bottom, lower), col_accent, accent);
		vec3 light = mix(mix(col_light, col_bottom * 1.15, lower), col_accent * 1.2, accent);
		float cl = clamp(1.0 - m.r - m.g - m.b, 0.0, 1.0);
		c = cloth * cl + light * m.r + col_leather * m.g + col_metal * m.b;
		vec3 shoe = mix(col_boots, col_boots * 1.35 + 0.02, m.r);
		c = mix(c, shoe, boots * (1.0 - m.b));
		float detail = m.a * 2.0;
		c *= clamp(mix(1.0, detail, 0.8), 0.25, 1.8) * mix(1.0, orm.r, 0.6);
		rough = orm.g;
		metal = orm.b * 0.85;
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	} else {
		int s = int(round(COLOR.r * 15.0));
		c = slot_color(s);
		// Match the textured cloth, which carries its own fold shading and AO.
		if (s <= 6 && s != 5) c *= 0.72;
		if (s == 5) { metal = 0.8; rough = 0.35; }
		if (s == 8) { EMISSION = col_trim * trim_energy * (1.0 - grey); }
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(c, vec3(lum, lum, lum * 1.05), grey);
	ROUGHNESS = rough;
	METALLIC = metal;
}
