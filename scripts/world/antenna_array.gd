extends Node3D
## Communication relay tower — tall lattice mast with rotating satellite dishes.
## Placed at approximately (-50, 0) in the territory.
## Features a blinking red beacon at the apex and angled support struts.
## Dish count and heights vary by territory seed for visual uniqueness.
## All procedural meshes, no external models.

const TOWER_HEIGHT: float = 15.0
const TOWER_RADIUS: float = 0.12
const STRUT_RADIUS: float = 0.04
const STRUT_HEIGHT_RATIO: float = 0.55  # Struts reach 55% of tower height
const BEACON_BLINK_INTERVAL: float = 1.5

var _dish_pivots: Array[Node3D] = []
var _dish_speeds: Array[float] = []
var _beacon_light: OmniLight3D
var _beacon_mesh: MeshInstance3D
var _beacon_timer: float = 0.0
var _beacon_on: bool = true
var _tower_material: StandardMaterial3D
var _strut_material: StandardMaterial3D
var _dish_material: StandardMaterial3D
var _beacon_material: StandardMaterial3D


func initialize(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4400

	_create_materials()
	_build_main_pole()
	_build_support_struts()

	var dish_count: int = rng.randi_range(3, 5)
	_build_dishes(rng, dish_count)
	_build_beacon()
	_build_cross_braces(rng)


func _process(delta: float) -> void:
	# Rotate each dish at its own speed
	for i in range(_dish_pivots.size()):
		if is_instance_valid(_dish_pivots[i]):
			_dish_pivots[i].rotate_y(_dish_speeds[i] * delta)

	# Blink beacon
	_beacon_timer += delta
	if _beacon_timer >= BEACON_BLINK_INTERVAL:
		_beacon_timer -= BEACON_BLINK_INTERVAL
		_beacon_on = not _beacon_on
		if _beacon_light:
			_beacon_light.light_energy = 3.0 if _beacon_on else 0.0
		if _beacon_material:
			_beacon_material.emission_energy_multiplier = 4.0 if _beacon_on else 0.1


func _create_materials() -> void:
	# Main tower pole — industrial grey metal
	_tower_material = StandardMaterial3D.new()
	_tower_material.albedo_color = Color(0.35, 0.34, 0.33)
	_tower_material.roughness = 0.55
	_tower_material.metallic = 0.7
	_tower_material.specular = 0.5

	# Support struts — slightly darker
	_strut_material = StandardMaterial3D.new()
	_strut_material.albedo_color = Color(0.28, 0.27, 0.26)
	_strut_material.roughness = 0.6
	_strut_material.metallic = 0.6
	_strut_material.specular = 0.4

	# Dish surface — lighter metallic
	_dish_material = StandardMaterial3D.new()
	_dish_material.albedo_color = Color(0.55, 0.54, 0.52)
	_dish_material.roughness = 0.25
	_dish_material.metallic = 0.8
	_dish_material.specular = 0.7

	# Beacon — red emissive
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.albedo_color = Color(0.6, 0.05, 0.02)
	_beacon_material.roughness = 0.3
	_beacon_material.metallic = 0.1
	_beacon_material.emission_enabled = true
	_beacon_material.emission = Color(1.0, 0.1, 0.05)
	_beacon_material.emission_energy_multiplier = 4.0


func _build_main_pole() -> void:
	## Central vertical mast — thin tall cylinder.
	var cyl := CylinderMesh.new()
	cyl.top_radius = TOWER_RADIUS * 0.7
	cyl.bottom_radius = TOWER_RADIUS
	cyl.height = TOWER_HEIGHT
	cyl.radial_segments = 8

	var inst := MeshInstance3D.new()
	inst.name = "MainPole"
	inst.mesh = cyl
	inst.material_override = _tower_material
	inst.position = Vector3(0.0, TOWER_HEIGHT * 0.5, 0.0)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)


func _build_support_struts() -> void:
	## 4 angled struts from base corners to mid-height of the main pole.
	## Creates a pyramidal support structure.
	var strut_top_y: float = TOWER_HEIGHT * STRUT_HEIGHT_RATIO
	var base_spread: float = 3.0  # How far from center the strut feet sit
	var strut_top := Vector3(0.0, strut_top_y, 0.0)

	var base_positions: Array[Vector3] = [
		Vector3(-base_spread, 0.0, -base_spread),
		Vector3(base_spread, 0.0, -base_spread),
		Vector3(-base_spread, 0.0, base_spread),
		Vector3(base_spread, 0.0, base_spread),
	]

	for i in range(base_positions.size()):
		var base_pos: Vector3 = base_positions[i]
		var midpoint: Vector3 = (base_pos + strut_top) * 0.5
		var length: float = base_pos.distance_to(strut_top)
		var direction: Vector3 = (strut_top - base_pos).normalized()

		var cyl := CylinderMesh.new()
		cyl.top_radius = STRUT_RADIUS * 0.8
		cyl.bottom_radius = STRUT_RADIUS
		cyl.height = length
		cyl.radial_segments = 6

		var inst := MeshInstance3D.new()
		inst.name = "Strut_%d" % i
		inst.mesh = cyl
		inst.material_override = _strut_material
		inst.position = midpoint
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		# Orient cylinder along the strut direction
		if direction.length() > 0.01:
			inst.look_at(inst.position + direction)
			inst.rotate_object_local(Vector3.RIGHT, PI * 0.5)

		add_child(inst)

		# Small foot pad at base
		var pad := CylinderMesh.new()
		pad.top_radius = 0.2
		pad.bottom_radius = 0.25
		pad.height = 0.08
		pad.radial_segments = 8
		var pad_inst := MeshInstance3D.new()
		pad_inst.mesh = pad
		pad_inst.material_override = _strut_material
		pad_inst.position = base_pos + Vector3(0.0, 0.04, 0.0)
		add_child(pad_inst)


func _build_dishes(rng: RandomNumberGenerator, count: int) -> void:
	## Satellite dishes at varying heights along the mast.
	## Each dish is a torus mounted on a short arm, attached to a pivot node
	## so it can rotate independently.
	var min_height: float = TOWER_HEIGHT * 0.4
	var max_height: float = TOWER_HEIGHT * 0.9
	var height_step: float = (max_height - min_height) / float(maxi(count - 1, 1))

	for i in range(count):
		var dish_y: float = min_height + float(i) * height_step
		dish_y += rng.randf_range(-0.5, 0.5)  # Slight random offset

		var dish_size: float = rng.randf_range(0.8, 1.5)
		var arm_length: float = rng.randf_range(0.6, 1.2)
		var rot_speed: float = rng.randf_range(0.15, 0.6)
		# Alternate rotation direction
		if i % 2 == 1:
			rot_speed = -rot_speed

		# Pivot node at mast center (for rotation)
		var pivot := Node3D.new()
		pivot.name = "DishPivot_%d" % i
		pivot.position = Vector3(0.0, dish_y, 0.0)
		add_child(pivot)
		_dish_pivots.append(pivot)
		_dish_speeds.append(rot_speed)

		# Arm — horizontal cylinder from mast to dish
		var arm := CylinderMesh.new()
		arm.top_radius = 0.03
		arm.bottom_radius = 0.03
		arm.height = arm_length
		arm.radial_segments = 6

		var arm_inst := MeshInstance3D.new()
		arm_inst.name = "DishArm_%d" % i
		arm_inst.mesh = arm
		arm_inst.material_override = _strut_material
		arm_inst.position = Vector3(arm_length * 0.5, 0.0, 0.0)
		arm_inst.rotation_degrees.z = 90.0  # Horizontal
		pivot.add_child(arm_inst)

		# Dish — scaled torus to represent a parabolic dish
		var torus := TorusMesh.new()
		torus.inner_radius = dish_size * 0.5
		torus.outer_radius = dish_size * 0.5 + 0.08
		torus.ring_segments = 16
		torus.rings = 12

		var dish_inst := MeshInstance3D.new()
		dish_inst.name = "Dish_%d" % i
		dish_inst.mesh = torus
		dish_inst.material_override = _dish_material
		dish_inst.position = Vector3(arm_length, 0.0, 0.0)
		# Tilt dish slightly upward (facing sky)
		dish_inst.rotation_degrees.x = rng.randf_range(20.0, 45.0)
		dish_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pivot.add_child(dish_inst)

		# Central feed horn — small cylinder in the dish center
		var horn := CylinderMesh.new()
		horn.top_radius = 0.02
		horn.bottom_radius = 0.04
		horn.height = dish_size * 0.3
		horn.radial_segments = 6
		var horn_inst := MeshInstance3D.new()
		horn_inst.mesh = horn
		horn_inst.material_override = _tower_material
		horn_inst.position = Vector3(0.0, dish_size * 0.15, 0.0)
		dish_inst.add_child(horn_inst)


func _build_beacon() -> void:
	## Red blinking light at the top of the mast.
	var beacon_y: float = TOWER_HEIGHT + 0.15

	# Beacon sphere
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.radial_segments = 8
	sphere.rings = 6

	_beacon_mesh = MeshInstance3D.new()
	_beacon_mesh.name = "Beacon"
	_beacon_mesh.mesh = sphere
	_beacon_mesh.material_override = _beacon_material
	_beacon_mesh.position = Vector3(0.0, beacon_y, 0.0)
	add_child(_beacon_mesh)

	# Beacon light
	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "BeaconLight"
	_beacon_light.light_color = Color(1.0, 0.15, 0.05)
	_beacon_light.light_energy = 3.0
	_beacon_light.omni_range = 30.0
	_beacon_light.omni_attenuation = 1.8
	_beacon_light.shadow_enabled = false
	_beacon_light.position = Vector3(0.0, beacon_y, 0.0)
	add_child(_beacon_light)


func _build_cross_braces(rng: RandomNumberGenerator) -> void:
	## Horizontal cross-braces between strut pairs at mid-height for structural detail.
	var brace_y: float = TOWER_HEIGHT * STRUT_HEIGHT_RATIO * 0.5
	var spread_at_y: float = 3.0 * (1.0 - brace_y / (TOWER_HEIGHT * STRUT_HEIGHT_RATIO)) * 0.5 + 0.5

	# 4 horizontal braces connecting adjacent strut legs
	var brace_pairs: Array = [
		[Vector3(-spread_at_y, brace_y, -spread_at_y), Vector3(spread_at_y, brace_y, -spread_at_y)],
		[Vector3(spread_at_y, brace_y, -spread_at_y), Vector3(spread_at_y, brace_y, spread_at_y)],
		[Vector3(spread_at_y, brace_y, spread_at_y), Vector3(-spread_at_y, brace_y, spread_at_y)],
		[Vector3(-spread_at_y, brace_y, spread_at_y), Vector3(-spread_at_y, brace_y, -spread_at_y)],
	]

	for i in range(brace_pairs.size()):
		var p0: Vector3 = brace_pairs[i][0]
		var p1: Vector3 = brace_pairs[i][1]
		var mid: Vector3 = (p0 + p1) * 0.5
		var length: float = p0.distance_to(p1)
		var direction: Vector3 = (p1 - p0).normalized()

		var cyl := CylinderMesh.new()
		cyl.top_radius = STRUT_RADIUS * 0.6
		cyl.bottom_radius = STRUT_RADIUS * 0.6
		cyl.height = length
		cyl.radial_segments = 4

		var inst := MeshInstance3D.new()
		inst.name = "CrossBrace_%d" % i
		inst.mesh = cyl
		inst.material_override = _strut_material
		inst.position = mid

		if direction.length() > 0.01:
			inst.look_at(inst.position + direction)
			inst.rotate_object_local(Vector3.RIGHT, PI * 0.5)

		add_child(inst)
