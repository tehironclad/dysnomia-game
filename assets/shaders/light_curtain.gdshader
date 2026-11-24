// A light curtain across a doorway (PassDoor "curtain"): fine bright threads
// that part from the middle as `open` goes 0 → 1, with a lit parting edge.
// round_mask = 1 masks it to a disc (the Void's portal ring). UV-space only.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.66, 0.9, 1.0);
uniform float open = 0.0;      // 0 shut … 1 parted
uniform float strength = 1.0;  // overall brightness (a curtain shown only while you pass ramps this)
uniform float round_mask = 0.0;

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float disc = round_mask > 0.5 ? 1.0 - smoothstep(0.96, 1.0, r) : 1.0;
	float d = round_mask > 0.5 ? r : abs(c.x) * 2.0;   // 0 at the middle … 1 at the edge
	float part = smoothstep(open - 0.06, open + 0.04, d);
	float threads = 0.55 + 0.45 * sin(UV.x * 140.0 + sin(UV.y * 7.0 + TIME * 1.3) * 2.0);
	float drift = 0.75 + 0.25 * sin(UV.y * 18.0 - TIME * 2.2);
	float edge = exp(-abs(d - open) * 22.0) * smoothstep(0.0, 0.08, open);
	float fadeout = 1.0 - smoothstep(0.85, 1.0, open);
	float a = ((0.10 + 0.16 * threads * drift) * part + edge * 0.8) * fadeout * disc * strength;
	ALBEDO = color * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
