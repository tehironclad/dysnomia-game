extends TestCase
## The landmark supertall and base jumping: heights from the tier and the
## Hypobar total, placement, the lift and plank geometry, the lift profile,
## glide and landing maths. No network, no scene.

const P := preload("res://scripts/world/skyline/landmark_plan.gd")
const J := preload("res://scripts/world/skyline/jump_physics.gd")


func test_wild_and_outpost_build_nothing() -> void:
	check(P.spec(0, -INF).is_empty(), "Wild: moonscape")
	check(P.spec(1, 3.5).is_empty(), "Outpost: moonscape")
	check(P.masses({}).is_empty(), "no masses without a spec")


func test_class_and_height_by_tier() -> void:
	eq(P.spec(2, 4.0)["kind"], "inn")
	eq(P.spec(3, 6.5)["kind"], "hotel")
	eq(P.spec(4, 8.5)["kind"], "supertall")
	eq(P.spec(5, 9.1)["kind"], "burj")
	# Heights grow with the Hypobar total and never shrink across a tier boundary
	var last := 0.0
	for x in [4.0, 4.5, 5.0, 5.99, 6.0, 7.0, 7.99, 8.0, 8.5, 8.99, 9.0, 9.5, 10.0, 11.0, 13.0]:
		var t := 2 if x < 6.0 else (3 if x < 8.0 else (4 if x < 9.0 else 5))
		var s: Dictionary = P.spec(t, x)
		check(float(s["roof"]) >= last, "roof grows (log %.2f: %d m after %d m)" % [x, int(s["roof"]), int(last)])
		last = s["roof"]
		eq(fmod(float(s["roof"]), P.FLOOR_M), 0.0, "whole floors")
		eq(int(s["floors"]) * int(P.FLOOR_M), int(s["roof"]))
		check(float(s["top"]) >= float(s["roof"]), "the top is at or above the roof")
	# RatKing (log10 ≈ 9.1, a Capital): a Burj with a spire over 550 m
	var rk: Dictionary = P.spec(5, 9.1)
	check(float(rk["roof"]) >= 440.0 and float(rk["roof"]) <= 460.0, "RatKing roof %d m" % int(rk["roof"]))
	check(float(rk["top"]) > 550.0, "with its spire")
	# The top tier is capped
	eq(P.spec(5, 30.0)["roof"], 600.0)


func test_sign_from_the_qing_name() -> void:
	eq(P.sign_name("burj", "RatKing QING"), "BURJ RATKING")
	eq(P.sign_name("supertall", "Zürich QING"), "ZÜRICH TOWER")
	eq(P.sign_name("hotel", "Qingston"), "HOTEL QINGSTON")
	eq(P.sign_name("inn", ""), "QING SKY INN")


func test_lift_shaft_never_cuts_the_tower() -> void:
	for t in [2, 3, 4, 5]:
		var s: Dictionary = P.spec(t, [0, 0, 5.0, 7.0, 8.5, 10.0][t])
		var ms := P.masses(s)
		check(ms.size() > 0, "%s has masses" % s["kind"])
		var l := P.lift(s)
		var half: float = l["half"]
		for dx in [-half, 0.0, half]:
			for dz in [-half, 0.0, half]:
				var p := Vector2(float(l["x"]) + dx, float(l["z"]) + dz)
				for m in ms:
					check(not P.in_footprint(p, m), "%s: the lift shaft at %s is clear of the masses" % [s["kind"], str(p)])
		check(P.deck_radius(s) >= float(l["z"]) + half, "%s: the deck covers the lift's top stop" % s["kind"])


func test_plank_tip_clears_everything_below() -> void:
	for t in [2, 3, 4, 5]:
		var s: Dictionary = P.spec(t, [0, 0, 5.0, 7.0, 8.5, 10.0][t])
		var ms := P.masses(s)
		for want in [0.0, 1.0, PI * 0.5, 2.5, -1.2, -PI * 0.5]:
			var pl := P.plank(s, want)
			var b: float = pl["bearing"]
			var tip := Vector2(cos(b), sin(b)) * float(pl["to"])
			for m in ms:
				check(not P.in_footprint(tip, m), "%s: plank tip toward %.2f is over open air" % [s["kind"], b])
			check(absf(angle_difference(b, PI * 0.5)) >= deg_to_rad(54.0), "%s: the plank never points over the lift" % s["kind"])
			check(float(pl["to"]) > float(pl["from"]), "the plank has length")


func test_footprint_rotation_matches_godot_yaw() -> void:
	# A 10 × 2 box turned by yaw = −a points its long side along (cos a, sin a) in (x, z).
	var a := deg_to_rad(30.0)
	var m := {"size": Vector3(10, 1, 2), "pos": Vector3.ZERO, "yaw": -a}
	check(P.in_footprint(Vector2(cos(a), sin(a)) * 4.5, m), "along the long side")
	check(not P.in_footprint(Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * 4.5, m), "not across it")
	# And Godot agrees: a node turned by that yaw sends its +X there
	var basis := Basis(Vector3.UP, -a)
	var x := basis * Vector3.RIGHT
	near(x.x, cos(a), 1e-5)
	near(x.z, sin(a), 1e-5)


func test_sites_on_land_clear_and_deterministic() -> void:
	# An island plateau (0 m) inside 230 m, sea (−20 m) beyond; gentle relief
	var island := func(x: float, z: float) -> float:
		return 0.5 * sin(x * 0.04) * cos(z * 0.05) if Vector2(x, z).length() < 230.0 else -20.0
	var fair_at := Vector2(0, 112)
	var s := P.tower_site(island, [[fair_at, 42.0]])
	check(s["ok"], "a tower site fully on land")
	var at: Vector2 = s["at"]
	check(at.length() + P.PLAZA_R <= 230.0 + 0.01, "the plaza is on the island")
	check(maxf(absf(at.x), absf(at.y)) + P.PLAZA_R <= P.BORDER_KEEP, "inside the border fields")
	check(at.length() >= P.CORE_CLEAR, "clear of the Core and the skyline")
	check(at.distance_to(fair_at) >= 42.0 + P.PLAZA_R + 10.0, "clear of the fair")
	eq(P.tower_site(island, [[fair_at, 42.0]])["at"], at, "deterministic")
	var r := P.ring_site(island, at, [[fair_at, 42.0]])
	check(r["ok"], "a landing ring on land")
	var ra: Vector2 = r["at"]
	check(ra.length() >= 62.0, "the ring is clear of the Core")
	check(ra.distance_to(at) >= P.PLAZA_R + P.RING_R + 46.0, "and away from the tower's foot")
	check(ra.distance_to(fair_at) >= 42.0 + P.RING_R + 8.0, "and the fair")
	# No land at all: best effort, never reported as a real site
	check(not P.tower_site(func(_x: float, _z: float) -> float: return -30.0, [[fair_at, 42.0]])["ok"])


func test_lift_profile() -> void:
	for h in [30.0, 100.0, 448.0, 600.0]:
		var T := P.lift_duration(h)
		near(P.lift_travel(0.0, h), 0.0, 1e-4)
		near(P.lift_travel(T, h), h, 1e-3, "arrives at %d m" % int(h))
		var last := -1.0
		var vmax := 0.0
		var dt := 0.05
		var t := 0.0
		while t <= T:
			var y := P.lift_travel(t, h)
			check(y >= last - 1e-6, "never goes back down")
			if last >= 0.0:
				vmax = maxf(vmax, (y - last) / dt)
			last = y
			t += dt
		check(vmax <= P.LIFT_V + 0.5, "top speed %.1f m/s" % vmax)
	check(P.lift_duration(448.0) < 20.0, "a Burj ride takes under 20 s")


func _settle(mode: int, pitch: float, secs: float = 40.0) -> Vector3:
	var v := Vector3(0, -5, -5)
	var dt := 1.0 / 60.0
	for i in int(secs / dt):
		v = J.step(mode, v, 0.0, 0.0, pitch, Vector3.ZERO, false, 0.0, Vector3.ZERO, 3.2, dt)
	return v


func test_freefall_reaches_terminal_speed() -> void:
	var v := _settle(J.Mode.FREEFALL, 0.0, 60.0)
	near(v.length(), J.FREEFALL_VT, 0.5, "belly-to-earth terminal")
	near(v.x, 0.0, 0.1, "no drift without wind or input")
	var dt := 1.0 / 60.0
	var w := Vector3.ZERO
	for i in 3600:
		w = J.step(J.Mode.FREEFALL, w, 0.0, 0.0, 0.0, Vector3.ZERO, true, 0.0, Vector3.ZERO, 3.2, dt)
	near(w.length(), J.DIVE_VT, 0.5, "head-down terminal")


func test_wingsuit_glides_and_canopy_lands_soft() -> void:
	var v := _settle(J.Mode.WINGSUIT, 0.0)
	var ratio := Vector2(v.x, v.z).length() / -v.y
	check(ratio > 2.5 and ratio < 4.0, "wingsuit glide ratio %.2f" % ratio)
	check(v.z < 0.0, "flies where it faces (−Z at yaw 0)")
	var dive := _settle(J.Mode.WINGSUIT, 1.0)
	var flare := _settle(J.Mode.WINGSUIT, -1.0)
	check(dive.length() > v.length() and -dive.y > -v.y, "diving is faster and steeper")
	check(-flare.y < -v.y, "flaring sinks slower")
	var c := _settle(J.Mode.CANOPY, 0.0)
	check(-c.y < 3.5 and Vector2(c.x, c.z).length() < 9.0, "canopy flies slow and soft")
	eq(J.landing(c)["mult"], 1.0, "a canopy landing stands up")
	eq(J.landing(v)["mult"], 0.6, "a wingsuit landing without a canopy skids")
	eq(J.landing(Vector3(0, -30, 0))["mult"], 0.25, "a freefall impact")
	# Wind carries the canopy
	var dt := 1.0 / 60.0
	var w := c
	for i in 2400:
		w = J.step(J.Mode.CANOPY, w, 0.0, 0.0, 0.0, Vector3.ZERO, false, 0.0, Vector3(3, 0, 0), 3.2, dt)
	near(w.x - c.x, 3.0, 0.05, "drifts with the wind")


func test_turning_and_edge() -> void:
	var y := J.turn(J.Mode.WINGSUIT, 0.0, 1.0, 1.0)
	near(y, -J.TURN[J.Mode.WINGSUIT], 1e-5, "right turns clockwise (yaw down)")
	eq(J.edge_push(Vector3(100, 0, -50)), Vector3.ZERO, "no push inside")
	check(J.edge_push(Vector3(240, 0, 0)).x < 0.0, "pushed back from the east edge")
	check(J.edge_push(Vector3(0, 0, -240)).z > 0.0, "and the north edge")


func test_wind_is_the_territorys() -> void:
	var a := J.wind("0xE4169cf239e2fdc6e6e4a3a6fa0a703058ce400b")
	eq(a, J.wind("0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"), "keyed by lower-cased address")
	check(a.length() >= 1.0 and a.length() <= 6.0, "1–6 m/s with gusts (%.2f)" % a.length())
	eq(a.y, 0.0)
	check(J.wind("0xd127839b83cbf537c29b7d268c135f745a0da2e8") != a, "territories differ")


func test_score() -> void:
	var soft := Vector3(2, -2.5, 1)
	var bull: Dictionary = J.score(300.0, Vector2(10, 10), Vector2(11, 11), 40.0, soft)
	eq(bull["accuracy"], 1000)
	eq(bull["points"], 1300)
	var mid: Dictionary = J.score(300.0, Vector2(0, 0), Vector2(6, 0), 40.0, soft)
	eq(mid["accuracy"], 600)
	var far: Dictionary = J.score(300.0, Vector2(0, 0), Vector2(150, 0), 40.0, soft)
	eq(far["accuracy"], 50)
	eq(J.ring_points(500.0), 0)
	var hard: Dictionary = J.score(300.0, Vector2(0, 0), Vector2(1, 0), 40.0, Vector3(0, -30, 0))
	eq(hard["points"], int(round(1300 * 0.25)), "an impact keeps a quarter")


func test_orient_points_the_plank_at_the_ring() -> void:
	for t in [2, 3, 4, 5]:
		var s: Dictionary = P.spec(t, [0, 0, 5.0, 7.0, 8.5, 10.0][t])
		for ring_a in [0.0, 1.0, 2.0, -0.4, -2.6, PI * 0.5]:
			for core_a in [0.3, PI * 0.5, -2.0]:
				var yaw := P.orient(s, ring_a, core_a)
				var pl := P.plank(s, ring_a + yaw)
				var world_b := float(pl["bearing"]) - yaw   # local bearing → world angle
				check(absf(angle_difference(world_b, ring_a)) < 0.01, "%s: the plank points at the ring (%.2f vs %.2f)" % [s["kind"], world_b, ring_a])
				check(absf(angle_difference(PI * 0.5 - yaw, core_a)) <= deg_to_rad(121.0), "%s: the front turns toward the Core" % s["kind"])
		# With the ring well away from the front, the front faces the Core exactly
		var y0 := P.orient(s, PI * 0.5 + PI, PI * 0.5)
		if s["kind"] != "burj":
			check(absf(angle_difference(PI * 0.5 - y0, PI * 0.5)) < 0.01, "%s: faces the Core" % s["kind"])


func test_real_relief_has_tower_and_ring_sites() -> void:
	# The v2 relief (terraced highlands round the Core's plain) must leave flat land
	# for the tower's plaza and the landing ring, clear of the fair and the vehicle pad.
	var F = load("res://scripts/world/funfair/fair_site.gd")
	var G = load("res://scripts/world/garage/garage_site.gd")
	for a in ["0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b", "0xd127839b83cbf537c29b7d268c135f745a0da2e8", "0x2b78b345880807ac9be28c1309ab55d6fa8796de"]:
		var q: Dictionary = Registry.get_territory(a)
		var hf := JuliaHeightfield.compute(DeepField.for_territory(q), a, 129)
		var core := hf.core_height
		var h := func(x: float, z: float) -> float: return hf.height_at(x, z) - core
		var fair: Dictionary = F.find_site(h)
		var garage: Dictionary = G.find_site(h, [[fair["at"], F.RADIUS + 10.0]])
		var others := [[fair["at"], F.RADIUS], [garage["at"], G.RADIUS]]
		var t := P.tower_site(h, others)
		check(t["ok"], "%s: a tower site on land" % q["name"])
		check(float(t["top"]) - float(t["low"]) < 8.0, "%s: plaza flat enough (%.1f m)" % [q["name"], float(t["top"]) - float(t["low"])])
		for o in others:
			check((t["at"] as Vector2).distance_to(o[0]) >= float(o[1]) + P.PLAZA_R, "%s: clear of the fair and the pad" % q["name"])
		var r := P.ring_site(h, t["at"], others)
		check(r["ok"], "%s: a landing ring on land" % q["name"])
		print("     %s: tower %s (steps %.1f m) · ring %s (%.0f m away)" % [q["name"], str(t["at"]), float(t["top"]) - float(t["low"]), str(r["at"]), (r["at"] as Vector2).distance_to(t["at"])])
