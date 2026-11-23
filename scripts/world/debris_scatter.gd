extends Node3D
## Crater debris scatter — rock fragments and metallic shards in low-lying areas.
## Uses two MultiMeshInstance3D batches for efficient rendering: rocks + metal shards.
## Only places debris in terrain depressions (below average height) to simulate
## impact ejecta and broken regolith settled in crater bowls.
## Deterministic from territory seed. Avoids monument/beat station/pub zones.

const MAX_ROCKS: int = 150
const MAX_SHARDS: int = 80
const TERRAIN_HALF: float = 200.0
const EXCLUSION_RADIUS: float = 25.0

# Exclusion zone centers (XZ)
const MONUMENT_POS := Vector2(0.0, -40.0)
const BEAT_STATION_POS := Vector2(0.0, 60.0)
const PUB_POS := Vector2(60.0, 0.0)
const FAIR_POS := Vector2(-100.0, 80.0)  # Affection Fair (flattened 80x80 m)
const FAIR_RADIUS := 55.0

var _rock_multimesh: MultiMeshInstance3D
var _shard_multimesh: MultiMeshInstance3D
var _rock_material: StandardMaterial3D
var _shard_material: StandardMaterial3D


func initialize(terrain_gen: Node3D, seed_value: int) -> void:
	_create_materials()

	var avg_height: float = _sample_average_height(terrain_gen, seed_value)

	_place_rocks(terrain_gen, seed_value, avg_height)
	_place_shards(terrain_gen, seed_value, avg_height)


func _sample_average_height(terrain_gen: Node3D, seed_value: int) -> float:
	## Sample terrain at a grid of points to find average height.
	## Debris only spawns below this threshold (in crater bowls).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9001
	var total: float = 0.0
	var count: int = 0
	var step: float = 40.0  # Sample every 40m across terrain

	var x: float = -TERRAIN_HALF * 0.85
	while x <= TERRAIN_HALF * 0.85:
		var z: float = -TERRAIN_HALF * 0.85
		while z <= TERRAIN_HALF * 0.85:
			if terrain_gen.has_method("get_height_at"):
				total += terrain_gen.get_height_at(x, z)
				count += 1
			z += step
		x += step

	if count == 0:
		return 0.0
	return total / float(count)


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


func _place_rocks(terrain_gen: Node3D, seed_value: int, avg_height: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5501

	var transforms: Array[Transform3D] = []

	for _i in range(MAX_ROCKS * 3):  # Over-sample then filter
		if transforms.size() >= MAX_ROCKS:
			break

		var x: float = rng.randf_range(-TERRAIN_HALF * 0.88, TERRAIN_HALF * 0.88)
		var z: float = rng.randf_range(-TERRAIN_HALF * 0.88, TERRAIN_HALF * 0.88)

		if _is_in_exclusion_zone(x, z):
			continue

		if not terrain_gen.has_method("get_height_at"):
			continue
		var h: float = terrain_gen.get_height_at(x, z)

		# Only place in low areas (crater bowls)
		if h > avg_height - 1.0:
			continue

		# Rock fragment size: 0.1 to 0.4m
		var base_size: float = rng.randf_range(0.1, 0.4)
		var sx: float = base_size * rng.randf_range(0.6, 1.5)
		var sy: float = base_size * rng.randf_range(0.3, 0.9)
		var sz: float = base_size * rng.randf_range(0.6, 1.5)

		# Random rotation for natural look
		var rot_y: float = rng.randf_range(0.0, TAU)
		var rot_x: float = rng.randf_range(-0.5, 0.5)
		var rot_z: float = rng.randf_range(-0.5, 0.5)

		# Embed slightly into terrain
		var embed: float = sy * 0.25

		var xform := Transform3D()
		xform = xform.scaled(Vector3(sx, sy, sz))
		xform = xform.rotated(Vector3.UP, rot_y)
		xform = xform.rotated(Vector3.RIGHT, rot_x)
		xform = xform.rotated(Vector3.FORWARD, rot_z)
		xform.origin = Vector3(x, h - embed, z)
		transforms.append(xform)

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()

	# Faceted box shape for angular rock fragments
	var rock_mesh := BoxMesh.new()
	rock_mesh.size = Vector3(1.0, 1.0, 1.0)
	mm.mesh = rock_mesh

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	_rock_multimesh = MultiMeshInstance3D.new()
	_rock_multimesh.name = "DebrisRocks"
	_rock_multimesh.multimesh = mm
	_rock_multimesh.material_override = _rock_material
	_rock_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rock_multimesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(_rock_multimesh)


func _place_shards(terrain_gen: Node3D, seed_value: int, avg_height: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7703

	var transforms: Array[Transform3D] = []

	for _i in range(MAX_SHARDS * 3):
		if transforms.size() >= MAX_SHARDS:
			break

		var x: float = rng.randf_range(-TERRAIN_HALF * 0.85, TERRAIN_HALF * 0.85)
		var z: float = rng.randf_range(-TERRAIN_HALF * 0.85, TERRAIN_HALF * 0.85)

		if _is_in_exclusion_zone(x, z):
			continue

		if not terrain_gen.has_method("get_height_at"):
			continue
		var h: float = terrain_gen.get_height_at(x, z)

		# Shards also only in low areas, slightly more permissive
		if h > avg_height + 0.5:
			continue

		# Thin metallic shard: narrow, flat, elongated
		var length: float = rng.randf_range(0.05, 0.2)
		var width: float = length * rng.randf_range(0.15, 0.4)
		var height: float = length * rng.randf_range(0.02, 0.15)

		var rot_y: float = rng.randf_range(0.0, TAU)
		# Shards can be tilted at steep angles (sticking out of ground)
		var rot_x: float = rng.randf_range(-0.8, 0.8)
		var rot_z: float = rng.randf_range(-0.4, 0.4)

		var embed: float = height * 0.3

		var xform := Transform3D()
		xform = xform.scaled(Vector3(width, height, length))
		xform = xform.rotated(Vector3.UP, rot_y)
		xform = xform.rotated(Vector3.RIGHT, rot_x)
		xform = xform.rotated(Vector3.FORWARD, rot_z)
		xform.origin = Vector3(x, h - embed, z)
		transforms.append(xform)

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()

	# Thin box for metallic shard appearance
	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(1.0, 1.0, 1.0)
	mm.mesh = shard_mesh

	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	_shard_multimesh = MultiMeshInstance3D.new()
	_shard_multimesh.name = "DebrisShards"
	_shard_multimesh.multimesh = mm
	_shard_multimesh.material_override = _shard_material
	_shard_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shard_multimesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(_shard_multimesh)


func _create_materials() -> void:
	# Dark grey rock fragments — rough matte regolith
	_rock_material = StandardMaterial3D.new()
	_rock_material.albedo_color = Color(0.22, 0.20, 0.19)
	_rock_material.roughness = 0.92
	_rock_material.metallic = 0.0
	_rock_material.specular = 0.2

	# Metallic shards — slightly reflective silver debris
	_shard_material = StandardMaterial3D.new()
	_shard_material.albedo_color = Color(0.45, 0.44, 0.42)
	_shard_material.roughness = 0.35
	_shard_material.metallic = 0.65
	_shard_material.specular = 0.6
