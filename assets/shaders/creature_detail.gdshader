shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Creature surface shader — bioluminescent noise stripes, hurt flash,
// dissolve discard, and animated glow emission.

uniform vec3 base_color : source_color = vec3(0.3, 0.25, 0.2);
uniform float hurt_flash : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(0.2, 0.8, 0.5);
uniform float glow_intensity : hint_range(0.0, 5.0) = 0.5;

// ─── Hash / noise helpers ─────────────────────────────────────────
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

void fragment() {
	vec2 uv = UV;
	vec3 wp = VERTEX;
	EMISSION = vec3(0.0);

	// ── Dissolve ──────────────────────────────────────────────────
	if (dissolve > 0.01) {
		float noise_val = value_noise(wp.xz * 4.0 + wp.y * 3.0);
		if (noise_val < dissolve) {
			discard;
		}
		// Bright edge near dissolve boundary
		float edge = smoothstep(dissolve, dissolve + 0.06, noise_val);
		if (edge < 1.0) {
			EMISSION = glow_color * (1.0 - edge) * 5.0;
		}
	}

	// ── Bioluminescent stripes (sin pattern along UV.y) ──────────
	float stripe_freq = 12.0;
	float stripe_raw = sin(uv.y * stripe_freq * 3.14159 + wp.x * 2.0);
	float stripe = smoothstep(0.6, 0.8, stripe_raw);

	// Animated glow pulse
	float pulse = sin(TIME * 2.5) * 0.25 + 0.75;
	float stripe_emission = stripe * glow_intensity * pulse;

	// ── Surface colour ───────────────────────────────────────────
	float detail = value_noise(wp.xz * 6.0 + wp.y * 4.0);
	ALBEDO = base_color * (0.85 + detail * 0.20);
	ROUGHNESS = 0.65 + detail * 0.15;
	METALLIC = 0.05;
	SPECULAR = 0.45;

	// Stripe colour tint on albedo
	ALBEDO = mix(ALBEDO, glow_color * 0.4, stripe * 0.3);

	// Emission from stripes
	EMISSION += glow_color * stripe_emission;

	// ── Hurt flash ───────────────────────────────────────────────
	if (hurt_flash > 0.01) {
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.15, 0.08), hurt_flash * 0.5);
		EMISSION += vec3(1.0, 0.2, 0.1) * hurt_flash * 2.5;
	}
}
