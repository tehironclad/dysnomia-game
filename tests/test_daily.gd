extends TestCase
## The daily challenge: days and the UTC reset, the game rotation, the seed from the day's first
## block (and "—" when it can't be read), attempts, streaks, board order, the input log, and the
## replay that scores a run (and refuses a forged one). No network.

const HASH := "0x8d1f00000000000000000000000000000000000000000000000000000000beef"
const W1 := "0x1111111111111111111111111111111111111111"
const W2 := "0x2222222222222222222222222222222222222222"
const W3 := "0x3333333333333333333333333333333333333333"
const T0 := 1795737600  # 2026-11-27T00:00:00Z


func test_days_and_the_utc_reset() -> void:
	eq(DailyChallenge.day_of(T0), "2026-11-27")
	eq(DailyChallenge.day_of(T0 - 1), "2026-11-26", "one second before midnight is still yesterday")
	eq(DailyChallenge.day_start("2026-11-27"), T0)
	eq(DailyChallenge.prev_day("2026-03-01"), "2026-02-28")
	eq(DailyChallenge.next_day("2026-12-31"), "2027-01-01")
	eq(DailyChallenge.seconds_left(T0), 86400, "a new day has all of it left")
	eq(DailyChallenge.seconds_left(T0 + 86399), 1)
	eq(DailyChallenge.left_text(T0 + 86400 - 3600 * 5 - 60 * 12), "5 h 12 min left")
	check(not DailyChallenge.valid_day("2026-02-31"), "no 31 February")
	check(not DailyChallenge.valid_day("2026-1-27") and not DailyChallenge.valid_day("x"), "malformed days are refused")
	# A run started before midnight still counts for its day for GRACE_S; then the board is closed.
	eq(DailyChallenge.accept_day("2026-11-26", T0 + 30), "2026-11-26")
	eq(DailyChallenge.accept_day("2026-11-26", T0 + DailyChallenge.GRACE_S + 1), "")
	eq(DailyChallenge.accept_day("2026-11-28", T0 + 30), "", "a future day is refused")
	eq(DailyChallenge.board_id("2026-11-27"), "daily:2026-11-27")
	check(DailyChallenge.is_board("daily:2026-11-27") and not DailyChallenge.is_board("daily:soon"))


func test_game_rotation_is_the_same_for_everyone() -> void:
	var seen := {}
	var d := "2026-11-27"
	var prev := ""
	for i in 12:
		var g := DailyChallenge.game_for(d)
		check(DailyChallenge.GAMES.has(g), "%s is an original game" % g)
		check(g != prev, "consecutive days play different games")
		seen[g] = true
		prev = g
		d = DailyChallenge.next_day(d)
	eq(seen.size(), DailyChallenge.GAMES.size(), "every game comes round within six days")
	eq(DailyChallenge.game_for("2026-11-27"), DailyChallenge.game_for("2026-11-27"))
	eq(DailyChallenge.game_for("2026-11-27"), DailyChallenge.GAMES[(T0 / 86400) % 6], "days since 1970 mod 6")
	for g in DailyChallenge.GAMES:
		check(not ArcadeCatalog.find(g).is_empty() and ArcadeCatalog.find(g)["kind"] == "game", "%s is in the catalog (not a cartridge)" % g)
	eq(DailyChallenge.title_of("void_lanes"), "Void Lanes")


func test_seed_comes_from_the_block_hash_only() -> void:
	var s := DailyChallenge.seed_from_hash("2026-11-27", HASH)
	check(s > 0, "a seed from a real-shaped hash")
	eq(DailyChallenge.seed_from_hash("2026-11-27", HASH.to_upper().replace("0X", "0x")), s, "case doesn't matter")
	eq(s, ("daily:2026-11-27:" + HASH).sha256_text().substr(0, 12).hex_to_int(), "anyone can recompute it")
	check(DailyChallenge.seed_from_hash("2026-11-28", HASH) != s, "the day is mixed in")
	eq(DailyChallenge.seed_from_hash("2026-11-27", ""), -1, "no hash, no seed")
	eq(DailyChallenge.seed_from_hash("2026-11-27", "0x1234"), -1, "a short hash is not a hash")
	check(DailyChallenge.practice_seed("2026-11-27", 1) != s and DailyChallenge.practice_seed("2026-11-27", 1) != DailyChallenge.practice_seed("2026-11-27", 2),
		"practice never uses the day's seed and changes every run")


## A made-up chain for the search: 10 s blocks with a slow patch and a gap (a test fixture).
static func _ts(n: int) -> int:
	var t := 1795000000 + n * 10
	if n > 70000:
		t += (n - 70000) * 3  # slower blocks
	if n > 74000:
		t += 900  # a 15-minute gap
	return t


func _search(target: int, head: int) -> DailyChallenge.Search:
	var s := DailyChallenge.Search.new(target, head, _ts(head))
	while not s.done:
		var n := s.next()
		if n < 0:
			break
		s.feed(n, _ts(n))
	return s


func test_search_finds_the_first_block_at_or_after_midnight() -> void:
	for target in [_ts(500) + 1, _ts(70500), _ts(74000) + 300, _ts(74001), _ts(79990) - 5]:
		var s := _search(target, 80000)
		check(s.done and s.found > 0, "found for %d (%s)" % [target, s.error])
		check(_ts(s.found) >= target and _ts(s.found - 1) < target, "block %d is the first at or after %d" % [s.found, target])
		check(s.reads <= 40, "in %d reads" % s.reads)
	# The head is older than midnight: no block yet, nothing invented.
	var early := DailyChallenge.Search.new(_ts(80000) + 5, 80000, _ts(80000))
	check(early.done and early.found == -1 and early.error != "", "no block at or after the target yet")
	# A failed read stops the search with nothing.
	var s2 := DailyChallenge.Search.new(_ts(500), 80000, _ts(80000))
	s2.next()
	s2.fail("block could not be read: —")
	check(s2.done and s2.found == -1, "a failed read finds nothing")


func test_unread_seed_shows_a_dash_and_offers_practice() -> void:
	check(DailyChallenge.seed_text({"state": "failed"}).contains("—"), "a failed read is —")
	check(DailyChallenge.seed_text({"state": "failed"}).contains("practice only"))
	check(DailyChallenge.seed_text({"state": "checking"}).contains("checking…"))
	check(DailyChallenge.seed_text({"state": "ok", "block": 28150000, "hash": HASH}).contains("28,150,000"))
	# DailySeed with a chain that answers nothing: failed, never a made-up seed.
	DailySeed.clear()
	var keep := DailySeed.use_file
	DailySeed.use_file = false
	DailySeed.override = func(_d): return {"ok": false, "error": "unreachable: —"}
	var find := Callable(DailySeed, "find")  # no read suspends here (the override answers at once)
	var r: Dictionary = find.call("2001-01-01")
	eq(String(r.get("state", "")), "failed", "an unreadable chain is 'failed'")
	check(not r.has("seed"), "and carries no seed")
	eq(DailySeed.peek("2001-01-01")["state"], "failed")
	DailySeed.override = func(_d): return {"ok": true, "block": 7, "hash": HASH, "timestamp": 978307200}
	DailySeed.clear()
	r = find.call("2001-01-01")
	eq(int(r.get("seed", -1)), DailyChallenge.seed_from_hash("2001-01-01", HASH), "a read block gives the seed")
	DailySeed.override = Callable()
	DailySeed.use_file = keep
	DailySeed.clear()


func test_attempts_and_streaks_on_the_server_book() -> void:
	var b := DailyBook.new()
	var d := "2026-11-27"
	for i in DailyChallenge.ATTEMPTS:
		var r := b.start_attempt(d, W1, T0 + i)
		check(r["ok"] and int(r["attempt"]) == i + 1, "attempt %d starts" % (i + 1))
	var no := b.start_attempt(d, W1, T0 + 10)
	check(not no["ok"] and String(no["error"]).contains("no scored attempts left"), "the 4th is refused")
	eq(b.used(d, W1), 3)
	eq(b.can_submit(d, W1, 4), "that attempt was never started")
	eq(b.can_submit(d, W2, 1), "that attempt was never started", "another wallet's attempt isn't yours")
	check(b.can_submit(d, W1, 2, 600.0, T0 + 30) != "", "a 10-minute run 30 s after its start is refused")
	eq(b.can_submit(d, W1, 2, 20.0, T0 + 30), "")
	b.mark_submitted(d, W1, 2, 500)
	eq(b.can_submit(d, W1, 2), "that attempt already has its score", "one score per attempt")
	# A new day: new attempts. Streaks: consecutive days count, a missed day starts again.
	check(b.start_attempt("2026-11-28", W1)["ok"], "the reset: tomorrow has its own attempts")
	eq(b.streak_of(W1, "2026-11-28")["streak"], 2)
	eq(b.streak_of(W1, "2026-11-29")["streak"], 2, "still standing the next day (not played yet)")
	eq(b.streak_of(W1, "2026-11-30")["streak"], 0, "a missed day ends it")
	b.start_attempt("2026-11-30", W1)
	eq(b.streak_of(W1, "2026-11-30")["streak"], 1)
	eq(b.streak_of(W1, "2026-11-30")["best"], 2)
	var c := DailyBook.new()
	c.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	eq(c.used(d, W1), 3, "the book survives a save")
	eq(c.can_submit(d, W1, 2), "that attempt already has its score")
	c.from_dict({"days": {"bad": {}, d: {"nope": {}, W2: {"started": 99}}}})
	eq(c.used(d, W2), DailyChallenge.ATTEMPTS, "a file can't grant more attempts than the day has")
	b.prune("2026-12-10")
	eq(b.used(d, W1), 0, "old days are forgotten")


func test_streak_rules() -> void:
	eq(DailyChallenge.streak_after("", 0, "2026-11-27"), ["2026-11-27", 1])
	eq(DailyChallenge.streak_after("2026-11-26", 4, "2026-11-27"), ["2026-11-27", 5])
	eq(DailyChallenge.streak_after("2026-11-27", 5, "2026-11-27"), ["2026-11-27", 5], "twice a day is still one day")
	eq(DailyChallenge.streak_after("2026-11-20", 9, "2026-11-27"), ["2026-11-27", 1])
	eq(DailyChallenge.attempts_left(1), 2)
	eq(DailyChallenge.attempts_left(7), 0)


func test_local_attempts_best_and_streak() -> void:
	var path := "user://test_daily.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var d := "2026-11-27"
	for i in DailyChallenge.ATTEMPTS:
		check(DailyLocal.start_attempt(d, "guest", path)["ok"], "local attempt %d" % (i + 1))
	check(not DailyLocal.start_attempt(d, "guest", path)["ok"], "a guest gets the same three a day")
	check(DailyLocal.start_attempt(d, W1, path)["ok"], "a wallet is counted apart")
	check(DailyLocal.record(d, "guest", {"score": 300}, path), "the first run is the best")
	check(not DailyLocal.record(d, "guest", {"score": 200}, path), "a lower run is not")
	check(DailyLocal.record(d, "guest", {"score": 900, "practice": true}, path), "practice is kept apart")
	eq(int(DailyLocal.best(d, "guest", false, path)["score"]), 300, "the scored best ignores practice")
	eq(DailyLocal.streak(d, path)["streak"], 1)
	check(DailyLocal.start_attempt("2026-11-28", "guest", path)["ok"], "tomorrow resets")
	eq(DailyLocal.streak("2026-11-28", path)["streak"], 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_board_order_and_one_row_per_wallet() -> void:
	var rows := [{"wallet": W1, "score": 50, "at": 10}, {"wallet": W2, "score": 90, "at": 20}, {"wallet": W3, "score": 90, "at": 15}]
	var s := DailyChallenge.sort_rows(rows)
	eq(s.map(func(r): return r["wallet"]), [W3, W2, W1], "best first; a tie goes to the earlier run")
	eq(DailyChallenge.rank_of(s, W2), 2)
	eq(DailyChallenge.rank_of(s, "0x9999999999999999999999999999999999999999"), 0)
	var lb := Leaderboards.new()
	var b := DailyChallenge.board_id("2026-11-27")
	lb.insert(b, NetDaily.row(W1, 100, true, "verified", 1, 1))
	lb.insert(b, NetDaily.row(W2, 300, true, "verified", 1, 2))
	var r := lb.insert(b, NetDaily.row(W1, 80, true, "verified", 2, 3))
	eq(String(r.get("kept", "")), "your best stands", "a lower run keeps the wallet's best")
	lb.insert(b, NetDaily.row(W1, 400, true, "verified", 3, 4))
	var top := lb.top(b, 10)
	eq(top.size(), 2, "one row per wallet")
	eq(top[0]["wallet"], W1)
	eq(int(top[0]["score"]), 400)
	eq(lb.top(DailyChallenge.board_id("2026-11-28"), 10), [], "the next day's board starts empty (the reset)")


func test_input_log_round_trip_and_refusals() -> void:
	var steps := PackedByteArray()
	for i in 5000:
		steps.append(ArcadeGame.IN_FIRE if (i / 7) % 3 == 0 else (ArcadeGame.IN_LEFT if i % 400 < 200 else 0))
	var text := DailyChallenge.encode_log(ArcadeGame.IN_FIRE, steps)
	check(text.begins_with("v1:16:"), "versioned, with the bits held at the start")
	var d := DailyChallenge.decode_log(text)
	check(d["ok"], "decodes")
	eq(int(d["start"]), ArcadeGame.IN_FIRE)
	eq(d["steps"], steps, "every step comes back")
	check(text.length() < 5000, "run-length: %d chars for 5,000 steps" % text.length())
	eq(DailyChallenge.decode_log("v1:0:")["steps"].size(), 0, "an empty run")
	for bad in ["", "v2:0:AAAA", "v1:99:", "v1:0:!!!!", "v1:0:" + Marshalls.raw_to_base64(PackedByteArray([0x40, 1])),
			"v1:0:" + Marshalls.raw_to_base64(PackedByteArray([1, 0])), "v1:0:" + Marshalls.raw_to_base64(PackedByteArray([1, 0x80]))]:
		check(not DailyChallenge.decode_log(bad)["ok"], "refused: %s" % bad)
	var huge := DailyChallenge.encode_log(0, PackedByteArray([0]))
	huge = "v1:0:" + Marshalls.raw_to_base64(PackedByteArray([0, 0xFF, 0xFF, 0x7F]))
	check(not DailyChallenge.decode_log(huge)["ok"], "a run longer than MAX_STEPS is refused before it is expanded")


## Plays `game_id` from `seed` with a scripted pattern, recording; returns [score, log text].
func _play_recorded(game_id: String, seed: int, n: int, pattern: Callable) -> Array:
	var g: ArcadeGame = load(DailyChallenge.script_of(game_id)).new()
	g.recording = true
	g.scripted_input = 0
	g.start(seed)
	var i := 0
	while g.playing and i < n:
		g.scripted_input = pattern.call(i)
		g.step(ArcadeGame.DT)
		i += 1
	var quit := g.playing
	if quit:
		g.end_game()  # Esc: the score so far stands
	var out := [g.score, DailyChallenge.encode_log(g.rec_start, g.rec_steps), quit]
	g.free()
	return out


static func _busy(i: int) -> int:
	var bits := 0
	match (i / 31) % 4:
		0: bits |= ArcadeGame.IN_LEFT | ArcadeGame.IN_UP
		1: bits |= ArcadeGame.IN_RIGHT
		2: bits |= ArcadeGame.IN_DOWN | ArcadeGame.IN_RIGHT
		3: bits |= ArcadeGame.IN_LEFT
	if (i % 23) < 9:
		bits |= ArcadeGame.IN_FIRE
	return bits


func test_replay_scores_a_run_exactly() -> void:
	var seed := DailyChallenge.seed_from_hash("2026-11-27", HASH)
	for game_id in DailyChallenge.GAMES:
		var run := _play_recorded(game_id, seed, 60 * 90, _busy)
		var r := DailyReplay.replay(game_id, seed, run[1])
		check(r["ok"], "%s replays (%s)" % [game_id, r.get("error", "")])
		eq(int(r.get("score", -1)), int(run[0]), "%s: the replay's score is the run's" % game_id)
	# A deterministic game run to its own game over (Bar Raiser: never pressing stalls every round).
	var lost := _play_recorded("bar_raiser", seed, 60 * 60, func(_i): return 0)
	check(not lost[2], "bar_raiser ended by itself")
	var rr := DailyReplay.replay("bar_raiser", seed, lost[1])
	check(rr["ok"] and int(rr["score"]) == int(lost[0]), "a game over replays to the same score")


func test_replay_refuses_forgeries() -> void:
	var seed := DailyChallenge.seed_from_hash("2026-11-27", HASH)
	var run := _play_recorded("void_lanes", seed, 60 * 40, _busy)
	var other := DailyReplay.replay("void_lanes", seed ^ 1, run[1])
	check(not other["ok"] or int(other["score"]) != int(run[0]) or int(run[0]) == 0, "another seed doesn't give the same run")
	check(int(run[0]) + 1000 != int(DailyReplay.replay("void_lanes", seed, run[1])["score"]), "a forged claim can't match the replay")
	# A log that runs on past the game's own end: the game couldn't have taken it.
	var lost := _play_recorded("bar_raiser", seed, 60 * 60, func(_i): return 0)
	var dec := DailyChallenge.decode_log(lost[1])
	var longer: PackedByteArray = dec["steps"]
	longer.append_array(PackedByteArray([0, 0, 0, 0]))
	var r := DailyReplay.replay("bar_raiser", seed, DailyChallenge.encode_log(int(dec["start"]), longer))
	check(not r["ok"] and String(r["error"]).contains("after the game ended"), "a log past the game over is refused (%s)" % r.get("error", ""))
	check(not DailyReplay.replay("cart_sweep", seed, lost[1])["ok"], "a cartridge is not a daily game")
	check(not DailyReplay.replay("bar_raiser", seed, "garbage")["ok"], "garbage is refused")
	# The server's sliced replay gives the same answer as one go.
	var sl := DailyReplay.begin("void_lanes", seed, run[1])
	var frames := 0
	while not sl.run(500):
		frames += 1
	check(sl.ok and sl.score == int(run[0]) and frames > 1, "sliced over %d frames, same score" % frames)


func test_net_daily_messages_are_cleaned() -> void:
	var b := NetDaily.clean_board({"ok": true, "day": "2026-11-27", "game": "void_lanes",
		"rows": [{"wallet": W2, "score": 10, "at": 5}, {"wallet": "nope", "score": 99}, {"wallet": W1, "score": 70, "check": "x".repeat(400)}, {"wallet": W3, "score": -4}, "row"],
		"seed": {"state": "ok", "block": 12, "hash": HASH}, "me": {"rank": "1", "used": 99}, "yesterday": {"day": "2026-11-26", "game": "evil", "winner": {"wallet": W3, "score": 5}}})
	eq(b["rows"].size(), 2, "rows with no wallet or no score are dropped")
	eq(b["rows"][0]["wallet"], W1, "re-sorted here, best first")
	check(String(b["rows"][0]["check"]).length() <= 140, "texts are capped")
	eq(int(b["me"]["used"]), DailyChallenge.ATTEMPTS, "numbers are clamped")
	eq(b["yesterday"]["game"], "", "an unknown game is dropped")
	eq(b["yesterday"]["winner"]["wallet"], W3)
	eq(NetDaily.parse(NetProto.json_msg(NetDaily.C_DAILY_START, {"day": "tomorrow"})), {}, "a bad day is refused")
	var p := NetDaily.parse(NetDaily.submit_msg(3, "2026-11-27", 2, 500, "v1:0:"))
	eq(int(p["attempt"]), 2)
	eq(int(p["score"]), 500)
	check(NetProto.size_ok(NetDaily.submit_msg(3, "2026-11-27", 2, 500, "v1:0:" + "A".repeat(DailyChallenge.MAX_LOG_CHARS - 10))), "a long log fits")
	check(not NetProto.size_ok(NetDaily.submit_msg(3, "2026-11-27", 2, 500, "v1:0:" + "A".repeat(DailyChallenge.MAX_LOG_CHARS + 500))), "a longer one is refused")
	var ev := NetEvents.clean_event({"k": "daily_record", "w": W1, "game": "void_lanes", "score": 1234, "board": "daily:2026-11-27", "verified": true})
	check(not ev.is_empty(), "daily_record is an event the feed shows")
	eq(NetEvents.format(ev, {"name": func(_w, _n): return "enteh"}), "enteh took #1 in the daily challenge (Void Lanes): 1,234 ✓ replayed")


func test_daily_access_goal() -> void:
	var r := AccessGates.resolve("daily_board", {"wallet": "", "extra": [{"id": "signin", "title": "Sign in", "status": "todo"}]})
	eq(String(r["title"]), "Put your daily runs on the board")
	eq(r["steps"][0]["id"], "wallet", "a wallet first")
	eq(r["steps"][-1]["id"], "signin", "then the server's sign-in")
