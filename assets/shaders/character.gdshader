shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Character PBR shader for the teddy bear astronaut.
// Mode 0: Fur — fiber micro-texture, Kajiya-Kay specular, subsurface scattering
// Mode 1: Suit — multi-layer EVA suit fabric with seams, wear, micro-fiber
// Mode 2: Visor — layered glass with depth-tinted reflections, rainbowing
// Mode 3: Metal — brushed steel with anodized color, micro-scratches

uniform int surface_mode : hint_range(0, 3) = 1;

// Base appearance
uniform vec3 base_color : source_color = vec3(0.9, 0.9, 0.92);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.5;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;

// Emission (unused by default — only shield flash)
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_strength : hint_range(0.0, 3.0) = 0.0;

// Territory-driven energy
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform vec3 power_accent : source_color = vec3(0.3, 0.5, 1.0);

// Shield/damage flash
uniform float shield_flash : hint_range(0.0, 1.0) = 0.0;

// ─── Noise Functions ────────────────────────────────────────────────
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	v += 0.5 * value_noise(p); p *= 2.01;
	v += 0.25 * value_noise(p); p *= 2.01;
	v += 0.125 * value_noise(p); p *= 2.01;
	v += 0.0625 * value_noise(p);
	return v;
}

// Voronoi-based cell noise for panel/plate patterns
float voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 cell_pos = vec2(hash21(i + neighbor), hash21(i + neighbor + vec2(7.0, 13.0)));
			float d = length(neighbor + cell_pos - f);
			min_dist = min(min_dist, d);
		}
	}
	return min_dist;
}

void fragment() {
	// Triplanar UV from object-space vertex
	vec3 wp = VERTEX;
	vec3 n_abs = abs(NORMAL);
	vec3 bw = pow(n_abs, vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);

	// Triplanar UV for consistent mapping
	vec2 uv_xz = wp.xz * bw.y + wp.xy * bw.z + wp.yz * bw.x;

	// Fresnel
	float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - NdotV, 3.5);

	// Curvature approximation from screen-space derivatives
	vec3 dn = fwidth(NORMAL);
	float curvature = clamp(length(dn) * 15.0, 0.0, 1.0);

	// ── Mode: Fur ───────────────────────────────────────────────
	if (surface_mode == 0) {
		vec2 fur_uv = wp.xy * 40.0;
		float fiber = value_noise(fur_uv + vec2(wp.z * 20.0, 0.0));
		float fiber2 = value_noise(fur_uv * 1.7 + vec2(0.0, wp.z * 15.0));

		// Kajiya-Kay anisotropic specular
		vec3 fiber_dir = normalize(vec3(0.1, 1.0, 0.05));
		float sin_th = length(cross(fiber_dir, normalize(VERTEX - VERTEX * dot(VERTEX, VIEW))));
		float aniso_spec = pow(sin_th, 8.0) * 0.15;

		ALBEDO = base_color * (0.85 + fiber * 0.15 + fiber2 * 0.1);
		ROUGHNESS = base_roughness - fiber * 0.08 + 0.05;
		METALLIC = 0.0;
		SPECULAR = 0.3 + aniso_spec;
		BACKLIGHT = base_color * 0.15;

		float eps = 0.02;
		float h_c = value_noise(fur_uv);
		float h_r = value_noise(fur_uv + vec2(eps, 0.0));
		float h_u = value_noise(fur_uv + vec2(0.0, eps));
		NORMAL_MAP = normalize(vec3((h_c - h_r) / eps, 1.0, (h_c - h_u) / eps)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.3;

		EMISSION = vec3(0.0);
	}

	// ── Mode: Suit Fabric (AAA) ─────────────────────────────────
	else if (surface_mode == 1) {
		// Layer 1: Woven Kevlar/Nomex weave pattern (tight diagonal twill)
		vec2 weave_uv = uv_xz * 120.0;
		float warp = sin(weave_uv.x * 3.14159) * 0.5 + 0.5;
		float weft = sin(weave_uv.y * 3.14159) * 0.5 + 0.5;
		float twill = sin((weave_uv.x + weave_uv.y) * 2.2) * 0.5 + 0.5;
		float weave = 0.92 + (warp * weft * 0.04) + (twill * 0.04);

		// Layer 2: Micro-fiber fuzz (suit surface isn't perfectly smooth)
		float micro_fuzz = value_noise(uv_xz * 200.0) * 0.06;

		// Layer 3: Seam lines — horizontal and vertical stitching
		float seam_h = 1.0 - smoothstep(0.0, 0.015, abs(fract(wp.y * 3.0) - 0.5));
		float seam_v = 1.0 - smoothstep(0.0, 0.015, abs(fract(uv_xz.x * 4.0) - 0.5));
		float seams = max(seam_h, seam_v) * 0.15;

		// Layer 4: Panel boundaries — larger segmentation (suit armor plates)
		float panels = voronoi(uv_xz * 6.0);
		float panel_edge = 1.0 - smoothstep(0.02, 0.06, panels);

		// Layer 5: Wear & scuff marks (concentrated at edges/joints via curvature)
		float wear_noise = fbm2(uv_xz * 15.0);
		float wear = wear_noise * curvature * 0.25;

		// Combine layers into final color
		vec3 suit_color = base_color * weave;
		suit_color -= vec3(micro_fuzz * 0.5);  // Slight darkening from fuzz
		suit_color = mix(suit_color, suit_color * 0.7, seams);  // Darker at seams
		suit_color = mix(suit_color, suit_color * 0.85, panel_edge * 0.4);  // Panel edges
		suit_color = mix(suit_color, suit_color * 1.15, wear);  // Lighter scuffs at edges

		ALBEDO = clamp(suit_color, vec3(0.0), vec3(1.0));

		// Roughness: smoother at panels, rougher at seams and edges
		float suit_rough = base_roughness;
		suit_rough += micro_fuzz * 0.3;  // Fuzz makes surface rougher
		suit_rough += seams * 0.15;       // Seams rougher
		suit_rough -= (1.0 - curvature) * 0.05;  // Flat areas slightly smoother
		ROUGHNESS = clamp(suit_rough, 0.15, 0.95);
		METALLIC = base_metallic;

		// Normal map: weave texture + seam indentations
		float eps = 0.008;
		float n_c = value_noise(weave_uv);
		float n_r = value_noise(weave_uv + vec2(eps, 0.0));
		float n_u = value_noise(weave_uv + vec2(0.0, eps));
		vec3 weave_normal = normalize(vec3(
			(n_c - n_r) / eps,
			1.0,
			(n_c - n_u) / eps
		));
		// Blend in seam depression
		weave_normal.y -= seams * 2.0;
		weave_normal = normalize(weave_normal);
		NORMAL_MAP = weave_normal * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.25;

		// Edge highlight: curvature-based rim (like ambient occlusion / edge wear on real suits)
		float edge_highlight = pow(curvature, 1.5) * 0.03;
		ALBEDO += vec3(edge_highlight);

		EMISSION = vec3(0.0);
	}

	// ── Mode: Visor/Glass (AAA) ─────────────────────────────────
	else if (surface_mode == 2) {
		// Multi-layer tinted glass with depth gradient and reflection

		// Base: very dark tinted glass
		float gradient = smoothstep(-0.4, 0.6, NORMAL.y);
		vec3 glass_color = mix(base_color * 0.08, base_color * 0.25, gradient);

		// Layer 1: Anti-reflective coating rainbow (thin-film interference)
		float thin_film = sin(NdotV * 12.0 + 1.0) * 0.5 + 0.5;
		vec3 ar_tint = vec3(
			sin(thin_film * 6.28) * 0.03,
			sin(thin_film * 6.28 + 2.09) * 0.03,
			sin(thin_film * 6.28 + 4.18) * 0.03
		);
		glass_color += ar_tint;

		// Layer 2: Environment distortion (warped reflection of surroundings)
		vec2 distort_uv = wp.xz * 3.0;
		float distortion = value_noise(distort_uv + vec2(TIME * 0.02, 0.0)) * 0.02;
		glass_color += vec3(distortion);

		// Layer 3: Micro-scratches (very faint, only at glancing angles)
		float scratch_noise = value_noise(uv_xz * 300.0);
		float scratches = smoothstep(0.7, 0.75, scratch_noise) * fresnel * 0.06;
		glass_color += vec3(scratches);

		ALBEDO = clamp(glass_color, vec3(0.0), vec3(0.4));
		ROUGHNESS = 0.03 + scratches * 2.0;  // Mirror-smooth except at scratches
		METALLIC = 0.8;  // High metallic for reflections
		SPECULAR = 0.9;

		EMISSION = vec3(0.0);
	}

	// ── Mode: Metal Accent (AAA) ────────────────────────────────
	else {
		// Brushed aerospace alloy with micro-scratches and anodized finish

		// Layer 1: Directional brushing pattern (anisotropic)
		vec2 metal_uv = uv_xz * 80.0;
		float brush_main = value_noise(vec2(metal_uv.x * 6.0, metal_uv.y * 0.3));
		float brush_cross = value_noise(vec2(metal_uv.x * 0.3, metal_uv.y * 6.0)) * 0.3;
		float brush = brush_main + brush_cross;

		// Layer 2: Micro-scratches (random fine lines)
		float scratch1 = smoothstep(0.72, 0.74, value_noise(metal_uv * 3.0 + vec2(42.0, 17.0)));
		float scratch2 = smoothstep(0.74, 0.76, value_noise(metal_uv * 2.5 + vec2(13.0, 29.0)));
		float scratches = (scratch1 + scratch2) * 0.08;

		// Layer 3: Anodized color variation (subtle shift across surface)
		float anodize = fbm2(uv_xz * 8.0);
		vec3 anodized_color = base_color * (0.9 + anodize * 0.15);

		// Layer 4: Edge wear (curvature-based — metal is shinier at worn edges)
		float edge_polish = curvature * 0.15;

		ALBEDO = anodized_color * (0.92 + brush * 0.08);
		ALBEDO += vec3(scratches);  // Scratches appear lighter
		ALBEDO += vec3(edge_polish);  // Worn edges are brighter

		// Roughness: brushing direction creates anisotropy
		float metal_rough = base_roughness;
		metal_rough -= brush * 0.12;     // Brush marks are smoother
		metal_rough += scratches * 0.5;  // Scratches are rougher
		metal_rough -= edge_polish * 0.3; // Worn edges are polished
		ROUGHNESS = clamp(metal_rough, 0.08, 0.7);

		METALLIC = max(base_metallic, 0.6);  // Always metallic
		SPECULAR = 0.7 + edge_polish * 0.2;

		// Normal map: brushing direction
		float eps = 0.01;
		float bh_c = value_noise(metal_uv);
		float bh_r = value_noise(metal_uv + vec2(eps, 0.0));
		float bh_u = value_noise(metal_uv + vec2(0.0, eps));
		NORMAL_MAP = normalize(vec3(
			(bh_c - bh_r) / eps * 0.5,
			1.0,
			(bh_c - bh_u) / eps * 0.5
		)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.2;

		EMISSION = vec3(0.0);
	}

	// ── Shield flash overlay (all modes) ──
	if (shield_flash > 0.01) {
		float hex_scale = 8.0;
		vec2 hex_uv = wp.xz * hex_scale;
		float hex_pattern = sin(hex_uv.x * 3.0 + hex_uv.y * 1.7) *
		                    sin(hex_uv.x * 1.3 - hex_uv.y * 2.9);
		hex_pattern = smoothstep(0.0, 0.3, abs(hex_pattern));

		vec3 shield_color = power_accent * 2.0;
		EMISSION += shield_color * shield_flash * (0.5 + hex_pattern * 0.5);
		ALBEDO = mix(ALBEDO, shield_color * 0.3, shield_flash * 0.3);
	}
}
