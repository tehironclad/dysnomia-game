shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;

// Biome colors — set from BiomeSystem via GDScript
uniform vec4 vegetation_base_color : source_color = vec4(0.18, 0.22, 0.15, 1.0);
uniform vec4 vegetation_tip_color : source_color = vec4(0.25, 0.40, 0.22, 1.0);
uniform vec4 bioluminescence_color : source_color = vec4(0.08, 0.25, 0.45, 1.0);

// Territory state — driven by on-chain data
uniform float territory_activity : hint_range(0.0, 1.0) = 0.0;
uniform float territory_power : hint_range(0.0, 1.0) = 0.0;
uniform vec3 power_tint = vec3(0.0);

// Beat shockwave — vegetation reaction
uniform float beat_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 beat_origin = vec3(0.0, 0.0, 60.0);

// Transmission / backlight (from OWDB grass shader)
uniform float transmission_strength : hint_range(0.0, 2.0) = 0.8;
uniform vec4 transmission_color : source_color = vec4(0.4, 0.7, 0.3, 1.0);
uniform float transmission_falloff : hint_range(0.1, 5.0) = 2.5;
uniform float backlight_strength : hint_range(0.0, 2.0) = 1.2;

// Wind — tuned for low gravity (slower, wider than Earth grass)
uniform float wind_strength : hint_range(0.0, 1.0) = 0.15;
uniform float wind_speed : hint_range(0.0, 2.0) = 0.3;
uniform float wave_size : hint_range(1.0, 40.0) = 25.0;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float gust_strength : hint_range(0.0, 1.0) = 0.25;
uniform float turbulence_amount : hint_range(0.0, 2.0) = 0.4;

// Blade curve and specular
uniform float blade_curve : hint_range(0.0, 2.0) = 1.2;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.7;
uniform float roughness_tip : hint_range(0.0, 1.0) = 0.35;

// Distance fade (from OWDB — width shrink + ground sink)
uniform float fade_start : hint_range(0.0, 200.0) = 40.0;
uniform float fade_end : hint_range(1.0, 200.0) = 80.0;

// Height scaling
uniform float height_min : hint_range(0.0, 2.0) = 0.15;
uniform float height_max : hint_range(0.0, 3.0) = 0.6;

varying float height_factor;
varying vec3 world_position;

// ── Noise functions for wind (from OWDB) ──

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return value;
}

void vertex() {
	height_factor = UV.y;

	// World position for wind calculations
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance for LOD fade
	vec3 camera_position = INV_VIEW_MATRIX[3].xyz;
	float distance_to_camera = length(world_position - camera_position);

	// Distance-based fade (from OWDB: width shrink + ground sink)
	float distance_fade = 1.0;
	if (distance_to_camera > fade_start) {
		distance_fade = 1.0 - smoothstep(fade_start, fade_end, distance_to_camera);
	}

	// Height scaling
	float final_height = mix(height_min, height_max, territory_activity);
	VERTEX.y *= final_height;

	// Width shrink at distance (OWDB effect 1)
	VERTEX.x *= distance_fade;

	// Ground sink at distance (OWDB effect 2)
	float ground_offset = final_height * (1.0 - distance_fade);
	vec3 world_offset = vec3(0.0, -ground_offset, 0.0);
	vec3 local_offset = (inverse(MODEL_MATRIX) * vec4(world_offset, 0.0)).xyz;
	VERTEX += local_offset;

	// Wind animation (only for visible, upper vertices)
	if (height_factor > 0.01 && distance_fade > 0.01) {
		float blade_variation = hash(world_position.xz * 0.1);

		vec2 wind_dir_norm = normalize(wind_direction);
		vec2 wind_pos = world_position.xz + TIME * wind_speed * wind_dir_norm;

		// Base wind — FBM gives natural variation
		float base_wind = fbm(wind_pos * 0.02) * 2.0 - 1.0;

		// Rolling waves — wider than OWDB (low gravity = longer wavelengths)
		float wave_distance = dot(world_position.xz, wind_dir_norm);
		float wave_phase = wave_distance / wave_size - TIME * wind_speed * 0.3;
		float rolling_wave = sin(wave_phase + blade_variation * 3.14159) * 0.25;

		// Cross-wind turbulence
		float turb_x = fbm(wind_pos * 0.08 + vec2(0.0, TIME * 1.2)) * 2.0 - 1.0;
		float turb_z = fbm(wind_pos * 0.08 + vec2(100.0, TIME * 0.9)) * 2.0 - 1.0;

		// Gusts — occasional stronger surges
		float gust_phase = TIME * 0.2 + blade_variation * 6.28;
		float gust = (sin(gust_phase) * 0.5 + 0.5) * gust_strength;
		gust = smoothstep(0.6, 1.0, gust);

		float main_wind = (base_wind + rolling_wave) * (1.0 + gust);
		vec2 turb_wind = vec2(turb_x, turb_z) * turbulence_amount * 0.25;

		// Height-squared falloff (tips move more than base)
		float wind_height = height_factor * height_factor;

		vec3 wind_offset = vec3(
			wind_dir_norm.x * main_wind * wind_strength * wind_height,
			0.0,
			wind_dir_norm.y * main_wind * wind_strength * wind_height
		);
		wind_offset.x += turb_wind.x * wind_strength * wind_height;
		wind_offset.z += turb_wind.y * wind_strength * wind_height;

		// Low-gravity vertical bounce — alien tendrils reach upward
		float vertical_bounce = sin(TIME * 0.5 + blade_variation * 12.0) * 0.03;
		wind_offset.y += vertical_bounce * wind_height * wind_strength;

		// Scale by distance fade to avoid popping
		wind_offset *= distance_fade;

		VERTEX += wind_offset;
	}

	// Beat shockwave push — blades push outward from beat station, then relax
	if (beat_flash > 0.01 && height_factor > 0.1) {
		vec2 to_blade = world_position.xz - beat_origin.xz;
		float dist_to_beat = length(to_blade);
		vec2 push_dir = normalize(to_blade + vec2(0.001));
		// Push strength: strong near station, fades with distance
		float push_strength = beat_flash * beat_flash * 2.0;
		push_strength *= max(0.0, 1.0 - dist_to_beat / 200.0);
		push_strength *= height_factor * height_factor;
		float push_fade = distance_fade;
		VERTEX.x += push_dir.x * push_strength * push_fade;
		VERTEX.z += push_dir.y * push_strength * push_fade;
		// Upward surge
		VERTEX.y += beat_flash * height_factor * 0.3 * push_fade;
	}
}

void fragment() {
	// Curved normal for blade depth (from OWDB)
	float blade_center = abs(UV.x - 0.5) * 2.0;
	float curve_factor = (1.0 - blade_center) * blade_curve;
	vec3 blade_normal = vec3(
		(UV.x - 0.5) * curve_factor,
		0.0,
		sqrt(1.0 - min(1.0, curve_factor * curve_factor * (UV.x - 0.5) * (UV.x - 0.5) * 4.0))
	);
	blade_normal = normalize(blade_normal);

	// Blend normal toward upward at tips (catches specular)
	vec3 upward_normal = vec3(0.0, 1.0, 0.0);
	blade_normal = mix(blade_normal, upward_normal, height_factor * 0.7);
	NORMAL = blade_normal;

	// Base color: blend from base to tip
	vec3 base_col = vegetation_base_color.rgb;
	vec3 tip_col = vegetation_tip_color.rgb;

	// Power tint modulation (from FAUNG scalars)
	base_col += power_tint * 0.15;
	tip_col += power_tint * 0.25;

	vec3 veg_color = mix(base_col, tip_col, height_factor);

	// Position-based variation (subtle)
	float pos_variation = hash(world_position.xz * 0.1) * 0.1;
	veg_color *= (1.0 + pos_variation);

	// Center highlight on blade
	float center_highlight = 1.0 - blade_center * 0.15;
	veg_color *= (0.75 + 0.25 * height_factor) * center_highlight;

	ALBEDO = veg_color;

	// Roughness: wetter/slimier at base, smoother at tips
	ROUGHNESS = mix(roughness_base, roughness_tip, height_factor);
	SPECULAR = 0.25;
	METALLIC = 0.0;

	// Backlight transmission (from OWDB — light shining through blades)
	vec3 view_dir = normalize(VIEW);
	float transmission_factor = height_factor * transmission_strength;
	float rim = 1.0 - max(0.0, dot(NORMAL, view_dir));
	rim = pow(rim, transmission_falloff) * transmission_factor;
	float backlight_factor = max(0.0, dot(NORMAL, -view_dir)) * transmission_factor;
	BACKLIGHT = transmission_color.rgb * backlight_strength;

	// Emission: bioluminescence + transmission glow
	vec3 bio_emission = bioluminescence_color.rgb * territory_power * height_factor * 0.25;
	vec3 trans_glow = transmission_color.rgb * rim * 0.25;
	trans_glow += transmission_color.rgb * backlight_factor * 0.15;

	// Beat flash bioluminescence surge — all vegetation glows bright
	vec3 beat_bio = bioluminescence_color.rgb * beat_flash * 2.0;
	beat_bio += beat_flash * vec3(0.2, 0.4, 0.8) * height_factor;

	EMISSION = bio_emission + trans_glow + beat_bio;
}
