class_name CrowModel
extends Node3D
## A crow built from feathers: a glossy blue-black body and head, a heavy
## beak, two-part wings (an arm panel with its row of secondaries, and a hand
## of five splayed primaries that folds at the wrist), and a fan tail.
## Faces -Z, Y up; about a real crow's size (≈ 0.85 m wingspan).
##
## animate(delta, mode, bank) drives it: mode "flap", "glide" or "perch".

const PRIMARIES := 5
const TAIL_FEATHERS := 7

var _feather: StandardMaterial3D
var _beak_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _shoulder := {}  # side (+1 right, -1 left) → Node3D
var _wrist := {}
var _primaries := {}  # side → Array[Node3D]
var _tail: Node3D
var _tail_feathers: Array = []
var _head: Node3D
var _phase := 0.0
var _flap := 0.0  # 0 (wings still) … 1 (full stroke)
var _fold := 0.0  # 0 spread … 1 folded on the back (perched)
var _look_t := 0.0
var _look := 0.0


func _ready() -> void:
	_materials()
	_build()


func _materials() -> void:
	_feather = StandardMaterial3D.new()
	_feather.albedo_color = Color(0.055, 0.06, 0.085)
	_feather.metallic = 0.35
	_feather.roughness = 0.32
	_feather.rim_enabled = true  # the blue sheen along the edges, so it reads against a dark sky
	_feather.rim = 0.55
	_feather.rim_tint = 0.25
	_feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beak_mat = StandardMaterial3D.new()
	_beak_mat.albedo_color = Color(0.09, 0.09, 0.1)
	_beak_mat.roughness = 0.25
	_beak_mat.metallic = 0.2
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.16, 0.1, 0.05)
	_eye_mat.roughness = 0.05
	_eye_mat.metallic = 0.4


func _build() -> void:
	var body := _ellipsoid(Vector3(0.062, 0.06, 0.17), _feather)
	add_child(body)
	var chest := _ellipsoid(Vector3(0.06, 0.06, 0.085), _feather)
	chest.position = Vector3(0.0, -0.012, -0.07)
	add_child(chest)
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.04, -0.19)
	add_child(_head)
	_head.add_child(_ellipsoid(Vector3(0.052, 0.05, 0.06), _feather))
	var beak := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.021
	cm.height = 0.095
	cm.radial_segments = 10
	beak.mesh = cm
	beak.material_override = _beak_mat
	beak.rotation_degrees.x = -90.0  # tip forward (-Z)
	beak.position = Vector3(0.0, -0.008, -0.095)
	beak.scale = Vector3(1.0, 1.0, 0.8)  # deeper than wide, like a crow's
	_head.add_child(beak)
	for sx in [-1.0, 1.0]:
		var eye := _ellipsoid(Vector3(0.0095, 0.0095, 0.0095), _eye_mat)
		eye.position = Vector3(sx * 0.036, 0.012, -0.03)
		_head.add_child(eye)
	# Tail fan
	_tail = Node3D.new()
	_tail.position = Vector3(0.0, 0.012, 0.13)
	add_child(_tail)
	for i in TAIL_FEATHERS:
		var f := Node3D.new()
		f.rotation.y = lerpf(-0.32, 0.32, float(i) / float(TAIL_FEATHERS - 1))
		f.position.y = 0.001 * abs(i - TAIL_FEATHERS / 2)
		var leaf := _leaf(0.15, 0.04, Vector3.BACK)
		leaf.material_override = _feather
		f.add_child(leaf)
		_tail.add_child(f)
		_tail_feathers.append(f)
	# Feet, tucked
	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.006
		lc.bottom_radius = 0.004
		lc.height = 0.06
		leg.mesh = lc
		leg.material_override = _beak_mat
		leg.position = Vector3(sx * 0.03, -0.065, 0.02)
		leg.rotation_degrees.x = 35.0
		add_child(leg)
	for side in [1.0, -1.0]:
		_wing(side)


func _wing(side: float) -> void:
	var sh := Node3D.new()
	sh.position = Vector3(side * 0.055, 0.035, -0.035)
	add_child(sh)
	_shoulder[side] = sh
	# The arm: a panel, its trailing edge made of overlapping secondaries.
	var arm := _panel([Vector2(0.0, -0.055), Vector2(0.2, -0.045), Vector2(0.21, 0.045), Vector2(0.1, 0.07), Vector2(0.0, 0.06)], side)
	sh.add_child(arm)
	for i in 6:
		var x := 0.02 + i * 0.034
		var sec := _leaf(0.085, 0.034, Vector3.BACK)
		sec.material_override = _feather
		sec.position = Vector3(side * x, -0.001 * i, 0.03)
		sec.rotation.y = side * -0.08
		sh.add_child(sec)
	var wr := Node3D.new()
	wr.position = Vector3(side * 0.205, 0.0, 0.0)
	sh.add_child(wr)
	_wrist[side] = wr
	wr.add_child(_panel([Vector2(0.0, -0.045), Vector2(0.09, -0.03), Vector2(0.1, 0.03), Vector2(0.0, 0.05)], side))
	var ps: Array = []
	for i in PRIMARIES:
		var f := Node3D.new()
		f.position = Vector3(side * 0.07, 0.002 * i, lerpf(-0.025, 0.035, float(i) / float(PRIMARIES - 1)))
		var leaf := _leaf(lerpf(0.2, 0.16, float(i) / float(PRIMARIES - 1)), 0.036, Vector3(side, 0, 0))
		leaf.material_override = _feather
		f.add_child(leaf)
		wr.add_child(f)
		ps.append(f)
	_primaries[side] = ps


## A flat wing panel from a polygon in wing space (x outward, y back); mirrored for the left.
func _panel(poly: Array, side: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3.ZERO
	for p in poly:
		c += Vector3(side * p.x, 0.0, p.y)
	c /= poly.size()
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		for v in [c, Vector3(side * a.x, 0.0, a.y), Vector3(side * b.x, 0.0, b.y)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _feather
	return mi


## A feather: a pointed leaf `length` long along `dir` (in the XZ plane), widest a third of the way.
func _leaf(length: float, width: float, dir: Vector3) -> MeshInstance3D:
	var along := dir.normalized()
	var across := Vector3.UP.cross(along).normalized()
	var pts: Array = []
	var n := 7
	for i in n + 1:  # one edge out to the tip …
		var u := float(i) / float(n)
		pts.append(along * u * length + across * _half_width(u, width))
	for i in range(n - 1, 0, -1):  # … and back along the other
		var u := float(i) / float(n)
		pts.append(along * u * length - across * _half_width(u, width))
	pts.append(-across * width * 0.18)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector3 = along * length * 0.35
	for i in pts.size():
		for v in [c, pts[i], pts[(i + 1) % pts.size()]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


static func _half_width(u: float, width: float) -> float:
	if u < 0.33:
		return width * (0.18 + 0.32 * u / 0.33)
	return width * 0.5 * sqrt(maxf(0.0, 1.0 - pow((u - 0.33) / 0.67, 2.0)))


func _ellipsoid(radii: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.scale = radii
	mi.material_override = mat
	return mi


## mode: "flap" (a full wingbeat), "glide" (held out, slight dihedral) or
## "perch" (folded on the back). bank: roll in radians, spreads the tail.
func animate(delta: float, mode: String, bank: float = 0.0) -> void:
	var want_flap := 1.0 if mode == "flap" else 0.0
	var want_fold := 1.0 if mode == "perch" else 0.0
	_flap = move_toward(_flap, want_flap, delta * 3.0)
	_fold = move_toward(_fold, want_fold, delta * 2.5)
	_phase += delta * TAU * 3.2
	var s := sin(_phase)
	for side in [1.0, -1.0]:
		var sh: Node3D = _shoulder[side]
		var wr: Node3D = _wrist[side]
		# Downstroke and upstroke about the body's long axis; the wrist bends
		# on the way up so the hand slices back through the air.
		var stroke := s * 0.85 * _flap + 0.14 * (1.0 - _flap)
		var wrist_bend := maxf(0.0, -sin(_phase + 0.7)) * 0.75 * _flap
		# Folded: the whole wing swings back along the flank and droops a little.
		sh.rotation = Vector3(0.0, side * -_fold * 1.45, side * stroke * (1.0 - _fold) - side * _fold * 0.12)
		wr.rotation = Vector3(0.0, side * (-wrist_bend * 0.6 - _fold * 0.2), side * -wrist_bend)
		var ps: Array = _primaries[side]
		for i in ps.size():
			var spread := (float(i) / float(ps.size() - 1)) * (0.5 - 0.35 * _fold)
			(ps[i] as Node3D).rotation.y = side * -spread
	_tail.rotation.x = -0.08 + 0.1 * _fold
	var fan := 0.6 + 0.8 * clampf(absf(bank) * 2.0, 0.0, 1.0) - 0.4 * _fold
	for i in _tail_feathers.size():
		(_tail_feathers[i] as Node3D).rotation.y = lerpf(-0.32, 0.32, float(i) / float(_tail_feathers.size() - 1)) * fan
	# The head looks about now and then (more when perched).
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = randf_range(0.6, 2.2)
		_look = randf_range(-0.9, 0.9) * (0.4 + 0.6 * _fold)
	_head.rotation.y = lerp_angle(_head.rotation.y, _look, delta * 8.0)
	_head.rotation.x = 0.1 * _fold
