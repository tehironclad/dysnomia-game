class_name DevelopmentSite
extends Node3D
## What a territory has built, by tier (Development, from its Hypobar total;
## the same for every viewer). Structures are added tier by tier and never
## removed in a visit, as bars never shrink:
##   Outpost     a light beacon on the Room's roof
##   Settlement  two landing pads with lights and supplies (kit pieces)
##   Town        (city lights along the Julia coast: the terrain shader)
##   City        (an aurora: the sky shader)
##   Capital     a light spire from the Heart into the sky, with an orbiting ring

var tier := -1
var _beacon: MeshInstance3D
var _beacon_mat: StandardMaterial3D
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
		_build_spire()
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


func _build_beacon() -> void:
	_beacon = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.15
	c.bottom_radius = 0.45
	c.height = 1.0
	_beacon.mesh = c
	_beacon_mat = _glow(_tint, 2.0, 0.35)
	_beacon.material_override = _beacon_mat
	add_child(_beacon)
	var h := 14.0 + 10.0 * tier
	_beacon.scale = Vector3(1.0, h, 1.0)
	_beacon.position = Vector3(0.0, 5.0 + h * 0.5, 0.0)


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
		var barrel := PlaceBase.load_piece("Prop_Barrel_Large")
		barrel.position = at + Vector3(side * 3.6, 0, 1.0)
		add_child(barrel)
		var ap := PlaceBase.load_piece("Prop_AccessPoint")
		ap.position = at + Vector3(side * -3.0, 0, -2.6)
		add_child(ap)
		var light := OmniLight3D.new()
		light.position = at + Vector3(0, 3.0, 0)
		light.light_color = _tint
		light.light_energy = 1.2
		light.omni_range = 9.0
		add_child(light)


func _build_spire() -> void:
	var spire := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.2
	c.bottom_radius = 1.2
	c.height = 300.0
	spire.mesh = c
	spire.material_override = _glow(_tint.lerp(Color.WHITE, 0.4), 3.0, 0.5)
	spire.position = Vector3(0, 12.0 + 150.0, 0)
	add_child(spire)
	_spire_ring = Node3D.new()
	_spire_ring.position = Vector3(0, 40.0, 0)
	add_child(_spire_ring)
	var t := TorusMesh.new()
	t.inner_radius = 18.0
	t.outer_radius = 18.6
	t.rings = 96
	var ring := MeshInstance3D.new()
	ring.mesh = t
	ring.material_override = _glow(Color("#ffd27a"), 2.2)
	_spire_ring.add_child(ring)
	var lamp := OmniLight3D.new()
	lamp.light_color = _tint
	lamp.light_energy = 3.0
	lamp.omni_range = 60.0
	lamp.position = Vector3(0, 30.0, 0)
	add_child(lamp)


func _set_energy(e: float) -> void:
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 1.2 + 2.5 * e


func _process(delta: float) -> void:
	_t += delta
	if _spire_ring:
		_spire_ring.rotation = Vector3(0.25 * sin(_t * 0.1), _t * 0.15, 0.2)
	if _beacon:
		_beacon_mat.albedo_color.a = 0.28 + 0.08 * sin(_t * 1.7)
