class_name HeartOrrery
extends Node3D
## The Heart (where Beat happens), redesigned as an armillary orrery. Every part
## is one of the territory's numbers; nothing is decoration for its own sake:
## - the core: a faceted crystal (icosahedron) holding a light, in the
##   territory's own colour (DeepField hue);
## - the rings: one gimbal ring per development tier (Wild 1 … Capital 6), each
##   tilted by the Julia parameter c's angle plus the golden angle, carrying one
##   bead (a body in orbit); they turn faster with the territory's energy
##   (Epibar total). Same for every viewer.
## - the heartbeat: a soft tick on every new block the territory is read at (the
##   chain's own clock), a full beat (rings flare, a shock ring spreads) when a
##   Beat is confirmed here, a smaller one when bars move (a Su lands).

const RING_R0 := 2.1
const RING_STEP := 0.55
const GOLDEN := 2.399963  # radians
const MAX_RINGS := 6

var tint := Color("#7fd3ff")
var tint2 := Color("#ffb070")
var params: Dictionary = {}
var tier := -1
var energy := 0.0
var _shell: MeshInstance3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _shell_mat: StandardMaterial3D
var _rings: Array = []   # [{node: Node3D, speed: float, base_tilt: Vector3}]
var _ring_mat: StandardMaterial3D
var _bead_mat: StandardMaterial3D
var _lamp: OmniLight3D
var _shock: MeshInstance3D
var _shock_mat: StandardMaterial3D
var _t := 0.0
var _beat := 0.0   # 0..1, decays
var _shock_t := 1.0


func build(p: Dictionary, p_tint: Color, p_tint2: Color) -> void:
	params = p
	tint = p_tint
	tint2 = p_tint2
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.03, 0.04, 0.06, 0.55)
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.metallic = 0.8
	_shell_mat.roughness = 0.08
	_shell_mat.rim_enabled = true
	_shell_mat.rim = 0.8
	_shell_mat.rim_tint = 0.6
	_shell_mat.emission_enabled = true
	_shell_mat.emission = tint * 0.25
	_shell = MeshInstance3D.new()
	_shell.name = "Crystal"
	_shell.mesh = icosahedron(1.05)
	_shell.material_override = _shell_mat
	add_child(_shell)
	_core = MeshInstance3D.new()
	_core.name = "Light"
	var s := SphereMesh.new()
	s.radius = 0.42
	s.height = 0.84
	s.radial_segments = 16
	s.rings = 8
	_core.mesh = s
	_core_mat = _glow(tint.lerp(Color.WHITE, 0.45), 3.0)
	_core.material_override = _core_mat
	add_child(_core)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.75, 0.8, 0.9)
	_ring_mat.metallic = 0.9
	_ring_mat.roughness = 0.25
	_ring_mat.emission_enabled = true
	_ring_mat.emission = tint
	_ring_mat.emission_energy_multiplier = 0.6
	_bead_mat = _glow(tint2.lerp(Color.WHITE, 0.3), 2.5)
	_shock_mat = _glow(tint, 1.5)
	_shock_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shock_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shock = MeshInstance3D.new()
	var st := TorusMesh.new()
	st.inner_radius = 0.96
	st.outer_radius = 1.0
	st.rings = 64
	st.ring_segments = 6
	_shock.mesh = st
	_shock.material_override = _shock_mat
	_shock.visible = false
	add_child(_shock)
	_lamp = OmniLight3D.new()
	_lamp.light_color = tint
	_lamp.light_energy = 1.4
	_lamp.omni_range = 28.0
	add_child(_lamp)
	set_development(0, 0.0)


static func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## A flat-shaded icosahedron (a crystal: every facet catches the light).
static func icosahedron(r: float) -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var stool := SurfaceTool.new()
	stool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in f:
		for k in [0, 2, 1]:  # Godot's front faces wind clockwise
			stool.add_vertex((v[tri[k]] as Vector3).normalized() * r * Vector3(1.0, 1.35, 1.0))
	stool.generate_normals()
	return stool.commit()


## Ring tilt i (pure: from c's angle and the golden angle).
static func ring_tilt(c: Array, i: int) -> Vector3:
	var theta := atan2(float(c[1]), float(c[0])) if c.size() >= 2 else 0.0
	return Vector3(deg_to_rad(18.0 + 14.0 * float(i % 4)) * (1.0 if i % 2 == 0 else -1.0), theta + GOLDEN * i, 0.0)


## Rings for a tier (Wild 1 … Capital 6).
static func rings_for(t: int) -> int:
	return clampi(t + 1, 1, MAX_RINGS)


func set_development(t: int, e: float) -> void:
	energy = clampf(e, 0.0, 1.0)
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 0.4 + 1.2 * energy
	if t == tier:
		return
	tier = t
	for r in _rings:
		(r["node"] as Node3D).queue_free()
	_rings.clear()
	var c: Array = params.get("c", [0.0, 0.0])
	for i in rings_for(t):
		var g := Node3D.new()
		g.name = "Ring%d" % i
		g.rotation = ring_tilt(c, i)
		add_child(g)
		var spin := Node3D.new()
		g.add_child(spin)
		var radius := RING_R0 + RING_STEP * i
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = radius - 0.035
		tm.outer_radius = radius + 0.035
		tm.rings = 72
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = _ring_mat
		spin.add_child(ring)
		var bead := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.12 + 0.03 * (i % 3)
		bs.height = bs.radius * 2.0
		bs.radial_segments = 12
		bs.rings = 6
		bead.mesh = bs
		bead.material_override = _bead_mat
		bead.position = Vector3(radius, 0.0, 0.0)
		spin.add_child(bead)
		_rings.append({"node": g, "spin": spin, "speed": (0.22 + 0.06 * i) * (1.0 if i % 2 == 0 else -1.0)})


## A confirmed Beat here: the full heartbeat.
func beat(strength: float = 1.0) -> void:
	_beat = maxf(_beat, clampf(strength, 0.0, 1.0))
	_shock_t = 0.0
	_shock.visible = true


## A new block was read here: the chain's clock, a soft tick.
func tick() -> void:
	_beat = maxf(_beat, 0.18)


func _process(delta: float) -> void:
	_t += delta
	_beat = maxf(0.0, _beat - delta * 0.9)
	var speed := 0.35 + 1.3 * energy
	for r in _rings:
		(r["spin"] as Node3D).rotation.y += float(r["speed"]) * speed * delta
	var b := _beat * _beat
	_shell.rotation.y += delta * 0.12
	_shell.scale = Vector3.ONE * (1.0 + 0.12 * b)
	_core.scale = Vector3.ONE * (1.0 + 0.6 * b + 0.05 * sin(_t * 1.3))
	_core_mat.emission_energy_multiplier = 2.4 + 5.0 * b
	_lamp.light_energy = 1.2 + 2.5 * b
	for i in _rings.size():
		var n: Node3D = _rings[i]["node"]
		n.scale = Vector3.ONE * (1.0 + 0.08 * b * (1.0 + i * 0.3))
	if _shock.visible:
		_shock_t += delta * 0.7
		var u := clampf(_shock_t, 0.0, 1.0)
		var rad := 2.0 + 16.0 * u
		_shock.scale = Vector3(rad, 1.0, rad)
		_shock_mat.albedo_color.a = (1.0 - u) * 0.8
		_shock_mat.emission_energy_multiplier = 1.5 * (1.0 - u)
		if u >= 1.0:
			_shock.visible = false
