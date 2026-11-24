extends TestCase
## The fair's mini games are pure deterministic sims: a round's input log replays to the same
## score; scores stay in bounds; the room line fits; the board and the rocket's progress check
## the chain's facts (receipts and Transfer logs here are test fixtures, never shown in the game).

const GAMES := ["striker", "entropy", "regolith", "crystal", "motzkin", "waat", "saat"]
const QING := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
const PLAYER := "0x1111111111111111111111111111111111111111"
const OTHER := "0x2222222222222222222222222222222222222222"
const TICKET := "0x9f3c2b1a000000000000000000000000000000000000000000000000c0ffee42"

## Recorded rounds: [game, seed, compact log, score]. If a rule changes, these fail: bump
## MidwaySim.VERSION (old room lines then say which rules they were played under).
const RECORDED := [
	["striker", 0x00c0ffee, "1b.4c.4c", 291],
	["entropy", 0x00c0ffee, "bzk.3it3.3b00", 100],
	["regolith", 0x00c0ffee, "43hshs.4g5ysg.2ytm74.6phs74.6ltmsg", 500],
	["crystal", 0x00c0ffee, "5hd9g.28agq4.2c9f9g.28idq4.2ci79g.289mq4.2ca99g.2897q4", 800],
	["motzkin", 0x00c0ffee, "174gra.4y4g8a.1xm8ra.30dcra.3tv4ra.1jdcra.2zdcra.xv48a.3uv48a.zv4ra.30v48a.v4gra.18m88a.4tv4ra.wv48a", 950],
	["waat", 0x00c0ffee, "k.49.4n", 290],
	["waat", 0x00c0ffee, "", 770],  # never braked: it brakes itself after 15 s each spin
	["striker", 0x00c0ffee, "", 0],  # never swung
]


## Plays a round with a deterministic policy: press when policy(sim) returns [ax, ay].
func _play(game: String, seed_v: int, policy: Callable) -> MidwaySim:
	var s := MidwaySim.new(game, seed_v)
	while not s.done and s.tick < MidwaySim.MAX_TICKS:
		if s.accepts():
			var a = policy.call(s)
			if a is Array:
				s.press(int(a[0]), int(a[1]))
		s.step()
	return s


## A fair bot per game: aims for the points (so scores are non-trivial), never perfect.
func _bot(game: String) -> Callable:
	match game:
		"striker":
			return func(s: MidwaySim): return [0, 0] if s.phase == "ready" and s.meter >= 950 else null
		"entropy":
			return func(s: MidwaySim):
				var d := MidwaySim.TOSS_Z0 - s.target.y
				var want := (d - 400) * 1000 / 1600
				if s.phase != "ready" or absi(s.meter - want) > 25:
					return null
				var ax := (s.target.x - s.wind * d / 1000) * 1000 * MidwaySim.AIM / (500 * d)
				return [ax, 0]
		"regolith":
			return func(s: MidwaySim):
				var w := s.sway()
				if s.phase != "ready" or absi(w.x) > 25 or absi(w.y) > 25:
					return null
				var peg: Array = [[0, 500], [-600, 800], [600, 200], [0, 200], [600, 800]][s.round_i % 5]
				return [peg[0] * MidwaySim.AIM / 900, (peg[1] - 500) * MidwaySim.AIM / 500]
		"crystal":
			return func(s: MidwaySim):
				if s.phase != "ready" or s.phase_t < 5:
					return null
				var row := s.round_i % 2
				for i in MidwaySim.RAIL_N:
					if (int(s.knocked[row]) >> i) & 1:
						continue
					var x := s.crystal_x(row, i, s.tick + 1 + MidwaySim.SHY_FLY[row])
					if absi(x) < 1500:
						return [x * MidwaySim.AIM / 1700, 300 if row == 1 else -300]
				return null
		"motzkin":
			return func(s: MidwaySim):
				for i in s.schedule.size():
					if s.target_up(i, s.tick) and s.tick - int(s.schedule[i][1]) > 12:
						var e: Array = s.schedule[i]
						if MidwaySim.is_prime(int(e[3])) or i % 7 == 0:  # the bot gets a few wrong
							var x := int(MidwaySim.SLOTS_X[int(e[0]) % 4])
							var y := int(MidwaySim.SLOTS_Y[int(e[0]) / 4])
							return [x * MidwaySim.AIM / 1800, (y - 1825) * MidwaySim.AIM / 700]
				return null
		"waat":
			return func(s: MidwaySim): return [0, 0] if s.phase == "ready" and s.phase_t >= 20 + 7 * s.round_i else null
		"saat":
			return func(s: MidwaySim): return [0, 0] if s.phase_t > 10 else null
	return func(_s): return null


func test_bot_rounds_replay_to_the_same_score() -> void:
	for game in GAMES:
		for seed_v in [1, 7, 0x2b1c0de5, 0x7fffffff, 123456789]:
			var s := _play(game, seed_v, _bot(game))
			check(s.done, "%s/%d finished" % [game, seed_v])
			eq(MidwaySim.replay(game, seed_v, s.events), s.score, "%s/%d replays" % [game, seed_v])
			var text := MidwaySim.encode_log(game, s.events)
			var d := MidwaySim.decode_log(game, text)
			check(d["ok"], "%s log decodes" % game)
			eq(d["log"], s.events, "%s log round-trips" % game)
			eq(MidwaySim.replay(game, seed_v, d["log"]), s.score, "%s/%d replays from the compact log" % [game, seed_v])


func test_bots_score_something() -> void:
	# Skill pays: every scored game gives the bot points over a few seeds
	for game in GAMES:
		if game == "saat":
			continue
		var total := 0
		for seed_v in [3, 99, 2024, 0x5eed]:
			total += _play(game, seed_v, _bot(game)).score
		check(total > 0, "%s: a skilled player scores (%d over 4 rounds)" % [game, total])


func test_recorded_logs_replay() -> void:
	for r in RECORDED:
		var d := MidwaySim.decode_log(String(r[0]), String(r[2]))
		check(d["ok"], "%s recorded log decodes" % r[0])
		eq(MidwaySim.replay(String(r[0]), int(r[1]), d["log"]), int(r[3]), "%s recorded round replays to its score" % r[0])


func test_scores_are_bounded_under_random_input() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for game in GAMES:
		var hi := 0
		for k in 25:
			var seed_v := rng.randi() & 0x7fffffff
			var p := float(k % 5 + 1) * 0.02
			var s := _play(game, seed_v, func(_s): return [rng.randi_range(-700, 700), rng.randi_range(-700, 700)] if rng.randf() < p else null)
			check(s.score >= 0 and s.score <= MidwaySim.max_score(game), "%s score %d within 0..%d" % [game, s.score, MidwaySim.max_score(game)])
			check(s.events.size() <= MidwaySim.rounds(game), "%s: at most %d presses" % [game, MidwaySim.rounds(game)])
			eq(MidwaySim.replay(game, seed_v, s.events), s.score, "%s random round replays" % game)
			hi = maxi(hi, s.score)


func test_bad_logs_do_not_replay() -> void:
	var s := _play("striker", 5, _bot("striker"))
	var log: Array = s.events.duplicate(true)
	check(log.size() == 3)
	var early := log.duplicate(true)
	early[1][0] = int(early[0][0]) + 3  # the second swing during the first one's flight
	eq(MidwaySim.replay("striker", 5, early), -1, "a press the game wouldn't take")
	eq(MidwaySim.replay("striker", 5, log.slice(0, 2)), MidwaySim.replay("striker", 5, log.slice(0, 2)), "deterministic")
	var extra := log.duplicate(true)
	extra.append([MidwaySim.MAX_TICKS + 5, 0, 0])
	eq(MidwaySim.replay("striker", 5, extra), -1, "a press after the end")
	check(not MidwaySim.decode_log("regolith", "zz").get("ok", true), "too short for two aims")
	check(not MidwaySim.decode_log("regolith", "1!!zz").get("ok", true), "not base 36")
	check(not MidwaySim.decode_log("regolith", "1zzzz").get("ok", true), "aim out of range")
	eq(MidwaySim.replay("nope", 1, []), -1)


func test_the_seed_changes_the_round() -> void:
	var a := MidwaySim.new("waat", 1)
	var b := MidwaySim.new("waat", 2)
	check(a.wheel != b.wheel or a.angle != b.angle, "the wheel comes from the ticket")
	var c := MidwaySim.new("motzkin", 1)
	var d := MidwaySim.new("motzkin", 2)
	check(c.schedule != d.schedule, "the targets come from the ticket")
	var primes := 0
	for e in c.schedule:
		if MidwaySim.is_prime(int(e[3])):
			primes += 1
	check(primes >= 10 and primes < c.schedule.size(), "a fair mix of primes (%d of %d)" % [primes, c.schedule.size()])


func test_integer_helpers() -> void:
	eq(MidwaySim.isin(0), 0)
	eq(MidwaySim.isin(900), 1000)
	eq(MidwaySim.isin(2700), -1000)
	check(absi(MidwaySim.isin(300) - 500) <= 3, "sin 30° ≈ 0.5")
	eq(MidwaySim.isqrt(98000), 313)
	eq(MidwaySim.tri(0, 96), 0)
	eq(MidwaySim.tri(48, 96), 1000)
	eq(MidwaySim.code("striker"), 1)
	eq(MidwaySim.code("saat"), 7)


func test_room_line_fits_and_parses() -> void:
	# The longest line: Motzkin, 15 shots, big tick gaps, full aims
	var log: Array = []
	var t := 0
	for i in 15:
		t += 1295
		log.append([t, -MidwaySim.AIM + i, MidwaySim.AIM - i])
	var text := FairBoard.line_text("motzkin", 1500, TICKET, log)
	check(text.length() <= FairBoard.MAX_LEN, "the longest score line is %d characters (≤ %d)" % [text.length(), FairBoard.MAX_LEN])
	check(text.to_utf8_buffer().size() <= 300, "and %d bytes" % text.to_utf8_buffer().size())
	var p := FairBoard.parse(text)
	eq(p["game"], "motzkin")
	eq(p["score"], 1500)
	eq(p["ticket"], TICKET)
	eq(p["log"], log)
	check(FairBoard.parse("🎱 challenge anyone").is_empty(), "a pool line is not a score line")
	check(FairBoard.parse("🎪 saat 0 %s v1:" % TICKET).is_empty(), "the teller posts no score")
	check(TableBook.parse(text).is_empty(), "the pool/cards book ignores score lines")


func _receipt(from: String, to: String, wei: String, status: String = "0x1") -> Dictionary:
	return {"status": status, "blockNumber": "0x1ad5530", "logs": [{"address": Contracts.AFFECTION,
		"topics": [Contracts.TOPIC_TRANSFER, "0x" + Abi.strip0x(from).lpad(64, "0"), "0x" + Abi.strip0x(to).lpad(64, "0")],
		"data": BigInt.to_word(BigInt.from_decimal(wei))}]}


func test_ticket_check() -> void:
	var fee := FairProgress.fee_wei("crystal")
	eq(fee, "1000000000000000004")
	check(FairBoard.ticket_check(_receipt(PLAYER, QING, fee), PLAYER, QING, "crystal")["ok"], "the right ticket")
	eq(int(FairBoard.ticket_check(_receipt(PLAYER, QING, fee), PLAYER, QING, "crystal")["block"]), 0x1ad5530)
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, fee), OTHER, QING, "crystal")["ok"], "posted by someone else")
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, fee), PLAYER, QING, "waat")["ok"], "a ticket for another stall")
	check(not FairBoard.ticket_check(_receipt(PLAYER, OTHER, fee), PLAYER, QING, "crystal")["ok"], "paid to another QING")
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, ArcadePay.FEE_WEI), PLAYER, QING, "crystal")["ok"], "an uncoded 1 Ⓐ")
	check(not FairBoard.ticket_check(_receipt(PLAYER, QING, fee, "0x0"), PLAYER, QING, "crystal")["ok"], "reverted")
	check(not FairBoard.ticket_check({}, PLAYER, QING, "crystal")["ok"], "no receipt")


func _line(text: String, from: String, block: int, tx: String, idx: int = 0) -> Dictionary:
	return {"text": text, "from": from, "block": block, "tx": tx, "log_index": idx, "name": "tester"}


func test_board_verifies_and_dedups() -> void:
	var seed_v := MidwayGame.seed_from_tx(TICKET)
	var s := _play("crystal", seed_v, _bot("crystal"))
	var good := FairBoard.line_text("crystal", s.score, TICKET, s.events)
	var rc := _receipt(PLAYER, QING, FairProgress.fee_wei("crystal"))
	var rows := [
		FairBoard.verify(_line(good, PLAYER, 100, "0xa1"), rc, QING),
		FairBoard.verify(_line(good, PLAYER, 101, "0xa2"), rc, QING),  # the same ticket again
		FairBoard.verify(_line(FairBoard.line_text("crystal", s.score + 100, TICKET, s.events), PLAYER, 99, "0xa3"), rc, QING),  # inflated
		FairBoard.verify(_line(good, OTHER, 102, "0xa4"), rc, QING),  # someone else's ticket
	]
	check(rows[0]["verified"], "a true line verifies: %s" % rows[0]["why"])
	check(not rows[2]["verified"] and String(rows[2]["why"]).begins_with("replays to"), "an inflated score fails replay")
	check(not rows[3]["verified"], "another wallet can't post my ticket")
	var b := FairBoard.compile(rows, "crystal")
	eq(b["top"].size(), 1, "one ticket counts once")
	eq(b["unverified"], 3)
	eq(String(b["top"][0]["line_tx"]), "0xa1", "its first valid line")
	eq(FairBoard.compile(rows, "waat")["top"].size(), 0, "boards are per stall")
	check(FairBoard.lines(b["top"])[0].contains("block 100"), "rows say their block")
	check(FairBoard.sign_text("crystal", {}).contains("reading"), "an unread board says so")
	check(FairBoard.sign_text("crystal", {"ok": false, "rows": []}).contains("—"), "a failed read shows —")


func test_progress_codes() -> void:
	eq(FairProgress.code_of(BigInt.from_decimal("1000000000000000003")), 3)
	eq(FairProgress.code_of(BigInt.from_decimal("1000000000000000000")), 0, "a plain 1 Ⓐ carries no code")
	eq(FairProgress.code_of(BigInt.from_decimal("1000000000000000008")), 0)
	eq(FairProgress.code_of(BigInt.from_decimal("2000000000000000001")), 0)
	var logs := []
	for g in ["crystal", "striker", "crystal", "waat"]:
		logs.append(_receipt(PLAYER, QING, FairProgress.fee_wei(g))["logs"][0])
	logs.append(_receipt(PLAYER, QING, ArcadePay.FEE_WEI)["logs"][0])
	var codes := FairProgress.codes_from_logs(logs)
	eq(codes, [1, 4, 6])
	check(not FairProgress.unlocked(codes))
	eq(FairProgress.text(codes), "Rocket: 3 / 7 games played · next: Entropy Toss")
	check(FairProgress.unlocked([1, 2, 3, 4, 5, 6, 7]))
	eq(FairProgress.text([7, 6, 5, 4, 3, 2, 1]), "Rocket: 7 / 7 games played · unlocked")
	var t := FairProgress.topics(PLAYER, QING)
	eq(t[1], "0x" + "1".repeat(40).lpad(64, "0"))
	eq(String(t[2]).length(), 66)
