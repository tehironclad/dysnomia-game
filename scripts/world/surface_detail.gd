extends Node3D
## Ground surface detail overlays — tire tracks, boot prints, and regolith patches.
## Uses MultiMeshInstance3D for small-scale detail that adds visual texture to the
## lunar surface without significant performance cost.
## Deterministic from territory seed. 30-50 total detail instances.

const MAX_TIRE_MARKS: int = 12
const MAX_BOOT_PRINTS: int = 10
const MAX_REGOLITH_PATCHES: int = 25
const TERRAIN_HALF: float = 200.0
const EXCLUSION_RADIUS: float = 20.0

# Structure positions to avoid
const MONUMENT_POS := Vector2(0.0, -40.0)
const BEAT_STATION_POS := Vector2(0.0, 60.0)
const PUB_POS := Vector2(60.0, 0.0)
const FAIR_POS := Vector2(-100.0, 80.0)  # Affection Fair (flattened 80x80 m)
const FAIR_RADIUS := 55.0

var _tire_multimesh: MultiMeshInstance3D
var _boot_multimesh: MultiMeshInstance3D
var _regolith_multimesh: MultiMeshInstance3D
var _tire_material: StandardMaterial3D
var _boot_material: StandardMaterial3D
var _regolith_material: StandardMaterial3D


func initialize(terrain_gen: Node3D, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3300

	_create_materials()
	_place_tire_tracks(terrain_gen, rng)
	_place_boot_prints(terrain_gen, rng)
	_place_regolith_patches(terrain_gen, rng)


func _is_in_exclusion_zone(x: float, z: float) -> bool:
	if Vector2(x, z).distance_to(MONUMENT_POS) < EXCLUSION_RADIUS:
		return true
	if Vector2(x, z).distance_to(BEAT_STATION_POS) < EXCLUSION_RADIUS:
		return true
	if Vector2(x, z).distance_to(PUB_POS) < EXCLUSION_RADIUS:
		return true
	if Vector2(x, z).distance_to(FAIR_POS) < FAIR_RADIUS:
		return true
	return false


func _create_materials() -> void:
	# Tire tracks — slightly darker than surrounding regolith (compressed dust)
	_tire_material = StandardMaterial3D.new()
	_tire_material.albedo_color = Color(0.16, 0.15, 0.14, 0.7)
	_tire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tire_material.roughness = 0.95
	_tire_material.metallic = 0.0
	_tire_material.specular = 0.05

	# Boot prints — subtle impression marks
	_boot_material = StandardMaterial3D.new()
	_boot_material.albedo_color = Color(0.18, 0.17, 0.15, 0.6)
	_boot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_boot_material.roughness = 0.9
	_boot_material.metallic = 0.0
	_boot_material.specular = 0.05

	# Regolith patches — dusty lighter areas (disturbed soil)
	_regolith_material = StandardMaterial3D.new()
	_regolith_material.albedo_color = Color(0.32, 0.30, 0.27, 0.5)
	_regolith_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_regolith_material.roughness = 0.98
	_regolith_material.metallic = 0.0
	_regolith_material.specular = 0.02


func _place_tire_tracks(terrain_gen: Node3D, rng: RandomNumberGenerator) -> void:
	## Tire tracks near the vehicle spawn area (around x=30-80, z=-20 to 20).
	## Rectangular boxes laid in a line pattern simulating wheel ruts.
	var transforms: Array[Transform3D] = []

	# Starting point for tire track line
	var track_x: float = rng.randf_range(25.0, 40.0)
	var track_z: float = rng.randf_range(-15.0, 5.0)
	var track_angle: float = rng.randf_range(-0.3, 0.3)  # Slight curve

	for i in range(MAX_TIRE_MARKS):
		# Advance along track direction
		var dx: float = cos(track_angle) * float(i) * 2.5
		var dz: float = sin(track_angle) * float(i) * 2.5
		var x: float = track_x + dx
		var z: float = track_z + dz

		if _is_in_exclusion_zone(x, z):
			continue
		if absf(x) > TERRAIN_HALF * 0.85 or absf(z) > TERRAIN_HALF * 0.85:
			continue

		var h: float = 0.0
		if terrain_gen.has_method("get_height_at"):
			h = terrain_gen.get_height_at(x, z)

		# Tire mark: elongated flat rectangle
		var mark_len: float = rng.randf_range(1.5, 2.2)
		var mark_width: float = rng.randf_range(0.25, 0.35)

		var xform := Transform3D()
		xform = xform.scaled(Vector3(mark_width, 0.01, mark_len))
		xform = xform.rotated(Vector3.UP, track_angle + rng.randf_range(-0.05, 0.05))
		xform.origin = Vector3(x, h + 0.005, z)
		transforms.append(xform)

		# Slight angle variation to simulate steering
		track_angle += rng.randf_range(-0.08, 0.08)

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	mm.mesh = mesh

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	_tire_multimesh = MultiMeshInstance3D.new()
	_tire_multimesh.name = "TireTracks"
	_tire_multimesh.multimesh = mm
	_tire_multimesh.material_override = _tire_material
	_tire_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tire_multimesh)


func _place_boot_prints(terrain_gen: Node3D, rng: RandomNumberGenerator) -> void:
	## Boot prints near the player spawn area (around origin, z=-5 to 10).
	## Small rectangles alternating left/right to simulate a walking path.
	var transforms: Array[Transform3D] = []

	var walk_x: float = rng.randf_range(-3.0, 3.0)
	var walk_z: float = rng.randf_range(-5.0, 0.0)
	var walk_angle: float = rng.randf_range(-0.2, 0.2)

	for i in range(MAX_BOOT_PRINTS):
		# Alternate left-right foot placement
		var side: float = -0.15 if i % 2 == 0 else 0.15
		var forward: float = float(i) * 0.7

		var perp_x: float = -sin(walk_angle) * side
		var perp_z: float = cos(walk_angle) * side
		var fwd_x: float = cos(walk_angle) * forward
		var fwd_z: float = sin(walk_angle) * forward

		var x: float = walk_x + fwd_x + perp_x
		var z: float = walk_z + fwd_z + perp_z

		if _is_in_exclusion_zone(x, z):
			continue

		var h: float = 0.0
		if terrain_gen.has_method("get_height_at"):
			h = terrain_gen.get_height_at(x, z)

		# Boot print: small narrow rectangle
		var print_len: float = rng.randf_range(0.28, 0.35)
		var print_width: float = rng.randf_range(0.10, 0.14)

		var xform := Transform3D()
		xform = xform.scaled(Vector3(print_width, 0.005, print_len))
		var foot_angle: float = walk_angle + (0.08 if i % 2 == 0 else -0.08)
		xform = xform.rotated(Vector3.UP, foot_angle)
		xform.origin = Vector3(x, h + 0.003, z)
		transforms.append(xform)

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	mm.mesh = mesh

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	_boot_multimesh = MultiMeshInstance3D.new()
	_boot_multimesh.name = "BootPrints"
	_boot_multimesh.multimesh = mm
	_boot_multimesh.material_override = _boot_material
	_boot_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_boot_multimesh)


func _place_regolith_patches(terrain_gen: Node3D, rng: RandomNumberGenerator) -> void:
	## Larger flat boxes scattered across the terrain representing disturbed
	## regolith — lighter dusty patches that add visual variety to the ground.
	var transforms: Array[Transform3D] = []

	for _i in range(MAX_REGOLITH_PATCHES * 2):  # Over-sample
		if transforms.size() >= MAX_REGOLITH_PATCHES:
			break

		var x: float = rng.randf_range(-TERRAIN_HALF * 0.8, TERRAIN_HALF * 0.8)
		var z: float = rng.randf_range(-TERRAIN_HALF * 0.8, TERRAIN_HALF * 0.8)

		if _is_in_exclusion_zone(x, z):
			continue

		var h: float = 0.0
		if terrain_gen.has_method("get_height_at"):
			h = terrain_gen.get_height_at(x, z)

		# Patch size: 1-4m diameter, very thin
		var patch_size: float = rng.randf_range(1.0, 4.0)
		var sx: float = patch_size * rng.randf_range(0.7, 1.3)
		var sz: float = patch_size * rng.randf_range(0.7, 1.3)

		var xform := Transform3D()
		xform = xform.scaled(Vector3(sx, 0.008, sz))
		xform = xform.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		xform.origin = Vector3(x, h + 0.004, z)
		transforms.append(xform)

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	mm.mesh = mesh

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	_regolith_multimesh = MultiMeshInstance3D.new()
	_regolith_multimesh.name = "RegolithPatches"
	_regolith_multimesh.multimesh = mm
	_regolith_multimesh.material_override = _regolith_material
	_regolith_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_regolith_multimesh)
