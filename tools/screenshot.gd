extends SceneTree
## Renders a scene and saves the viewport to PNG (needs a real renderer:
## run under xvfb-run with Vulkan, e.g. lavapipe; see CLAUDE.md).
##   godot --path . -s res://tools/screenshot.gd -- --out=/abs/shot.png
##       [--scene=<the main scene: the front door>] [--qing=0x…] [--frames=90] [--quality=0..3]
##       [--session=0x…] [--open=su|beat|world|steward] (with --view=hud: a move's panel, previewed only)
##       [--toggle=guide|help] (with --view=hud: show that panel)
##       (the front door: --open=void|identity|guide|opps shows that panel on the right)
##       [--update=x.y.z] (the front door: the "new version" notice as if the site named x.y.z, labelled PREVIEW)
##       [--daily=card|board|play] (today's challenge: the front door's card, its board panel, or the
##       DailyPlay screen with a practice run held mid-play; the seed block and the board are read live)
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
##       [--tg=dock|history|bar|tv --tg-text=…] (the Telegram bridge, with --net-url of a server pointed at
##       tools/tg_mock.gd: wait for its Telegram lines, then the chat dock's Telegram tab, its history, the bar in
##       Telegram mode (needs --net-key) or the pub's TV (with --view=tv). Nothing is sent)
##       [--activity=N] (online play, with --net-url: wait for N activity feed lines (bots make them) and the remote
##       players' name tags to be read from the chain; prints them. Debug builds: --net-lau-of=<test wallet>=<real wallet>
##       shows a test bot with a real wallet's LAU name, marked "(test)")
##       [--move=dolly|orbit|crane|pan --move-amt=<m or deg> --move-pivot=<m>] (the last --frames frames: move
##       the active 3D camera from where the view put it: dolly = forward by amt m, orbit = amt degrees around
##       the point --move-pivot m ahead, crane = up by amt m still facing that point, pan = turn amt degrees.
##       Linear. For trailers: run with --write-movie <abs dir>/f.png --fixed-fps 30 and keep the last --frames)
##       [--hide-ui] (hide every 2D layer while the frames run: a clean picture for a trailer)
##       [--away-since=<block>] (with --session: the "while you were away" card, the baseline read from the chain
##       at that block, labelled PREVIEW; front door: the right column; a territory: the arrival card. Nothing stored)
##       [--alert-replay=N] (a territory with --session: the room's real lines (N, read further back if needed) pass
##       through the mention alert again; a line naming the session's LAU makes the real toast, marked "replayed")
##       [--alert-panel] (the notification panel open: the away card at its top)
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
var _activity := 0  # wait for this many activity feed lines (online play: --net-url + bots)
var _update := ""  # the front door: preview the update notice for this version
var _move := ""  # dolly | orbit | crane | pan: a camera move over the last --frames frames
var _move_amt := 0.0
var _move_pivot := 30.0
var _hide_ui := false
var _daily := ""  # card | board | play: today's challenge (DailyCard, DailyBoard, DailyPlay)
var _away := false  # --away-since (read by Alerts itself): wait for the card
var _alert_replay := 0
var _alert_panel := false
var _tg := ""  # dock | bar | history | tv: wait for the server's Telegram lines (--net-url + a bridging server), then show them
var _tg_text := ""
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
		elif a.begins_with("--activity="):
			_activity = int(a.substr(11))
		elif a.begins_with("--invite="):
			_invite = a.substr(9)
		elif a.begins_with("--daily="):
			_daily = a.substr(8)
			if _daily == "play":
				_scene = "res://scenes/ui/daily_play.tscn"
		elif a.begins_with("--update="):
			_update = a.substr(9)
		elif a.begins_with("--away-since="):
			_away = true
		elif a.begins_with("--alert-replay="):
			_alert_replay = int(a.substr(15))
		elif a == "--alert-panel":
			_alert_panel = true
		elif a.begins_with("--tg="):
			_tg = a.substr(5)
		elif a.begins_with("--tg-text="):
			_tg_text = a.substr(10)
		elif a.begins_with("--access-fee="):
			_access_fee = a.substr(13)
		elif a.begins_with("--move="):
			_move = a.substr(7)
		elif a.begins_with("--move-amt="):
			_move_amt = float(a.substr(11))
		elif a.begins_with("--move-pivot="):
			_move_pivot = float(a.substr(13))
		elif a == "--hide-ui":
			_hide_ui = true
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
	if _activity > 0:
		await _activity_preview()
	if _daily != "":
		await _daily_preview()
	if _tg != "":
		await _tg_preview()
	if _update != "":
		for i in 10:
			await process_frame
		if current_scene and current_scene.has_method("preview_update"):
			current_scene.preview_update(_update)
	var cam: Camera3D = null
	var from := Transform3D()
	if _away or _alert_replay > 0 or _alert_panel:
		await _alerts_preview()
	for i in _frames:
		if _move != "":
			var c := root.get_viewport().get_camera_3d()
			if c != cam:
				cam = c  # the view's camera (or one a scene made current since)
				from = c.global_transform if c else Transform3D()
			if cam:
				cam.global_transform = _moved(from, float(i) / float(maxi(1, _frames - 1)))
		if _hide_ui:
			_hide_layers(root)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	quit()


## --move: the camera's transform at t (0..1, linear) of the move from `from`.
func _moved(from: Transform3D, t: float) -> Transform3D:
	var e := t  # linear: a trailer cuts mid-move
	var fwd := -from.basis.z
	var pivot := from.origin + fwd * _move_pivot
	match _move:
		"dolly":
			return Transform3D(from.basis, from.origin + fwd * _move_amt * e)
		"orbit":
			var r := Basis(Vector3.UP, deg_to_rad(_move_amt) * e)
			return Transform3D(r * from.basis, pivot + r * (from.origin - pivot))
		"crane":
			var o := from.origin + Vector3.UP * _move_amt * e
			return Transform3D(Basis.looking_at(pivot - o, Vector3.UP), o)
		"pan":
			return Transform3D(Basis(Vector3.UP, deg_to_rad(_move_amt) * e) * from.basis, from.origin)
	return from


## --hide-ui: every CanvasLayer off (some are made late, so this runs each frame).
func _hide_layers(n: Node) -> void:
	for c in n.get_children():
		if c is Viewport:
			continue  # a cabinet's screen or a picture in the world: its own 2D stays
		if c is CanvasLayer:
			c.visible = false
		elif c is Control and c.get_parent() == root:
			c.visible = false
		else:
			_hide_layers(c)


## Today's challenge: waits for the day's seed block to be read (or fail), then shows the card,
## the board panel or a practice run in DailyPlay. Nothing is submitted.
func _daily_preview() -> void:
	for i in 10:
		await process_frame
	var day: String = load("res://scripts/games/daily/daily_run.gd").today()
	var seed_script = load("res://scripts/games/daily/daily_seed.gd")
	var t0 := Time.get_ticks_msec()
	while seed_script.peek(day)["state"] == "checking" and Time.get_ticks_msec() - t0 < 90000:
		await process_frame
	print("[shot] daily %s: %s" % [day, seed_script.peek(day)])
	if _daily == "play" and current_scene and current_scene.has_method("preview_play"):
		current_scene.preview_play()
	elif current_scene and current_scene.has_method("preview_daily"):
		current_scene.preview_daily(_daily)
	await create_timer(3.0).timeout


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



## "While you were away" and the alerts (Alerts): waits for the card (read from the chain:
## the baseline at --away-since's block), replays the room's real lines through the mention
## alert, opens the notification panel. Nothing is signed or stored.
func _alerts_preview() -> void:
	var al = root.get_node("Alerts")
	var t0 := Time.get_ticks_msec()
	if _away:
		while al.away_state != "ready" and Time.get_ticks_msec() - t0 < 300000:
			await process_frame
		print("[shot] away card: %s" % al.away_state)
		for line in load("res://scripts/state/away_diff.gd").lines(al.away_card):
			print("[shot]   ", line)
	if _alert_replay > 0:
		var cf = root.get_node("ChatFeed")
		while (cf.current == null or not cf.current.is_loaded()) and Time.get_ticks_msec() - t0 < 300000:
			await process_frame
		while (current_scene == null or current_scene.get("is_built") == false) and Time.get_ticks_msec() - t0 < 300000:
			await process_frame
		print("[shot] room read (%d lines), territory built · %.0f s" % [cf.current.lines.size() if cf.current else -1, (Time.get_ticks_msec() - t0) / 1000.0])
		if cf.current:
			await cf.current.ensure_history(_alert_replay)
			var hits: int = al.replay_lines(_alert_replay)
			print("[shot] replayed %d real lines: %d named %s" % [mini(_alert_replay, cf.current.lines.size()), hits, root.get_node("Session").player.username if root.get_node("Session").player else "—"])
		for i in 3:
			await process_frame  # a toast lives AlertGate.LIFE_S: pass --frames=1 on a slow renderer
	if _alert_panel:
		for i in 20:
			await process_frame
		var p = current_scene.find_child("NotificationPanel", true, false) if current_scene else null
		if p:
			p.open()


## The Telegram bridge (NetTg): waits for the game server's Telegram lines (a server with
## TELEGRAM_* pointed at tools/tg_mock.gd), then shows them in the chat dock's Telegram tab
## (dock), its history (history), the bar in Telegram mode (bar, --tg-text=…; needs --net-key
## to be signed in) or just lets the pub's TV draw them (tv). Nothing is sent.
func _tg_preview() -> void:
	var net = root.get_node("Net")
	var cf = root.get_node("ChatFeed")
	var t0 := Time.get_ticks_msec()
	while (net.tg_lines.size() < 3 or (_tg == "bar" and not net.can_telegram())) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	print("[shot] telegram: %d lines, signed in: %s" % [net.tg_lines.size(), net.can_telegram()])
	for i in 20:
		await process_frame
	if _tg == "tv":
		return
	cf.hud.feed.set_source("telegram")
	if _tg == "history":
		cf.hud.feed.toggle_history()
	elif _tg == "bar":
		cf.set_mode("telegram")
		cf.hud.bar.open(_tg_text)
	for i in 10:
		await process_frame


## The activity feed (Net.activity): waits for `_activity` lines from the server and the
## chain (bots make them: tools/net_bot.gd), and for remote players' name tags to be read.
func _activity_preview() -> void:
	var net = root.get_node("Net")
	var t0 := Time.get_ticks_msec()
	while net.activity.items.size() < _activity and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 20000:
		var reading := false
		for p in net.client.peers.values():
			if String(p.get("wallet", "")) != "" and String(net.names.record(String(p["wallet"])).get("state", "reading")) == "reading":
				reading = true
		if not reading:
			break
		await process_frame
	print("[shot] activity: %d lines" % net.activity.items.size())
	for it in net.activity.items:
		print("[shot]   ", it["text"])
	var pres = current_scene.find_child("NetPresence", true, false) if current_scene else null
	if pres:
		for r in pres.remotes.values():
			print("[shot]   tag: ", r.tag_text())
	var feed = current_scene.find_child("ActivityFeed", true, false) if current_scene else null
	if feed:
		feed.replay_recent()  # lines that arrived a minute apart, on one frame (each is a real event)


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
