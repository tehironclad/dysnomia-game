extends TestCase
## The diegetic loop (PlayLoop): acts from a state snapshot, goal maths on
## BigInts, the measured Su outcome; the Heart's ring rules. No network.

const ME := "0x18f621662d6a1f23700ea32d146b32195dc33111"


func _w(s: String) -> PackedInt64Array:
	return BigInt.from_decimal(s)


func _keys(acts: Array) -> Array:
	return acts.map(func(a): return a["key"])


func _find(acts: Array, key: String) -> Dictionary:
	for a in acts:
		if a["key"] == key:
			return a
	return {}


func test_tower_goal_exact() -> void:
	# floors_for(100) = ceil(2 × 1.4) = 3; 139 is the first Hypobar with 4 floors.
	eq(BarColumns.floors_for(_w("138")), 3)
	eq(BarColumns.floors_for(_w("139")), 4)
	var g := PlayLoop.tower_goal(_w("100"), _w("10"))
	eq(g["floors"], 3)
	eq(g["su_next"], 4, "100 + 4·10 = 140 ≥ 139")
	eq(PlayLoop.tower_goal(_w("130"), _w("10"))["su_next"], 1)
	eq(PlayLoop.tower_goal(_w("100"), _w("0"))["su_next"], -1, "Ω = 0: never")
	# Huge values stay exact (well past 2^63).
	var big := PlayLoop.tower_goal(_w("1"), _w("1000000000000000000000"))
	eq(big["floors"], 1)
	eq(big["su_next"], 1)


func test_tier_goal_bigint() -> void:
	var g := PlayLoop.tier_goal(_w("3960"), _w("100"))
	eq(g["tier"], 1, "Outpost")
	eq(BigInt.to_decimal(g["need"]), "6040")
	eq(g["su"], 61, "⌈6040 / 100⌉")
	var c := PlayLoop.tier_goal(_w("500000000"), _w("7"))
	eq(c["next"], 5, "City → Capital")
	eq(c["su"], 71428572)
	eq(PlayLoop.tier_goal(_w("2000000000"), _w("7")), {}, "a Capital has no next tier")
	eq(PlayLoop.tier_goal(_w("3960"), PackedInt64Array())["su"], -1, "Ω = 0")
	eq(PlayLoop.su_to_reach(_w("1000000000000000000000000000000"), PackedInt64Array(), _w("1")), PlayLoop.MAX_SU)
	eq(PlayLoop.su_text(PlayLoop.MAX_SU), "too many")
	eq(PlayLoop.su_text(-1), "—")


func test_unread_snapshot_never_fabricates() -> void:
	var acts := PlayLoop.acts({"wallet": ME, "identity": "ok"})
	var su := _find(acts, "su")
	eq(su["title"], "Su here: Ω = —", "unread Ω shows —, not 0")
	check(not _keys(acts).has("room"), "no room act before the room is read")
	check(not _keys(acts).has("crown"), "no crown act without a board")
	for a in acts:
		check(not String(a["key"]).begins_with("well_"), "no dry well without a read")
	var goals := PlayLoop.goals({"wallet": ME})
	eq(goals[0]["text"], "Next tier: —")
	eq(goals[1]["text"], "Streak: —")


func test_acts_from_a_snapshot() -> void:
	var snap := {
		"wallet": ME, "identity": "ok", "block": 100, "omega": _w("10"),
		"board": [{"wallet": "0xaa", "hypobar": _w("150")}, {"wallet": ME, "hypobar": _w("130")}],
		"total_hypo": _w("280"), "readiness": "ready",
		"streak": {"current": 4, "best": 9, "today_done": false, "seconds_left": 3600},
		"room": {"loaded": true, "last_block": 10, "head": 20000, "cover": PackedInt64Array(), "admitted": true},
		"neighbours": [{"side": "n", "name": "North QING", "address": "0xn", "omega": _w("5"), "my_bars": false},
			{"side": "e", "name": "East QING", "address": "0xe", "omega": null, "my_bars": null}],
		"wells": {"fornax": _w("1"), "eris": PackedInt64Array(), "tethys": null},
		"bars_count": 2,
	}
	var acts := PlayLoop.acts(snap)
	eq(acts[0]["key"], "su", "a tower floor plus the streak puts Su first")
	check(String(acts[0]["detail"]).contains("3 → 4 floors"), acts[0]["detail"])
	check(String(acts[0]["detail"]).contains("4-day streak"))
	eq(_find(acts, "beat")["title"], "Beat is ready")
	eq(_find(acts, "room")["title"], "The room is quiet: speak")
	eq(_find(acts, "crown")["title"], "Pass #1 in 3 Su", "(150 − 130 + 1) / 10 → 3")
	check(_keys(acts).has("border_n"))
	check(not _keys(acts).has("border_e"), "unread bars there: no act")
	check(_keys(acts).size() <= PlayLoop.MAX_ACTS)
	# The dry Eris well is a fact; a well that was not read is never called dry.
	var all := snap.duplicate()
	all.erase("neighbours")
	all.erase("board")
	var a2 := PlayLoop.acts(all)
	var eris := _find(a2, "well_eris")
	eq(eris["doable"], false)
	check(_find(a2, "well_tethys").is_empty())
	var goals := PlayLoop.goals(snap)
	check(String(goals[0]["text"]).begins_with("Reach Settlement: 9,720 Hypobar to go (972 Su at Ω)"), goals[0]["text"])
	check(String(goals[1]["text"]).contains("3 floors, 130 Hypobar · #2 · next floor in 1 Su"), goals[1]["text"])
	check(String(goals[2]["text"]).contains("Streak 4 days (best 9) · today: 1h 00m left"), goals[2]["text"])


func test_identity_gates_and_cover() -> void:
	var acts := PlayLoop.acts({"wallet": "", "omega": _w("10"),
		"room": {"loaded": true, "last_block": -1, "head": 50, "cover": _w("414000000000000000000"), "admitted": false}})
	var su := _find(acts, "su")
	eq(su["doable"], false)
	check(String(su["blocker"]).contains("front door"))
	var room := _find(acts, "room")
	eq(room["call"], "QING.Join(LAU)")
	check(String(room["detail"]).contains("414"))
	var zero := PlayLoop.acts({"wallet": ME, "identity": "ok", "omega": PackedInt64Array()})
	eq(_find(zero, "su")["title"], "Su here: Ω = 0")


func test_su_outcome_measured() -> void:
	var o := PlayLoop.su_outcome(_w("130"), _w("140"), _w("7"), 123)
	eq(BigInt.to_decimal(o["d_hypo"]), "10")
	eq(o["floors_before"], 3)
	eq(o["floors_after"], 4)
	check(String(o["text"]).contains("your tower +1 floor (3 → 4)"), o["text"])
	check(String(o["text"]).ends_with("block 123"))


func test_heart_rings_follow_tier() -> void:
	eq(HeartOrrery.rings_for(0), 1, "Wild")
	eq(HeartOrrery.rings_for(5), 6, "Capital")
	eq(HeartOrrery.rings_for(9), HeartOrrery.MAX_RINGS)
	# Same c → same tilts (territory state only, never the viewer).
	eq(HeartOrrery.ring_tilt([0.25, -0.5], 2), HeartOrrery.ring_tilt([0.25, -0.5], 2))
	check(HeartOrrery.ring_tilt([0.25, -0.5], 1) != HeartOrrery.ring_tilt([-0.7, 0.2], 1))
	eq(DevelopmentSite.shaft_height(1), 24.0)
	eq(DevelopmentSite.shaft_height(5), 280.0)


func test_prompts_share_one_shape() -> void:
	eq(HudV2.split_prompt("E  go into the arcade"), ["E", "Go into the arcade"])
	eq(HudV2.split_prompt("E / Mouse 1  RIDE X"), ["E / Mouse 1", "RIDE X"])
	eq(HudV2.split_prompt("LIFT · 40 m · 3 m/s"), ["", "LIFT · 40 m · 3 m/s"])
	eq(HudV2.split_prompt("YOUR TOWER · 12 m  x"), ["", "YOUR TOWER · 12 m  x"])
