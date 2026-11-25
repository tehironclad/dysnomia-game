extends SceneTree
## Territory load time: how long the scene change blocks, and the hitches after it.
##   godot --headless --path . -s res://tools/load_time.gd -- [--qing=0x…] [--cold] [--frames=240] [--quality=N]
## Under xvfb + lavapipe (no --headless) it also counts shader compiles and rendering.
## --cold removes this territory's and its neighbours' cached grounds/roads first (a first visit).
## Prints the build stages ([Load] line from LoadProfile) and one "load {json}" line:
##   block_ms   the frame the scene change runs in (the game is frozen this long)
##   first_ms   from the change until the first frame after it is drawn
##   hitch_ms   the time spent in frames over 3 × the settled median over the next frames
##   settle_ms  when frames settle (the last frame over that threshold), from the change

var _qing := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
var _frames := 240
var _cold := false
var _preload := true  ## as the warp does: the scene's resources load on a thread first (--no-preload: the old way)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a == "--cold":
			_cold = true
		elif a == "--no-preload":
			_preload = false
	_run.call_deferred()


func _run() -> void:
	var reg: Node = root.get_node("Registry")
	var q: Dictionary = reg.get_territory(_qing)
	if q.is_empty():
		print("unknown territory")
		quit(1)
		return
	if _cold:
		var addrs := [String(q["address"])]
		var found: Dictionary = load("res://scripts/world/border/neighbours.gd").find(q, reg.all())
		for side in found:
			addrs.append(String(found[side]["address"]))
		var n := 0
		for dir in ["user://cache/terrain", "user://cache/roads", "user://cache/ground"]:
			var d := DirAccess.open(dir)
			if d == null:
				continue
			for f in d.get_files():
				for a in addrs:
					if f.to_lower().contains(a.to_lower().substr(2)):
						d.remove(f)
						n += 1
		print("cold: removed %d cached files" % n)
	for i in 10:
		await process_frame
	var pre_ms := 0.0
	var held: Resource = null
	if _preload:
		var tp := Time.get_ticks_usec()
		var path := "res://scenes/territory/territory_v2.tscn"
		ResourceLoader.load_threaded_request(path)
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await process_frame
		held = ResourceLoader.load_threaded_get(path)
		pre_ms = (Time.get_ticks_usec() - tp) / 1000.0
	var t0 := Time.get_ticks_usec()
	load("res://scripts/core/travel.gd").go(self, _qing)
	var dts: Array = []
	var prev := t0
	var block_ms := 0.0
	var first_ms := 0.0
	for i in _frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - prev) / 1000.0
		prev = now
		dts.append(dt)
		if i == 0:
			block_ms = dt
		if i == 1:
			first_ms = (now - t0) / 1000.0
	# Settled median: the last third of the run.
	var tail: Array = dts.slice(dts.size() * 2 / 3)
	tail.sort()
	var med: float = tail[tail.size() / 2] if not tail.is_empty() else 16.0
	var thr := maxf(med * 3.0, 50.0)
	var hitch := 0.0
	var settle := 0.0
	var big := 0
	var acc := 0.0
	var worst := 0.0
	for i in range(1, dts.size()):
		acc += float(dts[i])
		if float(dts[i]) > thr:
			hitch += float(dts[i])
			settle = block_ms + acc
			big += 1
		worst = maxf(worst, float(dts[i]))
	var res := {"block_ms": snappedf(block_ms, 1.0), "first_ms": snappedf(first_ms, 1.0), "hitch_ms": snappedf(hitch, 1.0),
		"hitches": big, "worst_after_ms": snappedf(worst, 1.0), "settle_ms": snappedf(maxf(settle, first_ms), 1.0),
		"median_ms": snappedf(med, 0.1), "cold": _cold, "quality": root.get_node("Config").graphics_quality,
		"renderer": RenderingServer.get_current_rendering_method(), "preload_thread_ms": snappedf(pre_ms, 1.0),
		"longest_freeze_ms": snappedf(maxf(block_ms, worst), 1.0)}
	var lp = load("res://scripts/core/load_profile.gd")
	if not lp.last_report.is_empty():
		res["build_ms"] = snappedf(float(lp.last_report["total_ms"]), 1.0)
	print("load ", JSON.stringify(res))
	quit(0)
