extends RefCounted
## Shared building kit for the territory structures (Beat Station, Landing Pad, Comm Array).
##
##   const Kit = preload("res://scripts/world/structures/struct_kit.gd")
##   Kit.prop(self, "barrel_03", Vector3(2, 0, 1), 0.4)          # CC0 Poly Haven model
##   Kit.box(self, Vector3(1, 2, 1), Vector3(0, 1, 0), Kit.paint(Color.GRAY))
##   Kit.cable(self, a, b, 0.6, 0.04, Kit.paint(Color(0.05, 0.05, 0.05)))
##
## Everything is static and caches its resources, so all three buildings share the same
## PackedScenes, textures and plain materials (draw-call batching + low memory).
## Models degrade gracefully: if an asset is missing the call returns null and the
## building still builds from primitives.

const MODEL_PATH := "res://assets/models/polyhaven/%s/%s_1k.gltf"
const TEX_PATH := "res://assets/textures/polyhaven/%s/%s.jpg"
const NPC_PATH := "res://scripts/world/npc/ambient_npc.gd"

const SCREEN_SHADER := preload("res://assets/shaders/struct_screen.gdshader")
const HAZARD_SHADER := preload("res://assets/shaders/struct_hazard.gdshader")
const CONDUIT_SHADER := preload("res://assets/shaders/struct_conduit.gdshader")
const POOL_SHADER := preload("res://assets/shaders/struct_glowpool.gdshader")
const BEAM_SHADER := preload("res://assets/shaders/struct_beam.gdshader")
const PAD_SHADER := preload("res://assets/shaders/struct_pad.gdshader")

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}
static var _mesh_parts: Dictionary = {}


# ─── Models ─────────────────────────────────────────────────────────────

static func model(id: String) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := MODEL_PATH % [id, id]
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_scenes[id] = ps
	return ps


static func prop(parent: Node3D, id: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0, shadows: bool = true) -> Node3D:
	## Instance a Poly Haven model. Models are authored in metres with the origin on the floor.
	var ps := model(id)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	if not shadows:
		_set_shadows(n, false)
	return n


static func prop_multi(parent: Node3D, id: String, xforms: Array, shadows: bool = true) -> void:
	## Many copies of one model through MultiMesh — one draw call per model surface.
	if xforms.is_empty():
		return
	var parts := _model_parts(id)
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * (part[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


static func _model_parts(id: String) -> Array:
	## [[Mesh, Transform3D], ...] for every MeshInstance3D in a model (cached).
	if _mesh_parts.has(id):
		return _mesh_parts[id]
	var out: Array = []
	var ps := model(id)
	if ps:
		var root: Node = ps.instantiate()
		_collect_meshes(root, Transform3D.IDENTITY, out, true)
		root.free()
	_mesh_parts[id] = out
	return out


static func _collect_meshes(n: Node, xf: Transform3D, out: Array, is_root: bool) -> void:
	if n is Node3D and not is_root:
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append([(n as MeshInstance3D).mesh, xf])
	for c in n.get_children():
		_collect_meshes(c, xf, out, false)


static func _set_shadows(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadows(c, on)


# ─── Materials ──────────────────────────────────────────────────────────

static func tex(id: String, map: String) -> Texture2D:
	var path := TEX_PATH % [id, map]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func pbr(id: String, uv_scale: float = 0.5, tint: Color = Color.WHITE, world: bool = true, metal: float = -1.0) -> StandardMaterial3D:
	## Poly Haven PBR set (diff / nor_gl / arm) on triplanar UVs, so boxes and cylinders of
	## any size tile at real-world scale. world=true keeps tiling continuous across pieces.
	var key := "pbr|%s|%.3f|%s|%s|%.2f" % [id, uv_scale, tint.to_html(), world, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var d := tex(id, "diff")
	if d:
		m.albedo_texture = d
	var n := tex(id, "nor_gl")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	var arm := tex(id, "arm")
	if arm:
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.4
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = 1.0
		if metal >= 0.0:
			m.metallic = metal
		else:
			m.metallic_texture = arm
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			m.metallic = 1.0
	else:
		m.roughness = 0.85
		m.metallic = maxf(metal, 0.0)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func painted(id: String, c: Color, uv_scale: float = 0.5, world: bool = false) -> StandardMaterial3D:
	## Flat paint colour over a Poly Haven surface's relief (normal + AO/roughness only),
	## e.g. an orange shipping container from the green container_side scan.
	var key := "painted|%s|%s|%.3f|%s" % [id, c.to_html(), uv_scale, world]
	if _mats.has(key):
		return _mats[key]
	var m := pbr(id, uv_scale, c, world, 0.35).duplicate() as StandardMaterial3D
	m.albedo_texture = null
	m.albedo_color = c
	_mats[key] = m
	return m


static func paint(c: Color, rough: float = 0.6, metal: float = 0.3) -> StandardMaterial3D:
	var key := "paint|%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func glow(c: Color, energy: float = 2.0, shared: bool = true) -> StandardMaterial3D:
	## Emissive material. shared=false returns a fresh one for per-object animation.
	var key := "glow|%s|%.2f" % [c.to_html(), energy]
	if shared and _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.6)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	if shared:
		_mats[key] = m
	return m


static func glass(c: Color = Color(0.55, 0.7, 0.8, 0.25)) -> StandardMaterial3D:
	var key := "glass|%s" % c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.2
	m.metallic_specular = 0.9
	_mats[key] = m
	return m


static func hazard(scale: float = 3.0, a: Color = Color(0.95, 0.68, 0.05), b: Color = Color(0.04, 0.04, 0.04)) -> ShaderMaterial:
	var key := "hazard|%.2f|%s|%s" % [scale, a.to_html(), b.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = HAZARD_SHADER
	m.set_shader_parameter("stripe_freq", scale)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	_mats[key] = m
	return m


static func screen(mode: int, accent: Color, seed_value: int = 0) -> ShaderMaterial:
	## Animated display: 0 = bar meters, 1 = oscilloscope, 2 = radar, 3 = data log, 4 = vertical VU.
	## Not cached: each screen is driven by its own values.
	var m := ShaderMaterial.new()
	m.shader = SCREEN_SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("accent", accent)
	m.set_shader_parameter("seed", float(seed_value % 997))
	return m


static func conduit(c: Color, speed: float = 1.0, energy: float = 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CONDUIT_SHADER
	m.set_shader_parameter("flow_color", c)
	m.set_shader_parameter("flow_speed", speed)
	m.set_shader_parameter("energy", energy)
	return m


static func ground_slab(mode: int, half_size: Vector2, accent: Color, seed_value: int = 0) -> ShaderMaterial:
	## Painted concrete surface (struct_pad.gdshader): 0 landing pad, 1 apron, 2 plaza.
	var m := ShaderMaterial.new()
	m.shader = PAD_SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("half_size", half_size)
	m.set_shader_parameter("accent", accent)
	m.set_shader_parameter("seed", float(seed_value % 977))
	m.set_shader_parameter("concrete_albedo", tex("brushed_concrete", "diff"))
	m.set_shader_parameter("concrete_normal", tex("brushed_concrete", "nor_gl"))
	m.set_shader_parameter("concrete_arm", tex("brushed_concrete", "arm"))
	return m


static func pool_material() -> ShaderMaterial:
	if _mats.has("pool"):
		return _mats["pool"]
	var m := ShaderMaterial.new()
	m.shader = POOL_SHADER
	_mats["pool"] = m
	return m


static func beam_material() -> ShaderMaterial:
	if _mats.has("beam"):
		return _mats["beam"]
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	_mats["beam"] = m
	return m


# ─── Primitives ─────────────────────────────────────────────────────────

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _inst(parent, bm, pos, mat, rot, shadows)


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, segs: int = 16, rot: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return _inst(parent, cm, pos, mat, rot, shadows)


static func ball(parent: Node3D, r: float, pos: Vector3, mat: Material, segs: int = 12) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(segs / 2, 4)
	return _inst(parent, sm, pos, mat, Vector3.ZERO, false)


static func ring(parent: Node3D, r: float, tube: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, segs: int = 32) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r - tube
	tm.outer_radius = r + tube
	tm.ring_segments = 8
	tm.rings = segs
	return _inst(parent, tm, pos, mat, rot, false)


static func quad(parent: Node3D, size: Vector2, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = size
	return _inst(parent, qm, pos, mat, rot, false)


static func beam(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, segs: int = 8, shadows: bool = true) -> MeshInstance3D:
	## Cylinder strut from a to b.
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = segs
	cm.rings = 1
	var mi := _inst(parent, cm, (a + b) * 0.5, mat, Vector3.ZERO, shadows)
	mi.basis = basis_from_y(b - a)
	return mi


static func beam_xform(a: Vector3, b: Vector3, r: float) -> Transform3D:
	## Transform that maps a unit cylinder (height 1, radius 1) onto a strut a→b of radius r.
	var bs := basis_from_y(b - a)
	bs = bs * Basis.from_scale(Vector3(r, a.distance_to(b), r))
	return Transform3D(bs, (a + b) * 0.5)


static func basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _inst(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func multi(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material, shadows: bool = true) -> MultiMeshInstance3D:
	## MultiMesh of a primitive (unit-sized meshes + scaled transforms work best).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


static func unit_cylinder(segs: int = 8) -> CylinderMesh:
	var key := "ucyl%d" % segs
	if _mats.has(key):
		return _mats[key]
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = segs
	cm.rings = 1
	_mats[key] = cm
	return cm


static func unit_box() -> BoxMesh:
	if _mats.has("ubox"):
		return _mats["ubox"]
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	_mats["ubox"] = bm
	return bm


# ─── Static batching ────────────────────────────────────────────────────

static func merge_static(root: Node3D, keep: Array = []) -> int:
	## Collapse every static primitive MeshInstance3D under `root` into one mesh per
	## (material, shadow) pair — hundreds of boxes and struts become a handful of draw calls.
	## Skipped: nodes in `keep` (and their subtrees: anything animated), imported models,
	## meshes driven by per-instance shader uniforms (light pools, beams). Returns meshes removed.
	var groups: Dictionary = {}
	var removed := 0
	_gather_static(root, root, Transform3D.IDENTITY, keep, groups)
	for key in groups:
		var g: Dictionary = groups[key]
		if (g.items as Array).size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for it in g.items:
			var mesh: Mesh = it[0]
			for sidx in mesh.get_surface_count():
				st.append_from(mesh, sidx, it[1])
		var mi := MeshInstance3D.new()
		mi.name = "Batched"
		mi.mesh = st.commit()
		mi.material_override = g.mat
		mi.cast_shadow = g.shadow
		root.add_child(mi)
		for n in g.nodes:
			n.get_parent().remove_child(n)
			n.free()
			removed += 1
	return removed


static func _gather_static(n: Node, root: Node3D, xf: Transform3D, keep: Array, groups: Dictionary) -> void:
	if n != root:
		if keep.has(n):
			return
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n.scene_file_path != "" or n.get_script() != null:
			return  # Imported model or scripted node (NPCs etc.)
	if n is MeshInstance3D and n != root:
		var mi := n as MeshInstance3D
		var mat := mi.material_override
		var ok := mi.mesh is PrimitiveMesh or (mi.mesh is ArrayMesh and mi.get_child_count() == 0)
		if mat == pool_material() or mat == beam_material():
			ok = false
		if ok and mi.get_child_count() == 0 and mat != null:
			var key := "%d|%d" % [mat.get_instance_id(), mi.cast_shadow]
			if not groups.has(key):
				groups[key] = {"mat": mat, "shadow": mi.cast_shadow, "items": [], "nodes": []}
			groups[key].items.append([mi.mesh, xf])
			groups[key].nodes.append(mi)
			return
	for c in n.get_children():
		_gather_static(c, root, xf, keep, groups)


# ─── Cables & tubes ─────────────────────────────────────────────────────

static func cable(parent: Node3D, a: Vector3, b: Vector3, sag: float, r: float, mat: Material, segs: int = 14) -> MeshInstance3D:
	## Sagging cable (parabolic catenary approximation) from a to b. UV.y runs in metres
	## along the length so the conduit shader can flow pulses down it.
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / float(segs)
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return tube(parent, pts, r, mat)


static func tube(parent: Node3D, pts: Array[Vector3], r: float, mat: Material, sides: int = 6) -> MeshInstance3D:
	## Tube along a polyline.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var fwd: Vector3
		if i == 0:
			fwd = pts[1] - pts[0]
		elif i == n - 1:
			fwd = pts[n - 1] - pts[n - 2]
		else:
			fwd = pts[i + 1] - pts[i - 1]
		if i > 0:
			dist += p.distance_to(pts[i - 1])
		var bs := basis_from_y(fwd)
		for s in sides + 1:
			var ang := float(s) / float(sides) * TAU
			var nrm := bs.x * cos(ang) + bs.z * sin(ang)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(s) / float(sides), dist))
			st.add_vertex(p + nrm * r)
	for i in n - 1:
		for s in sides:
			var i0 := i * (sides + 1) + s
			var i1 := i0 + sides + 1
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i1)
			st.add_index(i0 + 1)
			st.add_index(i1 + 1)
			st.add_index(i1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func dish_mesh(radius: float, depth: float, radial: int = 24, rings_n: int = 8) -> ArrayMesh:
	## Concave parabolic reflector, open side +Y, rim at y=0, double-sided via two surfaces' worth of tris.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in rings_n + 1:
		var v := float(ri) / float(rings_n)
		var rr := v * radius
		var y := -depth * (1.0 - v * v)
		for s in radial + 1:
			var u := float(s) / float(radial)
			var ang := u * TAU
			var slope := 2.0 * depth * v / radius
			st.set_normal(Vector3(-cos(ang) * slope, 1.0, -sin(ang) * slope).normalized())
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(cos(ang) * rr, y, sin(ang) * rr))
	for ri in rings_n:
		for s in radial:
			var c := ri * (radial + 1) + s
			var nx := c + radial + 1
			st.add_index(c)
			st.add_index(c + 1)
			st.add_index(nx)
			st.add_index(c + 1)
			st.add_index(nx + 1)
			st.add_index(nx)
	return st.commit()


# ─── Lighting helpers ───────────────────────────────────────────────────

static func night_factor() -> float:
	## 0 at noon .. 1 at night, from GameManager.time_of_day (0.5 = noon, 0/1 = midnight).
	var tod: float = 0.5
	var gm = Engine.get_main_loop().root.get_node_or_null("GameManager") if Engine.get_main_loop() is SceneTree else null
	if gm:
		tod = float(gm.time_of_day)
	var sun_h := sin((tod - 0.25) * TAU)
	return clampf(0.45 - sun_h * 2.2, 0.08, 1.0)


static func update_night() -> float:
	## Push the night factor into the shared pool/beam materials. Cheap; call every frame.
	var nf := night_factor()
	pool_material().set_shader_parameter("night", nf)
	beam_material().set_shader_parameter("night", nf)
	return nf


static func omni(parent: Node3D, pos: Vector3, c: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_specular = 0.6
	parent.add_child(l)
	return l


static func spot(parent: Node3D, pos: Vector3, target: Vector3, c: Color, energy: float, rng: float, angle: float = 40.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_attenuation = 0.8
	l.shadow_enabled = false
	parent.add_child(l)
	l.position = pos
	l.basis = Basis.looking_at(target - pos, Vector3.UP if absf((target - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	return l


static func light_pool(parent: Node3D, pos: Vector3, radius: float, c: Color, strength: float = 1.0) -> MeshInstance3D:
	## Fake light pool on the ground (additive radial gradient) — reads like a lit floor at
	## night without paying for a real light. Fades out in daylight via the shader.
	var mi := quad(parent, Vector2(radius * 2.0, radius * 2.0), pos, pool_material(), Vector3(-PI * 0.5, 0, 0))
	mi.set_instance_shader_parameter("tint", Color(c.r, c.g, c.b, strength))
	return mi


static func light_cone(parent: Node3D, pos: Vector3, dir: Vector3, length: float, r_top: float, r_bot: float, c: Color, strength: float = 1.0) -> MeshInstance3D:
	## Soft volumetric-looking beam (additive, fresnel-faded cone).
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = length
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = beam_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# Cylinder +Y is the narrow (top) end at the source
	var d := dir.normalized()
	mi.basis = basis_from_y(-d)
	mi.position = pos + d * length * 0.5
	mi.set_instance_shader_parameter("tint", Color(c.r, c.g, c.b, strength))
	return mi


# ─── Composite fixtures ─────────────────────────────────────────────────

static func truss_xforms(a: Vector3, b: Vector3, w: float, bay: float, out: Array, r: float = 0.03) -> void:
	## Square lattice truss from a to b (4 chords + zig-zag lacing), appended as unit-cylinder
	## transforms to `out` for one MultiMesh.
	var axis := b - a
	var bs := basis_from_y(axis)
	var len_ := axis.length()
	var h := w * 0.5
	var corners := [bs.x * h + bs.z * h, bs.x * -h + bs.z * h, bs.x * -h + bs.z * -h, bs.x * h + bs.z * -h]
	for c: Vector3 in corners:
		out.append(beam_xform(a + c, b + c, r))
	var n := maxi(1, int(len_ / bay))
	for i in n:
		var p0 := a + axis * (float(i) / float(n))
		var p1 := a + axis * (float(i + 1) / float(n))
		for k in 4:
			var c0: Vector3 = corners[k]
			var c1: Vector3 = corners[(k + 1) % 4]
			out.append(beam_xform(p0 + c0, p1 + c1 if i % 2 == 0 else p1 + c0, r * 0.55))
			out.append(beam_xform(p0 + c0, p0 + c1, r * 0.55))


static func flood_mast(parent: Node3D, pos: Vector3, height: float, aim: Vector3, c: Color, heads: int = 3, real_light: bool = true, energy: float = 3.0) -> Node3D:
	## Lighting mast: ballast block, lattice mast, lamp bar with floodlight heads aimed at `aim`
	## (parent space). Heads glow, cast soft light shafts, and one shadowless spot does the
	## actual lighting.
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	box(root, Vector3(0.9, 0.5, 0.9), Vector3(0, 0.1, 0), pbr("brushed_concrete", 0.8, Color(0.62, 0.62, 0.6)))
	var xs: Array = []
	truss_xforms(Vector3(0, 0.35, 0), Vector3(0, height, 0), 0.32, 0.45, xs, 0.028)
	multi(root, unit_cylinder(6), xs, paint(Color(0.62, 0.63, 0.65), 0.35, 0.9))
	var local_aim := aim - pos
	var yaw := atan2(local_aim.x, local_aim.z)
	var bar := Node3D.new()
	bar.position = Vector3(0, height + 0.2, 0)
	bar.rotation.y = yaw
	root.add_child(bar)
	var dark := paint(Color(0.08, 0.08, 0.09), 0.5, 0.7)
	box(bar, Vector3(0.12, 0.12, 0.12) + Vector3(float(heads) * 0.55, 0, 0), Vector3(0, -0.05, 0), dark, Vector3.ZERO, false)
	var lens := glow(c, 6.0)
	var dir := (aim - (pos + Vector3(0, height + 0.2, 0))).normalized()
	var pitch := asin(clampf(-dir.y, -1.0, 1.0))
	for i in heads:
		var x := (float(i) - float(heads - 1) * 0.5) * 0.55
		var head := Node3D.new()
		head.position = Vector3(x, 0.15, 0)
		head.rotation.x = pitch
		bar.add_child(head)
		box(head, Vector3(0.48, 0.34, 0.22), Vector3.ZERO, dark)
		box(head, Vector3(0.42, 0.28, 0.02), Vector3(0, 0, 0.115), lens, Vector3.ZERO, false)
		light_cone(head, Vector3(0, 0, 0.13), Vector3(0, 0, 1), minf(height * 2.2, 14.0), 0.2, 1.6, c, 0.7)
	if real_light:
		spot(root, Vector3(0, height + 0.1, 0), aim - pos, c, energy, height * 3.0, 38.0)
	return root


static func cabin(parent: Node3D, pos: Vector3, rot_y: float, size: Vector3, title: String, window_color: Color = Color(1.0, 0.85, 0.6), lit: bool = true) -> Node3D:
	## Converted shipping-container cabin: corrugated walls, door, lit window, roof AC unit.
	## Front (door + window) faces local +Z.
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	box(root, Vector3(size.x + 0.3, 0.3, size.z + 0.3), Vector3(0, 0.05, 0), pbr("brushed_concrete", 0.7, Color(0.6, 0.6, 0.58)))
	var wall := pbr("container_side", 0.45, Color(0.72, 0.74, 0.78), false)
	box(root, size, Vector3(0, 0.2 + size.y * 0.5, 0), wall)
	var trim := paint(Color(0.12, 0.12, 0.13), 0.5, 0.7)
	# Corner posts and roof rail
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			box(root, Vector3(0.14, size.y, 0.14), Vector3(sx * size.x * 0.5, 0.2 + size.y * 0.5, sz * size.z * 0.5), trim, Vector3.ZERO, false)
	box(root, Vector3(size.x + 0.1, 0.12, size.z + 0.1), Vector3(0, 0.2 + size.y + 0.04, 0), trim)
	var fz := size.z * 0.5 + 0.01
	# Door
	box(root, Vector3(0.95, 2.05, 0.05), Vector3(-size.x * 0.5 + 0.8, 0.2 + 1.03, fz), paint(Color(0.18, 0.2, 0.22), 0.5, 0.6), Vector3.ZERO, false)
	box(root, Vector3(0.05, 0.25, 0.06), Vector3(-size.x * 0.5 + 1.15, 0.2 + 1.0, fz + 0.03), paint(Color(0.7, 0.7, 0.7), 0.3, 1.0), Vector3.ZERO, false)
	# Window with lit interior
	var wx := size.x * 0.5 - 1.2
	box(root, Vector3(1.6, 0.95, 0.06), Vector3(wx, 0.2 + 1.45, fz), trim, Vector3.ZERO, false)
	var win := glow(window_color, 1.6 if lit else 0.05)
	box(root, Vector3(1.45, 0.82, 0.02), Vector3(wx, 0.2 + 1.45, fz + 0.03), win, Vector3.ZERO, false)
	# Blind slats
	for k in 4:
		box(root, Vector3(1.45, 0.025, 0.01), Vector3(wx, 0.2 + 1.2 + float(k) * 0.2, fz + 0.045), trim, Vector3.ZERO, false)
	# Door lamp
	box(root, Vector3(0.25, 0.12, 0.18), Vector3(-size.x * 0.5 + 0.8, 0.2 + 2.3, fz + 0.09), trim, Vector3.ZERO, false)
	box(root, Vector3(0.2, 0.03, 0.14), Vector3(-size.x * 0.5 + 0.8, 0.2 + 2.235, fz + 0.09), glow(Color(1.0, 0.85, 0.6), 4.0), Vector3.ZERO, false)
	light_pool(root, Vector3(-size.x * 0.5 + 0.8, 0.22, fz + 1.2), 2.2, Color(1.0, 0.8, 0.55), 1.0)
	light_pool(root, Vector3(wx, 0.22, fz + 1.3), 2.0, window_color, 0.7 if lit else 0.0)
	# Roof AC unit + vent stack
	var ac := box(root, Vector3(1.0, 0.5, 0.8), Vector3(size.x * 0.25, 0.2 + size.y + 0.35, 0), paint(Color(0.75, 0.76, 0.74), 0.5, 0.4))
	ac.name = "RoofAC"
	cyl(root, 0.3, 0.3, 0.06, Vector3(size.x * 0.25, 0.2 + size.y + 0.62, 0), paint(Color(0.1, 0.1, 0.1), 0.6, 0.4), 16)
	cyl(root, 0.07, 0.07, 0.8, Vector3(-size.x * 0.3, 0.2 + size.y + 0.4, -size.z * 0.25), trim, 8)
	# Step
	box(root, Vector3(1.2, 0.18, 0.6), Vector3(-size.x * 0.5 + 0.8, 0.09, fz + 0.3), pbr("metal_plate", 0.6, Color(0.5, 0.5, 0.52)))
	if title != "":
		var plate := sign_board(root, title, Vector3(0.2, 0.2 + size.y - 0.35, fz + 0.02), 0.0, Vector2(1.6, 0.34), Color(0.06, 0.07, 0.08), Color(0.95, 0.95, 0.95), 44, 0.6)
		plate.name = "TitlePlate"
	return root


# ─── Signage ────────────────────────────────────────────────────────────

static func label(parent: Node3D, text: String, pos: Vector3, size: int, c: Color, rot_y: float = 0.0, emissive: float = 0.0, outline: int = 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.position = pos
	l.rotation.y = rot_y
	l.modulate = Color(c.r * (1.0 + emissive), c.g * (1.0 + emissive), c.b * (1.0 + emissive), c.a)
	l.outline_size = outline
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.shaded = emissive <= 0.0
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	parent.add_child(l)
	return l


static func sign_board(parent: Node3D, text: String, pos: Vector3, rot_y: float, size: Vector2, bg: Color, fg: Color, font: int = 48, emissive: float = 0.0) -> Node3D:
	## Flat plate with printed text on its front (+Z local) face.
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	box(root, Vector3(size.x, size.y, 0.03), Vector3.ZERO, paint(bg, 0.55, 0.2), Vector3.ZERO, false)
	label(root, text, Vector3(0, 0, 0.02), font, fg, 0.0, emissive)
	return root


# ─── NPCs ───────────────────────────────────────────────────────────────

static func npc(parent: Node3D, seed_value: int, points: Array, facing: Vector3 = Vector3.FORWARD, height_fn: Callable = Callable()) -> Node3D:
	## AmbientNPC if that system is present in this build; null otherwise.
	if not ResourceLoader.exists(NPC_PATH):
		return null
	var scr: Script = load(NPC_PATH)
	if scr == null or not scr.can_instantiate():
		return null
	var n: Node3D = scr.new()
	parent.add_child(n)
	if n.has_method("setup"):
		n.setup(seed_value, points, facing, height_fn)
	if points.size() < 2 and facing.length() > 0.01:
		# Walkers steer with node -Z forward; give standing locals the same convention so
		# `facing` is the direction they look.
		n.rotation.y = atan2(-facing.x, -facing.z)
	return n
