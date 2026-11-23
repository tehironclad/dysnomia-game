shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Rocket exhaust on a lathed cone: UV.y = 0 at the nozzle, 1 at the tail.

uniform float throttle : hint_range(0.0, 1.5) = 0.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 edge_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float diamonds = 1.0;

void fragment() {
	float y = UV.y;
	float fres = abs(dot(NORMAL, VIEW));
	float n1 = sin(y * 38.0 - TIME * 61.0 + UV.x * 12.566) * 0.5 + 0.5;
	float n2 = sin(y * 15.0 - TIME * 37.0 - UV.x * 31.4) * 0.5 + 0.5;
	float flick = 0.7 + 0.3 * n1 * n2;
	// Mach diamonds near the nozzle
	float dia = diamonds * pow(0.5 + 0.5 * cos(y * 34.0), 6.0) * (1.0 - smoothstep(0.0, 0.45, y));
	float body = pow(fres, 1.4) * pow(1.0 - y, 1.6);
	vec3 col = mix(edge_color, core_color, clamp(pow(fres, 2.5) * (1.0 - y) + dia, 0.0, 1.0));
	ALBEDO = col * (body * flick + dia * 0.8) * throttle * 7.0;
}
