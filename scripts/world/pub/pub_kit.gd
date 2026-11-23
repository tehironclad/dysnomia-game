class_name PubKit
## Shared building blocks for the cantina: cached CC0 models, PBR materials and a
## box batcher that merges static procedural geometry into one mesh per material.
##
##   var m := PubKit.model("metal_stool_01")             # Poly Haven glTF instance (cached scene)
##   var mat := PubKit.pbr("dark_wooden_planks", 0.5)    # PBR (diff+normal+ARM), world triplanar, 1 tile / 0.5 m
##   var b := PubKit.Batch.new(); b.box(size, xform, mat); b.commit(parent)

const MODEL_DIR := "res://assets/models/polyhaven/%s/%s_1k.gltf"
const TEX_DIR := "res://assets/textures/polyhaven/%s/%s.jpg"

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}


static func model(id: String) -> Node3D:
	## Instance a downloaded Poly Haven model. Falls back to an empty node so a missing
	## asset never breaks the build (the caller still positions it).
	if not _scenes.has(id):
		var path := MODEL_DIR % [id, id]
		_scenes[id] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[id] == null:
			push_warning("[PubKit] missing model " + path)
	var ps: PackedScene = _scenes[id]
	var n: Node3D = ps.instantiate() if ps else Node3D.new()
	n.name = id
	return n


static func place(parent: Node3D, id: String, pos: Vector3, rot_y_deg: float = 0.0,
		scl: Variant = 1.0, shadows: bool = false) -> Node3D:
	var n := model(id)
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	n.scale = scl if scl is Vector3 else Vector3.ONE * float(scl)
	parent.add_child(n)
	set_shadows(n, shadows)
	return n


static func set_shadows(n: Node, on: bool, vis_end: float = 0.0) -> void:
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			g.visibility_range_end = vis_end
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func pbr(tex_id: String, tile_m: float = 1.0, tint: Color = Color.WHITE,
		triplanar: bool = true, rough_mul: float = 1.0, metal_mul: float = 1.0) -> BaseMaterial3D:
	## Poly Haven texture set (diff + nor_gl + arm) as a PBR material. Triplanar uses
	## world space so neighbouring boxes line up; tile_m is metres per texture repeat.
	var key := "%s|%.3f|%s|%s|%.2f|%.2f" % [tex_id, tile_m, tint.to_html(), triplanar, rough_mul, metal_mul]
	if _mats.has(key):
		return _mats[key]
	# StandardMaterial3D reading the packed ARM map per channel, so the roughness /
	# metallic multipliers scale the texture channels.
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
	m.metallic = metal_mul
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE / tile_m
	else:
		m.uv1_scale = Vector3(1.0 / tile_m, 1.0 / tile_m, 1.0)
	_mats[key] = m
	return m


static func flat(color: Color, rough: float = 0.6, metal: float = 0.0,
		emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
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


static func neon(color: Color, energy: float = 4.0) -> StandardMaterial3D:
	## Unshaded-looking glowing tube: dark-ish albedo, strong HDR emission so the
	## environment glow blooms it.
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


static func glass(tint: Color = Color(0.75, 0.85, 0.9, 0.18), emission: Color = Color.BLACK,
		energy: float = 0.0) -> StandardMaterial3D:
	var key := "glass|%s|%s|%.2f" % [tint.to_html(), emission.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.roughness = 0.05
	m.metallic = 0.2
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func mesh_instance(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D,
		shadows: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


static func text_mesh(text: String, px: float, depth: float = 0.03) -> TextMesh:
	## Extruded 3D text — used for neon signage so it can carry an HDR emissive material.
	var t := TextMesh.new()
	t.text = text
	t.font_size = 64
	t.pixel_size = px
	t.depth = depth
	t.curve_step = 1.0
	return t


static func label(text: String, size: int, color: Color, px: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return l


static func extrude(profile: PackedVector2Array, z0: float, z1: float, smooth: bool,
		tile_m: float = 1.0) -> ArrayMesh:
	## Sweep a 2D profile (x,y, ordered left→right over the top) along Z. UVs are in
	## metres / tile_m (u along Z, v down the profile) so vertical corrugation runs down the slope.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var seg_n: Array[Vector3] = []
	for i in n - 1:
		var dv := profile[i + 1] - profile[i]
		seg_n.append(Vector3(-dv.y, dv.x, 0.0).normalized())
	var u := [0.0]
	for i in range(1, n):
		u.append(u[i - 1] + profile[i].distance_to(profile[i - 1]))
	for i in n - 1:
		var na: Vector3 = seg_n[i]
		var nb: Vector3 = seg_n[i]
		if smooth:
			if i > 0:
				na = (seg_n[i - 1] + seg_n[i]).normalized()
			if i < n - 2:
				nb = (seg_n[i] + seg_n[i + 1]).normalized()
		var a := profile[i]
		var b := profile[i + 1]
		var ua: float = u[i] / tile_m
		var ub: float = u[i + 1] / tile_m
		var quad := [
			[Vector3(a.x, a.y, z0), na, Vector2(z0 / tile_m, ua)],
			[Vector3(b.x, b.y, z0), nb, Vector2(z0 / tile_m, ub)],
			[Vector3(b.x, b.y, z1), nb, Vector2(z1 / tile_m, ub)],
			[Vector3(a.x, a.y, z1), na, Vector2(z1 / tile_m, ua)],
		]
		for idx in [0, 1, 2, 0, 2, 3]:  # clockwise seen from outside (Godot front face)
			st.set_normal(quad[idx][1])
			st.set_uv(quad[idx][2])
			st.add_vertex(quad[idx][0])
	st.generate_tangents()
	return st.commit()


static func cap(poly: PackedVector2Array, z: float, facing: float, tile_m: float = 1.0) -> ArrayMesh:
	## Flat polygon in the XY plane at depth z (gable / vault end walls). facing = ±1 (normal along Z).
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nrm := Vector3(0, 0, facing)
	for t in range(0, tris.size(), 3):
		var p0 := poly[tris[t]]
		var p1 := poly[tris[t + 1]]
		var p2 := poly[tris[t + 2]]
		var cz := (p1 - p0).cross(p2 - p0)
		# Front faces wind clockwise as seen from the side the normal points to
		var order := [0, 1, 2] if (cz < 0.0) == (facing > 0.0) else [0, 2, 1]
		for k in order:
			var p := poly[tris[t + k]]
			st.set_normal(nrm)
			st.set_uv(Vector2(p.x, -p.y) / tile_m)
			st.add_vertex(Vector3(p.x, p.y, z))
	st.generate_tangents()
	return st.commit()


class Batch:
	## Collects procedural boxes/cylinders per material and commits each material's
	## geometry as one MeshInstance3D — keeps draw calls low for trim, beams, rails.
	var _tools: Dictionary = {}   # Material -> SurfaceTool
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

	func commit(parent: Node3D, shadows: bool, name_prefix: String = "Batch") -> void:
		var i := 0
		for mat in _tools:
			var st: SurfaceTool = _tools[mat]
			var mi := MeshInstance3D.new()
			mi.name = "%s%d" % [name_prefix, i]
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			i += 1
		_tools.clear()
