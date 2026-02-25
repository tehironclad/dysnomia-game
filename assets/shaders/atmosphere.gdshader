shader_type sky;

uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);
uniform float time_of_day : hint_range(0.0, 1.0) = 0.5;

// Sky colors — Dysnomia: thin atmosphere, dark sky but visible horizon glow during day
uniform vec3 day_zenith : source_color = vec3(0.08, 0.09, 0.18);     // Dark blue-grey — space visible
uniform vec3 day_horizon : source_color = vec3(0.14, 0.15, 0.25);    // Faint blue-grey haze
uniform vec3 sunset_color : source_color = vec3(0.30, 0.15, 0.08);   // Warm reddish glow
uniform vec3 night_zenith : source_color = vec3(0.002, 0.003, 0.012); // Pure space black
uniform vec3 night_horizon : source_color = vec3(0.005, 0.008, 0.025); // Barely perceptible

// Sun appearance — at ~96 AU the sun is a tiny brilliant point
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.95);
uniform float sun_size : hint_range(0.99, 1.0) = 0.99998;  // Even smaller than before

// Clouds — extremely sparse, only when territory is being terraformed
uniform float cloud_density : hint_range(0.0, 1.0) = 0.02;  // Nearly none by default
uniform float cloud_speed : hint_range(0.0, 0.05) = 0.001;
uniform float cloud_scale : hint_range(1.0, 20.0) = 12.0;

// Territory state (Phase 3A) — driven by on-chain data
uniform float latitude_factor : hint_range(-1.0, 1.0) = 0.0;
uniform float atmo_activity : hint_range(0.0, 1.0) = 0.0;

// Beat shockwave — sky flash and atmospheric energy ring
uniform float beat_flash : hint_range(0.0, 1.0) = 0.0;
uniform float beat_time : hint_range(0.0, 10.0) = 0.0;
uniform vec3 beat_color = vec3(0.4, 0.6, 1.0);

// Meteor showers — procedural streaks across the sky
uniform float meteor_intensity : hint_range(0.0, 1.0) = 0.5;

// Weather system — storm effects
uniform float storm_intensity : hint_range(0.0, 1.0) = 0.0;  // Dust storm fog density

// Physically-based scattering (from Sky3D — activates with atmo_activity)
uniform float atm_thickness : hint_range(0.0, 2.0) = 0.5;
uniform float atm_sun_intensity = 15.0;
uniform float atm_darkness = 0.5;
uniform vec3 atm_beta_ray = vec3(0.00001, 0.00001, 0.00003);
uniform vec3 atm_beta_mie = vec3(0.00000003038);
uniform vec3 atm_sun_partial_mie_phase = vec3(0.36, 1.64, 1.6);
uniform float atm_sun_mie_intensity = 1.0;

// ── Hash functions for procedural stars and clouds ──

float hash_f(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash_f3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise_2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash_f(i);
	float b = hash_f(i + vec2(1.0, 0.0));
	float c = hash_f(i + vec2(0.0, 1.0));
	float d = hash_f(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm_clouds(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise_2d(p);
		p = p * 2.0 + vec2(0.3, 0.7);
		a *= 0.5;
	}
	return v;
}

// ── 3D Noise for Volumetric Clouds ──

float noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep

	// 8-corner lattice interpolation
	float n000 = hash_f3(i);
	float n100 = hash_f3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash_f3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash_f3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash_f3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash_f3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash_f3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash_f3(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

float fbm_3d(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * noise_3d(p);
		p = p * 2.0 + vec3(0.3, 0.7, 0.1);
		a *= 0.5;
	}
	return v;
}

// ── Volumetric Cloud System ──
// Inspired by the volumetric cloud demo plugin's approach:
// Raymarching through a cloud layer with Beer's law extinction and
// Henyey-Greenstein phase function for realistic light scattering.
// Adapted for Dysnomia's thin/growing atmosphere.

// Cloud layer altitude (abstract units in sky shader space)
const float CLOUD_BOTTOM = 0.15;  // Minimum ray.y for cloud layer
const float CLOUD_TOP = 0.55;     // Maximum ray.y for cloud layer
const float CLOUD_THICKNESS = CLOUD_TOP - CLOUD_BOTTOM;

// Remap utility
float remap(float value, float old_min, float old_max, float new_min, float new_max) {
	return new_min + (value - old_min) / (old_max - old_min) * (new_max - new_min);
}

// Height gradient — shapes cloud density vertically (thicker in middle)
float cloud_height_gradient(float height_fraction) {
	// Rounded bottom, flat top — typical cumulus shape
	float bottom = smoothstep(0.0, 0.15, height_fraction);
	float top = smoothstep(1.0, 0.7, height_fraction);
	return bottom * top;
}

// Henyey-Greenstein phase function — forward scattering near sun
float hg_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5));
}

// Sample cloud density at a 3D position
float sample_cloud_density(vec3 pos, float coverage, float time_val) {
	// Wind offset
	vec3 wind = vec3(time_val * cloud_speed * 40.0, 0.0, time_val * cloud_speed * 12.0);

	// Height within cloud layer
	float height_frac = clamp((pos.y - CLOUD_BOTTOM) / CLOUD_THICKNESS, 0.0, 1.0);
	float height_grad = cloud_height_gradient(height_frac);

	// Base cloud shape — large-scale 3D noise
	float base_noise = fbm_3d((pos + wind) * cloud_scale * 0.08, 3);

	// Apply coverage: more coverage = more of the noise field becomes cloud
	float base_cloud = smoothstep(1.0 - coverage, 1.0 - coverage + 0.35, base_noise);
	base_cloud *= height_grad;

	// Detail erosion — high-frequency noise carves edges
	if (base_cloud > 0.01) {
		float detail = fbm_3d((pos + wind * 2.0) * cloud_scale * 0.3, 2);
		base_cloud = max(0.0, base_cloud - detail * 0.25);
	}

	return base_cloud;
}

// Raymarch through cloud layer
vec4 raymarch_clouds(vec3 ray_dir, vec3 sun_dir_n, float day_fac, float coverage) {
	if (ray_dir.y <= 0.01 || coverage < 0.04) {
		return vec4(0.0);  // Below horizon or no clouds
	}

	// Map ray direction to cloud space positions
	// In sky shader, EYEDIR is a direction — project to cloud altitude band
	float t_bottom = CLOUD_BOTTOM / max(ray_dir.y, 0.02);
	float t_top = CLOUD_TOP / max(ray_dir.y, 0.02);

	int num_steps = 24;
	float step_size = (t_top - t_bottom) / float(num_steps);

	vec3 accumulated_color = vec3(0.0);
	float accumulated_alpha = 0.0;

	// Sun lighting parameters
	float cos_theta = dot(ray_dir, sun_dir_n);
	// Dual-lobe phase function (forward + back scatter)
	float phase = max(hg_phase(cos_theta, 0.6), hg_phase(cos_theta, -0.3) * 0.25);
	phase = max(phase, 0.04); // Minimum ambient phase

	// Sky ambient color for cloud lighting
	vec3 ambient_sky = mix(vec3(0.04, 0.04, 0.06), vec3(0.35, 0.40, 0.50), day_fac);
	vec3 sun_light = sun_color * mix(0.1, 2.5, day_fac);

	for (int i = 0; i < num_steps; i++) {
		if (accumulated_alpha > 0.95) break;  // Early termination

		float t = t_bottom + (float(i) + 0.5) * step_size;
		vec3 sample_pos = ray_dir * t;

		float density = sample_cloud_density(sample_pos, coverage, TIME);

		if (density > 0.001) {
			// Beer's law extinction
			float extinction = density * step_size * 6.0;
			float transmittance = exp(-extinction);

			// Light sampling — march 4 steps toward sun for shadow
			float light_density = 0.0;
			float light_step = 0.08;
			for (int j = 0; j < 4; j++) {
				vec3 light_pos = sample_pos + sun_dir_n * light_step * float(j + 1);
				light_density += sample_cloud_density(light_pos, coverage, TIME) * light_step;
			}
			float light_transmittance = exp(-light_density * 8.0);

			// Powder sugar effect — bright edges when backlit
			float powder = 1.0 - exp(-density * step_size * 12.0);

			// Combined lighting
			vec3 lighting = sun_light * light_transmittance * phase;
			lighting += sun_light * powder * 0.15 * light_transmittance;
			lighting += ambient_sky * 0.4;

			// Cloud base color (slightly blue-ish white)
			vec3 cloud_col = vec3(0.92, 0.93, 0.96) * lighting;

			// Sunset tinting on clouds
			float sunset_fac = exp(-pow(sun_dir_n.y * 5.0, 2.0));
			cloud_col = mix(cloud_col, sunset_color * lighting * 1.5, sunset_fac * 0.35);

			// Integrate into accumulated color (front-to-back compositing)
			float alpha_step = (1.0 - transmittance);
			accumulated_color += cloud_col * alpha_step * (1.0 - accumulated_alpha);
			accumulated_alpha += alpha_step * (1.0 - accumulated_alpha);
		}
	}

	// Fade clouds near horizon (prevents hard cutoff)
	float horizon_fade = smoothstep(0.01, 0.12, ray_dir.y);
	accumulated_alpha *= horizon_fade;

	return vec4(accumulated_color, accumulated_alpha);
}


// ── Rayleigh/Mie Atmospheric Scattering (from Sky3D) ──
// Inlined from Common.gdshaderinc since shader_type sky supports #include
// but we keep it self-contained for simplicity.

const float RAYLEIGH_ZENITH_LENGTH = 8.4e3;
const float MIE_ZENITH_LENGTH = 1.25e3;
const float THREE_OVER_EIGHT_PI = 3.0 / (8.0 * PI);

float calc_rayleigh_phase(float mu) {
	return THREE_OVER_EIGHT_PI * (1.0 + mu * mu);
}

float calc_mie_phase_sky(float mu, vec3 partial) {
	float denominator = partial.y - partial.z * mu;
	float safe_denom = max(denominator, 0.0001);
	return PI * 4.0 * partial.x * pow(safe_denom, -1.5);
}

void calc_optical_depth(float y, out float sr, out float sm) {
	y = max(0.03, y + 0.03);
	y = 1.0 / y;
	sr = y * RAYLEIGH_ZENITH_LENGTH;
	sm = y * MIE_ZENITH_LENGTH;
}

vec3 calc_sky_scatter(vec3 ray_dir, vec3 sun_pos, float activity) {
	// Only compute scattering when there's atmosphere
	float sr, sm;
	calc_optical_depth(ray_dir.y, sr, sm);

	// Scale thickness with activity (more terraforming = thicker atmosphere)
	float eff_thickness = atm_thickness * activity;
	vec3 beta_ray = atm_beta_ray * eff_thickness;
	vec3 beta_mie = atm_beta_mie;

	vec3 extc_factor = clamp(exp(-(beta_ray * sr + beta_mie * sm)), vec3(0.0), vec3(1.0));

	float angle_mult_x = clamp(1.0 - sun_pos.y, 0.0, 1.0);       // Horizon factor
	float angle_mult_y = clamp(sun_pos.y + 0.45, 0.0, 1.0);       // Day factor
	float angle_mult_z = clamp(-sun_pos.y + 0.30, 0.0, 1.0);      // Night factor

	float extc_ff = mix(clamp(eff_thickness * 0.5, 0.0, 1.0), 1.0, angle_mult_x);
	vec3 final_extc = mix(1.0 - extc_factor, (1.0 - extc_factor) * extc_factor, extc_ff);

	float sun_mu = dot(sun_pos, ray_dir);
	float rayleigh = calc_rayleigh_phase(sun_mu);
	vec3 BRT = beta_ray * rayleigh;
	vec3 BMT = beta_mie * calc_mie_phase_sky(sun_mu, atm_sun_partial_mie_phase) * atm_sun_mie_intensity;

	vec3 BRMT = (BRT + BMT) / (beta_ray + beta_mie);

	// Scale sun intensity with activity (dim atmosphere at low terraforming)
	float eff_sun = atm_sun_intensity * activity;
	vec3 scatter = eff_sun * (BRMT * final_extc) * vec3(0.65, 0.72, 0.88) * angle_mult_y;
	scatter = mix(scatter, scatter * (1.0 - extc_factor), atm_darkness);

	// Horizon color shift at sunset
	vec3 lcol = mix(vec3(0.65, 0.72, 0.88), vec3(0.85, 0.6, 0.4), angle_mult_x);

	// Night scatter (faint)
	vec3 nscatter = (1.0 - extc_factor) * vec3(0.04, 0.05, 0.08);

	return (scatter * lcol) + nscatter;
}


void sky() {
	vec3 dir = EYEDIR;
	vec3 sun_dir = normalize(sun_direction);
	float sun_dot = dot(dir, sun_dir);
	float sun_height = sun_dir.y;

	// Day/night interpolation — much less dramatic on airless moon
	float day_factor = smoothstep(-0.15, 0.2, sun_height);
	float sunset_factor = exp(-pow(sun_height * 5.0, 2.0)) * 0.8; // Dimmer sunset
	sunset_factor = max(sunset_factor, 0.0);

	// Vertical gradient: zenith to horizon
	float horizon_factor = 1.0 - max(dir.y, 0.0);
	horizon_factor = pow(horizon_factor, 1.5);

	// Day sky — barely distinguishable from night on an airless moon
	vec3 lat_zenith = day_zenith;
	vec3 lat_horizon = day_horizon;
	if (latitude_factor > 0.0) {
		lat_zenith += vec3(-0.005, -0.003, 0.01) * latitude_factor;
		lat_horizon += vec3(-0.008, -0.003, 0.015) * latitude_factor;
	} else if (latitude_factor < 0.0) {
		float equator = -latitude_factor;
		lat_zenith += vec3(0.008, 0.003, -0.005) * equator;
		lat_horizon += vec3(0.01, 0.005, -0.008) * equator;
	}

	// Terraforming creates actual atmosphere — sky gets brighter with territory power
	float atmo_buildup = atmo_activity * 0.5;
	lat_zenith += vec3(0.02, 0.03, 0.06) * atmo_buildup;
	lat_horizon += vec3(0.04, 0.05, 0.08) * atmo_buildup;

	vec3 day_sky = mix(lat_zenith, lat_horizon, horizon_factor);

	// Night sky with gradient
	vec3 night_sky = mix(night_zenith, night_horizon, horizon_factor);

	// Blend day and night — this is the "vacuum sky" (no atmosphere)
	vec3 vacuum_sky = mix(night_sky, day_sky, day_factor);

	// Sunset/sunrise — very subtle on airless moon, brighter with terraforming
	float sun_horizon_glow = pow(max(sun_dot, 0.0), 3.0) * horizon_factor;
	float sunset_intensity = 0.15 + atmo_buildup * 0.3; // More atmosphere = more sunset
	vacuum_sky = mix(vacuum_sky, sunset_color, sunset_factor * sunset_intensity * (0.3 + sun_horizon_glow * 0.7));

	// Physically-based atmospheric scattering — blends in as territory is terraformed
	vec3 sky_col = vacuum_sky;
	if (atmo_activity > 0.01) {
		vec3 scattered = calc_sky_scatter(dir, sun_dir, atmo_activity);
		// Blend: at activity=0 pure vacuum, at activity=1 full scattering
		// Use smoothstep for gentle transition so low activity doesn't pop
		float scatter_blend = smoothstep(0.0, 0.8, atmo_activity);
		sky_col = mix(vacuum_sky, vacuum_sky + scattered, scatter_blend);
	}

	// Sun disc — tiny brilliant point at 96 AU
	float sun_disc = smoothstep(sun_size, sun_size + 0.00015, sun_dot);
	sky_col = mix(sky_col, sun_color * 4.0, sun_disc);  // Very bright but tiny

	// Sun glow (very tight halo — minimal atmospheric scattering)
	float sun_glow = pow(max(sun_dot, 0.0), 256.0) * 0.8; // Tighter, sharper
	sky_col += sun_color * sun_glow;

	// Minimal atmospheric scattering (increases with terraforming)
	float scatter_glow = pow(max(sun_dot, 0.0), 16.0) * (0.05 + atmo_buildup * 0.2);
	sky_col += sunset_color * scatter_glow * sunset_factor;

	// ── Multi-layer Parallax Star Field ──
	// Three layers at different grid scales create depth perception.
	// On an airless moon, stars are extremely bright and clear.
	float night_factor = 1.0 - day_factor;
	float star_visibility = max(night_factor, 0.7); // Stars dominate the sky always
	// Atmosphere dims stars — scattered light washes them out
	star_visibility *= (1.0 - atmo_activity * 0.4);
	{
		// Layer 1: Distant faint stars (dense background)
		vec3 star_grid_far = floor(dir * 600.0);
		float star_hash_far = hash_f3(star_grid_far);
		float star_far = step(0.993, star_hash_far);
		float bright_far = star_hash_far * 0.3 + 0.1; // Dim
		float temp_far = fract(star_hash_far * 7.3);
		vec3 sc_far = vec3(1.0);
		if (temp_far < 0.15) sc_far = vec3(1.0, 0.80, 0.65);       // Cool red
		else if (temp_far < 0.35) sc_far = vec3(0.75, 0.85, 1.0);   // Blue
		sky_col += sc_far * star_far * bright_far * star_visibility;

		// Layer 2: Medium stars (main field)
		vec3 star_grid_mid = floor(dir * 300.0);
		float star_hash_mid = hash_f3(star_grid_mid);
		float star_mid = step(0.994, star_hash_mid);
		float twinkle_mid = sin(TIME * 0.8 + star_hash_mid * 80.0) * 0.08 + 0.92;
		float bright_mid = star_hash_mid * 0.5 + 0.3;
		float temp_mid = fract(star_hash_mid * 5.1);
		vec3 sc_mid = vec3(1.0);
		if (temp_mid < 0.2) sc_mid = vec3(1.0, 0.85, 0.7);
		else if (temp_mid < 0.4) sc_mid = vec3(0.8, 0.9, 1.0);
		else if (temp_mid > 0.9) sc_mid = vec3(1.0, 1.0, 0.85);
		sky_col += sc_mid * star_mid * twinkle_mid * bright_mid * star_visibility;

		// Layer 3: Bright foreground stars (sparse, prominent)
		vec3 star_grid_near = floor(dir * 120.0);
		float star_hash_near = hash_f3(star_grid_near);
		float star_near = step(0.997, star_hash_near);
		float twinkle_near = sin(TIME * 1.2 + star_hash_near * 120.0) * 0.05 + 0.95;
		float bright_near = star_hash_near * 0.4 + 0.8; // Bright
		// These bright stars have a soft glow halo
		float glow_radius = (1.0 - step(0.997, star_hash_near)) * 0.0;
		float temp_near = fract(star_hash_near * 3.7);
		vec3 sc_near = vec3(1.0);
		if (temp_near < 0.25) sc_near = vec3(1.0, 0.78, 0.6);     // Orange giant
		else if (temp_near < 0.5) sc_near = vec3(0.7, 0.85, 1.0);  // Hot blue
		else if (temp_near > 0.85) sc_near = vec3(1.0, 0.95, 0.8); // Yellow
		sky_col += sc_near * star_near * twinkle_near * bright_near * star_visibility;

		// Bright star glow halos — soft diffuse light around the brightest stars
		if (star_near > 0.5) {
			vec3 star_center_dir = (star_grid_near + vec3(0.5)) / 120.0;
			star_center_dir = normalize(star_center_dir);
			float halo_dot = dot(dir, star_center_dir);
			float halo = pow(max(halo_dot, 0.0), 2000.0) * 0.4;
			sky_col += sc_near * halo * star_visibility;
		}

		// Milky Way band — multi-octave diffuse glow
		float milky_way_factor = 1.0 - abs(dir.y);
		float milky_noise = fbm_clouds(dir.xz * 3.0 + vec2(50.0, 80.0));
		float milky_detail = fbm_clouds(dir.xz * 8.0 + vec2(23.0, 41.0)) * 0.4;
		float milky_band = smoothstep(0.3, 0.7, milky_way_factor) * (milky_noise + milky_detail) * 0.08;
		// Slight color variation across the band
		vec3 milky_color = mix(vec3(0.07, 0.07, 0.11), vec3(0.10, 0.08, 0.12), milky_detail);
		sky_col += milky_color * milky_band * star_visibility;

		// Nebula patches — faint colored regions embedded in the Milky Way
		float neb_noise = fbm_clouds(dir.xz * 1.5 + vec2(77.0, 33.0));
		float neb_mask = smoothstep(0.55, 0.7, neb_noise) * smoothstep(0.35, 0.65, milky_way_factor);
		vec3 neb_color = mix(vec3(0.08, 0.04, 0.10), vec3(0.04, 0.06, 0.12), fract(neb_noise * 3.0));
		sky_col += neb_color * neb_mask * 0.15 * star_visibility;

		// ── ERIS — massive parent dwarf planet dominating the sky ──
		// Dysnomia is tidally locked to Eris, so Eris hangs in a fixed position.
		// Eris diameter ~2326 km, Dysnomia orbits at ~37,300 km.
		// Real angular diameter ~3.6° but we exaggerate to ~20° for dramatic visual impact.
		// Eris is an icy dwarf planet — NOT a star. It should look like a moon/planet
		// with a visible day/night terminator, surface features, and muted colors.
		vec3 eris_dir = normalize(vec3(0.3, 0.55, -0.4));
		float eris_dot = dot(dir, eris_dir);

		// Eris disc — HUGE in the sky (~20° angular diameter)
		// Sharper edge transition for a solid planetary body (not a glowing orb)
		float eris_disc = smoothstep(0.94, 0.948, eris_dot);

		// Eris surface detail — craters, ice plains, atmospheric wisps
		float eris_detail = 0.0;
		float eris_detail2 = 0.0;
		float eris_craters = 0.0;
		float eris_atmo_swirl = 0.0;
		if (eris_dot > 0.93) {
			// Project direction onto Eris surface for detail texture
			vec3 eris_local = dir - eris_dir * eris_dot;
			vec2 eris_uv = eris_local.xz * 20.0;

			// Multi-scale surface features — craters and ice plains
			eris_detail = noise_2d(eris_uv * 1.5) * 0.08;
			eris_detail += noise_2d(eris_uv * 3.0 + vec2(42.0)) * 0.05;
			// Large-scale albedo variation (bright fresh ice vs older grey terrain)
			eris_detail2 = noise_2d(eris_uv * 0.4 + vec2(17.0, 53.0));

			// Crater-like features — ring patterns from impact basins
			float crater_noise = noise_2d(eris_uv * 2.0 + vec2(91.0, 37.0));
			eris_craters = smoothstep(0.55, 0.60, crater_noise) * (1.0 - smoothstep(0.60, 0.68, crater_noise));
			eris_craters *= 0.12;  // Subtle rim brightening

			// ── Animated nitrogen atmosphere swirling ──
			float swirl_time = TIME * 0.008;
			vec2 swirl_uv1 = eris_uv * 0.8 + vec2(swirl_time, swirl_time * 0.3);
			vec2 swirl_uv2 = eris_uv * 1.2 + vec2(-swirl_time * 0.5, swirl_time * 0.7);

			float swirl1 = noise_2d(swirl_uv1) * 0.6;
			float swirl2 = noise_2d(swirl_uv2 + vec2(swirl1 * 0.5)) * 0.4;
			eris_atmo_swirl = (swirl1 + swirl2) * 0.5;

			// Banded structure — faint latitude lines
			float eris_lat = eris_local.y * 30.0;
			float bands = sin(eris_lat * 3.0 + swirl_time * 5.0) * 0.02;
			eris_atmo_swirl += bands;
		}

		// Eris base color — icy but NOT pure white. Mix of grey ice and brighter patches.
		// Real Eris albedo is ~0.96 but at 96 AU with dim sunlight, it appears much darker.
		vec3 eris_dark_terrain = vec3(0.25, 0.27, 0.32);    // Old grey surface
		vec3 eris_bright_ice = vec3(0.50, 0.53, 0.58);      // Fresh nitrogen ice
		vec3 eris_surface = mix(eris_dark_terrain, eris_bright_ice, eris_detail2);

		// Add fine surface detail — slight brightness variation
		eris_surface += vec3(eris_detail);
		// Crater rims catch light
		eris_surface += vec3(eris_craters * 0.8, eris_craters * 0.85, eris_craters);

		// Apply atmospheric swirl — wispy blue-white haze (very subtle)
		vec3 atmo_haze = vec3(0.45, 0.50, 0.60);
		eris_surface = mix(eris_surface, atmo_haze, eris_atmo_swirl * 0.15);

		// ── Phase illumination — this is what makes it look like a PLANET ──
		// The sun lights one side; the other side is dark.
		// Project sun direction onto the Eris disc to get per-pixel illumination.
		float eris_sun_dot = dot(eris_dir, sun_dir);

		// Per-pixel phase: how much of each point on the disc faces the sun
		vec3 eris_local_pt = normalize(dir - eris_dir * eris_dot);
		vec3 sun_on_disc = normalize(sun_dir - eris_dir * dot(sun_dir, eris_dir));
		float local_sun_facing = dot(eris_local_pt, sun_on_disc);

		// Global illumination factor (how much of Eris is generally lit)
		float global_illum = smoothstep(-0.5, 0.3, eris_sun_dot);

		// Per-pixel illumination: lit side vs shadow side
		// Sharp-ish terminator with slight softening (atmosphere scatters a tiny bit)
		float terminator = smoothstep(-0.15, 0.25, local_sun_facing * global_illum + global_illum * 0.5 - 0.3);

		// Night side is very dark but not pure black (faint reflected light from space)
		float illumination = mix(0.015, 0.55, terminator);
		eris_surface *= illumination;

		// Limb darkening — edges of the sphere are dimmer (atmosphere is thinner there)
		float eris_center_dist = 1.0 - smoothstep(0.94, 0.948, eris_dot);
		float limb_dark = mix(0.6, 1.0, smoothstep(0.0, 0.6, 1.0 - eris_center_dist));
		eris_surface *= limb_dark;

		// Thin atmospheric limb — faint blue line at the edge (nitrogen atmosphere)
		float limb_ring = smoothstep(0.948, 0.944, eris_dot) * (1.0 - smoothstep(0.944, 0.938, eris_dot));
		float limb_breathe = sin(TIME * 0.15) * 0.08 + 0.92;
		vec3 limb_color = vec3(0.15, 0.18, 0.28) * limb_ring * limb_breathe * global_illum;

		// Very subtle outer glow — NOT a sun-like bloom, just faint light bleed
		float eris_glow = pow(max(eris_dot - 0.88, 0.0) * 8.3, 4.0) * 0.02;

		// Composite: replace sky with Eris surface inside disc, add limb + glow outside
		sky_col = mix(sky_col, eris_surface, eris_disc);
		sky_col += limb_color;
		sky_col += vec3(0.10, 0.12, 0.16) * eris_glow * global_illum;
	}

	// (Horizon glow from terraforming is now handled by calc_sky_scatter above)

	// ── Volumetric Cloud Layer ──
	// Replaces the old flat 2D cloud projection with raymarched 3D clouds.
	// Only appears when territory is actively being terraformed.
	// On an untouched moon there are essentially no clouds.
	float effective_cloud_density = cloud_density + atmo_activity * 0.35;
	vec4 cloud_result = raymarch_clouds(dir, sun_dir, day_factor, effective_cloud_density);

	// Composite clouds over sky (stars/Eris are occluded behind clouds)
	sky_col = mix(sky_col, cloud_result.rgb, cloud_result.a);

	// ── Beat Shockwave — sky flash + expanding atmospheric energy ring ──
	if (beat_flash > 0.001) {
		// Full-sky flash — accent color floods the entire sky, quadratic falloff
		float flash_power = beat_flash * beat_flash;
		sky_col += beat_color * flash_power * 3.0;

		// Atmospheric energy ring — sweeps from horizon to zenith
		float ring_y = clamp(beat_time * 0.15, 0.0, 1.0);
		float ring_width = 0.06 + beat_time * 0.008;
		float elevation = max(dir.y, 0.0);
		float ring_dist_sky = abs(elevation - ring_y);
		float sky_ring = (1.0 - smoothstep(0.0, ring_width, ring_dist_sky)) * beat_flash;

		// Ring core — bright accent color
		sky_col += beat_color * sky_ring * 2.0;
		// Diffuse glow halo around the ring
		float ring_glow = exp(-ring_dist_sky * ring_dist_sky * 20.0) * beat_flash * 0.5;
		sky_col += beat_color * ring_glow;
	}

	// ── Meteor Showers — procedural streaks across the sky ──
	if (meteor_intensity > 0.01) {
		float meteor_vis = mix(1.0, 0.15, day_factor) * meteor_intensity;

		for (int m = 0; m < 3; m++) {
			// Deterministic per-meteor seed from TIME
			float slot_time = floor(TIME * 0.3 + float(m) * 1.7);
			float slot_hash = fract(sin(slot_time * 127.1 + float(m) * 311.7) * 43758.5453);

			// ~30% of slots produce a visible meteor
			if (slot_hash > 0.30) continue;

			float meteor_age = fract(TIME * 0.3 + float(m) * 1.7);
			float meteor_life = 0.3 + slot_hash * 0.2;
			if (meteor_age > meteor_life) continue;
			float meteor_t = meteor_age / meteor_life;

			// Random start direction on sky hemisphere
			float m_seed = slot_time * 73.0 + float(m) * 17.0;
			vec3 m_start = normalize(vec3(
				fract(sin(m_seed) * 43758.5) * 2.0 - 1.0,
				fract(sin(m_seed + 1.0) * 43758.5) * 0.8 + 0.1,
				fract(sin(m_seed + 2.0) * 43758.5) * 2.0 - 1.0
			));
			vec3 m_velocity = normalize(vec3(
				fract(sin(m_seed + 3.0) * 43758.5) * 2.0 - 1.0,
				-0.3 - fract(sin(m_seed + 4.0) * 43758.5) * 0.5,
				fract(sin(m_seed + 5.0) * 43758.5) * 2.0 - 1.0
			)) * 0.15;

			// Current meteor head position
			vec3 m_pos = normalize(m_start + m_velocity * meteor_t);
			float head_dot = dot(dir, m_pos);

			// Trail behind the meteor head
			float trail_length = 0.03 + meteor_t * 0.02;
			vec3 m_trail = normalize(m_start + m_velocity * max(0.0, meteor_t - trail_length));
			float trail_dot = dot(dir, m_trail);

			// Streak brightness — very tight angular proximity
			float streak_factor = max(head_dot, trail_dot);
			float streak = pow(max(streak_factor, 0.0), 8000.0) * 3.0;

			// Fade in/out over lifetime
			float fade = sin(meteor_t * 3.14159);
			float brightness = (0.5 + slot_hash * 1.5) * meteor_vis;

			// White-blue hot core
			sky_col += vec3(0.9, 0.95, 1.0) * streak * fade * brightness;
		}
	}

	// ── Storm fog overlay — dust storm reduces visibility ──
	if (storm_intensity > 0.01) {
		// Grey-brown haze washes out the sky from horizon upward
		vec3 storm_color = vec3(0.35, 0.32, 0.28);  // Dusty grey-brown
		float storm_gradient = smoothstep(0.0, 0.6, 1.0 - max(dir.y, 0.0));
		float storm_blend = storm_intensity * (0.4 + storm_gradient * 0.5);
		sky_col = mix(sky_col, storm_color, storm_blend);
		// Dim stars during storms
		// (stars were already added — this fog layer covers them)
	}

	// Ground plane (below horizon) — dark regolith color
	if (dir.y < 0.0) {
		float ground_fade = smoothstep(0.0, -0.05, dir.y);
		vec3 ground_col = vec3(0.03, 0.03, 0.04); // Very dark ground
		sky_col = mix(sky_col, ground_col, ground_fade);
	}

	COLOR = sky_col;
}
