extends TestCase
## The ground must be a pure function of the territory's numbers.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
## Pinned at n=33. If the mapping changes on purpose, bump
## JuliaHeightfield.VERSION (invalidates caches) and update this.
const PINNED := {"0xd127839b83cbf537c29b7d268c135f745a0da2e8": 4414673690696439422}


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
