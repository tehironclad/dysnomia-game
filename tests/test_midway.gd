extends TestCase
## The Affection Fair's midway games: pure rules, seeded by the ticket's tx hash.

const TX := "0x9f3c2b1a00000000000000000000000000000000000000000000000012345678"


func test_every_stall_kind_with_a_sign_is_playable_or_food() -> void:
	for k in Funfair.STALL_TITLES:
		check(MidwayGame.has_game(k) or k in ["pulse", "eris"], "%s has a game (or is a food stall)" % k)
	check(MidwayGame.has_game("striker"), "the high striker plays")


func test_seed_from_tx_is_deterministic() -> void:
	eq(MidwayGame.seed_from_tx(TX), 0x12345678)
	eq(MidwayGame.seed_from_tx("nope"), 0)
	eq(MidwayGame.wheel_values(7), MidwayGame.wheel_values(7), "same ticket, same wheel")
	eq(MidwayGame.prime_sequence(7), MidwayGame.prime_sequence(7))
	near(MidwayGame.toss_target(7, 1), MidwayGame.toss_target(7, 1), 1e-9)


func test_primes() -> void:
	for n in [2, 3, 5, 7, 11, 13, 97, 199]:
		check(MidwayGame.is_prime(n), "%d is prime" % n)
	for n in [0, 1, 4, 9, 15, 91, 121, 200]:
		check(not MidwayGame.is_prime(n), "%d is not prime" % n)
	var seq := MidwayGame.prime_sequence(42)
	var primes := 0
	for n in seq:
		if MidwayGame.is_prime(n):
			primes += 1
	check(primes >= 8 and primes < seq.size(), "a fair mix of primes (%d of %d)" % [primes, seq.size()])


func test_scoring() -> void:
	eq(MidwayGame.striker_points(1.0), 100)
	eq(MidwayGame.striker_points(0.5), 50)
	eq(MidwayGame.toss_points(0.5, 0.5), 100)
	eq(MidwayGame.toss_points(0.55, 0.5), 60)
	eq(MidwayGame.toss_points(0.9, 0.5), 0)
	eq(MidwayGame.ring_points(0.5, 0.5), 100, "dead on a peg")
	eq(MidwayGame.ring_points(0.35, 0.35), 0, "between pegs")
	check(MidwayGame.prize("striker", 300).begins_with("GRAND"))
	check(not MidwayGame.prize("striker", 0).begins_with("GRAND"))
	eq(MidwayGame.prize("saat", 0), "", "the fortune teller has no score")


func test_wheel_stops_the_same_way_every_time() -> void:
	var stop := MidwayGame.wheel_stop(1.0)
	near(stop - 1.0, MidwayGame.WHEEL_SPEED * MidwayGame.WHEEL_SPEED / (2.0 * MidwayGame.WHEEL_DECEL), 1e-6)
	eq(MidwayGame.wheel_segment(0.0), 0)
	eq(MidwayGame.wheel_segment(-TAU / 12.0 * 3.5), 3)
	for a in [0.0, 1.0, 2.5, 5.9]:
		var k := MidwayGame.wheel_segment(a)
		check(k >= 0 and k < 12)


func test_shy_has_hits_and_misses() -> void:
	var row: Dictionary = MidwayGame.shy_rows(5)[0]
	var hits := 0
	for i in 200:
		if MidwayGame.shy_hit(row, i * 0.05):
			hits += 1
	check(hits > 10 and hits < 190, "some throws hit, some miss (%d/200)" % hits)


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
