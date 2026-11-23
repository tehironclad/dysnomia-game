extends TestCase
## Pool and Twenty-One played over room lines, and arcade payments: integer
## physics, rules, chain-dealt cards, line parsing, replay, and wager
## settlement. No network.

const A := "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B := "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const C := "0xcccccccccccccccccccccccccccccccccccccccc"
const HASH1 := "0x1111111111111111111111111111111111111111111111111111111111111111"
const HASH2 := "0x2222222222222222222222222222222222222222222222222222222222222222"


func test_pool_rack_and_break_is_deterministic() -> void:
	var a := PoolSim.new()
	var b := PoolSim.new()
	eq(a.digest(), b.digest())
	for i in 16:
		check(a.px[i] > PoolSim.R and a.px[i] < PoolSim.W - PoolSim.R, "ball %d inside the rails" % i)
	var ra := a.shoot(1000, 7, 1000)
	var rb := b.shoot(1000, 7, 1000)
	eq(a.digest(), b.digest(), "same break, same table")
	eq(ra["first_contact"], 1, "the break hits the apex ball")
	eq(ra["pocketed"], rb["pocketed"])
	check(ra["ticks"] < PoolSim.MAX_TICKS, "the table comes to rest")
	# Everything still on the table lies inside the rails and nothing overlaps much.
	for i in 16:
		if a.on_table(i):
			check(a.px[i] >= PoolSim.R - 1 and a.px[i] <= PoolSim.W - PoolSim.R + 1 and a.py[i] >= PoolSim.R - 1 and a.py[i] <= PoolSim.H - PoolSim.R + 1, "ball %d inside" % i)


func test_pool_straight_pot() -> void:
	var s := PoolSim.new()
	for i in range(1, 16):
		s.down[i] = 1
	s.down[3] = 0
	s.px[3] = PoolSim.W - 200000
	s.py[3] = PoolSim.H / 2
	s.px[0] = PoolSim.W / 2
	s.py[0] = PoolSim.H / 2
	# Aim the 3 at the far corner pocket (W, H): cue ball behind it on that line.
	var dx := PoolSim.W - s.px[3]
	var dy := PoolSim.H - s.py[3]
	var d := PoolSim.isqrt(dx * dx + dy * dy)
	s.px[0] = s.px[3] - dx * (2 * PoolSim.R + 300000) / d
	s.py[0] = s.py[3] - dy * (2 * PoolSim.R + 300000) / d
	var r := s.shoot(dx, dy, 600)
	eq(r["first_contact"], 3)
	check(r["pocketed"].has(3), "the 3 drops in the corner: %s" % [r["pocketed"]])


func test_isqrt() -> void:
	for n in [0, 1, 2, 3, 4, 15, 16, 17, 999999, 1000000, 6451600000000]:
		var r := PoolSim.isqrt(n)
		check(r * r <= n and (r + 1) * (r + 1) > n, "isqrt(%d) = %d" % [n, r])


func test_eight_ball_turns_and_fouls() -> void:
	var g := EightBall.new()
	var r := g.shot(1, 1000, 0, 500)
	check(not r["ok"], "player 1 can't break")
	r = g.shot(0, 0, 1000, 300)  # straight at the side rail: hits nothing
	check(r["ok"] and r["foul"], "hitting nothing is a foul")
	eq(g.turn, 1, "a foul passes the turn")
	# The eight early loses.
	var h := EightBall.new()
	for i in range(1, 16):
		h.sim.down[i] = 1
	h.sim.down[8] = 0
	h.sim.px[8] = PoolSim.W - 200000
	h.sim.py[8] = PoolSim.H / 2
	h.groups = ["solids", "stripes"]
	h.sim.down[2] = 0  # a solid still up: player 0 isn't clear
	h.sim.px[2] = 400000
	h.sim.py[2] = 300000
	var dx := PoolSim.W - h.sim.px[8]
	var dy := PoolSim.H - h.sim.py[8]
	var d := PoolSim.isqrt(dx * dx + dy * dy)
	h.sim.px[0] = h.sim.px[8] - dx * (2 * PoolSim.R + 300000) / d
	h.sim.py[0] = h.sim.py[8] - dy * (2 * PoolSim.R + 300000) / d
	r = h.shot(0, dx, dy, 600)
	check(r["pocketed"].has(8), "the eight went down")
	eq(h.winner, 1, "the eight before your group is cleared loses")


func test_duel21_totals_and_draws() -> void:
	eq(Duel21.total([0, 12]), 21, "A + K")
	eq(Duel21.total([0, 0, 8]), 21, "A + A + 9")
	eq(Duel21.total([9, 10, 1]), 22, "10 + J + 2")
	var a := Duel21.new()
	var b := Duel21.new()
	a.deal(HASH1)
	b.deal(HASH1)
	eq(a.hands, b.hands, "the same block deals the same cards")
	eq(a.hands[0].size(), 2)
	eq(a.deck.size(), 48)
	var seen := {}
	for h in a.hands:
		for c in h:
			check(not seen.has(c), "no card twice")
			seen[c] = true
	var c := Duel21.new()
	c.deal(HASH2)
	check(c.hands != a.hands, "another block, another deal")
	check(not a.hit(1, HASH2)["ok"], "player 1 waits for player 0")
	a.stand(0)
	eq(a.turn, 1)
	a.stand(1)
	check(a.over(), "both stood: over")


func test_parse_lines() -> void:
	var p := TableBook.parse("🎱 challenge anyone stake 5 Ⓐ")
	eq(p["kind"], "pool")
	eq(p["invite"], "")
	eq(BigInt.to_decimal(p["stake"]), "5000000000000000000")
	p = TableBook.parse("🃏 challenge %s stake 0.25 Ⓐ" % B.to_upper().replace("0X", "0x"))
	eq(p["invite"], B)
	eq(BigInt.to_decimal(p["stake"]), "250000000000000000")
	p = TableBook.parse("🃏 challenge anyone")
	check(BigInt.is_zero(p["stake"]), "no stake")
	p = TableBook.parse("🎱 #deadbeef shot -350 120 700")
	eq([p["op"], p["dx"], p["dy"], p["power"]], ["shot", -350, 120, 700])
	eq(TableBook.parse("🃏 #deadbeef hit")["op"], "hit")
	check(TableBook.parse("hello 🎱 world").is_empty(), "ordinary chat isn't a table line")
	eq(TableBook.challenge_text("cards", "", "2"), "🃏 challenge anyone stake 2 Ⓐ")
	eq(TableBook.shot_text("deadbeef", 5, -6, 2000), "🎱 #deadbeef shot 5 -6 1000")


func _line(tx: String, block: int, from: String, text: String, hash: String = "") -> Dictionary:
	return {"tx": tx, "log_index": 0, "block": block, "from": from, "text": text, "name": "", "block_hash": hash}


func test_replay_cards_game_and_rules() -> void:
	var book := TableBook.new("0xq")
	var tx := "0x1234abcd" + "0".repeat(56)
	book.ingest(_line(tx, 100, A, "🃏 challenge %s stake 3 Ⓐ" % B))
	var m: Dictionary = book.by_id["1234abcd"]
	eq(m["status"], "open")
	book.ingest(_line("0x01", 101, C, "🃏 #1234abcd accept", HASH1))
	eq(m["status"], "open", "only the invited wallet may accept")
	book.ingest(_line("0x02", 102, B, "🃏 #1234abcd accept", HASH1))
	eq(m["status"], "playing")
	eq(m["players"], [A, B])
	book.ingest(_line("0x03", 103, B, "🃏 #1234abcd stand"))
	eq(TableBook.turn_index(m), 0, "a move out of turn is ignored")
	book.ingest(_line("0x04", 104, A, "🃏 #1234abcd stand"))
	book.ingest(_line("0x05", 105, B, "🃏 #1234abcd stand"))
	eq(m["status"], "over")
	var d: Duel21 = m["game"]
	var ta := Duel21.total(d.hands[0])
	var tb := Duel21.total(d.hands[1])
	if ta == tb:
		check(m["push"], "a tie is a push")
	else:
		eq(m["winner"], A if ta > tb else B)
		eq(book.debts().size(), 1)


func test_replay_pool_concede_and_forfeit() -> void:
	var book := TableBook.new("0xq")
	book.ingest(_line("0xaaaa0001" + "0".repeat(56), 10, A, "🎱 challenge anyone"))
	book.ingest(_line("0x10", 11, A, "🎱 #aaaa0001 accept"))
	eq(book.by_id["aaaa0001"]["status"], "open", "you can't accept your own challenge")
	book.ingest(_line("0x11", 12, B, "🎱 #aaaa0001 accept"))
	book.ingest(_line("0x12", 13, B, "🎱 #aaaa0001 shot 1000 0 900"))
	eq(book.by_id["aaaa0001"]["game"].shots, 0, "the challenger breaks")
	book.ingest(_line("0x13", 14, A, "🎱 #aaaa0001 shot 1000 7 1000"))
	eq(book.by_id["aaaa0001"]["game"].shots, 1)
	var m: Dictionary = book.by_id["aaaa0001"]
	var waiting := 1 - TableBook.turn_index(m)
	var claimer: String = m["players"][waiting]
	book.ingest(_line("0x14", 20, claimer, "🎱 #aaaa0001 forfeit"))
	eq(m["status"], "playing", "too early to claim")
	book.ingest(_line("0x15", 14 + TableBook.TIMEOUT_BLOCKS + 1, claimer, "🎱 #aaaa0001 forfeit"))
	eq(m["status"], "over")
	eq(m["winner"], claimer)


func test_allocate_debts() -> void:
	var five := BigInt.from_decimal("5")
	var debts := [{"stake": five, "end_block": 100}, {"stake": five, "end_block": 200}]
	var r := TableBook.allocate(debts, [{"block": 150, "value": BigInt.from_decimal("5")}])
	check(r[0]["paid"] and not r[1]["paid"], "a payment settles the older debt")
	r = TableBook.allocate(debts, [{"block": 90, "value": BigInt.from_decimal("10")}])
	check(not r[0]["paid"] and not r[1]["paid"], "a transfer before the game ended doesn't count")
	r = TableBook.allocate(debts, [{"block": 250, "value": BigInt.from_decimal("7")}, {"block": 260, "value": BigInt.from_decimal("3")}])
	check(r[0]["paid"] and r[1]["paid"], "partial payments add up")


func test_arcade_receipt_verification() -> void:
	var q := "0x2b78b345880807ac9be28c1309ab55d6fa8796de"
	var pad := func(a: String) -> String: return "0x" + Abi.strip0x(a).lpad(64, "0")
	var good := {"logs": [{"address": Contracts.AFFECTION, "topics": [Contracts.TOPIC_TRANSFER, pad.call(A), pad.call(q)], "data": "0x" + BigInt.to_word(BigInt.from_decimal(ArcadePay.FEE_WEI))}]}
	check(ArcadePay.verify_receipt(good, A, q)["ok"], "the fee reached the QING")
	var wrong_token := {"logs": [{"address": "0x0000000000000000000000000000000000000001", "topics": good["logs"][0]["topics"], "data": good["logs"][0]["data"]}]}
	check(not ArcadePay.verify_receipt(wrong_token, A, q)["ok"], "another token's Transfer doesn't count")
	var short_pay := {"logs": [{"address": Contracts.AFFECTION, "topics": good["logs"][0]["topics"], "data": "0x" + BigInt.to_word(BigInt.from_decimal("5"))}]}
	check(not ArcadePay.verify_receipt(short_pay, A, q)["ok"], "less than the fee doesn't count")
	eq(ArcadePay.fee_text(), "1 Ⓐ")
