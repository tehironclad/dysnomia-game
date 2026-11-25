class_name PubKit
## Building blocks for Sunny's Pub, ported from the cantina prototype
## (branch claude/eager-cannon-ctzojh, scripts/world/pub/pub_kit.gd): cached
## Poly Haven CC0 models, PBR materials from Poly Haven texture sets, and a box
## batcher that merges static geometry into one mesh per material, so the
## lived-in look costs few draw calls.
##
##   var m := PubKit.place(parent, "metal_stool_01", pos, yaw_deg, scale)
##   var mat := PubKit.pbr("brick_wall_02", 2.4)   # world triplanar, 1 repeat / 2.4 m
##   var b := PubKit.Batch.new(); b.box_at(size, pos, mat); b.commit(parent)

const MODEL_DIR := "res://assets/models/polyhaven/%s/%s_1k.gltf"
const TEX_DIR := "res://assets/textures/polyhaven/%s/%s.jpg"

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}


## A Poly Haven model instance; an empty node if the asset is missing (never breaks the build).
static func model(id: String) -> Node3D:
	if not _scenes.has(id):
		var path := MODEL_DIR % [id, id]
		_scenes[id] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[id] == null:
			push_warning("[PubKit] missing model " + path)
	var ps: PackedScene = _scenes[id]
	var n: Node3D = ps.instantiate() if ps else Node3D.new()
	n.name = id
	return n


static func place(parent: Node3D, id: String, pos: Vector3, rot_y_deg: float = 0.0, scl: Variant = 1.0) -> Node3D:
	var n := model(id)
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	n.scale = scl if scl is Vector3 else Vector3.ONE * float(scl)
	parent.add_child(n)
	no_shadows(n)
	return n


## Indoors under one roof: props needn't cast into a shadow pass.
static func no_shadows(n: Node) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A Poly Haven texture set (diff + nor_gl + arm) as a PBR material. World
## triplanar, so neighbouring boxes line up; tile_m is metres per repeat.
static func pbr(tex_id: String, tile_m: float = 1.0, tint: Color = Color.WHITE, rough_mul: float = 1.0) -> StandardMaterial3D:
	var key := "pbr|%s|%.3f|%s|%.2f" % [tex_id, tile_m, tint.to_html(), rough_mul]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var diff := TEX_DIR % [tex_id, "diff"]
	if ResourceLoader.exists(diff):
		var arm: Texture2D = load(TEX_DIR % [tex_id, "arm"])
		m.albedo_texture = load(diff)
		m.normal_enabled = true
		m.normal_texture = load(TEX_DIR % [tex_id, "nor_gl"])
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	else:
		push_warning("[PubKit] missing texture " + diff)
	m.albedo_color = tint
	m.roughness = rough_mul
	m.metallic = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / tile_m
	_mats[key] = m
	return m


static func flat(color: Color, rough: float = 0.6, metal: float = 0.0, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), rough, metal, emission.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


## A glowing tube: strong HDR emission so the environment's glow blooms it.
static func neon(color: Color, energy: float = 4.0) -> StandardMaterial3D:
	var key := "neon|%s|%.2f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func glass(tint: Color = Color(0.75, 0.85, 0.9, 0.18), emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var key := "glass|%s|%s|%.2f" % [tint.to_html(), emission.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.roughness = 0.05
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


## Clear drinking glass: nearly colourless, smooth, with a fresnel rim.
static func drinkware() -> StandardMaterial3D:
	if _mats.has("drinkware"):
		return _mats["drinkware"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.32, 0.38, 0.42, 0.14)
	m.roughness = 0.03
	m.metallic = 0.1
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["drinkware"] = m
	return m


## A framed print (pub_poster.gdshader art: Eris over Dysnomia) with its title
## in the paper strip. Flavour, not data: no numbers on it.
static func poster(parent: Node3D, pos: Vector3, rot_y_deg: float, size: Vector2, title: String, sub: String, seed_value: int, frame_mat: Material) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	parent.add_child(n)
	var fr := BoxMesh.new()
	fr.size = Vector3(size.x + 0.08, size.y + 0.08, 0.03)
	mesh_instance(fr, Vector3(0, 0, 0.015), frame_mat, n)
	var q := QuadMesh.new()
	q.size = size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/pub_poster.gdshader")
	var hue := rng.randf()
	sm.set_shader_parameter("sky_top", Color.from_hsv(hue, 0.6, 0.3))
	sm.set_shader_parameter("sky_low", Color.from_hsv(fmod(hue + 0.12, 1.0), 0.7, 0.95))
	sm.set_shader_parameter("variant", rng.randf())
	mesh_instance(q, Vector3(0, 0, 0.032), sm, n)
	var t := label(title, 40, Color(0.1, 0.06, 0.08), size.x / 260.0 * 0.8, DeepFieldTheme.display_font())
	t.position = Vector3(0, -size.y * 0.32, 0.036)
	n.add_child(t)
	if not sub.is_empty():
		var s := label(sub, 26, Color(0.25, 0.12, 0.1), size.x / 260.0 * 0.8)
		s.position = Vector3(0, -size.y * 0.42, 0.036)
		n.add_child(s)
	return n


static func mesh_instance(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func cyl(r_top: float, r_bot: float, h: float, segs: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func sphere(r: float, segs: int = 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(3, segs / 2)
	return s


## Extruded 3D text, so neon signage can carry an HDR emissive material.
static func text_mesh(text: String, px: float, depth: float = 0.03, font: Font = null) -> TextMesh:
	var t := TextMesh.new()
	t.text = text
	t.font_size = 64
	t.pixel_size = px
	t.depth = depth
	t.curve_step = 1.0
	if font:
		t.font = font
	return t


static func label(text: String, size: int, color: Color, px: float = 0.004, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.font = font if font else DeepFieldTheme.body_font()
	return l


## Collects boxes and meshes per material and commits each material's geometry
## as one MeshInstance3D: trim, beams, rails and shelves in a handful of draw calls.
class Batch:
	var _tools: Dictionary = {}  # Material → SurfaceTool
	var _box_cache: Dictionary = {}

	func box(size: Vector3, xf: Transform3D, mat: Material) -> void:
		var key := "%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
		if not _box_cache.has(key):
			var bm := BoxMesh.new()
			bm.size = size
			_box_cache[key] = bm
		add_mesh(_box_cache[key], xf, mat)

	func box_at(size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
		box(size, Transform3D(Basis.from_euler(rot), pos), mat)

	func add_mesh(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
		if not _tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_tools[mat] = st
		(_tools[mat] as SurfaceTool).append_from(mesh, 0, xf)

	## Everything collected as ONE mesh, a surface per material (a prop drawn
	## many times, e.g. as a MultiMesh).
	func to_mesh() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in _tools:
			var st: SurfaceTool = _tools[mat]
			st.set_material(mat)
			st.commit(mesh)
		_tools.clear()
		return mesh

	func commit(parent: Node3D, name_prefix: String = "Batch") -> void:
		var i := 0
		for mat in _tools:
			var st: SurfaceTool = _tools[mat]
			var mi := MeshInstance3D.new()
			mi.name = "%s%d" % [name_prefix, i]
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			i += 1
		_tools.clear()
