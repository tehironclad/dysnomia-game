extends SceneTree
## Where the render objects come from: loads a scene like perf.gd, then walks the
## tree and counts visible GeometryInstance3D nodes (a MultiMesh counts once),
## their surfaces and shadow casters, grouped by node path (first --depth levels
## under the scene root), plus how many sit inside the camera's frustum.
##   xvfb-run … godot --path . -s res://tools/perf_breakdown.gd -- [--qing=0x…] [--view=…] [--scene=…] [--depth=3] [--merge-ids]
## --list=<text> also tallies the in-view instances whose path contains <text> by (parent, class, material)
## (--by-tris: sorted by their triangles; --list-casters: the sun casters in reach instead).
## --merge-ids folds numbered siblings into one row (Visitor362, Visitor363 → Visitor#; @Node3D@881 → @Node3D@#).
## Instances past their visibility range don't count as in view. "sun-casters": shadow casters
## within the sun's shadow reach of the camera, in or out of view (--by-shadow sorts by them). Also prints the renderer's
## own visible/shadow split for the frame. "ktris": triangles in view (LOD 0, MultiMeshes × instances;
## an upper bound where the renderer picks a lower LOD).

var _scene := "res://scenes/territory/territory_v2.tscn"
var _depth := 3
var _cam_pos := Vector3.ZERO
var _shadow_d := 0.0  ## the sun's shadow reach (0: no sun shadows)
var _merge_ids := false
var _list := ""
var _list_casters := false  ## --list-casters: tally the sun casters in reach instead of what's in view
var _tally := {}
var _tris_cache := {}
var _numbers := RegEx.create_from_string("[0-9]+")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--depth="):
			_depth = int(a.substr(8))
		elif a == "--merge-ids":
			_merge_ids = true
		elif a.begins_with("--list="):
			_list = a.substr(7)
		elif a == "--list-casters":
			_list_casters = true
	change_scene_to_file(_scene)
	for i in 150:
		await process_frame
	var cam := root.get_viewport().get_camera_3d()
	var planes: Array[Plane] = cam.get_frustum() if cam else []
	if cam:
		_cam_pos = cam.global_position
	for l in current_scene.find_children("*", "DirectionalLight3D", true, false):
		if (l as DirectionalLight3D).shadow_enabled and l.is_visible_in_tree():
			_shadow_d = maxf(_shadow_d, (l as DirectionalLight3D).directional_shadow_max_distance)
	var groups := {}
	var total := [0, 0, 0, 0, 0, 0]
	_walk(current_scene, current_scene, planes, groups, total)
	var keys := groups.keys()
	var col := 4 if OS.get_cmdline_user_args().has("--by-shadow") else 1
	keys.sort_custom(func(a, b): return groups[a][col] > groups[b][col])
	print("group                                                     nodes  in-view surf  shadow  sun-casters  ktris")
	for k in keys.slice(0, 45):
		var g: Array = groups[k]
		print("%-56s %6d %6d %5d %6d %6d %7.1f" % [String(k).left(56), g[0], g[1], g[2], g[3], g[4], g[5] / 1000.0])
	if _list != "":
		var tk := _tally.keys()
		var tcol := 1 if OS.get_cmdline_user_args().has("--by-tris") else 0
		tk.sort_custom(func(a, b): return _tally[a][tcol] > _tally[b][tcol])
		for k in tk.slice(0, 60):
			print("  %5d %8.1fk  %s" % [_tally[k][0], _tally[k][1] / 1000.0, k])
	print("TOTAL nodes %d, in view %d, surfaces in view %d, shadow casters in view %d, sun casters in reach %d, ktris in view %.0f" % [
		total[0], total[1], total[2], total[3], total[4], total[5] / 1000.0])
	var vp := root.get_viewport_rid()
	for t in [["visible", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE], ["shadow", RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]]:
		print("render %s: objects %d, draw calls %d, primitives %d" % [t[0],
			RenderingServer.viewport_get_render_info(vp, t[1], RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			RenderingServer.viewport_get_render_info(vp, t[1], RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(vp, t[1], RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)])
	quit()


func _walk(n: Node, top: Node, planes: Array[Plane], groups: Dictionary, total: Array) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is CanvasItem:
		return
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var key := _key(gi, top)
		if not groups.has(key):
			groups[key] = [0, 0, 0, 0, 0, 0]
		var g: Array = groups[key]
		g[0] += 1
		total[0] += 1
		var inside := _in_view(gi, planes)
		var caster := false
		if _shadow_d > 0.0 and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var c := (gi.global_transform * gi.get_aabb()).get_center()
			var dc := _cam_pos.distance_to(c)
			if dc < _shadow_d and _in_range(gi, dc):
				g[4] += 1
				total[4] += 1
				caster = true
		var listed := caster if _list_casters else inside
		if listed and _list != "" and String(gi.get_path()).contains(_list):
			var mat: Material = gi.material_override
			if mat == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				mat = (gi as MeshInstance3D).mesh.surface_get_material(0)
			var tk := "%s / %s %s / %s" % [_numbers.sub(String(gi.get_parent().name), "#", true), gi.get_class(),
				_numbers.sub(String(gi.name), "#", true), (mat.get_class() + (":" + (mat as ShaderMaterial).shader.resource_path.get_file() if mat is ShaderMaterial and (mat as ShaderMaterial).shader else "")) if mat else "-"]
			var tv: Array = _tally.get(tk, [0, 0])
			_tally[tk] = [tv[0] + 1, tv[1] + _tris_of(gi)]
		if inside:
			var surf := 1
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				surf = (gi as MeshInstance3D).mesh.get_surface_count()
			var tris := _tris_of(gi)
			g[5] += tris
			total[5] += tris
			g[1] += 1
			g[2] += surf
			total[1] += 1
			total[2] += surf
			if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				g[3] += 1
				total[3] += 1
	for c in n.get_children():
		_walk(c, top, planes, groups, total)


func _key(n: Node, top: Node) -> String:
	var parts: Array = []
	var p := n.get_parent()
	while p and p != top:
		parts.push_front(String(p.name))
		p = p.get_parent()
	var key := "/".join(parts.slice(0, _depth))
	return _numbers.sub(key, "#", true) if _merge_ids else key


func _tris_of(gi: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	var times := 1
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		var mm := (gi as MultiMeshInstance3D).multimesh
		mesh = mm.mesh
		times = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	if mesh == null:
		return 0
	if not _tris_cache.has(mesh):
		var n := 0
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var idx = a[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null and idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		_tris_cache[mesh] = n
	return int(_tris_cache[mesh]) * times


## Within its visibility range (begin and end) at distance d, and its HLOD parent's (a part
## behind a FarProxy stand-in shows only while the stand-in is nearer than its begin).
func _in_range(gi: GeometryInstance3D, d: float) -> bool:
	if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end:
		return false
	if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin:
		return false
	if gi.visibility_parent != NodePath():
		var p := gi.get_node_or_null(gi.visibility_parent) as GeometryInstance3D
		if p and p.visibility_range_begin > 0.0:
			var dp := _cam_pos.distance_to((p.global_transform * p.get_aabb()).get_center())
			if dp >= p.visibility_range_begin:
				return false
	return true


func _in_view(gi: GeometryInstance3D, planes: Array[Plane]) -> bool:
	var box := gi.global_transform * gi.get_aabb()
	var c := box.get_center()
	if not _in_range(gi, _cam_pos.distance_to(c)):
		return false  # past its visibility range, or swapped for a stand-in
	if planes.is_empty():
		return true
	var r := box.size.length() * 0.5
	for pl in planes:
		if pl.distance_to(c) > r:
			return false
	return true
