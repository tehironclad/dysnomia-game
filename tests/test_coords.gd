extends TestCase
## Projection of raw HECKE.Compliment words must match the site's registry.


func test_projection_matches_site_registry() -> void:
	var vecs = load_json("res://tests/golden/projection.json")
	if vecs == null:
		return
	for v in vecs:
		var p := Coords.project(v["lon_word"], v["lat_word"])
		near(p[0], float(v["lat"]), 1e-6, "lat " + v["address"])
		near(p[1], float(v["lon"]), 1e-6, "lon " + v["address"])
	check(vecs.size() >= 250, "vectors: %d" % vecs.size())


func test_snapshot_shape() -> void:
	var reg = load_json("res://assets/data/territories.json")
	if reg == null:
		return
	check(int(reg["count"]) == reg["territories"].size())
	check(int(reg["snapshot_block"]) >= 27745387)
	var seen := {}
	for q in reg["territories"]:
		var a: String = q["address"]
		check(a == a.to_lower() and a.length() == 42, "address " + a)
		check(not seen.has(a), "duplicate " + a)
		seen[a] = true
		check(BigInt.from_decimal(q["entropy"]).size() > 0, "entropy " + a)
