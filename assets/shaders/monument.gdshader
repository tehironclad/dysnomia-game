shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Monument PBR stone/jade shader
// Procedural stone texture with jade veins, carved inscriptions, weathering, and energy emission.
// Driven by territory power and activity from on-chain state.

uniform vec3 accent_color : source_color = vec3(0.5, 0.7, 1.0);
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform float territory_activity : hint_range(0.0, 1.0) = 0.0;
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float wall_darken : hint_range(0.0, 1.0) = 0.0;
uniform vec3 power_tint = vec3(0.0, 0.0, 0.0);

// Stone appearance
uniform vec3 stone_color_base : source_color = vec3(0.22, 0.21, 0.19);
uniform vec3 stone_color_vein : source_color = vec3(0.18, 0.25, 0.20);
uniform float stone_roughness : hint_range(0.3, 1.0) = 0.75;

// ─── Hash / Noise ────────────────────────────────────────────────
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise (smooth)
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Cubic hermite

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM with domain warping for organic stone grain
float fbm_warped(vec2 p, int octaves) {
	// Domain warp: shift sample point by noise
	vec2 warp = vec2(
		value_noise(p + vec2(0.0, 0.0)),
		value_noise(p + vec2(5.2, 1.3))
	);
	p += warp * 0.8;

	float val = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < octaves; i++) {
		val += amp * value_noise(p * freq);
		freq *= 2.0;
		amp *= 0.5;
	}
	return val;
}

// Voronoi for jade vein structure
float voronoi_cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float min_dist = 1.0;
	float second_dist = 1.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 cell_point = hash22(i + neighbor);
			float d = length(neighbor + cell_point - f);
			if (d < min_dist) {
				second_dist = min_dist;
				min_dist = d;
			} else if (d < second_dist) {
				second_dist = d;
			}
		}
	}

	// Edge distance = difference between nearest two cell centers
	return second_dist - min_dist;
}

// ─── Fragment ────────────────────────────────────────────────────

void fragment() {
	// Triplanar UV coords from world position
	vec3 wp = VERTEX;
	vec3 n_abs = abs(NORMAL);
	// Triplanar weights
	vec3 blend_w = pow(n_abs, vec3(4.0));
	blend_w /= (blend_w.x + blend_w.y + blend_w.z);

	// ── Stone base texture (multi-scale FBM) ──
	float stone_x = fbm_warped(wp.yz * 0.3, 4);
	float stone_y = fbm_warped(wp.xz * 0.3, 4);
	float stone_z = fbm_warped(wp.xy * 0.3, 4);
	float stone_noise = stone_x * blend_w.x + stone_y * blend_w.y + stone_z * blend_w.z;

	// Micro grain layer (high frequency)
	float grain_x = value_noise(wp.yz * 8.0);
	float grain_y = value_noise(wp.xz * 8.0);
	float grain_z = value_noise(wp.xy * 8.0);
	float grain = grain_x * blend_w.x + grain_y * blend_w.y + grain_z * blend_w.z;

	// ── Jade veins (Voronoi crack pattern) ──
	float vein_x = voronoi_cracks(wp.yz * 1.2);
	float vein_y = voronoi_cracks(wp.xz * 1.2);
	float vein_z = voronoi_cracks(wp.xy * 1.2);
	float veins = vein_x * blend_w.x + vein_y * blend_w.y + vein_z * blend_w.z;
	float vein_mask = smoothstep(0.0, 0.08, veins); // 1 = solid stone, 0 = vein center

	// ── Stone block courses (horizontal lines) ──
	float block_scale = 3.5;
	float block_line_y = fract(wp.y * block_scale);
	float mortar_y = smoothstep(0.0, 0.03, block_line_y) * smoothstep(1.0, 0.97, block_line_y);
	// Vertical mortar lines offset per row
	float row_offset = floor(wp.y * block_scale) * 0.5;
	float block_line_xz = fract((wp.x + wp.z + row_offset) * block_scale * 0.5);
	float mortar_xz = smoothstep(0.0, 0.04, block_line_xz) * smoothstep(1.0, 0.96, block_line_xz);
	float mortar = mortar_y * mortar_xz;
	// Only show mortar on walls (wall_darken > 0)
	mortar = mix(1.0, mortar, wall_darken * 0.7);

	// ── Base albedo ──
	vec3 stone_col = mix(stone_color_base, stone_color_vein, stone_noise * 0.6);
	// Jade vein coloring: slightly green-shifted in cracks
	vec3 jade_color = accent_color * 0.3 + vec3(0.05, 0.12, 0.08);
	stone_col = mix(jade_color, stone_col, vein_mask);
	// Grain detail
	stone_col *= 0.85 + grain * 0.3;
	// Mortar darkening in gaps between blocks
	stone_col *= 0.3 + mortar * 0.7;
	// Wall darkening factor
	stone_col *= 1.0 - wall_darken * 0.35;

	ALBEDO = stone_col;

	// ── Roughness (veins are smoother/polished, stone is rough) ──
	float base_rough = stone_roughness + grain * 0.1 - stone_noise * 0.08;
	ROUGHNESS = mix(0.3, base_rough, vein_mask); // Vein = smooth jade, stone = rough
	ROUGHNESS += wall_darken * 0.15;

	// ── Metallic (jade veins have slight metallic sheen) ──
	METALLIC = mix(0.15, 0.02, vein_mask);

	// ── Normal map (procedural from noise derivatives) ──
	float eps = 0.5;
	vec2 sample_uv = wp.xz * 0.3;
	float h_c = fbm_warped(sample_uv, 3);
	float h_r = fbm_warped(sample_uv + vec2(eps, 0.0), 3);
	float h_u = fbm_warped(sample_uv + vec2(0.0, eps), 3);
	vec3 proc_normal = normalize(vec3(
		(h_c - h_r) / eps * 1.5,
		1.0,
		(h_c - h_u) / eps * 1.5
	));
	// Transform to tangent space (approximate — good enough for box meshes)
	NORMAL_MAP = proc_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6 + wall_darken * 0.4; // Walls get deeper normal detail

	// ── Ambient Occlusion ──
	// Mortar gaps are darker (crevice AO)
	float ao = mortar * 0.7 + 0.3;
	// Veins are slightly occluded
	ao *= 0.85 + vein_mask * 0.15;
	AO = ao;
	AO_LIGHT_AFFECT = 0.8;

	// ── Carved inscription runes (animated UV-scrolled glow) ──
	// Vertical bands with rune-like pattern
	float rune_uv_x = wp.x * 2.5 + wp.z * 0.8;
	float rune_uv_y = wp.y * 4.0;
	float rune_scroll = TIME * 0.3 * (1.0 + territory_activity * 2.0);

	// Multiple overlapping sine waves for organic rune shapes
	float rune1 = sin(rune_uv_x * 6.0 + rune_uv_y * 3.0 - rune_scroll) * 0.5 + 0.5;
	float rune2 = sin(rune_uv_x * 3.0 - rune_uv_y * 5.0 + rune_scroll * 0.7) * 0.5 + 0.5;
	float rune3 = sin(rune_uv_x * 1.5 + rune_uv_y * 8.0 - rune_scroll * 1.3) * 0.5 + 0.5;
	float rune = rune1 * rune2 * rune3;
	// Sharpen to thin glowing lines
	rune = smoothstep(0.55, 0.65, rune);
	// Only visible in vein areas (jade channels glow)
	rune *= (1.0 - vein_mask) * 2.0;
	rune = clamp(rune, 0.0, 1.0);

	// ── Vertical energy lines (legacy, enhanced) ──
	float line_speed = 2.0 + territory_activity * 3.0;
	float energy_lines = sin(wp.y * 8.0 - TIME * line_speed) * 0.5 + 0.5;
	energy_lines *= sin(wp.y * 3.0 - TIME * line_speed * 0.7) * 0.5 + 0.5;
	energy_lines = smoothstep(0.35, 0.65, energy_lines);

	// ── Fresnel edge glow ──
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	// ── Weathering: edge wear via curvature approximation ──
	// Use normal variation as proxy for curvature (edges where normals change rapidly)
	float curvature_proxy = 1.0 - abs(dot(NORMAL, vec3(0.0, 1.0, 0.0)));
	// Upward-facing surfaces get subtle moss tint when territory has power
	float moss_factor = clamp(NORMAL.y, 0.0, 1.0) * territory_power * 0.15;
	vec3 moss_color = vec3(0.15, 0.25, 0.12);
	ALBEDO = mix(ALBEDO, moss_color, moss_factor);
	// Edge brightening (weathered exposed stone is lighter)
	ALBEDO += curvature_proxy * 0.04;

	// ── Combine emission ──
	float power_factor = 0.15 + territory_power * 0.85;
	vec3 emission_color = accent_color + power_tint;

	float emission_strength = 0.0;
	// Rune glow (primary new feature)
	emission_strength += rune * 1.2;
	// Energy line glow (reduced weight vs old shader)
	emission_strength += energy_lines * 0.25 * (1.0 - wall_darken);
	// Fresnel rim
	emission_strength += fresnel * 0.5;
	// Jade vein subtle glow
	emission_strength += (1.0 - vein_mask) * 0.15;

	emission_strength *= power_factor * glow_intensity;

	EMISSION = emission_color * emission_strength;
}
