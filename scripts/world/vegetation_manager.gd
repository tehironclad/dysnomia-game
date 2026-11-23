extends Node3D
## Alien vegetation that emerges as territory gets terraformed.
## Density driven by territory_activity; colors from BiomeSystem.
## Adapted from OWDB's GrassManager — chunked MultiMesh with distance fade.
## Only spawns vegetation in the center territory (400m x 400m).

# Chunk parameters
const CHUNK_SIZE: float = 10.0           # Meters per side
const VIEW_DISTANCE: float = 80.0        # Max render distance from camera
const MAX_CHUNKS_PER_FRAME: int = 2      # Budget: 2 chunks per frame
const BLADES_PER_CHUNK: int = 150        # Max blades per chunk at full activity
const MIN_ACTIVITY: float = 0.05         # No vegetation below this threshold
const TERRITORY_HALF: float = 200.0      # Half of TERRAIN_SIZE (400m)
const UPDATE_INTERVAL: float = 1.0       # Seconds between full chunk updates

# Exclusion zones — flattened for buildings, no vegetation
const EXCLUSION_ZONES: Array[Dictionary] = [
	{"x": 0.0, "z": -40.0, "radius": 30.0},   # Monument
	{"x": 0.0, "z": 60.0, "radius": 18.0},     # Beat station
	{"x": 60.0, "z": 0.0, "radius": 22.0},     # Pub
	{"x": -50.0, "z": 0.0, "radius": 15.0},    # Antenna array
	{"x": 0.0, "z": 100.0, "radius": 18.0},    # Landing pad
	{"x": -100.0, "z": 80.0, "radius": 52.0},  # Affection Fair
]

var _camera: Camera3D
var _terrain_generator: Node3D  # Has get_height_at(x, z)
var _biome: Dictionary
var _territory_activity: float = 0.0
var _territory_power: float = 0.0
var _last_activity: float = -1.0  # Track for rebuild threshold

var _active_chunks: Dictionary = {}      # chunk_key -> {multimesh, coord}
var _chunk_queue: Array = []             # [{coord, world_pos, distance}]
var _grass_mesh_cache: ArrayMesh
var _frond_mesh_cache: ArrayMesh
var _mushroom_mesh_cache: ArrayMesh
var _shader_material: ShaderMaterial
var _last_camera_pos: Vector3 = Vector3.ZERO
var _update_timer: float = 0.0


func initialize(terrain_gen: Node3D, camera: Camera3D, biome: Dictionary) -> void:
	_terrain_generator = terrain_gen
	_camera = camera
	_biome = biome

	# Build shared vegetation meshes (3 variants)
	_grass_mesh_cache = _create_blade_mesh()
	_frond_mesh_cache = _create_frond_mesh()
	_mushroom_mesh_cache = _create_mushroom_mesh()

	# Build shader material with biome colors
	_shader_material = _create_vegetation_material(biome)

	if _camera:
		_last_camera_pos = _camera.global_position
		call_deferred("_update_chunks_around_camera")


func get_shader_material() -> ShaderMaterial:
	return _shader_material


func set_territory_state(activity: float, power: float) -> void:
	_territory_power = power

	# Update shader uniform
	if _shader_material:
		_shader_material.set_shader_parameter("territory_activity", activity)
		_shader_material.set_shader_parameter("territory_power", power)

	# Check if activity changed enough to rebuild vegetation
	var old_activity := _territory_activity
	_territory_activity = activity

	if activity < MIN_ACTIVITY:
		if old_activity >= MIN_ACTIVITY:
			clear_all_vegetation()
		return

	# Rebuild if activity changed significantly (blade count depends on it)
	if absf(activity - _last_activity) > 0.05:
		_last_activity = activity
		_rebuild_all_chunks()


func _process(delta: float) -> void:
	if not _camera or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if not _camera:
			return

	if _territory_activity < MIN_ACTIVITY:
		return

	_update_timer += delta

	var camera_pos := _camera.global_position
	var camera_moved := _last_camera_pos.distance_squared_to(camera_pos) > CHUNK_SIZE * CHUNK_SIZE * 0.0625

	if camera_moved or _update_timer >= UPDATE_INTERVAL:
		_update_chunks_around_camera()
		_last_camera_pos = camera_pos
		_update_timer = 0.0

	_process_chunk_queue()


func _update_chunks_around_camera() -> void:
	if not _camera:
		return

	var camera_pos := _camera.global_position
	var chunks_to_keep: Dictionary = {}

	# Get all valid chunks in range
	var chunk_range := int(ceil(VIEW_DISTANCE / CHUNK_SIZE))
	var center_chunk := _world_to_chunk(camera_pos)

	for cx in range(-chunk_range, chunk_range + 1):
		for cz in range(-chunk_range, chunk_range + 1):
			var chunk_coord := Vector2i(center_chunk.x + cx, center_chunk.y + cz)
			var chunk_world := _chunk_to_world(chunk_coord)

			# Skip chunks outside center territory
			if absf(chunk_world.x) > TERRITORY_HALF or absf(chunk_world.z) > TERRITORY_HALF:
				continue

			# Skip chunks in exclusion zones (monument, beat station)
			if _is_in_exclusion_zone(chunk_world.x, chunk_world.z):
				continue

			# Distance check (circular, not square)
			var dist := camera_pos.distance_to(Vector3(chunk_world.x, camera_pos.y, chunk_world.z))
			if dist > VIEW_DISTANCE:
				continue

			var chunk_key := _chunk_key(chunk_coord)
			chunks_to_keep[chunk_key] = true

			# Queue creation if not active
			if not _active_chunks.has(chunk_key):
				var already_queued := false
				for queued in _chunk_queue:
					if queued.coord == chunk_coord:
						already_queued = true
						break
				if not already_queued:
					_chunk_queue.append({
						"coord": chunk_coord,
						"world_pos": chunk_world,
						"distance": dist
					})

	# Remove out-of-range chunks
	var to_remove: Array[String] = []
	for chunk_key in _active_chunks:
		if not chunks_to_keep.has(chunk_key):
			to_remove.append(chunk_key)
	for chunk_key in to_remove:
		_remove_chunk(chunk_key)


func _process_chunk_queue() -> void:
	# Sort by distance (nearest first)
	_chunk_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)

	var generated := 0
	while _chunk_queue.size() > 0 and generated < MAX_CHUNKS_PER_FRAME:
		var chunk_data: Dictionary = _chunk_queue.pop_front()
		_create_vegetation_chunk(chunk_data.coord, chunk_data.world_pos)
		generated += 1


func _create_vegetation_chunk(chunk_coord: Vector2i, world_pos: Vector3) -> void:
	var chunk_key := _chunk_key(chunk_coord)

	# Generate blade positions
	var positions := _generate_blade_positions(chunk_coord, world_pos)
	if positions.is_empty():
		return

	# Pick mesh variant based on chunk position hash (deterministic)
	var chunk_hash := hash(chunk_key) & 0x7FFFFFFF
	var mesh_selection: ArrayMesh
	var variant := chunk_hash % 10
	if variant < 6:
		mesh_selection = _grass_mesh_cache  # 60% grass blades
	elif variant < 9:
		mesh_selection = _frond_mesh_cache  # 30% tall fronds
	else:
		mesh_selection = _mushroom_mesh_cache  # 10% mushroom clusters

	# MultiMeshInstance3D
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "VegChunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	add_child(mmi)

	# MultiMesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = positions.size()
	mm.mesh = mesh_selection

	# Deterministic RNG for this chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_key)

	for i in range(positions.size()):
		var pos: Vector3 = positions[i]
		var xform := Transform3D()

		# Random Y rotation
		var rot_y := rng.randf() * TAU
		xform = xform.rotated(Vector3.UP, rot_y)

		# Random tilt (70% chance, up to 12 degrees — alien tendrils lean)
		if rng.randf() < 0.7:
			var tilt_dir := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var tilt_angle := rng.randf_range(0.0, deg_to_rad(12.0))
			xform = xform.rotated(Vector3.RIGHT, tilt_dir.y * tilt_angle)
			xform = xform.rotated(Vector3.FORWARD, tilt_dir.x * tilt_angle)

		# Scale variation
		var scale_xz := rng.randf_range(0.7, 1.3)
		var scale_y := rng.randf_range(0.6, 1.4)
		xform = xform.scaled(Vector3(scale_xz, scale_y, scale_xz))

		xform.origin = pos
		mm.set_instance_transform(i, xform)

	mmi.multimesh = mm
	mmi.material_override = _shader_material

	_active_chunks[chunk_key] = {
		"multimesh": mmi,
		"coord": chunk_coord,
	}


func _generate_blade_positions(chunk_coord: Vector2i, chunk_world_pos: Vector3) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var half := CHUNK_SIZE * 0.5

	# Blade count scales with territory activity
	var count := int(BLADES_PER_CHUNK * clampf(_territory_activity, 0.0, 1.0))
	if count < 3:
		return positions

	# Deterministic seeding from chunk position
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(chunk_coord))

	for i in range(count):
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)
		var world_x := chunk_world_pos.x + local_x
		var world_z := chunk_world_pos.z + local_z

		# Clamp to territory bounds
		if absf(world_x) > TERRITORY_HALF or absf(world_z) > TERRITORY_HALF:
			continue

		# Skip exclusion zones (already checked at chunk level, but fine-grained check here)
		if _is_in_exclusion_zone(world_x, world_z):
			continue

		# Sample terrain height
		var terrain_y := 0.0
		if _terrain_generator and _terrain_generator.has_method("get_height_at"):
			terrain_y = _terrain_generator.get_height_at(world_x, world_z)

		# Skip underwater areas or above snow line
		if _biome.has("water_level"):
			var water_y: float = _biome.water_level
			# water_level is a normalized parameter, terrain heights are absolute
			# Skip low-lying areas (crater bottoms)
			if terrain_y < -5.0:
				continue

		positions.append(Vector3(world_x, terrain_y, world_z))

	return positions


func _remove_chunk(chunk_key: String) -> void:
	if _active_chunks.has(chunk_key):
		var data: Dictionary = _active_chunks[chunk_key]
		if data.multimesh and is_instance_valid(data.multimesh):
			data.multimesh.queue_free()
		_active_chunks.erase(chunk_key)


func _rebuild_all_chunks() -> void:
	## Rebuild all active chunks (e.g., when activity changes significantly).
	var coords_to_rebuild: Array = []
	for chunk_key in _active_chunks:
		var data: Dictionary = _active_chunks[chunk_key]
		coords_to_rebuild.append(data.coord)

	# Clear and re-queue
	clear_all_vegetation()
	for coord in coords_to_rebuild:
		var world_pos := _chunk_to_world(coord)
		_chunk_queue.append({
			"coord": coord,
			"world_pos": world_pos,
			"distance": 0.0
		})


func clear_all_vegetation() -> void:
	for chunk_key in _active_chunks.keys():
		_remove_chunk(chunk_key)
	_chunk_queue.clear()


# ── Blade Mesh ───────────────────────────────────────────────────────────

func _create_blade_mesh() -> ArrayMesh:
	## 5-segment tapered alien tendril with front + back faces.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var width: float = 0.04  # 4cm base width
	var height: float = 1.0  # Normalized, scaled by shader
	var hw := width * 0.5

	# 6 vertices: base pair, 3 mid pairs, tip point
	# UV.y = height fraction for shader wind/color
	var verts: Array[Dictionary] = [
		{"pos": Vector3(-hw, 0.0, 0.0), "uv": Vector2(0.0, 0.0)},                     # 0: base left
		{"pos": Vector3(hw, 0.0, 0.0), "uv": Vector2(1.0, 0.0)},                      # 1: base right
		{"pos": Vector3(-hw * 0.85, height * 0.25, 0.0), "uv": Vector2(0.08, 0.25)},   # 2: lower-mid L
		{"pos": Vector3(hw * 0.85, height * 0.25, 0.0), "uv": Vector2(0.92, 0.25)},    # 3: lower-mid R
		{"pos": Vector3(-hw * 0.6, height * 0.5, 0.0), "uv": Vector2(0.2, 0.5)},       # 4: mid L
		{"pos": Vector3(hw * 0.6, height * 0.5, 0.0), "uv": Vector2(0.8, 0.5)},        # 5: mid R
		{"pos": Vector3(-hw * 0.3, height * 0.75, 0.0), "uv": Vector2(0.35, 0.75)},    # 6: upper-mid L
		{"pos": Vector3(hw * 0.3, height * 0.75, 0.0), "uv": Vector2(0.65, 0.75)},     # 7: upper-mid R
		{"pos": Vector3(0.0, height, 0.0), "uv": Vector2(0.5, 1.0)},                   # 8: tip
	]

	# Front face triangles (5 quads → 10 triangles, top segment is 1 triangle)
	# Segment 0: verts 0-1-2-3
	_add_vert(st, verts[0]); _add_vert(st, verts[2]); _add_vert(st, verts[1])
	_add_vert(st, verts[1]); _add_vert(st, verts[2]); _add_vert(st, verts[3])
	# Segment 1: verts 2-3-4-5
	_add_vert(st, verts[2]); _add_vert(st, verts[4]); _add_vert(st, verts[3])
	_add_vert(st, verts[3]); _add_vert(st, verts[4]); _add_vert(st, verts[5])
	# Segment 2: verts 4-5-6-7
	_add_vert(st, verts[4]); _add_vert(st, verts[6]); _add_vert(st, verts[5])
	_add_vert(st, verts[5]); _add_vert(st, verts[6]); _add_vert(st, verts[7])
	# Segment 3: verts 6-7-8 (triangle)
	_add_vert(st, verts[6]); _add_vert(st, verts[8]); _add_vert(st, verts[7])

	# Back face (reversed winding for cull_disabled rendering)
	_add_vert(st, verts[0]); _add_vert(st, verts[1]); _add_vert(st, verts[2])
	_add_vert(st, verts[1]); _add_vert(st, verts[3]); _add_vert(st, verts[2])
	_add_vert(st, verts[2]); _add_vert(st, verts[3]); _add_vert(st, verts[4])
	_add_vert(st, verts[3]); _add_vert(st, verts[5]); _add_vert(st, verts[4])
	_add_vert(st, verts[4]); _add_vert(st, verts[5]); _add_vert(st, verts[6])
	_add_vert(st, verts[5]); _add_vert(st, verts[7]); _add_vert(st, verts[6])
	_add_vert(st, verts[6]); _add_vert(st, verts[7]); _add_vert(st, verts[8])

	st.generate_normals()
	return st.commit()


func _add_vert(st: SurfaceTool, data: Dictionary) -> void:
	st.set_uv(data.uv)
	st.add_vertex(data.pos)


func _create_frond_mesh() -> ArrayMesh:
	## Tall alien frond — wider blade that curls at the tip. 3 segments.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var width: float = 0.08  # Wider than grass
	var height: float = 1.2
	var hw := width * 0.5

	var verts: Array[Dictionary] = [
		{"pos": Vector3(-hw, 0.0, 0.0), "uv": Vector2(0.0, 0.0)},
		{"pos": Vector3(hw, 0.0, 0.0), "uv": Vector2(1.0, 0.0)},
		{"pos": Vector3(-hw * 1.2, height * 0.3, 0.01), "uv": Vector2(0.0, 0.3)},
		{"pos": Vector3(hw * 1.2, height * 0.3, 0.01), "uv": Vector2(1.0, 0.3)},
		{"pos": Vector3(-hw * 0.8, height * 0.6, 0.04), "uv": Vector2(0.1, 0.6)},
		{"pos": Vector3(hw * 0.8, height * 0.6, 0.04), "uv": Vector2(0.9, 0.6)},
		{"pos": Vector3(-hw * 0.3, height * 0.85, 0.08), "uv": Vector2(0.35, 0.85)},
		{"pos": Vector3(hw * 0.3, height * 0.85, 0.08), "uv": Vector2(0.65, 0.85)},
		{"pos": Vector3(0.0, height, 0.12), "uv": Vector2(0.5, 1.0)},
	]

	# Front face
	_add_vert(st, verts[0]); _add_vert(st, verts[2]); _add_vert(st, verts[1])
	_add_vert(st, verts[1]); _add_vert(st, verts[2]); _add_vert(st, verts[3])
	_add_vert(st, verts[2]); _add_vert(st, verts[4]); _add_vert(st, verts[3])
	_add_vert(st, verts[3]); _add_vert(st, verts[4]); _add_vert(st, verts[5])
	_add_vert(st, verts[4]); _add_vert(st, verts[6]); _add_vert(st, verts[5])
	_add_vert(st, verts[5]); _add_vert(st, verts[6]); _add_vert(st, verts[7])
	_add_vert(st, verts[6]); _add_vert(st, verts[8]); _add_vert(st, verts[7])
	# Back face
	_add_vert(st, verts[0]); _add_vert(st, verts[1]); _add_vert(st, verts[2])
	_add_vert(st, verts[1]); _add_vert(st, verts[3]); _add_vert(st, verts[2])
	_add_vert(st, verts[2]); _add_vert(st, verts[3]); _add_vert(st, verts[4])
	_add_vert(st, verts[3]); _add_vert(st, verts[5]); _add_vert(st, verts[4])
	_add_vert(st, verts[4]); _add_vert(st, verts[5]); _add_vert(st, verts[6])
	_add_vert(st, verts[5]); _add_vert(st, verts[7]); _add_vert(st, verts[6])
	_add_vert(st, verts[6]); _add_vert(st, verts[7]); _add_vert(st, verts[8])

	st.generate_normals()
	return st.commit()


func _create_mushroom_mesh() -> ArrayMesh:
	## Flat disc-on-stem mushroom shape. Low-poly alien fungus.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stem_radius: float = 0.015
	var cap_radius: float = 0.06
	var stem_height: float = 0.3
	var cap_height: float = 0.08
	var segments: int = 8

	# Generate stem (cylinder)
	for i in range(segments):
		var angle0 := float(i) / float(segments) * TAU
		var angle1 := float(i + 1) / float(segments) * TAU
		var x0 := cos(angle0) * stem_radius
		var z0 := sin(angle0) * stem_radius
		var x1 := cos(angle1) * stem_radius
		var z1 := sin(angle1) * stem_radius
		var u0 := float(i) / float(segments)
		var u1 := float(i + 1) / float(segments)

		# Stem wall
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(Vector3(x0, 0.0, z0))
		st.set_uv(Vector2(u0, 0.4))
		st.add_vertex(Vector3(x0, stem_height, z0))
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(Vector3(x1, 0.0, z1))
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(Vector3(x1, 0.0, z1))
		st.set_uv(Vector2(u0, 0.4))
		st.add_vertex(Vector3(x0, stem_height, z0))
		st.set_uv(Vector2(u1, 0.4))
		st.add_vertex(Vector3(x1, stem_height, z1))

	# Generate cap (cone/dome)
	for i in range(segments):
		var angle0 := float(i) / float(segments) * TAU
		var angle1 := float(i + 1) / float(segments) * TAU
		var cx0 := cos(angle0) * cap_radius
		var cz0 := sin(angle0) * cap_radius
		var cx1 := cos(angle1) * cap_radius
		var cz1 := sin(angle1) * cap_radius

		# Cap underside (ring at stem_height)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(0.0, stem_height, 0.0))
		st.set_uv(Vector2(float(i) / float(segments), 0.6))
		st.add_vertex(Vector3(cx0, stem_height, cz0))
		st.set_uv(Vector2(float(i + 1) / float(segments), 0.6))
		st.add_vertex(Vector3(cx1, stem_height, cz1))

		# Cap top (dome)
		st.set_uv(Vector2(float(i) / float(segments), 0.6))
		st.add_vertex(Vector3(cx0, stem_height, cz0))
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(Vector3(0.0, stem_height + cap_height, 0.0))
		st.set_uv(Vector2(float(i + 1) / float(segments), 0.6))
		st.add_vertex(Vector3(cx1, stem_height, cz1))

	st.generate_normals()
	return st.commit()


# ── Material ─────────────────────────────────────────────────────────────

func _create_vegetation_material(biome: Dictionary) -> ShaderMaterial:
	var shader := load("res://assets/shaders/vegetation.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Derive alien vegetation colors from biome
	var grass_col: Color = biome.get("grass_color", Color(0.4, 0.42, 0.38))
	# Pioneer vegetation: grey-green lichen on regolith
	var base_col := Color(
		grass_col.r * 0.5 + 0.08,
		grass_col.g * 0.6 + 0.10,
		grass_col.b * 0.4 + 0.05
	)
	var tip_col := Color(
		base_col.r * 1.1 + 0.05,
		base_col.g * 1.3 + 0.08,
		base_col.b * 0.9 + 0.03
	)
	var bio_col := Color(
		0.05 + grass_col.b * 0.15,
		0.10 + grass_col.g * 0.20,
		0.20 + grass_col.b * 0.25
	)
	var trans_col := Color(
		base_col.r * 1.2 + 0.1,
		base_col.g * 1.4 + 0.15,
		base_col.b * 0.8 + 0.05
	)

	mat.set_shader_parameter("vegetation_base_color", base_col)
	mat.set_shader_parameter("vegetation_tip_color", tip_col)
	mat.set_shader_parameter("bioluminescence_color", bio_col)
	mat.set_shader_parameter("transmission_color", trans_col)
	mat.set_shader_parameter("territory_activity", 0.0)
	mat.set_shader_parameter("territory_power", 0.0)

	return mat


# ── Utility ──────────────────────────────────────────────────────────────

func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CHUNK_SIZE)), int(floor(pos.z / CHUNK_SIZE)))


func _chunk_to_world(coord: Vector2i) -> Vector3:
	return Vector3(
		coord.x * CHUNK_SIZE + CHUNK_SIZE * 0.5,
		0.0,
		coord.y * CHUNK_SIZE + CHUNK_SIZE * 0.5
	)


func _chunk_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


func _is_in_exclusion_zone(wx: float, wz: float) -> bool:
	for zone in EXCLUSION_ZONES:
		var dx: float = wx - zone.x
		var dz: float = wz - zone.z
		if dx * dx + dz * dz < zone.radius * zone.radius:
			return true
	return false
