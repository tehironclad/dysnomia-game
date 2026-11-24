class_name DevelopmentSite
extends Node3D
## What a territory has built, by tier (Development, from its Hypobar total;
## the same for every viewer). Structures are added tier by tier and never
## removed in a visit, as bars never shrink:
##   Outpost     a soft shaft of light rising from the Heart (taller each tier)
##   Settlement  two landing pads with lights and supplies (kit pieces)
##   Town        (city lights along the Julia coast: the terrain shader)
##   City        (an aurora: the sky shader)
##   Capital     the shaft reaches the sky, and a halo of lights orbits above it
## (Redesigned 2026-11-24: an additive light-shaft shader that fades with height
## and at its edges, not a solid beam; the Heart itself is HeartOrrery.)

var tier := -1
const SHAFT_SHADER := preload("res://assets/shaders/light_shaft.gdshader")
const SHAFT_FROM := 12.6  # just above the Heart (core-local)

var _beacon: MeshInstance3D
var _beacon_mat: ShaderMaterial
var _spire_ring: Node3D
var _tint := Color("#7fd3ff")
var _t := 0.0


func setup(tint: Color) -> void:
	_tint = tint


func set_tier(t: int, energy: float) -> void:
	if t == tier:
		_set_energy(energy)
		return
	tier = t
	for c in get_children():
		c.queue_free()
	_beacon = null
	_spire_ring = null
	if t >= 1:
		_build_beacon()
	if t >= 2:
		_build_pads()
	if t >= 5:
		_build_halo()
	_set_energy(energy)


func _glow(c: Color, e: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


## Shaft height by tier: Outpost 24 m … City 54 m; a Capital's reaches the sky.
static func shaft_height(t: int) -> float:
	return 280.0 if t >= 5 else 14.0 + 10.0 * t


func _build_beacon() -> void:
	var h := shaft_height(tier)
	_beacon = MeshInstance3D.new()
	_beacon.name = "Shaft"
	var c := CylinderMesh.new()
	c.top_radius = 1.2 + h * 0.004
	c.bottom_radius = 0.55
	c.height = h
	c.radial_segments = 24
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	_beacon.mesh = c
	_beacon_mat = ShaderMaterial.new()
	_beacon_mat.shader = SHAFT_SHADER
	var col := _tint.lerp(Color.WHITE, 0.3)
	_beacon_mat.set_shader_parameter("color", Vector3(col.r, col.g, col.b))
	_beacon_mat.set_shader_parameter("height", h)
	_beacon_mat.set_shader_parameter("fade_power", 1.2 if tier >= 5 else 1.8)
	_beacon.material_override = _beacon_mat
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.position = Vector3(0.0, SHAFT_FROM + h * 0.5, 0.0)
	add_child(_beacon)


func _build_pads() -> void:
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 15.5, 0.0, 9.0)
		var pad := PlaceBase.load_piece("Platform_Round1")
		pad.position = at
		add_child(pad)
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 1.6
		t.outer_radius = 1.75
		t.rings = 48
		ring.mesh = t
		ring.material_override = _glow(_tint, 1.6)
		ring.position = at + Vector3(0, 0.06, 0)
		add_child(ring)
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			var lamp := PlaceBase.load_piece("Prop_Light_Floor")
			lamp.position = at + Vector3(cos(a) * 2.3, 0, sin(a) * 2.3)
			add_child(lamp)
		var crate := PlaceBase.load_piece("Prop_Crate3")
		crate.position = at + Vector3(side * 3.4, 0, -1.2)
		add_child(crate)
		Solid.wrap(crate)
		var barrel := PlaceBase.load_piece("Prop_Barrel_Large")
		barrel.position = at + Vector3(side * 3.6, 0, 1.0)
		add_child(barrel)
		Solid.wrap(barrel)
		var ap := PlaceBase.load_piece("Prop_AccessPoint")
		ap.position = at + Vector3(side * -3.0, 0, -2.6)
		add_child(ap)
		Solid.wrap(ap)
		var light := OmniLight3D.new()
		light.position = at + Vector3(0, 3.0, 0)
		light.light_color = _tint
		light.light_energy = 1.2
		light.omni_range = 9.0
		add_child(light)


## Capital: a halo of 48 small lights on a tilted orbit high above the Heart
## (one MultiMesh, one draw call), turning slowly.
func _build_halo() -> void:
	_spire_ring = Node3D.new()
	_spire_ring.name = "Halo"
	_spire_ring.position = Vector3(0, 46.0, 0)
	add_child(_spire_ring)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.32
	dot.height = 0.64
	dot.radial_segments = 8
	dot.rings = 4
	mm.mesh = dot
	var n := 48
	mm.instance_count = n
	for i in n:
		var a := TAU * i / n
		var s := 1.0 if i % 4 == 0 else 0.55
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(cos(a) * 16.0, 0.0, sin(a) * 16.0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _glow(_tint.lerp(Color.WHITE, 0.55), 2.6)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spire_ring.add_child(mi)
	var lamp := OmniLight3D.new()
	lamp.light_color = _tint
	lamp.light_energy = 2.0
	lamp.omni_range = 50.0
	lamp.position = Vector3(0, 26.0, 0)
	add_child(lamp)


func _set_energy(e: float) -> void:
	if _beacon_mat:
		_beacon_mat.set_shader_parameter("intensity", 0.28 + 0.5 * e)
		_beacon_mat.set_shader_parameter("band_rate", 0.15 + 0.6 * e)


func _process(delta: float) -> void:
	_t += delta
	if _spire_ring:
		_spire_ring.rotation = Vector3(0.22, _t * 0.06, 0.12 * sin(_t * 0.05))
