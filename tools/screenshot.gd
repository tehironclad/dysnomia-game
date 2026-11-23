extends SceneTree
## Renders a scene and saves the viewport to PNG (needs a real renderer:
## run under xvfb-run with Vulkan, e.g. lavapipe; see CLAUDE.md).
##   godot --path . -s res://tools/screenshot.gd -- --out=/abs/shot.png
##       [--scene=res://scenes/main.tscn] [--qing=0x…] [--frames=90] [--quality=0..3]
## With --qing, the territory is loaded from the chain first (read-only).

var _out := ""
var _scene := "res://scenes/main.tscn"
var _qing := ""
var _frames := 90
var _quality := -1
var _warp := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--qing="):
			_qing = a.substr(7)
		elif a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--warp="):
			_warp = a.substr(7)
		elif a.begins_with("--quality="):
			_quality = int(a.substr(10))
	_run.call_deferred()


func _run() -> void:
	if _quality >= 0:
		root.get_node("Config").graphics_quality = _quality  # 0 = Low (software renderers)
	if _qing != "":
		var cm = root.get_node("ChainManager")
		var done := {"ok": false, "err": ""}
		cm.territory_loaded.connect(func(_d): done["ok"] = true, CONNECT_ONE_SHOT)
		cm.territory_load_failed.connect(func(e): done["err"] = str(e), CONNECT_ONE_SHOT)
		cm.load_territory(_qing)
		var t0 := Time.get_ticks_msec()
		while not done["ok"] and done["err"] == "" and Time.get_ticks_msec() - t0 < 60000:
			await process_frame
		print("territory load ok=%s %s" % [done["ok"], done["err"]])
	change_scene_to_file(_scene)
	if _warp != "":
		for i in 5:
			await process_frame
		load("res://scripts/core/warp.gd").to(self, _warp)
	for i in _frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	quit()
