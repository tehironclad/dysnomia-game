extends TestCase
## Ticket strips: the price table (Prices), what a transfer's amount says it bought (TicketCode),
## the seeds of a strip's plays, the room board's play checks (FairBoard), the rocket's rule
## (FairProgress) and the local ledger of plays left (ArcadePay). Receipts and logs here are test
## fixtures, never shown in the game.

const QING := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
const PLAYER := "0x1111111111111111111111111111111111111111"
const OTHER := "0x2222222222222222222222222222222222222222"
const STRIP_TX := "0x77aa000000000000000000000000000000000000000000000000000000c0b1b2"
const SINGLE_TX := "0x9f3c2b1a000000000000000000000000000000000000000000000000c0ffee42"
const TEST_QING := "0x00000000000000000000000000000000057a1b5e"  ## a ledger key no real play uses


func _receipt(from: String, to: String, wei: String, tx: String = STRIP_TX, status: String = "0x1") -> Dictionary:
	return {"status": status, "blockNumber": "0x1ad5530", "transactionHash": tx, "logs": [{"address": Contracts.AFFECTION,
		"topics": [Contracts.TOPIC_TRANSFER, "0x" + Abi.strip0x(from).lpad(64, "0"), "0x" + Abi.strip0x(to).lpad(64, "0")],
		"data": BigInt.to_word(BigInt.from_decimal(wei)), "transactionHash": tx, "blockNumber": "0x1ad5530"}]}


func _round(game: String, seed_v: int) -> MidwaySim:
	var s := MidwaySim.new(game, seed_v)
	while not s.done and s.tick < MidwaySim.MAX_TICKS:
		if s.accepts():
			var a = MidwayAuto.choose(s)
			if a is Array:
				s.press(int(a[0]), int(a[1]))
		s.step()
	return s


func _line(text: String, from: String, block: int, tx: String, idx: int = 0) -> Dictionary:
	return {"text": text, "from": from, "block": block, "tx": tx, "log_index": idx, "name": "tester"}


func test_prices_are_one_table() -> void:
	eq(Prices.play_text(), "1 Ⓐ")
	eq(Prices.strip_text(), "10 Ⓐ")
	eq(Prices.play_button(), "Play 1 · 1 Ⓐ")
	eq(Prices.strip_button(), "Strip of 10 · 10 Ⓐ (gas once)")
	eq(Prices.menu_line(), "1 Ⓐ a play · strip of 10: 10 Ⓐ")
	eq(ArcadePay.FEE_WEI, Prices.wei(Prices.PLAY), "ArcadePay's fee is the table's")
	eq(ArcadePay.fee_text(), Prices.play_text())
	eq(Prices.price(3, 1), 1)
	eq(Prices.price(3, 10), 10)
	eq(Prices.price(TicketCode.ROCKET, 1), 5, "the rocket's flight")
	eq(Prices.drink("pi_shot"), 1)
	eq(Prices.drink("upsilon_fizz"), 2)
	eq(Prices.drink("house_round"), Prices.ROUND)
	for d in BarTab.DRINKS:
		var w := Prices.drink(String(d["id"]))
		check(w >= 1 and w <= 2, "every drink is 1–2 Ⓐ (%s)" % d["id"])
		check(Prices.DRINK_ITEMS.has(String(d["id"])), "every drink has an item code (%s)" % d["id"])
	eq(Prices.drink_wei("alpha_sour"), "2000000000000000024", "2 Ⓐ + the drink's code")
	eq(Prices.drink_wei("house_round"), "1000000000000000020")


func test_wager_helper() -> void:
	eq(BigInt.to_decimal(Prices.wager_wei("5")["wei"]), "5000000000000000000")
	eq(BigInt.to_decimal(Prices.wager_wei("0.25 Ⓐ")["wei"]), "250000000000000000")
	eq(BigInt.to_decimal(Prices.wager_wei("1.000000000000000001")["wei"]), "1000000000000000001")
	check(not Prices.wager_wei("0")["ok"], "no zero wager")
	check(not Prices.wager_wei("-1")["ok"], "no negative wager")
	check(not Prices.wager_wei("abc")["ok"], "not a number")
	check(not Prices.wager_wei("1e3")["ok"], "no exponents")
	check(not Prices.wager_wei("1001")["ok"], "over the bound")
	check(not Prices.wager_wei("0.0000000000000000001")["ok"], "19 decimals")
	eq(Prices.wager_text(BigInt.from_decimal("2500000000000000000")), "2.5 Ⓐ")


func test_encoding_and_old_tickets() -> void:
	eq(Prices.ticket_wei(3, 1), "1000000000000000003", "a single ticket is the old coded ticket")
	eq(FairProgress.fee_wei("regolith"), "1000000000000000003")
	eq(Prices.ticket_wei(3, 10), "10000000000000001003", "a strip of 10 for one game")
	eq(FairProgress.strip_wei("any"), "10000000000000001008", "a strip of 10 for any fair game")
	eq(Prices.ticket_wei(TicketCode.ARCADE, 10), "10000000000000001010", "an arcade strip")
	eq(Prices.ticket_wei(TicketCode.ROCKET, 1), "5000000000000000009", "a rocket flight")
	eq(Prices.ticket_wei(TicketCode.GENERAL, 1), "1000000000000000000", "a plain credit stays plain")
	var d := TicketCode.decode_decimal("10000000000000001003")
	check(d["ok"] and d["strip"], "a strip decodes")
	eq(int(d["item"]), 3)
	eq(int(d["plays"]), 10)
	eq(int(d["whole_n"]), 10)
	var old := TicketCode.decode_decimal("1000000000000000007")
	check(old["ok"] and not old["strip"] and int(old["item"]) == 7 and int(old["plays"]) == 1, "an old ticket decodes as one play of its game")
	var plain := TicketCode.decode_decimal("2000000000000000000")
	check(plain["ok"] and int(plain["item"]) == 0 and int(plain["plays"]) == 1, "a plain 2 Ⓐ is one general play")
	check(not TicketCode.decode_decimal("1000000000000000150")["ok"], "100..199 is not a code (one play is written < 100)")
	check(not TicketCode.decode_decimal("1000000000000010000")["ok"], "≥ 10,000 wei is not a code")
	check(not TicketCode.decode_decimal("1234567890123456789")["ok"], "arbitrary dust is not a code")
	var huge := TicketCode.decode(BigInt.add(BigInt.mul(BigInt.pow2(200), BigInt.from_decimal(TicketCode.UNIT)), BigInt.from_int(1003)))
	check(huge["ok"] and int(huge["whole_n"]) == -1 and int(huge["plays"]) == 10, "a huge amount decodes without floats")
	check(Prices.covers(d), "10 Ⓐ covers a strip of 10")
	check(not Prices.covers(TicketCode.decode_decimal("9000000000000001003")), "9 Ⓐ doesn't")
	check(Prices.covers(TicketCode.decode_decimal("2000000000000000001")), "overpaying a single is fine")
	check(not Prices.covers(TicketCode.decode_decimal("1000000000000000009")), "1 Ⓐ doesn't fly the rocket")
	for item in [1, 7, 8, 10]:
		for plays in [1, 2, 10, 99]:
			var dd := TicketCode.decode_decimal(TicketCode.encode(item, plays, plays))
			check(dd["ok"] and int(dd["item"]) == item and int(dd["plays"]) == plays, "round trip %d×%d" % [plays, item])


func test_strip_seeds() -> void:
	eq(TicketCode.seed_tx(SINGLE_TX), SINGLE_TX, "a single ticket is seeded by its own hash")
	eq(MidwayGame.seed_from_tx(TicketCode.seed_tx(SINGLE_TX)), MidwayGame.seed_from_tx(SINGLE_TX), "old rounds replay unchanged")
	var s0 := TicketCode.seed_tx(STRIP_TX, 0)
	eq(s0, "0x" + (STRIP_TX + "#0").sha256_text(), "play i = SHA-256(\"<tx>#<i>\")")
	eq(s0.length(), 66)
	eq(TicketCode.seed_tx(STRIP_TX.to_upper().replace("0X", "0x"), 0), s0, "case-insensitive")
	var seen := {}
	for i in 10:
		seen[MidwayGame.seed_from_tx(TicketCode.seed_tx(STRIP_TX, i))] = true
	eq(seen.size(), 10, "every play of a strip has its own seed")
	check(TicketCode.index_ok(10, 0) and TicketCode.index_ok(10, 9), "plays 0..9")
	check(not TicketCode.index_ok(10, 10) and not TicketCode.index_ok(10, -1), "not 10, and a strip's play needs its number")
	check(TicketCode.index_ok(1, -1) and not TicketCode.index_ok(1, 0), "a single ticket has no play number")


func test_strip_lines_and_board() -> void:
	var strip := FairProgress.strip_wei("any")
	var rc := _receipt(PLAYER, QING, strip)
	var a := _round("crystal", MidwayGame.seed_from_tx(TicketCode.seed_tx(STRIP_TX, 0)))
	var b := _round("waat", MidwayGame.seed_from_tx(TicketCode.seed_tx(STRIP_TX, 1)))
	var la := FairBoard.line_text("crystal", a.score, STRIP_TX, a.events, 0)
	check(la.contains(STRIP_TX + "#0 v%d:" % MidwaySim.VERSION), "the line names ticket#play")
	var p := FairBoard.parse(la)
	eq(int(p["index"]), 0)
	eq(int(FairBoard.parse(FairBoard.line_text("crystal", a.score, SINGLE_TX, a.events)).get("index", 99)), -1, "an old line has no play")
	var longest := FairBoard.line_text("motzkin", MidwaySim.max_score("motzkin"), STRIP_TX, _round("motzkin", 7).events, 98)
	check(longest.length() <= FairBoard.MAX_LEN, "a strip's line still fits (%d)" % longest.length())
	var lb := FairBoard.line_text("waat", b.score, STRIP_TX, b.events, 1)
	var c := _round("waat", MidwayGame.seed_from_tx(TicketCode.seed_tx(STRIP_TX, 0)))
	var rows := [
		FairBoard.verify(_line(la, PLAYER, 100, "0xb1"), rc, QING),
		FairBoard.verify(_line(lb, PLAYER, 101, "0xb2"), rc, QING),
		FairBoard.verify(_line(FairBoard.line_text("waat", c.score, STRIP_TX, c.events, 0), PLAYER, 102, "0xb3"), rc, QING),  # play 0 again, another stall
		FairBoard.verify(_line(FairBoard.line_text("crystal", a.score, STRIP_TX, a.events, 10), PLAYER, 103, "0xb4"), rc, QING),  # play 10 of 10
		FairBoard.verify(_line(FairBoard.line_text("crystal", a.score, STRIP_TX, a.events), PLAYER, 104, "0xb5"), rc, QING),  # no play number
		FairBoard.verify(_line(FairBoard.line_text("crystal", a.score, STRIP_TX, a.events, 1), PLAYER, 105, "0xb6"), rc, QING),  # play 0's log as play 1
		FairBoard.verify(_line(la, PLAYER, 106, "0xb7"), rc, QING),  # the same line again
		FairBoard.verify(_line(la, OTHER, 107, "0xb8"), rc, QING),  # someone else's strip
	]
	check(rows[0]["verified"], "play 0 verifies: %s" % rows[0]["why"])
	check(rows[1]["verified"], "play 1 at another stall verifies: %s" % rows[1]["why"])
	check(not rows[3]["verified"] and String(rows[3]["why"]).contains("not one of the strip's 10"), "play #10 of 10 is rejected: %s" % rows[3]["why"])
	check(not rows[4]["verified"], "a strip's line must name its play")
	check(not rows[5]["verified"], "each play replays from its own seed: %s" % rows[5]["why"])
	check(not rows[7]["verified"], "another wallet can't post my strip")
	var d := FairBoard.dedupe(rows)
	check(rows[2]["verified"], "play 0 at the wheel replays on its own: %s" % rows[2]["why"])
	check(not d[2]["verified"] and String(d[2]["why"]).contains("already posted"), "play 0 counts once, across stalls")
	check(not d[6]["verified"], "a duplicate line counts once")
	eq(FairBoard.compile(rows, "crystal")["top"].size(), 1)
	eq(FairBoard.compile(rows, "waat")["top"].size(), 1, "play 0's second posting doesn't reach the waat board")
	eq(String(FairBoard.compile(rows, "waat")["top"][0]["line_tx"]), "0xb2")
	# A per-game strip plays only its own game; an any-game single doesn't exist
	var own := _receipt(PLAYER, QING, Prices.ticket_wei(4, 10))
	check(FairBoard.ticket_check(own, PLAYER, QING, "crystal", 3)["ok"], "a crystal strip at the crystal stall")
	check(not FairBoard.ticket_check(own, PLAYER, QING, "waat", 3)["ok"], "a crystal strip is not for the wheel")
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, "1000000000000000008"), PLAYER, QING, "waat")["ok"], "1 Ⓐ + 8 is no ticket")
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, "9000000000000001008"), PLAYER, QING, "waat", 0)["ok"], "an underpaid strip")
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, Prices.ticket_wei(TicketCode.ARCADE, 10)), PLAYER, QING, "waat", 0)["ok"], "an arcade strip is no fair ticket")
	eq(FairProgress.posted_indices(FairBoard.dedupe(rows), PLAYER, STRIP_TX), [0, 1], "plays spent, read from the room")


func test_rocket_rule() -> void:
	var logs := []
	logs.append(_receipt(PLAYER, QING, FairProgress.fee_wei("striker"), "0x01")["logs"][0])  # an old single ticket
	logs.append(_receipt(PLAYER, QING, Prices.ticket_wei(4, 10), "0x02")["logs"][0])  # a crystal strip
	logs.append(_receipt(PLAYER, QING, FairProgress.strip_wei("any"), STRIP_TX)["logs"][0])  # an any-game strip
	logs.append(_receipt(PLAYER, QING, "9000000000000001005", "0x03")["logs"][0])  # underpaid motzkin strip
	logs.append(_receipt(PLAYER, QING, Prices.ticket_wei(TicketCode.ROCKET, 1), "0x04")["logs"][0])
	eq(FairProgress.codes_from_logs(logs), [1, 4], "(a) singles and per-game strips count; any-game strips don't by themselves")
	var strips := FairProgress.strips_from_logs(logs)
	eq(strips.size(), 2, "both fair strips are found")
	eq(String(strips[1]["tx"]), STRIP_TX)
	eq(int(strips[1]["plays"]), 10)
	eq(int(strips[1]["item"]), TicketCode.FAIR_ANY)
	eq(int(strips[1]["block"]), 0x1ad5530)
	# (b) posted rounds of the any-game strip count, one game each
	var rows := [{"verified": true, "wallet": PLAYER, "game": "waat"}, {"verified": false, "wallet": PLAYER, "game": "saat"},
		{"verified": true, "wallet": OTHER, "game": "entropy"}, {"verified": true, "wallet": PLAYER.to_upper().replace("0X", "0x"), "game": "regolith"}]
	eq(FairProgress.posted_codes(rows, PLAYER), [3, 6], "verified, mine")
	var played := FairProgress.played(FairProgress.codes_from_logs(logs), rows, PLAYER)
	eq(played, [1, 3, 4, 6])
	check(not FairProgress.unlocked(played))
	for g in ["entropy", "motzkin", "saat"]:
		rows.append({"verified": true, "wallet": PLAYER, "game": g})
	check(FairProgress.unlocked(FairProgress.played(FairProgress.codes_from_logs(logs), rows, PLAYER)), "all seven: unlocked")


func test_ledger_counts_strips() -> void:
	var w := PLAYER
	var q := TEST_QING
	var c := ConfigFile.new()
	c.load(ArcadePay.LEDGER)
	var key := "%s@%s" % [w, q]
	if c.has_section_key("credits", key):
		c.erase_section_key("credits", key)
	# One credit from before strips (no item, no plays): still one arcade play
	c.set_value("credits", key, [{"tx": "0xold", "block": 5, "used": false}])
	c.save(ArcadePay.LEDGER)
	eq(ArcadePay.credits(w, q), 1, "an old credit counts")
	ArcadePay.add_credit(w, q, STRIP_TX, 10, TicketCode.FAIR_ANY, 10)
	ArcadePay.add_credit(w, q, "0xarc", 11, TicketCode.ARCADE, 10)
	ArcadePay.add_credit(w, q, STRIP_TX, 10, TicketCode.FAIR_ANY, 10)  # the same transfer twice: once
	eq(ArcadePay.credits(w, q), 11, "arcade: the old credit + an arcade strip")
	eq(ArcadePay.credits(w, q, [3, TicketCode.FAIR_ANY]), 10, "a stall: its game's and any-game plays")
	var p0 := ArcadePay.use_credit(w, q, [TicketCode.FAIR_ANY])
	var p1 := ArcadePay.use_credit(w, q, [TicketCode.FAIR_ANY])
	eq(int(p0["index"]), 0)
	eq(int(p1["index"]), 1)
	eq(int(p1["left"]), 8)
	eq(String(p1["seed_tx"]), TicketCode.seed_tx(STRIP_TX, 1))
	eq(ArcadePay.seed_tx(p1), TicketCode.seed_tx(STRIP_TX, 1))
	var old := ArcadePay.use_credit(w, q)
	eq(String(old["tx"]), "0xold", "the oldest arcade credit first")
	eq(int(old["index"]), -1, "a single ticket has no play number")
	eq(ArcadePay.seed_tx(old), "0xold")
	eq(ArcadePay.credits(w, q), 10)
	# Derivable: the room shows plays 1 and 4 posted (on any computer) → spent here too
	ArcadePay.sync_strip(w, q, STRIP_TX, 10, TicketCode.FAIR_ANY, 10, [1, 4, 12])
	eq(ArcadePay.credits(w, q, [TicketCode.FAIR_ANY]), 7, "0, 1 played here, 4 posted elsewhere")
	eq(int(ArcadePay.use_credit(w, q, [TicketCode.FAIR_ANY])["index"]), 2)
	ArcadePay.sync_strip(w, q, "0xelsewhere", 12, 5, 10, [0])
	eq(ArcadePay.credits(w, q, [5]), 9, "a strip bought on another computer appears, minus its posted play")
	eq(ArcadePay.strips(w, q, [5])[0]["next"], 1)
	var by_tx := ArcadePay.use_credit(w, q, [], "0xarc")
	eq(int(by_tx["index"]), 0, "a named transfer's next play")
	for i in 20:
		ArcadePay.use_credit(w, q, [TicketCode.FAIR_ANY])
	eq(ArcadePay.credits(w, q, [TicketCode.FAIR_ANY]), 0)
	check(ArcadePay.use_credit(w, q, [TicketCode.FAIR_ANY]).is_empty(), "an empty strip gives nothing")
	c = ConfigFile.new()
	c.load(ArcadePay.LEDGER)
	c.erase_section_key("credits", key)
	c.save(ArcadePay.LEDGER)
