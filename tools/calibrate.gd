extends SceneTree
## The automatic graphics on this machine, as a first launch would run them (needs a
## renderer: xvfb + lavapipe, or a real GPU):
##   xvfb-run … godot --path . --resolution 1280x720 -s res://tools/calibrate.gd -- [--qing=0x…]
##       [--start=N] [--follow=30] [--no-calibrate] [--target=30|60]
## Loads the territory (staged, as in play), runs the calibration (CalibrationRun) from
## level N (default: the hardware's guess), then follows in play for --follow seconds with
## dynamic resolution and the level steps, printing Config.status_line() each second.
## Writes user://settings.cfg like a first launch would.

var _qing := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
var _start := -1
var _follow := 30.0
var _calibrate := true
var _target := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7)
		elif a.begins_with("--start="):
			_start = int(a.substr(8))
		elif a.begins_with("--follow="):
			_follow = float(a.substr(9))
		elif a == "--no-calibrate":
			_calibrate = false
		elif a.begins_with("--target="):
			_target = int(a.substr(9))
	_run.call_deferred()


func _run() -> void:
	var cfg: Node = root.get_node("Config")
	load("res://scripts/world/territory_v2.gd").force_staged = true
	for i in 5:
		await process_frame
	var rec: Dictionary = cfg.recommend(RenderingServer.get_video_adapter_type(), RenderingServer.get_video_adapter_name(),
		OS.get_processor_count(), float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
		RenderingServer.get_current_rendering_method())
	print("[calibrate] GPU: %s · guess: %s" % [cfg.gpu_line(), cfg.QUALITY_NAMES[rec["quality"]]])
	cfg.auto_quality = true
	cfg.target_fps_setting = _target
	cfg.graphics_quality = rec["quality"] if _start < 0 else _start
	cfg.apply()
	load("res://scripts/core/travel.gd").go(self, _qing)
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.get("is_built") != true) and Time.get_ticks_msec() - t0 < 600000:
		await process_frame
	print("[calibrate] built in %d ms" % (Time.get_ticks_msec() - t0))
	for i in 30:
		await process_frame
	if _calibrate:
		var tc := Time.get_ticks_msec()
		var run = cfg.calibrate()
		var out: Array = []
		run.finished.connect(func(l, f, r): out.append([l, f, r]))
		while out.is_empty():
			await process_frame
		print("[calibrate] chose %s at %d fps in %.1f s: %s" % [cfg.QUALITY_NAMES[out[0][0]], out[0][1],
			(Time.get_ticks_msec() - tc) / 1000.0, cfg.calib_note])
	cfg.follow_in_tools = true
	cfg.register_scene(current_scene.get_node("WorldEnvironment").environment, current_scene.get_node("Sun"), true)
	var tf := Time.get_ticks_msec()
	var next := 1000
	while Time.get_ticks_msec() - tf < int(_follow * 1000.0):
		await process_frame
		if Time.get_ticks_msec() - tf >= next:
			next += 1000
			print("[follow] %2ds %s" % [next / 1000 - 1, cfg.status_line()])
	cfg.follow_in_tools = false
	quit(0)
