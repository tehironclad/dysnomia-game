extends SceneTree
## Renders a scene and saves the viewport to PNG (needs a real renderer:
## run under xvfb-run with Vulkan, e.g. lavapipe; see CLAUDE.md).
##   godot --path . -s res://tools/screenshot.gd -- --out=/abs/shot.png
##       [--scene=<the main scene: the front door>] [--qing=0x…] [--frames=90] [--quality=0..3]
##       [--session=0x…] [--open=su|beat|world|steward] (with --view=hud: a move's panel, previewed only)
##       [--toggle=guide|help] (with --view=hud: show that panel)
##       (the front door: --open=void|identity|guide|opps shows that panel on the right)
##       [--dive=<arcade catalog id> --dive-phase=push|warp|inside|menu --classic] (an arcade place:
##       dive into that cabinet; the attract demo plays, nothing is paid)
##       [--seat=pool|cards --seat-phase=aim|roll|overhead|seated|enter] (an arcade place or the pub:
##       sit at that table in first person, practice mode; nothing is posted or signed)
##       [--near=<arcade catalog id> --near-back=<m>] (stand in front of that cabinet: its floating title shows)
##       [--fair=<midway game id>|rocket --fair-phase=aim|play|result|board|buy|strip] (a territory: play that fair game
##       in first person, a scripted practice round held mid-play or on its result screen; rocket: the
##       rocket's 7-light board, with --fair-codes=1,2,3 lit as a preview; buy: the stall's ticket choice;
##       strip: its price plaque and prompt with a strip's plays left, labelled PREVIEW. Nothing is paid or posted)
##       [--field-search=<text> --field-filter=mine,joined,fair,yue,near,tier:N] (the Field: the finder
##       with that search and those filters, the top result selected and hovered)
##       [--access=<AccessGates goal> --access-fee=<wei>] (any scene: the AccessSteps overlay for that
##       goal, read live: e.g. fair_ticket, room_post; with --qing the room/fair is that QING's)
##       [--invite=panel|seated|play|result] (game invites over a game server: with --net-url, --net-key=<test key>
##       and --session=<its wallet>; a net_bot invites this wallet. panel: the notification panel with the
##       invite; seated: accept → the walk to the table → seated, the bot's first move replayed; play: then this
##       side's shot from the seat, through the server, rolling; result: accept,
##       confirm the stake, play to the end (this side stands), the panel over the table with the wager's
##       chain check. Nothing is signed on chain or paid)
## With --qing, the territory is loaded from the chain first (read-only).

var _out := ""
var _scene := String(ProjectSettings.get_setting("application/run/main_scene", "res://scenes/ui/front_door.tscn"))
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
var _near_back := 2.2  ## --near-back=<m>: how far in front of the cabinet to stand
var _fair := ""
var _fair_phase := "play"
var _fair_codes: Array = []
var _chat := ""  # bar | history: the chat bar open (with --chat-text) or the history panel
var _chat_text := ""
var _chat_replay := 0  # replay the room's last N real lines as new (bubbles, echoes rising, feed rows)
var _field_search := ""
var _field_filter: Array = []
var _access := ""
var _access_fee := ""
var _invite := ""  # panel | seated | result
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
		elif a.begins_with("--fair="):
			_fair = a.substr(7)
		elif a.begins_with("--fair-phase="):
			_fair_phase = a.substr(13)
		elif a.begins_with("--fair-codes="):
			for c in a.substr(13).split(","):
				_fair_codes.append(int(c))
		elif a.begins_with("--near="):
			_near = a.substr(7)
		elif a.begins_with("--near-back="):
			_near_back = float(a.substr(12))
		elif a.begins_with("--chat="):
			_chat = a.substr(7)
		elif a.begins_with("--chat-text="):
			_chat_text = a.substr(12)
		elif a.begins_with("--chat-replay="):
			_chat_replay = int(a.substr(14))
		elif a.begins_with("--field-search="):
			_field_search = a.substr(15)
		elif a.begins_with("--field-filter="):
			_field_filter = Array(a.substr(15).split(",", false))
		elif a.begins_with("--access="):
			_access = a.substr(9)
		elif a.begins_with("--invite="):
			_invite = a.substr(9)
		elif a.begins_with("--access-fee="):
			_access_fee = a.substr(13)
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
	if _warp != "":
		for i in 5:
			await process_frame
		load("res://scripts/core/warp.gd").to(self, _warp)
	if _open != "":
		for i in 30:
			await process_frame
		var acts = current_scene.get("actions") if current_scene else null
		if current_scene and current_scene.has_method("open_panel"):
			current_scene.open_panel(_open)  # the front door: void | identity | guide | opps
		elif _open == "steward" and current_scene and current_scene.get("act_loop"):
			current_scene.act_loop.open_steward()  # the Steward's words (ActLoop)
		elif acts and acts.has_method("open_" + _open):
			acts.call("open_" + _open)
		elif acts:
			# The room and the Void are places now (a door, not a panel): render the scene instead.
			push_warning("--open=%s: no such panel here (rooms and the Void are places: --scene=res://scenes/places/…)" % _open)
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
	if _toggle != "":
		for i in 30:
			await process_frame  # the scene (and its panels) must exist first
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
			current_scene.preview_near(_near, _near_back)
	if _seat != "":
		for i in 20:
			await process_frame
		if current_scene and current_scene.has_method("preview_seat"):
			current_scene.preview_seat(_seat, _seat_phase)
	if _fair != "":
		var t0 := Time.get_ticks_msec()
		var fs = null
		while Time.get_ticks_msec() - t0 < 90000:
			fs = current_scene.find_child("AffectionFair", true, false) if current_scene else null
			if fs and fs.get("_fair") != null and int(fs.get("_tier")) >= (3 if _fair == "rocket" else 2):
				break
			await process_frame
		if fs:
			fs.preview_game(_fair, _fair_phase, _fair_codes)
			await create_timer(2.5).timeout
	if _chat != "" or _chat_replay > 0:
		await _chat_preview()
	if _field_search != "" or not _field_filter.is_empty():
		for i in 10:
			await process_frame
		if current_scene and current_scene.has_method("preview"):
			current_scene.preview(_field_search, _field_filter)
			var t1 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t1 < 30000 and (current_scene.get("yue_state") == "reading" or current_scene.get("joined_state") == "reading"):
				await process_frame
			current_scene.preview(_field_search, [])
	if _access != "":
		for i in 10:
			await process_frame
		var ctx := {}
		var q := _qing if _qing != "" else String(root.get_node("GameManager").territory_address)
		if q != "":
			ctx["qing"] = q
			ctx["room_name"] = String(root.get_node("Registry").get_territory(q).get("name", ""))
		if _access_fee != "":
			ctx["fee_wei"] = _access_fee
		var steps = load("res://scripts/ui/access/access_steps.gd").popup(current_scene, _access, ctx)
		var t2 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t2 < 20000:
			var busy := false
			for s in steps.result.get("steps", []):
				if s["status"] == "checking":
					busy = true
			if not busy and not steps.result.is_empty():
				break
			await process_frame
	if _invite != "":
		await _invite_preview()
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
	while (cf.current == null or not cf.current.is_loaded()) and Time.get_ticks_msec() - t0 < 240000:  # lavapipe runs a few fps: the reads take longer
		await process_frame
	for i in 4:
		await process_frame
	if cf.current and _chat_replay > 0:
		var ls: Array = cf.current.lines.slice(maxi(0, cf.current.lines.size() - _chat_replay))
		await cf.current.resolve_wallets(ls)
		cf.hud.feed._on_arrived(ls)
		for l in ls:
			cf.bubble.emit(l)
			for i in 3:
				await process_frame
	if _chat == "bar":
		cf.hud.bar.open(_chat_text)
	elif _chat == "history":
		cf.hud.feed.toggle_history()



## Game invites over a game server (Invites): waits for the bot's invite, then
## shows the panel, or accepts and follows the walk to the table, or plays the
## game out and opens the panel over the table with the wager line.
func _invite_preview() -> void:
	var inv = root.get_node("Invites")
	var t0 := Time.get_ticks_msec()
	var pending := ""
	while pending == "" and Time.get_ticks_msec() - t0 < 120000:
		for i in inv.invites.values():
			if i["state"] == "pending" and i["to"] == inv.me():
				pending = String(i["id"])
		await process_frame
	print("[shot] invite: ", pending if pending != "" else "none arrived")
	if pending == "":
		return
	if _invite == "panel":
		for i in 30:
			await process_frame
		var p = current_scene.find_child("NotificationPanel", true, false) if current_scene else null
		if p:
			p.open()
		await create_timer(2.0).timeout  # the online list answers
		return
	inv.answer(pending, "accept")
	var mid := ""
	while mid == "" and Time.get_ticks_msec() - t0 < 120000:
		mid = String(inv.invites[pending].get("match", ""))
		await process_frame
	# the walk through the door, then seated
	var seat = null
	while Time.get_ticks_msec() - t0 < 150000:
		seat = current_scene.get("seat") if current_scene else null
		if seat and seat.is_inside():
			break
		await process_frame
	print("[shot] seated: ", seat != null and seat.is_inside(), " match ", mid)
	var m: Dictionary = inv.match_dict(mid)
	if _invite == "seated" or _invite == "play":
		if m.get("status") == "confirm":
			inv.confirm_stake(mid, true)
		# the bot (player 0) breaks: wait for its shot to be replayed here, and catch it rolling
		while Time.get_ticks_msec() - t0 < 150000 and not m.has("last_shot") and int(m.get("moves", 0)) < 3:
			await process_frame
		if _invite == "play":
			# then this side's turn: a shot from the seat (PoolSeat → the server → both tables)
			var me: int = (m["players"] as Array).find(inv.me())
			var ps = current_scene.get("pool_seat")
			while Time.get_ticks_msec() - t0 < 200000 and not (m.get("status") == "playing" and int(m["game"].turn) == me and ps.state == "aim" and ps.mode == "play"):
				await process_frame
			var before := int(m.get("moves", 0))
			ps.charge = 0.55
			ps._release()
			print("[shot] my shot sent: ", ps.seat.status.text)
			while Time.get_ticks_msec() - t0 < 220000 and int(m.get("moves", 0)) == before:
				await process_frame
			print("[shot] replayed: ", m["events"][-1] if not m["events"].is_empty() else "—")
		await create_timer(0.9).timeout
		return
	if m.get("status") == "confirm":
		inv.confirm_stake(mid, true)
	var me: int = (m["players"] as Array).find(inv.me())
	var stood := false
	while Time.get_ticks_msec() - t0 < 200000 and m.get("status") != "over":
		var d = m.get("game")
		if not stood and m.get("status") == "playing" and d != null and d.get("dealt") and int(d.turn) == me:
			stood = true
			inv.send_move(mid, "stand")
		await process_frame
	print("[shot] over: ", m.get("status"), " winner ", m.get("winner"))
	await create_timer(3.0).timeout
	while Time.get_ticks_msec() - t0 < 240000 and m.get("paid") == null and String(m.get("check_note", "")) == "":
		await process_frame  # the wager's chain check (the end block, then the Transfer logs)
	print("[shot] wager: paid=", m.get("paid"), " end block ", m.get("end_block"), " ", m.get("check_note", ""))
	var p = current_scene.find_child("NotificationPanel", true, false) if current_scene else null
	if p:
		p.open()
	await create_timer(1.5).timeout
