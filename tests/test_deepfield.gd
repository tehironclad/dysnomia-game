extends TestCase
## The GDScript Deep Field port must match the site's lib/deep-field.js
## (tests/golden/deepfield.json, produced by tools/golden/deepfield.js).

const TOL := 1e-9


func _cmp_params(got: Dictionary, want: Dictionary, label: String) -> void:
	for k in ["family", "tier", "style"]:
		eq(got[k], want[k], "%s %s" % [label, k])
	for k in ["arms", "turn", "power"]:
		eq(got[k], int(want[k]), "%s %s" % [label, k])
	for k in ["depth", "rotation", "hue", "extent", "frame"]:
		near(got[k], float(want[k]), TOL, "%s %s" % [label, k])
	for k in ["c", "color", "color2"]:
		for i in want[k].size():
			near(got[k][i], float(want[k][i]), TOL, "%s %s[%d]" % [label, k, i])


func test_mix_known_values() -> void:
	eq(DeepField.imul32(0xFFFFFFFF, 0xFFFFFFFF), 1)
	eq(DeepField.imul32(123456789, 2246822507), (123456789 * 2246822507) & 0xFFFFFFFF)


func test_params_all_territories() -> void:
	var g = load_json("res://tests/golden/deepfield.json")
	if g == null:
		return
	var bad_before := failures.size()
	for t in g["territories"]:
		_cmp_params(DeepField.params(String(t["number"]), t["address"]), t["p"], t["address"])
		if failures.size() - bad_before > 20:
			break
	check(g["territories"].size() >= 942, "golden territories %d" % g["territories"].size())


func test_params_identities() -> void:
	var g = load_json("res://tests/golden/deepfield.json")
	if g == null:
		return
	for t in g["identities"]:
		eq(DeepField.aura(t["address"]), t["aura"], "aura " + t["address"])
		_cmp_params(DeepField.for_identity(t["address"]), t["p"], "identity " + t["address"])


func test_dive_points() -> void:
	var g = load_json("res://tests/golden/deepfield.json")
	if g == null:
		return
	for d in g["dives"]:
		var p := DeepField.params(String(d["number"]), d["address"])
		var got = DeepField.dive_point(p, d["address"])
		eq(got["period"], int(d["period"]), "period " + d["address"])
		near(got["mag"], float(d["mag"]), 1e-6, "mag " + d["address"])
		near(got["arg"], float(d["arg"]), 1e-6, "arg " + d["address"])
		near(got["z"][0], float(d["z"][0]), 1e-6, "z.x " + d["address"])


func test_cpu_render_matches_site() -> void:
	var g = load_json("res://tests/golden/deepfield.json")
	if g == null:
		return
	for r in g["renders"]:
		var p := DeepField.params(String(r["number"]), r["address"])
		var got := Julia.render_rgb(p, int(r["w"]), int(r["h"]))
		var want: PackedByteArray = String(r["rgb"]).hex_decode()
		eq(got.size(), want.size(), "size")
		var worst := 0
		var off := 0
		for i in want.size():
			var dlt := absi(got[i] - want[i])
			worst = maxi(worst, dlt)
			if dlt > 1:
				off += 1
		# Floating-point libm differences may flip a pixel at a filament edge.
		check(worst <= 1 or off <= want.size() / 100, "%s (%s): %d bytes differ by >1, worst %d" % [r["address"], r["style"], off, worst])


func test_boundary_point_is_on_the_edge() -> void:
	var g = load_json("res://tests/golden/deepfield.json")
	for t in g["territories"].slice(0, 40):
		var p := DeepField.params(String(t["number"]), t["address"])
		var b := DeepField.boundary_point(p, 1.0)
		var inside_a: bool = JuliaHeightfield.probe(p, b[0] * 0.995, b[1] * 0.995, 96)[0]
		var inside_b: bool = JuliaHeightfield.probe(p, b[0] * 1.005, b[1] * 1.005, 96)[0]
		check(inside_a or not inside_b, "boundary straddles the set for %s" % t["address"])
