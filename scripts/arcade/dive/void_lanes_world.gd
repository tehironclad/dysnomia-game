extends ArcadeWorld
## Void Lanes, dived into: you run down four neon lanes through the Void while the chat lines come
## at you, standing on the lanes like gates. True lines glow ice, OG lines gold; an imposter turns
## magenta and shakes once it is checked. Your LAU runs behind the catcher frame; Space fires the
## flag beam up your lane. The 2D game (void_lanes.gd) decides every catch, miss and point; this
## only stages its state: 2D y → depth (the catch line is z = 0), 2D lane x → lane x.

const LANE_W := 2.4
const K := 0.27  ## metres per 2D px along the lanes
const GATES := 6
const GATE_GAP := 22.0
const STREAKS := 48
const POOL := 28

var _floor_mat: ShaderMaterial
var _scroll := 0.0
var _gates: Array = []
var _streaks: MultiMesh
var _streak_seed: Array = []  # [x, y, z0, len]
var _lines: Array = []  # {root, fill, frame: Array, label, kind}
var _kind_mats := {}
var _avatar: Node3D
var _catcher: Node3D
var _beam: MeshInstance3D
var _pops: Array = []
var _cx := 0.0


func controls_hint() -> String:
	return "%s / %s or ← → switch lanes · %s flags the line in your lane" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right"), ControlsHelp.key_of("jump")]


static func zf(y: float) -> float:
	return (y - 214.0) * K


static func xf(px: float) -> float:
	return (px - 160.0) / 72.0 * LANE_W


func _build() -> void:
	make_environment(Color(0.006, 0.004, 0.016), Color(0.02, 0.0, 0.05), 0.016, 1.1)
	make_camera(68.0)
	starfield(700, 260.0, 0x701D, 1.6)
	# A far Deep Field glow at the end of the lanes.
	var neb := add_mesh(_quad(Vector2(170, 90)), _soft_mat(accent.lerp(MAGENTA, 0.5), 0.45))
	neb.position = Vector3(0, 4, -320)
	var neb2 := add_mesh(_quad(Vector2(90, 60)), _soft_mat(ICE, 0.3))
	neb2.position = Vector3(-45, 10, -300)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 160, 0)
	key.light_energy = 0.9
	key.light_color = Color(0.7, 0.85, 1.0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -20, 0)
	rim.light_energy = 1.2
	rim.light_color = MAGENTA
	add_child(rim)
	_build_floor()
	_build_gates()
	_build_streaks()
	for k in ["true", "og", "imp"]:
		var c: Color = {"true": ICE, "og": GOLD, "imp": MAGENTA}[k]
		_kind_mats[k] = [neon_mat(c, 0.09, true), neon_mat(c, 2.6)]
	for i in POOL:
		_lines.append(_make_line())
	_catcher = Node3D.new()
	add_child(_catcher)
	var cm := neon_mat(ICE, 3.2)
	for part in [[Vector3(2.3, 0.07, 0.07), Vector3(0, 0.62, 0)], [Vector3(0.07, 1.05, 0.07), Vector3(-1.15, 1.1, 0)], [Vector3(0.07, 1.05, 0.07), Vector3(1.15, 1.1, 0)]]:
		var m := add_mesh(box_mesh(part[0]), cm, _catcher)
		m.position = part[1]
	_avatar = make_avatar()
	if _avatar:
		_avatar.rotation.y = PI
	var bm := CylinderMesh.new()
	bm.top_radius = 0.07
	bm.bottom_radius = 0.07
	bm.height = 1.0
	_beam = add_mesh(bm, neon_mat(MAGENTA, 4.0, true))
	_beam.rotation_degrees.x = 90.0
	_beam.visible = false
	for i in 8:
		var l := label3d("", 64, ICE, false)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.visible = false
		_pops.append(l)


func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


func _soft_mat(c: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c, a)
	m.albedo_texture = _dot_texture()
	m.disable_fog = true
	return m


const FLOOR_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float scroll = 0.0;
uniform float lane_w = 2.4;
uniform float sel_x = 0.0;
uniform vec4 line_c : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform vec4 alt_c : source_color = vec4(1.0, 0.3, 0.85, 1.0);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float lx = wp.x / lane_w;
	float d = abs(lx - round(lx)) * lane_w;
	float rail = smoothstep(0.07, 0.0, d);
	float edge = step(2.0 * lane_w - 0.2, abs(wp.x));
	float z = wp.z - scroll;
	float cz = abs(fract(z / 6.0) - 0.5) * 6.0;
	float cross = smoothstep(2.9, 3.0, cz);
	float dots = smoothstep(0.18, 0.0, length(vec2(d, (3.0 - cz)))) ;
	float sel = smoothstep(lane_w * 0.5, lane_w * 0.2, abs(wp.x - sel_x)) * smoothstep(-40.0, 2.0, wp.z);
	vec3 base = mix(vec3(0.0015, 0.001, 0.004), vec3(0.006, 0.004, 0.016), sel);
	vec3 c = base + line_c.rgb * rail * (1.1 + edge * 1.4) + alt_c.rgb * cross * 0.3 + line_c.rgb * dots * 1.6;
	c += line_c.rgb * sel * 0.008;
	ALBEDO = c;
}
"""


func _build_floor() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(LANE_W * 4.0 + 1.2, 150.0)
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = sh
	_floor_mat.set_shader_parameter("lane_w", LANE_W)
	_floor_mat.set_shader_parameter("line_c", ICE)
	_floor_mat.set_shader_parameter("alt_c", MAGENTA)
	var f := add_mesh(pm, _floor_mat)
	f.position = Vector3(0, 0, -65)


func _build_gates() -> void:
	var half := LANE_W * 2.0 + 0.7
	for i in GATES:
		var g := Node3D.new()
		add_child(g)
		var m := neon_mat(ICE if i % 2 == 0 else MAGENTA, 2.6)
		for sx in [-1.0, 1.0]:
			var post := add_mesh(box_mesh(Vector3(0.12, 4.6, 0.12)), m, g)
			post.position = Vector3(sx * half, 2.3, 0)
		var beam := add_mesh(box_mesh(Vector3(half * 2.0, 0.12, 0.12)), m, g)
		beam.position = Vector3(0, 4.6, 0)
		_gates.append(g)


func _build_streaks() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 0x57EA
	_streaks = pool_multimesh(box_mesh(Vector3(0.03, 0.03, 1.0)), neon_mat(ICE, 2.0, true, 0.6), STREAKS)
	for i in STREAKS:
		var side := -1.0 if i % 2 == 0 else 1.0
		_streak_seed.append([side * r.randf_range(LANE_W * 2.0 + 2.0, 16.0), r.randf_range(-2.0, 9.0), r.randf_range(0.0, 140.0), r.randf_range(2.0, 6.0)])
		_streaks.set_instance_color(i, Color(ICE if r.randf() < 0.7 else MAGENTA, r.randf_range(0.3, 1.0)))
	_streaks.visible_instance_count = STREAKS


func _make_line() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var fill := add_mesh(box_mesh(Vector3(2.1, 0.8, 0.04)), null, root)
	var frame: Array = []
	for part in [[Vector3(2.18, 0.05, 0.06), Vector3(0, 0.42, 0)], [Vector3(2.18, 0.05, 0.06), Vector3(0, -0.42, 0)], [Vector3(0.05, 0.88, 0.06), Vector3(-1.09, 0, 0)], [Vector3(0.05, 0.88, 0.06), Vector3(1.09, 0, 0)]]:
		var m := add_mesh(box_mesh(part[0]), null, root)
		m.position = part[1]
		frame.append(m)
	var label := Label3D.new()
	label.font = DeepFieldTheme.mono_font()
	label.font_size = 48
	label.pixel_size = 0.0075
	label.render_priority = 2
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.shaded = false
	label.position = Vector3(0, 0, 0.06)
	label.width = 230.0
	root.add_child(label)
	return {"root": root, "fill": fill, "frame": frame, "label": label, "kind": "", "text": ""}


func _set_kind(n: Dictionary, k: String) -> void:
	if n["kind"] == k:
		return
	n["kind"] = k
	var mats: Array = _kind_mats[k]
	n["fill"].material_override = mats[0]
	for f in n["frame"]:
		f.material_override = mats[1]
	n["label"].modulate = {"true": ICE, "og": GOLD, "imp": MAGENTA}[k].lightened(0.55)


func _sync(delta: float) -> void:
	var g = game
	var fall: float = g.fall
	var speed := fall * K
	_scroll += speed * delta if (g.playing or g.attract_mode) else 0.0
	_floor_mat.set_shader_parameter("scroll", -_scroll)
	var lane_x := xf(g.lane_x)
	_floor_mat.set_shader_parameter("sel_x", lane_x)
	for i in _gates.size():
		_gates[i].position.z = fmod(i * GATE_GAP + _scroll, GATES * GATE_GAP) - (GATES - 1) * GATE_GAP + 8.0
	for i in STREAKS:
		var s: Array = _streak_seed[i]
		var z := fmod(s[2] + _scroll * 1.6, 140.0) - 130.0
		_streaks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, 1, s[3] * (0.6 + speed / 30.0))), Vector3(s[0], s[1], z)))

	# The lines.
	var lines: Array = g.lines
	for i in POOL:
		var n: Dictionary = _lines[i]
		if i >= lines.size():
			n["root"].visible = false
			continue
		var l: Dictionary = lines[i]
		var revealed: bool = g.revealed(l)
		_set_kind(n, "imp" if revealed else ("og" if l.kind == 2 else "true"))
		var text: String = ("[!] " if revealed else ("◆ " if l.kind == 2 else "")) + "%s: %s" % [l.who, l.msg]
		if n["text"] != text:
			n["text"] = text
			n["label"].text = text
		var root: Node3D = n["root"]
		root.visible = true
		var x := xf(g.LANE_X[l.lane])
		if revealed:
			x += sin(_t * 47.0 + i) * 0.05
		root.position = Vector3(x, 1.2, zf(l.y + g.LINE_H * 0.5))
		root.rotation.z = sin(_t * 31.0 + i) * 0.03 if revealed else 0.0

	# The runner and the catcher.
	_catcher.position = Vector3(lane_x, 0, 0)
	if _avatar:
		_avatar.position = Vector3(lane_x, 0, 1.0)
		var running: bool = g.playing or g.attract_mode
		_avatar.update_movement(Vector3(0, 0, -minf(speed * 0.45, 9.0)) if running else Vector3.ZERO, true, false)
	_beam.visible = g.beam_t >= 0.0
	if _beam.visible:
		var top := zf(g.beam_top)
		var length := maxf(0.1, -top)
		_beam.position = Vector3(xf(g.beam_x), 1.2, top * 0.5)
		_beam.scale = Vector3(1.0 - g.beam_t / 0.18 * 0.6, length, 1.0 - g.beam_t / 0.18 * 0.6)
	var pops: Array = g.popups
	for i in _pops.size():
		var lab: Label3D = _pops[i]
		if i >= pops.size():
			lab.visible = false
			continue
		var pu: Dictionary = pops[i]
		lab.visible = true
		lab.text = pu.s
		lab.modulate = Color(pu.c, clampf(pu.life * 2.0, 0.0, 1.0))
		lab.position = Vector3(xf(pu.p.x), 2.3 + (0.7 - pu.life) * 2.0, zf(pu.p.y) + 1.0)

	# The camera rides behind, leaning toward your lane; it shakes on a hit.
	_cx = lerpf(_cx, lane_x, minf(1.0, delta * 5.0))
	var shake := Vector3.ZERO
	if g.flash > 0.0:
		shake = Vector3(sin(_t * 90.0), cos(_t * 77.0), 0) * g.flash * 0.25
	camera.position = Vector3(_cx * 0.6, 2.7, 5.6) + shake
	camera.look_at(Vector3(_cx * 0.8, 1.1, -20.0), Vector3.UP)
	camera.fov = 64.0 + clampf((fall - 46.0) / 130.0, 0.0, 1.0) * 16.0


func hud() -> Dictionary:
	var g = game
	var m: int = g.multiplier()
	var pips := ""
	for i in g.MISSES_PER_LIFE:
		pips += "●" if i < g.misses else "○"
	return {
		"stats": PackedStringArray(["x%d · COMBO %d" % [m, g.combo], "EPOCH %d" % g.epoch, "MISSED %s" % pips]),
		"flash": g.flash, "flash_color": g.flash_c,
	}
