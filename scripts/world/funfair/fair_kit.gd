class_name FairKit
extends RefCounted
## Shared builders and materials for the Affection Fair.
##
## Everything here is cached so the whole fair (four rides + midway) shares a handful of
## materials and meshes. Repeated small things (bulbs, struts, wires, bunting, balloons,
## light pools) are collected in a FairKit.Batch and flushed as one MultiMesh each.
##
## Night: Funfair calls FairKit.apply_night(n) every frame (n = 0 noon … 1 midnight); the
## shared glow materials and every light tagged with meta "base_energy" follow it.

const TEX := "res://assets/textures/polyhaven/%s/%s.jpg"
const MODEL := "res://assets/models/polyhaven/%s/%s_1k.gltf"

## Carnival palette — saturated but not candy: warm bulbs, cyan, magenta, gold.
const BULB_WARM := Color(1.0, 0.72, 0.38)
## Dysnomia accents: the cool neon / crystal colours used across the territory.
const NEON_CYAN := Color(0.3, 0.9, 1.0)
const NEON_VIOLET := Color(0.62, 0.42, 1.0)
const CRYSTAL_COLORS := [Color(0.3, 0.85, 1.0), Color(0.62, 0.45, 1.0), Color(0.35, 1.0, 0.75), Color(1.0, 0.4, 0.8)]
const PALETTE := [
	Color(1.0, 0.28, 0.42), Color(1.0, 0.70, 0.22), Color(0.22, 0.82, 1.0),
	Color(0.62, 0.40, 1.0), Color(0.36, 1.0, 0.60), Color(1.0, 0.48, 0.16),
]
const AWNING_PAIRS := [
	[Color(0.78, 0.08, 0.12), Color(0.95, 0.92, 0.86)],
	[Color(0.06, 0.32, 0.62), Color(0.95, 0.92, 0.86)],
	[Color(0.95, 0.62, 0.08), Color(0.42, 0.10, 0.38)],
	[Color(0.10, 0.48, 0.36), Color(0.96, 0.88, 0.62)],
	[Color(0.45, 0.12, 0.55), Color(0.98, 0.78, 0.25)],
	[Color(0.85, 0.30, 0.10), Color(0.15, 0.14, 0.18)],
]

static var _cache: Dictionary = {}
static var night: float = 1.0


# ─── Materials ──────────────────────────────────────────────────────────

static func pbr(id: String, tint: Color = Color.WHITE, uv_scale: float = 1.0, metal_boost: float = 0.0) -> ORMMaterial3D:
	## Poly Haven texture set as a triplanar (object-space metres) ORM material.
	var key := "pbr:%s:%s:%s:%s" % [id, tint.to_html(), uv_scale, metal_boost]
	if _cache.has(key):
		return _cache[key]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(TEX % [id, "diff"])
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX % [id, "nor_gl"])
	m.normal_scale = 1.0
	m.orm_texture = load(TEX % [id, "arm"])
	m.metallic = 1.0 if metal_boost > 0.0 else 0.0
	m.metallic_specular = 0.5
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


static func paint(c: Color, rough: float = 0.45, metal: float = 0.25, clearcoat: float = 0.0) -> StandardMaterial3D:
	var key := "paint:%s:%s:%s:%s" % [c.to_html(), rough, metal, clearcoat]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.15
	_cache[key] = m
	return m


static func glow(c: Color, energy: float = 3.0, day_energy: float = -1.0) -> StandardMaterial3D:
	## Self-lit material (neon tubes, sign faces, lamp lenses). Follows apply_night().
	var key := "glow:%s:%s:%s" % [c.to_html(), energy, day_energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.6
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.set_meta("night_energy", energy)
	m.set_meta("day_energy", energy * 0.35 if day_energy < 0.0 else day_energy)
	_cache[key] = m
	_glow_list().append(m)
	return m


static func glass(tint: Color = Color(0.75, 0.88, 1.0, 0.16)) -> StandardMaterial3D:
	var key := "glass:%s" % tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.roughness = 0.04
	m.metallic = 0.1
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


static func shader_mat(shader_name: String, key_extra: String = "") -> ShaderMaterial:
	var key := "shader:%s:%s" % [shader_name, key_extra]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/%s.gdshader" % shader_name)
	_cache[key] = m
	return m


static func bulb_mat() -> ShaderMaterial:
	return shader_mat("fair_bulb")


static func pool_mat() -> ShaderMaterial:
	return shader_mat("fair_pool")


static func _glow_list() -> Array:
	if not _cache.has("_glows"):
		_cache["_glows"] = []
	return _cache["_glows"]


static func apply_night(n: float) -> void:
	## n: 0 = full day, 1 = full night. Drives every shared emissive material.
	night = n
	for m in _glow_list():
		var mm: StandardMaterial3D = m
		mm.emission_energy_multiplier = lerpf(mm.get_meta("day_energy"), mm.get_meta("night_energy"), n)
	bulb_mat().set_shader_parameter("energy", lerpf(1.6, 3.2, n))
	pool_mat().set_shader_parameter("energy", n * 0.9)
	var aw := shader_mat("fair_awning")
	aw.set_shader_parameter("night", n)
	shader_mat("fair_firework").set_shader_parameter("energy", n * 3.0)
	shader_mat("fair_beam").set_shader_parameter("energy", n * 0.2)


# ─── Meshes ─────────────────────────────────────────────────────────────

static func cached_mesh(key: String, ctor: Callable) -> Mesh:
	if not _cache.has("mesh:" + key):
		_cache["mesh:" + key] = ctor.call()
	return _cache["mesh:" + key]


static func box_mesh(size: Vector3) -> Mesh:
	return cached_mesh("box:%s" % size, func() -> Mesh:
		var b := BoxMesh.new()
		b.size = size
		return b)


static func cyl_mesh(r_top: float, r_bot: float, h: float, sides: int = 20) -> Mesh:
	return cached_mesh("cyl:%s:%s:%s:%d" % [r_top, r_bot, h, sides], func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bot
		c.height = h
		c.radial_segments = sides
		c.rings = 1
		return c)


static func sphere_mesh(r: float, segs: int = 16) -> Mesh:
	return cached_mesh("sph:%s:%d" % [r, segs], func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = maxi(4, segs / 2)
		return s)


static func torus_mesh(inner: float, outer: float, rings: int = 48, ring_segs: int = 8) -> Mesh:
	return cached_mesh("tor:%s:%s:%d" % [inner, outer, rings], func() -> Mesh:
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = rings
		t.ring_segments = ring_segs
		return t)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
	## Emit one triangle facing `n` (Godot front faces are clockwise).
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b; b = c; c = t
		var tu := ub; ub = uc; uc = tu
		var tn := nb; nb = nc; nc = tn
	st.set_normal(na if na != Vector3.ZERO else n); st.set_uv(ua); st.add_vertex(a)
	st.set_normal(nb if nb != Vector3.ZERO else n); st.set_uv(ub); st.add_vertex(b)
	st.set_normal(nc if nc != Vector3.ZERO else n); st.set_uv(uc); st.add_vertex(c)


static func lathe(profile: PackedVector2Array, segments: int = 32) -> ArrayMesh:
	## Revolve a (radius, y) profile around +Y. UV.x = angle 0..1, UV.y = profile arc 0..1
	## from the first point. Smooth around, faceted along the profile (crisp seams).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var arc := PackedFloat32Array([0.0])
	for i in range(1, n):
		arc.append(arc[i - 1] + profile[i].distance_to(profile[i - 1]))
	var total := maxf(arc[n - 1], 0.0001)
	for s in segments:
		var a0 := TAU * float(s) / float(segments)
		var a1 := TAU * float(s + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for i in n - 1:
			var p0 := profile[i]
			var p1 := profile[i + 1]
			var t := p1 - p0
			if t.length() < 0.00001:
				continue
			var n2 := Vector2(t.y, -t.x).normalized()
			# Orientation: outward when the profile climbs; flip for descending profiles
			var v00 := d0 * p0.x + Vector3.UP * p0.y
			var v10 := d1 * p0.x + Vector3.UP * p0.y
			var v01 := d0 * p1.x + Vector3.UP * p1.y
			var v11 := d1 * p1.x + Vector3.UP * p1.y
			var nn0 := (d0 * n2.x + Vector3.UP * n2.y).normalized()
			var nn1 := (d1 * n2.x + Vector3.UP * n2.y).normalized()
			var mid := ((d0 + d1) * 0.5 * n2.x + Vector3.UP * n2.y).normalized()
			var u0 := float(s) / segments
			var u1 := float(s + 1) / segments
			var w0 := arc[i] / total
			var w1 := arc[i + 1] / total
			if p0.x > 0.0001:
				_tri(st, v00, v10, v01, mid, Vector2(u0, w0), Vector2(u1, w0), Vector2(u0, w1), nn0, nn1, nn0)
			if p1.x > 0.0001:
				_tri(st, v10, v11, v01, mid, Vector2(u1, w0), Vector2(u1, w1), Vector2(u0, w1), nn1, nn1, nn0)
	st.generate_tangents()
	return st.commit()


static func extrude(poly: PackedVector2Array, depth: float, uv_scale: float = 1.0) -> ArrayMesh:
	## Polygon in XY (any winding), extruded ±depth/2 along Z. UVs are metres * uv_scale.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	var hz := depth * 0.5
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]; var b := poly[idx[k + 1]]; var c := poly[idx[k + 2]]
		for side in [1.0, -1.0]:
			var z: float = hz * side
			_tri(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3(0, 0, side),
				a * uv_scale, b * uv_scale, c * uv_scale)
	var m := poly.size()
	var ctr := Vector2.ZERO
	for p in poly:
		ctr += p
	ctr /= float(m)
	for i in m:
		var p := poly[i]
		var q := poly[(i + 1) % m]
		var e := q - p
		var nrm := Vector3(e.y, -e.x, 0).normalized()
		if Vector2(nrm.x, nrm.y).dot((p + q) * 0.5 - ctr) < 0.0:
			nrm = -nrm
		var l := e.length() * uv_scale
		_tri(st, Vector3(p.x, p.y, hz), Vector3(q.x, q.y, hz), Vector3(p.x, p.y, -hz), nrm,
			Vector2(0, 0), Vector2(l, 0), Vector2(0, depth * uv_scale))
		_tri(st, Vector3(q.x, q.y, hz), Vector3(q.x, q.y, -hz), Vector3(p.x, p.y, -hz), nrm,
			Vector2(l, 0), Vector2(l, depth * uv_scale), Vector2(0, depth * uv_scale))
	st.generate_tangents()
	return st.commit()


# ─── Node helpers ───────────────────────────────────────────────────────

static func mesh(parent: Node, m: Mesh, pos: Vector3, mat: Material = null, rot: Vector3 = Vector3.ZERO,
		shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	if mat:
		mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return mesh(parent, box_mesh(size), pos, mat, rot)


static func cyl(parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, sides: int = 20) -> MeshInstance3D:
	return mesh(parent, cyl_mesh(r_top, r_bot, h, sides), pos, mat)


static func beam(parent: Node, a: Vector3, b: Vector3, r: float, mat: Material, sides: int = 8) -> MeshInstance3D:
	## Round bar from a to b (parent-local).
	var mi := MeshInstance3D.new()
	mi.mesh = cyl_mesh(1.0, 1.0, 1.0, sides)
	mi.material_override = mat
	mi.transform = strut_xform(a, b, r)
	parent.add_child(mi)
	return mi


static func strut_xform(a: Vector3, b: Vector3, r: float) -> Transform3D:
	## Transform that maps a unit cylinder (r=1, h=1, centred) onto the segment a→b.
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return Transform3D(Basis.from_scale(Vector3(r, 0.001, r)), a)
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * r, y * l, z * r), (a + b) * 0.5)


static func solid_box(parent: Node, size: Vector3, pos: Vector3, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = pos
	body.rotation.y = rot_y
	parent.add_child(body)
	return body


static func solid_cyl(parent: Node, r: float, h: float, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(cs)
	body.position = pos
	parent.add_child(body)
	return body


static func model(parent: Node, id: String, pos: Vector3, rot_y: float = 0.0, scl: float = 1.0) -> Node3D:
	## Instance a Poly Haven glTF (real-world metres, Y up, origin at the base).
	var key := "scene:" + id
	if not _cache.has(key):
		_cache[key] = load(MODEL % [id, id])
	var ps: PackedScene = _cache[key]
	if ps == null:
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	return n


static func model_mesh(id: String) -> Array:
	## [Mesh, Transform3D] of a single-mesh glTF, for MultiMesh use.
	var key := "mm:" + id
	if _cache.has(key):
		return _cache[key]
	var ps: PackedScene = load(MODEL % [id, id])
	var n: Node3D = ps.instantiate()
	var out := [null, Transform3D.IDENTITY]
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		if node is Node3D and node != n:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D:
			out = [(node as MeshInstance3D).mesh, xf]
			break
		for c in node.get_children():
			stack.append([c, xf])
	n.free()
	_cache[key] = out
	return out


static func omni(parent: Node, pos: Vector3, c: Color, energy: float, rng: float, day_scale: float = 0.25) -> OmniLight3D:
	## Shadowless point light that dims by day (see Funfair._process).
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.light_specular = 0.6
	l.set_meta("base_energy", energy)
	l.set_meta("day_scale", day_scale)
	l.add_to_group("fair_light")
	parent.add_child(l)
	return l


static func spot(parent: Node, pos: Vector3, target: Vector3, c: Color, energy: float, rng: float, angle: float,
		day_scale: float = 0.1) -> SpotLight3D:
	var l := SpotLight3D.new()
	parent.add_child(l)
	var dir := (target - pos).normalized()
	var up := Vector3.FORWARD if absf(dir.y) > 0.98 else Vector3.UP
	l.transform = Transform3D(Basis.looking_at(dir, up), pos)
	l.light_color = c
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_attenuation = 0.8
	l.shadow_enabled = false
	l.set_meta("base_energy", energy)
	l.set_meta("day_scale", day_scale)
	l.add_to_group("fair_light")
	return l


static func label(parent: Node, text: String, pos: Vector3, font_px: int, c: Color, rot_y: float = 0.0,
		outline: Color = Color(0.02, 0.01, 0.03), pixel: float = 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_px
	l.pixel_size = pixel
	l.outline_size = maxi(4, font_px / 8)
	l.outline_modulate = outline
	l.modulate = c
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	l.shaded = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(l)
	return l


static func catenary(a: Vector3, b: Vector3, sag: float, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts


static func ring_points(center: Vector3, r: float, n: int, phase: float = 0.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n:
		var a := TAU * float(i) / float(n) + phase
		pts.append(center + Vector3(cos(a) * r, 0, sin(a) * r))
	return pts


# ─── Batch ──────────────────────────────────────────────────────────────

class Batch:
	## Collects repeated small things and flushes each kind as one MultiMeshInstance3D.
	var bulbs: Array = []        # [pos, color, phase, radius]
	var struts: Dictionary = {}  # Material -> Array[Transform3D]
	var flags: Array = []        # [Transform3D, Color]
	var pools: Array = []        # [pos, radius, color]
	var balloons: Array = []     # [pos, color, phase]
	var models: Dictionary = {}  # model id -> Array[Transform3D]

	func bulb(p: Vector3, c: Color, phase: float = 0.0, r: float = 0.07) -> void:
		bulbs.append([p, c, phase, r])

	func bulb_line(pts: PackedVector3Array, palette: Array, chase: float = 0.0, r: float = 0.07, offset: int = 0) -> void:
		for i in pts.size():
			var c: Color = palette[(i + offset) % palette.size()]
			bulb(pts[i], c, float(i) * chase, r)

	func strut(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
		if not struts.has(mat):
			struts[mat] = []
		struts[mat].append(FairKit.strut_xform(a, b, r))

	func wire(pts: PackedVector3Array, r: float = 0.012) -> void:
		var m := FairKit.paint(Color(0.05, 0.05, 0.06), 0.6, 0.2)
		for i in pts.size() - 1:
			strut(pts[i], pts[i + 1], r, m)

	func string_lights(a: Vector3, b: Vector3, sag: float, spacing: float, palette: Array, chase: float = 0.07) -> void:
		var n := maxi(2, int(a.distance_to(b) / spacing))
		var pts := FairKit.catenary(a, b, sag, n)
		wire(pts)
		var hang := PackedVector3Array()
		for i in range(1, pts.size() - 1):
			hang.append(pts[i] + Vector3.DOWN * 0.09)
		bulb_line(hang, palette, chase)

	func bunting(a: Vector3, b: Vector3, sag: float, palette: Array, spacing: float = 0.55) -> void:
		var n := maxi(2, int(a.distance_to(b) / spacing))
		var pts := FairKit.catenary(a, b, sag, n)
		wire(pts, 0.008)
		var along := (b - a)
		along.y = 0.0
		var yaw := atan2(along.x, along.z) - PI * 0.5
		for i in range(1, pts.size() - 1):
			var xf := Transform3D(Basis(Vector3.UP, yaw), pts[i])
			flags.append([xf, palette[i % palette.size()]])

	func pool(p: Vector3, r: float, c: Color) -> void:
		pools.append([p, r, c])

	func balloon(p: Vector3, c: Color, phase: float) -> void:
		balloons.append([p, c, phase])

	func prop(id: String, xf: Transform3D) -> void:
		if not models.has(id):
			models[id] = []
		models[id].append(xf)

	func flush(parent: Node3D) -> void:
		if bulbs.size() > 0:
			var mm := _mm(FairKit.sphere_mesh(1.0, 8), bulbs.size(), true, true)
			for i in bulbs.size():
				var e: Array = bulbs[i]
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * float(e[3])), e[0]))
				mm.set_instance_color(i, e[1])
				mm.set_instance_custom_data(i, Color(float(e[2]), 0, 0, 0))
			_add(parent, mm, FairKit.bulb_mat(), false, "Bulbs")
		for mat in struts:
			var xs: Array = struts[mat]
			var mm2 := _mm(FairKit.cyl_mesh(1.0, 1.0, 1.0, 6), xs.size(), false, false)
			for i in xs.size():
				mm2.set_instance_transform(i, xs[i])
			_add(parent, mm2, mat, true, "Struts")
		if flags.size() > 0:
			var mm3 := _mm(FairKit.flag_mesh(), flags.size(), true, true)
			for i in flags.size():
				mm3.set_instance_transform(i, flags[i][0])
				mm3.set_instance_color(i, flags[i][1])
				mm3.set_instance_custom_data(i, Color(float(i) * 0.37, 0.0, 0, 0))
			var fm := FairKit.shader_mat("fair_sway", "flag")
			fm.set_shader_parameter("mode", 0.0)
			_add(parent, mm3, fm, false, "Bunting")
		if pools.size() > 0:
			var mm4 := _mm(FairKit.cached_mesh("pool_quad", func() -> Mesh:
				var q := PlaneMesh.new()
				q.size = Vector2(2, 2)
				return q), pools.size(), true, false)
			for i in pools.size():
				var e2: Array = pools[i]
				mm4.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(e2[1], 1, e2[1])), e2[0]))
				mm4.set_instance_color(i, e2[2])
			_add(parent, mm4, FairKit.pool_mat(), false, "LightPools")
		if balloons.size() > 0:
			var mm5 := _mm(FairKit.balloon_mesh(), balloons.size(), true, true)
			for i in balloons.size():
				var e3: Array = balloons[i]
				mm5.set_instance_transform(i, Transform3D(Basis.IDENTITY, e3[0]))
				mm5.set_instance_color(i, e3[1])
				mm5.set_instance_custom_data(i, Color(float(e3[2]), 1.0, 0, 0))
			var bm := FairKit.shader_mat("fair_sway", "balloon")
			bm.set_shader_parameter("mode", 1.0)
			_add(parent, mm5, bm, true, "Balloons")
		for id in models:
			var mx: Array = FairKit.model_mesh(id)
			if mx[0] == null:
				continue
			var xs2: Array = models[id]
			var mm6 := _mm(mx[0], xs2.size(), false, false)
			for i in xs2.size():
				mm6.set_instance_transform(i, (xs2[i] as Transform3D) * (mx[1] as Transform3D))
			_add(parent, mm6, null, true, "Props_" + id)
		bulbs.clear(); struts.clear(); flags.clear(); pools.clear(); balloons.clear(); models.clear()

	func _mm(m: Mesh, count: int, colors: bool, custom: bool) -> MultiMesh:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = colors
		mm.use_custom_data = custom
		mm.mesh = m
		mm.instance_count = count
		return mm

	func _add(parent: Node3D, mm: MultiMesh, mat: Material, shadows: bool, nm: String) -> void:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = nm
		mmi.multimesh = mm
		if mat:
			mmi.material_override = mat
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


static func flag_mesh() -> Mesh:
	## Bunting pennant: downward triangle hanging from its top edge, in the XY plane.
	return cached_mesh("flag", func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(-0.2, 0, 0); var b := Vector3(0.2, 0, 0); var c := Vector3(0, -0.36, 0)
		_tri(st, a, b, c, Vector3.BACK, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
		_tri(st, a, b, c, Vector3.FORWARD, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
		return st.commit())


static func balloon_mesh() -> Mesh:
	## Teardrop balloon with knot and a 1.1 m string, origin at the string's end.
	return cached_mesh("balloon", func() -> Mesh:
		var prof := PackedVector2Array()
		var base := 1.1
		prof.append(Vector2(0.0, base))
		prof.append(Vector2(0.025, base + 0.0))
		prof.append(Vector2(0.03, base + 0.04))
		for i in 13:
			var a := -PI * 0.5 + PI * float(i) / 12.0
			var taper := (1.0 + 0.18 * sin(a)) if a < 0.0 else 1.0  # narrower toward the knot
			var r := 0.19 * cos(a) * taper
			prof.append(Vector2(maxf(r, 0.0), base + 0.26 + 0.24 * sin(a) + (0.03 if a < 0.0 else 0.0)))
		var m := lathe(prof, 14)
		# String
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w := 0.004
		for side in [Vector3.RIGHT, Vector3.BACK]:
			_tri(st, -side * w, side * w, Vector3(0, base, 0) - side * w, side.cross(Vector3.UP), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			_tri(st, side * w, Vector3(0, base, 0) + side * w, Vector3(0, base, 0) - side * w, side.cross(Vector3.UP), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		st.commit(m)
		return m)


static func awning(parent: Node, width: float, depth: float, pos: Vector3, rot: Vector3, pair: Array,
		stripes: float = -1.0) -> MeshInstance3D:
	## Striped canvas awning (fair_awning shader, colors per instance).
	var q := cached_mesh("awn:%s:%s" % [width, depth], func() -> Mesh:
		var p := PlaneMesh.new()
		p.size = Vector2(width, depth)
		p.subdivide_depth = 2
		return p)
	var mi := mesh(parent, q, pos, shader_mat("fair_awning"), rot)
	mi.set_instance_shader_parameter("color_a", pair[0])
	mi.set_instance_shader_parameter("color_b", pair[1])
	mi.set_instance_shader_parameter("stripes", stripes if stripes > 0.0 else roundf(width / 0.45))
	return mi


# ─── Particles ──────────────────────────────────────────────────────────

static func puff_texture() -> Texture2D:
	if _cache.has("puff"):
		return _cache["puff"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["puff"] = t
	return t


static func smoke(amount: int, lifetime: float, size: Vector2, tint: Color, spread_deg: float,
		speed: Vector2, damping: float, gravity: Vector3, emit_radius: float, hot: bool,
		dir: Vector3 = Vector3.UP) -> GPUParticles3D:
	## Billowing, lit smoke/vapour. `hot` adds a fire-lit orange start to the colour ramp.
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = emit_radius
	pm.direction = dir
	pm.spread = spread_deg
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.damping_min = damping
	pm.damping_max = damping * 1.4
	pm.gravity = gravity
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = size.x
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.25))
	sc.add_point(Vector2(0.3, 0.75))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.scale_max = size.y
	var g := Gradient.new()
	var tc := Color(tint.r, tint.g, tint.b, 0.0)
	if hot:
		g.offsets = PackedFloat32Array([0.0, 0.03, 0.18, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1.0, 0.8, 0.5, 0.0), Color(1.0, 0.72, 0.42, 0.95),
			Color(tint.r, tint.g, tint.b, 0.92), Color(tint.r, tint.g, tint.b, 0.6), tc])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
		g.colors = PackedColorArray([tc, Color(tint.r, tint.g, tint.b, 0.55), tc])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff_texture()
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.5, 0.5, 0.5)
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	return p


# ─── Ticket booth ───────────────────────────────────────────────────────

static func ticket_booth(parent: Node3D, batch: Batch, booth_pos: Vector3, facing: Vector3, ride_item: Dictionary,
		accent: Color, queue_len: float = 5.5) -> Node3D:
	## Kiosk with a lit sign (ride name + price), counter, register, and a stanchion queue
	## lane running from the window toward `facing`. booth_pos is where the player stands
	## to buy (the RideBase trigger); the kiosk sits 1.7 m behind it.
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var yaw := atan2(f.x, f.z)
	var root := Node3D.new()
	root.name = "TicketBooth"
	root.position = booth_pos - f * 1.7
	root.rotation.y = yaw
	parent.add_child(root)
	var wall := pbr("corrugated_iron", accent.darkened(0.35).lerp(Color(0.7, 0.7, 0.72), 0.25), 0.7, 1.0)
	var trim := paint(Color(0.92, 0.86, 0.7), 0.5, 0.5)
	var dark := paint(Color(0.05, 0.05, 0.06), 0.7, 0.2)
	var wood := pbr("brown_planks_05", Color(0.95, 0.85, 0.7), 1.2)
	# Body (local +Z = window side, toward the queue)
	box(root, Vector3(2.0, 2.5, 0.08), Vector3(0, 1.25, -0.71), wall)
	box(root, Vector3(0.08, 2.5, 1.5), Vector3(-0.96, 1.25, 0), wall)
	box(root, Vector3(0.08, 2.5, 1.5), Vector3(0.96, 1.25, 0), wall)
	box(root, Vector3(2.0, 1.05, 0.08), Vector3(0, 0.525, 0.71), wall)
	box(root, Vector3(2.0, 0.42, 0.08), Vector3(0, 2.29, 0.71), wall)
	box(root, Vector3(0.12, 0.95, 0.08), Vector3(-0.92, 1.53, 0.71), trim)
	box(root, Vector3(0.12, 0.95, 0.08), Vector3(0.92, 1.53, 0.71), trim)
	box(root, Vector3(2.0, 0.06, 1.5), Vector3(0, 0.03, 0), dark)
	# Counter + roof
	box(root, Vector3(2.2, 0.07, 0.55), Vector3(0, 1.08, 0.92), wood)
	box(root, Vector3(2.5, 0.12, 2.1), Vector3(0, 2.56, 0.12), trim)
	box(root, Vector3(2.56, 0.05, 2.16), Vector3(0, 2.645, 0.12), glow(accent, 2.2, 0.6))
	model(root, "CashRegister_01", Vector3(0.45, 1.115, 0.7), PI, 0.75)
	# Inside glow + glass
	box(root, Vector3(1.8, 0.05, 0.05), Vector3(0, 2.0, 0.6), glow(Color(1.0, 0.85, 0.6), 4.0, 1.5))
	var g := box(root, Vector3(1.72, 0.92, 0.02), Vector3(0, 1.58, 0.74), glass(Color(0.8, 0.9, 1.0, 0.1)))
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Speaking grille hole in the glass
	cyl(root, 0.09, 0.09, 0.03, Vector3(-0.35, 1.45, 0.75), dark, 12).rotation.x = PI * 0.5
	# Sign board on the roof
	var title := String(ride_item.get("name", "RIDE")).to_upper()
	var price := AttractionCatalog.price_label(ride_item) if not ride_item.is_empty() else ""
	box(root, Vector3(2.9, 1.05, 0.14), Vector3(0, 3.25, 0.25), dark)
	box(root, Vector3(0.08, 0.6, 0.08), Vector3(-1.0, 2.85, 0.25), trim)
	box(root, Vector3(0.08, 0.6, 0.08), Vector3(1.0, 2.85, 0.25), trim)
	label(root, title, Vector3(0, 3.42, 0.33), 46, Color(1.6, 1.45, 1.2))
	label(root, price, Vector3(0, 3.02, 0.33), 34, Color(accent.r * 2.2, accent.g * 2.2, accent.b * 2.2))
	label(root, title, Vector3(0, 3.3, 0.17), 46, Color(1.3, 1.2, 1.0), PI)
	var border := PackedVector3Array()
	for i in 15:
		border.append(Vector3(-1.4 + i * 0.2, 3.74, 0.34))
		border.append(Vector3(-1.4 + i * 0.2, 2.76, 0.34))
	for j in 4:
		border.append(Vector3(-1.42, 2.95 + j * 0.2, 0.34))
		border.append(Vector3(1.42, 2.95 + j * 0.2, 0.34))
	var bl := PackedVector3Array()
	for p in border:
		bl.append(root.transform * p)
	batch.bulb_line(bl, [BULB_WARM], 0.11, 0.045)
	# Stanchion queue lane
	var chrome := paint(Color(0.8, 0.8, 0.82), 0.18, 0.95)
	var rope := paint(accent.darkened(0.2), 0.6, 0.0)
	var n := int(queue_len / 1.1)
	for side in [-0.75, 0.75]:
		var prev := Vector3.ZERO
		for i in n + 1:
			var lp := Vector3(side, 0, 1.25 + i * 1.1)
			var wp := root.transform * lp
			batch.strut(wp, wp + Vector3.UP * 0.95, 0.025, chrome)
			if i > 0:
				batch.strut(prev + Vector3.UP * 0.9, wp + Vector3.UP * 0.9, 0.018, rope)
			prev = wp
	# Light pool in front of the window
	batch.pool(root.transform * Vector3(0, 0.1, 2.0), 3.2, Color(1.0, 0.75, 0.45) * 0.55)
	solid_box(root, Vector3(2.1, 2.6, 1.6), Vector3(0, 1.3, 0))
	return root


# ─── Dysnomia crystals & holograms ──────────────────────────────────────

static func crystal_mesh() -> Mesh:
	## Hexagonal crystal prism with a pointed tip, 0.75 m tall, base at the origin.
	return cached_mesh("crystal", func() -> Mesh:
		return lathe(PackedVector2Array([Vector2(0.0, -0.05), Vector2(0.085, -0.02), Vector2(0.1, 0.5),
			Vector2(0.0, 0.75)]), 6))


static func crystal_mat(c: Color) -> ShaderMaterial:
	## The territory's own crystal shader (crystal.gdshader), fully powered.
	var key := "crystal:" + c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/crystal.gdshader")
	m.set_shader_parameter("crystal_color", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("territory_power", 1.0)
	_cache[key] = m
	return m


static func crystal_cluster(parent: Node, pos: Vector3, rng: RandomNumberGenerator, c: Color, count: int = 6,
		scl: float = 1.0) -> Node3D:
	## A glowing crystal outcrop (lit from within, like the crystal fields outside the fair).
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf() * TAU
	parent.add_child(root)
	var m := crystal_mat(c)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = crystal_mesh()
		mi.material_override = m
		var r := 0.0 if i == 0 else rng.randf_range(0.12, 0.35) * scl
		var a := rng.randf() * TAU
		mi.position = Vector3(cos(a) * r, 0, sin(a) * r)
		var h := (1.6 if i == 0 else rng.randf_range(0.6, 1.2)) * scl
		mi.scale = Vector3(h * 0.9, h, h * 0.9)
		mi.rotation = Vector3(rng.randf_range(-0.45, 0.45), rng.randf() * TAU, rng.randf_range(-0.45, 0.45)) * (0.2 if i == 0 else 1.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func holo_mat(c: Color, energy: float = 2.2) -> StandardMaterial3D:
	## Translucent holographic panel (additive, unshaded, double-sided).
	var key := "holo:%s:%s" % [c.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, 0.35)
	m.disable_receive_shadows = true
	_cache[key] = m
	return m
