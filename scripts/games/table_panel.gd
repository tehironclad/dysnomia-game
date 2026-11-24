class_name TablePanel
extends PanelContainer
## The pool table or the card table, up close: the room's games of that kind
## (open challenges, live games, finished ones with ✓ paid / ⚠ unpaid), the
## selected game drawn from its replayed lines, and the moves you can make.
## Every move is a room line signed in your wallet (simulate → sign →
## receipt → read back); nothing changes on screen until the chain has it.

signal closed

var kind := "pool"  # "pool" | "cards"
var book: TableBook
var qing := ""
var place_name := ""
var blocker_fn: Callable  # → "" or why you can't sign here
var join_fn: Callable  # the room's Join (GamesPlace → ChatController)
var access: AccessSteps  # the steps to play here when blocked

var _title: Label
var _sub: Label
var _list: ItemList
var _view: Control
var _events: Label
var _status: Label
var _accept: Button
var _cancel: Button
var _concede: Button
var _claim: Button
var _pay: Button
var _shoot: Button
var _power: HSlider
var _hit: Button
var _stand: Button
var _invite: LineEdit
var _stake: LineEdit
var _challenge: Button
var _shown: Array = []
var _sel_id := ""
var _busy := false
var _label := ""
var _animated_tx := ""


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.96
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(960, 560)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.add_theme_font_size_override("font_size", 18)
	col.add_child(_title)
	_sub = Label.new()
	_sub.theme_type_variation = "MutedLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(920, 0)
	col.add_child(_sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	var left := VBoxContainer.new()
	body.add_child(left)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(340, 300)
	_list.add_theme_font_override("font", DeepFieldTheme.mono_font())
	_list.add_theme_font_size_override("font_size", 12)
	_list.item_selected.connect(func(i): _sel_id = String(_shown[i]["id"]) if i < _shown.size() else ""; _refresh_detail())
	left.add_child(_list)
	var lrow := HBoxContainer.new()
	left.add_child(lrow)
	_accept = _button(lrow, "Accept", func(): _move("accept"))
	_cancel = _button(lrow, "Decline", func(): _move("decline"))
	_concede = _button(lrow, "Concede", func(): _move("concede"))
	_claim = _button(lrow, "Claim (idle)", func(): _move("forfeit"))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_view = PoolView.new()
	right.add_child(_view)
	_events = Label.new()
	_events.theme_type_variation = "MonoLabel"
	_events.add_theme_font_size_override("font_size", 12)
	_events.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events.custom_minimum_size = Vector2(560, 60)
	right.add_child(_events)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	right.add_child(mrow)
	var pl := Label.new()
	pl.text = "Power"
	pl.theme_type_variation = "MutedLabel"
	mrow.add_child(pl)
	_power = HSlider.new()
	_power.min_value = 50
	_power.max_value = 1000
	_power.step = 10
	_power.value = 550
	_power.custom_minimum_size = Vector2(220, 0)
	mrow.add_child(_power)
	_shoot = _button(mrow, "Shoot (signs a room line)", _shoot_now)
	_hit = _button(mrow, "Hit", func(): _move("hit"))
	_stand = _button(mrow, "Stand", func(): _move("stand"))
	_pay = _button(right, "Pay", _pay_now)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	col.add_child(crow)
	_invite = LineEdit.new()
	_invite.placeholder_text = "opponent's wallet 0x… (empty: anyone)"
	_invite.custom_minimum_size = Vector2(380, 0)
	crow.add_child(_invite)
	_stake = LineEdit.new()
	_stake.placeholder_text = "stake in Ⓐ (optional)"
	_stake.custom_minimum_size = Vector2(170, 0)
	crow.add_child(_stake)
	_challenge = _button(crow, "Post a challenge", _post_challenge)
	var close := _button(crow, "Close", close_panel)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	_status.add_theme_color_override("font_color", Color("#ffd27a"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(920, 0)
	col.add_child(_status)
	access = AccessSteps.embed(col)
	Wallet.tx_stage.connect(_on_stage)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func setup(p_kind: String, p_book: TableBook, p_qing: String, p_place: String, p_blocker: Callable) -> void:
	kind = p_kind
	book = p_book
	qing = p_qing
	place_name = p_place
	blocker_fn = p_blocker
	if kind == "cards":
		_view.queue_free()
		_view = CardsView.new()
		_events.get_parent().add_child(_view)
		_events.get_parent().move_child(_view, 0)
	book.changed.connect(refresh)


func open() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_title.text = ("POOL · EIGHT-BALL" if kind == "pool" else "TWENTY-ONE") + " · " + place_name
	_sub.text = ("Challenger breaks. Aim with the mouse on the table, set the power, shoot: each shot is a room line (CHOA.Chat) that every player's game replays the same way." if kind == "pool"
		else "Cards come from the chain: each one is SHA-256 of the block that holds the line asking for it. Challenger plays first: hit or stand; closest to 21 wins, a tie is a push.") + \
		"  Wagers are honour-bound (no escrow): the loser pays the stake in Ⓐ, and the chain shows ✓ paid or ⚠ unpaid next to their wallet. A game idle for %d blocks can be claimed by the player who is waiting." % TableBook.TIMEOUT_BLOCKS
	refresh()
	_settle()


func _settle() -> void:
	var head := await Chain.refresh_head()
	if head > 0 and book:
		book.settle(head)


func is_open() -> bool:
	return visible


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()


## The selected game, or {}.
func selected() -> Dictionary:
	return book.by_id.get(_sel_id, {}) if book else {}


func refresh() -> void:
	if not visible or book == null:
		return
	_shown = book.of_kind(kind)
	_list.clear()
	var me := Session.wallet
	for m in _shown:
		_list.add_item(_row_text(m, me))
	if _sel_id == "" and not _shown.is_empty():
		_sel_id = String(_shown[0]["id"])
	for i in _shown.size():
		if _shown[i]["id"] == _sel_id:
			_list.select(i)
	_refresh_detail()


func _row_text(m: Dictionary, me: String) -> String:
	var stake := "" if BigInt.is_zero(m["stake"]) else " · %s" % ArcadePay.fmt(m["stake"])
	var a := book.display(m["players"][0])
	var b := book.display(m["players"][1]) if m["players"][1] != "" else ("anyone" if m["invite"] == "" else book.display(m["invite"]))
	var state := ""
	match m["status"]:
		"open": state = "open"
		"playing":
			var t := TableBook.turn_index(m)
			state = "your move" if t >= 0 and m["players"][t] == me else "playing"
		"over":
			if m["push"]:
				state = "push"
			else:
				state = "%s won" % book.display(m["winner"])
				if not BigInt.is_zero(m["stake"]):
					state += (" ✓ paid" if m["paid"] == true else (" ⚠ unpaid" if m["paid"] == false else " · checking payment —"))
	return "#%s  %s vs %s%s  ·  %s" % [m["id"], a, b, stake, state]


func _refresh_detail() -> void:
	var m := selected()
	var me := Session.wallet
	var blocker := String(blocker_fn.call()) if blocker_fn.is_valid() else ""
	var mine: bool = not m.is_empty() and TableBook.player_index(m, me) >= 0
	var my_turn: bool = not m.is_empty() and TableBook.turn_index(m) >= 0 and m["players"][TableBook.turn_index(m)] == me
	_accept.disabled = _busy or blocker != "" or m.is_empty() or m["status"] != "open" or m["challenger"] == me or (m["invite"] != "" and m["invite"] != me)
	_cancel.disabled = _busy or blocker != "" or m.is_empty() or m["status"] != "open" or not (m["challenger"] == me or m["invite"] == me)
	_concede.disabled = _busy or blocker != "" or m.is_empty() or m["status"] != "playing" or not mine
	_claim.disabled = _busy or blocker != "" or m.is_empty() or m["status"] != "playing" or not mine or my_turn
	_shoot.visible = kind == "pool"
	_power.visible = kind == "pool"
	_power.get_parent().get_child(0).visible = kind == "pool"
	_hit.visible = kind == "cards"
	_stand.visible = kind == "cards"
	_shoot.disabled = _busy or blocker != "" or not my_turn
	_hit.disabled = _shoot.disabled
	_stand.disabled = _shoot.disabled
	_challenge.disabled = _busy or blocker != ""
	var owes: bool = not m.is_empty() and m["status"] == "over" and m["loser"] == me and m["paid"] == false
	_pay.visible = owes
	if owes:
		_pay.text = "Pay %s to %s (your stake: you lost)" % [ArcadePay.fmt(m["stake"]), book.display(m["winner"])]
	_pay.disabled = _busy or blocker != ""
	if m.is_empty():
		_events.text = "No games of %s here yet. Post a challenge below: to one wallet, or to anyone." % ("pool" if kind == "pool" else "Twenty-One")
	else:
		var ev: Array = m["events"]
		var lines: Array = ev.slice(maxi(0, ev.size() - 4))
		var head := "#%s · started at block %d" % [m["id"], m["created_block"]]
		if m["status"] == "over" and not m["push"]:
			head += " · %s won at block %d" % [book.display(m["winner"]), m["end_block"]]
			if not BigInt.is_zero(m["stake"]):
				head += " · %s owes %s %s" % [book.display(m["loser"]), ArcadePay.fmt(m["stake"]), "✓ paid (block %d)" % m.get("paid_block", -1) if m["paid"] == true else ("⚠ unpaid" if m["paid"] == false else "(payment not read yet: —)")]
		_events.text = head + "\n" + "\n".join(lines)
	if blocker != "":
		_status.text = blocker
	access.update_for(blocker, "table", {"qing": qing, "room_name": place_name}, {"join": join_fn} if join_fn.is_valid() else {})
	if kind == "pool":
		(_view as PoolView).show_match(m, my_turn)
		_maybe_animate(m)
	else:
		(_view as CardsView).show_match(m, book)


func _maybe_animate(m: Dictionary) -> void:
	if m.is_empty() or not m.has("last_shot"):
		return
	var s: Dictionary = m["last_shot"]
	if s["tx"] == _animated_tx:
		return
	_animated_tx = s["tx"]
	(_view as PoolView).play_shot(s["before"], s["dx"], s["dy"], s["power"], m)


# --- Moves --------------------------------------------------------------------

func _post(text: String, label: String) -> void:
	if _busy:
		return
	_busy = true
	_label = label
	_refresh_detail()
	var r: Dictionary = await TableBook.post(qing, text, label)
	_busy = false
	if r["ok"]:
		_status.text = "On the chain: read back from block %d." % r["block"]
		await book.feed([r["line"]])
		if text.contains(" challenge "):
			_sel_id = TableBook.game_id(String(r["line"]["tx"]))
	refresh()


func _move(op: String) -> void:
	var m := selected()
	if m.is_empty():
		return
	_post(TableBook.move_text(kind, m["id"], op), "%s #%s %s" % ["Pool" if kind == "pool" else "Twenty-One", m["id"], op])


func _shoot_now() -> void:
	var m := selected()
	if m.is_empty():
		return
	var aim: Vector2i = (_view as PoolView).aim
	if aim == Vector2i.ZERO:
		_status.text = "Aim first: point at the table with the mouse."
		return
	_post(TableBook.shot_text(m["id"], aim.x, aim.y, int(_power.value)), "Pool #%s shot" % m["id"])


func _post_challenge() -> void:
	var who := _invite.text.strip_edges().to_lower()
	if who != "" and not (who.begins_with("0x") and who.length() == 42 and Abi.strip0x(who).is_valid_hex_number()):
		_status.text = "The opponent must be a full wallet address (0x + 40 hex digits), or empty for anyone."
		return
	if who == Session.wallet:
		_status.text = "You can't challenge yourself."
		return
	var stake := _stake.text.strip_edges().trim_suffix("Ⓐ").strip_edges()
	if stake != "" and not RegEx.create_from_string("^[0-9]+(\\.[0-9]{1,18})?$").search(stake):
		_status.text = "The stake is a number of Ⓐ, like 5 or 0.25."
		return
	_post(TableBook.challenge_text(kind, who, stake), "%s challenge" % ("Pool" if kind == "pool" else "Twenty-One"))


func _pay_now() -> void:
	var m := selected()
	if m.is_empty() or _busy:
		return
	_busy = true
	_label = "Pay %s to %s" % [ArcadePay.fmt(m["stake"]), TableBook.short(m["winner"])]
	_refresh_detail()
	var r: Dictionary = await TableBook.pay_debt(m["winner"], m["stake"])
	_busy = false
	if r["ok"]:
		_status.text = "Paid: the Transfer is in block %d. Re-reading the debts…" % r["block"]
		await book.settle(r["block"])
	refresh()


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if not visible or label != _label:
		return
	match stage:
		"simulate": _status.text = "Simulating from your wallet…"
		"sign": _status.text = "Waiting for your signature in the browser wallet…"
		"pending": _status.text = "Sent %s · waiting for the receipt…" % String(info.get("hash", ""))
		"confirmed": _status.text = "Mined in block %d. Reading it back from the chain…" % int(info.get("block", -1))
		"failed": _status.text = "Not done (%s): %s" % [String(info.get("stage", "?")), String(info.get("message", ""))]


# --- Views --------------------------------------------------------------------

class PoolView extends Control:
	## The table from above. When it's your shot, the mouse aims from the cue ball.
	var aim := Vector2i.ZERO
	var _snap := PackedInt64Array()
	var _frames: Array = []
	var _t := 0.0
	var _can_aim := false
	var _mouse := Vector2.ZERO
	var _caption := ""

	func _init() -> void:
		custom_minimum_size = Vector2(580, 330)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func show_match(m: Dictionary, my_turn: bool) -> void:
		_can_aim = my_turn and _frames.is_empty()
		if m.is_empty() or m["game"] == null:
			_snap = PoolSim.new().snapshot()
			_caption = "" if m.is_empty() else "waiting for someone to accept"
		else:
			var g: EightBall = m["game"]
			if _frames.is_empty():
				_snap = g.sim.snapshot()
			var t := TableBook.turn_index(m)
			_caption = ("your shot" if my_turn else "waiting for %s" % TableBook.short(m["players"][t])) if t >= 0 else ""
			if g.groups[0] != "":
				_caption += "  ·  breaker: %s, other: %s" % [g.groups[0], g.groups[1]]
		queue_redraw()

	func play_shot(before: PackedInt64Array, dx: int, dy: int, power: int, _m: Dictionary) -> void:
		var sim := PoolSim.new()
		sim.apply_snapshot(before)
		_frames = sim.shoot(dx, dy, power, PoolTable3D.FRAME_EVERY).get("frames", [])
		_t = 0.0

	func _process(delta: float) -> void:
		if _frames.is_empty():
			return
		_t += delta * 60.0
		var i := int(_t)
		if i >= _frames.size():
			_snap = _frames[-1]
			_frames.clear()
		else:
			_snap = _frames[i]
		queue_redraw()

	func _rect() -> Rect2:
		var w := size.x - 40.0
		var h := w * 0.5
		if h > size.y - 60.0:
			h = size.y - 60.0
			w = h * 2.0
		return Rect2(Vector2((size.x - w) * 0.5, 18.0), Vector2(w, h))

	func _to_screen(x: int, y: int) -> Vector2:
		var r := _rect()
		return r.position + Vector2(float(x) / PoolSim.W * r.size.x, float(y) / PoolSim.H * r.size.y)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			_mouse = event.position
			if _can_aim and _snap.size() >= 48 and _snap[2] == 0:
				var cue := _to_screen(_snap[0], _snap[1])
				var d := _mouse - cue
				if d.length() > 4.0:
					var n := d.normalized()
					aim = Vector2i(int(round(n.x * 10000.0)), int(round(n.y * 10000.0)))
			queue_redraw()

	func _draw() -> void:
		var r := _rect()
		draw_rect(r.grow(14.0), Color(0.28, 0.14, 0.07))
		draw_rect(r, Color(0.05, 0.36, 0.2))
		var scale := r.size.x / float(PoolSim.W)
		for p in PoolSim.pockets():
			draw_circle(_to_screen(p.x, p.y), 0.06e6 * scale, Color(0.02, 0.02, 0.02))
		if _snap.size() < 48:
			return
		var rad := PoolSim.R * scale
		for i in 16:
			if _snap[i * 3 + 2] != 0:
				continue
			var c := _to_screen(_snap[i * 3], _snap[i * 3 + 1])
			var base: Color = PoolTable3D.COLORS[i if i <= 8 else i - 8]
			if i >= 9:
				draw_circle(c, rad, Color(0.95, 0.94, 0.9))
				draw_rect(Rect2(c - Vector2(rad, rad * 0.45), Vector2(rad * 2.0, rad * 0.9)), base)
			else:
				draw_circle(c, rad, base)
			if i > 0:
				draw_string(ThemeDB.fallback_font, c + Vector2(-rad * 0.6, rad * 0.4), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, int(rad * 1.1), Color.WHITE if i == 8 else Color.BLACK)
		if _can_aim and aim != Vector2i.ZERO and _snap[2] == 0:
			var cue := _to_screen(_snap[0], _snap[1])
			var dir := Vector2(aim.x, aim.y).normalized()
			draw_line(cue, cue + dir * r.size.x * 0.6, Color(1, 1, 1, 0.55), 1.5)
			draw_line(cue - dir * rad * 1.5, cue - dir * rad * 9.0, Color(0.85, 0.7, 0.45), 3.0)  # the cue
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.end.y + 26.0), _caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.9, 1.0))


class CardsView extends Control:
	var _m := {}
	var _book: TableBook

	func _init() -> void:
		custom_minimum_size = Vector2(580, 300)

	func show_match(m: Dictionary, book: TableBook) -> void:
		_m = m
		_book = book
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.32, 0.06, 0.08))
		if _m.is_empty() or _m["game"] == null:
			draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Waiting for someone to accept." if not _m.is_empty() else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			return
		var d: Duel21 = _m["game"]
		for p in 2:
			var y := 30.0 + p * 140.0
			var who := _book.display(_m["players"][p]) if _book else String(_m["players"][p])
			var turn := "  ← to play" if TableBook.turn_index(_m) == p else ("  · stood" if d.stood[p] else "")
			draw_string(ThemeDB.fallback_font, Vector2(20, y), "%s  ·  %d%s" % [who, Duel21.total(d.hands[p]), turn], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.92, 0.8))
			var hand: Array = d.hands[p]
			for i in hand.size():
				var c: int = hand[i]
				var rect := Rect2(Vector2(20 + i * 74, y + 12), Vector2(64, 92))
				draw_rect(rect, Color(0.97, 0.96, 0.92))
				draw_rect(rect, Color(0.2, 0.2, 0.2), false, 1.5)
				var red := c / 13 == 1 or c / 13 == 2
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, 34), Duel21.card_name(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.75, 0.05, 0.08) if red else Color.BLACK)
