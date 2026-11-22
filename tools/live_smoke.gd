extends SceneTree
## Read-only live checks against PulseChain. Sends no transactions.
##   godot --headless --path . -s res://tools/live_smoke.gd
## Exit code 0 = every check passed.

var _failed := 0


func _ok(cond: bool, label: String, detail := "") -> void:
	print("%s %s %s" % ["ok  " if cond else "FAIL", label, detail])
	if not cond:
		_failed += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rpc := Rpc.new()
	root.add_child(rpc)
	var head := await rpc.block_number()
	_ok(head["ok"], "eth_blockNumber", str(head.get("block", head)))
	if not head["ok"]:
		quit(1)
		return
	var head_block: int = head["block"]

	# 1. Every territory from MAP's NewQing logs.
	var scan := await LogScanner.new(rpc).scan(Contracts.MAP, [Contracts.TOPIC_NEW_QING], Contracts.MAP_FIRST_BLOCK, head_block)
	_ok(scan["ok"] and scan["logs"].size() >= 942, "NewQing logs", "%d territories" % scan["logs"].size())

	# 2. Multicall: Entropy + CoverCharge for the first snapshot territories vs the snapshot.
	var snap = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/territories.json"))
	var sample: Array = snap["territories"].slice(0, 25)
	var calls: Array = []
	for q in sample:
		calls.append(Multicall.make_call(q["address"], "Entropy()"))
		calls.append(Multicall.make_call(q["address"], "CoverCharge()"))
	var res := await Multicall.new(rpc).run(calls)
	var matched := 0
	for i in sample.size():
		var e = Multicall.value(res[2 * i], ["uint256"])
		var c = Multicall.value(res[2 * i + 1], ["uint256"])
		if e != null and c != null \
				and BigInt.to_decimal(BigInt.from_hex(e[0])) == sample[i]["entropy"] \
				and BigInt.to_decimal(BigInt.from_hex(c[0])) == sample[i]["cover_charge"]:
			matched += 1
	_ok(matched == sample.size(), "Multicall Entropy+CoverCharge", "%d/%d match snapshot" % [matched, sample.size()])

	# 3. Compliment of the first territory projects to the snapshot's lat/lon.
	var first: Dictionary = sample[0]
	var comp := await rpc.call_decoded(Contracts.HECKE, "Compliment(uint256)", [first["waat"]], ["uint256", "uint256"])
	if comp["ok"]:
		var p := Coords.project(comp["values"][0], comp["values"][1])
		_ok(absf(p[0] - float(first["lat"])) < 1e-6 and absf(p[1] - float(first["lon"])) < 1e-6,
			"Compliment projection", "%s → %.6f, %.6f" % [first["name"], p[0], p[1]])
	else:
		_ok(false, "Compliment", str(comp))

	# 4. A tx.origin read from a wallet that never onboarded reverts NotStarted (decoded).
	var beat := await rpc.eth_call(Contracts.META, Abi.encode_call("Beat(uint256)", [Contracts.PHOBOS_WAAT]),
		"0x000000000000000000000000000000000000dead")
	_ok(not beat["ok"] and beat.get("kind") == "revert", "Beat from a stranger reverts",
		String(beat.get("revert", {}).get("message", str(beat))))

	# 5. WORLD still latent: deployer nonce.
	var nonce := await rpc.get_transaction_count(Contracts.DYSNOMIA_DEPLOYER)
	var n := String(nonce.get("result", "0x0")).hex_to_int()
	print("info deployer nonce %d (baseline %d)%s" % [n, Contracts.DEPLOYER_NONCE_BASELINE,
		"  ← CHANGED: check whether WORLD deployed" if n != Contracts.DEPLOYER_NONCE_BASELINE else ""])
	_ok(nonce["ok"], "deployer nonce read")

	print("\n%d failed; rpc stats %s" % [_failed, rpc.stats])
	quit(1 if _failed > 0 else 0)
