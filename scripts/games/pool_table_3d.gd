class_name PoolTable3D
extends Node3D
## A 9-foot table in the room. It shows a PoolSim position (from the replayed
## room lines) and plays a shot back from its frames. Felt 2.54 × 1.27 m,
## the bed 0.8 m up; the sim's x runs along the table's X axis.

const BED := 0.8
const COLORS := [Color(0.95, 0.94, 0.9), Color(1.0, 0.8, 0.1), Color(0.1, 0.25, 0.85), Color(0.85, 0.12, 0.1),
	Color(0.45, 0.15, 0.6), Color(1.0, 0.45, 0.05), Color(0.05, 0.5, 0.2), Color(0.5, 0.08, 0.1), Color(0.03, 0.03, 0.03)]
const FRAME_EVERY := 8  # sim ticks per animation frame (480 Hz / 8 = 60 fps)

signal roll_finished

var felt_color := Color(0.05, 0.36, 0.2)
var hold_frame := -1  ## previews: stop a replay at this frame (mid-roll stills)
var _balls: Array = []
var _frames: Array = []
var _frame_t := 0.0
var _label: Label3D
var _last := PackedInt64Array()


func build(cloth: Color = Color(0.05, 0.36, 0.2)) -> void:
	felt_color = cloth
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.14, 0.07)
	wood.roughness = 0.45
	var felt := StandardMaterial3D.new()
	felt.albedo_color = felt_color
	felt.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	_box(Vector3(2.54, 0.04, 1.27), Vector3(0, BED - 0.02, 0), felt)
	_box(Vector3(2.9, 0.16, 1.63), Vector3(0, BED - 0.12, 0), wood)  # apron
	for sz in [-1.0, 1.0]:  # long rails (with the felt cushion's lip)
		_box(Vector3(2.54, 0.06, 0.06), Vector3(0, BED + 0.02, sz * 0.665), felt)
		_box(Vector3(2.9, 0.07, 0.12), Vector3(0, BED + 0.035, sz * 0.755), wood)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.06, 1.27), Vector3(sx * 1.3, BED + 0.02, 0), felt)
		_box(Vector3(0.12, 0.07, 1.63), Vector3(sx * 1.39, BED + 0.035, 0), wood)
	for p in PoolSim.pockets():
		var pocket := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.065
		cm.bottom_radius = 0.06
		cm.height = 0.02
		pocket.mesh = cm
		pocket.material_override = dark
		pocket.position = _to3(p.x, p.y) + Vector3(0, 0.002, 0)
		add_child(pocket)
	for sx in [-1.0, 1.0]:  # legs
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.16, BED - 0.2, 0.16), Vector3(sx * 1.2, (BED - 0.2) * 0.5, sz * 0.6), wood)
	for i in 16:
		var b := _ball(i)
		add_child(b)
		_balls.append(b)
	_label = Label3D.new()
	_label.font = DeepFieldTheme.mono_font()
	_label.font_size = 28
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, BED + 0.9, 0)
	_label.modulate = Color(0.85, 0.95, 1.0)
	add_child(_label)
	show_sim(PoolSim.new())
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.9, BED + 0.1, 1.63)
	cs.shape = sh
	cs.position = Vector3(0, (BED + 0.1) * 0.5, 0)
	body.add_child(cs)


func _ball(i: int) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0286
	sm.height = 0.0572
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.roughness = 0.15
	var base: Color = COLORS[i if i <= 8 else i - 8]
	m.albedo_color = Color(0.95, 0.94, 0.9) if i >= 9 else base
	mi.material_override = m
	n.add_child(mi)
	# A spot on every ball (the cue ball's is red, like a measle ball), so a roll reads up close.
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.0105
	dm.height = 0.006
	dm.radial_segments = 12
	dm.rings = 2
	dot.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.85, 0.1, 0.1) if i == 0 else Color(0.97, 0.96, 0.92)
	dmat.roughness = 0.2
	dot.material_override = dmat
	dot.position = Vector3(0, 0.0262, 0)
	n.add_child(dot)
	if i >= 9:  # the stripe
		var band := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0289
		cm.bottom_radius = 0.0289
		cm.height = 0.03
		band.mesh = cm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = base
		bm.roughness = 0.15
		band.material_override = bm
		band.rotation_degrees.z = 90.0
		n.add_child(band)
	return n


func _to3(x: int, y: int) -> Vector3:
	return Vector3(float(x) / 1e6 - 1.27, BED + 0.0286, float(y) / 1e6 - 0.635)


## The position on screen now (a snapshot), the frame playing during a replay.
func current_snapshot() -> PackedInt64Array:
	return _last


func is_rolling() -> bool:
	return not _frames.is_empty()


## Shows a table position at rest.
func show_sim(sim: PoolSim) -> void:
	_frames.clear()
	show_snapshot(sim.snapshot())


func show_snapshot(s: PackedInt64Array) -> void:
	var roll := _last.size() == s.size()
	for i in 16:
		var b: Node3D = _balls[i]
		b.visible = s[i * 3 + 2] == 0
		var to := _to3(s[i * 3], s[i * 3 + 1])
		if roll and b.visible:
			var d := to - b.position
			var l := d.length()
			if l > 1e-5 and l < 0.5:  # rolling without slipping: turn by distance / radius
				b.rotate(Vector3.UP.cross(d / l).normalized(), l / 0.0286)
		b.position = to
	_last = s


## Plays a shot: from the position before it (a snapshot), re-run with frames.
func play_shot(before: PackedInt64Array, dx: int, dy: int, power: int) -> void:
	var sim := PoolSim.new()
	sim.apply_snapshot(before)
	play_frames(before, sim.shoot(dx, dy, power, FRAME_EVERY).get("frames", []))


## Plays recorded frames (every FRAME_EVERY ticks) from a position.
func play_frames(before: PackedInt64Array, frames: Array) -> void:
	_frames = frames
	_frame_t = 0.0
	show_snapshot(before)


## Seated play hides the floating caption (the overlay says it instead).
func show_caption(on: bool) -> void:
	if _label:
		_label.visible = on


func set_caption(text: String) -> void:
	if _label:
		_label.text = text


func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	_frame_t += delta * 60.0
	if hold_frame >= 0:
		_frame_t = minf(_frame_t, float(hold_frame))
	var i := int(_frame_t)
	if i >= _frames.size():
		show_snapshot(_frames[-1])
		_frames.clear()
		roll_finished.emit()
		return
	show_snapshot(_frames[i])


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	add_child(mi)
