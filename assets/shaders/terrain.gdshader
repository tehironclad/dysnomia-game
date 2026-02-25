shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Slope thresholds
uniform float slope_grass_max : hint_range(0.0, 1.0) = 0.75;
uniform float slope_rock_min : hint_range(0.0, 1.0) = 0.4;

// Altitude thresholds
uniform float snow_line : hint_range(0.0, 100.0) = 35.0;
uniform float water_level : hint_range(-20.0, 20.0) = -5.0;

// Biome colors (driven by BiomeSystem — perceptually correct lunar regolith)
// Dysnomia surface: medium grey in direct sunlight, like real moon photos
uniform vec3 grass_color : source_color = vec3(0.44, 0.42, 0.40);   // Regolith primary
uniform vec3 grass_color_2 : source_color = vec3(0.38, 0.36, 0.34); // Regolith secondary
uniform vec3 rock_color : source_color = vec3(0.30, 0.28, 0.26);    // Exposed bedrock
uniform vec3 rock_color_2 : source_color = vec3(0.34, 0.32, 0.30);  // Bedrock variation
uniform vec3 soil_color : source_color = vec3(0.46, 0.44, 0.41);    // Fine dust
uniform vec3 snow_color : source_color = vec3(0.72, 0.74, 0.78);    // Nitrogen frost
uniform vec3 water_color : source_color = vec3(0.06, 0.06, 0.08);   // Deep crater shadow

// Texture scale for procedural detail
uniform float texture_scale : hint_range(0.01, 1.0) = 0.1;

// Territory state (Phase 3A) — driven by on-chain data
// Terraforming brings life to the dead moon surface
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform float territory_activity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 power_tint = vec3(0.0);

// Beat shockwave ripple — expanding energy ring from Meta Beat Station
uniform vec3 ripple_center = vec3(0.0, 0.0, 60.0);
uniform float ripple_radius = 0.0;
uniform float ripple_intensity = 0.0;
uniform vec3 ripple_color = vec3(0.4, 0.6, 1.0);
uniform float ripple_vertex_height : hint_range(0.0, 3.0) = 0.0;

// Cloud shadow projection — matches volumetric clouds in atmosphere.gdshader
uniform float cloud_shadow_density : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloud_shadow_sun_dir = vec3(0.0, 0.3, -1.0);
uniform float cloud_shadow_scale : hint_range(1.0, 20.0) = 12.0;
uniform float cloud_shadow_speed : hint_range(0.0, 0.05) = 0.001;

// Dual-scale texturing (inspired by Terrain3D) — reduces tiling at distance
uniform float dual_scale_near : hint_range(10.0, 200.0) = 60.0;
uniform float dual_scale_far : hint_range(50.0, 400.0) = 150.0;
uniform float dual_scale_reduction : hint_range(0.1, 0.8) = 0.3;

// Anti-tiling (from OWDB) — breaks up visible noise repetition
uniform float anti_tile_strength : hint_range(0.0, 1.0) = 0.5;

// Procedural normal map intensity
uniform float normal_detail_strength : hint_range(0.0, 2.0) = 0.35;

// Parallax Occlusion Mapping — close-range depth illusion
uniform float pom_strength : hint_range(0.0, 0.5) = 0.0;
uniform float pom_distance : hint_range(10.0, 60.0) = 20.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float v_camera_dist; // Distance from camera for dual-scale blending
varying vec3 v_view_dir_tangent; // View direction in tangent space for POM

// ── Procedural noise functions ──

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453);
}

// ── OWDB-style hash4: returns 4 random values per tile coordinate ──
// Used for anti-tiling: per-tile UV offsets + scale variation
vec4 hash4(ivec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Anti-tiled noise (adapted from OWDB texture_no_tile) ──
// Samples noise 4 times per tile with per-tile random UV offsets + scale,
// then Hermite-interpolates across tile boundaries for seamless blending.
// This breaks visible repetition patterns in procedural noise.
float noise_at(vec2 p) {
	// Anti-tiling disabled or zero strength → plain noise
	if (anti_tile_strength < 0.01) {
		return noise(p);
	}

	ivec2 iuv = ivec2(floor(p));
	vec2 fuv = fract(p);

	// Per-tile random offsets + scale for 4 neighboring tiles
	vec4 ofa = hash4(iuv + ivec2(0, 0));
	vec4 ofb = hash4(iuv + ivec2(1, 0));
	vec4 ofc = hash4(iuv + ivec2(0, 1));
	vec4 ofd = hash4(iuv + ivec2(1, 1));

	// Random UV offsets: ±0.5 * strength
	vec2 off_a = (ofa.xy - 0.5) * anti_tile_strength;
	vec2 off_b = (ofb.xy - 0.5) * anti_tile_strength;
	vec2 off_c = (ofc.xy - 0.5) * anti_tile_strength;
	vec2 off_d = (ofd.xy - 0.5) * anti_tile_strength;

	// Gentle scale variation: ±10% * strength
	float sc_a = 1.0 + (ofa.z - 0.5) * 0.1 * anti_tile_strength;
	float sc_b = 1.0 + (ofb.z - 0.5) * 0.1 * anti_tile_strength;
	float sc_c = 1.0 + (ofc.z - 0.5) * 0.1 * anti_tile_strength;
	float sc_d = 1.0 + (ofd.z - 0.5) * 0.1 * anti_tile_strength;

	// Sample noise at 4 jittered positions
	float sa = noise(p * sc_a + off_a);
	float sb = noise(p * sc_b + off_b);
	float sc = noise(p * sc_c + off_c);
	float sd = noise(p * sc_d + off_d);

	// Hermite interpolation for extra-smooth tile transitions
	vec2 b = fuv * fuv * (3.0 - 2.0 * fuv);
	b = b * b * (3.0 - 2.0 * b);

	return mix(mix(sa, sb, b.x), mix(sc, sd, b.x), b.y);
}

float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// ── Anti-tiled FBM — uses noise_at() for visibly tiling octaves ──
float fbm_at(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise_at(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// GPU micro-displacement — adds detail the CPU heightmap resolution can't capture
uniform float micro_displacement_strength : hint_range(0.0, 2.0) = 0.6;
uniform float micro_displacement_scale : hint_range(0.01, 0.5) = 0.08;
uniform float micro_displacement_distance : hint_range(20.0, 200.0) = 80.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Camera distance for dual-scale blending
	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_dist_raw = length(world_pos - cam_pos);

	// GPU micro-displacement — 2 octaves of noise add regolith detail
	// Only applied within micro_displacement_distance to save GPU
	if (micro_displacement_strength > 0.01 && cam_dist_raw < micro_displacement_distance) {
		float disp_fade = 1.0 - smoothstep(micro_displacement_distance * 0.5, micro_displacement_distance, cam_dist_raw);
		float n1 = noise(world_pos.xz * micro_displacement_scale * 4.0 + vec2(77.0, 33.0));
		float n2 = noise(world_pos.xz * micro_displacement_scale * 9.0 + vec2(13.0, 91.0)) * 0.5;
		float displacement_amount = (n1 + n2 - 0.75) * micro_displacement_strength * disp_fade;
		VERTEX.y += displacement_amount;
		world_pos.y += displacement_amount;
	}

	// Beat shockwave vertex displacement — ground rises at the ring front
	if (ripple_vertex_height > 0.001) {
		float dist_to_ripple = length(world_pos.xz - ripple_center.xz);
		float ring_width_v = 3.0 + ripple_radius * 0.05;
		float ring_dist_v = abs(dist_to_ripple - ripple_radius);
		float ring_lift = 1.0 - smoothstep(0.0, ring_width_v, ring_dist_v);
		// Trailing wake — ground stays slightly raised behind the ring
		float behind = ripple_radius - dist_to_ripple;
		float wake = smoothstep(0.0, ring_width_v * 3.0, behind)
		           * (1.0 - smoothstep(ring_width_v * 3.0, ring_width_v * 8.0, behind));
		float displacement = (ring_lift * 1.5 + wake * 0.4) * ripple_vertex_height;
		VERTEX.y += displacement;
		world_pos.y += displacement;
	}

	v_camera_dist = length(world_pos - cam_pos);

	// Tangent-space view direction for POM
	vec3 view_dir_world = normalize(cam_pos - world_pos);
	vec3 T = normalize(cross(vec3(0.0, 1.0, 0.0), world_normal + vec3(0.001)));
	vec3 B = cross(world_normal, T);
	v_view_dir_tangent = vec3(dot(view_dir_world, T), dot(view_dir_world, B), dot(view_dir_world, world_normal));
}

void fragment() {
	float slope = dot(world_normal, vec3(0.0, 1.0, 0.0));
	float height = world_pos.y;

	// ── Dual-scale blending factor (Terrain3D-inspired) ──
	// At distance, switch to lower-frequency noise to prevent visible tiling/repetition
	float far_factor = clamp(smoothstep(dual_scale_near, dual_scale_far, v_camera_dist), 0.0, 1.0);
	float near_scale = texture_scale;
	float far_scale = texture_scale * dual_scale_reduction;

	// Per-tile random rotation (detiling) — rotates far UVs to break alignment
	vec2 far_tile_center = floor(world_pos.xz * far_scale * 2.0 + vec2(0.5));
	float far_rot_angle = hash(far_tile_center) * 6.2832;
	float far_cos_a = cos(far_rot_angle);
	float far_sin_a = sin(far_rot_angle);
	vec2 far_uv_base = world_pos.xz * far_scale;
	vec2 far_uv_rotated = vec2(
		(far_uv_base.x - far_tile_center.x) * far_cos_a - (far_uv_base.y - far_tile_center.y) * far_sin_a + far_tile_center.x,
		(far_uv_base.x - far_tile_center.x) * far_sin_a + (far_uv_base.y - far_tile_center.y) * far_cos_a + far_tile_center.y
	);

	// ── Multi-scale procedural detail (anti-tiled via OWDB hash4 technique) ──
	// Near: high-frequency anti-tiled detail visible up close
	// Far: blended with lower-frequency rotated noise to hide repetition

	// Fine regolith grain — anti-tiled to prevent visible noise repeats
	float detail_fine_near = fbm_at(world_pos.xz * near_scale * 8.0, 3);
	float detail_fine_far = fbm(far_uv_rotated * 8.0 + vec2(11.0, 29.0), 2);
	float detail_fine = mix(detail_fine_near, detail_fine_far, far_factor);

	// Medium texture — surface variation (anti-tiled)
	float detail_med_near = fbm_at(world_pos.xz * near_scale * 3.7 + vec2(42.0, 17.0), 3);
	float detail_med_far = fbm(far_uv_rotated * 3.7 + vec2(42.0, 17.0), 2);
	float detail_med = mix(detail_med_near, detail_med_far, far_factor);

	// Broad patches — low frequency, less visible tiling; still anti-tile for consistency
	float detail_broad = fbm_at(world_pos.xz * near_scale * 0.3 + vec2(99.0, 55.0), 2);

	// ── Multi-scale crater detail (shader-space, for color only) ──

	// Large-scale crater-like features — anti-tiled for natural irregularity
	float large_crater = fbm_at(world_pos.xz * near_scale * 0.5 + vec2(7.0, 31.0), 3);
	float large_rim = smoothstep(0.35, 0.5, large_crater) * (1.0 - smoothstep(0.5, 0.65, large_crater));
	float large_bowl = smoothstep(0.5, 0.35, large_crater); // interior darkening

	// Medium craters — anti-tiled near, rotated far
	float med_crater_near = fbm_at(world_pos.xz * near_scale * 2.5 + vec2(51.0, 13.0), 3);
	float med_crater_far = fbm(far_uv_rotated * 2.5 + vec2(51.0, 13.0), 2);
	float med_crater = mix(med_crater_near, med_crater_far, far_factor);
	float med_rim = smoothstep(0.38, 0.52, med_crater) * (1.0 - smoothstep(0.52, 0.66, med_crater));

	// Micro-pitting — anti-tiled, only visible up close (saves GPU at distance)
	float micro_pit = fbm_at(world_pos.xz * near_scale * 15.0 + vec2(23.0, 67.0), 2) * (1.0 - far_factor);

	// Ejecta ray pattern — radial streaks from crater centers
	float ray_angle = atan(world_pos.z + 50.0, world_pos.x + 50.0);
	float ray_pattern = sin(ray_angle * 8.0) * 0.5 + 0.5;
	ray_pattern = ray_pattern * ray_pattern; // sharpen
	ray_pattern *= large_bowl * 0.5; // only visible near crater depressions

	// ── Triplanar blend weights for steep surfaces ──
	vec3 blend_weights = abs(world_normal);
	blend_weights = pow(blend_weights, vec3(4.0));
	blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z + 0.0001);

	// Triplanar noise for rock detail (prevents stretching on cliffs, anti-tiled)
	float tri_detail = noise_at(world_pos.xz * 0.3) * blend_weights.y
	                  + noise_at(world_pos.xy * 0.3) * blend_weights.z
	                  + noise_at(world_pos.yz * 0.3) * blend_weights.x;

	// ── Build regolith surface ──
	vec3 regolith = mix(grass_color, grass_color_2, detail_fine);
	// Micro-pitting variation — subtle brightness shifts from bombardment
	regolith += vec3((micro_pit - 0.5) * 0.02);
	// Crater rim brightening — fresh ejecta is lighter
	regolith += vec3(large_rim * 0.06 + med_rim * 0.03);
	// Crater interior darkening — accumulated shadow/older dust
	regolith -= vec3(large_bowl * 0.04);
	// Ejecta ray streaks — faint radial brightness
	regolith += vec3(ray_pattern * 0.02);

	// Exposed bedrock on steep slopes
	vec3 rock = mix(rock_color, rock_color_2, detail_med);
	rock += vec3(tri_detail * 0.04 - 0.02);

	// Fine dust accumulation in valleys
	vec3 dust = soil_color * (0.90 + detail_fine * 0.2);

	// Slope-based blending
	float regolith_factor = smoothstep(slope_rock_min, slope_grass_max, slope);
	vec3 base_color = mix(rock, mix(dust, regolith, regolith_factor), regolith_factor);

	// ── Height-based color variation ──
	// Valleys accumulate older, darker dust. Ridges expose fresher material.
	float height_norm = clamp((height + 10.0) / 50.0, 0.0, 1.0);
	base_color *= mix(0.88, 1.08, height_norm);

	// ── Space weathering gradient ──
	// Flat exposed surfaces darken faster from micrometeorite bombardment
	float weathering = mix(1.0, 0.94, regolith_factor * (1.0 - abs(height_norm - 0.5) * 2.0));
	base_color *= weathering;

	// ── Macro variation (inspired by Terrain3D) ──
	// Two-layer noise breaks up tiling at landscape scale — ±15% brightness
	float macro1 = fbm(world_pos.xz * 0.003 + vec2(71.0, 23.0), 2);
	float macro2 = fbm(world_pos.xz * 0.008 + vec2(13.0, 97.0), 2);
	float macro_factor = mix(0.85, 1.15, macro1 * 0.5 + macro2 * 0.5);
	// Less variation on steep cliffs (they already have natural visual breakup)
	macro_factor = mix(1.0, macro_factor, clamp(slope + 0.33, 0.0, 1.0));
	base_color *= macro_factor;

	// ── Nitrogen/methane frost overlay at high elevations ──
	float frost_factor = smoothstep(snow_line - 5.0, snow_line + 5.0, height);
	frost_factor *= smoothstep(0.3, 0.65, slope); // frost sticks to flatter surfaces
	frost_factor *= (0.9 + detail_fine * 0.2); // variation at frost edge
	base_color = mix(base_color, snow_color, clamp(frost_factor, 0.0, 1.0));

	// ── Crater pools — liquid fills low areas when territory is terraformed ──
	float shadow_factor = smoothstep(water_level + 1.5, water_level - 1.0, height);
	float pool_liquid = 0.0;

	if (shadow_factor > 0.01 && territory_power > 0.1) {
		// Liquid appears as territory is terraformed — filling craters
		float liquid_strength = smoothstep(0.1, 0.5, territory_power);
		pool_liquid = shadow_factor * liquid_strength;

		// Animated wave normals — two scrolling sine layers
		vec2 pool_uv = world_pos.xz * 0.3;
		float wave1 = sin(pool_uv.x * 3.0 + TIME * 0.8) * sin(pool_uv.y * 2.5 + TIME * 0.6);
		float wave2 = sin(pool_uv.x * 5.0 - TIME * 1.2 + 1.5) * sin(pool_uv.y * 4.0 + TIME * 0.9);
		float wave_combined = (wave1 * 0.6 + wave2 * 0.4) * pool_liquid * 0.02;

		// Depth-based color: darker center, lighter caustic edges
		float depth = smoothstep(water_level + 1.0, water_level - 2.0, height);
		vec3 shallow_color = water_color + vec3(0.04, 0.06, 0.10) + power_tint * 0.3;
		vec3 deep_color = water_color * 0.5;
		vec3 liquid_color = mix(shallow_color, deep_color, depth);

		// Caustic ripple pattern — bright shimmer
		float caustic = noise(pool_uv * 0.5 + vec2(TIME * 0.3, TIME * 0.2));
		caustic = smoothstep(0.4, 0.6, caustic) * (1.0 - depth) * 0.15;
		liquid_color += vec3(caustic) * vec3(0.5, 0.7, 1.0);

		// Apply liquid color
		base_color = mix(base_color, liquid_color, pool_liquid);

		// Bioluminescent emission glow
		float bio_glow = (0.02 + caustic * 0.5) * territory_power * pool_liquid;
		base_color += (power_tint + vec3(0.02, 0.04, 0.08)) * bio_glow;
	} else {
		// No liquid — just darken crater floors as before
		base_color = mix(base_color, water_color, shadow_factor);
	}

	// ── Territory power effects: terraforming brings life to dead moon ──
	if (territory_power > 0.01) {
		// As territory is terraformed, surface gains subtle color
		// Against the dark regolith, even small color shifts are dramatic
		float luma = dot(base_color, vec3(0.299, 0.587, 0.114));

		// Terraformed surface gets warmer, more saturated
		vec3 life_tint = vec3(0.02, 0.04, 0.01) * territory_power;
		base_color += life_tint;

		// Power tint from FAUNG scalars — alien bio-luminescence
		base_color += power_tint * territory_power * 0.2;

		// Rim glow on terrain edges — energy seeping through cracks
		float rim = 1.0 - slope;
		vec3 energy_color = vec3(0.06, 0.10, 0.18) + power_tint * 0.3;
		base_color += energy_color * rim * territory_power;

		// At high power, regolith starts to look less dead
		float vitality = territory_power * 0.3;
		vec3 vital_color = mix(base_color, base_color * vec3(1.05, 1.08, 1.02), vitality);
		base_color = vital_color;
	}

	// Territory activity effects: terraform operations leave visible marks
	float active_detail = 0.0;
	if (territory_activity > 0.01) {
		// Churned-up regolith from terraform work — freshly exposed subsurface
		active_detail = fbm(world_pos.xz * texture_scale * 7.0 + vec2(13.0, 37.0), 3);
		// Fresh excavation reveals slightly different mineral color
		vec3 subsurface = base_color * vec3(0.95, 0.92, 0.90);
		base_color = mix(base_color, subsurface, active_detail * territory_activity * 0.3);
	}

	// ── Beat shockwave — MASSIVE energy ring from Meta Beat Station ──
	float ripple_roughness_mod = 0.0;
	if (ripple_intensity > 0.001) {
		float dist_to_center = length(world_pos.xz - ripple_center.xz);

		// Primary ring — wide, bright, dramatic
		float ring_width = 3.0 + ripple_radius * 0.05;
		float ring_dist = abs(dist_to_center - ripple_radius);
		float ring = 1.0 - smoothstep(0.0, ring_width, ring_dist);

		// Precursor wave — thin fast ring racing ahead of main shockwave
		float precursor_radius = ripple_radius * 1.15 + 5.0;
		float precursor_dist = abs(dist_to_center - precursor_radius);
		float precursor = (1.0 - smoothstep(0.0, ring_width * 0.3, precursor_dist)) * 0.4;

		// Inner glow trail — wide, intense energy wake
		float trail_width = ring_width * 6.0;
		float behind_ring = ripple_radius - dist_to_center;
		float trail = smoothstep(0.0, trail_width, behind_ring)
		            * smoothstep(trail_width * 2.5, 0.0, behind_ring);

		// Scanning lines within the trail
		float scan_lines = sin(dist_to_center * 1.5 - TIME * 10.0) * 0.5 + 0.5;
		scan_lines = smoothstep(0.35, 0.65, scan_lines);

		// Ground cracking — noise-based glowing fractures along the ring path
		float crack_noise = noise(world_pos.xz * 0.8 + vec2(TIME * 2.0));
		float crack = smoothstep(0.6, 0.8, crack_noise) * trail * 0.6;

		// Combine: bright ring + precursor + trail + cracks
		float ripple_factor = (ring * 2.0 + precursor + trail * 0.4 * scan_lines + crack)
		                    * ripple_intensity;

		// Dramatic color shift and emission boost
		base_color = mix(base_color, ripple_color * 1.5, ripple_factor * 0.6);
		// Bright emission on the ring front (HDR bloom will catch this)
		base_color += ripple_color * ring * ripple_intensity * 2.5;
		base_color += ripple_color * precursor * ripple_intensity * 0.8;

		// Ring front gets very shiny (almost mirror-like energy surface)
		ripple_roughness_mod = (ring * 0.5 + precursor * 0.2) * ripple_intensity;
	}

	// ── Cloud shadows — projected from volumetric clouds overhead ──
	// Uses the same noise pattern as atmosphere.gdshader clouds
	if (cloud_shadow_density > 0.03) {
		// Project world position along sun direction to cloud plane
		vec2 shadow_uv = world_pos.xz;
		// Offset by sun direction to align shadows with overhead clouds
		float sun_y = max(cloud_shadow_sun_dir.y, 0.1);
		shadow_uv -= cloud_shadow_sun_dir.xz * (world_pos.y / sun_y) * 0.1;
		// Scale and animate to match cloud layer
		shadow_uv = shadow_uv * cloud_shadow_scale * 0.08;
		shadow_uv += vec2(TIME * cloud_shadow_speed * 40.0, TIME * cloud_shadow_speed * 12.0);

		// Multi-octave noise matching the cloud density sampling
		float shadow_noise = fbm(shadow_uv, 3);
		float shadow_mask = smoothstep(1.0 - cloud_shadow_density, 1.0 - cloud_shadow_density + 0.35, shadow_noise);

		// Darken terrain under cloud shadows — subtle dappled light
		base_color *= mix(1.0, 0.6, shadow_mask * clamp(cloud_shadow_density, 0.0, 0.8));
	}

	// ── Parallax Occlusion Mapping — depth illusion at close range ──
	vec2 pom_offset = vec2(0.0);
	if (pom_strength > 0.001 && v_camera_dist < pom_distance) {
		float pom_fade = 1.0 - smoothstep(pom_distance * 0.5, pom_distance, v_camera_dist);
		float effective_pom = pom_strength * pom_fade;

		vec2 view_dir_2d = normalize(v_view_dir_tangent.xy);
		float view_z = max(abs(v_view_dir_tangent.z), 0.1);

		// 4-step ray march through procedural heightmap
		float step_size = 0.25;
		float current_depth = 0.0;
		vec2 current_offset = vec2(0.0);
		vec2 delta_offset = view_dir_2d * effective_pom / (view_z * 4.0);

		for (int i = 0; i < 4; i++) {
			current_depth += step_size;
			current_offset += delta_offset;
			float h = noise(world_pos.xz * near_scale * 6.0 + current_offset * 30.0);
			h = 1.0 - h;
			if (h < current_depth) break;
		}
		pom_offset = current_offset;
	}

	// ── Procedural normal map — micro-detail surface bumps ──
	// Finite-difference derivatives of noise give tangent-space surface perturbation.
	// This adds visible surface grain that catches light, making the regolith feel 3D
	// instead of flat painted color. Scales with crater and detail noise.
	if (normal_detail_strength > 0.01) {
		float bump_scale = near_scale * 6.0;
		float eps = 0.15; // Finite difference step size

		// Sample noise at neighboring points for gradient (offset by POM)
		vec2 bump_uv = world_pos.xz * bump_scale + pom_offset * 30.0;
		float h_center = noise_at(bump_uv);
		float h_right  = noise_at(bump_uv + vec2(eps, 0.0));
		float h_up     = noise_at(bump_uv + vec2(0.0, eps));

		// Add medium-scale crater bumps
		vec2 crater_uv = world_pos.xz * near_scale * 2.5 + vec2(51.0, 13.0);
		float cr_center = noise_at(crater_uv);
		float cr_right  = noise_at(crater_uv + vec2(eps, 0.0));
		float cr_up     = noise_at(crater_uv + vec2(0.0, eps));

		// Third layer: ultra-fine regolith grain (high frequency)
		vec2 grain_uv = world_pos.xz * near_scale * 18.0 + vec2(37.0, 59.0);
		float gr_center = noise_at(grain_uv);
		float gr_right  = noise_at(grain_uv + vec2(eps * 0.5, 0.0));
		float gr_up     = noise_at(grain_uv + vec2(0.0, eps * 0.5));

		// Anisotropic slope streaks: elongated noise along downhill direction
		vec2 slope_dir = normalize(vec2(
			noise_at(world_pos.xz * near_scale * 0.8 + vec2(83.0, 11.0)) - 0.5,
			noise_at(world_pos.xz * near_scale * 0.8 + vec2(11.0, 83.0)) - 0.5
		) + vec2(0.001));
		vec2 streak_uv = world_pos.xz * near_scale * 5.0;
		// Project UV along slope direction for stretched streaks
		float streak_coord = dot(streak_uv, slope_dir);
		float streak_perp = dot(streak_uv, vec2(-slope_dir.y, slope_dir.x));
		float sk_center = noise(vec2(streak_coord * 0.5, streak_perp * 3.0));
		float sk_right  = noise(vec2(streak_coord * 0.5 + eps, streak_perp * 3.0));
		float sk_up     = noise(vec2(streak_coord * 0.5, streak_perp * 3.0 + eps));
		float streak_strength = (1.0 - slope) * 0.3; // Stronger on steep slopes

		// Combine fine + crater-scale + grain + streak derivatives
		float dx = (h_right - h_center)
		         + (cr_right - cr_center) * 0.5
		         + (gr_right - gr_center) * 0.25
		         + (sk_right - sk_center) * streak_strength;
		float dy = (h_up - h_center)
		         + (cr_up - cr_center) * 0.5
		         + (gr_up - gr_center) * 0.25
		         + (sk_up - sk_center) * streak_strength;

		// Fade out bumps at distance (they alias and shimmer)
		float bump_fade = 1.0 - far_factor;
		dx *= bump_fade;
		dy *= bump_fade;

		// Convert to tangent-space normal
		vec3 bump_normal = normalize(vec3(-dx * normal_detail_strength, -dy * normal_detail_strength, 1.0));
		// Map from [-1,1] to [0,1] for NORMAL_MAP
		NORMAL_MAP = bump_normal * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 1.0;
	}

	// ── Procedural Ambient Occlusion — cavity/convexity from terrain derivatives ──
	// Laplacian of heightfield approximated from noise samples detects
	// concave areas (crater bowls, valleys) vs convex areas (ridges, rims).
	float ao_sample_c = noise_at(world_pos.xz * near_scale * 1.5);
	float ao_sample_r = noise_at(world_pos.xz * near_scale * 1.5 + vec2(0.5, 0.0));
	float ao_sample_u = noise_at(world_pos.xz * near_scale * 1.5 + vec2(0.0, 0.5));
	float ao_sample_l = noise_at(world_pos.xz * near_scale * 1.5 - vec2(0.5, 0.0));
	float ao_sample_d = noise_at(world_pos.xz * near_scale * 1.5 - vec2(0.0, 0.5));
	float laplacian = (ao_sample_r + ao_sample_l + ao_sample_u + ao_sample_d) * 0.25 - ao_sample_c;
	// Slope-based AO: steep concave areas are darker
	float slope_ao = mix(0.7, 1.0, clamp(slope, 0.0, 1.0));
	// Height-based AO: deep areas naturally darker
	float height_ao = smoothstep(-15.0, 5.0, height) * 0.3 + 0.7;
	// Large crater bowl AO
	float crater_ao = 1.0 - large_bowl * 0.2;
	// Combine
	float ao = clamp(0.5 + laplacian * 4.0, 0.0, 1.0) * slope_ao * height_ao * crater_ao;
	AO = clamp(ao, 0.15, 1.0);

	// ── PBR outputs — NASA-accurate lunar surface properties ──
	ALBEDO = base_color;

	// Roughness: real lunar regolith is extremely rough (0.88-0.95)
	float roughness = 0.92; // powdery regolith, almost no specular
	roughness = mix(roughness, 0.88, 1.0 - regolith_factor); // exposed rock, slightly less rough
	roughness = mix(roughness, 0.5, clamp(frost_factor, 0.0, 1.0)); // frost is smoother
	roughness = mix(roughness, 0.94, shadow_factor); // crater floor dust, roughest

	// Micro-roughness variation — prevents uniform matte appearance
	float rough_variation = fbm(world_pos.xz * 0.15 + vec2(41.0, 73.0), 2) * 0.04 - 0.02;
	roughness += rough_variation;

	// Active terraforming polishes the surface slightly
	roughness -= territory_activity * 0.08;
	// High power = life emerging, surface becomes less dead/rough
	roughness -= territory_power * 0.15;
	// Beat shockwave ring polishes the surface briefly
	roughness -= ripple_roughness_mod;

	// Crater pool surfaces are very smooth and reflective
	if (pool_liquid > 0.01) {
		roughness = mix(roughness, 0.05, pool_liquid);
	}

	ROUGHNESS = clamp(roughness, 0.0, 1.0);

	// Lunar regolith is dielectric silicate — zero metallic
	float metallic_out = territory_power * 0.03;
	float specular_out = 0.3 + territory_power * 0.1;

	// Liquid pools get strong Fresnel reflections
	if (pool_liquid > 0.01) {
		metallic_out = mix(metallic_out, 0.1, pool_liquid);
		specular_out = mix(specular_out, 0.8, pool_liquid);
	}

	METALLIC = metallic_out;
	SPECULAR = specular_out;
}
