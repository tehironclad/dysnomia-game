class_name ArcadeFront
extends Node3D
## The arcade's storefront in a territory, across the plaza from the Void
## monolith. Its door leads inside: the mall arcade (cabinets at 1 Ⓐ a play,
## paid to this QING, plus the pool and card tables). In TehSunFlowrScioety
## QING the same door is Sunny's Pub. Which one depends only on the territory.

const SUNFLOWER_QING := "0x2b78b345880807ac9be28c1309ab55d6fa8796de"
const AT := Vector2(26.0, 18.0)  # relative to the Core; mirrors the monolith
const DOOR_REACH := 3.2

var is_pub := false
var door_local := Vector3(0.0, 0.0, 4.2)  # in this node's space, in front of the door
var door: PassDoor  ## sliding doors in the doorway (open as you come near; DoorSequence)


static func pub_for(address: String) -> bool:
	return address.to_lower() == SUNFLOWER_QING


func build(address: String, accent: Color) -> void:
	is_pub = pub_for(address)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.32, 0.2, 0.13) if is_pub else Color(0.13, 0.14, 0.17)
	wall.roughness = 0.85 if is_pub else 0.4
	wall.metallic = 0.0 if is_pub else 0.6
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.18, 0.12, 0.08) if is_pub else Color(0.22, 0.23, 0.27)
	trim.metallic = 0.2 if is_pub else 0.8
	trim.roughness = 0.5
	var sign_col := Color(1.0, 0.78, 0.25) if is_pub else accent.lerp(Color(1.0, 0.3, 0.8), 0.5)
	var glow := _glow(sign_col, 3.0)
	_box(Vector3(11.0, 6.0, 7.0), Vector3(0.0, 3.0, -3.5), wall)  # the block
	_box(Vector3(11.6, 0.4, 7.6), Vector3(0.0, 6.2, -3.5), trim)  # roof lip
	# Shop window either side of the door: glass lit from inside.
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(1.0, 0.75, 0.4, 0.8) if is_pub else Color(0.4, 0.5, 1.0, 0.8)
	window.emission_enabled = true
	window.emission = window.albedo_color
	window.emission_energy_multiplier = 0.9
	for sx in [-1.0, 1.0]:
		_box(Vector3(3.2, 2.4, 0.1), Vector3(sx * 3.4, 2.0, 0.02), window)
		_box(Vector3(3.4, 0.15, 0.25), Vector3(sx * 3.4, 3.3, 0.05), trim)
	# The door: a dark opening with a lit frame.
	_box(Vector3(2.0, 3.0, 0.1), Vector3(0.0, 1.5, 0.03), _flat(Color(0.02, 0.02, 0.03)))
	_box(Vector3(2.3, 0.12, 0.2), Vector3(0.0, 3.06, 0.06), glow)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.12, 3.0, 0.2), Vector3(sx * 1.08, 1.5, 0.06), glow)
	door = PassDoor.make("slide", 2.0, 2.94, sign_col)
	door.position = Vector3(0.0, 0.0, 0.12)
	add_child(door)
	# The sign
	var sign := Label3D.new()
	sign.text = "SUNNY'S PUB" if is_pub else "ARCADE"
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 100
	sign.pixel_size = 0.012
	sign.outline_size = 18
	sign.outline_modulate = Color(0, 0, 0, 0.8)
	sign.modulate = sign_col
	sign.position = Vector3(0.0, 4.6, 0.12)
	add_child(sign)
	var sub := Label3D.new()
	sub.text = "arcade · pool · cards · a drink with Sunny" if is_pub else "%s · paid to this QING · pool & cards in the back" % Prices.menu_line()
	sub.font = DeepFieldTheme.mono_font()
	sub.font_size = 36
	sub.pixel_size = 0.01
	sub.modulate = Color(1, 1, 1, 0.85)
	sub.position = Vector3(0.0, 3.7, 0.12)
	add_child(sub)
	if is_pub:
		_sun_sign(Vector3(-4.75, 4.7, 0.15))
		_sun_sign(Vector3(4.75, 4.7, 0.15))
	var lamp := OmniLight3D.new()
	lamp.light_color = sign_col
	lamp.light_energy = 2.2
	lamp.omni_range = 9.0
	lamp.position = Vector3(0.0, 4.0, 2.0)
	add_child(lamp)
	# Walls you can't walk through.
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(11.0, 6.0, 7.0)
	cs.shape = sh
	cs.position = Vector3(0.0, 3.0, -3.5)
	body.add_child(cs)


## A little neon sun: a disc and its rays.
func _sun_sign(at: Vector3) -> void:
	var gold := _glow(Color(1.0, 0.8, 0.2), 3.0)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.05
	disc.mesh = cm
	disc.material_override = gold
	disc.rotation_degrees.x = 90.0
	disc.position = at
	add_child(disc)
	for i in 12:
		var a := TAU * i / 12.0
		var ray := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.32, 0.04)
		ray.mesh = bm
		ray.material_override = gold
		ray.position = at + Vector3(cos(a) * 0.68, sin(a) * 0.68, 0.0)
		ray.rotation.z = a - PI * 0.5
		add_child(ray)


func near_door(player_global: Vector3) -> bool:
	var d := to_global(door_local)
	return Vector2(player_global.x - d.x, player_global.z - d.z).length() < DOOR_REACH


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	add_child(mi)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m
