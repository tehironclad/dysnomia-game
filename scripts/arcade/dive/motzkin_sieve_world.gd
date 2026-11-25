extends ArcadeWorld
## Motzkin Sieve, dived into: you ride the sieve's sled across the QING's floor at the mouth of a
## neon shaft, and the numbers come down the shaft at you as glass blocks: primes ice, composites
## magenta, the Motzkin primes gold. Fire sends a bolt up the shaft; a composite it meets bursts into
## gold factor shards that tumble toward you. The 2D game (motzkin_sieve.gd) rules every hit, catch
## and leak; this only stages its state: 2D x → across the shaft, 2D y → depth (the floor is z = 0).

const KX := 0.05  ## metres per 2D px across
const KZ := 0.22  ## metres per 2D px down the shaft (2D y → −z)
const POOL := 24
const SHARDS := 24
const FRAMES := 14
const FRAME_GAP := 4.0

const BLOCK_SHADER := """shader_type spatial;
render_mode unshaded, cull_back;
instance uniform vec3 size_m = vec3(1.0);
instance uniform vec4 tint : source_color = vec4(0.5, 0.9, 1.0, 1.0);
varying vec3 pm;
void vertex() { pm = VERTEX * size_m; }
void fragment() {
	vec3 e = size_m * 0.5 - abs(pm);
	float m1 = min(e.x, min(e.y, e.z));
	float m3 = max(e.x, max(e.y, e.z));
	float m2 = e.x + e.y + e.z - m1 - m3;
	float edge = smoothstep(0.07, 0.015, m2);
	ALBEDO = tint.rgb * (0.16 + edge * 2.8);
	ALPHA = clamp(0.45 + edge * 0.55, 0.0, 1.0);
}
"""

var _block_mat: ShaderMaterial
var _blocks: Array = []  # [MeshInstance3D, Label3D]
var _shards: Array = []  # [MeshInstance3D, Label3D]
var _bolts: Array = []
var _frames: MultiMesh
var _floor_lines: MultiMesh
var _scroll := 0.0
var _sled: Node3D
var _avatar: Node3D
var _pops: Array = []
var _sx := 0.0


func controls_list() -> Array:
	return [["%s %s / ← →" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right")], "slide the sieve"],
		[ControlsHelp.key_of("jump"), "fire a bolt up the shaft (hold: auto-fire)"]]


func controls_hint() -> String:
	return "%s / %s or ← → slide · %s fires up the shaft: break composites, never primes" % [
		ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right"), ControlsHelp.key_of("jump")]


static func xf(px: float) -> float:
	return (px - 160.0) * KX


static func zf(py: float) -> float:
	return -(222.0 - py) * KZ


func _build() -> void:
	make_environment(Color(0.006, 0.003, 0.014), Color(0.05, 0.0, 0.08), 0.012, 1.15)
	make_camera(64.0)
	starfield(400, 220.0, 0x5137, 1.4)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 20, 0)
	key.light_energy = 0.7
	add_child(key)
	var sh := Shader.new()
	sh.code = BLOCK_SHADER
	_block_mat = ShaderMaterial.new()
	_block_mat.shader = sh
	# The shaft: square neon frames down to the far end, scrolling toward you with the rain.
	_frames = pool_multimesh(box_mesh(Vector3(1, 1, 1)), neon_mat(accent.lerp(MAGENTA, 0.4), 1.4), FRAMES * 4)
	_frames.visible_instance_count = FRAMES * 4
	_floor_lines = pool_multimesh(box_mesh(Vector3(1, 1, 1)), neon_mat(ICE, 0.7), 34)
	_floor_lines.visible_instance_count = 34
	var floor_mat := mat(Color(0.02, 0.015, 0.04), 0.3, 0.6)
	var fl := add_mesh(box_mesh(Vector3(18, 0.2, 60)), floor_mat)
	fl.position = Vector3(0, -0.1, -26)
	var q := label3d("QING", 110, Color(accent, 0.5), false)
	q.rotation_degrees.x = -90.0
	q.position = Vector3(-5.0, 0.02, -2.5)
	var nm := label3d(String(ctx.get("territory", {}).get("name", "")).to_upper(), 44, Color(accent, 0.4))
	nm.rotation_degrees.x = -90.0
	nm.position = Vector3(-5.0, 0.02, -1.4)
	# The far end: the source of the rain, a Deep Field glow.
	var glow_q := QuadMesh.new()
	glow_q.size = Vector2(26, 16)
	var far := add_mesh(glow_q, neon_mat(accent.lerp(MAGENTA, 0.5), 0.5, true, 0.6))
	far.position = Vector3(0, 4, -56)
	for i in POOL:
		var m := add_mesh(BoxMesh.new(), _block_mat)
		m.visible = false
		var l := label3d("", 96, Color.WHITE, false)
		l.pixel_size = 0.009
		l.visible = false
		_blocks.append([m, l])
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 4
	sm.rings = 2
	for i in SHARDS:
		var m := add_mesh(sm, neon_mat(GOLD, 2.6))
		m.visible = false
		var l := label3d("", 56, GOLD)
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.visible = false
		_shards.append([m, l])
	for i in 3:
		var b := add_mesh(box_mesh(Vector3(0.08, 0.08, 1.6)), neon_mat(ICE, 3.5))
		b.visible = false
		_bolts.append(b)
	for i in 8:
		var l := label3d("", 64, GOLD, false)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.006
		l.visible = false
		_pops.append(l)
	_sled = Node3D.new()
	add_child(_sled)
	var sled_mat := neon_mat(ICE, 2.2)
	var deck := add_mesh(box_mesh(Vector3(1.7, 0.1, 0.9)), mat(Color(0.05, 0.05, 0.08), 0.3, 0.8), _sled)
	deck.position.y = 0.2
	add_mesh(box_mesh(Vector3(1.75, 0.04, 0.04)), sled_mat, _sled).position = Vector3(0, 0.27, -0.45)
	for k in 7:  # the comb's teeth
		add_mesh(box_mesh(Vector3(0.04, 0.04, 0.5)), sled_mat, _sled).position = Vector3(-0.78 + k * 0.26, 0.27, -0.7)
	var gun := add_mesh(box_mesh(Vector3(0.12, 0.12, 0.7)), neon_mat(GOLD, 2.0), _sled)
	gun.position = Vector3(0.55, 1.1, -0.2)
	_avatar = make_avatar()
	if _avatar:
		remove_child(_avatar)
		_sled.add_child(_avatar)
		_avatar.position = Vector3(0, 0.25, 0.1)
		_avatar.rotation.y = PI


func _sync(delta: float) -> void:
	var g = game
	_scroll = fmod(_scroll + delta * g.fall_speed() * KZ, FRAME_GAP)
	# The shaft frames: 8 m wide, 6 m tall, scrolling toward you.
	var k := 0
	for i in FRAMES:
		var z := -i * FRAME_GAP + _scroll - 2.0
		for side in [[Vector3(0, 6.0, z), Vector3(17.0, 0.08, 0.08)], [Vector3(-8.5, 3.0, z), Vector3(0.08, 6.0, 0.08)],
				[Vector3(8.5, 3.0, z), Vector3(0.08, 6.0, 0.08)], [Vector3(0, 0.02, z), Vector3(17.0, 0.03, 0.06)]]:
			_frames.set_instance_transform(k, Transform3D(Basis.from_scale(side[1]), side[0]))
			var fade := 1.0 - i / float(FRAMES)
			_frames.set_instance_color(k, Color(fade, fade, fade))
			k += 1
	for i in 34:
		var x := -8.0 + i * (16.0 / 33.0)
		_floor_lines.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.025, 0.02, 56.0)), Vector3(x, 0.01, -26.0)))
		_floor_lines.set_instance_color(i, Color(0.35, 0.35, 0.35))
	# The rain.
	for i in _blocks.size():
		var m: MeshInstance3D = _blocks[i][0]
		var l: Label3D = _blocks[i][1]
		var on: bool = i < g.blocks.size()
		m.visible = on
		l.visible = on
		if not on:
			continue
		var bl: Dictionary = g.blocks[i]
		var w: float = float(bl["w"]) * KX * 1.6
		var size := Vector3(w, 1.3, 1.0)
		var c: Color = GOLD if bool(bl["motzkin"]) else (ICE if bool(bl["prime"]) else MAGENTA)
		m.scale = size
		m.position = Vector3(xf(float(bl["x"])), 1.2, zf(float(bl["y"])))
		m.rotation.y = sin(_t * 1.3 + i) * 0.12
		m.set_instance_shader_parameter("size_m", size)
		m.set_instance_shader_parameter("tint", c)
		l.text = str(bl["n"])
		l.modulate = c.lerp(Color.WHITE, 0.55)
		l.position = m.position + Vector3(0, 0, 0.52)
		l.rotation.y = m.rotation.y
	for i in _shards.size():
		var m: MeshInstance3D = _shards[i][0]
		var l: Label3D = _shards[i][1]
		var on: bool = i < g.shards.size()
		m.visible = on
		l.visible = on
		if not on:
			continue
		var s: Dictionary = g.shards[i]
		m.position = Vector3(xf(float(s["x"])), 0.9, zf(float(s["y"])))
		m.rotation = Vector3(_t * 3.0 + i, _t * 2.0, 0)
		l.text = str(s["n"])
		l.position = m.position + Vector3(0, 0.45, 0)
	for i in _bolts.size():
		var b: MeshInstance3D = _bolts[i]
		b.visible = i < g.bolts.size()
		if b.visible:
			var p: Vector2 = g.bolts[i]
			b.position = Vector3(xf(p.x), 1.1, zf(p.y))
	for i in _pops.size():
		var l: Label3D = _pops[i]
		l.visible = i < g.popups.size()
		if l.visible:
			var pp: Dictionary = g.popups[i]
			var pv: Vector2 = pp["p"]
			l.text = String(pp["s"])
			l.modulate = Color(pp["c"], clampf(float(pp["life"]) / 0.4, 0.0, 1.0))
			l.position = Vector3(xf(pv.x), 2.2 + (1.0 - float(pp["life"])) * 1.2, zf(pv.y) + 0.4)
	# The sled and you.
	var x := xf(g.sieve_x)
	var vx := (x - _sx) / maxf(delta, 0.001)
	_sx = x
	_sled.position = Vector3(x, 0, 0)
	_sled.rotation.z = clampf(-vx * 0.02, -0.18, 0.18)
	if _avatar:
		_avatar.update_movement(Vector3.ZERO, true, false)
	camera.position = Vector3(x * 0.55, 3.1, 6.2)
	camera.look_at(Vector3(x * 0.3, 1.3, -14.0), Vector3.UP)


func hud() -> Dictionary:
	var g = game
	var stats := PackedStringArray(["LEVEL %d" % g.level, "x%d · COMBO %d" % [g.multiplier(), g.combo]])
	if g.last_event != "":
		stats.append(g.last_event)
	return {"stats": stats, "flash": g.flash, "flash_color": g.flash_c,
		"center": g.last_event if g.flash > 0.2 else "", "center_color": g.flash_c}
