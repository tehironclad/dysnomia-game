extends TestCase
## Roads between a territory's places (TerritoryRoads): pure, deterministic,
## reaching every place's rim and every gate, keeping out of the Core's cluster.

const R := preload("res://scripts/world/roads/territory_roads.gd")


func _land(x: float, z: float) -> float:
	# A plateau with a steep ridge across the east: roads should go round, not over.
	var ridge := 30.0 if absf(x - 150.0) < 12.0 and z > -150.0 else 0.0
	return 22.0 + ridge


func test_roads_reach_places_and_gates() -> void:
	var places := [{"name": "fair", "at": Vector2(-120, 60), "r": 42.0},
		{"name": "tower", "at": Vector2(60, -180), "r": 30.0},
		{"name": "ring", "at": Vector2(-60, -250), "r": 14.0, "from": Vector2(60, -180)}]
	var gates := [Vector2(0, -362), Vector2(362, 0)]
	var lines := R.plan(_land, places, gates)
	eq(lines.size(), 2 + places.size() + gates.size(), "ring, avenue, one road per place and gate")
	eq(str(R.plan(_land, places, gates)), str(lines), "deterministic")
	for pl in places:
		check(R.distance_to_roads(lines, pl["at"]) <= float(pl["r"]) + 0.01, "%s: a road reaches its rim" % pl["name"])
	for g in gates:
		check(R.distance_to_roads(lines, g) < 1.0, "a road reaches the gate at %s" % str(g))
	# Routed roads (not the ring/avenue) never cross the Core's cluster or the ridge top
	for i in range(2, lines.size()):
		var l: PackedVector2Array = lines[i]
		for k in range(1, l.size() - 1):
			check(l[k].length() > R.CORE_KEEP - R.CELL_M, "road %d keeps out of the Core" % i)
			check(not (absf(l[k].x - 150.0) < 6.0 and l[k].y > -140.0), "road %d goes round the ridge" % i)


func test_field_marks_roads_and_clears_terraces() -> void:
	var places := [{"name": "pad", "at": Vector2(0, 120), "r": 17.0}]
	var lines := [PackedVector2Array([Vector2(-200, 120), Vector2(200, 120)])]
	var f := R.rasterize(lines, places)
	eq(f.size(), R.TEX * R.TEX)
	var px := func(x: float, z: float) -> int:
		var t := JuliaHeightfield.SIZE_M / R.TEX
		return f[int((z + JuliaHeightfield.SIZE_M * 0.5) / t) * R.TEX + int((x + JuliaHeightfield.SIZE_M * 0.5) / t)]
	check(px.call(-150.0, 120.0) < 25, "on the road (within a texel)")
	eq(px.call(-150.0, 160.0), 255, "far from it")
	eq(px.call(0.0, 120.0), 255, "the pad's terrace stays clear")
	for s in R.lamp_spots(lines, places):
		check((s[0] as Vector2).distance_to(Vector2(0, 120)) > 17.0, "no lamp on the pad")
