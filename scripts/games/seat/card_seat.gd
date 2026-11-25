class_name CardSeat
extends Node
## Twenty-One in first person. You sit on your stool at the card table: the
## dealer's shoe across the felt (it says which block dealt), your cards dealt
## onto the felt in front of you, the other player's seat and hand beside
## yours, chips for the stake. HIT and STAND are plates on the felt you can
## click, or keys.
##
## Live games are the room's lines as before (TableBook): a hit or a stand is
## a room line (simulate, sign, receipt, read back), and a card appears only
## when the chain has the line, drawn from that line's block hash (Duel21).
## A game over the game server (an invite: Invites, NetMatch) plays the same way:
## a hit or a stand goes to the server, and each card is the hash of the first
## block mined at least NetMatch.CARD_MARGIN_S after the server stamped the move.
## Practice (no live game of yours): you against the house on this computer,
## dealt from the latest block's hash read from the chain (no hash: no cards,
## "—"); the house draws to 17. Nothing is posted.

const HOUSE_STANDS := 17
const HOUSE_PAUSE := 0.8

var place: Node  # GamesPlace
var table: CardTable3D
var seat: TableSeat
var book: TableBook
var mode := "practice"  # play | wait | watch | practice
var match_id := ""
var my_seat := 0
var overhead := false
var practice: Duel21
var practice_block := -1
var _busy := false
var _label := ""
var _hover := ""
var _result_shown := ""


## The house's rule in practice: draw below 17.
static func house_hits(hand: Array) -> bool:
	return Duel21.total(hand) < HOUSE_STANDS


## The outcome for seat `me` of a finished Duel21: "win" | "lose" | "push" | "" (not over).
static func outcome(d: Duel21, me: int) -> String:
	if d == null or not d.over():
		return ""
	if d.winner == 2:
		return "push"
	return "win" if d.winner == me else "lose"


## Chips to stack for a stake (wei): one per whole Ⓐ, at least one, at most 12.
static func chips_for(stake: PackedInt64Array) -> int:
	if BigInt.is_zero(stake):
		return 0
	var whole := BigInt.to_decimal(stake)
	whole = whole.left(maxi(0, whole.length() - 18))
	if whole == "" or whole.length() > 3:
		return 1 if whole == "" else 12
	return clampi(int(whole), 1, 12)


func setup(p_place: Node, p_table: CardTable3D, p_seat: TableSeat, p_book: TableBook) -> void:
	place = p_place
	table = p_table
	seat = p_seat
	book = p_book
	Wallet.tx_stage.connect(_on_stage)


func is_active() -> bool:
	return seat.is_active() and seat.get_meta("owner", null) == self


func sit() -> void:
	seat.set_meta("owner", self)
	overhead = false
	_result_shown = ""
	_pick_mode()
	table.show_caption(false)
	book.changed.connect(_on_book)
	seat.title.text = "TWENTY-ONE · %s" % String(place.territory.get("name", "")).to_upper()
	_show(false)
	seat.enter(_view_xf(), 54.0, place.player.get_node_or_null("PlayerModel"), [place.hud_layer])
	seat.howto.setup(howto_spec())
	seat.howto.open_card(GameHowto.Mode.KEY)
	await seat.entered
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if mode == "practice" and (practice == null or practice.over()):
		await _practice_deal()
	else:
		_show(true)


## The how-to card: Twenty-One's rules (cards from block hashes), this seat's mode, the controls.
func howto_spec() -> Dictionary:
	var rules := PackedStringArray(["Get closer to 21 than the other hand without going over. Aces count 11 or 1; faces 10. A tie is a push.",
		"Every card comes from a block hash: SHA-256(block hash : draw) over the cards left. Nobody knows a card before its block.",
		"Hit to draw a card; stand to hold. Over 21 is bust."])
	match mode:
		"practice": rules.append("Practice against the house, dealt from the latest block; nothing is posted. A live game starts from the games list (%s)." % ControlsHelp.key_of("table_lobby"))
		"play": rules.append("Live game %s: each hit or stand is a room line signed in your wallet; the card is that line's block hash." % match_id)
		_: rules.append("Live game %s: every move replays here from its room line." % match_id)
	return {"title": "Twenty-One", "tag": String(place.territory.get("name", "")), "rules": rules,
		"controls": controls(), "accent": TableSeat.GOLD, "verb": "play", "esc": "stand up"}


## [[key, words]] for the card and the strip.
func controls() -> Array:
	var rows: Array = []
	var again := mode == "practice" and (practice == null or practice.over())
	if again:
		rows.append([ControlsHelp.key_of("table_hit"), "deal again (new block hash)"])
	elif mode == "play" or mode == "practice":
		rows.append([ControlsHelp.key_of("table_hit"), "hit"])
		rows.append([ControlsHelp.key_of("table_stand"), "stand"])
		rows.append(["Click", "the plates on the table"])
	else:
		rows.append(["", "watching"])
	rows.append([ControlsHelp.key_of("table_view"), "back to your seat" if overhead else "table view"])
	rows.append([ControlsHelp.key_of("table_lobby"), "games & challenges"])
	rows.append([ControlsHelp.key_of("notifications"), "invite a player online"])
	rows.append(["Esc", "stand up"])
	return rows


func stand() -> void:
	if book.changed.is_connected(_on_book):
		book.changed.disconnect(_on_book)
	table.show_buttons(-1)
	table.show_caption(true)
	seat.leave()
	await seat.exited
	seat.remove_meta("owner")


func _match() -> Dictionary:
	if match_id.begins_with("n"):
		return Invites.match_dict(match_id)  # a game over the game server
	return book.by_id.get(match_id, {}) if match_id != "" else {}


func _pick_mode() -> void:
	var m: Dictionary = place._latest("cards")
	var me := Session.wallet
	match_id = ""
	mode = "practice"
	my_seat = 0
	if not PoolSeat._live(m):
		return
	match_id = String(m["id"])
	var mine := TableBook.player_index(m, me)
	if mine < 0:
		mode = "watch"
		return
	my_seat = mine
	if m.get("net", false):
		Invites.sat_down(match_id)
	mode = "play" if TableBook.turn_index(m) == mine else "wait"


func _game() -> Duel21:
	if mode == "practice":
		return practice
	var m := _match()
	return m["game"] if not m.is_empty() else null


func _my_turn() -> bool:
	var d := _game()
	return d != null and not d.over() and d.dealt and d.turn == my_seat and (mode == "play" or mode == "practice")


# --- Input ----------------------------------------------------------------------

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var k := _button_under(event.position)
		if k != _hover:
			_hover = k
			table.hover_button(k)
		return false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var k := _button_under(event.position)
		if k != "":
			_act(k)
			return true
		return false
	if event.is_action_pressed("table_hit"):
		_act("hit")
		return true
	if event.is_action_pressed("table_stand"):
		_act("stand")
		return true
	if event.is_action_pressed("table_view"):
		overhead = not overhead
		seat.target = _view_xf()
		seat.snap()
		_refresh_texts()
		return true
	return false


func _button_under(pos: Vector2) -> String:
	if seat.cam == null or not seat.is_inside() or overhead:
		return ""
	var inv := table.global_transform.affine_inverse()
	var o := inv * seat.cam.project_ray_origin(pos)
	var d := inv.basis * seat.cam.project_ray_normal(pos)
	if d.y >= -0.001:
		return ""
	var t := (CardTable3D.TOP - o.y) / d.y
	return CardTable3D.button_at(my_seat, o + d * t)


func _act(op: String) -> void:
	if _busy or not seat.is_inside():
		return
	if mode == "practice":
		if practice == null or practice.over():
			if op == "hit":
				await _practice_deal()
			return
		if not _my_turn():
			return
		if op == "hit":
			await _practice_hit(0)
		else:
			practice.stand(0)
			_show(true)
			await _house_plays()
		return
	if mode != "play" or not _my_turn():
		return
	var nm := _match()
	if nm.get("net", false):
		if Invites.send_move(nm["id"], op):
			seat.status.text = "Sent \"%s\" to the game server.%s" % [op, " Your card is the hash of the first block mined at least %d s after the server stamps it: a few seconds." % NetMatch.CARD_MARGIN_S if op == "hit" else ""]
		else:
			seat.status.text = "Not sent: the game server isn't answering. Nothing was played."
		_show(true)
		return
	var b: String = place._table_blocker()
	if b != "":
		seat.status.text = b
		return
	var m := _match()
	_busy = true
	_label = "Twenty-One #%s %s" % [m["id"], op]
	_show(false)
	seat.status.text = "Posting \"%s\" as a room line…" % TableBook.move_text("cards", m["id"], op)
	var r: Dictionary = await TableBook.post(place.qing, TableBook.move_text("cards", m["id"], op), _label)
	_busy = false
	if not is_active():
		return
	if r["ok"]:
		seat.status.text = "On the chain: block %d. %s" % [r["block"], "The card is that block's hash." if op == "hit" else "You stand."]
		await book.feed([r["line"]])
	else:
		seat.status.text = "Not sent (%s): %s" % [String(r.get("stage", "?")), String(r.get("message", ""))]
	_show(true)


# --- Practice (local, dealt from real block hashes) -------------------------------

## The latest block: {ok, hash, block}.
static func latest_block() -> Dictionary:
	var r: Dictionary = await Chain.rpc.get_block("latest")
	if not r["ok"] or not (r["result"] is Dictionary):
		return {"ok": false}
	var h := String(r["result"].get("hash", ""))
	if not h.begins_with("0x") or h.length() != 66:
		return {"ok": false}
	return {"ok": true, "hash": h, "block": String(r["result"].get("number", "0x0")).hex_to_int()}


func _practice_deal() -> void:
	_busy = true
	_result_shown = ""
	seat.status.text = "Reading the latest block for the deal…"
	var b := await latest_block()
	_busy = false
	if not is_active():
		return
	if not b["ok"]:
		seat.status.text = "The latest block couldn't be read: — (no block hash, no cards; nothing is made up)."
		practice = null
		_show(false)
		return
	practice = Duel21.new()
	practice.deal(b["hash"])
	practice_block = b["block"]
	seat.status.text = "Dealt from block %s's hash." % ArcadeScores.grouped(practice_block)
	_show(true)


func _practice_hit(who: int) -> void:
	_busy = true
	var b := await latest_block()
	_busy = false
	if not is_active() or practice == null:
		return
	if not b["ok"]:
		seat.status.text = "The latest block couldn't be read: — (no card drawn)."
		return
	practice.hit(who, b["hash"])
	practice_block = b["block"]
	seat.status.text = "%s drew from block %s's hash (draw %d)." % ["You" if who == 0 else "The house", ArcadeScores.grouped(practice_block), practice.draws - 1]
	_show(true)


func _house_plays() -> void:
	_busy = true
	while is_active() and practice and not practice.over() and practice.turn == 1:
		await get_tree().create_timer(HOUSE_PAUSE).timeout
		if not is_active() or practice == null:
			break
		if house_hits(practice.hands[1]):
			_busy = false
			await _practice_hit(1)
			_busy = true
		else:
			practice.stand(1)
	_busy = false
	_show(true)


# --- Chain updates ----------------------------------------------------------------

func _on_book() -> void:
	if not is_active():
		return
	if mode == "practice":
		var m: Dictionary = place._latest("cards")
		if not m.is_empty() and m["status"] == "playing" and TableBook.player_index(m, Session.wallet) >= 0:
			seat.show_toast("Your game #%s is live: stand up (Esc) and sit again to play it." % m["id"])
		return
	var m := _match()
	if m.is_empty():
		_pick_mode()
	elif PoolSeat._live(m):
		var mine := TableBook.player_index(m, Session.wallet)
		mode = "watch" if mine < 0 else ("play" if TableBook.turn_index(m) == mine else "wait")
	_show(true)


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if not is_active() or label != _label:
		return
	match stage:
		"simulate": seat.status.text = "Simulating the line from your wallet…"
		"sign": seat.status.text = "Waiting for your signature in the browser wallet…"
		"pending": seat.status.text = "Sent %s · waiting for the receipt…" % String(info.get("hash", ""))
		"confirmed": seat.status.text = "Mined in block %d. Reading the line back from the chain…" % int(info.get("block", -1))


# --- Showing it -------------------------------------------------------------------

func _show(animate: bool) -> void:
	var d := _game()
	table.show_hands(d.hands if d else [[], []], animate)
	var seats: Array = []
	var m := _match()
	for i in 2:
		var name := ""
		if mode == "practice":
			name = "YOU" if i == 0 else "THE HOUSE"
		elif not m.is_empty():
			name = ("YOU · " if i == my_seat and mode != "watch" else "") + book.display(m["players"][i])
		var note := ""
		if d and d.dealt:
			if Duel21.total(d.hands[i]) > 21:
				note = " BUST"
			elif d.stood[i]:
				note = " ✓"
		seats.append({"name": name, "total": Duel21.total(d.hands[i]) if d and d.dealt else -1, "turn": d != null and d.dealt and not d.over() and d.turn == i, "note": note})
	table.set_seats(seats)
	if mode == "practice":
		table.set_chips(0, "")
		table.set_dealer(("PRACTICE DEAL\nblock %s" % ArcadeScores.grouped(practice_block)) if practice else "PRACTICE\nno block read: —")
	elif not m.is_empty():
		table.set_chips(chips_for(m["stake"]), ArcadePay.fmt(m["stake"]) if not BigInt.is_zero(m["stake"]) else "")
		var db := int(m.get("deal_block", m["created_block"]))
		table.set_dealer(("DEALT BY THE CHAIN\nblock %s" % ArcadeScores.grouped(db)) if db >= 0 else "DEALT BY THE CHAIN\nthe next block…")
	var can := _my_turn() and not _busy
	table.show_buttons(my_seat if (mode == "play" or mode == "practice") and not overhead else -1, can or (mode == "practice" and (practice == null or practice.over())))
	_refresh_texts()
	var oc := outcome(d, my_seat)
	var key := "%s:%s:%d" % [match_id, oc, d.draws if d else 0]
	if oc != "" and key != _result_shown:
		_result_shown = key
		var text := "PUSH"
		var col := TableSeat.ICE
		if oc != "push":
			if mode == "watch":
				text = "%s WON" % book.display(m["winner"]).to_upper()
				col = TableSeat.GOLD
			else:
				text = "YOU WIN" if oc == "win" else "YOU LOSE"
				col = TableSeat.LIVE if oc == "win" else TableSeat.MAGENTA
		seat.call_out(text, col, 4.0)


func _refresh_texts() -> void:
	var d := _game()
	var m := _match()
	var you := Duel21.total(d.hands[my_seat]) if d and d.dealt else -1
	var them := Duel21.total(d.hands[1 - my_seat]) if d and d.dealt else -1
	match mode:
		"practice":
			seat.set_badge("PRACTICE vs the house · on this computer only: cards from the latest block's hash, nothing is posted. A live game starts from the table's list (%s)." % ControlsHelp.key_of("table_lobby"), false)
			seat.source.text = "Each card: SHA-256(\"<block hash>:<draw n>\") mod the cards left (Duel21), the same rule as a live game; the house draws below %d." % HOUSE_STANDS
		_:
			seat.set_badge("LIVE GAME #%s · %s vs %s · every hit and stand is a room line; each card is the hash of the block holding the line" % [m.get("id", "—"), book.display(m["players"][0]) if not m.is_empty() else "—", book.display(m["players"][1]) if not m.is_empty() else "—"], true)
			if not m.is_empty():
				seat.source.text = "Cards: SHA-256(\"<block hash>:<draw n>\") mod the cards left; the deal is the accept line's block (%d), each hit its own line's block. Who moved = the line's tx.from." % int(m.get("deal_block", m["created_block"]))
	if d == null or not d.dealt:
		seat.headline.text = "—" if mode == "practice" else "WAITING"
	elif d.over():
		seat.headline.text = "%d vs %d" % [you, them]
	elif _my_turn():
		seat.headline.text = "%d · HIT OR STAND?" % you
	else:
		seat.headline.text = "%d · %s" % [you, "THE HOUSE DRAWS" if mode == "practice" else "THEIR MOVE"]
	var lines: Array = []
	if d and d.dealt:
		lines.append("%s: %d%s" % ["you" if mode != "watch" else "seat 1", you, " (bust)" if you > 21 else ""])
		lines.append("%s: %d%s" % ["the house" if mode == "practice" else ("them" if mode != "watch" else "seat 2"), them, " (bust)" if them > 21 else ""])
		lines.append("cards left in the deck: %d" % d.deck.size())
	if not m.is_empty() and m.get("net", false):
		if Wager.code(m) != "none":
			lines.append(Wager.short(m, Session.wallet))
		if String(m.get("waiting", "")) != "":
			seat.status.text = "Waiting for %s." % m["waiting"]
		elif seat.status.text.begins_with("Waiting for"):
			seat.status.text = ""
		seat.set_badge("GAME #%s OVER THE GAME SERVER · %s vs %s · a hit or a stand goes to the server (no transaction); each card is the hash of the first block after the server stamped the move%s" % [
			m["id"], book.display(m["players"][0]), book.display(m["players"][1]),
			(" · CONFIRM THE STAKE: %s" % ControlsHelp.key_of("notifications")) if m["status"] == "confirm" else ""], true)
		seat.source.text = "Cards: SHA-256(\"<block hash>:<draw n>\") mod the cards left (Duel21); the deal is the first block at least %d s after the game started (block %s), each hit the first block %d s after the server stamped it. %d moves in the server's log; both machines must agree on the result." % [
			NetMatch.CARD_MARGIN_S, str(m["deal_block"]) if int(m["deal_block"]) >= 0 else "not mined yet", NetMatch.CARD_MARGIN_S, int(m.get("moves", 0))]
	elif not m.is_empty() and not BigInt.is_zero(m["stake"]):
		lines.append("stake: %s (honour-bound)" % ArcadePay.fmt(m["stake"]))
	seat.stats.text = "\n".join(lines)
	seat.set_controls(controls())


func _view_xf() -> Transform3D:
	var g := table.global_transform
	if overhead:
		return g * Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, CardTable3D.TOP + 1.75, 0.12))
	return g * CardTable3D.seat_eye(my_seat)


## Previews (tools/screenshot.gd): "seated" deals a practice hand from the latest block and hits once.
func preview(phase: String) -> void:
	if phase != "howto":
		seat.howto.close_card(false)
	while _busy or (practice == null and is_active() and seat.status.text.begins_with("Reading")):
		await get_tree().process_frame
	if phase == "seated" and practice and not practice.over():
		await _practice_hit(0)
