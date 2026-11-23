extends TestCase
## Phase 6 logic: WORLD detection by bytecode, the CREATE table, the centre
## cell's exact call, the range scale. No network.


func test_classify_by_push4() -> void:
	var W = load("res://scripts/state/world_watch.gd")
	var code := "0x6080604052" + "63" + "99790fb6" + "1461" + "63" + "ce29ab3c" + "57"
	eq(W.classify(code), "WORLD")
	eq(W.classify("0x6080" + "63e24893a2" + "636e69adcf"), "WAR")
	eq(W.classify("0x6080" + "6399790fb6"), "", "one selector is not enough")
	eq(W.classify("0x"), "")
	# The selector bytes without the PUSH4 opcode do not count.
	eq(W.classify("0x99790fb6ce29ab3c"), "")


func test_create_table_reproduces_known_contracts() -> void:
	var d = load_json("res://assets/data/deployer_creates.json")
	eq(String(d["deployer"]), Contracts.DYSNOMIA_DEPLOYER)
	check(int(d["from"]) <= Contracts.DEPLOYER_NONCE_BASELINE and int(d["to"]) > Contracts.DEPLOYER_NONCE_BASELINE + 100)
	eq(String(d["creates"]["712"]), "0x61df5ea307da4ac2549840f7ee8b16f14596d0b7")


func test_world_not_live_by_default() -> void:
	var w = load("res://scripts/state/world_watch.gd").new()
	check(not w.is_live())
	eq(w.address_of("WORLD"), "")
	w.found = {"WORLD": {"address": "0x1", "wired": false}}
	eq(w.address_of("WORLD"), "", "unwired WORLD-shaped code is never used")
	w.free()


func test_code_call_centre_cell() -> void:
	var q := Registry.get_territory("0xd127839b83cbf537c29b7d268c135f745a0da2e8")
	var cc := CoreActions.code_call(q)
	var data: String = cc["data"]
	check(data.begins_with("0x99790fb6"), "Code(int256,int256,address)")
	eq(data.substr(10, 64), String(q["lon_word"]), "word0 first, as the site sends it")
	eq(data.substr(74, 64), String(q["lat_word"]))
	eq(data.substr(138 + 24, 40), "d127839b83cbf537c29b7d268c135f745a0da2e8")
	check(String(cc["text"]).begins_with("WORLD.Code(-"), "negative words decode as signed")


func test_range_scale() -> void:
	near(WorldLattice.range_half(PackedInt64Array()), WorldLattice.CELL * 0.5, 0.001)
	check(WorldLattice.range_half(BigInt.from_decimal("1958672891831255168")) > WorldLattice.range_half(BigInt.from_decimal("74")))
	near(WorldLattice.range_half(BigInt.from_decimal("1" + "0".repeat(70))), WorldLattice.EXTENT, 0.001)


func test_world_zone() -> void:
	var t: GDScript = load("res://scripts/world/territory_v2.gd")
	eq(t.zone_at(Vector3(0, 0, -11.5), Vector3(-26, 0, 18)), "world")
