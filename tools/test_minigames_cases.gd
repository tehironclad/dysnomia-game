extends RefCounted
## Test cases for tools/test_minigames.gd. Loaded at runtime so the autoloads
## (GameManager, …) exist before these scripts compile.

var tree: SceneTree
var _fails := 0
var _passes := 0

const DICE := preload("res://scripts/minigames/entropy_dice.gd")
const SLOTS := preload("res://scripts/minigames/waat_slots.gd")
const CARDS := preload("res://scripts/minigames/card_match.gd")


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
	else:
		_fails += 1
		print("[test] FAIL %s %s" % [name, detail])


func run(t: SceneTree) -> int:
	tree = t
	QuestBoard.reset("user://test_quest_board.json")
	MinigameRecords.reset("user://test_minigame_records.json")
	_test_quest_determinism()
	_test_quest_progress_and_streak()
	_test_gm_and_titles()
	_test_trivia()
	_test_dice()
	_test_slots()
	_test_cards()
	_test_records()
	await _test_ui()
	print("[test] %d passed, %d failed" % [_passes, _fails])
	print("[test] %s" % ("ALL PASSED" if _fails == 0 else "FAILURES"))
	for f in ["user://test_quest_board.json", "user://test_minigame_records.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	return _fails


# ─── Quests ─────────────────────────────────────────────────────────────

func _ids(qs: Array) -> Array:
	return qs.map(func(q): return q["id"])


func _test_quest_determinism() -> void:
	var qa := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
	var a1 := QuestBoard.generate(qa, "2026-11-23", 3)
	var a2 := QuestBoard.generate(qa, "2026-11-23", 3)
	_check("quests: same QING+date+tier → identical", JSON.stringify(a1) == JSON.stringify(a2))
	_check("quests: 4 per day", a1.size() == QuestBoard.QUESTS_PER_DAY, str(a1.size()))
	_check("quests: case-insensitive QING key", JSON.stringify(a1) == JSON.stringify(QuestBoard.generate(qa.to_upper().replace("0X", "0x"), "2026-11-23", 3)))
	var differs_day := 0
	var differs_qing := 0
	for d in range(1, 21):
		var date := "2026-12-%02d" % d
		if JSON.stringify(QuestBoard.generate(qa, date, 3)) != JSON.stringify(a1):
			differs_day += 1
		if JSON.stringify(QuestBoard.generate("0x%040x" % d, "2026-11-23", 3)) != JSON.stringify(a1):
			differs_qing += 1
	_check("quests: vary by date", differs_day >= 18, str(differs_day))
	_check("quests: vary by QING", differs_qing >= 18, str(differs_qing))
	var cats_ok := true
	var no_dupes := true
	var tier0_fair := false
	var rocket_seen := false
	for d in range(1, 29):
		var date := "2027-02-%02d" % d
		var q3 := QuestBoard.generate("0x%040x" % (d * 7), date, 3)
		var ids := _ids(q3)
		for id in ids:
			if ids.count(id) > 1:
				no_dupes = false
			if id in ["ride_rocket", "rocket_watch"]:
				rocket_seen = true
		var cats := q3.map(func(q): return q["cat"])
		if cats != ["fair", "cantina", "social", "explore"]:
			cats_ok = false
		for q in QuestBoard.generate("0x%040x" % (d * 7), date, 0):
			if q["cat"] == "fair":
				tier0_fair = true
	_check("quests: one per category", cats_ok)
	_check("quests: no duplicate quests in a day", no_dupes)
	_check("quests: Outpost (tier 0) never asks for rides", not tier0_fair)
	_check("quests: Capital can ask for the rocket", rocket_seen)
	for q in QuestBoard.generate(qa, "2026-11-23", 1):
		_check("quests: tier 1 board only has built rides (%s)" % q["id"], not (q["id"] in ["ride_wheel", "ride_drop", "ride_rocket", "rocket_watch"]))
	# Every template's event is a supported event
	for t in QuestBoard.TEMPLATES:
		_check("quests: template event supported (%s)" % t["id"], QuestBoard.EVENTS.has(t["ev"]))
	# UTC date boundaries
	_check("utc: 23:59:59 is still the 23rd", QuestBoard.utc_date(1795478399) == "2026-11-23", QuestBoard.utc_date(1795478399))
	_check("utc: 00:00:00 is the 24th", QuestBoard.utc_date(1795478400) == "2026-11-24")
	_check("utc: seconds until reset", QuestBoard.seconds_until_reset(1795478399) == 1)


func _feed_to_complete(q: Dictionary, qing: String) -> void:
	var f: Dictionary = q["filter"]
	for i in int(q["target"]):
		var data := {"at_qing": qing}
		for k in f:
			if k.ends_with(">="):
				data[k.trim_suffix(">=")] = f[k]
			elif k.ends_with("~"):
				data[k.trim_suffix("~")] = "gm frens"
			else:
				data[k] = f[k]
		if q["distinct"] != "":
			data[q["distinct"]] = "0x%040x" % (i + 9000) if q["distinct"] == "qing" else "game_%d" % i
		QuestBoard.report(q["event"], data)


func _test_quest_progress_and_streak() -> void:
	QuestBoard.reset("user://test_quest_board.json")
	QuestBoard.tier = 3
	var qing := "0x1299bbac80f7038c19c20843f80608bd80c14a74"
	var day1 := 1795392000 + 3600 * 10   # 2026-11-23 10:00 UTC
	QuestBoard.now_override = day1
	var b := QuestBoard.board(qing)
	_check("board: matches generate()", JSON.stringify(_ids(b["quests"])) == JSON.stringify(_ids(QuestBoard.generate(qing, "2026-11-23", 3))))
	_check("streak: starts at 0", QuestBoard.streak()["current"] == 0)
	# Board locks for the day even if the tier changes
	QuestBoard.tier = 0
	_check("board: locked after Standing change", JSON.stringify(_ids(QuestBoard.board(qing)["quests"])) == JSON.stringify(_ids(b["quests"])))
	QuestBoard.tier = 3
	# Wrong filter doesn't count
	var q0: Dictionary = b["quests"][1]  # cantina quest
	QuestBoard.report(q0["event"], {"at_qing": qing, "game": "nope", "id": "nope", "score": 0})
	_check("progress: non-matching data ignored", int(QuestBoard.board(qing)["quests"][1]["progress"]) == 0)
	# Events in another QING don't count here (except visits)
	_feed_to_complete(q0, "0x" + "ab".repeat(20))
	_check("progress: other QING's events don't count here", not QuestBoard.board(qing)["quests"][1]["done"])
	# Complete all four
	for q in b["quests"]:
		_feed_to_complete(q, qing)
	var after := QuestBoard.board(qing)
	var all_done := true
	for q in after["quests"]:
		if not q["done"] or int(q["progress"]) != int(q["target"]):
			all_done = false
			print("[test]   not done: ", q["id"], " ", q["progress"], "/", q["target"])
	_check("progress: every quest completable by its events", all_done)
	_check("streak: 1 after first day", QuestBoard.streak()["current"] == 1)
	_check("totals: quests_completed counted", int(QuestBoard.totals().get("quests_completed", 0)) >= 4)
	_check("totals: full board counted once", int(QuestBoard.totals().get("full_boards", 0)) == 1)
	# Extra reports after done don't over-count
	_feed_to_complete(b["quests"][0], qing)
	_check("progress: capped at target", int(QuestBoard.board(qing)["quests"][0]["progress"]) == int(b["quests"][0]["target"]))
	# Next UTC day: fresh board, streak continues
	QuestBoard.now_override = day1 + 86400
	_check("reset: new date after midnight", QuestBoard.utc_date() == "2026-11-24")
	var b2 := QuestBoard.board(qing)
	var fresh := true
	for q in b2["quests"]:
		if q["done"] or int(q["progress"]) != 0:
			fresh = false
	_check("reset: day-2 board starts fresh", fresh)
	_check("streak: at risk before day-2 quest", QuestBoard.streak()["at_risk"])
	_feed_to_complete(b2["quests"][2], qing)
	_check("streak: 2 on consecutive day", QuestBoard.streak()["current"] == 2)
	_feed_to_complete(b2["quests"][3], qing)
	_check("streak: same day doesn't double count", QuestBoard.streak()["current"] == 2)
	# Skip a day → broken
	QuestBoard.now_override = day1 + 86400 * 3
	_check("streak: reads 0 after a missed day", QuestBoard.streak()["current"] == 0)
	_check("streak: best remembered", QuestBoard.streak()["best"] == 2)
	_feed_to_complete(QuestBoard.board(qing)["quests"][2], qing)
	_check("streak: restarts at 1", QuestBoard.streak()["current"] == 1)
	# Persistence round-trip
	var before := QuestBoard.export_state()
	var streak_before := QuestBoard.streak()
	QuestBoard._loaded = false
	QuestBoard._ensure()
	var after_load := QuestBoard.export_state()
	_check("save: round-trips through user://", JSON.stringify(streak_before) == JSON.stringify(QuestBoard.streak()) \
		and JSON.stringify(_ids(QuestBoard.board(qing)["quests"])) == JSON.stringify(_ids(before["days"][QuestBoard.utc_date()][qing]["quests"])))
	_check("save: keeps at most %d days" % QuestBoard.KEEP_DAYS, after_load["days"].size() <= QuestBoard.KEEP_DAYS)
	_check("report: unknown event ignored", QuestBoard.report("not_an_event", {}).is_empty())
	_check("report: alias rocket_watch → rocket_watched", QuestBoard.ALIASES["rocket_watch"] == "rocket_watched")
	QuestBoard.now_override = -1


func _test_gm_and_titles() -> void:
	for t in ["gm", "GM frens", "gm!", "ggmm", "good morning gm"]:
		_check("gm: '%s' counts" % t, QuestBoard._has_word(t, "gm"))
	for t in ["dogma", "programming", "gmail", "hi"]:
		_check("gm: '%s' doesn't" % t, not QuestBoard._has_word(t, "gm"))
	QuestBoard.reset("user://test_quest_board.json")
	QuestBoard.now_override = 1795392000
	var unlocked := []
	var cb := func(t: Dictionary) -> void: unlocked.append(t["id"])
	QuestBoard.bus.title_unlocked.connect(cb)
	for i in 10:
		QuestBoard.report("visit_qing", {"qing": "0x%040x" % (i + 1), "at_qing": "0x%040x" % (i + 1)})
	QuestBoard.report("minigame_score", {"game": "waat_slots", "score": 953, "jackpot": true})
	for i in 7:
		QuestBoard.report("chat", {"text": "gm"})
	QuestBoard.bus.title_unlocked.disconnect(cb)
	_check("titles: QING Hopper after 10 QINGs", unlocked.has("qing_hopper"), str(unlocked))
	_check("titles: Motzkin-Touched after jackpot", unlocked.has("motzkin_touched"))
	_check("titles: gm Bear after 7 gms", unlocked.has("gm_bear"))
	_check("titles: Fresh Regolith always", QuestBoard.titles()[0]["unlocked"])
	_check("titles: select unlocked", QuestBoard.select_title("gm_bear") and QuestBoard.selected_title() == "gm Bear")
	_check("titles: can't select locked", not QuestBoard.select_title("eris_devotee"))
	QuestBoard.now_override = -1


# ─── Trivia ─────────────────────────────────────────────────────────────

func _test_trivia() -> void:
	var names := DysnomiaLore.qing_names()
	_check("trivia: real QING names loaded", names.size() > 100, str(names.size()))
	var ctx := {"names": names, "qing_name": names[3], "has_state": true,
		"charge": 48213377001, "hypobar": 9000, "epibar": 120}
	var rng := RandomNumberGenerator.new()
	rng.seed = 369
	var pool := TriviaBank.all_questions(ctx, rng)
	_check("trivia: big bank", pool.size() >= 60, str(pool.size()))
	var drinks_seen := 0
	for q in pool:
		var a: Array = q["answers"]
		var uniq := {}
		for x in a:
			uniq[x] = true
		_check("trivia: 4 distinct answers (%s)" % q["id"], a.size() == 4 and uniq.size() == 4, str(a))
		_check("trivia: correct index points at truth (%s)" % q["id"], q["correct"] >= 0 and a[q["correct"]] == q["truth"])
		_check("trivia: difficulty 1-3 (%s)" % q["id"], q["difficulty"] in [1, 2, 3])
		match q["id"]:
			"chain_id": _check("trivia: chain id 369", q["truth"] == "369")
			"motzkin": _check("trivia: Motzkin prime", q["truth"] == str(GameManager.MOTZKIN_PRIME))
			"drink_rho_rocks":
				_check("trivia: Rho on the Rocks is AFFECTION.Rho()", q["truth"] == "AFFECTION.Rho()")
				drinks_seen += 1
			"bars_here": _check("trivia: live bars answer", q["truth"] == "Hypobar")
			"charge_here": _check("trivia: live charge bucket", q["truth"] == "10 – 100 billion", q["truth"])
			"here": _check("trivia: current QING", q["truth"] == names[3])
			"saat_1": _check("trivia: Saat 1 is Soul", q["truth"] == "Soul")
			"role_XIE": _check("trivia: XIE is power", q["truth"] == "XIE")
		if str(q["id"]).begins_with("real_"):
			_check("trivia: real QING is real", names.has(q["truth"]))
			for x in a:
				if x != q["truth"]:
					_check("trivia: decoys are fake (%s)" % x, not names.has(x))
		if str(q["id"]).begins_with("fake_"):
			_check("trivia: fake QING not on chain", not names.has(q["truth"]))
			for x in a:
				if x != q["truth"]:
					_check("trivia: others are real (%s)" % x, names.has(x))
	_check("trivia: drink question present", drinks_seen == 1)
	for d in AttractionCatalog.DRINKS:
		if d.get("kind", "") == AttractionCatalog.KIND_OP:
			var found := pool.filter(func(q): return q["id"] == "drink_" + d["id"])
			_check("trivia: drink %s → op %s" % [d["id"], d["op"]], found.size() == 1 and found[0]["truth"] == "AFFECTION.%s()" % str(d["op"]).capitalize())

	# Games: ramp + no repeats in a session
	TriviaBank.session_seen.clear()
	var seen := {}
	var repeats := 0
	var ramp_ok := true
	var games := 0
	var pool_size := pool.size()
	while seen.size() + 10 <= pool_size - 12:
		var g := TriviaBank.build_game(ctx, rng)
		games += 1
		if g.size() != 10:
			ramp_ok = false
		for i in g.size():
			if seen.has(g[i]["id"]):
				repeats += 1
			seen[g[i]["id"]] = true
			if i > 0 and int(g[i]["difficulty"]) < int(g[i - 1]["difficulty"]) and g.size() == 10:
				# allowed only when a difficulty tier ran dry; first games must ramp
				if games == 1:
					ramp_ok = false
		var tpl := {}
		for q in g:
			tpl[q["tpl"]] = int(tpl.get(q["tpl"], 0)) + 1
		for k in tpl:
			if tpl[k] > TriviaBank.MAX_PER_TEMPLATE:
				ramp_ok = false
		if games > 20:
			break
	_check("trivia: %d games, no repeats in session" % games, repeats == 0, str(repeats))
	_check("trivia: 10 questions, ramped, ≤2 per template", ramp_ok)
	var first := TriviaBank.build_game(ctx, rng)
	_check("trivia: difficulty ramp shape", first.size() == 10)
	# Offline context still works (no live data, no names)
	var off := TriviaBank.build_game({"names": [], "has_state": false}, rng)
	_check("trivia: offline game still has 10 questions", off.size() == 10, str(off.size()))


# ─── Dice / slots / cards ───────────────────────────────────────────────

func _test_dice() -> void:
	var r: Dictionary = DICE.dice_from_bytes(PackedByteArray([255, 252, 0, 5, 251]))
	_check("dice: bytes ≥252 skipped", r["dice"] == [1, 6, 6] and r["used"] == [2, 3, 4], str(r))
	var b1: PackedByteArray = DICE.roll_bytes("0xABCDEF", 1795392000, 3)
	var b2: PackedByteArray = DICE.roll_bytes("0xabcdef", 1795392000, 3)
	_check("dice: roll bytes deterministic (entropy, second, roll#)", b1 == b2 and b1.size() == 32)
	_check("dice: different second → different bytes", b1 != DICE.roll_bytes("0xabcdef", 1795392001, 3))
	_check("dice: triple 6 is the Motzkin", DICE.score_roll([6, 6, 6], 2)["points"] == 600 and DICE.score_roll([6, 6, 6], 2)["label"] == "MOTZKIN TRIPLE")
	_check("dice: triple w/ lucky", DICE.score_roll([3, 3, 3], 3)["points"] == 375)
	_check("dice: straight 150", DICE.score_roll([4, 2, 3], 6)["points"] == 150)
	_check("dice: straight + lucky", DICE.score_roll([4, 5, 6], 5)["points"] == 175)
	_check("dice: pair 50", DICE.score_roll([2, 5, 2], 1)["points"] == 50)
	_check("dice: lucky-only 25", DICE.score_roll([1, 3, 6], 3) == {"points": 25, "kind": "lucky", "label": "LUCKY 3"})
	_check("dice: collapse", DICE.score_roll([1, 3, 6], 4)["kind"] == "bust")
	_check("dice: multipliers", DICE.multiplier(1) == 1.0 and DICE.multiplier(3) == 2.0 and DICE.multiplier(99) == 5.0)
	_check("dice: house line in 300..500", DICE.house_line("0x00ff") >= 300 and DICE.house_line("0x00ff") <= 500)
	_check("dice: lucky face 1..6", DICE.lucky_face("0x05") == 6 and DICE.lucky_face("") == 3)
	# Exact bust odds per lucky face: tension without misery
	for lucky in range(1, 7):
		var busts := 0
		for a in range(1, 7):
			for b in range(1, 7):
				for c in range(1, 7):
					if DICE.score_roll([a, b, c], lucky)["kind"] == "bust":
						busts += 1
		var p := busts / 216.0
		_check("dice: collapse odds %.2f for lucky %d" % [p, lucky], p > 0.15 and p < 0.30)
	# Fairness: faces uniform over many real rolls
	var counts := [0, 0, 0, 0, 0, 0]
	for i in 4000:
		var d: Array = DICE.dice_from_bytes(DICE.roll_bytes("0x5eed", 1795392000 + i, i))["dice"]
		for v in d:
			counts[v - 1] += 1
	var uniform := true
	for c in counts:
		if c < 1800 or c > 2200:
			uniform = false
	_check("dice: faces uniform over 12000 dice", uniform, str(counts))


func _test_slots() -> void:
	var S := SLOTS
	_check("slots: Motzkin jackpot 953", S.payout([6, 6, 6], 3)["amount"] == 953 and S.payout([6, 6, 6], 3)["jackpot"])
	_check("slots: featured triple pays double", S.payout([4, 4, 4], 4)["amount"] == 400 and S.payout([4, 4, 4], 3)["amount"] == 200)
	_check("slots: rocket triple 300", S.payout([5, 5, 5], 2)["amount"] == 300)
	_check("slots: LAU triple 60", S.payout([0, 0, 0], 2)["amount"] == 60)
	_check("slots: two Motzkins", S.payout([6, 1, 6], 2)["amount"] == S.TWO_MOTZKIN_PAY)
	_check("slots: first-two pair", S.payout([1, 1, 3], 2)["amount"] == S.PAIR_PAY)
	_check("slots: featured pair double", S.payout([3, 3, 1], 3)["amount"] == S.PAIR_PAY * 2)
	_check("slots: non-adjacent pair pays nothing", S.payout([1, 2, 1], 4)["amount"] == 0)
	_check("slots: one Motzkin", S.payout([0, 6, 2], 4)["amount"] == S.ONE_MOTZKIN_PAY)
	_check("slots: blank", S.payout([0, 1, 2], 4)["amount"] == 0)
	var waat := "0x00d666cf000b02a1c10eb330fddc8b97b5921a246dfbe40e0a6b9514a961bcdf"
	var th := DysnomiaLore.house_theme(waat)
	var st: Array = S.build_strip(waat, 0, th["featured"])
	_check("slots: strip deterministic per Waat", st == S.build_strip(waat, 0, th["featured"]))
	_check("slots: reels differ", st != S.build_strip(waat, 1, th["featured"]))
	_check("slots: strip weights (+2 featured)", st.size() == 27 and st.count(6) == 1 and st.count(th["featured"]) == S.WEIGHTS[th["featured"]] + 2)
	for i in DysnomiaLore.HOUSE_THEMES.size():
		var f: int = DysnomiaLore.HOUSE_THEMES[i]["featured"]
		var strips := [S.build_strip(waat, 0, f), S.build_strip(waat, 1, f), S.build_strip(waat, 2, f)]
		var rtp: float = S.expected_return(strips, f) / float(S.SPIN_COST)
		_check("slots: RTP %.2f for %s (0.7..1.0)" % [rtp, DysnomiaLore.HOUSE_THEMES[i]["name"]], rtp > 0.7 and rtp < 1.0)


func _test_cards() -> void:
	_check("cards: combo points", CARDS.match_points(1) == 50 and CARDS.match_points(3) == 150 and CARDS.match_points(9) == 250)
	_check("cards: round bonus", CARDS.round_bonus(0, 12.7) == 320 and CARDS.round_bonus(2, 0.0) == 600)
	var keys := DysnomiaLore.CONTRACTS.keys()
	_check("cards: enough contracts for 10 pairs", keys.size() >= 10)
	for k in ["LAU", "QING", "AFFECTION", "YUE", "META", "GWAT", "XIE", "HECKE", "MAP", "ZUO", "CHAN", "CHO", "VOID", "RING", "PANG"]:
		_check("cards: %s has flavour" % k, DysnomiaLore.CONTRACTS.has(k) and str(DysnomiaLore.CONTRACTS[k]["flavour"]).length() > 10)


func _test_records() -> void:
	MinigameRecords.reset("user://test_minigame_records.json")
	var q := "0xd0ccbb3e2aad138c4e7e8727887557823f3c296c"
	var r1 := MinigameRecords.submit("entropy_dice", 300, false, q, "Prof. Oak QING", "bear", 1)
	_check("records: first score is PB + QING record", r1["personal_best"] and r1["qing_record"] and r1["rank"] == 0)
	var r2 := MinigameRecords.submit("entropy_dice", 200, false, q, "Prof. Oak QING", "cub", 2)
	_check("records: lower score ranks 2nd", not r2["personal_best"] and not r2["qing_record"] and r2["rank"] == 1)
	var r3 := MinigameRecords.submit("entropy_dice", 450, true, q, "Prof. Oak QING", "cub", 3)
	_check("records: new record", r3["qing_record"] and r3["prev_record"] == 300)
	for i in 6:
		MinigameRecords.submit("entropy_dice", 10 + i, false, q, "", "x", 4)
	_check("records: board capped at 5", MinigameRecords.leaderboard("entropy_dice", q).size() == MinigameRecords.BOARD_SIZE)
	_check("records: record holder", MinigameRecords.qing_record("entropy_dice", q)["player"] == "cub")
	_check("records: other QING empty", MinigameRecords.qing_record("entropy_dice", "0x" + "00".repeat(20)).is_empty())
	var b := MinigameRecords.get_bests()
	_check("records: get_bests shape", b["games"]["entropy_dice"]["personal_best"] == 450 \
		and b["games"]["entropy_dice"]["plays"] == 9 and b["games"]["entropy_dice"]["wins"] == 1 \
		and b["qing_records"][q]["records"]["entropy_dice"]["score"] == 450)
	_check("records: get_bests is JSON-safe", JSON.parse_string(JSON.stringify(b)) is Dictionary)
	MinigameRecords._loaded = false
	_check("records: persisted", MinigameRecords.personal_best("entropy_dice") == 450)


# ─── UI smoke ───────────────────────────────────────────────────────────

func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _test_ui() -> void:
	QuestBoard.reset("user://test_quest_board.json")
	MinigameRecords.reset("user://test_minigame_records.json")
	var hud := CanvasLayer.new()
	tree.root.add_child(hud)
	var mgr := Node.new()
	mgr.set_script(load("res://scripts/minigames/minigame_manager.gd"))
	hud.add_child(mgr)
	mgr.initialize(hud)
	var results := []
	mgr.minigame_result.connect(func(g, r, rec): results.append([g, r, rec]))

	# Entropy Dice: play 5 turns, rolling once and banking
	mgr.open_game_by_type("entropy_dice")
	await _frames(3)
	var dice = mgr.get_active_game()
	_check("ui: dice opened", dice != null and dice._dice.size() == 3)
	for turn in 5:
		dice._on_roll()
		await _frames(3)
		dice._roll_t = 10.0
		await _frames(2)
		if dice._pot > 0:
			dice._on_bank()
		await _frames(1)
	_check("ui: dice finished after 5 turns", dice._finished)
	_check("ui: dice reported result", results.size() == 1 and results[0][0] == "entropy_dice")
	_check("ui: dice result card shown", dice._result_card.visible)
	_check("ui: dice feed shows bytes", dice._feed.text.contains("sha256"))

	# Slots: spin until cash-out
	mgr.open_game_by_type("waat_slots")
	await _frames(2)
	var slots = mgr.get_active_game()
	_check("ui: slots start with 100 SAAT", slots._score == SLOTS.START_SAAT)
	var guard := 0
	while not slots._finished and guard < 40:
		guard += 1
		slots._on_spin()
		for i in 3:
			slots._spin_t = 10.0
			await _frames(1)
		await tree.create_timer(0.5).timeout
		if not slots._finished and slots._spins >= 3:
			slots._on_cash_out()
	_check("ui: slots cashed out", slots._finished and results.size() == 2, "spins=%d" % slots._spins)

	# Trivia: answer everything correctly
	mgr.open_game_by_type("territory_trivia")
	await _frames(2)
	var tr = mgr.get_active_game()
	_check("ui: trivia has 10 questions", tr._questions.size() == 10)
	for i in tr._questions.size():
		tr._on_answer(tr._correct_index)
		tr._next_question()
	await _frames(2)
	_check("ui: trivia perfect run reported", results.size() == 3 and results[2][1].get("perfect", false) and results[2][1]["won"])

	# Card Match: solve round 1 instantly, then let the clock run out
	mgr.open_game_by_type("card_match")
	await _frames(3)
	var cm = mgr.get_active_game()
	_check("ui: cards dealt 12", cm._cards.size() == 12)
	var by := {}
	for c in cm._cards:
		by[c.contract] = by.get(c.contract, []) + [c]
	for k in by:
		cm._on_match(by[k][0], by[k][1])
	_check("ui: round 1 cleared", cm._rounds_cleared == 1)
	await tree.create_timer(1.8).timeout
	_check("ui: round 2 dealt 16", cm._cards.size() == 16)
	cm._time_left = 0.01
	await _frames(3)
	_check("ui: cards finished on time-out", cm._finished and results.size() == 4)
	_check("ui: card match lost with 1 round", not results[3][1]["won"])

	# Quests got the minigame events
	var t := QuestBoard.totals()
	_check("quests: minigame_played reported ×4", int(t.get("ev_minigame_played", 0)) == 4, str(t))
	_check("quests: perfect trivia → Sage of Eris", QuestBoard.titles().filter(func(x): return x["id"] == "sage_of_eris")[0]["unlocked"])
	_check("records: every game has a personal entry", MinigameRecords.get_bests()["games"].size() == 4)
	mgr.close_game()

	# To-do panel
	var panel := TodoPanel.install(hud, null, null)
	await _frames(2)
	panel.open()
	await _frames(3)
	_check("ui: to-do panel open with content", panel.is_open() and panel._body.get_child_count() > 15)
	panel.close()
	_check("ui: to-do panel closes", not panel.visible)
	hud.queue_free()
	await _frames(2)
