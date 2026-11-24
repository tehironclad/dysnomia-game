extends TestCase
## The ground must be a pure function of the territory's numbers.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
## Pinned at n=33. If the mapping changes on purpose, bump
## JuliaHeightfield.VERSION (invalidates caches) and update this.
## v3 (2026-11-24): SIZE_M 512 → 724 m. The chain → shape mapping (Deep Field
## params, relief_params, the Julia frame) is unchanged; the frame is drawn over
## the larger square, so the same samples land on different metres.
const PINNED := {"0xd127839b83cbf537c29b7d268c135f745a0da2e8": 3309458385701477657}


func _q(addr: String) -> Dictionary:
	return Registry.get_territory(addr)


func test_deterministic() -> void:
	var q := _q(ILLINOIS)
	var p := DeepField.for_territory(q)
	var a := JuliaHeightfield.compute(p, ILLINOIS, 33)
	var b := JuliaHeightfield.compute(p, ILLINOIS, 33)
	eq(a.fingerprint(), b.fingerprint(), "same input, same ground")
	eq(a.heights.size(), 33 * 33)


func test_pinned_fingerprint() -> void:
	var a := JuliaHeightfield.compute(DeepField.for_territory(_q(ILLINOIS)), ILLINOIS, 33)
	if PINNED[ILLINOIS] == 0:
		fail("pin me: fingerprint = %d" % a.fingerprint())
		return
	eq(a.fingerprint(), PINNED[ILLINOIS], "mapping changed without a VERSION bump?")


func test_core_is_flat_and_on_the_plateau() -> void:
	var hf := JuliaHeightfield.compute(DeepField.for_territory(_q(ILLINOIS)), ILLINOIS, 65)
	near(hf.height_at(0.0, 0.0), hf.core_height, 1e-4, "centre")
	near(hf.height_at(10.0, -12.0), hf.core_height, 1e-4, "inside the core disc")
	check(hf.core_height > JuliaHeightfield.PLATEAU_M * 0.9, "core sits on the plateau: %f" % hf.core_height)


func test_different_territories_differ() -> void:
	var all: Array = Registry.all()
	var a = all[0]
	var b = all[1]
	var ha := JuliaHeightfield.compute(DeepField.for_territory(a), a["address"], 33)
	var hb := JuliaHeightfield.compute(DeepField.for_territory(b), b["address"], 33)
	check(ha.fingerprint() != hb.fingerprint(), "two territories, two grounds")


func test_cache_roundtrip() -> void:
	var q := _q(ILLINOIS)
	var path := JuliaHeightfield.cache_path(ILLINOIS, 33)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var fresh := JuliaHeightfield.for_territory(q, 33)
	check(FileAccess.file_exists(path), "cached to disk")
	var cached := JuliaHeightfield.for_territory(q, 33)
	eq(cached.fingerprint(), fresh.fingerprint(), "cache returns identical heights")


# --- Relief v2: landforms from the territory's own numbers ---------------------------

func test_relief_params_are_pure_and_in_range() -> void:
	var all: Array = Registry.all()
	for i in range(0, all.size(), maxi(1, all.size() / 60)):
		var a := JuliaHeightfield.relief_params(DeepField.for_territory(all[i]))
		eq(a, JuliaHeightfield.relief_params(DeepField.for_territory(all[i])), "same numbers, same landforms")
		var r := float(a["relief"])
		check(r >= 10.0 and r <= 27.0, "relief %f m" % r)
		check(float(a["terrace"]) >= 2.0 and float(a["terrace"]) <= 3.5, "terrace step")
		check(float(a["crater"]) >= 0.08 and float(a["crater"]) <= 0.2, "crater reach")
		check(int(a["rays"]) >= 3, "canyon rays")
		check(float(a["canyon"]) >= 5.0 and float(a["canyon"]) <= 10.0, "canyon depth")


func test_terraces_have_flat_treads() -> void:
	near(JuliaHeightfield.terrace(2.2, 2.0), 2.0, 1e-9, "on a tread")
	near(JuliaHeightfield.terrace(3.2, 2.0), 2.0, 1e-9, "still the same tread")
	near(JuliaHeightfield.terrace(4.0, 2.0), 4.0, 1e-9, "next step")
	var last := -1.0
	for i in 200:
		var h := JuliaHeightfield.terrace(i * 0.05, 2.5)
		check(h >= last - 1e-9, "never goes down")
		last = h


func test_ground_has_real_relief_not_flat() -> void:
	# Several territories: land rises well above the Core's plain, canyons stay
	# bounded, the Core stays on the plateau, and every border sits at 0 m.
	var all: Array = Registry.all()
	for a in [ILLINOIS, all[1]["address"], all[7]["address"], all[200]["address"]]:
		var q := _q(a)
		var hf := JuliaHeightfield.compute(DeepField.for_territory(q), a, 65)
		var lo := INF
		var hi := -INF
		for h in hf.heights:
			lo = minf(lo, h)
			hi = maxf(hi, h)
		check(hi - hf.core_height >= 4.0, "%s: highlands rise %.1f m over the Core" % [q["name"], hi - hf.core_height])
		check(hi <= JuliaHeightfield.PLATEAU_M + 40.0, "%s: bounded (%.1f m)" % [q["name"], hi])
		check(lo >= -12.0, "%s: canyons bounded (%.1f m)" % [q["name"], lo])
		near(hf.core_height, JuliaHeightfield.PLATEAU_M, 0.5, "the Core sits on the plateau's plain")
		for i in hf.n:
			near(hf.heights[i], 0.0, 1e-6, "north border at 0 m")
			near(hf.heights[(hf.n - 1) * hf.n + i], 0.0, 1e-6, "south border at 0 m")
			near(hf.heights[i * hf.n], 0.0, 1e-6, "west border at 0 m")
			near(hf.heights[i * hf.n + hf.n - 1], 0.0, 1e-6, "east border at 0 m")


func test_external_angle_matches_arg_far_away() -> void:
	# Far from the set Böttcher's coordinate is ≈ z, so the angle is ≈ arg z.
	var p := DeepField.for_territory(_q(ILLINOIS))
	for k in 8:
		var a := -PI + 0.3 + k * 0.75
		var g := JuliaHeightfield.external_angle(p, 40.0 * cos(a), 40.0 * sin(a), 3)
		near(angle_difference(g, a), 0.0, 0.01, "angle %f" % a)
