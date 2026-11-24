class_name VehicleModels
extends RefCounted
## Procedural models of the garage vehicles (primitives only, Deep Field palette:
## white hardware, dark trim, the single ice accent, the territory's own colour
## as the stripe). Forward is -Z; the origin is the ground contact point.
##
## build() returns the parts the vehicle animates:
##   body      Node3D holding everything that rides on the suspension
##   wheels    [{node, spin, rest: Vector3, radius}] wheel pivots, not parented: the vehicle
##             adds them to itself so they stay on the ground while the body bobs
##   lights    [Vector3] headlight positions in body space
##   flames    [Node3D] thruster flame pivots (scaled along Y by thrust)
##   tracks    [StandardMaterial3D] track materials (UV scrolled with speed)
##   beacon    Node3D that spins (or null)
##   probes    [Vector3] ground probe points in vehicle space (corners) for tilt

const HULL := Color(0.83, 0.85, 0.89)
const TRIM := Color(0.075, 0.08, 0.1)
const STEEL := Color(0.42, 0.44, 0.5)

static var _mats := {}


static func build(kind: String, tint: Color) -> Dictionary:
	var out := {"body": Node3D.new(), "wheels": [], "lights": [], "flames": [], "tracks": [], "beacon": null, "probes": []}
	out["body"].name = "Body"
	match kind:
		"hoverbike":
			_hoverbike(out, tint)
		"skimmer":
			_skimmer(out, tint)
		"hopper":
			_hopper(out, tint)
		"crawler":
			_crawler(out, tint)
		_:
			_rover(out, tint)
	return out


# --- materials (shared per colour) --------------------------------------------

static func mat(c: Color, rough: float = 0.5, metal: float = 0.2) -> StandardMaterial3D:
	var key := "m%s/%.2f/%.2f" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


static func glow(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "g%s/%.2f" % [c.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


static func glass() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.55, 0.8, 1.0, 0.22)
		m.roughness = 0.05
		m.metallic = 0.6
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["glass"] = m
	return _mats["glass"]


static func flame_mat() -> StandardMaterial3D:
	if not _mats.has("flame"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.55, 0.85, 1.0, 0.75)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["flame"] = m
	return _mats["flame"]


## A track belt: dark rubber with cleats, scrolled along V by the vehicle.
static func track_mat() -> StandardMaterial3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.09, 0.09, 0.1), Color(0.11, 0.11, 0.12), Color(0.32, 0.33, 0.36), Color(0.32, 0.33, 0.36)])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.9
	m.uv1_scale = Vector3(1.0, 10.0, 1.0)
	m.texture_repeat = true
	return m


# --- helpers --------------------------------------------------------------------

static func _m(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _cyl(top: float, bottom: float, h: float, seg: int = 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 20
	c.rings = 6
	return c


static func _sphere(r: float, hemi: bool = false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = 24
	s.rings = 10
	return s


static func _flame(parent: Node3D, pos: Vector3, length: float, radius: float, rot: Vector3 = Vector3.ZERO) -> Node3D:
	## A cone of light pointing down its local -Y, pivoting at the nozzle.
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation = rot
	parent.add_child(pivot)
	var f := _m(pivot, _cyl(radius, 0.02, length, 12), flame_mat(), Vector3(0, -length * 0.5, 0))
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.scale = Vector3(1, 0.05, 1)
	return pivot


static func _wheel(out: Dictionary, parent: Node3D, at: Vector3, r: float, w: float, tint: Color) -> void:
	var pivot := Node3D.new()
	pivot.position = at
	if parent:
		parent.add_child(pivot)
	var spin := Node3D.new()
	spin.name = "Spin"
	pivot.add_child(spin)
	# Mesh tyre (the Apollo rover's woven wire, here a dark ribbed drum) and a bright hub.
	_m(spin, _cyl(r, r, w, 18), mat(Color(0.16, 0.16, 0.17), 0.95, 0.1), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	_m(spin, _box(w * 1.04, r * 0.32, r * 2.02), mat(Color(0.3, 0.3, 0.32), 0.8, 0.3), Vector3.ZERO)
	_m(spin, _cyl(r * 0.45, r * 0.45, w * 1.08, 12), mat(HULL, 0.4, 0.08), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	_m(spin, _cyl(r * 0.16, r * 0.16, w * 1.14, 8), glow(tint, 1.6), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	out["wheels"].append({"node": pivot, "spin": spin, "rest": at, "radius": r})


static func _headlight(out: Dictionary, parent: Node3D, at: Vector3, r: float = 0.11) -> void:
	_m(parent, _cyl(r, r * 1.2, 0.12, 12), glow(Color(1.0, 0.96, 0.86), 3.5), at, Vector3(PI * 0.5, 0, 0))
	out["lights"].append(at + Vector3(0, 0, -0.1))


static func _taillight(parent: Node3D, at: Vector3, size: Vector3 = Vector3(0.22, 0.08, 0.04)) -> void:
	_m(parent, _box(size.x, size.y, size.z), glow(Color(1.0, 0.22, 0.25), 2.5), at)


# --- the five vehicles ------------------------------------------------------------

static func _rover(out: Dictionary, tint: Color) -> void:
	var b: Node3D = out["body"]
	var hull := mat(HULL, 0.45, 0.08)
	var trim := mat(TRIM, 0.7, 0.3)
	# Chassis tray, a lower spine, fenders over each wheel line
	_m(b, _box(2.1, 0.22, 3.7), hull, Vector3(0, 0.78, 0))
	_m(b, _box(1.1, 0.3, 3.2), trim, Vector3(0, 0.6, 0))
	for sx in [-1.0, 1.0]:
		_m(b, _box(0.52, 0.07, 4.0), hull, Vector3(sx * 1.3, 1.02, 0))
		_m(b, _box(0.04, 0.06, 3.6), glow(tint, 1.8), Vector3(sx * 1.06, 0.8, 0))
	# Console, single seat with a roll hoop behind it
	_m(b, _box(1.3, 0.38, 0.34), trim, Vector3(0, 1.08, -0.75))
	_m(b, _box(0.8, 0.02, 0.22), glow(DeepFieldTheme.ICE, 1.2), Vector3(0, 1.28, -0.72), Vector3(-0.5, 0, 0))
	_m(b, _box(0.62, 0.12, 0.6), trim, Vector3(0, 0.95, 0.25))
	_m(b, _box(0.62, 0.62, 0.1), trim, Vector3(0, 1.25, 0.58), Vector3(-0.18, 0, 0))
	for sx in [-1.0, 1.0]:
		_m(b, _cyl(0.04, 0.04, 1.25), mat(STEEL, 0.4, 0.7), Vector3(sx * 0.62, 1.45, 0.78))
	_m(b, _cyl(0.04, 0.04, 1.28), mat(STEEL, 0.4, 0.7), Vector3(0, 2.07, 0.78), Vector3(0, 0, PI * 0.5))
	# Cargo pallet and the high-gain dish on its mast
	_m(b, _box(1.6, 0.42, 0.9), mat(Color(0.62, 0.64, 0.68), 0.7, 0.2), Vector3(0, 1.1, 1.45))
	_m(b, _cyl(0.035, 0.035, 1.3), mat(STEEL, 0.4, 0.7), Vector3(0.75, 1.75, 1.6))
	_m(b, _cyl(0.55, 0.06, 0.16, 24), hull, Vector3(0.75, 2.45, 1.6), Vector3(-0.5, 0, 0.3))
	_m(b, _sphere(0.05), glow(tint, 3.0), Vector3(0.75, 2.6, 1.55))
	# Lights
	for sx in [-1.0, 1.0]:
		_headlight(out, b, Vector3(sx * 0.62, 0.86, -1.9))
		_taillight(b, Vector3(sx * 0.8, 0.82, 1.86))
	# Six wheels on their own springs
	for z in [-1.32, 0.0, 1.32]:
		for sx in [-1.0, 1.0]:
			_wheel(out, null, Vector3(sx * 1.3, 0.46, z), 0.46, 0.36, tint)
	out["probes"] = [Vector3(-1.3, 0, -1.32), Vector3(1.3, 0, -1.32), Vector3(-1.3, 0, 1.32), Vector3(1.3, 0, 1.32)]


static func _hoverbike(out: Dictionary, tint: Color) -> void:
	var b: Node3D = out["body"]
	var hull := mat(HULL, 0.35, 0.08)
	var trim := mat(TRIM, 0.6, 0.4)
	_m(b, _cap(0.36, 2.5), hull, Vector3(0, 0.62, 0), Vector3(PI * 0.5, 0, 0))
	_m(b, _sphere(0.42), hull, Vector3(0, 0.72, -1.05), Vector3.ZERO, Vector3(0.9, 0.62, 1.4))
	_m(b, _cap(0.2, 1.1), trim, Vector3(0, 0.95, 0.35), Vector3(PI * 0.5, 0, 0))  # saddle
	_m(b, _box(0.05, 0.06, 2.3), glow(tint, 2.0), Vector3(0, 0.98, -0.2))
	# Handlebars and a short screen
	_m(b, _cyl(0.03, 0.03, 0.9), mat(STEEL, 0.3, 0.8), Vector3(0, 1.08, -0.62), Vector3(0, 0, PI * 0.5))
	_m(b, _box(0.55, 0.32, 0.02), glass(), Vector3(0, 1.2, -0.82), Vector3(-0.45, 0, 0))
	# Two hover rings with ice-lit floors
	for z in [-0.95, 0.95]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.34
		ring.outer_radius = 0.5
		ring.rings = 24
		ring.ring_segments = 10
		_m(b, ring, trim, Vector3(0, 0.3, z), Vector3.ZERO, Vector3(1.25, 1.0, 1.0))
		_m(b, _cyl(0.36, 0.36, 0.03, 20), glow(DeepFieldTheme.ICE, 2.6), Vector3(0, 0.24, z), Vector3.ZERO, Vector3(1.25, 1, 1))
	# Tail fins and the exhaust
	for sx in [-1.0, 1.0]:
		_m(b, _box(0.04, 0.4, 0.5), hull, Vector3(sx * 0.2, 0.95, 1.2), Vector3(0, 0, sx * 0.35))
	_m(b, _cyl(0.17, 0.22, 0.3, 14), trim, Vector3(0, 0.62, 1.42), Vector3(PI * 0.5, 0, 0))
	out["flames"].append(_flame(b, Vector3(0, 0.62, 1.55), 1.3, 0.15, Vector3(-PI * 0.5, 0, 0)))
	_headlight(out, b, Vector3(0, 0.78, -1.62), 0.13)
	_taillight(b, Vector3(0, 0.9, 1.3), Vector3(0.18, 0.06, 0.04))
	out["probes"] = [Vector3(-0.5, 0, -0.95), Vector3(0.5, 0, -0.95), Vector3(-0.5, 0, 0.95), Vector3(0.5, 0, 0.95)]


static func _skimmer(out: Dictionary, tint: Color) -> void:
	var b: Node3D = out["body"]
	var hull := mat(HULL, 0.4, 0.08)
	var trim := mat(TRIM, 0.65, 0.35)
	_m(b, _box(1.6, 0.3, 2.6), hull, Vector3(0, 0.42, 0.15))
	var nose := PrismMesh.new()
	nose.size = Vector3(1.6, 0.9, 0.3)
	_m(b, nose, hull, Vector3(0, 0.42, -1.6), Vector3(-PI * 0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		_m(b, _cap(0.22, 3.4), trim, Vector3(sx * 0.95, 0.32, 0.0), Vector3(PI * 0.5, 0, 0))
		_m(b, _box(0.05, 0.05, 3.0), glow(tint, 2.0), Vector3(sx * 0.95, 0.12, 0.0))
		_m(b, _cyl(0.2, 0.24, 0.5, 14), mat(STEEL, 0.35, 0.8), Vector3(sx * 0.55, 0.55, 1.5), Vector3(PI * 0.5, 0, 0))
		out["flames"].append(_flame(b, Vector3(sx * 0.55, 0.55, 1.75), 1.6, 0.16, Vector3(-PI * 0.5, 0, 0)))
		_taillight(b, Vector3(sx * 0.7, 0.62, 1.46), Vector3(0.2, 0.06, 0.04))
		_headlight(out, b, Vector3(sx * 0.45, 0.5, -1.72), 0.08)
	# The under-glow cushion
	_m(b, _box(1.3, 0.03, 2.2), glow(DeepFieldTheme.ICE, 2.2), Vector3(0, 0.25, 0.1))
	# Low cockpit: seat, cowl, screen
	_m(b, _box(0.6, 0.14, 0.7), trim, Vector3(0, 0.62, 0.5))
	_m(b, _box(0.6, 0.45, 0.1), trim, Vector3(0, 0.85, 0.85), Vector3(-0.2, 0, 0))
	_m(b, _box(0.9, 0.22, 0.5), hull, Vector3(0, 0.68, -0.4))
	_m(b, _box(0.85, 0.3, 0.02), glass(), Vector3(0, 0.92, -0.62), Vector3(-0.6, 0, 0))
	_m(b, _box(0.5, 0.03, 0.15), glow(DeepFieldTheme.ICE, 1.2), Vector3(0, 0.8, -0.3))
	out["probes"] = [Vector3(-0.9, 0, -1.2), Vector3(0.9, 0, -1.2), Vector3(-0.9, 0, 1.2), Vector3(0.9, 0, 1.2)]


static func _hopper(out: Dictionary, tint: Color) -> void:
	var b: Node3D = out["body"]
	var hull := mat(HULL, 0.4, 0.08)
	var trim := mat(TRIM, 0.6, 0.4)
	var gold := mat(Color(0.78, 0.6, 0.28), 0.35, 0.85)  # the lander's foil skirt
	_m(b, _cyl(1.05, 0.85, 0.75, 8), gold, Vector3(0, 1.15, 0))
	_m(b, _cyl(1.08, 1.08, 0.12, 8), hull, Vector3(0, 1.56, 0))
	_m(b, _box(0.7, 0.14, 0.7), trim, Vector3(0, 1.66, 0.1))  # seat
	_m(b, _sphere(1.05, true), glass(), Vector3(0, 1.6, 0))
	_m(b, _box(0.9, 0.3, 0.25), trim, Vector3(0, 1.75, -0.65))
	_m(b, _box(0.6, 0.02, 0.18), glow(DeepFieldTheme.ICE, 1.2), Vector3(0, 1.91, -0.62), Vector3(-0.4, 0, 0))
	_m(b, _box(1.4, 0.05, 0.05), glow(tint, 2.0), Vector3(0, 1.5, -1.02))
	# Side tanks and four splayed legs with pads
	for sx in [-1.0, 1.0]:
		_m(b, _sphere(0.38), hull, Vector3(sx * 1.2, 1.2, 0.0))
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var top := dir * 0.8 + Vector3(0, 1.0, 0)
		var foot := dir * 1.55 + Vector3(0, 0.08, 0)
		var mid := (top + foot) * 0.5
		var leg := _m(b, _cyl(0.05, 0.05, top.distance_to(foot), 8), mat(STEEL, 0.4, 0.8), mid)
		leg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
		_m(b, _cyl(0.26, 0.3, 0.08, 12), trim, foot)
		# Thrusters under the skirt, angled out a little
		_m(b, _cyl(0.12, 0.2, 0.32, 12), mat(STEEL, 0.3, 0.85), dir * 0.6 + Vector3(0, 0.68, 0))
		out["flames"].append(_flame(b, dir * 0.6 + Vector3(0, 0.52, 0), 1.8, 0.18))
	_headlight(out, b, Vector3(-0.4, 1.1, -0.98), 0.1)
	_headlight(out, b, Vector3(0.4, 1.1, -0.98), 0.1)
	# A red beacon on a short mast
	var beacon := Node3D.new()
	beacon.position = Vector3(0, 2.75, 0.2)
	b.add_child(beacon)
	_m(b, _cyl(0.03, 0.03, 0.2), mat(STEEL, 0.4, 0.7), Vector3(0, 2.62, 0.2))
	_m(beacon, _sphere(0.08), glow(Color(1.0, 0.25, 0.3), 4.0), Vector3.ZERO)
	out["beacon"] = beacon
	out["probes"] = [Vector3(-1.1, 0, -1.1), Vector3(1.1, 0, -1.1), Vector3(-1.1, 0, 1.1), Vector3(1.1, 0, 1.1)]


static func _crawler(out: Dictionary, tint: Color) -> void:
	var b: Node3D = out["body"]
	var hull := mat(HULL, 0.5, 0.08)
	var trim := mat(TRIM, 0.7, 0.3)
	var steel := mat(STEEL, 0.45, 0.7)
	# Tracks: belts with rounded ends and road wheels showing through
	for sx in [-1.0, 1.0]:
		var tm := track_mat()
		out["tracks"].append(tm)
		_m(b, _box(0.85, 0.16, 4.2), tm, Vector3(sx * 1.35, 1.12, 0))
		_m(b, _box(0.85, 0.16, 4.2), tm, Vector3(sx * 1.35, 0.08, 0))
		for z in [-2.1, 2.1]:
			_m(b, _cyl(0.6, 0.6, 0.85, 16), tm, Vector3(sx * 1.35, 0.6, z), Vector3(0, 0, PI * 0.5))
		_m(b, _box(0.9, 0.9, 4.2), trim, Vector3(sx * 1.35, 0.6, 0))
		for z in [-1.3, -0.45, 0.45, 1.3]:
			_m(b, _cyl(0.36, 0.36, 0.1, 14), steel, Vector3(sx * 1.82, 0.5, z), Vector3(0, 0, PI * 0.5))
		_m(b, _box(0.08, 0.08, 4.6), glow(tint, 2.0), Vector3(sx * 1.82, 1.15, 0))
	# Hull, deck and an open cab with a roll cage
	_m(b, _box(2.0, 1.0, 4.6), hull, Vector3(0, 1.2, 0))
	_m(b, _box(3.6, 0.12, 4.9), hull, Vector3(0, 1.3, 0))
	_m(b, _box(0.8, 0.16, 0.75), trim, Vector3(0, 1.45, -0.3))
	_m(b, _box(0.8, 0.8, 0.12), trim, Vector3(0, 1.85, 0.12))
	_m(b, _box(1.6, 0.5, 0.4), trim, Vector3(0, 1.6, -1.25))
	_m(b, _box(1.0, 0.03, 0.25), glow(DeepFieldTheme.ICE, 1.2), Vector3(0, 1.87, -1.2), Vector3(-0.4, 0, 0))
	for p in [Vector3(-0.9, 0, -1.45), Vector3(0.9, 0, -1.45), Vector3(-0.9, 0, 0.6), Vector3(0.9, 0, 0.6)]:
		_m(b, _cyl(0.06, 0.06, 2.0), steel, Vector3(p.x, 2.35, p.z))
	_m(b, _box(2.0, 0.12, 2.25), hull, Vector3(0, 3.36, -0.42))
	# Light bar on the roof, the amber beacon
	for i in 4:
		var x := -0.75 + i * 0.5
		_m(b, _box(0.34, 0.16, 0.1), glow(Color(1.0, 0.96, 0.86), 3.5), Vector3(x, 3.5, -1.5))
	out["lights"].append(Vector3(-0.5, 3.45, -1.6))
	out["lights"].append(Vector3(0.5, 3.45, -1.6))
	var beacon := Node3D.new()
	beacon.position = Vector3(0.7, 3.6, 0.3)
	b.add_child(beacon)
	_m(beacon, _box(0.12, 0.18, 0.3), glow(Color(1.0, 0.7, 0.2), 4.0), Vector3(0, 0, 0.1))
	_m(b, _cyl(0.14, 0.14, 0.2, 12), glass(), Vector3(0.7, 3.6, 0.3))
	out["beacon"] = beacon
	# Dozer blade on two arms
	_m(b, _box(3.6, 0.9, 0.18), steel, Vector3(0, 0.65, -2.95), Vector3(0.25, 0, 0))
	for sx in [-1.0, 1.0]:
		_m(b, _box(0.14, 0.14, 1.0), trim, Vector3(sx * 0.9, 0.75, -2.45))
	# The Bar Crawler's own bars: three tint-lit tanks on the back deck
	for i in 3:
		_m(b, _cyl(0.22, 0.22, 0.7 + i * 0.35, 12), glow(tint.lerp(Color.WHITE, 0.15 * i), 1.4), Vector3(-0.6 + i * 0.6, 1.36 + (0.7 + i * 0.35) * 0.5, 1.75))
	_taillight(b, Vector3(-1.0, 1.25, 2.32))
	_taillight(b, Vector3(1.0, 1.25, 2.32))
	out["probes"] = [Vector3(-1.35, 0, -2.0), Vector3(1.35, 0, -2.0), Vector3(-1.35, 0, 2.0), Vector3(1.35, 0, 2.0)]
