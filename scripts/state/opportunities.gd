class_name Opportunities
extends RefCounted
## Things worth doing right now, computed from the chain at one block. Every
## number is exact arithmetic on chain reads:
##
## - Ω at a QING = ⌊Fornax(QING) / Entropy(QING)⌋: the Hypobar every Su adds
##   there, the same for everyone. Where Ω = 0 a Su adds no Hypobar at all.
##   (Measured 2026-11-23: 27 of 942 territories have Ω ≥ 1.)
## - The board at a QING: YUE.Bar(QING) over known players (a floor).
## - Su to pass a player = ⌈(their Hypobar − yours + 1) / Ω⌉, a snapshot at
##   the block: they can react too.
## - Su to the next development tier = ⌈(threshold − total) / Ω⌉.
## Gas per Su is quoted from eth_estimateGas × eth_gasPrice when available.
##
## Sections: hot (by Ω), reach (you can take a rank in ≤ REACH_MAX Su),
## crowns (you lead; how many Su a rival needs), build (Su to the next tier).

const REACH_MAX := 25

var block := -1
var ok := false
var error := ""
var hot: Array = []     # [{address, name, omega, rank, mine, leader, su_top, su_next}]
var reach: Array = []
var crowns: Array = []  # [{address, name, omega, margin_su, runner_up}]
var build: Array = []   # [{address, name, omega, tier, next_tier, su}]
var gas_per_su := -1    # gas units, -1 = unknown
var gas_price := PackedInt64Array()


## Ceil division on BigInts: ⌈a / b⌉ for b > 0.
static func ceil_div(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	if BigInt.is_zero(a):
		return PackedInt64Array()
	return BigInt.div(BigInt.sub(BigInt.add(a, b), BigInt.from_int(1)), b)


## Su needed to pass `target` from `mine` at Ω (0 if already above).
static func su_to_pass(target: PackedInt64Array, mine: PackedInt64Array, omega: PackedInt64Array) -> PackedInt64Array:
	if BigInt.cmp(mine, target) > 0:
		return PackedInt64Array()
	return ceil_div(BigInt.add(BigInt.sub(target, mine), BigInt.from_int(1)), omega)


static func _n(b: PackedInt64Array) -> int:
	return BigInt.to_int(b) if BigInt.fits_int(b) else 1 << 62


## Pure: the sections from per-territory rows.
## rows: [{address, name, omega: PackedInt64Array, board: [{wallet, hypobar}] (desc)}]
static func compute(rows: Array, me: String) -> Dictionary:
	var hot: Array = []
	var reach: Array = []
	var crowns: Array = []
	var build: Array = []
	for r in rows:
		var omega: PackedInt64Array = r["omega"]
		if BigInt.is_zero(omega):
			continue
		var board: Array = r["board"]
		var total := PackedInt64Array()
		var rank := -1
		var mine := PackedInt64Array()
		for i in board.size():
			total = BigInt.add(total, board[i]["hypobar"])
			if board[i]["wallet"] == me:
				rank = i + 1
				mine = board[i]["hypobar"]
		var leader: PackedInt64Array = board[0]["hypobar"] if not board.is_empty() else PackedInt64Array()
		var e := {"address": r["address"], "name": r["name"], "omega": omega, "rank": rank, "mine": mine,
			"leader": leader, "players": board.size()}
		if me != "":
			if rank == 1:
				var runner: PackedInt64Array = board[1]["hypobar"] if board.size() > 1 else PackedInt64Array()
				crowns.append({"address": r["address"], "name": r["name"], "omega": omega,
					"margin_su": _n(su_to_pass(mine, runner, omega)), "runner_up": board[1]["wallet"] if board.size() > 1 else ""})
			else:
				e["su_top"] = _n(su_to_pass(leader, mine, omega)) if not board.is_empty() else 1
				var above: PackedInt64Array = board[rank - 2]["hypobar"] if rank > 1 else (board[board.size() - 1]["hypobar"] if not board.is_empty() else PackedInt64Array())
				e["su_next"] = _n(su_to_pass(above, mine, omega)) if not board.is_empty() else 1
				e["next_rank"] = rank - 1 if rank > 1 else maxi(1, board.size())
				if int(e["su_top"]) <= REACH_MAX:
					reach.append(e)
		hot.append(e)
		var tier := Development.tier_of(total)
		var nxt := Development.next_threshold(tier)
		if nxt != "":
			var need := BigInt.sub(BigInt.from_decimal(nxt), total) if BigInt.cmp(BigInt.from_decimal(nxt), total) > 0 else PackedInt64Array()
			build.append({"address": r["address"], "name": r["name"], "omega": omega, "tier": tier,
				"next_tier": tier + 1, "su": _n(ceil_div(need, omega)), "total": total})
	hot.sort_custom(func(a, b): return BigInt.cmp(a["omega"], b["omega"]) > 0)
	reach.sort_custom(func(a, b): return int(a["su_top"]) < int(b["su_top"]))
	crowns.sort_custom(func(a, b): return int(a["margin_su"]) < int(b["margin_su"]))
	build.sort_custom(func(a, b): return int(a["su"]) < int(b["su"]))
	return {"hot": hot, "reach": reach, "crowns": crowns, "build": build}


## Reads Ω everywhere, the boards where Ω ≥ 1, and a gas quote; then compute().
static func read(me: String) -> Opportunities:
	var o := Opportunities.new()
	var head := await Chain.refresh_head()
	if head < 0:
		o.error = "chain head unavailable"
		return o
	o.block = head
	var terr: Array = Registry.all()
	var calls: Array = []
	for q in terr:
		calls.append(Multicall.make_call(Contracts.FORNAX, "balanceOf(address)", [q["address"]]))
	var res: Array = await Chain.multicall.run(calls, "", head)
	var live: Array = []
	for i in terr.size():
		var v = Multicall.value(res[i], ["uint256"])
		if v == null:
			continue
		var om := BigInt.div(BigInt.from_hex(v[0]), BigInt.from_decimal(String(terr[i]["entropy"])))
		if not BigInt.is_zero(om):
			live.append({"address": String(terr[i]["address"]), "name": String(terr[i].get("name", "")), "omega": om})
	var players: Array = Players.all()
	var c2: Array = []
	for t in live:
		for p in players:
			c2.append(Multicall.make_call(p["yue"], "Bar(address)", [t["address"]]))
	var r2: Array = await Chain.multicall.run(c2, "", head)
	for ti in live.size():
		var board: Array = []
		for pi in players.size():
			var v2 = Multicall.value(r2[ti * players.size() + pi], ["uint256", "uint256"])
			if v2 == null:
				continue
			var hb := BigInt.from_hex(v2[0])
			if not BigInt.is_zero(hb):
				board.append({"wallet": String(players[pi]["wallet"]), "hypobar": hb})
		board.sort_custom(func(a, b): return BigInt.cmp(a["hypobar"], b["hypobar"]) > 0)
		live[ti]["board"] = board
	var sec := compute(live, me)
	o.hot = sec["hot"]
	o.reach = sec["reach"]
	o.crowns = sec["crowns"]
	o.build = sec["build"]
	if me != "" and not live.is_empty():
		var g := await Moves.gas_quote(me, Contracts.CHEON, Abi.encode_call("Su(address)", [live[0]["address"]]))
		if g["ok"]:
			o.gas_per_su = int(g["gas"])
			o.gas_price = BigInt.div(g["cost_wei"], BigInt.from_int(maxi(1, int(g["gas"]))))
	o.ok = true
	return o


## PLS for n Su at the quoted gas ("—" without a quote).
func cost_of(n: int) -> String:
	if gas_per_su < 0 or gas_price.is_empty():
		return "—"
	return TokenFormat.wei_to_tokens(BigInt.mul(gas_price, BigInt.from_int(gas_per_su * n))) + " PLS"
