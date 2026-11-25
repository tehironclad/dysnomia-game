extends TestCase
## Invites (InviteBook), head-to-head replay over the game server (NetMatch) and
## honour-bound wagers (Wager). Pure: no network, no chain.

const A := "0x1111111111111111111111111111111111111111"
const B := "0x2222222222222222222222222222222222222222"
const C := "0x3333333333333333333333333333333333333333"
const ROOM := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


# --- InviteBook --------------------------------------------------------------

func test_stake_cleaning() -> void:
	eq(InviteBook.clean_stake(""), "")
	eq(InviteBook.clean_stake("0"), "")
	eq(InviteBook.clean_stake("0.000"), "")
	eq(InviteBook.clean_stake(" 5 Ⓐ"), "5")
	eq(InviteBook.clean_stake("007.50"), "7.5")
	eq(InviteBook.clean_stake("0.25"), "0.25")
	eq(InviteBook.clean_stake("-1"), "!")
	eq(InviteBook.clean_stake("1e3"), "!")
	eq(InviteBook.clean_stake("12345678"), "!", "more than 7 whole digits")
	eq(InviteBook.clean_stake("1." + "1".repeat(19)), "!", "more than 18 decimals")


func test_invite_lifecycle() -> void:
	var book := InviteBook.new()
	var r := book.create("i1", A, "Alice", B, "Bob", "pool", "5", ROOM, "arcade", 1000)
	check(r["ok"], "created: %s" % r.get("error", ""))
	var inv: Dictionary = r["invite"]
	eq(inv["state"], "pending")
	eq(inv["expires"], 1000 + InviteBook.TTL_S)
	eq(InviteBook.seconds_left(inv, 1030), InviteBook.TTL_S - 30)
	# only B may accept or decline, only A may cancel
	check(not book.answer("i1", A, "accept", 1010)["ok"], "the inviter can't accept")
	check(not book.answer("i1", C, "decline", 1010)["ok"], "a stranger can't decline")
	check(not book.answer("i1", B, "cancel", 1010)["ok"], "the invitee can't cancel")
	check(not book.answer("i1", B, "maybe", 1010)["ok"], "unknown answers are refused")
	var ok := book.answer("i1", B, "accept", 1020)
	check(ok["ok"])
	eq(inv["state"], "accepted")
	var again := book.answer("i1", B, "decline", 1021)
	check(not again["ok"] and String(again["error"]).contains("accepted"), "a finished invite can't change")


func test_invite_expiry_and_cancel() -> void:
	var book := InviteBook.new()
	book.create("i1", A, "", B, "", "cards", "", ROOM, "arcade", 0)
	book.create("i2", A, "", C, "", "cards", "", ROOM, "arcade", 0)
	eq(book.expire(InviteBook.TTL_S - 1).size(), 0, "not yet")
	check(book.answer("i2", A, "cancel", 10)["ok"])
	eq(book.invites["i2"]["state"], "cancelled")
	var gone := book.expire(InviteBook.TTL_S)
	eq(gone.size(), 1, "one expired")
	eq(book.invites["i1"]["state"], "expired")
	# answering after the time expires it
	book.create("i3", B, "", A, "", "pool", "", ROOM, "arcade", 100)
	var late := book.answer("i3", A, "accept", 100 + InviteBook.TTL_S + 5)
	check(not late["ok"])
	eq(book.invites["i3"]["state"], "expired")
	book.prune(100 + InviteBook.TTL_S + 5 + InviteBook.KEEP_S + 1)
	check(book.invites.is_empty(), "finished invites are forgotten after KEEP_S")


func test_invite_validation() -> void:
	var book := InviteBook.new()
	check(not book.create("x", A, "", A, "", "pool", "", ROOM, "arcade", 0)["ok"], "not yourself")
	check(not book.create("x", A, "", "0x12", "", "pool", "", ROOM, "arcade", 0)["ok"], "a full wallet")
	check(not book.create("x", A, "", B, "", "chess", "", ROOM, "arcade", 0)["ok"], "a known game")
	check(not book.create("x", A, "", B, "", "pool", "lots", ROOM, "arcade", 0)["ok"], "a numeric stake")
	check(not book.create("x", A, "", B, "", "pool", "", "nowhere", "arcade", 0)["ok"], "a QING room")
	check(not book.create("x", A, "", B, "", "pool", "", ROOM, "void", 0)["ok"], "the game's own door")
	check(book.create("x", A, "", B, "", "pool", "", ROOM, "arcade", 0)["ok"])
	check(not book.create("y", A, "", B, "", "pool", "", ROOM, "arcade", 0)["ok"], "no duplicate invite to the same game")
	check(not book.create("x", A, "", C, "", "cards", "", ROOM, "arcade", 0)["ok"], "no duplicate id")
	check(book.create("y", A, "", B, "", "cards", "", ROOM, "arcade", 0)["ok"], "another game is fine")
	check(book.create("z", A, "", C, "", "pool", "", ROOM, "arcade", 0)["ok"])
	var r := book.create("w", A, "", C, "", "cards", "", ROOM, "arcade", 0)
	check(not r["ok"] and String(r["error"]).contains("waiting"), "at most MAX_OPEN_PER_WALLET pending")
	eq(book.for_wallet(A).size(), 3)
	eq(book.for_wallet(C).size(), 1)
	check(InviteBook.ops_for("pool").has("shot") and InviteBook.ops_for("pool").has("concede"))
	check(not InviteBook.ops_for("pool").has("hit"), "pool takes no hits")
	eq(InviteBook.ops_for("chess"), [])


func test_invite_messages_fit() -> void:
	var inv := NetProto.json_msg(NetProto.C_INVITE, {"to": A, "game": "cards", "stake": "1234567.123456789012345678", "room": ROOM, "door": "arcade"})
	check(NetProto.size_ok(inv), "the largest invite fits (%d B)" % inv.size())
	var mv := NetProto.json_msg(NetProto.C_MOVE, {"match": "n1234567", "op": "shot", "a": [-100000, -100000, 1000]})
	check(NetProto.size_ok(mv), "a shot fits (%d B)" % mv.size())
	check(NetProto.size_ok(NetProto.json_msg(NetProto.C_RESULT, {"match": "n1234567", "winner": 2, "digest": "ab".repeat(16)})))
	check(NetProto.size_ok(NetProto.json_msg(NetProto.C_ANSWER, {"id": "abcdef12", "answer": "decline"})))
	check(NetProto.FEATURES.has("invites"))


# --- NetMatch ------------------------------------------------------------------

func _rec(game: String, stake: String, log: Array) -> Dictionary:
	return {"id": "n1a2b3c4", "game": game, "players": [A, B], "names": ["Alice", "Bob"], "stake": stake,
		"room": ROOM, "door": "arcade", "created": 1_700_000_000_000, "log": log}


func _e(seq: int, by: int, op: String, a: Array = [], t: int = 0) -> Dictionary:
	return {"seq": seq, "by": by, "op": op, "a": a, "t": 1_700_000_000_000 + (t if t > 0 else seq * 1000)}


static func _fake_block(unix_s: int) -> Dictionary:
	return {"hash": "0x" + str(unix_s).sha256_text(), "number": unix_s - 1_700_000_000 + 900}


func test_pool_replays_identically() -> void:
	var log := [_e(1, 0, "sit"), _e(2, 1, "sit"), _e(3, 0, "shot", [10000, 120, 1000]), _e(4, 1, "shot", [-7000, 7000, 600]), _e(5, 0, "shot", [9000, -3000, 800])]
	var a := NetMatch.replay(_rec("pool", "", log), _fake_block)
	var b := NetMatch.replay(_rec("pool", "", log), _fake_block)
	eq(a.digest(), b.digest(), "two machines, one outcome")
	eq(a.m["status"], "playing")
	check(a.m["seated"][0] and a.m["seated"][1], "both sat down")
	check(a.m.has("last_shot") and String(a.m["last_shot"]["tx"]).begins_with("net:n1a2b3c4:"), "the last shot is tagged for the table's animation")
	check((a.m["game"] as EightBall).shots >= 2, "the shots on turn were played")
	# the same shots straight into EightBall give the same table
	var g := EightBall.new()
	for e in log:
		if e["op"] == "shot":
			g.shot(g.turn, e["a"][0], e["a"][1], e["a"][2])
	eq(Array(g.sim.snapshot()), Array((a.m["game"] as EightBall).sim.snapshot()), "the replay is EightBall's own")


func test_pool_out_of_turn_is_ignored() -> void:
	var nm := NetMatch.new(_rec("pool", "", []))
	var r := nm.apply(_e(1, 1, "shot", [10000, 0, 500]))
	check(not r["ok"], "player 1 can't break")
	eq((nm.m["game"] as EightBall).shots, 0)
	check(nm.apply(_e(2, 0, "shot", [10000, 0, 500]))["ok"])
	check(not nm.apply(_e(3, 0, "hit"))["ok"], "pool takes no hits")
	check(not nm.apply(_e(4, 5, "concede"))["ok"], "not a player")


func test_concede_and_claim() -> void:
	var nm := NetMatch.new(_rec("pool", "", []))
	check(nm.apply(_e(1, 0, "shot", [10000, 0, 500]))["ok"])
	var waiting := 1 - int((nm.m["game"] as EightBall).turn)
	var last_t: int = 1_700_000_000_000 + 1000
	check(not nm.apply(_e(2, waiting, "claim", [], 2000 + 1000))["ok"], "too early to claim")
	check(not nm.apply(_e(3, 1 - waiting, "claim", [], 1000 + NetMatch.IDLE_CLAIM_MS + 5000))["ok"], "the player on turn can't claim")
	check(nm.apply(_e(4, waiting, "claim", [], 1000 + NetMatch.IDLE_CLAIM_MS + 5000))["ok"], "claimed after the idle time")
	eq(nm.m["status"], "over")
	eq(nm.m["winner"], nm.m["players"][waiting])
	eq(nm.m["end_t"], last_t + NetMatch.IDLE_CLAIM_MS + 5000)
	var c := NetMatch.new(_rec("cards", "", []))
	c.deal(_fake_block(c.needs_block()))
	check(c.apply(_e(1, 1, "concede"))["ok"])
	eq(c.m["winner"], A)
	eq(c.winner_index(), 0)
	check(not c.apply(_e(2, 0, "concede"))["ok"], "over is over")


func test_stake_needs_both() -> void:
	var nm := NetMatch.new(_rec("pool", "5", []))
	eq(nm.m["status"], "confirm")
	eq(Wager.code(nm.m), "proposed")
	check(not nm.apply(_e(1, 0, "shot", [10000, 0, 500]))["ok"], "no play before the stake is settled")
	check(nm.apply(_e(2, 0, "stake_ok"))["ok"])
	eq(nm.m["status"], "confirm", "one confirmation is not enough")
	check(Wager.text(nm.m, A).contains("Bob") or Wager.text(nm.m, A).contains("0x2222"), "says who must still confirm: %s" % Wager.text(nm.m, A))
	check(nm.apply(_e(3, 1, "stake_ok"))["ok"])
	eq(nm.m["status"], "playing")
	eq(nm.m["stake_state"], "agreed")
	eq(BigInt.to_decimal(nm.m["stake"]), "5000000000000000000")
	eq(Wager.code(nm.m), "agreed")
	var no := NetMatch.replay(_rec("pool", "5", [_e(1, 1, "stake_no")]), _fake_block)
	eq(no.m["status"], "playing")
	eq(Wager.code(no.m), "dropped")
	check(BigInt.is_zero(no.m["stake"]), "no stake after a refusal")


func test_cards_dealt_from_blocks_after_the_move() -> void:
	var log := [_e(1, 0, "stake_ok"), _e(2, 1, "stake_ok", [], 4000), _e(3, 0, "hit", [], 9000), _e(4, 0, "stand", [], 12000),
		_e(5, 1, "hit", [], 15000), _e(6, 1, "hit", [], 21000)]
	var asked: Array = []
	var src := func(s: int) -> Dictionary:
		asked.append(s)
		return _fake_block(s)
	var nm := NetMatch.replay(_rec("cards", "2", log), src)
	var base := 1_700_000_000
	check(asked.has(base + 4 + NetMatch.CARD_MARGIN_S), "the deal is the first block %d s after the stake was agreed (asked %s)" % [NetMatch.CARD_MARGIN_S, asked])
	check(asked.has(base + 9 + NetMatch.CARD_MARGIN_S), "the hit is the first block %d s after the hit was stamped" % NetMatch.CARD_MARGIN_S)
	var d: Duel21 = nm.m["game"]
	check(d.dealt)
	eq(nm.m["deal_block"], _fake_block(base + 4 + NetMatch.CARD_MARGIN_S)["number"])
	# the same cards straight from Duel21 with the same hashes
	var ref := Duel21.new()
	ref.deal(_fake_block(base + 6)["hash"])
	ref.hit(0, _fake_block(base + 11)["hash"])
	if not ref.over():
		ref.stand(0)
	eq(d.hands[0], ref.hands[0], "player 0's hand is Duel21's own")
	var nm2 := NetMatch.replay(_rec("cards", "2", log), _fake_block)
	eq(nm.digest(), nm2.digest(), "both machines agree")


func test_cards_wait_for_the_deal() -> void:
	var nm := NetMatch.new(_rec("cards", "", []))
	check(nm.needs_block() > 0, "a game without a stake deals at once: from the first block after its creation")
	eq(nm.needs_block(), NetMatch.anchor_of(1_700_000_000_000))
	check(not nm.apply(_e(1, 0, "stand"))["ok"], "no move before the deal")
	check(not nm.deal({"hash": "0x12", "number": 5}), "a malformed hash deals nothing")
	check(nm.deal(_fake_block(nm.needs_block())))
	eq(nm.needs_block(), -1)
	eq(nm.hash_anchor(_e(2, 1, "hit")), -1, "player 1 can't hit first: no card is drawn for it")
	check(nm.hash_anchor(_e(2, 0, "hit")) > 0)
	check(not nm.apply(_e(3, 0, "hit"), {})["ok"], "a hit with no block draws nothing")


func test_push_and_debts() -> void:
	var nm := NetMatch.new(_rec("cards", "", []))
	nm.deal(_fake_block(nm.needs_block()))
	nm.apply(_e(1, 0, "stand"))
	nm.apply(_e(2, 1, "stand"))
	check(nm.over())
	var d: Duel21 = nm.m["game"]
	var expect := 2 if Duel21.total(d.hands[0]) == Duel21.total(d.hands[1]) else (0 if Duel21.total(d.hands[0]) > Duel21.total(d.hands[1]) else 1)
	eq(nm.winner_index(), expect)


# --- Wager -------------------------------------------------------------------

func test_wager_states() -> void:
	eq(Wager.code({}), "none")
	var nm := NetMatch.replay(_rec("pool", "3", [_e(1, 0, "stake_ok"), _e(2, 1, "stake_ok"), _e(3, 1, "concede")]), _fake_block)
	eq(nm.m["winner"], A)
	eq(Wager.code(nm.m), "owed", "over, not read from the chain yet")
	check(Wager.text(nm.m, A).contains("checking"), "unread is said, not guessed")
	nm.m["end_block"] = 100
	var debt := Wager.debt(nm.m)
	eq(debt["loser"], B)
	nm.m["paid"] = false
	eq(Wager.code(nm.m), "unpaid")
	check(Wager.i_owe(nm.m, B) and not Wager.i_owe(nm.m, A))
	check(Wager.text(nm.m, B).begins_with("⚠ unpaid: you owe"), Wager.text(nm.m, B))
	# the payment is matched the way room-line debts are: a Transfer at or after the end block
	var res := TableBook.allocate([debt], [{"block": 99, "value": BigInt.from_decimal("3000000000000000000")}])
	check(not res[0]["paid"], "a transfer before the game ended doesn't pay it")
	res = TableBook.allocate([debt], [{"block": 120, "value": BigInt.from_decimal("1000000000000000000")}, {"block": 130, "value": BigInt.from_decimal("2000000000000000000")}])
	check(res[0]["paid"] and res[0]["paid_block"] == 130, "two transfers pay 3 Ⓐ")
	nm.m["paid"] = true
	nm.m["paid_block"] = 130
	check(Wager.text(nm.m, A).begins_with("✓ paid") and Wager.text(nm.m, A).contains("130"), Wager.text(nm.m, A))
	var conf := NetMatch.new(_rec("pool", "3", []))
	conf.apply(_e(1, 0, "concede"))
	eq(Wager.code(conf.m), "dropped", "conceding before the stake was agreed owes nothing")
	check(Wager.debt(conf.m).is_empty())


func test_wager_words() -> void:
	var nm := NetMatch.replay(_rec("cards", "1", [_e(1, 0, "stake_ok"), _e(2, 1, "stake_ok"), _e(3, 0, "concede")]), _fake_block)
	eq(nm.m["winner"], B)
	check(Wager.text(nm.m, A).begins_with("you owe "), "you owe, not you owes: %s" % Wager.text(nm.m, A))
	check(Wager.text(nm.m, B).contains("owes you"), Wager.text(nm.m, B))
	eq(Wager.short(nm.m, A), "you owe 1 Ⓐ · checking the chain")
	nm.m["paid"] = false
	eq(Wager.short(nm.m, A), "⚠ 1 Ⓐ unpaid (yours to pay)")
	nm.m["disputed"] = true
	eq(Wager.code(nm.m), "disputed")
	check(Wager.debt(nm.m).is_empty(), "a disputed game owes nothing")


func test_offline_says_invites_need_the_server() -> void:
	var inv: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Invites")
	check(String(inv.blocker()).begins_with("Invites need the game server"), "offline: %s" % inv.blocker())
	eq(inv.me(), "", "nobody is signed in offline")
	eq(inv.invite(B, "pool", ""), inv.blocker(), "inviting offline says why")
	eq(inv.table_match(ROOM, "pool", A), {}, "no game over the server: the tables play room lines as before")
	var p := NotificationPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.open()
	check(p.is_open())
	check(String(p._online_note.text).contains("game server"), "the panel says invites need the server: %s" % p._online_note.text)
	p.close()
	p.free()
