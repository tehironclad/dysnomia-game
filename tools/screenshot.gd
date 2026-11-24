extends SceneTree
## Renders a scene and saves the viewport to PNG (needs a real renderer:
## run under xvfb-run with Vulkan, e.g. lavapipe; see CLAUDE.md).
##   godot --path . -s res://tools/screenshot.gd -- --out=/abs/shot.png
##       [--scene=res://scenes/main.tscn] [--qing=0x…] [--frames=90] [--quality=0..3]
##       [--session=0x…] [--open=su|room|beat|void|world] (with --view=hud: a move's panel, previewed only)
##       [--toggle=guide|help] (with --view=hud: show that panel)
##       [--dive=<arcade catalog id> --dive-phase=push|warp|inside|menu --classic] (an arcade place:
##       dive into that cabinet; the attract demo plays, nothing is paid)
##       [--seat=pool|cards --seat-phase=aim|roll|overhead|seated|enter] (an arcade place or the pub:
##       sit at that table in first person, practice mode; nothing is posted or signed)
##       [--near=<arcade catalog id>] (stand in front of that cabinet: its floating title shows)
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
var _head := ""
var _dive := ""  # an arcade place: dive into the cabinet running this catalog id
var _dive_phase := "inside"  # push | warp | inside | menu
var _classic := false
var _seat := ""
var _seat_phase := "aim"
var _near := ""
var _chat := ""  # bar | history: the chat bar open (with --chat-text) or the history panel
var _chat_text := ""
var _chat_replay := 0  # replay the room's last N real lines as new (bubbles, echoes rising, feed rows)
var _flash := false  # preview a head on the player (local only), e.g. alien or rat:crown  # a scene panel with toggle(): guide | help  # su | room | beat | void: open that move's panel (previews only)


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
		elif a.begins_with("--dive="):
			_dive = a.substr(7)
		elif a.begins_with("--dive-phase="):
			_dive_phase = a.substr(13)
		elif a.begins_with("--seat="):
			_seat = a.substr(7)
		elif a.begins_with("--seat-phase="):
			_seat_phase = a.substr(13)
		elif a.begins_with("--near="):
			_near = a.substr(7)
		elif a.begins_with("--chat="):
			_chat = a.substr(7)
		elif a.begins_with("--chat-text="):
			_chat_text = a.substr(12)
		elif a.begins_with("--chat-replay="):
			_chat_replay = int(a.substr(14))
		elif a == "--classic":
			_classic = true
		elif a == "--flashlight":
			_flash = true
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
		elif _open == "chat" and current_scene and current_scene.get("chat_ctl"):
			current_scene.chat_ctl.open()  # a hall or the Void
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
	if _flash and current_scene and current_scene.get_node_or_null("Player"):
		for i in 10:
			await process_frame
		current_scene.get_node("Player")._toggle_flashlight()
	if _toggle != "" and current_scene and current_scene.get(_toggle) != null:
		current_scene.get(_toggle).toggle()
	if _dive != "":
		for i in 20:
			await process_frame
		if current_scene and current_scene.has_method("preview_dive"):
			current_scene.preview_dive(_dive, _dive_phase, _classic)
	if _near != "":
		for i in 20:
			await process_frame
		if current_scene and current_scene.has_method("preview_near"):
			current_scene.preview_near(_near)
	if _seat != "":
		for i in 20:
			await process_frame
		if current_scene and current_scene.has_method("preview_seat"):
			current_scene.preview_seat(_seat, _seat_phase)
	if _chat != "" or _chat_replay > 0:
		await _chat_preview()
	for i in _frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	quit()


## The room chat (ChatFeed): waits for the feed, replays the last real lines
## as if new (each keeps its own block), opens the bar or the history. Nothing
## is posted or signed.
func _chat_preview() -> void:
	var cf = root.get_node("ChatFeed")
	var t0 := Time.get_ticks_msec()
	while (cf.current == null or not cf.current.is_loaded()) and Time.get_ticks_msec() - t0 < 90000:
		await process_frame
	for i in 30:
		await process_frame
	if cf.current and _chat_replay > 0:
		var ls: Array = cf.current.lines.slice(maxi(0, cf.current.lines.size() - _chat_replay))
		await cf.current.resolve_wallets(ls)
		cf.hud.feed._on_arrived(ls)
		for l in ls:
			cf.bubble.emit(l)
			for i in 20:
				await process_frame
	if _chat == "bar":
		cf.hud.bar.open(_chat_text)
	elif _chat == "history":
		cf.hud.feed.toggle_history()

