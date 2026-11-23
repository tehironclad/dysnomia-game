extends SceneTree
## Renders a scene and saves the viewport to PNG (needs a real renderer:
## run under xvfb-run with Vulkan, e.g. lavapipe; see CLAUDE.md).
##   godot --path . -s res://tools/screenshot.gd -- --out=/abs/shot.png
##       [--scene=res://scenes/main.tscn] [--qing=0x…] [--frames=90] [--quality=0..3]
##       [--session=0x…] [--open=su|room|beat|void|world] (with --view=hud: a move's panel, previewed only)
##       [--toggle=guide|help] (with --view=hud: show that panel)
## With --qing, the territory is loaded from the chain first (read-only).

var _out := ""
var _scene := "res://scenes/main.tscn"
var _qing := ""
var _frames := 90
var _quality := -1
var _warp := ""
var _session := ""
var _open := ""
var _toggle := ""
var _head := ""  # preview a head on the player (local only), e.g. alien or rat:crown  # a scene panel with toggle(): guide | help  # su | room | beat | void: open that move's panel (previews only)


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
		elif a.begins_with("--session="):
			_session = a.substr(10)  # read-only: view a wallet's identity (no signing)
		elif a.begins_with("--head="):
			_head = a.substr(7)
		elif a.begins_with("--toggle="):
			_toggle = a.substr(9)
		elif a.begins_with("--open="):
			_open = a.substr(7)
		elif a.begins_with("--warp="):
			_warp = a.substr(7)
		elif a.begins_with("--quality="):
			_quality = int(a.substr(10))
	_run.call_deferred()


func _run() -> void:
	if _quality >= 0:
		root.get_node("Config").graphics_quality = _quality  # 0 = Low (software renderers)
		root.get_node("Config").apply()
	if _qing != "":
		var gm = root.get_node("GameManager")
		gm.territory_address = _qing
		gm.is_chain_sourced = true
	change_scene_to_file(_scene)
	if _session != "":
		root.get_node("Session").set_wallet(_session)
		var t0 := Time.get_ticks_msec()
		while root.get_node("Session").readiness == null and Time.get_ticks_msec() - t0 < 60000:
			await process_frame
		var door = current_scene
		if door and door.get("_onboarding") != null:
			door._onboarding.visible = true
	if _warp != "":
		for i in 5:
			await process_frame
		load("res://scripts/core/warp.gd").to(self, _warp)
	if _open != "":
		for i in 30:
			await process_frame
		var acts = current_scene.get("actions") if current_scene else null
		if acts:
			acts.call("open_" + _open)
	if _head != "" and current_scene:
		# With a session: the wallet's local head choice, exactly as the identity
		# card's picker stores it (the chain-derived head is the default).
		if _session != "":
			load("res://scripts/player/avatar_heads.gd").set_local_choice(_session, _head.split(":")[0])
			root.get_node("Session").changed.emit()
		else:
			for i in 20:
				await process_frame
			var model = current_scene.get_node_or_null("Player/PlayerModel")
			if model:
				var parts := _head.split(":")
				model.set_head(parts[0], Array(parts[1].split(",")) if parts.size() > 1 else [])
	if _toggle != "" and current_scene and current_scene.get(_toggle) != null:
		current_scene.get(_toggle).toggle()
	for i in _frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	quit()
