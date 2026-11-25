class_name DeepFieldTerrain
extends Node3D
## A territory's walkable ground (WP 2.2). Heights: JuliaHeightfield at 725²
## (1 m spacing over 724 m, the collider's native resolution). Mesh: every `mesh_step`-th
## sample. Light: deep_field_terrain.gdshader, the Julia set per pixel in
## world space. Everything derives from the territory's Entropy() + address.

const SHADER := preload("res://assets/shaders/deep_field_terrain.gdshader")
const STYLE_INDEX := {"glow": 0, "duo": 1, "bands": 2, "ember": 3, "gilded": 4, "prism": 5}
const SAMPLES := int(JuliaHeightfield.SIZE_M) + 1  ## 1 m spacing (725 over 724 m)

@export var mesh_step := 2  ## 2 → 363² mesh vertices (2 m); 4 → 182² (4 m) on Potato/Low (Config preset "mesh_step")
var heightfield: JuliaHeightfield
var params: Dictionary = {}
var material: ShaderMaterial
var _mesh_instance: MeshInstance3D
var _shadow_instance: MeshInstance3D
const SHADOW_SINK_M := 0.45
var _body: StaticBody3D
## The ground mesh is computed on a worker thread (2026-11-25: ~150–200 ms of GDScript at 363²):
## build() starts it, mesh_ready() says when it's drawn, finish_mesh() waits for it.
var _mesh_thread: Thread
var _mesh_arrays: Array = []  ## [ground arrays, shadow arrays or []] once computed
var _mesh_has_shadow := false
var _is_main := false


## Builds ground for a Registry territory record. Blocks while the heightfield
## computes the first time (~8 s at 725²); later loads come from the disk cache.
func build(q: Dictionary) -> void:
	params = DeepField.for_territory(q)
	heightfield = JuliaHeightfield.for_territory(q, SAMPLES)
	LoadProfile.mark("heightfield")
	_is_main = true
	_build_material()
	mesh_step = _step_for_level()
	_start_mesh()
	_build_collider()
	LoadProfile.mark("collider")
	var cfg := get_node_or_null("/root/Config")
	if cfg and cfg.has_signal("applied") and not cfg.applied.is_connected(_on_config):
		cfg.applied.connect(_on_config)
	Inspector.register(self, "Ground",
		"Heights: the filled Julia set of %s — inside the set is a plateau, its boundary a crest, outside the land falls away with the distance estimate (JuliaHeightfield v%d).\nLight: the same set computed per pixel in world space; filaments glow where the land meets the set." % [
			DeepField.describe(params, "QING.Entropy()", String(q["entropy"]), String(q["address"])),
			JuliaHeightfield.VERSION])


## A neighbour's ground seen beyond the border (BorderRing): its own heightfield
## at a low resolution, drawn with its own Deep Field numbers, no collider.
## `centre` is where this node sits in the world (the shader's pattern origin).
func build_distant(q: Dictionary, hf: JuliaHeightfield, centre: Vector3, iterations: int = 40) -> void:
	params = DeepField.for_territory(q)
	heightfield = hf
	var cfg := get_node_or_null("/root/Config")
	mesh_step = int(cfg.preset().get("nb_step", 1)) if cfg else 1  # 181² (4 m), or 91² on Potato/Low
	_build_material()
	material.set_shader_parameter("centre", Vector2(centre.x, centre.z))
	material.set_shader_parameter("max_iter", iterations)
	material.set_shader_parameter("detail_strength", 0.5)
	_build_mesh(false)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Preview camera (--view=relief): from the highest ground, looking back over
## the terraces toward the Core.
func frame_relief(cam: Camera3D) -> void:
	var hf := heightfield
	var best := 0
	for k in hf.heights.size():
		if hf.heights[k] > hf.heights[best]:
			best = k
	var sp := JuliaHeightfield.sample_spacing(hf.n)
	var half := JuliaHeightfield.SIZE_M * 0.5
	var top := Vector3(-half + (best % hf.n) * sp, 0.0, -half + (best / hf.n) * sp)
	var back := Vector2(top.x, top.z).normalized() * 30.0
	var at := Vector3(top.x + back.x, 0.0, top.z + back.y)
	cam.position = Vector3(at.x, height_at(at.x, at.z) + 22.0, at.z)
	cam.look_at(Vector3(0.0, hf.core_height + 4.0, 0.0))
	cam.fov = 70.0


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
## Development tier and energy (Development.gd): city lights and roads.
func set_development(tier: int, energy: float) -> void:
	if material:
		material.set_shader_parameter("dev_tier", tier)
		material.set_shader_parameter("dev_energy", energy)


func set_activity(glow: float, lit_bands: float) -> void:
	if material:
		material.set_shader_parameter("glow", glow)
		material.set_shader_parameter("lit_bands", lit_bands)


func _step_for_level() -> int:
	var cfg := get_node_or_null("/root/Config")
	return int(cfg.preset().get("mesh_step", 2)) if cfg else 2


func _shadow_for_level() -> bool:
	var cfg := get_node_or_null("/root/Config")
	return bool(cfg.preset().get("shadows", true)) if cfg else true


## Starts computing the ground's mesh arrays (and its shadow proxy's, where the level casts
## sun shadows) on a worker thread; _process adds the mesh when they're done.
func _start_mesh() -> void:
	if _mesh_thread != null:
		return
	_mesh_has_shadow = _shadow_for_level()
	var hf := heightfield
	var step := mesh_step
	var shadow := _mesh_has_shadow
	_mesh_thread = Thread.new()
	_mesh_thread.start(func() -> Array:
		return [grid_arrays(hf, step), grid_arrays(hf, step * 2) if shadow else []])
	set_process(true)


## True once the ground is drawn (its mesh computed and added).
func mesh_ready() -> bool:
	return _mesh_thread == null and _mesh_instance != null


## Waits for the mesh thread and adds the mesh now (non-staged builds, tools).
func finish_mesh() -> void:
	if _mesh_thread != null:
		_collect_mesh()


func _process(_delta: float) -> void:
	if _mesh_thread == null:
		set_process(false)
		return
	if not _mesh_thread.is_alive():
		_collect_mesh()


func _collect_mesh() -> void:
	var res: Array = _mesh_thread.wait_to_finish()
	_mesh_thread = null
	var mesh := _mesh_from(res[0])
	mesh.surface_set_material(0, material)
	var shadow: ArrayMesh = _mesh_from(res[1]) if not (res[1] as Array).is_empty() else null
	_set_meshes(mesh, shadow)
	LoadProfile.mark("ground mesh")


## The level changed: a coarser or finer ground, with or without its shadow proxy.
func _on_config() -> void:
	if not _is_main or heightfield == null:
		return
	if _step_for_level() != mesh_step or _shadow_for_level() != _mesh_has_shadow:
		mesh_step = _step_for_level()
		_start_mesh()  # the old mesh stays until the new one is ready


func _exit_tree() -> void:
	if _mesh_thread != null and _mesh_thread.is_started():
		_mesh_thread.wait_to_finish()
		_mesh_thread = null


func _set_meshes(mesh: ArrayMesh, shadow: ArrayMesh) -> void:
	if _mesh_instance:
		_mesh_instance.queue_free()
	if _shadow_instance:
		_shadow_instance.queue_free()
		_shadow_instance = null
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "GroundMesh"
	_mesh_instance.mesh = mesh
	add_child(_mesh_instance)
	# The ground's shadow caster is a half-resolution copy (perf 2026-11-24): the sun draws a
	# caster once per cascade, and the full ground (0.26 M triangles) was ~1 M of each frame's
	# shadow primitives. Hills and terraces still shade; only the shadow maps see the proxy.
	# Levels without sun shadows (Potato, Low) build none.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if shadow:
		_shadow_instance = MeshInstance3D.new()
		_shadow_instance.name = "GroundShadow"
		_shadow_instance.mesh = shadow
		_shadow_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		# Sunk a little so its coarser facets never poke above the drawn ground (acne blotches).
		_shadow_instance.position.y = -SHADOW_SINK_M
		add_child(_shadow_instance)


func _build_mesh(shadow_proxy: bool = true) -> void:
	var mesh := _grid_mesh(mesh_step)
	mesh.surface_set_material(0, material)
	_set_meshes(mesh, _grid_mesh(mesh_step * 2) if shadow_proxy else null)


func _grid_mesh(step: int) -> ArrayMesh:
	return _mesh_from(grid_arrays(heightfield, step))


static func _mesh_from(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The ground's surface arrays at every `step`-th sample. Pure (thread-safe: reads `hf` only).
static func grid_arrays(hf: JuliaHeightfield, step: int) -> Array:
	var n := hf.n
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
	return arrays


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
	cs.shape = shape  # 1 m spacing (SAMPLES = SIZE_M + 1): no scaling needed, centred on the origin
	_body.add_child(cs)
	add_child(_body)
