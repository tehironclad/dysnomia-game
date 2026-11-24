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
##
## Game feel (2026-11-24): every press and result is dressed by the stage's FairFx (bursts,
## sparks, pop-ups, chase bulbs), FairSfx sounds, camera shake and a hit-stop on big hits (the
## sim's ticks only pause: replay is unaffected), streak / frenzy call-outs, a first-time
## how-to card, onlookers (FairCrowd) who gather and cheer, and on a good round a short
## celebration (a wide shot, confetti, the prize spinning over the counter). A paid round's
## prize goes on the stall's shelf (FairPrizes, this computer).

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
var _seen_presses := 0
var _seen_last := -1
var _frenzy_shown := false
var _shake := 0.0
var _stop_t := 0.0
var _tut: PanelContainer
var _tut_t := 0.0
var _celebrate_t := 0.0
var _prize: Node3D
var prize_kind := ""            ## the prize shown at the end ("" none)
var prize_kept := ""            ## the kind that went on the shelf (paid rounds)
var _seed_v := 1

const SEEN_PATH := "user://fair_seen.cfg"
const CELEBRATE_T := 3.4


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
	_seed_v = seed_v
	stage.host = self
	stage.begin(sim, String(ticket.get("hash", "")))
	if stage.crowd:
		stage.crowd.gather(2, seed_v)
	stage.refresh_shelf(String(site.get("_qing")))
	seat.title.text = "%s · AFFECTION FAIR" % MidwayGame.title(game)
	seat.set_badge(note, paid)
	seat.headline.text = "SCORE 0"
	seat.status.text = String(MidwayGame.GAMES[game]["how"])
	seat.source.text = _source_line()
	seat.hint.text = "%s / click: %s   ·   Esc: leave" % [ControlsHelp.key_of("interact"), "start"]
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
	_apply_shake(delta)
	if phase == "play":
		if _tut_t > 0.0:
			_tut_t -= delta
			_tut.modulate.a = clampf(_tut_t * 2.0, 0.0, 1.0)
			if _tut_t <= 0.0:
				_tut.visible = false
		if stage.aim_axes() > 0:
			var kx := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
			var ky := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
			_aim = (_aim + Vector2(kx, ky) * KEY_AIM * delta).clamp(Vector2(-MidwaySim.AIM, -MidwaySim.AIM), Vector2(MidwaySim.AIM, MidwaySim.AIM))
		stage.aim = _aim
		if _stop_t > 0.0:
			_stop_t -= delta  # hit-stop: the sim's clock pauses a beat (ticks, not rules)
		elif not hold and _tut_t <= 0.0:
			_acc = minf(_acc + delta, float(MAX_STEPS) / MidwaySim.HZ)
			var n := 0
			while _acc >= 1.0 / MidwaySim.HZ and n < MAX_STEPS and not sim.done:
				sim.step()
				_acc -= 1.0 / MidwaySim.HZ
				n += 1
		stage.render()
		_juice()
		_overlay()
		if sim.done:
			_finish()
	elif phase == "celebrate":
		stage.render()
		seat.target = stage.global_transform * stage.cheer_eye()
		seat.target_fov = 55.0
		if _prize:
			_prize.rotation.y += delta * 2.2
			_prize.position.y = 1.55 + 0.06 * sin(_celebrate_t * 3.0)
		if not hold:
			_celebrate_t -= delta
			if _celebrate_t <= 0.0:
				_end_celebration()
	elif phase == "result":
		stage.render()


func _overlay() -> void:
	var m := stage.meter()
	seat.set_meter(m, "POWER" if m >= 0.0 else "")
	# The texts change a few times a round: only rebuild them then (no per-frame strings)
	var key := sim.score * 1000003 + sim.round_i * 1009 + (sim.tick / MidwaySim.HZ if game == "motzkin" else 0) + (7 if sim.phase == "show" else 0) + sim.streak * 13
	if key == _overlay_key and sim.last_tick == _overlay_last:
		return
	_overlay_key = key
	_overlay_last = sim.last_tick
	seat.headline.text = "SCORE %d" % sim.score
	match game:
		"motzkin":
			seat.stats.text = "%d shots left\n%d s" % [sim.ammo_left(), maxi(0, (MidwaySim.PRIME_RUN - sim.tick) / MidwaySim.HZ)]
			if sim.last_tick != _seen_motz and sim.last_tick >= 0:
				_seen_motz = sim.last_tick
				seat.call_out(sim.last_text, _result_color(), 0.9)
		_:
			seat.stats.text = "%s %d / %d" % [_unit(), mini(sim.round_i + 1, MidwaySim.rounds(game)), MidwaySim.rounds(game)]
			if sim.phase == "show" and _seen_result != sim.round_i:
				_seen_result = sim.round_i
				seat.call_out(sim.last_text if sim.last_text != "" else "+%d" % sim.last_points, _result_color(), 1.0)
	if sim.streak >= 2:
		seat.stats.text += "\nSTREAK %d · next ×%d" % [sim.streak, sim.next_mult()]
	elif not sim.done:
		seat.stats.text += "\nnext ×%d" % sim.next_mult()
	if sim.frenzy_now() and not sim.done:
		seat.stats.text += "\nFRENZY: points ×2"
	if game == "entropy":
		seat.stats.text += "\ndrift %+d mm/m" % sim.wind


func _result_color() -> Color:
	if sim.last_bonus:
		return Color("#ffe45c")
	if sim.last_near:
		return Color("#ffb347")
	if sim.last_points > 0:
		return Color("#7dffb0") if sim.last_good else Color("#ffd27a")
	return Color("#ff8fa0") if sim.last_points < 0 else Color("#8e97a9")


# --- Game feel ----------------------------------------------------------------------------

## Reacts to what the sim just did: presses, results, the frenzy (all read, nothing decided here).
func _juice() -> void:
	if sim.events.size() != _seen_presses:
		_seen_presses = sim.events.size()
		stage.on_press()
		FairSfx.play(self, stage.press_sound(), randf_range(0.92, 1.08))
	if sim.last_tick != _seen_last and sim.last_tick >= 0:
		_seen_last = sim.last_tick
		_on_result()
	if not _frenzy_shown and sim.frenzy_now() and not sim.done and (game == "motzkin" or sim.phase == "ready"):
		_frenzy_shown = true
		seat.call_out("FRENZY! ×2", Color("#ff5cc8"), 1.6)
		FairSfx.play(self, "fanfare", 1.25, -4.0)
		if stage.fx:
			stage.fx.set_mode("win")


func _on_result() -> void:
	var pts := sim.last_points
	var pos := stage.impact_pos()
	stage.on_result()
	var snd := stage.result_sound()
	if snd != "":
		FairSfx.play(self, snd)
	var fx := stage.fx
	if pts > 0:
		var big := sim.last_bonus or sim.last_mult >= 3
		var power := clampf(0.6 + pts / 250.0, 0.6, 2.2)
		if fx:
			fx.burst(pos, Color(1.0, 0.85, 0.35) if sim.last_bonus else (Color(0.4, 1.0, 0.65) if sim.last_good else Color(1.0, 0.75, 0.4)), power)
			if big:
				fx.sparks(pos, Color(1.0, 0.9, 0.5), power)
			fx.popup(pos + Vector3(0, 0.25, 0.2), "+%d%s" % [pts, (" ×%d" % sim.last_mult) if sim.last_mult > 1 else ""], _result_color(), 1.5 if big else 1.0)
		FairSfx.play(self, "coin" if sim.last_bonus else "pop", 1.0 + 0.06 * mini(sim.streak, 6))
		kick(0.025 + 0.05 * power, 0.1 if big else 0.0)
		if sim.streak >= 2:
			FairSfx.play(self, "streak", 1.0 + 0.08 * mini(sim.streak, 8), -3.0)
		if stage.crowd:
			if big or sim.streak >= 2:
				stage.crowd.add_one()
			if sim.last_good:
				stage.crowd.hop()
		if fx and sim.streak >= 3:
			fx.set_mode("win")
	elif pts < 0:
		if fx:
			fx.popup(pos + Vector3(0, 0.25, 0.2), "%d" % pts, Color("#ff6b7f"), 1.1)
			fx.burst(pos, Color(1.0, 0.25, 0.3), 0.6)
			fx.set_mode("idle")
		FairSfx.play(self, "buzz")
		kick(0.04)
	else:
		if fx:
			fx.popup(pos + Vector3(0, 0.25, 0.2), "SO CLOSE!" if sim.last_near else "miss", Color("#ffb347") if sim.last_near else Color("#a7b0c0"), 1.15 if sim.last_near else 0.8)
			fx.set_mode("idle")
		if sim.last_near:
			FairSfx.play(self, "aww", 1.0, -2.0)


## Camera shake (m of offset, decays fast) and a hit-stop (s the sim's clock pauses).
func kick(shake: float, stop: float = 0.0) -> void:
	_shake = maxf(_shake, shake)
	_stop_t = maxf(_stop_t, stop)


func _apply_shake(delta: float) -> void:
	if seat.cam == null:
		return
	if _shake > 0.0005:
		_shake *= exp(-9.0 * delta)
		seat.cam.h_offset = randf_range(-1.0, 1.0) * _shake
		seat.cam.v_offset = randf_range(-1.0, 1.0) * _shake
	elif seat.cam.h_offset != 0.0 or seat.cam.v_offset != 0.0:
		_shake = 0.0
		seat.cam.h_offset = 0.0
		seat.cam.v_offset = 0.0


func _unit() -> String:
	match game:
		"striker": return "swing"
		"entropy": return "puck"
		"regolith": return "ring"
		"crystal": return "ball"
		"waat": return "spin"
		"saat": return "guess"
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
			if _tut_t > 0.0:
				_tut_t = minf(_tut_t, 0.25)  # a press during the how-to card just dismisses it
			else:
				press()
		"celebrate":
			_end_celebration()
		"result":
			if not _posting:
				leave()


## Starts the round (after the how-to).
func begin_play() -> void:
	phase = "play"
	seat.status.text = ""
	seat.hint.text = _play_hint()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if stage.fx:
		stage.fx.set_mode("idle")
	if not _seen_before(game):
		_show_tutorial()


## The first time on this computer, a how-to card for a few seconds (the round waits for it).
func _seen_before(id: String) -> bool:
	var c := ConfigFile.new()
	c.load(SEEN_PATH)
	return bool(c.get_value("seen", id, false))


func _show_tutorial() -> void:
	var c := ConfigFile.new()
	c.load(SEEN_PATH)
	c.set_value("seen", game, true)
	c.save(SEEN_PATH)
	_tut.visible = true
	_tut.modulate.a = 1.0
	_tut_t = 3.4

func _play_hint() -> String:
	var k := ControlsHelp.key_of("interact")
	match game:
		"striker": return "%s / Space / click: swing at the top of the meter   ·   Esc: leave" % k
		"entropy": return "mouse or A/D: aim   ·   %s / click: toss at the right power   ·   Esc: leave" % k
		"regolith": return "mouse or WASD: aim at a peg   ·   %s / click: throw   ·   Esc: leave" % k
		"crystal": return "mouse or WASD: aim (up: the high rail)   ·   %s / click: throw   ·   Esc: leave" % k
		"motzkin": return "mouse or WASD: aim   ·   %s / click: shoot primes only   ·   Esc: leave" % k
		"waat": return "%s / click: brake   ·   Esc: leave" % k
		"saat": return "mouse or A/D: LOWER (left) or HIGHER (right)   ·   %s / click: guess   ·   Esc: leave" % k
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
	var tier := MidwayGame.prize_tier(game, sim.score)
	prize_kind = String(tier[1]) if not tier.is_empty() else ""
	var qing := String(site.get("_qing"))
	if paid and prize_kind != "":
		prize_kept = FairPrizes.award(qing, game, prize_kind, sim.score, String(ticket.get("hash", "")))
		prize_kind = prize_kept
		stage.refresh_shelf(qing)
	if paid and MidwayGame.max_score(game) > 0:
		rank = ArcadeScores.record(site.get("_qing"), "fair:" + game, {"score": sim.score, "wallet": Wallet.address,
			"tx": ticket.get("hash", ""), "block": int(ticket.get("block", 0)), "at": int(Time.get_unix_time_from_system()),
			"log": MidwaySim.encode_log(game, sim.events)})
	seat.status.text = ""
	seat.hint.text = ""
	if prize_kind != "" and (prize_kind != "pennant" or sim.best_streak >= 3):
		_celebrate()
	else:
		if sim.score <= 0:
			FairSfx.play(self, "aww", 0.9, -4.0)
		show_result()


## A good round: a wide shot of the stall, the crowd cheering, confetti, chase bulbs, the
## prize spinning over the counter (the bell and a fanfare for the grand prize).
func _celebrate() -> void:
	phase = "celebrate"
	_celebrate_t = CELEBRATE_T
	var grand := prize_kind == "trophy"
	seat.call_out("GRAND PRIZE!" if grand else "YOU WIN!", Color("#ffe45c") if grand else Color("#7dffb0"), CELEBRATE_T)
	seat.hint.text = "%s: continue" % ControlsHelp.key_of("interact")
	if stage.crowd:
		stage.crowd.gather(5 if grand else 4, _seed_v)
		stage.crowd.cheer(CELEBRATE_T + 0.6)
	if stage.fx:
		stage.fx.set_mode("grand" if grand else "win")
		stage.fx.confetti(Vector3(0, 2.7, 1.4))
		stage.fx.burst(Vector3(0, 1.55, 1.3), Color(1.0, 0.85, 0.4), 2.0)
	_prize = Node3D.new()
	_prize.position = Vector3(0, 1.55, 1.35)
	stage.add_child(_prize)
	var m := FairPrizes.model(prize_kind, 2.6 if prize_kind != "pennant" else 2.0)
	m.position.y = -0.3
	_prize.add_child(m)
	FairKit.omni(_prize, Vector3(0, 0.3, 0.6), Color(1.0, 0.9, 0.7), 2.5, 3.0)
	var tag := FairKit.label(_prize, FairPrizes.NAMES.get(prize_kind, "").to_upper() + ("" if paid else "\npractice: a ticket takes it home"),
		Vector3(0, 0.62, 0), 40, Color(1.0, 0.9, 0.6), 0.0, Color(0.08, 0.02, 0.1), 0.004)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	FairSfx.play(self, "cheer")
	if grand:
		FairSfx.play(self, "bell")
		FairSfx.play(self, "fanfare")
		kick(0.08, 0.0)


func _end_celebration() -> void:
	if phase != "celebrate":
		return
	phase = "result"
	seat.hint.text = ""
	seat.call_out("", Color.WHITE, 0.0)
	show_result()


## The result screen: score, prize, both boards and what can be done next.
func show_result() -> void:
	_panel.visible = true
	_p_title.text = "%s · SCORE %d" % [MidwayGame.title(game), sim.score]
	var won := MidwayGame.prize(game, sim.score)
	var t := ("You win %s" % won) if won != "" else "No prize this time: the shelf is still full."
	if prize_kept != "" and prize_kept != MidwayGame.prize_kind(game, sim.score):
		t = "You win a %s (the %s is gone for today)" % [FairPrizes.NAMES[prize_kept], FairPrizes.NAMES.get(MidwayGame.prize_kind(game, sim.score), "")]
	if prize_kept != "":
		t += " · it's on this stall's prize shelf (this computer)"
	elif won != "" and not paid:
		t += " · practice: a ticket takes it home"
	t += "   ·   best streak %d" % sim.best_streak
	if game == "saat":
		t += "\nThe teller reads your ticket: “%s”" % MidwayGame.fortune(sim.seed_v)
	_p_prize.text = t
	refresh_boards()
	_hint_text()


func refresh_boards() -> void:
	if _panel == null or not _panel.visible:
		return
	var qing := String(site.get("_qing"))
	var st := FairBoard.state_of(qing)
	var room := "ROOM BOARD · verified on chain\n"
	if st.is_empty():
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
	if lb.is_empty():
		local += "no paid rounds here yet"
	else:
		local += "\n".join(ArcadeScores.lines(lb, 10))
	if paid:
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
	return paid and sim.score > 0 and posted.is_empty() and not _posting


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
	var forfeit := phase not in ["result", "celebrate"]
	phase = "leaving"
	_tut_t = 0.0
	_shake = 0.0
	if seat.cam:
		seat.cam.h_offset = 0.0
		seat.cam.v_offset = 0.0
	if _prize:
		_prize.queue_free()
		_prize = null
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
	sb.bg_color = Color(0.02, 0.025, 0.05, 0.97)
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
	# The first-time how-to card (top centre, over the play)
	_tut = PanelContainer.new()
	_tut.theme = DeepFieldTheme.get_theme()
	var ts := DeepFieldTheme.panel_style(Color("#ffd27a"))
	ts.bg_color = Color(0.03, 0.02, 0.07, 0.9)
	_tut.add_theme_stylebox_override("panel", ts)
	_tut.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tut.offset_left = -330
	_tut.offset_right = 330
	_tut.offset_top = 110
	_tut.offset_bottom = 290
	_tut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tut.visible = false
	seat.add_child(_tut)
	var tc := VBoxContainer.new()
	_tut.add_child(tc)
	var th := _lab(tc, "DisplayLabel", 26, Color("#ffd27a"))
	th.text = "HOW TO PLAY · %s" % MidwayGame.title(game)
	th.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tb := _lab(tc, "", 22, DeepFieldTheme.INK)
	tb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tb.text = "\n".join(PackedStringArray(MidwayGame.GAMES[game].get("tips", [])))


func _lab(parent: Control, variation: String, size: int, c: Color) -> Label:
	var l := Label.new()
	if variation != "":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
