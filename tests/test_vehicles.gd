extends TestCase
## Garage vehicles: unlock rules from real chain state (never guessed), the pure
## drive/hover/spring helpers, the pad's placement, the engine loops. No network.

const Q := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
const ME := "0x00000000000000000000000000000000000000aa"
const ONE := "1000000000000000000"


func _facts(over: Dictionary = {}) -> Dictionary:
	var f := {"wallet": ME, "qing": Q, "identity": "ok", "has_yue": true, "bars": {}, "bars_block": 100,
		"territories": 942, "board": [], "board_note": "…", "board_block": 100}
	for k in over:
		f[k] = over[k]
	return f


func _bar(h: String) -> Array:
	return [BigInt.from_decimal(h), BigInt.from_decimal("1")]


func _st(kind: String, f: Dictionary) -> int:
	return VehicleUnlocks.evaluate(kind, f)["state"]


func test_rover_is_free_even_without_a_wallet() -> void:
	VehicleUnlocks.rentals.clear()
	eq(_st("rover", {"wallet": ""}), VehicleUnlocks.State.OPEN)
	eq(_st("rover", _facts({"identity": "failed"})), VehicleUnlocks.State.OPEN)


func test_no_wallet_locks_the_rest() -> void:
	VehicleUnlocks.rentals.clear()
	for k in ["hoverbike", "skimmer", "hopper", "crawler"]:
		var r := VehicleUnlocks.evaluate(k, {"wallet": "", "qing": Q})
		eq(r["state"], VehicleUnlocks.State.LOCKED, k)
		check(String(r["why"]).contains("connect a wallet"), k)


func test_unread_state_is_unknown_not_locked() -> void:
	VehicleUnlocks.rentals.clear()
	for k in ["hoverbike", "skimmer", "hopper", "crawler"]:
		eq(_st(k, _facts({"identity": "loading"})), VehicleUnlocks.State.UNKNOWN, k + " while the identity loads")
		var failed := VehicleUnlocks.evaluate(k, _facts({"identity": "failed"}))
		eq(failed["state"], VehicleUnlocks.State.UNKNOWN, k + " when the identity read failed")
		check(String(failed["why"]).begins_with("—"), "a failed read shows —")
	for k in ["hoverbike", "skimmer", "hopper"]:
		eq(_st(k, _facts({"bars": null})), VehicleUnlocks.State.UNKNOWN, k + " before the bars pass")
	eq(_st("crawler", _facts({"board": null})), VehicleUnlocks.State.UNKNOWN, "crawler before the board")
	var down := VehicleUnlocks.evaluate("crawler", _facts({"board": null, "board_note": "—"}))
	check(String(down["why"]).begins_with("—"), "board unavailable shows —")


func test_no_yue_means_no_bars() -> void:
	VehicleUnlocks.rentals.clear()
	for k in ["hoverbike", "skimmer", "hopper", "crawler"]:
		eq(_st(k, _facts({"has_yue": false, "bars": null, "board": null})), VehicleUnlocks.State.LOCKED, k)


func test_hoverbike_needs_any_hypobar() -> void:
	VehicleUnlocks.rentals.clear()
	eq(_st("hoverbike", _facts()), VehicleUnlocks.State.LOCKED)
	var elsewhere := {"0x1111111111111111111111111111111111111111": _bar(ONE)}
	eq(_st("hoverbike", _facts({"bars": elsewhere})), VehicleUnlocks.State.OPEN)
	# An Epibar alone is not a Hypobar
	var epi_only := {"0x1111111111111111111111111111111111111111": [PackedInt64Array(), BigInt.from_decimal("5")]}
	eq(_st("hoverbike", _facts({"bars": epi_only})), VehicleUnlocks.State.LOCKED)
	check(String(VehicleUnlocks.evaluate("hoverbike", _facts({"bars": elsewhere}))["why"]).contains("block 100"), "says the block")


func test_skimmer_needs_hypobar_here() -> void:
	VehicleUnlocks.rentals.clear()
	var elsewhere := {"0x1111111111111111111111111111111111111111": _bar(ONE)}
	eq(_st("skimmer", _facts({"bars": elsewhere})), VehicleUnlocks.State.LOCKED)
	eq(_st("skimmer", _facts({"bars": {Q: _bar("7")}})), VehicleUnlocks.State.OPEN)
	# Mixed-case keys still match (everything keyed by lower-cased address)
	eq(_st("skimmer", _facts({"bars": {Q.to_upper().replace("0X", "0x"): _bar("7")}})), VehicleUnlocks.State.OPEN)
	# The territory's own board counts too (even before the bars pass)
	eq(_st("skimmer", _facts({"bars": null, "board": [{"wallet": ME, "hypobar": BigInt.from_decimal("3")}]})), VehicleUnlocks.State.OPEN)


func test_hopper_needs_three_territories() -> void:
	VehicleUnlocks.rentals.clear()
	var bars := {}
	for i in 2:
		bars["0x%040d" % (i + 1)] = _bar(ONE)
	eq(_st("hopper", _facts({"bars": bars})), VehicleUnlocks.State.LOCKED)
	bars["0x%040d" % 9] = _bar("1")
	eq(_st("hopper", _facts({"bars": bars})), VehicleUnlocks.State.OPEN)


func test_crawler_needs_a_top_three_tower_here() -> void:
	VehicleUnlocks.rentals.clear()
	var board := []
	for h in ["900", "800", "700", "600"]:
		board.append({"wallet": "0x%040d" % int(h), "hypobar": BigInt.from_decimal(h)})
	eq(_st("crawler", _facts({"board": board})), VehicleUnlocks.State.LOCKED, "no tower here")
	var b2 := board.duplicate()
	b2.append({"wallet": ME, "hypobar": BigInt.from_decimal("650")})
	eq(VehicleUnlocks.rank_on(ME, b2), 4)
	eq(_st("crawler", _facts({"board": b2})), VehicleUnlocks.State.LOCKED, "#4")
	var b3 := board.duplicate()
	b3.append({"wallet": ME, "hypobar": BigInt.from_decimal("800")})
	eq(VehicleUnlocks.rank_on(ME, b3), 2, "ties share the better rank")
	eq(_st("crawler", _facts({"board": b3})), VehicleUnlocks.State.OPEN)
	eq(VehicleUnlocks.rank_on(ME, [{"wallet": ME, "hypobar": PackedInt64Array()}]), -1, "a zero Hypobar is no tower")


func test_rental_opens_one_vehicle_here_only() -> void:
	VehicleUnlocks.rentals.clear()
	VehicleUnlocks.add_rental(ME, Q, "crawler", "0xabcdef0123456789", 28200000)
	var r := VehicleUnlocks.evaluate("crawler", _facts())
	eq(r["state"], VehicleUnlocks.State.OPEN)
	check(String(r["why"]).contains("28200000"), "names the block")
	eq(_st("skimmer", _facts()), VehicleUnlocks.State.LOCKED, "only the rented kind")
	eq(_st("crawler", _facts({"qing": "0x1111111111111111111111111111111111111111"})), VehicleUnlocks.State.LOCKED, "only at that QING")
	eq(_st("crawler", _facts({"wallet": "0x00000000000000000000000000000000000000bb"})), VehicleUnlocks.State.LOCKED, "only for that wallet")
	VehicleUnlocks.rentals.clear()


func test_drive_step_accelerates_to_top_speed_and_no_further() -> void:
	var s := VehicleSpecs.spec("rover")
	var v := Vector2.ZERO
	for i in 600:
		v = VehicleSpecs.drive_step(v, 1.0, false, false, true, s, 1.0 / 60.0)
	near(v.x, float(s["max_speed"]), 0.01, "reaches max")
	for i in 600:
		v = VehicleSpecs.drive_step(v, 1.0, true, false, true, s, 1.0 / 60.0)
	near(v.x, float(s["max_speed"]) * float(s["boost"]), 0.01, "boost")
	# Reverse is capped
	var r := Vector2.ZERO
	for i in 600:
		r = VehicleSpecs.drive_step(r, -1.0, false, false, true, s, 1.0 / 60.0)
	near(r.x, -float(s["max_speed"]) * float(s["reverse"]), 0.01)
	# Braking against the motion is quicker than coasting
	var a := VehicleSpecs.drive_step(Vector2(15, 0), -1.0, false, false, true, s, 0.5)
	var c := VehicleSpecs.drive_step(Vector2(15, 0), 0.0, false, false, true, s, 0.5)
	check(a.x < c.x, "braking beats coasting")


func test_drift_hoverbike_slides_crawler_grips() -> void:
	var bike := VehicleSpecs.drive_step(Vector2(20, 8), 1.0, false, false, true, VehicleSpecs.spec("hoverbike"), 0.25)
	var crawl := VehicleSpecs.drive_step(Vector2(10, 8), 1.0, false, false, true, VehicleSpecs.spec("crawler"), 0.25)
	check(bike.y > 3.0, "the hoverbike keeps its slide (%.2f)" % bike.y)
	check(crawl.y < 0.5, "the crawler bites (%.2f)" % crawl.y)
	var rover := VehicleSpecs.spec("rover")
	var grip := VehicleSpecs.drive_step(Vector2(15, 6), 0.0, false, false, true, rover, 0.25)
	var slide := VehicleSpecs.drive_step(Vector2(15, 6), 0.0, false, true, true, rover, 0.25)
	check(slide.y > grip.y * 2.0, "Ctrl slides the rover")


func test_wheels_cannot_throttle_in_the_air() -> void:
	var s := VehicleSpecs.spec("crawler")
	var v := VehicleSpecs.drive_step(Vector2(5, 0), 1.0, false, false, false, s, 0.5)
	eq(v.x, 5.0, "no air control on tracks")


func test_turning() -> void:
	var rover := VehicleSpecs.spec("rover")
	eq(VehicleSpecs.yaw_rate(1.0, 0.0, false, rover), 0.0, "a wheeled rover does not turn standing still")
	check(VehicleSpecs.yaw_rate(1.0, -5.0, false, rover) < 0.0, "reversing steers the other way")
	check(VehicleSpecs.yaw_rate(1.0, 0.0, false, VehicleSpecs.spec("crawler")) > 0.0, "tracks turn on the spot")
	check(absf(VehicleSpecs.yaw_rate(1.0, 20.0, false, rover)) < absf(VehicleSpecs.yaw_rate(1.0, 6.0, false, rover)), "less steering at speed")


func test_hover_settles_at_its_height_and_glides_off_edges() -> void:
	for k in ["hoverbike", "skimmer"]:
		var s := VehicleSpecs.spec(k)
		var y := 0.0  # clearance over flat ground
		var vy := 0.0
		for i in 600:
			vy += VehicleSpecs.hover_accel(y, vy, s) * (1.0 / 60.0)
			y += vy / 60.0
		near(y, float(s["hover"]), 0.02, k + " hovers at its height")
		var fall := VehicleSpecs.hover_accel(-1.0, -1.0, s)
		check(fall > -VehicleSpecs.GRAVITY and fall < 0.0, k + " glides when the ground falls away")
		eq(VehicleSpecs.hover_accel(-1.0, 3.0, s), -VehicleSpecs.GRAVITY, k + " rises against full gravity")


func test_skimmer_hop_clears_a_crest() -> void:
	## From the cushion, the crest jump must clear the Julia boundary ridge (CREST_M).
	var s := VehicleSpecs.spec("skimmer")
	var y := float(s["hover"])
	var vy := float(s["jump"])
	var top := y
	for i in 1200:
		vy += VehicleSpecs.hover_accel(y, vy, s) / 60.0
		y += vy / 60.0
		top = maxf(top, y)
	check(top > JuliaHeightfield.CREST_M + 1.0, "apex %.1f m" % top)


func test_spring_is_stable_and_damped() -> void:
	for k in VehicleSpecs.KINDS:
		var s := VehicleSpecs.spec(k)
		var st := Vector2(-0.4, -3.0)
		var peak := 0.0
		for i in 600:
			st = VehicleSpecs.spring_step(st.x, st.y, 0.0, float(s["susp_k"]), float(s["susp_c"]), 1.0 / 60.0)
			if i > 60:
				peak = maxf(peak, absf(st.x))
		check(absf(st.x) < 0.01, k + " settles")
		check(peak < 0.2, k + " damped")


func test_landing_squash_and_fuel() -> void:
	var s := VehicleSpecs.spec("rover")
	eq(VehicleSpecs.landing_squash(-1.0, s), 0.0, "a soft touch does not squash")
	check(VehicleSpecs.landing_squash(-8.0, s) > VehicleSpecs.landing_squash(-4.0, s), "harder lands squash more")
	check(VehicleSpecs.landing_squash(-100.0, s) <= 0.45, "bounded")
	var h := VehicleSpecs.spec("hopper")
	var f := Vector2(float(h["fuel_s"]), 0.0)
	var t := 0.0
	while f.x > 0.0 and t < 60.0:
		f = VehicleSpecs.fuel_step(f.x, true, false, h, 0.1)
		t += 0.1
	near(t, float(h["fuel_s"]), 0.11, "the tank lasts fuel_s")
	eq(VehicleSpecs.fuel_step(0.0, true, false, h, 0.1).y, 0.0, "no thrust when empty")
	check(VehicleSpecs.fuel_step(0.0, false, true, h, 1.0).x > 0.0, "refuels on the ground")
	check(float(h["thrust"]) > VehicleSpecs.GRAVITY * 2.0, "the hopper can lift itself")


func test_body_tilt() -> void:
	var t := VehicleSpecs.body_tilt(1.0, 0.0, 0.0, 0.0, 2.0, 2.0)
	check(t.x > 0.0, "nose up when the front is higher")
	t = VehicleSpecs.body_tilt(0.0, 0.0, 0.5, 0.0, 2.0, 2.0)
	check(t.y > 0.0, "left higher rolls")
	eq(VehicleSpecs.body_tilt(0, 0, 0, 0, 2, 2), Vector2.ZERO)


func test_garage_site_is_on_land_clear_and_deterministic() -> void:
	# An island around (0, 60), sea elsewhere
	var island := func(x: float, z: float) -> float:
		return 0.4 * sin(x * 0.1) if Vector2(x, z).distance_to(Vector2(0, 60)) < 45.0 else -25.0
	var s := GarageSite.find_site(island)
	check(s["ok"], "found a site on land")
	var at: Vector2 = s["at"]
	check(at.distance_to(Vector2(0, 60)) + GarageSite.RADIUS <= 45.0 + 0.01, "whole terrace on the island")
	for k in GarageSite.KEEP_OUT:
		check(at.distance_to(k[0]) >= float(k[1]) + GarageSite.RADIUS, "clear of %s" % str(k[0]))
	eq(GarageSite.find_site(island)["at"], at, "deterministic")
	# A keep-out (the fair) pushes it away
	var s2 := GarageSite.find_site(island, [[at, 20.0]])
	if s2["ok"]:
		check((s2["at"] as Vector2).distance_to(at) >= 20.0 + GarageSite.RADIUS, "clear of the extra keep-out")
	# No land: best effort, never reported as ok
	check(not GarageSite.find_site(func(_x: float, _z: float) -> float: return -40.0)["ok"])


func test_bays_face_the_pad_centre() -> void:
	var bays := GarageSite.bay_layout(Vector2(0, 1))
	eq(bays.size(), VehicleSpecs.KINDS.size())
	for b in bays:
		var at: Vector2 = b["at"]
		near(at.length(), GarageSite.BAY_RING, 0.001)
		check(at.y > 0.0, "on the far side from the Core")
		var fwd := Vector2(-sin(b["yaw"]), -cos(b["yaw"]))
		near(fwd.dot(-at.normalized()), 1.0, 0.001, "faces the centre")
	for i in bays.size():
		for j in range(i + 1, bays.size()):
			check((bays[i]["at"] as Vector2).distance_to(bays[j]["at"]) > 5.8, "bays do not overlap")


func test_engine_loops_wrap_seamlessly() -> void:
	for k in VehicleAudio.DEFS:
		var n := int(VehicleAudio.RATE * VehicleAudio.LOOP_S)
		var buf := VehicleAudio.samples(VehicleAudio.DEFS[k], n, int(VehicleAudio.RATE * 0.05), 7)
		var peak := 0.0
		var step := 0.0
		for i in n:
			peak = maxf(peak, absf(buf[i]))
			if i > 0:
				step = maxf(step, absf(buf[i] - buf[i - 1]))
		check(peak <= 0.71, k + " peak")
		check(absf(buf[0] - buf[n - 1]) <= step * 1.5 + 0.01, "%s wraps without a click (%.3f vs step %.3f)" % [k, absf(buf[0] - buf[n - 1]), step])
	var w := VehicleAudio.engine("rover")
	eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	check(VehicleAudio.engine("rover") == w, "cached")
