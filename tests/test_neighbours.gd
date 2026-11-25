extends TestCase
## Neighbouring QINGs from raw HECKE coordinates (int256 words, BigInt only),
## the border geometry, and the BorderRing built from them. No network.

const RATKING := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
## ~2^238: coordinates are this big on chain; a float would lose the low digits.
const BIG := "0x3fffffffffffffffffffffffffffffffffffffffffffffffffffffffff01"


## A record at (lat, lon) = (BIG + dlat, BIG·k + dlon) as raw words.
func _rec(addr: String, dlat: int, dlon: int, lat_base: String = BIG, lon_base: String = "-" + BIG) -> Dictionary:
	return {"address": addr, "name": addr, "lat_word": _word(lat_base, dlat), "lon_word": _word(lon_base, dlon)}


func _word(base: String, d: int) -> String:
	var b := BigInt.from_signed(base)
	var neg: bool = b[0]
	var mag: PackedInt64Array = b[1]
	# base + d with signs (|d| is far smaller than |base| here)
	if (d >= 0) != neg:
		mag = BigInt.add(mag, BigInt.from_int(absi(d)))
	else:
		mag = BigInt.sub(mag, BigInt.from_int(absi(d)))
	return BigInt.signed_to_word(("-0x" if neg else "0x") + BigInt.to_hex(mag))


func test_signed_sub() -> void:
	var r := Neighbours.signed_sub(false, BigInt.from_int(5), false, BigInt.from_int(3))
	eq([r[0], BigInt.to_int(r[1])], [true, 2], "3 − 5 = −2")
	r = Neighbours.signed_sub(true, BigInt.from_int(5), false, BigInt.from_int(3))
	eq([r[0], BigInt.to_int(r[1])], [false, 8], "3 − (−5) = 8")
	r = Neighbours.signed_sub(false, BigInt.from_int(5), true, BigInt.from_int(3))
	eq([r[0], BigInt.to_int(r[1])], [true, 8], "−3 − 5 = −8")
	r = Neighbours.signed_sub(true, BigInt.from_int(5), true, BigInt.from_int(9))
	eq([r[0], BigInt.to_int(r[1])], [true, 4], "−9 − (−5) = −4")


func test_layout_from_known_coordinates() -> void:
	var me := _rec("0x00000000000000000000000000000000000000c0", 0, 0)
	var all := [me,
		_rec("0x00000000000000000000000000000000000000a1", 100, 10),   # north, far
		_rec("0x00000000000000000000000000000000000000a2", 50, -50),   # north, a tie on |Δ| goes to N/S, nearer
		_rec("0x00000000000000000000000000000000000000a3", -900, 3),   # south
		_rec("0x00000000000000000000000000000000000000a4", 3, 7),      # east
		_rec("0x00000000000000000000000000000000000000a5", -2, 7),     # east, same reach, smaller offset: wins
		_rec("0x00000000000000000000000000000000000000a6", 0, 0),      # same cell: no side
		{"address": "0x00000000000000000000000000000000000000a7", "name": "no words"},  # unknown coords: skipped
	]
	Neighbours._coords.clear()
	var n := Neighbours.find(me, all)
	eq(n.get("n", {}).get("address", ""), "0x00000000000000000000000000000000000000a2", "north")
	eq(n.get("s", {}).get("address", ""), "0x00000000000000000000000000000000000000a3", "south")
	eq(n.get("e", {}).get("address", ""), "0x00000000000000000000000000000000000000a5", "east")
	check(not n.has("w"), "nothing lies west: the edge of the map, not a fake neighbour")
	eq(Neighbours.short(n["s"]["dlat"]), "−900", "Δlat exact")
	eq(BigInt.to_int(n["e"]["perp"]), 2)


func test_huge_offsets_stay_exact() -> void:
	# Two candidates north whose distances differ by 1 raw unit at ~2^238: only exact
	# integers tell them apart.
	var me := _rec("0x00000000000000000000000000000000000000c0", 0, 0, "-" + BIG, BIG)
	var far := _rec("0x00000000000000000000000000000000000000b2", 0, 0, BIG, BIG)
	var near_ := _rec("0x00000000000000000000000000000000000000b1", -1, 0, BIG, BIG)
	Neighbours._coords.clear()
	var n := Neighbours.find(me, [me, far, near_])
	eq(n["n"]["address"], "0x00000000000000000000000000000000000000b1", "1 unit nearer at 2^239 wins")


func test_real_registry_neighbours() -> void:
	var q: Dictionary = Registry.get_territory(RATKING)
	check(not q.is_empty(), "RatKing in the snapshot")
	var t0 := Time.get_ticks_msec()
	var n := Neighbours.find(q, Registry.all())
	var ms := Time.get_ticks_msec() - t0
	check(ms < 3000, "fast enough to run at load (%d ms)" % ms)
	check(n.size() >= 2, "an interior QING has neighbours (%d)" % n.size())
	for side in n:
		var e: Dictionary = n[side]
		check(Registry.has_territory(e["address"]), "a real QING, from the registry")
		check(e["address"] != RATKING, "not itself")
		eq(Neighbours.relate(q, Registry.get_territory(e["address"]))["side"], side, "in its quarter")
	eq(Neighbours.find(q, Registry.all()).keys(), n.keys(), "deterministic")


func test_border_geometry() -> void:
	# Written against the half-edge H (362 m since territories grew from 512 to 724 m).
	var H := JuliaHeightfield.SIZE_M * 0.5
	var b := Neighbours.nearest_border(10.0, -(H - 6.0))
	eq(b["side"], "n")
	near(b["inside_m"], 6.0, 1e-6)
	eq(Neighbours.nearest_border(H - 3.0, 0.0)["side"], "e")
	eq(Neighbours.arrival("n", 10.0), Vector2(10.0, H - 6.0), "out north → in at the neighbour's south edge")
	eq(Neighbours.arrival("w", -40.0), Vector2(H - 6.0, -40.0), "out west → in at its east edge")
	eq(Neighbours.arrival("e", 999.0), Vector2(-(H - 6.0), H - 6.0), "clamped along the edge")
	eq(Neighbours.offset("e"), Vector3(2.0 * H, 0, 0))
	eq(Neighbours.offset("n"), Vector3(0, 0, -2.0 * H))
	eq(Neighbours.offset("e"), Vector3(724, 0, 0), "the territory edge is 724 m")


func test_border_ring_builds_from_territory_state() -> void:
	var q: Dictionary = Registry.get_territory(RATKING)
	var ring := BorderRing.new()
	Engine.get_main_loop().root.add_child(ring)
	ring.setup(q, null, null, null, false)
	var found := Neighbours.find(q, Registry.all())
	for side in Neighbours.SIDES:
		check(ring.get_node_or_null("Field_" + side) != null, "a field on the %s border" % side)
		var label: Label3D = ring.get_node("Name_" + side)
		if found.has(side):
			eq(label.text, BorderRing.qname(Registry.get_territory(found[side]["address"])).to_upper(), "its real name")
		else:
			check(label.text.begins_with("EDGE OF THE MAP"), "an empty side says so")
	if ring._thread:
		ring._thread.wait_to_finish()
		ring._thread = null
	ring._attach_grounds(4)
	for side in Neighbours.SIDES:
		eq(ring.ground_ready(side), found.has(side), "ground drawn only where a QING lies (%s)" % side)
	if found.has("n"):
		var g: DeepFieldTerrain = ring.get_node("Neighbour_n")
		eq(g.heightfield.n, BorderRing.SAMPLES, "low LOD")
		eq(g.position, Neighbours.offset("n"))
		check(g.get_node_or_null("GroundBody") == null, "no collider beyond the field")
		for i in g.heightfield.n:
			near(g.heightfield.heights[(g.heightfield.n - 1) * g.heightfield.n + i], 0.0, 1e-6, "it meets us level at 0 m")
	ring.queue_free()
