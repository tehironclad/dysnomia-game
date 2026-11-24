class_name FarProxy
extends RefCounted
## Far LOD for the fair (perf, 2026-11-24): a ride, a stall or a corner of the fair is
## many small meshes, each one object (and one more per shadow cascade). Past BEGIN_M
## from the camera a rigid group of them is drawn as ONE stand-in mesh with one surface
## per material (the same geometry and materials, merged in the group's space), plus one
## single-surface shadow caster; the parts themselves hide (each part's visibility_parent
## is the stand-in: Godot's HLOD, so parts and stand-in swap at the same distance, measured
## from the stand-in's centre). A stand-in is a child of its group, so a turning wheel or a
## spinning turntable keeps turning far away; what moves *inside* a group (a sled's bob)
## is frozen in the stand-in as it was built, which can't be seen from that far.
##
## Left live (never merged, never hidden by the stand-in): labels, particles, lights,
## MultiMeshes other than plain struts (bulbs chase, balloons sway), ShaderMaterial meshes
## (awnings and hulls carry per-instance stripes / uniforms), anything with its own
## visibility range or parent (prizes, NPCs), anything hidden when the group is built
## (flames, chutes, the round's reticle: they show live when they show), skinned meshes,
## nodes in the group "lod_live" and nodes the caller stops at (separately moving parts).
## Parts smaller than MIN_PART_M are not in the stand-in (DetailCull would have ended them
## by then anyway) but still hide with the group.
##
## Purely presentational: the same for every viewer; only the camera's distance matters.
## Collision, triggers, booths and game logic are untouched.

const BEGIN_M := 36.0        ## the stand-in shows past this distance (m) from its centre
const MARGIN_M := 3.0        ## hysteresis either side of BEGIN_M
const MIN_PART_M := 0.3      ## parts smaller than this (world size, m) are dropped from the stand-in
                             ## (≈ 5 px at BEGIN_M; DetailCull ends a 0.3 m prop at 72 m at High)
const SHADOW_MIN_M := 1.8    ## parts this big cast from the stand-in's shadow caster (20 × 1.8 = BEGIN_M)…
const SHADOW_FAR_M := 72.0   ## …and past this distance only parts of SHADOW_FAR_MIN_M or more
const SHADOW_FAR_MIN_M := 3.6
const LOD_MERGE_ANGLE := 25.0  ## ImporterMesh.generate_lods: the stand-ins get automatic LODs
const LOD_SPLIT_ANGLE := 60.0
const KEEP_META := "far_keep"  ## a material animated at runtime (a flashing beacon): never collapsed
const MAX_STRUT_TRIS := 200  ## a MultiMesh of a mesh this small, plain material: merged (struts)
const LIVE_GROUP := "lod_live"
const META := "far_proxied"  ## set on every part that hides behind a stand-in (DetailCull reads it)

static var _mesh_cache := {}  ## cache_key → [visual ArrayMesh, shadow ArrayMesh, far shadow ArrayMesh]
static var _tex_mats := {}    ## textured triplanar material key → its vertex-tinted twin
static var _paint_mat: ShaderMaterial
static var _glow_mat: ShaderMaterial
static var built := 0         ## stand-ins made (perf notes)
static var parts_hidden := 0  ## parts that swap to a stand-in
static var build_ms := 0.0    ## main-thread time spent merging
static var lod_ms := 0.0      ## worker time generating LODs
static var _queue: Array = []    ## jobs not started
static var _pending: Array = []  ## jobs whose LODs are on a worker


## Queues the stand-ins for several rigid groups: [[Node3D, Array stop_at, cache_key], …].
## Every group stops at the other groups, so nothing is merged twice. Built over the next
## frames by pump() (the merge on the main thread, a group per pump; the LODs on a worker
## thread), so a fair loads no slower: until its stand-in lands a group just draws its parts.
static func enqueue_groups(groups: Array, begin_m: float = BEGIN_M) -> void:
	var all: Array = []
	for g in groups:
		all.append(g[0])
	for g in groups:
		var stop: Array = (g[1] as Array).duplicate() if g.size() > 1 else []
		for other in all:
			if other != g[0] and not stop.has(other):
				stop.append(other)
		_queue.append({"group": g[0], "stop": stop, "begin": begin_m, "key": String(g[2]) if g.size() > 2 else ""})


## Queues spatial stand-ins for the loose, static dressing under `root` (stalls, the arch,
## kiosks, lamps, rocks…): each of `members` (children of root) falls in a cell_m × cell_m
## cell by its position, and each cell gets one stand-in.
static func enqueue_cells(root: Node3D, members: Array, cell_m: float, begin_m: float = BEGIN_M) -> void:
	_queue.append({"cells": root, "members": members, "cell": cell_m, "begin": begin_m})


## Runs queued work for about `budget_ms` (at least one job), and lands finished stand-ins.
## Call every frame from the fair.
static func pump(budget_ms: float = 4.0) -> void:
	_land(false)
	var t0 := Time.get_ticks_usec()
	var guard := _queue.size()
	while not _queue.is_empty() and guard > 0:
		guard -= 1
		_run(_queue.pop_front())
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break


## Everything queued, now (tests, tools, a fair about to go): runs every job and waits for
## every worker.
static func flush() -> void:
	var guard := 10000
	while (not _queue.is_empty() or not _pending.is_empty()) and guard > 0:
		guard -= 1
		while not _queue.is_empty():
			_run(_queue.pop_front())
		_land(true)


## Drops the work for `root` and everything under it (a fair going away): queued jobs are
## forgotten, workers already running are waited for and their meshes dropped.
static func cancel(root: Node) -> void:
	_queue = _queue.filter(func(j: Dictionary) -> bool: return not _under(j, root))
	var i := 0
	while i < _pending.size():
		if _under(_pending[i], root):
			WorkerThreadPool.wait_for_task_completion(int(_pending[i]["task"]))
			_pending.remove_at(i)
		else:
			i += 1


static func _under(job: Dictionary, root: Node) -> bool:
	var n = job.get("group", job.get("cells", job.get("parent")))
	return not is_instance_valid(n) or n == root or root.is_ancestor_of(n)


## Is there still work (queued or on a worker)?
static func busy() -> bool:
	return not _queue.is_empty() or not _pending.is_empty()


## One group, built now: collects its mergeable parts (not under `stop`), merges them into a
## stand-in child, and parents the parts' visibility to it. Returns the stand-in (null: nothing
## to merge). `cache_key`: groups built alike (the wheel's gondolas of one colour) share one
## mesh, so their draws batch.
static func build(group: Node3D, stop: Array = [], begin_m: float = BEGIN_M, cache_key: String = "") -> MeshInstance3D:
	if group == null:
		return null
	var parts: Array = []  # [GeometryInstance3D, Transform3D in group space]
	_collect(group, Transform3D.IDENTITY, stop, parts)
	if parts.size() < 2:
		return null
	var meshes: Array
	if cache_key != "" and _mesh_cache.has(cache_key):
		meshes = _mesh_cache[cache_key]
	else:
		var ims := merge_data(parts, _group_scale(group))
		_lods(ims)
		meshes = _meshes(ims)
		if cache_key != "":
			_mesh_cache[cache_key] = meshes
	return attach(group, parts, meshes, begin_m)


static func _run(job: Dictionary) -> void:
	if job.has("cells"):
		var root: Node3D = job["cells"]
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
		var cells := {}  # Vector2i → parts
		for m in job["members"]:
			if not is_instance_valid(m):
				continue
			var n := m as Node3D
			if n == null or not n.visible or n.get_parent() != root:
				continue
			var key := Vector2i(floori(n.position.x / float(job["cell"])), floori(n.position.z / float(job["cell"])))
			if not cells.has(key):
				cells[key] = []
			var parts: Array = cells[key]
			if n is GeometryInstance3D:
				if mergeable(n as GeometryInstance3D) and n.transform.basis.determinant() > 0.0:
					parts.append([n, n.transform])
			elif _live(n):
				continue
			_collect(n, n.transform, [], parts)
		for key in cells:
			_queue.append({"parent": root, "parts": cells[key], "begin": job["begin"], "key": "",
				"name": "FarProxyCell_%d_%d" % [key.x, key.y], "scale": _group_scale(root)})
		return
	if job.has("group"):
		var group: Node3D = job["group"]
		if not is_instance_valid(group) or not group.is_inside_tree():
			return
		var parts: Array = []
		_collect(group, Transform3D.IDENTITY, job["stop"], parts)
		job = {"parent": group, "parts": parts, "begin": job["begin"], "key": job["key"], "name": "FarProxy", "scale": _group_scale(group)}
	var parent: Node3D = job["parent"]
	if not is_instance_valid(parent) or (job["parts"] as Array).size() < 2:
		return
	var key: String = job["key"]
	if key != "" and _mesh_cache.has(key):
		attach(parent, job["parts"], _mesh_cache[key], job["begin"], job["name"])
		return
	for p in _pending:
		if key != "" and p["key"] == key:
			_queue.append(job)  # its twin is on a worker: share that mesh once it lands
			return
	var t0 := Time.get_ticks_usec()
	var ims := merge_data(job["parts"], job["scale"])
	build_ms += (Time.get_ticks_usec() - t0) / 1000.0
	job["ims"] = ims
	job["task"] = WorkerThreadPool.add_task(func() -> void: _lods(ims), false, "FarProxy LODs")
	_pending.append(job)


static func _land(wait: bool) -> void:
	var i := 0
	while i < _pending.size():
		var job: Dictionary = _pending[i]
		var task: int = job["task"]
		if not wait and not WorkerThreadPool.is_task_completed(task):
			i += 1
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		_pending.remove_at(i)
		var meshes := _meshes(job["ims"])
		if job["key"] != "":
			_mesh_cache[job["key"]] = meshes
		var parent: Node3D = job["parent"]
		if is_instance_valid(parent) and parent.is_inside_tree():
			attach(parent, job["parts"], meshes, job["begin"], job["name"])


## Puts the stand-in (and its shadow casters) under `parent` for parts given in parent's space,
## and hides the parts behind it. Parts freed or changed since they were merged are left alone.
static func attach(parent: Node3D, parts: Array, meshes: Array, begin_m: float, proxy_name: String = "FarProxy") -> MeshInstance3D:
	var vis: ArrayMesh = meshes[0]
	if vis == null or vis.get_surface_count() == 0:
		return null
	if parent.has_node(NodePath(proxy_name)):
		return null  # built already
	var proxy := MeshInstance3D.new()
	proxy.name = proxy_name
	proxy.mesh = vis
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.set_meta(META, true)
	_range(proxy, begin_m)
	parent.add_child(proxy)
	# Shadow casters in two tiers (DetailCull's shadow LOD, in bulk): parts big enough to cast
	# from BEGIN_M, then only the big ones from SHADOW_FAR_M (High: a prop casts within 20 × its size)
	for tier in 2:
		var sh: ArrayMesh = meshes[1 + tier]
		if sh == null or sh.get_surface_count() == 0:
			continue
		var caster := MeshInstance3D.new()
		caster.name = proxy_name + ("Shadow" if tier == 0 else "ShadowFar")
		caster.mesh = sh
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		caster.custom_aabb = vis.get_aabb()  # same centre as the stand-in: they swap together
		caster.set_meta(META, true)
		if tier == 0:
			_range(caster, begin_m)
			caster.visibility_range_end = maxf(begin_m + MARGIN_M * 2.0, SHADOW_FAR_M)
			caster.visibility_range_end_margin = MARGIN_M
		else:
			_range(caster, maxf(begin_m + MARGIN_M * 2.0, SHADOW_FAR_M))
		parent.add_child(caster)
	for e in parts:
		if not is_instance_valid(e[0]):
			continue
		var gi: GeometryInstance3D = e[0]
		if not mergeable(gi):
			continue  # changed since it was merged (its own range now, hidden by someone else)
		gi.visibility_parent = gi.get_path_to(proxy)
		gi.set_meta(META, true)
		parts_hidden += 1
	built += 1
	return proxy


static func _range(gi: GeometryInstance3D, begin_m: float) -> void:
	gi.visibility_range_begin = begin_m
	gi.visibility_range_begin_margin = MARGIN_M
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static func _group_scale(group: Node3D) -> float:
	var s := group.global_transform.basis.get_scale() if group.is_inside_tree() else group.basis.get_scale()
	return maxf(absf(s.x), maxf(absf(s.y), absf(s.z)))


static func _collect(n: Node, xf: Transform3D, stop: Array, parts: Array) -> void:
	for c in n.get_children():
		if stop.has(c) or not (c is Node3D) or _live(c):
			continue
		var c3 := c as Node3D
		if not c3.visible or c3.top_level:
			continue
		if c3 is CollisionObject3D and not (c3 is StaticBody3D):
			continue  # bodies and triggers: nothing to draw, or something that moves
		if c3 is Skeleton3D:
			continue
		var cx := xf * c3.transform
		if c3 is GeometryInstance3D and mergeable(c3 as GeometryInstance3D) and cx.basis.determinant() > 0.0:
			parts.append([c3, cx])
		elif c3 is GeometryInstance3D and (c3 as GeometryInstance3D).visibility_parent != NodePath():
			continue  # someone else's HLOD
		_collect(c3, cx, stop, parts)


## Left live with everything under it: the "lod_live" group, and any node with a script of
## its own (NPCs, effects, crowds, boards that light from chain state), except a midway
## game's stage (its idle props are static; a round only runs up close).
static func _live(n: Node) -> bool:
	if n.is_in_group(LIVE_GROUP):
		return true
	return n.get_script() != null and not (n is MidwayStage)


## Can this instance be drawn by a stand-in? (Pure on the node's own settings.)
static func mergeable(gi: GeometryInstance3D) -> bool:
	if gi.visibility_range_begin > 0.0 or gi.visibility_parent != NodePath():
		return false  # its own range or HLOD (prizes, NPCs): theirs stands
	if gi.visibility_range_end > 0.0 and not gi.has_meta(DetailCull.META):
		return false  # its own range (a range DetailCull gave it is fine: it keeps it up close)
	if gi.material_overlay != null or gi.has_meta(META):
		return false
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		if mi.mesh == null or mi.skin != null:
			return false
		var am := mi.mesh as ArrayMesh  # a PrimitiveMesh is indexed triangles
		if am == null and not (mi.mesh is PrimitiveMesh):
			return false
		for s in mi.mesh.get_surface_count():
			if am and am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				return false
			if am and am.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES:
				return false
			if not _plain(_surface_mat(mi, s)):
				return false
		return true
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null or mm.use_colors or mm.use_custom_data or mm.visible_instance_count >= 0 and mm.visible_instance_count != mm.instance_count:
			return false
		if mm.transform_format != MultiMesh.TRANSFORM_3D or mm.mesh.get_surface_count() != 1 or not (mm.mesh is ArrayMesh or mm.mesh is PrimitiveMesh):
			return false
		if _tris(mm.mesh) > MAX_STRUT_TRIS:
			return false
		var m: Material = gi.material_override if gi.material_override else mm.mesh.surface_get_material(0)
		return _plain(m)
	return false


static func _plain(m: Material) -> bool:
	return m == null or m is BaseMaterial3D


static func _surface_mat(mi: MeshInstance3D, s: int) -> Material:
	if mi.material_override:
		return mi.material_override
	var m := mi.get_surface_override_material(s)
	return m if m else mi.mesh.surface_get_material(s)


static func _tris(m: Mesh) -> int:
	var arr := m.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	return (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3


## Merges [[GeometryInstance3D, Transform3D], …] into [visual, shadow, far shadow] ImporterMeshes
## (null: none). `scale`: the group's world scale, for the size thresholds. Main thread (it
## reads the parts' meshes); _lods() may then run anywhere, _meshes() back on the main thread.
##
## Draw calls: plain paints (untextured, opaque) collapse into ONE surface whatever their colour
## (far_paint.gdshader: per-vertex albedo, roughness, metallic, clearcoat), plain glows into one
## more (far_glow.gdshader), and the triplanar textures into one surface per texture set (tint as
## vertex colour). Glass, model materials and anything marked KEEP_META keep their own surface.
## SurfaceTool.append_from does the vertex work (C++); the per-vertex constants are filled per
## part. Every mesh gets automatic LODs.
static func merge_data(parts: Array, scale: float = 1.0) -> Array:
	var groups := {}   # key → {st, mat, consts, col: [PackedColorArray chunks], uv2: [PackedVector2Array chunks]}
	var order: Array = []
	var shadows: Array = [null, null]
	for e in parts:
		var gi: GeometryInstance3D = e[0]
		var xf: Transform3D = e[1]
		var pieces: Array = []  # [mesh, surface, Transform3D, Material]
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				pieces.append([mi.mesh, s, xf, _surface_mat(mi, s)])
		else:
			var mm := (gi as MultiMeshInstance3D).multimesh
			var m: Material = gi.material_override if gi.material_override else mm.mesh.surface_get_material(0)
			for i in mm.instance_count:
				pieces.append([mm.mesh, 0, xf * mm.get_instance_transform(i), m])
		var casts: bool = int(gi.get_meta(DetailCull.SHADOW_META, gi.cast_shadow)) != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for p in pieces:
			var pxf: Transform3D = p[2]
			var mesh := _indexed(p[0], int(p[1]))
			var surf := 0 if mesh != p[0] else int(p[1])
			var size := (pxf.basis * mesh.get_aabb().size).length() * scale
			if size < MIN_PART_M:
				continue
			var mat: Material = p[3]
			var slot := far_slot(mat)
			var key = slot[0]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"st": st, "mat": slot[1], "consts": slot[4], "col": [], "uv2": []}
				order.append(key)
			var g: Dictionary = groups[key]
			(g["st"] as SurfaceTool).append_from(mesh, surf, pxf)
			if g["consts"]:
				var n := _vertex_count(mesh, surf)
				var c := PackedColorArray()
				c.resize(n)
				c.fill(slot[2])
				(g["col"] as Array).append(c)  # chunks (packed arrays are values): joined once at the end
				var u := PackedVector2Array()
				u.resize(n)
				u.fill(slot[3])
				(g["uv2"] as Array).append(u)
			var opaque := not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			if casts and opaque:
				for tier in 2:
					if size >= (SHADOW_MIN_M if tier == 0 else SHADOW_FAR_MIN_M):
						if shadows[tier] == null:
							shadows[tier] = SurfaceTool.new()
							(shadows[tier] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
						(shadows[tier] as SurfaceTool).append_from(mesh, surf, pxf)
	var im := ImporterMesh.new()
	for key in order:
		var g: Dictionary = groups[key]
		var arrays := (g["st"] as SurfaceTool).commit_to_arrays()
		var nv := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if nv == 0:
			continue
		if g["consts"]:
			var col := PackedColorArray()
			for c in g["col"]:
				col.append_array(c)
			var uv2 := PackedVector2Array()
			for u in g["uv2"]:
				uv2.append_array(u)
			if col.size() != nv:
				push_warning("FarProxy: vertex count mismatch (%d vs %d), constants dropped" % [col.size(), nv])
			else:
				arrays[Mesh.ARRAY_COLOR] = col
				arrays[Mesh.ARRAY_TEX_UV2] = uv2
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, g["mat"])
	var out: Array = [im]
	for tier in 2:
		var sst: SurfaceTool = shadows[tier]
		if sst == null:
			out.append(null)
			continue
		var sa := sst.commit_to_arrays()
		var bare := []
		bare.resize(Mesh.ARRAY_MAX)
		bare[Mesh.ARRAY_VERTEX] = sa[Mesh.ARRAY_VERTEX]
		bare[Mesh.ARRAY_NORMAL] = sa[Mesh.ARRAY_NORMAL]
		bare[Mesh.ARRAY_INDEX] = sa[Mesh.ARRAY_INDEX]
		var sim := ImporterMesh.new()
		sim.add_surface(Mesh.PRIMITIVE_TRIANGLES, bare)
		out.append(sim)
	return out


## Same as merge_data, as finished meshes (synchronous: tests).
static func merge(parts: Array, scale: float = 1.0) -> Array:
	var ims := merge_data(parts, scale)
	_lods(ims)
	return _meshes(ims)


## Automatic LODs for the stand-ins (meshoptimizer; pure CPU on the ImporterMeshes' own data,
## so it runs on a worker thread).
static func _lods(ims: Array) -> void:
	var t0 := Time.get_ticks_usec()
	for im in ims:
		if im != null and (im as ImporterMesh).get_surface_count() > 0:
			(im as ImporterMesh).generate_lods(LOD_MERGE_ANGLE, LOD_SPLIT_ANGLE, [])
	lod_ms += (Time.get_ticks_usec() - t0) / 1000.0


static func _meshes(ims: Array) -> Array:
	var out: Array = []
	for im in ims:
		out.append((im as ImporterMesh).get_mesh() if im != null and (im as ImporterMesh).get_surface_count() > 0 else null)
	return out


static func _vertex_count(mesh: Mesh, surface: int) -> int:
	var key := "far_proxy_nverts_%d" % surface
	if mesh.has_meta(key):
		return int(mesh.get_meta(key))
	var n := (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	mesh.set_meta(key, n)
	return n


## Where a material's parts go in a stand-in: [group key, the surface's material, per-vertex
## colour, per-vertex UV2, whether the group carries per-vertex constants].
static func far_slot(mat: Material) -> Array:
	if mat == null:
		return ["none", null, Color.WHITE, Vector2.ZERO, false]
	var b := mat as BaseMaterial3D
	if b == null or mat.has_meta(KEEP_META) or b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or b.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or b.cull_mode != BaseMaterial3D.CULL_BACK \
			or b.vertex_color_use_as_albedo or b.rim_enabled or b.detail_enabled \
			or b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or b.grow or b.use_point_size or b.next_pass != null:
		return [mat, mat, Color.WHITE, Vector2.ZERO, false]
	var textured := b.albedo_texture != null or b.normal_enabled or b.emission_texture != null \
		or (b is StandardMaterial3D and ((b as StandardMaterial3D).roughness_texture != null or (b as StandardMaterial3D).metallic_texture != null)) \
		or (b is ORMMaterial3D and (b as ORMMaterial3D).orm_texture != null)
	if not textured:
		var cc := b.clearcoat if b.clearcoat_enabled else 0.0
		if b.emission_enabled:
			var e := b.emission
			var le := maxf(0.001, e.r + e.g + e.b)
			var k := clampf((b.albedo_color.r + b.albedo_color.g + b.albedo_color.b) / le, 0.0, 1.0)
			return ["far_glow", _glow(), Color(e.r, e.g, e.b, k), Vector2(b.emission_energy_multiplier, b.roughness), true]
		return ["far_paint", _paint(), Color(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b, cc), Vector2(b.roughness, b.metallic), true]
	if b.uv1_triplanar and not b.emission_enabled and b.albedo_texture != null:
		var key := "tex:%s:%s:%s:%s:%s:%s:%s:%s" % [b.albedo_texture.get_rid(), (b.normal_texture.get_rid() if b.normal_texture else ""),
			((b as ORMMaterial3D).orm_texture.get_rid() if b is ORMMaterial3D and (b as ORMMaterial3D).orm_texture else ""),
			b.uv1_scale, b.uv1_triplanar_sharpness, b.metallic, b.roughness, b.normal_scale]
		if not _tex_mats.has(key):
			var twin := b.duplicate() as BaseMaterial3D
			twin.albedo_color = Color.WHITE
			twin.vertex_color_use_as_albedo = true
			twin.vertex_color_is_srgb = true
			_tex_mats[key] = twin
		return [key, _tex_mats[key], Color(b.albedo_color.r, b.albedo_color.g, b.albedo_color.b, 1.0), Vector2.ZERO, true]
	return [mat, mat, Color.WHITE, Vector2.ZERO, false]


static func _paint() -> ShaderMaterial:
	if _paint_mat == null:
		_paint_mat = ShaderMaterial.new()
		_paint_mat.shader = load("res://assets/shaders/far_paint.gdshader")
	return _paint_mat


static func _glow() -> ShaderMaterial:
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = load("res://assets/shaders/far_glow.gdshader")
	return _glow_mat


## append_from keeps a part's indices as they are, so a part without an index array (the
## lathed and extruded meshes) is indexed once first (cached per mesh and surface).
static func _indexed(mesh: Mesh, surface: int) -> Mesh:
	if not (mesh is ArrayMesh) or (mesh as ArrayMesh).surface_get_format(surface) & Mesh.ARRAY_FORMAT_INDEX:
		return mesh
	var key := "far_proxy_indexed_%d" % surface
	if mesh.has_meta(key):
		return mesh.get_meta(key)
	var st := SurfaceTool.new()
	st.create_from(mesh, surface)
	st.index()
	var out := st.commit()
	mesh.set_meta(key, out)  # lives and dies with the mesh
	return out
