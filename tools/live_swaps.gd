extends SceneTree
## Read-only: the PulseX pools behind the Swap Hall. Nothing is signed.
##   godot --headless --path . -s res://tools/live_swaps.gd [-- --wallet=0x… --qing=0x… --all]
## 1. Verifies the four PulseX addresses (eth_getCode, router.factory(), router.WPLS()).
## 2. For every Swap Hall token (+ the --qing territory's token and asset): the pair on
##    each factory (getPair(WPLS, token)), its reserves and the mid price, at one block.
## 3. Simulates (eth_call from --wallet) a 1,000 PLS buy of each pooled token on its
##    deeper router, and a sell of 1 token where the wallet holds it and has approved.
## --all: also counts which of the 942 territories' QING tokens and assets have a pool.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wallet := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	var qing := ""
	var all := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wallet="):
			wallet = a.substr(9).to_lower()
		elif a.begins_with("--qing="):
			qing = a.substr(7).to_lower()
		elif a == "--all":
			all = true
	var C = load("res://scripts/chain/contracts.gd")
	var PX = load("res://scripts/chain/pulsex.gd")
	var BI = load("res://scripts/chain/bigint.gd")
	var AB = load("res://scripts/chain/abi.gd")
	var chain = root.get_node("Chain")
	var rpc = chain.rpc
	print("-- PulseX addresses --")
	for pair in [["V1 router", C.PULSEX_V1_ROUTER], ["V1 factory", C.PULSEX_V1_FACTORY], ["V2 router", C.PULSEX_V2_ROUTER], ["V2 factory", C.PULSEX_V2_FACTORY]]:
		var code: Dictionary = await rpc.get_code(pair[1])
		var n: int = (String(code.get("result", "0x")).length() - 2) / 2 if code["ok"] else -1
		print("%-10s %s  code %s bytes" % [pair[0], pair[1], str(n) if n >= 0 else "— (read failed)"])
	var tokens: Array = PX.TOKENS.duplicate()
	if qing != "":
		var q: Dictionary = root.get_node("Registry").get_territory(qing)
		var have := {}
		for t in tokens:
			have[t[0]] = true
		if not have.has(qing):
			tokens.append([qing, "%s (this QING)" % q.get("symbol", "QING")])
		if String(q.get("asset", "")) != "" and not have.has(String(q["asset"])):
			tokens.append([String(q["asset"]), "its asset"])
	var board: Dictionary = await PX.read_board(tokens, wallet)
	if not board["ok"]:
		print("board: ", board.get("error", "failed"))
		quit(1)
		return
	print("routers verified live (factory() and WPLS() match): %s · block %d" % [board["routers_ok"], board["block"]])
	print("\n-- pools at block %d (WPLS reserve / token reserve · PLS per token) --" % board["block"])
	var pooled := 0
	for t in board["tokens"]:
		var line: String = "%-14s %s  " % [String(t["name"]).left(14), t["address"]]
		if t["decimals"] < 0:
			line += "decimals() did not read"
		elif t["pools"].is_empty():
			line += "no pool on PulseX"
		else:
			pooled += 1
			var parts: Array = []
			for v in PX.VERSIONS:
				if not t["pools"].has(v):
					continue
				var p: Dictionary = t["pools"][v]
				parts.append("%s%s %s: %s WPLS / %s · %s PLS" % [v, "*" if v == t["best"] else "", String(p["pair"]).left(10),
					PX.fmt(p["wpls"], 18, 2), PX.fmt(p["token"], t["decimals"], 4), PX.fmt(PX.price_wei(p["wpls"], p["token"], t["decimals"]), 18, 4)])
			line += " | ".join(parts)
		if t["balance"] != null and not BI.is_zero(t["balance"]):
			line += "   wallet holds %s" % PX.fmt(t["balance"], maxi(t["decimals"], 0), 4)
		print(line)
	print("%d of %d tokens have a pool (* = the deeper one, used for quotes)" % [pooled, board["tokens"].size()])
	print("wallet %s PLS: %s" % [wallet, PX.fmt(board["pls"], 18, 2) if board["pls"] != null else "—"])
	# Simulations from the wallet
	var blk: Dictionary = await rpc.get_block("latest")
	var deadline: int = String(blk.get("result", {}).get("timestamp", "0x0")).hex_to_int() + PX.DEADLINE_S
	print("\n-- simulations from %s (eth_call, nothing signed) --" % wallet)
	var thousand = BI.from_decimal("1000000000000000000000")
	for t in board["tokens"]:
		if t["best"] == "" or t["decimals"] < 0:
			continue
		var router: String = PX.router_of(t["best"])
		var path: Array = PX.path_for("buy", "", t["address"])
		var q: Dictionary = await rpc.eth_call(router, PX.amounts_out_call(thousand, path))
		var amts: Array = PX.decode_amounts(q.get("result", "")) if q["ok"] else []
		var p: Dictionary = t["pools"][t["best"]]
		var local: Array = PX.amounts_out(thousand, [[p["wpls"], p["token"]]])
		if amts.size() < 2:
			print("%-14s quote failed: %s" % [String(t["name"]).left(14), q.get("revert", q.get("error", {})).get("message", "?")])
			continue
		var minimum = PX.min_out(amts[1], PX.DEFAULT_SLIPPAGE_BPS)
		var data: String = PX.swap_call("buy", thousand, minimum, path, wallet, deadline)
		var sim: Dictionary = await rpc.eth_call(router, data, wallet, "latest", "0x" + BI.to_hex(thousand))
		var fot := ""
		if not sim["ok"] and PX.wants_fot(String(sim.get("revert", {}).get("message", ""))):
			sim = await rpc.eth_call(router, PX.swap_call("buy", thousand, minimum, path, wallet, deadline, true), wallet, "latest", "0x" + BI.to_hex(thousand))
			fot = " (fee-on-transfer variant)"
		print("%-14s buy 1,000 PLS → %s (router) / %s (local maths %s) · impact %.2f%% · %s%s" % [String(t["name"]).left(14),
			PX.fmt(amts[1], t["decimals"], 6), PX.fmt(local[1], t["decimals"], 6), "matches" if BI.cmp(local[1], amts[1]) == 0 else "DIFFERS",
			PX.impact_bps(thousand, p["wpls"], p["token"]) / 100.0,
			"simulation OK" if sim["ok"] else "simulation reverts: " + PX.explain(String(sim.get("revert", {}).get("message", sim.get("error", {}).get("message", "?")))), fot])
		# A sell of up to 1 token, if the wallet holds some
		if t["balance"] != null and not BI.is_zero(t["balance"]):
			var one = PX.pow10(t["decimals"])
			var amt = one if BI.cmp(t["balance"], one) >= 0 else t["balance"]
			var al: Dictionary = await rpc.call_decoded(t["address"], "allowance(address,address)", [wallet, router], ["uint256"])
			var allowance = BI.coerce(al["values"][0]) if al["ok"] else null
			var sp: Array = PX.path_for("sell", t["address"], "")
			var sq: Dictionary = await rpc.eth_call(router, PX.amounts_out_call(amt, sp))
			var sa: Array = PX.decode_amounts(sq.get("result", "")) if sq["ok"] else []
			if sa.size() < 2:
				continue
			var s2: Dictionary = await rpc.eth_call(router, PX.swap_call("sell", amt, PX.min_out(sa[1], 100), sp, wallet, deadline), wallet)
			print("%-14s sell %s → %s PLS · allowance to the %s router %s · %s" % ["", PX.fmt(amt, t["decimals"], 6), PX.fmt(sa[1], 18, 4), t["best"],
				PX.fmt(allowance, t["decimals"], 4) if allowance != null else "—",
				"simulation OK" if s2["ok"] else "simulation reverts: " + PX.explain(String(s2.get("revert", {}).get("message", "?"))) + " → approve first"])
	if all:
		var terr: Array = root.get_node("Registry").all()
		var calls: Array = []
		for q in terr:
			for a in [String(q["address"]), String(q.get("asset", ""))]:
				for v in PX.VERSIONS:
					calls.append(load("res://scripts/chain/multicall.gd").make_call(PX.factory_of(v), "getPair(address,address)",
						[C.WPLS, a if a != "" else "0x0000000000000000000000000000000000000000"]))
		var r: Array = await chain.multicall.run(calls, "", board["block"])
		var qn := 0
		var an := 0
		var names: Array = []
		for i in terr.size():
			var has_q := false
			var has_a := false
			for k in 4:
				var v = load("res://scripts/chain/multicall.gd").value(r[i * 4 + k], ["address"])
				if v != null and String(v[0]).trim_prefix("0x").replace("0", "") != "":
					if k < 2:
						has_q = true
					else:
						has_a = true
			if has_q:
				qn += 1
				names.append(String(terr[i].get("symbol", "")))
			if has_a:
				an += 1
		print("\n-- all %d territories at block %d --\nQING tokens with a WPLS pair: %d (%s)\nassets with a WPLS pair: %d" % [terr.size(), board["block"], qn, ", ".join(names), an])
	quit(0)
