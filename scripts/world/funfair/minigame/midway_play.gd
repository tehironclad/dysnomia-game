class_name MidwayPlay
extends Node
## One round of a midway game in first person. The camera glides from the player to the stall's
## counter (TableSeat, the pool table's glide and overlay), the stall's MidwayStage plays what the
## round's MidwaySim says, and the result screen shows the score with both boards: the room's
## verified board (FairBoard, from this QING's room lines) and this computer's (ArcadeScores).
##
## The sim runs at MidwaySim.HZ fixed ticks; a press (Use / Space / left click) is queued with the
## aim (mouse, or the move keys) quantised to integers, so the round's input log replays to the
## same score anywhere. After a paid round the player may post the score to the room
## (fair_post): one room line, simulate → sign → receipt → read back (TableBook.post).
## Esc leaves (during play it forfeits: no score is recorded).

signal closed(score: int)

const AIM_SENS := 1.3          ## aim units per mouse pixel
const KEY_AIM := 520.0         ## aim units a second with the move keys
const MAX_STEPS := 8           ## sim ticks per frame at most (a slow frame catches up over a few)

var site: Node                 ## FairSite
var stage: MidwayStage
var sim: MidwaySim
var seat: TableSeat
var game := ""
var paid := false
var note := ""
var ticket := {}               ## {hash, block, …} from ArcadePay, {} in practice
var phase := "intro"           ## intro | play | result | leaving
var hold := false              ## previews: don't step the sim
var posted := {}               ## the room line once posted
var rank := 0

var _acc := 0.0
var _aim := Vector2.ZERO
var _seen_result := -1
var _seen_motz := -1
var _overlay_key := -1
var _overlay_last := -1
var _posting := false
var _panel: PanelContainer
var _p_title: Label
var _p_prize: Label
var _p_room: Label
var _p_local: Label
var _p_source: Label
var _p_status: Label
var _p_hint: Label


func start(p_site: Node, p_stage: MidwayStage, p_game: String, seed_v: int, p_paid: bool, p_note: String, p_ticket: Dictionary, hide_layers: Array) -> void:
	site = p_site
	stage = p_stage
	game = p_game
	paid = p_paid
	note = p_note
	ticket = p_ticket
	sim = MidwaySim.new(game, seed_v)
	seat = TableSeat.new()
	site.add_child(seat)
	_build_panel()
	stage.begin(sim, String(ticket.get("hash", "")))
	seat.title.text = "%s · AFFECTION FAIR" % MidwayGame.title(game)
	seat.set_badge(note, paid)
	seat.headline.text = "" if game == "saat" else "SCORE 0"
	seat.status.text = String(MidwayGame.GAMES[game]["how"])
	seat.source.text = _source_line()
	seat.hint.text = "%s / click: %s   ·   Esc: leave" % [ControlsHelp.key_of("interact"), "turn the first card" if game == "saat" else "start"]
	var player: Node3D = site.get("_player")
	var model: Node3D = player.get_node_or_null("PlayerModel") if player else null
	seat.enter(stage.global_transform * stage.eye(), stage.fov(), model, hide_layers)


func _source_line() -> String:
	var s := "Rules: MidwaySim v%d · %d ticks a second · integer physics · " % [MidwaySim.VERSION, MidwaySim.HZ]
	if paid:
		s += "seeded by ticket %s (block %s): anyone can replay this round from it" % [ArcadeScores.short(String(ticket.get("hash", ""))), ArcadeScores.grouped(int(ticket.get("block", 0)))]
	else:
		s += "practice seed from this computer: on no board"
	return s


func _process(delta: float) -> void:
	if seat == null or not seat.is_active():
		return
	seat.target = stage.global_transform * stage.eye()
	seat.target_fov = stage.fov()
	if phase == "play":
		if stage.aim_axes() > 0:
			var kx := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
			var ky := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
			_aim = (_aim + Vector2(kx, ky) * KEY_AIM * delta).clamp(Vector2(-MidwaySim.AIM, -MidwaySim.AIM), Vector2(MidwaySim.AIM, MidwaySim.AIM))
		stage.aim = _aim
		if not hold:
			_acc = minf(_acc + delta, float(MAX_STEPS) / MidwaySim.HZ)
			var n := 0
			while _acc >= 1.0 / MidwaySim.HZ and n < MAX_STEPS and not sim.done:
				sim.step()
				_acc -= 1.0 / MidwaySim.HZ
				n += 1
		stage.render()
		_overlay()
		if sim.done:
			_finish()
	elif phase == "result":
		stage.render()


func _overlay() -> void:
	var m := stage.meter()
	seat.set_meter(m, "POWER" if m >= 0.0 else "")
	# The texts change a few times a round: only rebuild them then (no per-frame strings)
	var key := sim.score * 1000003 + sim.round_i * 1009 + (sim.tick / MidwaySim.HZ if game == "motzkin" else 0) + (7 if sim.phase == "show" else 0)
	if key == _overlay_key and sim.last_tick == _overlay_last:
		return
	_overlay_key = key
	_overlay_last = sim.last_tick
	if game != "saat":
		seat.headline.text = "SCORE %d" % sim.score
	match game:
		"motzkin":
			seat.stats.text = "%d shots left\n%d s" % [sim.ammo_left(), maxi(0, (MidwaySim.PRIME_RUN - sim.tick) / MidwaySim.HZ)]
			if sim.last_tick != _seen_motz and sim.last_tick >= 0:
				_seen_motz = sim.last_tick
				var good := sim.last_points > 0
				seat.call_out(sim.last_text, Color("#7dffb0") if good else (Color("#ff8fa0") if sim.last_points < 0 else Color("#8e97a9")), 0.9)
		"saat":
			seat.stats.text = "card %d / 3" % mini(sim.round_i + 1, 3)
		_:
			seat.stats.text = "%s %d / %d" % [_unit(), mini(sim.round_i + 1, MidwaySim.rounds(game)), MidwaySim.rounds(game)]
			if sim.phase == "show" and _seen_result != sim.round_i:
				_seen_result = sim.round_i
				seat.call_out(sim.last_text, Color("#ffd27a") if sim.last_points > 0 else Color("#ff8fa0"), 1.0)
	if game == "entropy":
		seat.stats.text += "\ndrift %+d mm/m" % sim.wind


func _unit() -> String:
	match game:
		"striker": return "swing"
		"entropy": return "puck"
		"regolith": return "ring"
		"crystal": return "ball"
		"waat": return "spin"
	return "round"


func _input(event: InputEvent) -> void:
	if seat == null or phase == "leaving" or not seat.is_active():
		return
	if event is InputEventMouseMotion:
		if phase == "play" and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_aim = (_aim + Vector2(event.relative.x, -event.relative.y) * AIM_SENS).clamp(Vector2(-MidwaySim.AIM, -MidwaySim.AIM), Vector2(MidwaySim.AIM, MidwaySim.AIM))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()
		return
	if event.is_echo():
		return
	var go := event.is_action_pressed("interact") or event.is_action_pressed("table_shoot")
	if event.is_action_pressed("fair_post"):
		get_viewport().set_input_as_handled()
		if phase == "result":
			post()
		return
	if not go:
		return
	get_viewport().set_input_as_handled()
	match phase:
		"intro":
			if seat.is_inside():
				begin_play()
		"play":
			press()
		"result":
			if not _posting:
				leave()


## Starts the round (after the how-to).
func begin_play() -> void:
	phase = "play"
	seat.status.text = ""
	seat.hint.text = _play_hint()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if game == "saat":
		press()


func _play_hint() -> String:
	var k := ControlsHelp.key_of("interact")
	match game:
		"striker": return "%s / Space / click: swing at the top of the meter   ·   Esc: leave" % k
		"entropy": return "mouse or A/D: aim   ·   %s / click: toss at the right power   ·   Esc: leave" % k
		"regolith": return "mouse or WASD: aim at a peg   ·   %s / click: throw   ·   Esc: leave" % k
		"crystal": return "mouse or WASD: aim (up: the high rail)   ·   %s / click: throw   ·   Esc: leave" % k
		"motzkin": return "mouse or WASD: aim   ·   %s / click: shoot primes only   ·   Esc: leave" % k
		"waat": return "%s / click: brake   ·   Esc: leave" % k
		"saat": return "%s / click: turn the next card   ·   Esc: leave" % k
	return ""


## A press of the one button, with the current aim (also used by previews and the probe).
func press() -> bool:
	if phase != "play":
		return false
	return sim.press(int(round(_aim.x)), int(round(_aim.y)))


func set_aim(v: Vector2) -> void:
	_aim = v


func _finish() -> void:
	phase = "result"
	seat.set_meter(-1.0)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if paid and MidwayGame.max_score(game) > 0:
		rank = ArcadeScores.record(site.get("_qing"), "fair:" + game, {"score": sim.score, "wallet": Wallet.address,
			"tx": ticket.get("hash", ""), "block": int(ticket.get("block", 0)), "at": int(Time.get_unix_time_from_system()),
			"log": MidwaySim.encode_log(game, sim.events)})
	seat.status.text = ""
	seat.hint.text = ""
	show_result()


## The result screen: score, prize, both boards and what can be done next.
func show_result() -> void:
	_panel.visible = true
	if game == "saat":
		_p_title.text = "THE TELLER READS YOUR TICKET"
		_p_prize.text = "“%s”" % MidwayGame.fortune(sim.seed_v)
	else:
		_p_title.text = "%s · SCORE %d" % [MidwayGame.title(game), sim.score]
		_p_prize.text = "You win %s" % MidwayGame.prize(game, sim.score)
	refresh_boards()
	_hint_text()


func refresh_boards() -> void:
	if _panel == null or not _panel.visible:
		return
	var qing := String(site.get("_qing"))
	var st := FairBoard.state_of(qing)
	var room := "ROOM BOARD · verified on chain\n"
	if game == "saat":
		room += "The fortune teller keeps no scores."
	elif st.is_empty():
		room += "reading this QING's room lines…"
	else:
		var b := FairBoard.compile(st.get("rows", []), game)
		var rows := FairBoard.lines(b["top"])
		if not st.get("ok", false) and st.get("rows", []).is_empty():
			room += "—"
		elif rows.is_empty():
			room += "no verified scores yet: post yours"
		else:
			room += "\n".join(rows)
		_p_source.text = FairBoard.source_text(st, b)
	var local := "THIS COMPUTER (not on chain)\n"
	var lb := ArcadeScores.board(qing, "fair:" + game)
	if game == "saat":
		local += "—"
	elif lb.is_empty():
		local += "no paid rounds here yet"
	else:
		local += "\n".join(ArcadeScores.lines(lb, 10))
	if paid and game != "saat":
		local += "\n" + (("this round: #%d" % rank) if rank > 0 else "this round: off the top %d" % ArcadeScores.KEEP)
	elif not paid:
		local += "\npractice round: on no board"
	_p_room.text = room
	_p_local.text = local


func _hint_text() -> void:
	var k := ControlsHelp.key_of("interact")
	var parts := PackedStringArray()
	if can_post():
		parts.append("%s: post this score to the room (one approval; a room line also adds Ω Hypobar to this QING)" % ControlsHelp.key_of("fair_post"))
	parts.append("%s / Esc: leave" % k)
	_p_hint.text = "\n".join(parts)


func can_post() -> bool:
	return paid and game != "saat" and sim.score > 0 and posted.is_empty() and not _posting


## Posts the round to the room: 🎪 <game> <score> <ticket> v1:<log>, through TableBook.post
## (Wallet.send simulates, signs, waits for the receipt; the line is read back from its block).
func post() -> void:
	if not can_post():
		return
	var blocker := ChatController._signer_blocker()
	if blocker == "":
		blocker = ChatController._identity_blocker()
	if blocker != "":
		_p_status.text = blocker
		return
	var qing := String(site.get("_qing"))
	var text := FairBoard.line_text(game, sim.score, String(ticket["hash"]), sim.events)
	if text.length() > FairBoard.MAX_LEN:
		_p_status.text = "This round's line is %d characters; a room line takes %d. Not posted." % [text.length(), FairBoard.MAX_LEN]
		return
	_posting = true
	_hint_text()
	_p_status.text = "Approve the room line in your wallet window… (simulate → sign → receipt → read back)"
	var res: Dictionary = await TableBook.post(qing, text, "Affection Fair · post %s score %d" % [MidwayGame.title(game), sim.score])
	_posting = false
	if not res.get("ok", false):
		_p_status.text = "Not posted (%s): %s" % [res.get("stage", "?"), res.get("message", "cancelled")]
		_hint_text()
		return
	posted = res
	_p_status.text = "Posted in block %s and read back from the chain. Checking the board…" % ArcadeScores.grouped(int(res["block"]))
	_hint_text()
	if site.has_method("refresh_boards"):
		await site.refresh_boards()
	refresh_boards()
	var b := FairBoard.compile(FairBoard.state_of(qing).get("rows", []), game)
	var mine: Array = b["top"].filter(func(r): return r["line_tx"] == String(res["hash"]))
	_p_status.text = ("Posted in block %s: verified, #%d on the room board." % [ArcadeScores.grouped(int(res["block"])), b["top"].find(mine[0]) + 1]) if not mine.is_empty() \
		else "Posted in block %s. Not in the room's top %d (or still being checked)." % [ArcadeScores.grouped(int(res["block"])), FairBoard.TOP]


func leave() -> void:
	if phase == "leaving" or _posting:
		return
	var forfeit := phase != "result"
	phase = "leaving"
	if _panel:
		_panel.visible = false
	seat.set_meter(-1.0)
	seat.leave()
	await seat.exited
	stage.end()
	seat.queue_free()
	closed.emit(-1 if forfeit else sim.score)


# --- The result panel -----------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.93
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -560
	_panel.offset_right = 560
	_panel.offset_top = -230
	_panel.offset_bottom = 270
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	seat.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	_p_title = _lab(col, "DisplayLabel", 30, Color("#ffd27a"))
	_p_prize = _lab(col, "", 18, DeepFieldTheme.INK)
	_p_prize.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	col.add_child(row)
	_p_room = _lab(row, "MonoLabel", 14, DeepFieldTheme.ICE)
	_p_room.custom_minimum_size = Vector2(560, 250)
	_p_room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_room.clip_text = true
	_p_local = _lab(row, "MonoLabel", 14, DeepFieldTheme.MUTED)
	_p_local.custom_minimum_size = Vector2(480, 250)
	_p_local.clip_text = true
	_p_source = _lab(col, "MonoLabel", 12, DeepFieldTheme.DIM)
	_p_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_status = _lab(col, "MonoLabel", 14, Color("#ffd27a"))
	_p_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_hint = _lab(col, "MonoLabel", 15, Color("#7fe9ff"))
	_p_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _lab(parent: Control, variation: String, size: int, c: Color) -> Label:
	var l := Label.new()
	if variation != "":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
