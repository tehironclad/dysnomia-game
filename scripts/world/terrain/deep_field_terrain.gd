class_name DeepFieldTerrain
extends Node3D
## A territory's walkable ground (WP 2.2). Heights: JuliaHeightfield at 513²
## (1 m spacing, the collider's native resolution). Mesh: every `mesh_step`-th
## sample. Light: deep_field_terrain.gdshader, the Julia set per pixel in
## world space. Everything derives from the territory's Entropy() + address.

const SHADER := preload("res://assets/shaders/deep_field_terrain.gdshader")
const STYLE_INDEX := {"glow": 0, "duo": 1, "bands": 2, "ember": 3, "gilded": 4, "prism": 5}
const SAMPLES := 513  ## 512 m / 512 intervals = 1 m spacing

@export var mesh_step := 2  ## 2 → 257² mesh vertices
var heightfield: JuliaHeightfield
var params: Dictionary = {}
var material: ShaderMaterial
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D


## Builds ground for a Registry territory record. Blocks while the heightfield
## computes the first time (~4 s); later loads come from the disk cache.
func build(q: Dictionary) -> void:
	params = DeepField.for_territory(q)
	heightfield = JuliaHeightfield.for_territory(q, SAMPLES)
	_build_material()
	_build_mesh()
	_build_collider()
	Inspector.register(self, "Ground",
		"Heights: the filled Julia set of %s — inside the set is a plateau, its boundary a crest, outside the land falls away with the distance estimate (JuliaHeightfield v%d).\nLight: the same set computed per pixel in world space; filaments glow where the land meets the set." % [
			DeepField.describe(params, "QING.Entropy()", String(q["entropy"]), String(q["address"])),
			JuliaHeightfield.VERSION])


func height_at(x: float, z: float) -> float:
	return heightfield.height_at(x, z) if heightfield else 0.0


## The player controller's height query.
func get_height_at(x: float, z: float) -> float:
	return height_at(x, z)


func _build_material() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	var c: Array = params["c"]
	material.set_shader_parameter("c", Vector2(c[0], c[1]))
	material.set_shader_parameter("power", int(params["power"]))
	material.set_shader_parameter("extent", float(params["extent"]))
	material.set_shader_parameter("rotation", float(params["rotation"]))
	material.set_shader_parameter("half_size", JuliaHeightfield.SIZE_M * 0.5)
	material.set_shader_parameter("color", Vector3(params["color"][0], params["color"][1], params["color"][2]))
	material.set_shader_parameter("color2", Vector3(params["color2"][0], params["color2"][1], params["color2"][2]))
	material.set_shader_parameter("hue", float(params["hue"]))
	var rd := "res://assets/textures/polyhaven/moon_dusted_02/moon_dusted_02_"
	material.set_shader_parameter("regolith_albedo", load(rd + "diff_1k.jpg"))
	material.set_shader_parameter("regolith_normal", load(rd + "nor_gl_1k.jpg"))
	material.set_shader_parameter("regolith_rough", load(rd + "rough_1k.jpg"))
	material.set_shader_parameter("style", STYLE_INDEX.get(String(params["style"]), 0))


## Shared state hooks (WP 2.5): brightness and lit escape bands.
func set_activity(glow: float, lit_bands: float) -> void:
	if material:
		material.set_shader_parameter("glow", glow)
		material.set_shader_parameter("lit_bands", lit_bands)


func _build_mesh() -> void:
	var hf := heightfield
	var n := hf.n
	var step := mesh_step
	var m := (n - 1) / step + 1  # vertices per side
	var sp := JuliaHeightfield.sample_spacing(n) * step
	var half := JuliaHeightfield.SIZE_M * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(m * m)
	normals.resize(m * m)
	uvs.resize(m * m)
	var h := hf.heights
	for r in m:
		for col in m:
			var hr := mini(r * step, n - 1)
			var hc := mini(col * step, n - 1)
			var k := r * m + col
			verts[k] = Vector3(-half + col * sp, h[hr * n + hc], -half + r * sp)
			var hl := h[hr * n + maxi(hc - step, 0)]
			var hx := h[hr * n + mini(hc + step, n - 1)]
			var hu := h[maxi(hr - step, 0) * n + hc]
			var hd := h[mini(hr + step, n - 1) * n + hc]
			normals[k] = Vector3(hl - hx, 2.0 * sp, hu - hd).normalized()
			uvs[k] = Vector2(float(col) / (m - 1), float(r) / (m - 1))
	var idx := PackedInt32Array()
	idx.resize((m - 1) * (m - 1) * 6)
	var w := 0
	for r in m - 1:
		for col in m - 1:
			var a := r * m + col
			var b := a + 1
			var cc := a + m
			var d := cc + 1
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = cc
			idx[w + 3] = b
			idx[w + 4] = d
			idx[w + 5] = cc
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	if _mesh_instance:
		_mesh_instance.queue_free()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GroundMesh"
	_mesh_instance.mesh = mesh
	add_child(_mesh_instance)


func _build_collider() -> void:
	var hf := heightfield
	var shape := HeightMapShape3D.new()
	shape.map_width = hf.n
	shape.map_depth = hf.n
	shape.map_data = hf.heights
	if _body:
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.name = "GroundBody"
	var cs := CollisionShape3D.new()
	cs.shape = shape  # 1 m spacing at 513 samples: no scaling needed, centred on the origin
	_body.add_child(cs)
	add_child(_body)
