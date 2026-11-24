extends TestCase
## The Affection Fair's placement and tier mapping. No network, no scene.


func test_tier_mapping() -> void:
	var F = load("res://scripts/world/funfair/fair_site.gd")
	eq(F.fair_tier(0), 0, "Wild → surveyed lot")
	eq(F.fair_tier(1), 0, "Outpost → surveyed lot")
	eq(F.fair_tier(2), 1, "Settlement → night market")
	eq(F.fair_tier(3), 2, "Town → fairground")
	eq(F.fair_tier(4), 3, "City → grand fair")
	eq(F.fair_tier(5), 3, "Capital → grand fair")


func test_site_is_on_land_and_clear_of_landmarks() -> void:
	var F = load("res://scripts/world/funfair/fair_site.gd")
	# An island: land (0 m) within 150 m of (40, 110), sea (−20 m) elsewhere, gentle relief.
	var island := func(x: float, z: float) -> float:
		var d := Vector2(x, z).distance_to(Vector2(40, 110))
		return (0.6 * sin(x * 0.05) if d < 150.0 else -20.0)
	var s: Dictionary = F.find_site(island)
	check(s["ok"], "a site fully on land is found")
	var at: Vector2 = s["at"]
	check(at.distance_to(Vector2(40, 110)) + F.RADIUS <= 150.0 + 0.01, "the whole footprint is on the island")
	for k in F.KEEP_CLEAR:
		check(at.distance_to(k) >= F.CLEAR_M, "clear of the Core's landmarks")
	check(float(s["top"]) - float(s["low"]) < 2.0, "flat enough")
	# Deterministic
	eq(F.find_site(island)["at"], at)


func test_no_land_gives_best_effort_not_a_fake_site() -> void:
	var F = load("res://scripts/world/funfair/fair_site.gd")
	var s: Dictionary = F.find_site(func(_x: float, _z: float) -> float: return -30.0)
	check(not s["ok"], "no fully-on-land spot is reported as such")
	check(s.has("at"), "still returns the best effort")


func test_real_relief_still_has_fair_sites() -> void:
	# The v2 relief (terraced highlands round the Core's plain) must still leave
	# flat land for the fair: a full on-land site, steps under 5 m, on real territories.
	var F = load("res://scripts/world/funfair/fair_site.gd")
	for a in ["0xd127839b83cbf537c29b7d268c135f745a0da2e8", "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b", Registry.all()[7]["address"]]:
		var q: Dictionary = Registry.get_territory(a)
		var hf := JuliaHeightfield.compute(DeepField.for_territory(q), a, 129)
		var core := hf.core_height
		var s: Dictionary = F.find_site(func(x: float, z: float) -> float: return hf.height_at(x, z) - core)
		check(s["ok"], "%s: a fair site on land" % q["name"])
		check(float(s["top"]) - float(s["low"]) < 5.0, "%s: flat enough (%.1f m)" % [q["name"], float(s["top"]) - float(s["low"])])
