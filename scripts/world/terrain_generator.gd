extends Node3D
## Procedural terrain generator using multi-octave simplex noise.
## Deterministic: same seed always produces identical terrain.
## Designed for QING territory visualization — seed comes from chain data.
## Terrain represents Dysnomia's lunar surface: craters, ridges, regolith.

const TERRAIN_SIZE: float = 400.0 # meters per side
const TERRAIN_RESOLUTION: int = 256 # default — overridden by Config quality preset

var _heights: PackedFloat32Array
var _terrain_mesh_instance: MeshInstance3D
var _collision_body: StaticBody3D
var _material: ShaderMaterial
var _resolution: int = TERRAIN_RESOLUTION  # actual resolution for this instance

# Noise instances for multi-layer terrain
var _base_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _erosion_noise: FastNoiseLite

var _current_seed: int = 0
var _current_params: Dictionary = {}


func generate(seed_value: int, params: Dictionary, resolution_override: int = 0) -> void:
	_current_seed = seed_value
	_current_params = params
	if resolution_override > 0:
		_resolution = resolution_override
	else:
		var preset: Dictionary = Config.get_quality_preset()
		_resolution = preset.get("terrain_resolution", TERRAIN_RESOLUTION)

	_configure_noise(seed_value, params)
	_generate_heightmap(params)
	_stamp_craters(seed_value, params)
	_build_terrain_mesh()
	_build_collision()


func get_height_at(world_x: float, world_z: float) -> float:
	if _heights.is_empty():
		return 0.0

	# Convert world coords to grid coords
	var half_size: float = TERRAIN_SIZE / 2.0
	var gx: float = (world_x + half_size) / TERRAIN_SIZE * (_resolution - 1)
	var gz: float = (world_z + half_size) / TERRAIN_SIZE * (_resolution - 1)

	# Clamp to grid bounds
	gx = clampf(gx, 0.0, _resolution - 2.0)
	gz = clampf(gz, 0.0, _resolution - 2.0)

	# Bilinear interpolation
	var ix: int = int(gx)
	var iz: int = int(gz)
	var fx: float = gx - ix
	var fz: float = gz - iz

	var h00: float = _heights[iz * _resolution + ix]
	var h10: float = _heights[iz * _resolution + ix + 1]
	var h01: float = _heights[(iz + 1) * _resolution + ix]
	var h11: float = _heights[(iz + 1) * _resolution + ix + 1]

	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func set_shader_material(mat: ShaderMaterial) -> void:
	_material = mat
	if _terrain_mesh_instance:
		_terrain_mesh_instance.material_override = _material


func _configure_noise(seed_value: int, params: Dictionary) -> void:
	var freq: float = params.get("frequency", 0.008)
	var octaves: int = params.get("octaves", 6)
	var lac: float = params.get("lacunarity", 2.0)
	var gain: float = params.get("gain", 0.5)

	# Base terrain noise — broad elevation changes, cratered highlands
	_base_noise = FastNoiseLite.new()
	_base_noise.seed = seed_value
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_base_noise.fractal_octaves = octaves
	_base_noise.fractal_lacunarity = lac
	_base_noise.fractal_gain = gain
	_base_noise.frequency = freq

	# Ridge noise — crater rims and sharp ridges (impact features)
	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = seed_value + 1
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 4
	_ridge_noise.fractal_lacunarity = 2.5
	_ridge_noise.fractal_gain = 0.45
	_ridge_noise.frequency = freq * 2.0

	# Detail noise — fine regolith texture, microcraters
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = seed_value + 2
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_lacunarity = 2.0
	_detail_noise.fractal_gain = 0.5
	_detail_noise.frequency = freq * 8.0

	# Erosion noise — crater bowls (depressions carved by impacts)
	_erosion_noise = FastNoiseLite.new()
	_erosion_noise.seed = seed_value + 3
	_erosion_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_erosion_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_erosion_noise.fractal_octaves = 3
	_erosion_noise.fractal_lacunarity = 1.8
	_erosion_noise.fractal_gain = 0.55
	_erosion_noise.frequency = freq * 0.6


func _generate_heightmap(params: Dictionary) -> void:
	var max_height: float = params.get("max_height", 40.0)
	var ridge_strength: float = params.get("ridge_strength", 0.3)
	var erosion_strength: float = params.get("erosion_strength", 0.2)
	var biome_type: int = params.get("biome_type", 0)
	var step: float = TERRAIN_SIZE / float(_resolution - 1)

	_heights = PackedFloat32Array()
	_heights.resize(_resolution * _resolution)

	for gz in range(_resolution):
		for gx in range(_resolution):
			var world_x: float = gx * step - TERRAIN_SIZE / 2.0
			var world_z: float = gz * step - TERRAIN_SIZE / 2.0

			# Base terrain layer
			var base_h: float = _base_noise.get_noise_2d(world_x, world_z) * max_height

			# Ridge layer — sharp peaks
			var ridge_val: float = _ridge_noise.get_noise_2d(world_x, world_z)
			var ridge_h: float = ridge_val * max_height * ridge_strength

			# Detail layer — fine surface texture
			var detail_h: float = _detail_noise.get_noise_2d(world_x, world_z) * max_height * 0.05

			# Erosion layer — carve valleys where noise is high
			var erosion_val: float = _erosion_noise.get_noise_2d(world_x, world_z)
			var erosion_h: float = maxf(0.0, erosion_val - 0.3) * max_height * erosion_strength

			var height: float = base_h + ridge_h + detail_h - erosion_h

			# Apply biome-specific modifications
			height = _apply_biome(height, world_x, world_z, biome_type, max_height)

			_heights[gz * _resolution + gx] = height


func _apply_biome(height: float, world_x: float, world_z: float, biome_type: int, max_height: float) -> float:
	match biome_type:
		0: # Cratered Highlands — amplified relief, deep craters
			return height * 1.5
		1: # Mare Basin — flatter, smoother plains (ancient lava flows)
			return height * 0.45
		2: # Rift Valley — deep central trench with raised edges
			var rift_factor: float = smoothstep(0.0, TERRAIN_SIZE * 0.15, absf(world_x))
			return height * (0.6 + rift_factor * 0.8) - (1.0 - rift_factor) * max_height * 0.3
		3: # Impact Shelf — terraced descent (ejecta blanket)
			var shelf_factor: float = smoothstep(-TERRAIN_SIZE * 0.2, TERRAIN_SIZE * 0.3, world_z)
			return height * (0.5 + shelf_factor * 0.5) - (1.0 - shelf_factor) * 5.0
		_:
			return height


func _stamp_craters(seed_value: int, params: Dictionary) -> void:
	## Stamp explicit impact craters with realistic morphology onto the heightmap.
	## Creates bowl-shaped depressions with raised rims, ejecta skirts,
	## and optional central peaks for larger craters.
	var biome_type: int = params.get("biome_type", 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 100

	# Number of craters varies by biome: highlands have more, mare fewer
	var num_craters: int
	match biome_type:
		0: num_craters = rng.randi_range(5, 10)  # Cratered Highlands — heavily cratered
		1: num_craters = rng.randi_range(2, 5)    # Mare Basin — fewer craters
		2: num_craters = rng.randi_range(3, 7)    # Rift Valley — moderate
		3: num_craters = rng.randi_range(4, 8)    # Impact Shelf — many secondary craters
		_: num_craters = rng.randi_range(3, 8)

	var largest_cx: float = 0.0
	var largest_cz: float = 0.0
	var largest_radius: float = 0.0

	for i in range(num_craters):
		var cx: float = rng.randf_range(-TERRAIN_SIZE * 0.35, TERRAIN_SIZE * 0.35)
		var cz: float = rng.randf_range(-TERRAIN_SIZE * 0.35, TERRAIN_SIZE * 0.35)
		var radius: float = rng.randf_range(8.0, 50.0)
		var depth: float = radius * rng.randf_range(0.2, 0.3)  # depth-to-diameter ratio
		var rim_height: float = depth * rng.randf_range(0.25, 0.4)
		var has_peak: bool = radius > 35.0  # Central peak for larger craters

		_apply_crater(cx, cz, radius, depth, rim_height, has_peak)

		if radius > largest_radius:
			largest_radius = radius
			largest_cx = cx
			largest_cz = cz

	# Secondary crater chain from largest impact — line of smaller craters
	if largest_radius > 25.0:
		var chain_angle: float = rng.randf_range(0.0, TAU)
		var chain_count: int = rng.randi_range(3, 5)
		for j in range(chain_count):
			var dist: float = largest_radius * (1.5 + float(j) * 0.8)
			var scatter: float = rng.randf_range(-0.3, 0.3)
			var sx: float = largest_cx + cos(chain_angle + scatter) * dist
			var sz: float = largest_cz + sin(chain_angle + scatter) * dist
			# Skip if too far outside terrain
			if absf(sx) > TERRAIN_SIZE * 0.45 or absf(sz) > TERRAIN_SIZE * 0.45:
				continue
			var sr: float = rng.randf_range(3.0, largest_radius * 0.25)
			var sd: float = sr * 0.25
			_apply_crater(sx, sz, sr, sd, sd * 0.3, false)


func _apply_crater(cx: float, cz: float, radius: float, depth: float, rim_height: float, has_peak: bool) -> void:
	## Apply a single impact crater to the heightmap with realistic profile:
	## - Parabolic bowl interior (sharp inner wall ~35-40 deg)
	## - Raised rim ring at the edge
	## - Gentle ejecta skirt extending to ~2.5x radius
	## - Optional central peak for complex craters
	var step: float = TERRAIN_SIZE / float(_resolution - 1)
	var affect_radius: float = radius * 2.5  # Ejecta extends well beyond crater

	# Convert crater center to grid bounds (only iterate affected area)
	var half_size: float = TERRAIN_SIZE / 2.0
	var gx_min: int = maxi(0, int((cx - affect_radius + half_size) / step))
	var gx_max: int = mini(_resolution - 1, int((cx + affect_radius + half_size) / step) + 1)
	var gz_min: int = maxi(0, int((cz - affect_radius + half_size) / step))
	var gz_max: int = mini(_resolution - 1, int((cz + affect_radius + half_size) / step) + 1)

	for gz in range(gz_min, gz_max + 1):
		for gx in range(gx_min, gx_max + 1):
			var world_x: float = gx * step - half_size
			var world_z: float = gz * step - half_size

			var dx: float = world_x - cx
			var dz: float = world_z - cz
			var dist: float = sqrt(dx * dx + dz * dz)

			if dist > affect_radius:
				continue

			var idx: int = gz * _resolution + gx
			var normalized_dist: float = dist / radius

			var height_mod: float = 0.0

			if normalized_dist < 1.0:
				# ── Inside crater: parabolic bowl ──
				# Steep inner walls, flat floor for smaller craters
				var bowl: float = normalized_dist * normalized_dist
				height_mod = -depth * (1.0 - bowl)

				# Central peak for complex craters
				if has_peak and normalized_dist < 0.25:
					var peak_factor: float = 1.0 - (normalized_dist / 0.25)
					peak_factor = peak_factor * peak_factor  # Sharpen peak
					height_mod += depth * 0.35 * peak_factor

				# Raised rim (gaussian peak at edge)
				var rim_dist: float = absf(normalized_dist - 0.9)
				var rim: float = exp(-rim_dist * rim_dist / 0.02) * rim_height
				height_mod += rim

			else:
				# ── Outside crater: ejecta skirt ──
				# Gentle raised slope that fades with distance
				var ejecta_dist: float = (normalized_dist - 1.0) / 1.5  # 0 at rim, 1 at 2.5x radius
				if ejecta_dist < 1.0:
					var ejecta: float = (1.0 - ejecta_dist)
					ejecta = ejecta * ejecta * ejecta  # Cubic falloff
					height_mod = rim_height * 0.3 * ejecta

			_heights[idx] += height_mod


func _build_terrain_mesh() -> void:
	# Clean up previous mesh
	if _terrain_mesh_instance:
		_terrain_mesh_instance.queue_free()

	var step: float = TERRAIN_SIZE / float(_resolution - 1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	verts.resize(_resolution * _resolution)
	normals.resize(_resolution * _resolution)
	uvs.resize(_resolution * _resolution)

	# Build vertex positions and UVs
	for gz in range(_resolution):
		for gx in range(_resolution):
			var idx: int = gz * _resolution + gx
			var world_x: float = gx * step - TERRAIN_SIZE / 2.0
			var world_z: float = gz * step - TERRAIN_SIZE / 2.0
			var h: float = _heights[idx]

			verts[idx] = Vector3(world_x, h, world_z)
			uvs[idx] = Vector2(world_x / 10.0, world_z / 10.0)

	# Compute normals via cross product of neighbors
	# Edge vertices use mirror-extrapolation instead of repeating (avoids degenerate normals)
	for gz in range(_resolution):
		for gx in range(_resolution):
			var idx: int = gz * _resolution + gx

			var left: Vector3
			if gx > 0:
				left = verts[idx - 1]
			else:
				left = verts[idx] + (verts[idx] - verts[idx + 1])

			var right: Vector3
			if gx < _resolution - 1:
				right = verts[idx + 1]
			else:
				right = verts[idx] + (verts[idx] - verts[idx - 1])

			var down: Vector3
			if gz > 0:
				down = verts[idx - _resolution]
			else:
				down = verts[idx] + (verts[idx] - verts[idx + _resolution])

			var up: Vector3
			if gz < _resolution - 1:
				up = verts[idx + _resolution]
			else:
				up = verts[idx] + (verts[idx] - verts[idx - _resolution])

			var dx: Vector3 = right - left
			var dz: Vector3 = up - down
			var n: Vector3 = dz.cross(dx)
			normals[idx] = n.normalized() if n.length_squared() > 0.0001 else Vector3.UP

	# Build index buffer (two triangles per quad)
	var num_quads: int = (_resolution - 1) * (_resolution - 1)
	indices.resize(num_quads * 6)
	var tri_idx: int = 0
	for gz in range(_resolution - 1):
		for gx in range(_resolution - 1):
			var top_left: int = gz * _resolution + gx
			var top_right: int = top_left + 1
			var bottom_left: int = (gz + 1) * _resolution + gx
			var bottom_right: int = bottom_left + 1

			# Triangle 1
			indices[tri_idx] = top_left
			indices[tri_idx + 1] = bottom_left
			indices[tri_idx + 2] = top_right
			# Triangle 2
			indices[tri_idx + 3] = top_right
			indices[tri_idx + 4] = bottom_left
			indices[tri_idx + 5] = bottom_right
			tri_idx += 6

	# ── Terrain Skirt: vertical walls hanging from edge vertices to hide underside ──
	var skirt_drop: float = 30.0
	var skirt_base_vert: int = verts.size()
	var skirt_verts := PackedVector3Array()
	var skirt_normals := PackedVector3Array()
	var skirt_uvs := PackedVector2Array()
	var skirt_indices := PackedInt32Array()

	# Collect edge vertex indices in order: bottom (gz=0), right (gx=max), top (gz=max), left (gx=0)
	var edge_strips: Array[PackedInt32Array] = []
	var edge_outward_normals: Array[Vector3] = [
		Vector3(0.0, 0.0, -1.0),  # Bottom edge faces -Z
		Vector3(1.0, 0.0, 0.0),   # Right edge faces +X
		Vector3(0.0, 0.0, 1.0),   # Top edge faces +Z
		Vector3(-1.0, 0.0, 0.0),  # Left edge faces -X
	]

	# Bottom edge (gz=0, gx 0 to max)
	var bottom_edge := PackedInt32Array()
	for gx2 in range(_resolution):
		bottom_edge.append(gx2)
	edge_strips.append(bottom_edge)

	# Right edge (gx=max, gz 0 to max)
	var right_edge := PackedInt32Array()
	for gz2 in range(_resolution):
		right_edge.append(gz2 * _resolution + (_resolution - 1))
	edge_strips.append(right_edge)

	# Top edge (gz=max, gx max to 0 — reversed for consistent winding)
	var top_edge := PackedInt32Array()
	for gx2 in range(_resolution - 1, -1, -1):
		top_edge.append((_resolution - 1) * _resolution + gx2)
	edge_strips.append(top_edge)

	# Left edge (gx=0, gz max to 0 — reversed for consistent winding)
	var left_edge := PackedInt32Array()
	for gz2 in range(_resolution - 1, -1, -1):
		left_edge.append(gz2 * _resolution)
	edge_strips.append(left_edge)

	for strip_i in range(edge_strips.size()):
		var strip: PackedInt32Array = edge_strips[strip_i]
		var outward: Vector3 = edge_outward_normals[strip_i]

		for ei in range(strip.size()):
			var orig_idx: int = strip[ei]
			var top_pos: Vector3 = verts[orig_idx]
			var bot_pos := Vector3(top_pos.x, top_pos.y - skirt_drop, top_pos.z)

			# Add two verts per edge vertex: top duplicate + dropped bottom
			skirt_verts.append(top_pos)
			skirt_normals.append(outward)
			skirt_uvs.append(uvs[orig_idx])

			skirt_verts.append(bot_pos)
			skirt_normals.append(outward)
			skirt_uvs.append(uvs[orig_idx])

		# Build quad strip triangles
		var strip_base: int = skirt_base_vert + strip_i * strip.size() * 2
		for ei in range(strip.size() - 1):
			var tl: int = strip_base + ei * 2
			var bl: int = tl + 1
			var tr: int = tl + 2
			var br: int = tl + 3
			# Two triangles per quad
			skirt_indices.append(tl)
			skirt_indices.append(bl)
			skirt_indices.append(tr)
			skirt_indices.append(tr)
			skirt_indices.append(bl)
			skirt_indices.append(br)

	# Merge skirt data into main arrays
	verts.append_array(skirt_verts)
	normals.append_array(skirt_normals)
	uvs.append_array(skirt_uvs)
	indices.append_array(skirt_indices)

	# Create ArrayMesh with tangents for proper normal mapping
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	# Compute tangent vectors (needed for NORMAL_MAP in terrain shader)
	var tangents := PackedFloat32Array()
	tangents.resize(verts.size() * 4)
	for ti in range(verts.size()):
		# UV-aligned tangent: along +X in world space (UV.x maps to world_x/10)
		var n: Vector3 = normals[ti]
		var t := Vector3(1.0, 0.0, 0.0)
		# Orthogonalize tangent against normal (Gram-Schmidt)
		t = (t - n * n.dot(t)).normalized()
		if t.length_squared() < 0.001:
			t = Vector3(0.0, 0.0, 1.0)
			t = (t - n * n.dot(t)).normalized()
		# Bitangent sign: cross(N, T) should align with +Z (UV.y direction)
		var b := n.cross(t)
		var sign_val: float = 1.0 if b.z >= 0.0 else -1.0
		tangents[ti * 4] = t.x
		tangents[ti * 4 + 1] = t.y
		tangents[ti * 4 + 2] = t.z
		tangents[ti * 4 + 3] = sign_val
	arrays[Mesh.ARRAY_TANGENT] = tangents

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Create mesh instance
	_terrain_mesh_instance = MeshInstance3D.new()
	_terrain_mesh_instance.mesh = mesh
	_terrain_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _material:
		_terrain_mesh_instance.material_override = _material
	add_child(_terrain_mesh_instance)


func _build_collision() -> void:
	# Clean up previous collision immediately (not deferred)
	if _collision_body and is_instance_valid(_collision_body):
		remove_child(_collision_body)
		_collision_body.queue_free()
		_collision_body = null

	if not _terrain_mesh_instance or not _terrain_mesh_instance.mesh:
		return

	# Build collision shape from heightmap directly (more reliable than get_faces)
	var step: float = TERRAIN_SIZE / float(_resolution - 1)
	var faces := PackedVector3Array()
	faces.resize((_resolution - 1) * (_resolution - 1) * 6)
	var fi: int = 0

	for gz in range(_resolution - 1):
		for gx in range(_resolution - 1):
			var x0: float = gx * step - TERRAIN_SIZE / 2.0
			var x1: float = (gx + 1) * step - TERRAIN_SIZE / 2.0
			var z0: float = gz * step - TERRAIN_SIZE / 2.0
			var z1: float = (gz + 1) * step - TERRAIN_SIZE / 2.0

			var h00: float = _heights[gz * _resolution + gx]
			var h10: float = _heights[gz * _resolution + gx + 1]
			var h01: float = _heights[(gz + 1) * _resolution + gx]
			var h11: float = _heights[(gz + 1) * _resolution + gx + 1]

			# Triangle 1 (top_left, bottom_left, top_right)
			faces[fi] = Vector3(x0, h00, z0)
			faces[fi + 1] = Vector3(x0, h01, z1)
			faces[fi + 2] = Vector3(x1, h10, z0)
			# Triangle 2 (top_right, bottom_left, bottom_right)
			faces[fi + 3] = Vector3(x1, h10, z0)
			faces[fi + 4] = Vector3(x0, h01, z1)
			faces[fi + 5] = Vector3(x1, h11, z1)
			fi += 6

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)

	_collision_body = StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	_collision_body.add_child(collision_shape)

	# Safety floor — invisible collision plane far below terrain to catch fallthrough
	var min_h: float = _heights[0]
	for hi in range(1, _heights.size()):
		min_h = minf(min_h, _heights[hi])
	var safety_box := BoxShape3D.new()
	safety_box.size = Vector3(TERRAIN_SIZE + 20.0, 2.0, TERRAIN_SIZE + 20.0)
	var safety_shape := CollisionShape3D.new()
	safety_shape.shape = safety_box
	safety_shape.position.y = min_h - 40.0
	_collision_body.add_child(safety_shape)

	add_child(_collision_body)


func flatten_area(center_x: float, center_z: float, half_w: float, half_d: float, margin: float = 15.0) -> void:
	## Flatten terrain within a rectangular area, with smooth blending at edges.
	## The target height is the average terrain height at the center of the area.
	## margin = distance over which terrain smoothly ramps from flat to natural.
	##
	## Use this to create a level building site for the mausoleum — like real
	## mausoleums carved into mountainsides with leveled platforms.

	if _heights.is_empty():
		return

	# Sample center height — average of a small area for stability
	var target_h: float = 0.0
	var sample_count: int = 0
	for sx in range(-2, 3):
		for sz in range(-2, 3):
			target_h += get_height_at(center_x + sx * 2.0, center_z + sz * 2.0)
			sample_count += 1
	target_h /= float(sample_count)

	var step: float = TERRAIN_SIZE / float(_resolution - 1)
	var changed: bool = false

	for gz in range(_resolution):
		for gx in range(_resolution):
			var world_x: float = gx * step - TERRAIN_SIZE / 2.0
			var world_z: float = gz * step - TERRAIN_SIZE / 2.0

			# Distance from center of flattened area
			var dx: float = absf(world_x - center_x)
			var dz: float = absf(world_z - center_z)

			# Skip vertices clearly outside the affected zone
			if dx > half_w + margin or dz > half_d + margin:
				continue

			# Compute blend factor: 1.0 = fully flat, 0.0 = natural terrain
			var blend_x: float = 1.0
			var blend_z: float = 1.0

			if dx > half_w:
				blend_x = 1.0 - smoothstep(half_w, half_w + margin, dx)
			if dz > half_d:
				blend_z = 1.0 - smoothstep(half_d, half_d + margin, dz)

			var blend: float = blend_x * blend_z

			if blend < 0.001:
				continue

			var idx: int = gz * _resolution + gx
			var natural_h: float = _heights[idx]
			_heights[idx] = lerpf(natural_h, target_h, blend)
			changed = true

	# Rebuild mesh and collision with the modified heights
	if changed:
		_build_terrain_mesh()
		_build_collision()


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
