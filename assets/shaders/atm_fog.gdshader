// Screen-space atmospheric fog for Dysnomia.
// Adapted from Sky3D's AtmFog.gdshader (Copyright (c) 2023-2025 Cory Petkovsek, J. Cuellar).
// Only visible when territory is being terraformed (atmo_activity > 0).
// Fog density scales with atmo_activity — no terraforming = vacuum = no fog.

shader_type spatial;
render_mode blend_mix, cull_front, unshaded, fog_disabled;

// Territory state
uniform float atmo_activity : hint_range(0.0, 1.0) = 0.0;

// Fog parameters (tuned for 400m territory, low-gravity moon)
uniform float fog_density : hint_range(0.0, 0.01) = 0.0003;
uniform float fog_rayleigh_depth = 0.12;
uniform float fog_mie_depth = 0.0;
uniform float fog_falloff = 4.0;      // Higher = fog hugs ground more
uniform float fog_start = 0.0;
uniform float fog_end = 500.0;

// Sun / atmosphere
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);
uniform float atm_sun_intensity = 15.0;
uniform float atm_thickness = 0.5;
uniform float atm_darkness = 0.5;
uniform vec4 atm_day_tint : source_color = vec4(0.6, 0.65, 0.8, 1.0);
uniform vec4 atm_horizon_light_tint : source_color = vec4(0.85, 0.6, 0.4, 1.0);
uniform vec4 atm_night_tint : source_color = vec4(0.06, 0.07, 0.12, 1.0);

// Scattering coefficients
uniform vec3 atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 atm_beta_mie = vec3(0.00000003038);

// Mie phase parameters (sun only — no moon on Dysnomia)
uniform vec3 atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);
uniform vec4 atm_sun_mie_tint : source_color = vec4(1.0);
uniform float atm_sun_mie_intensity = 1.0;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// ── Inlined from Sky3D Common.gdshaderinc ──

const float RAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float MIE_ZENITH_LENGTH = 1.25e3;
const float THREE_OVER_EIGHT_PI = 3.0 / (8.0 * PI);

float clamp_to_unit(float value) {
	return clamp(value, 0.0, 1.0);
}

vec3 clamp_rgb_to_unit(vec3 value) {
	return clamp(value.rgb, 0.0, 1.0);
}

vec3 apply_photo_tonemap(vec3 color, float exposure, float level) {
	color.rgb *= exposure;
	return mix(color.rgb, 1.0 - exp(-color.rgb), level);
}

float calc_rayleigh_phase(float mu) {
	return THREE_OVER_EIGHT_PI * (1.0 + mu * mu);
}

float calc_mie_phase(float mu, vec3 partial) {
	float denominator = partial.y - partial.z * mu;
	float safe_denominator = max(denominator, 0.0001);
	return PI * 4.0 * partial.x * pow(safe_denominator, -1.5);
}

void calc_simple_optical_depth(float y, out float sr, out float sm) {
	y = max(0.03, y + 0.03);
	y = 1.0 / y;
	sr = y * RAYLEIGH_ZENITH_LENGTH;
	sm = y * MIE_ZENITH_LENGTH;
}

// ── Atmospheric scatter (simplified from Sky3D — no moon) ──

vec3 calc_atmospheric_scatter(float sr, float sm, float sun_mu, vec3 angle_mult, float depth) {
	vec3 beta_mie = atm_beta_mie;
	vec3 beta_ray = atm_beta_ray * atm_thickness;

	vec3 extc_factor = clamp_rgb_to_unit(exp(-(beta_ray * sr + beta_mie * sm)));

	float extc_ff = mix(clamp_to_unit(atm_thickness * 0.5), 1.0, angle_mult.x);
	vec3 final_extc_factor = mix(1.0 - extc_factor, (1.0 - extc_factor) * extc_factor, extc_ff);

	float rayleigh_phase = calc_rayleigh_phase(sun_mu);
	vec3 BRT = beta_ray * rayleigh_phase * clamp_to_unit(depth * fog_rayleigh_depth);
	vec3 BMT = beta_mie * calc_mie_phase(sun_mu, atm_sun_partial_mie_phase);
	BMT *= atm_sun_mie_intensity * atm_sun_mie_tint.rgb * clamp_to_unit(depth * fog_mie_depth);

	vec3 BRMT = (BRT + BMT) / (beta_ray + beta_mie);
	vec3 scatter = atm_sun_intensity * (BRMT * final_extc_factor) * atm_day_tint.rgb * angle_mult.y;
	scatter = mix(scatter, scatter * (1.0 - extc_factor), atm_darkness);

	vec3 lcol = mix(atm_day_tint.rgb, atm_horizon_light_tint.rgb, angle_mult.x);
	vec3 nscatter = (1.0 - extc_factor) * atm_night_tint.rgb * clamp_to_unit(depth * fog_rayleigh_depth);

	return (scatter * lcol) + nscatter;
}

// ── Fog calculations ──

float calc_fog_exp(float depth, float density) {
	return 1.0 - clamp_to_unit(exp2(-depth * density));
}

float calc_fog_falloff(float y, float falloff) {
	return clamp_to_unit(exp(-y * falloff));
}

float calc_fog_distance(float depth) {
	float d = (fog_end - depth) / (fog_end - fog_start);
	return clamp_to_unit(1.0 - d);
}

void calc_coords(vec2 uv, float depth, mat4 cam_mat, mat4 inv_proj_mat,
	out vec3 view_dir, out vec3 world_pos) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = inv_proj_mat * vec4(ndc, 1.0);
	view_dir = view.xyz / view.w;
	view = cam_mat * view;
	view.xyz /= view.w;
	view.xyz -= (cam_mat * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	world_pos = view.xyz;
}

// ── Main ──

varying mat4 camera_matrix;
varying vec4 angle_mult;

void vertex() {
	// Full-screen quad: ignore model transform, fill viewport
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);

	angle_mult = vec4(
		clamp_to_unit(1.0 - sun_direction.y),
		clamp_to_unit(sun_direction.y + 0.45),
		clamp_to_unit(-sun_direction.y + 0.30),
		clamp_to_unit(-sun_direction.y + 0.60));

	camera_matrix = INV_VIEW_MATRIX;
}

void fragment() {
	// Early out if no atmosphere
	if (atmo_activity < 0.01) {
		ALPHA = 0.0;
	} else {

		float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;

		// Renderer-specific depth handling
		#ifndef CURRENT_RENDERER
			depth_raw = PROJECTION_MATRIX[3][2] > PROJECTION_MATRIX[2][2] ? depth_raw : depth_raw * 2.0 - 1.0;
		#else
			#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
				depth_raw = depth_raw * 2.0 - 1.0;
			#endif
		#endif

		// Exclude sky pixels (depth ≈ 1.0) — fog only on geometry
		if (depth_raw > 0.9999) {
			ALPHA = 0.0;
		} else {

			vec3 view; vec3 world_pos;
			calc_coords(SCREEN_UV, depth_raw, camera_matrix, INV_PROJECTION_MATRIX, view, world_pos);
			world_pos = normalize(world_pos);

			float linear_depth = -view.z;

			// Fog factor — density scales with atmo_activity
			float effective_density = fog_density * atmo_activity;
			float fog_factor = calc_fog_exp(linear_depth, effective_density);
			fog_factor *= calc_fog_falloff(world_pos.y, fog_falloff);
			fog_factor *= calc_fog_distance(linear_depth);

			// Atmospheric scattering color
			float sun_mu = dot(sun_direction, world_pos);
			float sr, sm;
			calc_simple_optical_depth(world_pos.y, sr, sm);
			vec3 scatter = calc_atmospheric_scatter(sr, sm, sun_mu, angle_mult.xyz, linear_depth);

			// Tonemap
			vec3 fog_color = apply_photo_tonemap(scatter, 1.0, 0.5);

			ALBEDO = fog_color;
			ALPHA = clamp_to_unit(fog_factor);
		}
	}
}
