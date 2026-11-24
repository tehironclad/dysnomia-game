extends SceneTree
## Performance sample (WP 7.5) of the territory scene: draw calls, objects,
## primitives, process time, and whether the object count grows per frame
## (per-frame allocations of Nodes/Resources). Needs a renderer (xvfb + lavapipe):
##   xvfb-run … godot --path . -s res://tools/perf.gd -- [--qing=0x…] [--frames=300] [--scene=res://…tscn] [--view=…]
##       [--hide=<name part>] (profiling: what those nodes cost)
## Absolute FPS under a CPU rasteriser means little; the counts are what to budget.
## Budgets for a mid-range GPU at High. Frame time under lavapipe is not one of
## them (a CPU rasteriser); headless wall time minus the empty-scene floor
## (--disable=.) is the scene's script cost (measured ≈ 0.4 ms, 2026-11-23).
const BUDGET := {"draw_calls": 900, "objects": 1500, "primitives": 1500000, "object_growth_per_frame": 0.05}

var _frames := 300
var _disable: Array = []
var _hide: Array = []  ## profiling: hide every node whose name contains one of these (what does it cost?)
var _scene := "res://scenes/territory/territory_v2.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--scene="):
			_scene = a.substr(8)  # e.g. res://scenes/places/sunny_pub.tscn (the scene reads --qing/--view itself)
		elif a.begins_with("--disable="):
			_disable.append(a.substr(10))  # profiling: a node path under the scene
		elif a.begins_with("--hide="):
			_hide.append(a.substr(7))
	change_scene_to_file(_scene)
	for i in 180:
		await process_frame
	for path in _disable:
		var nd := current_scene.get_node_or_null(path)
		if nd:
			nd.process_mode = Node.PROCESS_MODE_DISABLED
	for pat in _hide:
		var n := 0
		for nd in current_scene.find_children("*" + pat + "*", "Node3D", true, false):
			(nd as Node3D).visible = false
			n += 1
		print("hidden %d nodes named *%s*" % [n, pat])
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var dc := 0.0
	var ob := 0.0
	var pr := 0.0
	var pt := 0.0
	var pmax := 0.0
	var phys := 0.0
	var t0 := Time.get_ticks_usec()
	for i in _frames:
		await process_frame
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		ob += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		pr += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		pt += p
		pmax = maxf(pmax, p)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var wall_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(_frames)
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var n := float(_frames)
	var res := {"draw_calls": dc / n, "objects": ob / n, "primitives": pr / n, "process_ms": pt / n,
		"process_ms_max": pmax, "object_growth_per_frame": (obj1 - obj0) / n,
		"fps_cpu_renderer": Performance.get_monitor(Performance.TIME_FPS),
		"physics_ms": phys / float(_frames), "wall_ms_per_frame": wall_ms}
	print("perf ", JSON.stringify(res))
	for k in BUDGET:
		print("%-24s %12.2f  budget %12.2f  %s" % [k, res[k], BUDGET[k], "ok" if res[k] <= BUDGET[k] else "OVER"])
	quit()
