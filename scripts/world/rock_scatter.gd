extends Node3D
## Procedural boulder scatter on steep terrain slopes.
## Uses MultiMeshInstance3D for efficient rendering of 200-500 rocks.
## Placement is deterministic from territory seed.

const MAX_ROCKS: int = 400
const MIN_SLOPE: float = 0.3  # Minimum slope steepness to place rocks (0=vertical, 1=flat)
const MAX_SLOPE: float = 0.75 # Maximum slope (don't place on flat ground)
const MIN_SIZE: float = 0.4
const MAX_SIZE: float = 3.5
const TERRAIN_HALF: float = 200.0
const EXCLUSION_RADIUS: float = 35.0  # Don't place near monument/beat station

var _multi_mesh_instance: MultiMeshInstance3D
var _rock_material: StandardMaterial3D


func initialize(seed_value: int, terrain_gen: Node3D, biome: Dictionary) -> void:
	_create_material(biome)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 777  # Separate seed space from other systems

	# Generate candidate positions and filter by slope
	var transforms: Array[Transform3D] = []

	for _i in range(MAX_ROCKS * 3):  # Over-sample then filter
		if transforms.size() >= MAX_ROCKS:
			break

		var x: float = rng.randf_range(-TERRAIN_HALF * 0.9, TERRAIN_HALF * 0.9)
		var z: float = rng.randf_range(-TERRAIN_HALF * 0.9, TERRAIN_HALF * 0.9)

		# Exclude areas near monument, beat station, pub, antenna, landing pad
		if Vector2(x, z - (-40.0)).length() < EXCLUSION_RADIUS:
			continue
		if Vector2(x, z - 60.0).length() < EXCLUSION_RADIUS:
			continue
		if Vector2(x - 60.0, z).length() < EXCLUSION_RADIUS:
			continue
		if Vector2(x - (-50.0), z).length() < 20.0:
			continue
		if Vector2(x, z - 100.0).length() < 22.0:
			continue

		# Sample height and slope from terrain
		var h: float = terrain_gen.get_height_at(x, z)

		# Estimate slope from neighboring heights
		var h_dx: float = terrain_gen.get_height_at(x + 1.0, z)
		var h_dz: float = terrain_gen.get_height_at(x, z + 1.0)
		var slope_vec := Vector3(1.0, h_dx - h, 0.0).cross(Vector3(0.0, h_dz - h, 1.0)).normalized()
		var slope_dot: float = slope_vec.y  # 1.0 = flat, 0.0 = vertical

		# Only place on slopes between MIN_SLOPE and MAX_SLOPE
		if slope_dot < MIN_SLOPE or slope_dot > MAX_SLOPE:
			continue

		# Rock size: larger rocks on steeper slopes
		var steepness: float = 1.0 - slope_dot
		var size_base: float = rng.randf_range(MIN_SIZE, MAX_SIZE)
		var size: float = size_base * (0.5 + steepness)

		# Deformed scale for non-uniform boulders (not perfect spheres)
		var sx: float = size * rng.randf_range(0.6, 1.4)
		var sy: float = size * rng.randf_range(0.4, 1.0)  # Flatter vertically
		var sz: float = size * rng.randf_range(0.6, 1.4)

		# Random rotation
		var rot_y: float = rng.randf_range(0.0, TAU)
		var rot_x: float = rng.randf_range(-0.3, 0.3)
		var rot_z: float = rng.randf_range(-0.3, 0.3)

		# Partially embed in terrain
		var embed: float = sy * 0.3

		var xform := Transform3D()
		xform = xform.scaled(Vector3(sx, sy, sz))
		xform = xform.rotated(Vector3.UP, rot_y)
		xform = xform.rotated(Vector3.RIGHT, rot_x)
		xform = xform.rotated(Vector3.FORWARD, rot_z)
		xform.origin = Vector3(x, h - embed, z)

		transforms.append(xform)

	if transforms.is_empty():
		return

	# Create MultiMesh
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.instance_count = transforms.size()

	# Rock mesh: icosphere-like shape (use SphereMesh with low detail for faceted look)
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 8   # Low poly for faceted rock look
	rock_mesh.rings = 5
	multi_mesh.mesh = rock_mesh

	# Set transforms
	for i in range(transforms.size()):
		multi_mesh.set_instance_transform(i, transforms[i])

	# Create instance
	_multi_mesh_instance = MultiMeshInstance3D.new()
	_multi_mesh_instance.multimesh = multi_mesh
	_multi_mesh_instance.material_override = _rock_material
	_multi_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_multi_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(_multi_mesh_instance)


func _create_material(biome: Dictionary) -> void:
	_rock_material = StandardMaterial3D.new()
	# Rock color derived from biome's rock colors
	var rock_base: Color = biome.get("rock_color", Color(0.30, 0.28, 0.26))
	var rock_var: Color = biome.get("rock_color_2", Color(0.34, 0.32, 0.30))
	_rock_material.albedo_color = rock_base.lerp(rock_var, 0.5)
	_rock_material.roughness = 0.88
	_rock_material.metallic = 0.0
	_rock_material.specular = 0.3
	# Slight normal detail via detail layer
	_rock_material.detail_enabled = false  # Keep simple for MultiMesh perf
