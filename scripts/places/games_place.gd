class_name GamesPlace
extends PlaceBase
## What the arcade and Sunny's Pub share: arcade cabinets you dive into
## (ArcadeDive; 1 Ⓐ a play, paid to this territory's QING and verified on
## chain before the run starts), a
## pool table and a card table played through this QING's room lines, the
## room's chat (T), and an exit back to the territory.

var territory: Dictionary = {}
var qing := ""
var book: TableBook
var cabinets: Array = []
var pool_table: PoolTable3D
var card_table: CardTable3D
var accent := DeepFieldTheme.ICE
var _spots: Array = []  # {at: Vector3, r: float, prompt: Callable, act: Callable}
var _near_spot := -1
var _ui_layer: CanvasLayer
var _pool_panel: TablePanel
var _cards_panel: TablePanel
var dive: ArcadeDive
var seat: TableSeat  ## sitting at the pool or card table (first person)
var pool_seat: PoolSeat
var card_seat: CardSeat
var _cab: ArcadeCabinet
var _running := false
var _busy := false
var _pay_label := ""
var _run_credit: Dictionary = {}
var _last_score := -1
var _last_rank := 0
var _animated_tx := ""
var _near_cab: ArcadeCabinet


func load_territory() -> void:
	var addr := GameManager.territory_address
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			addr = a.substr(7)
	territory = Registry.get_territory(addr)
	if territory.is_empty():
		territory = Registry.all()[0] if Registry.count() > 0 else {}
	qing = String(territory.get("address", "")).to_lower()
	GameManager.territory_address = qing
	GameManager.territory_name = String(territory.get("name", ""))
	if not territory.is_empty():
		accent = DeepField.to_color(DeepField.for_territory(territory)["color"])


## After setup_player/setup_hud: the room's chat (its lines feed the tables) and the UI.
func setup_games(echo_spots: Array) -> void:
	setup_chat("room", territory, 400)
	echoes.spots = echo_spots
	book = TableBook.new(qing)
	chat_ctl.lines_changed.connect(func(ls, _fresh): book.feed(ls))
	book.changed.connect(_on_book)
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 25
	add_child(_ui_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(center)
	var place := String(territory.get("name", ""))
	_pool_panel = TablePanel.new()
	center.add_child(_pool_panel)
	_pool_panel.setup("pool", book, qing, place, _table_blocker)
	_cards_panel = TablePanel.new()
	center.add_child(_cards_panel)
	_cards_panel.setup("cards", book, qing, place, _table_blocker)
	for p in [_pool_panel, _cards_panel]:
		p.closed.connect(_on_panel_closed)
	_build_dive()
	_build_seats()
	Wallet.tx_stage.connect(_on_stage)


# --- Building pieces ----------------------------------------------------------

func add_cabinet(entry: Dictionary, xf: Transform3D) -> ArcadeCabinet:
	var c := ArcadeCabinet.new()
	add_child(c)
	c.transform = xf
	c.setup(entry, accent)
	cabinets.append(c)
	var title := String(entry.get("title", "?"))
	_spots.append({"at": c.play_spot(), "r": 1.1,
		"prompt": func(): return _cabinet_prompt(c, title),
		"act": func(): _open_cabinet(c)})
	return c


func add_pool_table(xf: Transform3D, cloth: Color = Color(0.05, 0.36, 0.2)) -> void:
	pool_table = PoolTable3D.new()
	add_child(pool_table)
	pool_table.transform = xf
	pool_table.build(cloth)
	for sx in [-1.0, 1.0]:
		_spots.append({"at": xf * Vector3(sx * 1.9, 0, 0), "r": 1.3, "prompt": _pool_prompt, "act": func(): _sit("pool")})
	for sz in [-1.0, 1.0]:
		_spots.append({"at": xf * Vector3(0, 0, sz * 1.4), "r": 1.2, "prompt": _pool_prompt, "act": func(): _sit("pool")})


func add_card_table(xf: Transform3D) -> void:
	card_table = CardTable3D.new()
	add_child(card_table)
	card_table.transform = xf
	card_table.build()
	_spots.append({"at": xf.origin, "r": 2.1, "prompt": func(): return "sit at the card table: Twenty-One, first person · cards dealt by the chain", "act": func(): _sit("cards")})


## Any other interactable (the bartender…).
func add_spot(at: Vector3, r: float, prompt: Callable, act: Callable) -> void:
	_spots.append({"at": at, "r": r, "prompt": prompt, "act": act})


static func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, collide: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.position = at
		parent.add_child(body)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
	return mi


static func mat(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func glow(c: Color, e: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


# --- The tables in 3D -----------------------------------------------------------

func _on_book() -> void:
	if pool_table and not (pool_seat and pool_seat.is_active()):
		var m := _latest("pool")
		if m.is_empty() or m["game"] == null:
			pool_table.show_sim(PoolSim.new())
			pool_table.set_caption("" if m.is_empty() else "#%s · open: %s waits for a player" % [m["id"], book.display(m["challenger"])])
		else:
			if m.has("last_shot") and m["last_shot"]["tx"] != _animated_tx:
				_animated_tx = m["last_shot"]["tx"]
				var s: Dictionary = m["last_shot"]
				pool_table.play_shot(s["before"], s["dx"], s["dy"], s["power"])
			elif not pool_table.is_rolling():
				pool_table.show_sim(m["game"].sim)
			pool_table.set_caption(_caption(m))
	if card_table and not (card_seat and card_seat.is_active()):
		var m := _latest("cards")
		var live: bool = not m.is_empty() and m["game"] != null
		var d: Duel21 = m["game"] if live else null
		card_table.show_hands(d.hands if d else [[], []], true)
		var seats: Array = []
		for i in 2:
			var who := "open seat"
			if not m.is_empty() and m["players"][i] != "":
				who = book.display(m["players"][i])
			seats.append({"name": who, "total": Duel21.total(d.hands[i]) if d and d.dealt else -1, "turn": d != null and not d.over() and d.turn == i, "note": " ✓" if d and d.stood[i] else ""})
		card_table.set_seats(seats)
		card_table.set_chips(CardSeat.chips_for(m["stake"]) if not m.is_empty() else 0, ArcadePay.fmt(m["stake"]) if not m.is_empty() and not BigInt.is_zero(m["stake"]) else "")
		card_table.set_dealer(("DEALT BY THE CHAIN\nblock %s" % ArcadeScores.grouped(int(m.get("deal_block", m["created_block"])))) if live else "DEALT BY THE CHAIN")
		card_table.set_caption("" if m.is_empty() else _caption(m))


func _latest(kind: String) -> Dictionary:
	var list := book.of_kind(kind)
	for m in list:
		if m["status"] == "playing":
			return m
	return list[0] if not list.is_empty() else {}


func _caption(m: Dictionary) -> String:
	var vs := "%s vs %s" % [book.display(m["players"][0]), book.display(m["players"][1])]
	match m["status"]:
		"playing":
			return "#%s · %s · %s to play" % [m["id"], vs, book.display(m["players"][TableBook.turn_index(m)])]
		"over":
			return "#%s · %s · %s" % [m["id"], vs, "push" if m["push"] else "%s won" % book.display(m["winner"])]
	return "#%s · %s" % [m["id"], vs]


# --- Who may sign -----------------------------------------------------------------

func _signer_blocker() -> String:
	var b := ChatController._identity_blocker()
	return b if b != "" else ChatController._signer_blocker()


## Table moves are room lines: the room's door applies too.
func _table_blocker() -> String:
	var b := _signer_blocker()
	if b != "":
		return b
	if chat_ctl.room == null or not chat_ctl.room.ok:
		return "Reading this room's door… (T opens the chat, where Join is if the room has a cover)"
	var rb: String = chat_ctl.room.chat_blocker()
	return rb


# --- Interaction ----------------------------------------------------------------

func _any_open() -> bool:
	return (chat_ctl and chat_ctl.is_open()) or (_pool_panel and _pool_panel.is_open()) or (_cards_panel and _cards_panel.is_open()) or (dive and dive.is_active()) or (seat and seat.is_active()) or DoorSequence.active_in(self)


func _process(delta: float) -> void:
	super._process(delta)
	if player == null or _any_open():
		return
	var near_cab: ArcadeCabinet = null
	var near_d := ArcadeCabinet.TITLE_NEAR
	for c in cabinets:
		(c as ArcadeCabinet).set_awake(c.global_position.distance_to(player.global_position) < ArcadeCabinet.NEAR)
		var f: Vector3 = c.play_spot() - player.global_position
		var d := Vector2(f.x, f.z).length()
		if d < near_d:
			near_d = d
			near_cab = c
	if near_cab != _near_cab:
		if _near_cab:
			_near_cab.set_near(false)
		_near_cab = near_cab
		if _near_cab:
			_near_cab.set_near(true)
	if _near_exit:
		_near_spot = -1
		return
	var best := -1
	var best_d := 1e9
	for i in _spots.size():
		var s: Dictionary = _spots[i]
		var d := Vector2(player.global_position.x - s["at"].x, player.global_position.z - s["at"].z).length()
		if d < s["r"] and d < best_d:
			best = i
			best_d = d
	_near_spot = best
	PromptFade.set_text(prompt_label, ("%s  %s" % [ControlsHelp.key_of("interact"), String(_spots[best]["prompt"].call())]) if best >= 0 else "")


func _unhandled_input(event: InputEvent) -> void:
	if seat and seat.is_active():
		if not seat.is_inside() or (_pool_panel and _pool_panel.is_open()) or (_cards_panel and _cards_panel.is_open()):
			return
		get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_cancel"):
			_stand()
		elif event.is_action_pressed("table_lobby"):
			_open_panel(_pool_panel if pool_seat.is_active() else _cards_panel)
		elif pool_seat and pool_seat.is_active():
			pool_seat.handle_input(event)
		elif card_seat and card_seat.is_active():
			card_seat.handle_input(event)
		return
	if dive and dive.is_active():
		if not dive.is_inside():
			return
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_on_escape()
		elif event.is_action_pressed("arcade_view"):
			get_viewport().set_input_as_handled()
			dive.toggle_view()
		elif event.is_action_pressed("arcade_start"):
			get_viewport().set_input_as_handled()
			_start_run()
		return
	if _any_open():
		return
	if event.is_action_pressed("interact") and _near_spot >= 0 and not _near_exit:
		get_viewport().set_input_as_handled()
		prompt_label.text = ""
		_spots[_near_spot]["act"].call()
		return
	super._unhandled_input(event)


func _open_panel(p: TablePanel) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	p.open()


func _on_panel_closed() -> void:
	if seat and seat.is_active():
		# Back to the seat: the aim wants the mouse captured, the card plates want it visible.
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if pool_seat.is_active() else Input.MOUSE_MODE_VISIBLE)
		return
	_resume()


func _resume() -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)




# --- Sitting at a table (first person) ------------------------------------------------
# Walking up to the pool or card table and using it sits you down (TableSeat): pool from behind
# the cue ball (PoolSeat), Twenty-One on your stool (CardSeat). Every live move is still a room line
# through TableBook; the full list (challenge, accept, concede, pay) opens over the seat.

func _pool_prompt() -> String:
	return "sit at the pool table: eight-ball in first person · shots are this room's lines"


func _build_seats() -> void:
	if pool_table == null and card_table == null:
		return
	seat = TableSeat.new()
	seat.name = "TableSeat"
	add_child(seat)
	if pool_table:
		pool_seat = PoolSeat.new()
		pool_seat.name = "PoolSeat"
		add_child(pool_seat)
		pool_seat.setup(self, pool_table, seat, book)
	if card_table:
		card_seat = CardSeat.new()
		card_seat.name = "CardSeat"
		add_child(card_seat)
		card_seat.setup(self, card_table, seat, book)


func _hide_cabinet_titles() -> void:
	if _near_cab:
		_near_cab.set_near(false)
	_near_cab = null


func _sit(kind: String) -> void:
	if seat == null or seat.is_active() or (dive and dive.is_active()):
		return
	player.process_mode = Node.PROCESS_MODE_DISABLED
	prompt_label.text = ""
	_hide_cabinet_titles()
	if kind == "pool" and pool_seat:
		pool_seat.sit()
	elif kind == "cards" and card_seat:
		card_seat.sit()


func _stand() -> void:
	if seat == null or not seat.is_inside():
		return
	if pool_seat and pool_seat.is_active():
		await pool_seat.stand()
	elif card_seat and card_seat.is_active():
		await card_seat.stand()
	_on_book()
	_resume()


## Tools and previews: stand the player `back` metres in front of the cabinet running `id`, facing it.
func preview_near(id: String, back: float = 2.2) -> void:
	for c in cabinets:
		if String(c.entry.get("id", "")) != id:
			continue
		player.global_position = c.to_global(Vector3(0, 0.1, back))
		player.rotation.y = c.global_rotation.y
		var rig := player.get_node_or_null("CameraRig")
		if rig and "_yaw" in rig:
			rig.set("_yaw", c.global_rotation.y)
		return
	push_warning("preview_near: no cabinet runs %s" % id)


## Tools and previews: sit at a table. kind "pool": phase aim | roll | overhead | enter;
## kind "cards": seated | enter. Practice mode (nothing is posted, nothing is signed).
func preview_seat(kind: String, phase: String) -> void:
	var t: Node3D = pool_table if kind == "pool" else card_table
	if t == null:
		push_warning("preview_seat: no %s table here" % kind)
		return
	player.global_position = t.global_transform * Vector3(0, 0.1, 2.0 if kind == "pool" else 2.4)
	await get_tree().process_frame
	if phase == "enter":
		seat.freeze_at = 0.5
	_sit(kind)
	if phase == "enter":
		return
	await seat.entered
	if kind == "pool":
		pool_seat.preview(phase)
	else:
		card_seat.preview(phase)


# --- The arcade -------------------------------------------------------------------
# Using a cabinet dives into it (ArcadeDive). Inside, the game's attract demo plays behind a menu:
# pay (ArcadePay: simulate, sign, verify the receipt, re-read the QING), play a credit, the
# cabinet's high-score board (this computer only), leave. A run hides the menu; game over brings it
# back with the score. Esc ends a run (the score counts), then leaves.

func _cabinet_prompt(c: ArcadeCabinet, title: String) -> String:
	if not c.playable():
		return "dive into %s (Maria's cartridge, full-screen CRT, free)" % title
	var n := ArcadePay.credits(Session.wallet, qing)
	return "dive into %s · %s a play, to this QING%s" % [title, ArcadePay.fee_text(), (" · %d credit%s" % [n, "" if n == 1 else "s"]) if n > 0 else ""]


func _build_dive() -> void:
	dive = ArcadeDive.new()
	dive.name = "ArcadeDive"
	add_child(dive)
	dive.pay_pressed.connect(_pay_credit)
	dive.start_pressed.connect(_start_run)
	dive.leave_pressed.connect(_on_escape)
	dive.view_pressed.connect(func(): dive.toggle_view())
	dive.entered.connect(func():
		if not _running:
			dive.show_menu())


func _open_cabinet(c: ArcadeCabinet) -> void:
	if dive.is_active():
		return
	_cab = c
	_running = false
	_last_score = -1
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_hide_cabinet_titles()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	prompt_label.text = ""
	if c.game and not c.game.game_over.is_connected(_on_game_over):
		c.game.game_over.connect(_on_game_over)
	dive.enter(c, {"qing": qing, "territory": territory, "accent": accent, "model": player.get_node_or_null("PlayerModel")})
	_refresh_play()
	_read_balance()


func _refresh_play(note: String = "") -> void:
	if _cab == null or dive == null:
		return
	var n := ArcadePay.credits(Session.wallet, qing)
	var blocker := ChatController._signer_blocker()  # paying needs a wallet on PulseChain, not a LAU
	var title := String(_cab.entry.get("title", ""))
	dive.menu_title.text = title.to_upper() + " · " + String(territory.get("name", ""))
	dive.menu_blurb.text = String(_cab.entry.get("blurb", ""))
	dive.pay_button.text = "Pay %s for a play" % ArcadePay.fee_text()
	dive.pay_button.visible = _cab.playable() and not _running
	# A credit is a plain AFFECTION.transfer from the wallet: no LAU involved, so only
	# the wallet/chain checks apply (table moves, which are room lines, still need a LAU).
	dive.pay_button.disabled = _busy or ChatController._signer_blocker() != ""
	dive.start_button.text = "Play (uses a credit) · %s" % ControlsHelp.key_of("arcade_start")
	dive.start_button.visible = _cab.playable() and not _running
	dive.start_button.disabled = _busy or n <= 0
	var info := "A play costs %s: AFFECTION.transfer to %s's QING contract (its own balance), checked in the receipt on chain before the game starts. Credits here: %d." % [ArcadePay.fee_text(), String(territory.get("name", "")), n]
	if not _cab.playable():
		info = "This cartridge runs by itself on the Folklore CPU: it shows here for free and takes no credits."
	if _last_score >= 0:
		info = "GAME OVER · score %s%s\n%s" % [ArcadeScores.grouped(_last_score), (" · #%d on this cabinet's board" % _last_rank) if _last_rank > 0 else "", info]
	if blocker != "" and not _running and _cab.playable():
		info += "\n" + blocker
	if note != "":
		info += "\n" + note
	dive.menu_info.text = info
	var playable := _cab.playable()
	dive.scores_title.visible = playable
	dive.scores_label.visible = playable
	if playable:
		var board := ArcadeScores.board(qing, String(_cab.entry.get("id", "")))
		dive.scores_title.text = "%s: the credit's block shows it was paid." % ArcadeScores.LABEL
		dive.scores_label.text = "\n".join(ArcadeScores.lines(board)) if not board.is_empty() else "No paid runs on this cabinet yet (on this computer)."


func _read_balance() -> void:
	if Session.wallet == "":
		return
	var r := await ArcadePay.read_balance(Session.wallet)
	if dive.is_active() and not _running:
		_refresh_play(("Your Ⓐ: %s (AFFECTION.balanceOf, latest block)." % ArcadePay.fmt(r["balance"])) if r["ok"] else "Your Ⓐ balance could not be read: —")


func _pay_credit() -> void:
	if _busy:
		return
	_busy = true
	_pay_label = "Arcade credit at %s (%s)" % [String(territory.get("name", "")), ArcadePay.fee_text()]
	_refresh_play("Paying…")
	var r := await ArcadePay.pay(qing, String(territory.get("name", "")))
	_busy = false
	if r["ok"]:
		var bal: Variant = r.get("qing_balance", null)
		_refresh_play("Paid: the Transfer to the QING is in block %d%s. One credit added." % [r["block"],
			(" · the QING now holds %s" % ArcadePay.fmt(bal)) if bal != null else ""])
	else:
		_refresh_play("Not paid (%s): %s" % [r.get("stage", "?"), r.get("message", "")])


func _start_run() -> void:
	if _cab == null or _running or _busy or not dive.is_inside() or not _cab.playable():
		return
	var credit := ArcadePay.use_credit(Session.wallet, qing)
	if credit.is_empty():
		_refresh_play("No credit left: pay for a play first.")
		return
	_running = true
	_busy = true
	_run_credit = credit
	_last_score = -1
	var cab := _cab
	var seed := ArcadeWorld.seed_from_tx(String(credit["tx"]))
	if dive.world:
		seed = await dive.world.prepare_run(credit)
	_busy = false
	if _cab != cab:
		return
	_cab.start_run(seed)
	dive.set_running(true, "PAID RUN · credit tx %s · block %s · %s to this QING, verified in the receipt" % [ArcadeScores.short(String(credit["tx"])), ArcadeScores.grouped(int(credit.get("block", 0))), ArcadePay.fee_text()])
	_refresh_play()


func _on_game_over(score: int) -> void:
	if not _running:
		return
	_running = false
	_last_score = score
	_last_rank = 0
	if not _run_credit.is_empty() and _cab:
		_last_rank = ArcadeScores.record(qing, String(_cab.entry.get("id", "")), {
			"score": score, "wallet": Session.wallet.to_lower(), "tx": String(_run_credit["tx"]),
			"block": int(_run_credit.get("block", 0)), "at": int(Time.get_unix_time_from_system()),
		})
	_run_credit = {}
	dive.set_running(false)
	_refresh_play()


## Esc inside a cabinet: ends a live run (its score counts), otherwise leaves.
func _on_escape() -> void:
	if _busy and _running:
		return
	if _running and _cab and _cab.game and _cab.game.playing:
		_cab.game.end_game()
		return
	_close_play()


func _close_play() -> void:
	if not dive.is_active():
		return
	var cab := _cab
	var toast := ""
	if cab and _last_score >= 0:
		toast = "%s · SCORE %s%s" % [String(cab.entry.get("title", "")).to_upper(), ArcadeScores.grouped(_last_score),
			(" · #%d on this cabinet's board (this computer)" % _last_rank) if _last_rank > 0 else ""]
	_running = false
	_last_score = -1
	dive.leave()
	await dive.exited
	if cab:
		cab.back_to_attract()
	_cab = null
	_resume()
	if toast != "":
		dive.show_toast(toast)


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if not (dive and dive.is_active()) or label != _pay_label:
		return
	match stage:
		"simulate": _refresh_play("Simulating the transfer from your wallet…")
		"sign": _refresh_play("Waiting for your signature in the browser wallet…")
		"pending": _refresh_play("Sent %s · waiting for the receipt…" % String(info.get("hash", "")))
		"confirmed": _refresh_play("Mined in block %d. Checking the Transfer log…" % int(info.get("block", -1)))


## Tools and previews: dive into the cabinet running catalog entry `id`. phase: "push" or "warp"
## hold the transition there; "inside" lands and hides the menu (the demo plays full-screen);
## "menu" lands with the menu up. classic: the cabinet's own screen instead of the 3D world.
func preview_dive(id: String, phase: String = "inside", classic: bool = false) -> void:
	for c in cabinets:
		if String(c.entry.get("id", "")) != id:
			continue
		player.global_position = c.play_spot()
		player.rotation.y = c.global_rotation.y
		var rig := player.get_node_or_null("CameraRig")
		if rig and "_yaw" in rig:
			rig.set("_yaw", c.global_rotation.y)
		await get_tree().process_frame
		match phase:
			"push":
				dive.freeze_at = 0.3
			"warp":
				dive.freeze_at = 0.62
		_open_cabinet(c)
		if phase in ["push", "warp"]:
			return
		await dive.entered
		if classic:
			dive.toggle_view()
		if phase == "inside":
			dive.menu.visible = false
		return
	push_warning("preview_dive: no cabinet runs %s" % id)
