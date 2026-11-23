shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

// Heat shimmer / energy distortion visible near terraformed territory.
// Applied as a screen-space distortion plane near the ground.
// Intensity driven by territory_power from on-chain state.

uniform float shimmer_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float shimmer_speed : hint_range(0.1, 5.0) = 1.5;
uniform float shimmer_scale : hint_range(1.0, 50.0) = 15.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_position;

float hash_s(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise_s(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash_s(i);
	float b = hash_s(i + vec2(1.0, 0.0));
	float c = hash_s(i + vec2(0.0, 1.0));
	float d = hash_s(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Always sample screen — this mesh is an invisible distortion overlay,
	// never opaque. If intensity is near zero the mesh should be hidden via
	// set_power_level(), but guard here too for safety.
	vec2 uv = SCREEN_UV;

	if (shimmer_intensity < 0.01) {
		ALBEDO = texture(screen_texture, uv).rgb;
		ALPHA = 1.0;
	} else {

		// Height-based fade — strongest near ground (0-3m above mesh), fades above
		float height_fade = 1.0 - smoothstep(0.0, 4.0, world_position.y);
		height_fade = height_fade * height_fade; // Sharper falloff

		// Distortion from animated noise
		float time_val = TIME * shimmer_speed;

		// Two layers of scrolling noise for organic movement
		float distort1 = noise_s(world_position.xz * shimmer_scale * 0.1 + vec2(time_val, time_val * 0.7));
		float distort2 = noise_s(world_position.xz * shimmer_scale * 0.15 + vec2(-time_val * 0.5, time_val * 1.3));

		// Combine into displacement vector
		float fade = shimmer_intensity * height_fade;
		vec2 distortion = vec2(
			(distort1 - 0.5) * 2.0,
			(distort2 - 0.5) * 2.0
		) * fade * 0.008;

		// Sample distorted screen — always output full screen color (never white)
		vec3 screen_col = texture(screen_texture, uv + distortion).rgb;

		// Slight energy tint in heavily distorted areas
		float energy_factor = length(distortion) * 200.0 * shimmer_intensity;
		screen_col += vec3(0.02, 0.04, 0.08) * energy_factor;

		ALBEDO = screen_col;
		ALPHA = 1.0;
	}
}
