extends TestCase
## The Affection Fair's midway games: titles, seeding by the ticket's tx hash, prizes.

const TX := "0x9f3c2b1a00000000000000000000000000000000000000000000000012345678"


func test_every_stall_kind_with_a_sign_is_playable_or_food() -> void:
	for k in Funfair.STALL_TITLES:
		check(MidwayGame.has_game(k) or k in ["pulse", "eris"], "%s has a game (or is a food stall)" % k)
	check(MidwayGame.has_game("striker"), "the high striker plays")
	for k in MidwayGame.GAMES:
		check(MidwaySim.SPEC.has(k), "%s has a sim" % k)
		check(MidwayStage.create(k) != null, "%s has a 3D stage" % k)


func test_seed_from_tx_is_deterministic() -> void:
	eq(MidwayGame.seed_from_tx(TX), 0x12345678)
	eq(MidwayGame.seed_from_tx("nope"), 0)


func test_primes() -> void:
	for n in [2, 3, 5, 7, 11, 13, 97, 199]:
		check(MidwayGame.is_prime(n), "%d is prime" % n)
	for n in [0, 1, 4, 9, 15, 91, 121, 200]:
		check(not MidwayGame.is_prime(n), "%d is not prime" % n)


func test_prizes() -> void:
	check(MidwayGame.prize("striker", MidwaySim.par("striker")).begins_with("GRAND"))
	eq(MidwayGame.prize_kind("striker", MidwaySim.par("striker")), "trophy")
	eq(MidwayGame.prize_kind("striker", 1), "pennant", "any score wins something")
	eq(MidwayGame.prize("striker", 0), "", "no score, no prize")
	check(not MidwayGame.prize("striker", 0).begins_with("GRAND"))

	eq(MidwayGame.max_score("motzkin"), 37000, "20 shots of 250 at ×4 in the frenzy, the bound")


func test_rocket_voyage_heading_and_ramp() -> void:
	var up := RocketVoyage.heading(0.0, PI * 0.5)
	near(up.y, 1.0, 1e-5, "pitch 90°: straight up")
	var level := RocketVoyage.heading(0.0, 0.0)
	near(level.z, -1.0, 1e-5, "pitch 0: level, toward -Z")
	# Full thrust from liftoff reaches the wormhole in about half a minute (slowly), boost in half that
	var b := 18.0 / RocketVoyage.C_MS
	var t := 0.0
	while b < RocketVoyage.WORMHOLE_BETA and t < 300.0:
		b += RocketVoyage.beta_rate(b, true, false, false) * 0.1
		t += 0.1
	check(t > 20.0 and t < 50.0, "thrust to the wormhole takes %.0f s" % t)
	check(RocketVoyage.beta_rate(0.5, false, false, true) < 0.0, "the brake slows")
	eq(RocketVoyage.beta_rate(0.5, false, false, false), 0.0, "coasting keeps speed")


func test_wormhole_crossing_on_long_frames() -> void:
	var c := Vector3(0, 0, -1000)
	var n := Vector3(0, 0, 1)
	check(RocketVoyage.crosses_disc(Vector3(0, 0, -900), Vector3(0, 0, -1300), c, n, 320.0), "a long frame straight through counts")
	check(RocketVoyage.crosses_disc(Vector3(100, 50, -990), Vector3(100, 50, -1010), c, n, 320.0), "off-centre but inside the ring")
	check(not RocketVoyage.crosses_disc(Vector3(500, 0, -900), Vector3(500, 0, -1100), c, n, 320.0), "outside the ring misses")
	check(not RocketVoyage.crosses_disc(Vector3(0, 0, -100), Vector3(0, 0, -200), c, n, 320.0), "not there yet")


func test_ride_steps_are_short_walks_not_teleports() -> void:
	near(RideBase.step_seconds(0.0), RideBase.STEP_MIN_S, 1e-5, "a step on the spot still takes a moment")
	check(RideBase.step_seconds(3.0) > 0.6 and RideBase.step_seconds(3.0) <= RideBase.STEP_MAX_S, "3 m: a short walk")
	near(RideBase.step_seconds(80.0), RideBase.STEP_MAX_S, 1e-5, "never long")
	var a := Vector3(0, 0, 0)
	var b := Vector3(4, 1, 0)
	near(RideBase.step_point(a, b, 0.0).distance_to(a), 0.0, 1e-5, "starts where they stood")
	near(RideBase.step_point(a, b, 1.0).distance_to(b), 0.0, 1e-5, "ends on the seat")
	var mid := RideBase.step_point(a, b, 0.5)
	check(mid.x > 0.5 and mid.x < 3.5, "in between halfway")
	check(RideBase.step_point(a, b, 0.8).y > a.lerp(b, 0.8 * 0.8 * (3.0 - 1.6)).y, "a little hop onto the seat")


func test_prize_models_build() -> void:
	for k in FairPrizes.KINDS:
		var m := FairPrizes.mesh(k)
		check(m != null and m.get_surface_count() >= 2, "%s: one mesh, a surface per material (%d)" % [k, m.get_surface_count() if m else 0])
	eq(MidwayGame.prize_kind("motzkin", MidwaySim.par("motzkin") * 7 / 10), "rocket")
	eq(MidwayGame.prize_kind("saat", MidwaySim.par("saat") / 2), "moon")
