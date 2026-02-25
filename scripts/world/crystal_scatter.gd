extends Node3D
## Crystalline mineral formations that emerge with terraforming.
## Hexagonal prism ArrayMesh clusters placed on terrain via MultiMesh.
## Scale grows from 0 → full as territory_power increases.
## Glows with bioluminescent energy from the chain state.

const CRYSTAL_SHADER = preload("res://assets/shaders/crystal.gdshader")

const MAX_CRYSTALS: int = 80
const TERRITORY_HALF: float = 200.0
const MIN_POWER: float = 0.05

var _terrain: Node3D
var _multimesh_inst: MultiMeshInstance3D
var _crystal_mesh: ArrayMesh
var _shader_mat: ShaderMaterial
var _current_power: float = 0.0
var _target_scale: float = 0.0
var _seed: int = 0


func initialize(seed_val: int, terrain: Node3D, biome: Dictionary) -> void:
	_seed = seed_val
	_terrain = terrain
	_crystal_mesh = _create_crystal_mesh()
	_shader_mat = _create_crystal_material(biome)
	_place_crystals()


func set_territory_power(power: float) -> void:
	_current_power = power
	_target_scale = clampf(power, 0.0, 1.0)
	if _shader_mat:
		_shader_mat.set_shader_parameter("territory_power", power)


func _process(delta: float) -> void:
	# Smoothly grow/shrink crystals toward target scale
	if not _multimesh_inst or not is_instance_valid(_multimesh_inst):
		return
	var current := _multimesh_inst.scale.x
	var target := maxf(_target_scale * 1.5, 0.01)  # Scale 0-1.5
	if absf(current - target) > 0.001:
		var new_s := lerpf(current, target, delta * 2.0)
		_multimesh_inst.scale = Vector3(new_s, new_s, new_s)


func _place_crystals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + 31337

	_multimesh_inst = MultiMeshInstance3D.new()
	_multimesh_inst.name = "CrystalFormations"
	_multimesh_inst.material_override = _shader_mat
	add_child(_multimesh_inst)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = MAX_CRYSTALS
	mm.mesh = _crystal_mesh

	for i in range(MAX_CRYSTALS):
		var x := rng.randf_range(-TERRITORY_HALF * 0.9, TERRITORY_HALF * 0.9)
		var z := rng.randf_range(-TERRITORY_HALF * 0.9, TERRITORY_HALF * 0.9)

		# Skip near monument and beat station
		if Vector2(x, z + 40.0).length() < 35.0:
			x = rng.randf_range(50.0, 150.0) * sign(rng.randf() - 0.5)
		if Vector2(x, z - 60.0).length() < 20.0:
			z = rng.randf_range(-120.0, -60.0)

		var y := 0.0
		if _terrain and _terrain.has_method("get_height_at"):
			y = _terrain.get_height_at(x, z)

		var xform := Transform3D()
		# Random rotation
		xform = xform.rotated(Vector3.UP, rng.randf() * TAU)
		# Random tilt (crystals angle outward from ground)
		var tilt := rng.randf_range(0.0, deg_to_rad(25.0))
		xform = xform.rotated(Vector3.RIGHT, tilt)
		# Random scale
		var s := rng.randf_range(0.5, 2.0)
		xform = xform.scaled(Vector3(s, s * rng.randf_range(1.0, 2.5), s))
		xform.origin = Vector3(x, y, z)
		mm.set_instance_transform(i, xform)

	_multimesh_inst.multimesh = mm
	_multimesh_inst.scale = Vector3(0.01, 0.01, 0.01)  # Start invisible


func _create_crystal_mesh() -> ArrayMesh:
	## Hexagonal prism — 6-sided column.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radius: float = 0.15
	var height: float = 0.6
	var sides: int = 6

	# Bottom center and top center
	var bottom_y: float = 0.0
	var top_y: float = height

	# Generate side faces
	for i in range(sides):
		var angle0 := float(i) / float(sides) * TAU
		var angle1 := float(i + 1) / float(sides) * TAU
		var x0 := cos(angle0) * radius
		var z0 := sin(angle0) * radius
		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius

		# Taper toward top (pyramidal tip)
		var top_radius := radius * 0.3
		var tx0 := cos(angle0) * top_radius
		var tz0 := sin(angle0) * top_radius
		var tx1 := cos(angle1) * top_radius
		var tz1 := sin(angle1) * top_radius

		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)

		# Side quad (two triangles)
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(Vector3(x0, bottom_y, z0))
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(Vector3(tx0, top_y, tz0))
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(Vector3(x1, bottom_y, z1))

		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(Vector3(x1, bottom_y, z1))
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(Vector3(tx0, top_y, tz0))
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(Vector3(tx1, top_y, tz1))

	# Top cap (triangle fan)
	for i in range(sides):
		var angle0 := float(i) / float(sides) * TAU
		var angle1 := float(i + 1) / float(sides) * TAU
		var top_r := radius * 0.3
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(Vector3(0.0, top_y + 0.05, 0.0))  # Pointed tip
		st.set_uv(Vector2(float(i) / float(sides), 0.9))
		st.add_vertex(Vector3(cos(angle0) * top_r, top_y, sin(angle0) * top_r))
		st.set_uv(Vector2(float(i + 1) / float(sides), 0.9))
		st.add_vertex(Vector3(cos(angle1) * top_r, top_y, sin(angle1) * top_r))

	st.generate_normals()
	return st.commit()


func _create_crystal_material(biome: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CRYSTAL_SHADER

	# Crystal color from biome accent
	var grass: Color = biome.get("grass_color", Color(0.3, 0.35, 0.4))
	var crystal_col := Color(
		0.3 + grass.b * 0.5,
		0.4 + grass.g * 0.3,
		0.6 + grass.r * 0.2
	)
	mat.set_shader_parameter("crystal_color", Vector3(crystal_col.r, crystal_col.g, crystal_col.b))
	mat.set_shader_parameter("territory_power", 0.0)

	return mat
