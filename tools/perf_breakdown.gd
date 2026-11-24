extends SceneTree
## Where the render objects come from: loads a scene like perf.gd, then walks the
## tree and counts visible GeometryInstance3D nodes (a MultiMesh counts once),
## their surfaces and shadow casters, grouped by node path (first --depth levels
## under the scene root), plus how many sit inside the camera's frustum.
##   xvfb-run … godot --path . -s res://tools/perf_breakdown.gd -- [--qing=0x…] [--view=…] [--scene=…] [--depth=3]
## Instances past their visibility range don't count as in view. "sun-casters": shadow casters
## within the sun's shadow reach of the camera, in or out of view (--by-shadow sorts by them). Also prints the renderer's
## own visible/shadow split for the frame.

var _scene := "res://scenes/territory/territory_v2.tscn"
var _depth := 3
var _cam_pos := Vector3.ZERO
var _shadow_d := 0.0  ## the sun's shadow reach (0: no sun shadows)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--depth="):
			_depth = int(a.substr(8))
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
	var total := [0, 0, 0, 0, 0]
	_walk(current_scene, current_scene, planes, groups, total)
	var keys := groups.keys()
	var col := 4 if OS.get_cmdline_user_args().has("--by-shadow") else 1
	keys.sort_custom(func(a, b): return groups[a][col] > groups[b][col])
	print("group                                                     nodes  in-view surf  shadow  sun-casters")
	for k in keys.slice(0, 45):
		var g: Array = groups[k]
		print("%-56s %6d %6d %5d %6d %6d" % [String(k).left(56), g[0], g[1], g[2], g[3], g[4]])
	print("TOTAL nodes %d, in view %d, surfaces in view %d, shadow casters in view %d, sun casters in reach %d" % total)
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
			groups[key] = [0, 0, 0, 0, 0]
		var g: Array = groups[key]
		g[0] += 1
		total[0] += 1
		var inside := _in_view(gi, planes)
		if _shadow_d > 0.0 and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var c := (gi.global_transform * gi.get_aabb()).get_center()
			var dc := _cam_pos.distance_to(c)
			if dc < _shadow_d and (gi.visibility_range_end <= 0.0 or dc < gi.visibility_range_end):
				g[4] += 1
				total[4] += 1
		if inside:
			var surf := 1
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
				surf = (gi as MeshInstance3D).mesh.get_surface_count()
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
	return "/".join(parts.slice(0, _depth))


func _in_view(gi: GeometryInstance3D, planes: Array[Plane]) -> bool:
	if planes.is_empty():
		return true
	var box := gi.global_transform * gi.get_aabb()
	var c := box.get_center()
	var r := box.size.length() * 0.5
	if gi.visibility_range_end > 0.0 and _cam_pos.distance_to(c) > gi.visibility_range_end:
		return false  # past its visibility range
	for pl in planes:
		if pl.distance_to(c) > r:
			return false
	return true
