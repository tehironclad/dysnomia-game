shader_type canvas_item;
render_mode unshaded;
// The arcade dive: one full-screen pass over everything.
//   bulge      the CRT glass: barrel distortion of the whole frame (the arcade while the camera pushes in)
//   world_*    the game's world (a 3D SubViewport, or the cabinet's 320×240 screen in classic mode),
//              growing out of the light tunnel (world_zoom) and replacing the arcade (world_mix)
//   tunnel     radial light streaks rushing past: the warp between the hall and the game
//   bezel      classic mode: the picture sits in a dark CRT bezel with its own curvature
//   scan       scanlines (rows of the picture in classic mode, of the screen otherwise)

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D world_tex : filter_linear;
uniform vec2 world_px = vec2(320.0, 240.0);
uniform float screen_aspect = 1.7778;
uniform float world_aspect = 1.7778;
uniform float bulge = 0.0;
uniform float scan = 0.0;
uniform float scan_rows = 240.0;
uniform float tunnel = 0.0;
uniform float flash = 0.0;
uniform float world_mix = 0.0;
uniform float world_zoom = 1.0;
uniform float bezel = 0.0;
uniform float pixelate = 0.0;
uniform float rgb_split = 0.0;
uniform float vignette = 0.0;
uniform float time_s = 0.0;
uniform vec4 tint : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform vec4 tint2 : source_color = vec4(1.0, 0.31, 0.85, 1.0);

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

vec3 world_at(vec2 wuv) {
	if (pixelate > 0.5) {
		wuv = (floor(wuv * world_px) + 0.5) / world_px;
	}
	return texture(world_tex, wuv).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	c.x *= screen_aspect;
	float r2 = dot(c, c);
	vec2 cb = c * (1.0 + bulge * r2 * 1.6);

	// The arcade behind, through the curved glass.
	vec3 base = vec3(0.0);
	if (world_mix < 0.999) {
		vec2 suv = vec2(cb.x / screen_aspect, cb.y) + 0.5;
		if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0) {
			base = texture(screen_tex, suv).rgb;
		}
	}

	// The world picture, centred, fitted to the screen, scaled by world_zoom.
	vec2 half_size = world_aspect <= screen_aspect
		? vec2(world_aspect * 0.5, 0.5)
		: vec2(screen_aspect * 0.5, 0.5 * screen_aspect / world_aspect);
	half_size *= mix(1.0, 0.9, bezel);
	vec2 wuv = (cb / max(world_zoom, 0.0005)) / (2.0 * half_size) + 0.5;
	vec2 q = wuv - 0.5;
	wuv = 0.5 + q * (1.0 + bezel * 0.32 * dot(q, q));
	float edge = min(min(wuv.x, 1.0 - wuv.x), min(wuv.y, 1.0 - wuv.y));
	float inside = smoothstep(-0.002, 0.004, edge);
	vec3 w;
	if (rgb_split > 0.0) {
		vec2 d = normalize(q + 1e-5) * rgb_split * length(q);
		w = vec3(world_at(wuv + d).r, world_at(wuv).g, world_at(wuv - d).b);
	} else {
		w = world_at(wuv);
	}
	// Classic: scanlines on the picture's own rows, a glow at the glass edge.
	if (bezel > 0.0) {
		float row = 0.5 + 0.5 * cos(wuv.y * scan_rows * 6.2831853);
		w *= 1.0 - bezel * 0.32 * row;
		w *= 0.82 + 0.18 * smoothstep(0.0, 0.08, edge);
	}
	vec3 outside = base * (1.0 - world_mix);
	if (bezel > 0.0) {
		float rim = exp(-abs(edge) * 60.0) * step(edge, 0.0);
		outside += tint.rgb * rim * 0.35 * bezel * world_mix;
	}
	vec3 col = mix(outside, w, inside * world_mix);

	// The light tunnel: 72 spokes of streaks rushing outwards.
	if (tunnel > 0.0) {
		float ang = atan(c.y, c.x);
		float rad = length(c);
		float spokes = 72.0;
		float a = (ang + 3.14159265) / 6.2831853 * spokes;
		float seg = floor(a);
		float h = hash1(seg);
		float h2 = hash1(seg + 31.7);
		float z = fract(h * 5.0 + log(rad + 0.015) * 0.75 - time_s * (1.6 + h2 * 2.2));
		float dash = smoothstep(0.0, 0.05, z) * smoothstep(0.42, 0.06, z);
		float thin = 1.0 - abs(fract(a) - 0.5) * 2.0;
		float s = dash * pow(thin, 2.0) * smoothstep(0.03, 0.4, rad) * (0.35 + 0.65 * h2 * h2);
		vec3 sc = mix(tint.rgb, tint2.rgb, step(0.62, h));
		float core = exp(-rad * 5.5) * 0.9;
		vec3 tun = sc * s * 2.2 + mix(tint.rgb, vec3(1.0), 0.6) * core;
		col += tun * tunnel * (1.0 - inside * world_mix * 0.8);
	}

	if (scan > 0.0) {
		float row = 0.5 + 0.5 * cos(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159265);
		col *= 1.0 - scan * 0.4 * row;
	}
	float vig = vignette + bulge * 0.8;
	col *= clamp(1.0 - vig * r2 * 1.4, 0.0, 1.0);
	col = mix(col, vec3(1.0, 0.98, 1.0), clamp(flash, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
