// The force field on a territory's border (BorderRing). Translucent and
// additive, so the neighbour's land shows through it. Tint: the neighbour's own
// Deep Field colour, or a dim neutral where no QING lies beyond. The look is
// the same for every viewer (it depends only on which QING is next door).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.5, 0.8, 1.0);
uniform float strength = 1.0;      // 0.35 where the map ends
uniform float cell = 4.5;          // hex cell size, metres
uniform float base_y = 0.0;        // world height where the field meets the ground
uniform bool along_x = true;       // the wall runs along X (north/south) or Z (east/west)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Distance to the nearest hex cell edge (0 on the edge, ~0.5 in the middle).
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

void fragment() {
	// along the wall: the horizontal axis this quad spans
	float along = along_x ? world_pos.x : world_pos.z;
	vec2 p = vec2(along, world_pos.y) / cell;
	float e = hex_edge(p);
	float lines = smoothstep(0.045, 0.0, e);
	float rise = max(0.0, world_pos.y - base_y);
	float fade = exp(-rise / 26.0);                 // bright at the ground, gone by ~80 m
	float sweep = 0.5 + 0.5 * sin(world_pos.y * 0.35 - TIME * 1.4 + along * 0.02);
	float foot = exp(-rise / 0.45);                  // a glowing seam where it meets the ground
	float a = (0.03 + 0.26 * lines * (0.5 + 0.5 * sweep)) * fade + 0.6 * foot;

	ALBEDO = tint * a * strength;
}
