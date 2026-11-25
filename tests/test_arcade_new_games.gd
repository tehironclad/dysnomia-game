extends TestCase
## The three arcade games added 2026-11-25 (Motzkin Sieve, Qing Orbit, YUE Courier): their pure rules,
## and that a strip's plays start them the way the others start (ArcadePay's arcade items, the play seed).
## The shared checks (deterministic from the seed, one game_over, attract never ends, the 3D worlds
## follow) run for every ArcadeCatalog.GAMES entry in test_arcade.gd / test_arcade_dive.gd.

const SIEVE := "res://scripts/arcade/motzkin_sieve.gd"
const ORBIT := "res://scripts/arcade/qing_orbit.gd"
const COURIER := "res://scripts/arcade/yue_courier.gd"


func _game(path: String, seed: int = 11) -> ArcadeGame:
	var g: ArcadeGame = load(path).new()
	g.start(seed)
	g.scripted_input = 0
	return g


# ── Motzkin Sieve ────────────────────────────────────────────────────────────


func test_sieve_number_theory() -> void:
	var s = load(SIEVE)
	var primes := []
	for n in 60:
		if s.is_prime(n):
			primes.append(n)
	eq(primes, [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59])
	check(s.is_prime(15511) and s.is_prime(127) and not s.is_prime(323) and not s.is_prime(1), "the Motzkin primes; 323 = 17 × 19")
	eq(s.factors(91), [7, 13])
	eq(s.factors(12), [2, 2, 3])
	eq(s.factors(97), [97])
	eq(s.factors(1024), [2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
	eq(s.motzkin(12), [1, 1, 2, 4, 9, 21, 51, 127, 323, 835, 2188, 5798])
	# The Motzkin primes the game drops are exactly the primes among the first Motzkin numbers.
	var mp := []
	for m in s.motzkin(16):
		if s.is_prime(m) and not mp.has(m):
			mp.append(m)
	eq(mp, s.MOTZKIN_PRIMES)
	eq(s.multiplier_of(0), 1)
	eq(s.multiplier_of(4), 2)
	eq(s.multiplier_of(400), 9, "capped")


func test_sieve_shoot_composite_into_factors() -> void:
	var g = _game(SIEVE)
	g.blocks = [{"x": 160.0, "y": 150.0, "n": 91, "prime": false, "motzkin": false, "w": 26.0}]
	g.spawn_t = 99.0
	g.sieve_x = 160.0
	g.scripted_input = ArcadeGame.IN_FIRE
	for i in 20:
		g.step(ArcadeGame.DT)
		g.scripted_input = 0
	eq(g.blocks.size(), 0, "the composite broke")
	var ns := []
	for sh in g.shards:
		ns.append(int(sh["n"]))
	ns.sort()
	eq(ns, [7, 13], "into its prime factors")
	eq(g.last_event, "91 = 7 × 13")
	eq(g.lives, 3, "no life lost")
	check(g.score > 0, "scores")
	g.free()


func test_sieve_shooting_a_prime_costs_a_life() -> void:
	var g = _game(SIEVE)
	g.blocks = [{"x": 160.0, "y": 150.0, "n": 89, "prime": true, "motzkin": false, "w": 26.0}]
	g.spawn_t = 99.0
	g.scripted_input = ArcadeGame.IN_FIRE
	for i in 20:
		g.step(ArcadeGame.DT)
		g.scripted_input = 0
	eq(g.lives, 2)
	eq(g.shards.size(), 0, "a prime doesn't shatter")
	g.free()


func test_sieve_floor_rules() -> void:
	# A prime through to the floor banks its value; caught on the sieve, double; a Motzkin prime on the
	# sieve adds the bonus. A composite on the floor leaks: a life.
	var g = _game(SIEVE)
	g.spawn_t = 99.0
	g.sieve_x = 40.0
	g.blocks = [{"x": 260.0, "y": 214.0, "n": 37, "prime": true, "motzkin": false, "w": 26.0}]
	for i in 30:
		g.step(ArcadeGame.DT)
	eq(g.score, 37, "banked")
	eq(g.last_event, "BANKED 37")
	g.blocks = [{"x": 40.0, "y": 214.0, "n": 127, "prime": true, "motzkin": true, "w": 33.0}]
	for i in 30:
		g.step(ArcadeGame.DT)
	eq(g.score, 37 + (127 * 2 + g.MOTZKIN_BONUS) * 1, "a Motzkin prime caught")
	g.blocks = [{"x": 260.0, "y": 214.0, "n": 51, "prime": false, "motzkin": false, "w": 26.0}]
	for i in 30:
		g.step(ArcadeGame.DT)
	eq(g.lives, 2, "a composite leaked")
	eq(g.combo, 0)
	g.free()


# ── Qing Orbit ───────────────────────────────────────────────────────────────


func test_orbit_geometry() -> void:
	var o = load(ORBIT)
	var p: Vector2 = o.at(50.0, 0.0)
	near(p.x, o.CENTER.x + 50.0, 0.001)
	near(o.at(50.0, PI * 0.5).y, o.CENTER.y - 50.0, 0.001, "counter-clockwise: up the screen at 90°")
	near(o.angle_to(3.0, -3.0), TAU - 6.0, 0.0001, "the short way round")
	near(o.angle_to(-3.0, 3.0), -(TAU - 6.0), 0.0001)


func test_orbit_rings_and_pickups() -> void:
	var g = _game(ORBIT)
	g.things.clear()
	g.spawn_t = 99.0
	eq(g.ring, 1)
	g.scripted_input = ArcadeGame.IN_RIGHT
	g.step(ArcadeGame.DT)
	g.scripted_input = 0
	for i in 20:
		g.step(ArcadeGame.DT)
	eq(g.ring, 2, "right climbs outward")
	eq(g.hit_ring(), 2)
	near(g.radius(), g.RINGS[2], 0.01)
	# A coin just ahead on this ring: picked up.
	g.things = [{"ring": 2, "a": g.angle + 0.05, "kind": 0, "w": 0.0}]
	for i in 30:
		g.step(ArcadeGame.DT)
	eq(g.score, 10, "10 × ×1")
	eq(g.streak, 1)
	# A rift ahead: a life, the multiplier back to 1, a moment untouchable.
	g.mult = 4
	g.things = [{"ring": 2, "a": g.angle + 0.05, "kind": 1, "w": 0.0}]
	for i in 30:
		g.step(ArcadeGame.DT)
	eq(g.lives, 2)
	eq(g.mult, 1)
	check(g.safe > 0.0, "untouchable for a moment")
	g.free()


func test_orbit_dash_is_untouchable() -> void:
	var g = _game(ORBIT)
	g.things.clear()
	g.spawn_t = 99.0
	g.scripted_input = ArcadeGame.IN_FIRE
	g.step(ArcadeGame.DT)
	g.scripted_input = 0
	check(g.dash > 0.0 and g.charge == 0.0, "the dash fires and spends the charge")
	g.things = [{"ring": g.ring, "a": g.angle + 0.06, "kind": 1, "w": 0.0}]
	for i in 8:
		g.step(ArcadeGame.DT)
	eq(g.lives, 3, "a rift passes through a dash")
	g.scripted_input = ArcadeGame.IN_FIRE
	g.step(ArcadeGame.DT)
	check(g.charge < 1.0 and g.dash <= ArcadeGame.DT * 30, "no second dash before it recharges")
	g.free()


# ── YUE Courier ──────────────────────────────────────────────────────────────


func test_courier_pads_and_score() -> void:
	var c = load(COURIER)
	var pads: Array = c.pad_positions()
	eq(pads.size(), 5)
	for i in pads.size():
		check(c.ARENA.has_point(pads[i]), "pad %d inside the arena" % i)
		for j in range(i + 1, pads.size()):
			check((pads[i] as Vector2).distance_to(pads[j]) > c.PAD_HIT * 4.0, "pads %d and %d apart" % [i, j])
	eq(c.delivery_score(3.7, 1), 160)
	eq(c.delivery_score(0.0, 3), 300)
	eq(c.delivery_score(5.0, 20), 1600, "the chain caps at ×8")


func test_courier_pickup_and_delivery() -> void:
	var g = _game(COURIER)
	g.wisp_t = 99.0
	var src: int = g.source
	var dst: int = g.dest
	check(src != dst, "a parcel goes somewhere else")
	g.pos = g.pads[src]
	g.step(ArcadeGame.DT)
	check(g.carrying, "picked up on its pad")
	eq(g.score, 10)
	var before: float = g.clock
	g.pos = g.pads[dst]
	g.step(ArcadeGame.DT)
	eq(g.delivered, 1)
	eq(g.chain, 1)
	eq(g.score, 10 + g.delivery_score(before - ArcadeGame.DT, 1))
	check(not g.carrying and g.source != dst, "a new parcel, not on the pad you stand on")
	g.free()


func test_courier_pulse_and_wisps() -> void:
	var g = _game(COURIER)
	g.wisp_t = 99.0
	g.pos = Vector2(160, 200)
	g.wisps = [{"p": Vector2(180, 200), "v": Vector2.ZERO, "stun": 0.0}, {"p": Vector2(160, 60), "v": Vector2.ZERO, "stun": 0.0}]
	g.scripted_input = ArcadeGame.IN_FIRE
	g.step(ArcadeGame.DT)
	check(float(g.wisps[0]["stun"]) > 0.0, "the near wisp is stunned")
	eq(float(g.wisps[1]["stun"]), 0.0, "the far one is not")
	eq(g.score, 15)
	check(g.charge < 1.0, "the pulse recharges")
	# A wisp that reaches you: a life and the chain.
	g.chain = 3
	g.wisps = [{"p": g.pos + Vector2(3, 0), "v": Vector2.ZERO, "stun": 0.0}]
	g.scripted_input = 0
	g.step(ArcadeGame.DT)
	eq(g.lives, 2)
	eq(g.chain, 0)
	g.free()


# ── paying for them ──────────────────────────────────────────────────────────


func test_new_games_take_arcade_strips() -> void:
	for id in ["motzkin_sieve", "qing_orbit", "yue_courier"]:
		var e := ArcadeCatalog.find(id)
		check(not e.is_empty() and e["playable"] and e["kind"] == "game", id + " is a playable cabinet")
		check(e.has("world"), id + " dives into its own world")
	# A strip's items are cabinet-agnostic: any arcade play starts any cabinet.
	check(ArcadePay.ARCADE_ITEMS.has(TicketCode.ARCADE) and ArcadePay.ARCADE_ITEMS.has(TicketCode.GENERAL), "credits and strips both count")
	var tx := "0x" + "ab".repeat(32)
	var s0 := ArcadeWorld.seed_from_tx(TicketCode.seed_tx(tx, 0))
	var s1 := ArcadeWorld.seed_from_tx(TicketCode.seed_tx(tx, 1))
	check(s0 != s1, "each strip play has its own seed")
	for path in [SIEVE, ORBIT, COURIER]:
		var a: ArcadeGame = load(path).new()
		var b: ArcadeGame = load(path).new()
		a.start(s0)
		b.start(s0)
		for i in 600:
			a.scripted_input = (i / 20) % 3 + (ArcadeGame.IN_FIRE if i % 17 == 0 else 0)
			b.scripted_input = a.scripted_input
			a.step(ArcadeGame.DT)
			b.step(ArcadeGame.DT)
		eq([a.score, a.lives], [b.score, b.lives], path.get_file() + ": a play replays from its seed")
		a.free()
		b.free()
