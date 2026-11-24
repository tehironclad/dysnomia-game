class_name CoreDressing
extends Node3D
## Architectural detail around the Core (2026-11-24): the plaza's paving, kerb,
## inlaid light lines and bollards; the Room's plinth, cornice and door portal;
## bases for the monolith, the World plinth and the arcade front. Built from the
## CC0 kits (Quaternius Modular Sci-Fi MegaKit, Poly Haven metal plates); every
## repeated piece is a MultiMesh. Decoration only: it encodes nothing, so it
## stays dim and lets the numbers (wells, pylons, Heart, towers) lead. Same for
## every viewer.

const PLAZA_R := 22.0
const TEX := "res://assets/textures/polyhaven/%s/%s.jpg"

static var _mats := {}

var tint := Color("#7fd3ff")


static func pbr(id: String, col: Color, uv_scale: float, metal: float = 1.0, rough: float = 1.0) -> ORMMaterial3D:
	var key := "%s:%s:%s:%s" % [id, col.to_html(), uv_scale, metal]
	if _mats.has(key):
		return _mats[key]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(TEX % [id, "diff"])
	m.albedo_color = col
	m.normal_enabled = true
	m.normal_texture = load(TEX % [id, "nor_gl"])
	m.orm_texture = load(TEX % [id, "arm"])
	m.metallic = metal
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


static func dark_metal() -> ORMMaterial3D:
	return pbr("metal_plate", Color(0.32, 0.34, 0.4), 0.5, 0.9, 0.55)


func build(p_tint: Color, room_radius: float) -> void:
	tint = p_tint
	_plaza()
	_room(room_radius)


static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, scale_v: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.scale = scale_v
	parent.add_child(mi)
	return mi


static func _cyl(r_top: float, r_bot: float, h: float, seg: int = 48) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _torus(r_in: float, r_out: float, rings: int = 96, seg: int = 6) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = rings
	t.ring_segments = seg
	return t


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## A MultiMesh of `mesh` at the given transforms (one draw call).
static func multi(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material, shadows: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Angles (radians) where the plaza's rim stays open: the avenue from the door
## (+Z) and the four compass roads.
static func _open_at(a: float) -> bool:
	for open in [PI * 0.5, 0.0, PI, PI * 1.5]:
		if absf(wrapf(a - open, -PI, PI)) < deg_to_rad(9.0):
			return true
	return false


func _plaza() -> void:
	# Paving: a low disc of dark metal plates over the flat Core plain.
	var pave := pbr("metal_plate_02", Color(0.2, 0.21, 0.25), 0.22, 0.6, 0.8)
	_mesh(self, _cyl(PLAZA_R, PLAZA_R + 0.25, 0.14, 96), Vector3(0.0, -0.03, 0.0), pave).name = "Paving"
	# Kerb and inlaid rings.
	_mesh(self, _torus(PLAZA_R - 0.12, PLAZA_R + 0.32, 128, 8), Vector3(0.0, 0.03, 0.0), dark_metal(), Vector3(1.0, 0.45, 1.0)).name = "Kerb"
	var line := glow(tint.lerp(Color.WHITE, 0.2), 1.3)
	for r in [10.6, PLAZA_R - 0.6]:
		var ring := _mesh(self, _torus(r - 0.05, r + 0.05, 128, 4), Vector3(0.0, 0.05, 0.0), line, Vector3(1.0, 0.25, 1.0))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Radial light lines between the rings (24, one MultiMesh), and paving joints.
	var strips: Array = []
	var joints: Array = []
	for i in 24:
		var a := TAU * (i + 0.5) / 24.0
		var mid := (10.9 + PLAZA_R - 0.9) * 0.5
		var b := Basis(Vector3.UP, -a + PI * 0.5)
		if i % 2 == 0:
			strips.append(Transform3D(b, Vector3(cos(a) * mid, 0.045, sin(a) * mid)))
		else:
			joints.append(Transform3D(b, Vector3(cos(a) * mid, 0.045, sin(a) * mid)))
	multi(self, _box(Vector3(0.07, 0.02, PLAZA_R - 11.8)), strips, glow(tint, 0.9), false).name = "LightLines"
	multi(self, _box(Vector3(0.05, 0.02, PLAZA_R - 11.8)), joints, dark_metal(), false).name = "Joints"
	# Bollards round the rim, lit caps (two MultiMeshes), gaps at the roads.
	var posts: Array = []
	for i in 40:
		var a := TAU * i / 40.0
		if _open_at(a):
			continue
		posts.append(Transform3D(Basis(), Vector3(cos(a), 0.0, sin(a)) * (PLAZA_R - 0.9)))
	var post_xf := posts.map(func(t): return t.translated(Vector3(0.0, 0.45, 0.0)))
	var cap_xf := posts.map(func(t): return t.translated(Vector3(0.0, 0.93, 0.0)))
	multi(self, _cyl(0.1, 0.14, 0.9, 8), post_xf, dark_metal()).name = "Bollards"
	multi(self, _cyl(0.11, 0.11, 0.06, 8), cap_xf, glow(tint.lerp(Color.WHITE, 0.4), 2.2), false).name = "BollardLights"


func _room(room_r: float) -> void:
	var metal := dark_metal()
	# Plinth band round the base of the Room's wall and a cornice on top.
	_mesh(self, _torus(room_r + 1.0, room_r + 2.7, 96, 8), Vector3(0.0, 0.05, 0.0), metal, Vector3(1.0, 0.18, 1.0)).name = "RoomPlinth"
	_mesh(self, _torus(room_r + 2.05, room_r + 2.4, 96, 6), Vector3(0.0, 4.25, 0.0), metal, Vector3(1.0, 0.5, 1.0)).name = "RoomCornice"
	# The door portal: columns either side, a canopy with a lit edge, a threshold.
	var z := room_r + 0.9
	for sx in [-1.0, 1.0]:
		var col := PlaceBase.load_piece("Column_Astra")
		col.position = Vector3(sx * 2.05, 0.0, z)
		col.scale = Vector3(0.75, 0.88, 0.75)
		add_child(col)
		var lamp := PlaceBase.load_piece("Prop_Light_Floor")
		lamp.position = Vector3(sx * 2.9, 0.0, z + 1.6)
		add_child(lamp)
	_mesh(self, _box(Vector3(5.0, 0.16, 2.2)), Vector3(0.0, 3.55, z + 0.5), metal).name = "Canopy"
	_mesh(self, _box(Vector3(5.0, 0.05, 0.06)), Vector3(0.0, 3.47, z + 1.6), glow(tint, 2.0)).name = "CanopyEdge"
	_mesh(self, _box(Vector3(3.4, 0.08, 2.4)), Vector3(0.0, 0.04, z + 0.9), pbr("metal_plate", Color(0.5, 0.52, 0.58), 0.6, 0.9, 0.5)).name = "Threshold"
	var light := SpotLight3D.new()
	light.light_color = tint.lerp(Color.WHITE, 0.5)
	light.light_energy = 2.0
	light.spot_range = 7.0
	light.spot_angle = 50.0
	light.position = Vector3(0.0, 3.4, z + 0.8)
	light.rotation_degrees.x = -90.0
	add_child(light)


## A dark stepped base under a standing object (the monolith, the World plinth),
## in the object's own space; `w`×`d` is the object's footprint.
static func base_under(parent: Node3D, w: float, d: float, accent: Color) -> void:
	var metal := dark_metal()
	_mesh(parent, _box(Vector3(w + 1.6, 0.22, d + 1.6)), Vector3(0.0, 0.11, 0.0), metal).name = "BaseLow"
	_mesh(parent, _box(Vector3(w + 0.8, 0.2, d + 0.8)), Vector3(0.0, 0.32, 0.0), metal).name = "BaseHigh"
	var edge := _mesh(parent, _box(Vector3(w + 0.84, 0.03, d + 0.84)), Vector3(0.0, 0.43, 0.0), glow(accent, 1.6))
	edge.name = "BaseEdge"
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The arcade front's street furniture, in its own space (front face at z = 0,
## facing +Z, block 11 × 7 m behind it): a stepped forecourt, pilasters at the
## corners, floor lamps by the door and side vents.
static func dress_arcade(front: Node3D, accent: Color) -> void:
	var metal := dark_metal()
	_mesh(front, _box(Vector3(9.0, 0.1, 3.0)), Vector3(0.0, 0.05, 1.5), pbr("metal_plate_02", Color(0.3, 0.31, 0.36), 0.3, 0.7, 0.7)).name = "Forecourt"
	var edge := _mesh(front, _box(Vector3(9.0, 0.03, 0.05)), Vector3(0.0, 0.11, 3.0), glow(accent, 1.4))
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		_mesh(front, _box(Vector3(0.5, 6.6, 0.5)), Vector3(sx * 5.65, 3.3, 0.1), metal).name = "Pilaster"
		var lamp := PlaceBase.load_piece("Prop_Light_Floor")
		lamp.position = Vector3(sx * 1.9, 0.0, 1.2)
		front.add_child(lamp)
		var vent := PlaceBase.load_piece("Prop_Vent_Big")
		vent.position = Vector3(sx * 5.9, 0.0, -3.5)
		vent.rotation_degrees.y = 90.0 * sx
		vent.scale = Vector3.ONE * 0.7
		front.add_child(vent)
