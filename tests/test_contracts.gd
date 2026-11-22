extends TestCase
## Checks contracts.gd against keccak-256 goldens (tools/golden/gen.js).


func test_selectors_match_keccak() -> void:
	var g = load_json("res://tests/golden/selectors.json")
	if g == null:
		return
	var sels: Dictionary = g["selectors"]
	for sig in Contracts.SELECTORS:
		check(sels.has(sig), "golden missing %s (add it to tools/golden/gen.js)" % sig)
		if sels.has(sig):
			eq(Contracts.SELECTORS[sig], sels[sig], sig)


func test_topics_match_keccak() -> void:
	var g = load_json("res://tests/golden/selectors.json")
	if g == null:
		return
	for sig in Contracts.TOPICS:
		eq(Contracts.TOPICS[sig], g["topics"].get(sig, ""), sig)


func test_error_selectors_match_keccak() -> void:
	var g = load_json("res://tests/golden/selectors.json")
	if g == null:
		return
	var by_name := {}
	for sig in g["selectors"]:
		by_name[g["selectors"][sig]] = sig
	for sel in Contracts.ERRORS:
		var spec: Array = Contracts.ERRORS[sel]
		var sig: String = "%s(%s)" % [spec[0], ",".join(PackedStringArray(spec[1]))]
		eq(by_name.get(sel, ""), sig, "error " + sel)


func test_addresses_are_lowercase_and_valid() -> void:
	var consts: Dictionary = Contracts.new().get_script().get_script_constant_map()
	var n := 0
	for k in consts:
		var v = consts[k]
		if v is String and String(v).begins_with("0x") and String(v).length() == 42:
			eq(v, String(v).to_lower(), k)
			n += 1
	check(n >= 30, "found %d addresses" % n)


func test_world_not_deployed() -> void:
	check(not Contracts.is_world_deployed(), "WORLD must stay empty until verified on chain")
	for k in Contracts.WORLD_ADDRESSES:
		eq(Contracts.WORLD_ADDRESSES[k], "", k)


func test_arg_types() -> void:
	eq(Contracts.arg_types("Start(address,string,string)"), ["address", "string", "string"])
	eq(Contracts.arg_types("Pi()"), [])
	eq(Contracts.arg_types("aggregate3((address,bool,bytes)[])"), ["(address,bool,bytes)[]"])
