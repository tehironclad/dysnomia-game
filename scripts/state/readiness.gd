class_name Readiness
extends RefCounted
## WORLD-readiness (WP 4.3), ported from the site's owner/power/world-ready.js
## (docs/LEARNINGS.md §7). States, in order:
##   no-account → not-started → blocked → not-ready → fragile → ready
## The probe runs [CHEON.Su(Phobos), META.Beat(Phobos Waat)] through Multicall3
## with from = wallet: the player is tx.origin and a contract is msg.sender,
## exactly as under WORLD.Code.

const MILLI := "1000000000000000"  # 0.001 token in wei
const FORNAX_THIN := "375000000000000"  # below 0.000375 Fornax fails in many blocks

var state := "unknown"
var reason := ""
var block := -1
## key → {verdict: ok|thin|low|wrong-place|round|missing, detail}
var holdings := {}
## When ready: decoded Beat (Dione, Charge, Deimos, Yeo) and Su (Charge, Hypobar, Epibar).
var beat := {}
var su := {}
var fragile_reason := ""


static func evaluate(ps: PlayerState) -> Readiness:
	var r := Readiness.new()
	r.block = ps.block
	if not ps.ok:
		r.state = "unknown"
		r.reason = "could not read the chain: " + ps.error
		return r
	r.holdings = verdicts(ps)
	if not ps.has_lau():
		r.state = "no-account"
		r.reason = "No LAU registered for this wallet (CHO.GetUserTokenAddress returns 0)."
		return r
	if not ps.has_yue():
		r.state = "not-started"
		r.reason = "LAU but no YUE: call SEI.Start(LAU, name, symbol)."
		return r
	var phobos := Contracts.PHOBOS_QING
	var calls := [
		Multicall.make_call(Contracts.CHEON, "Su(address)", [phobos]),
		Multicall.make_call(Contracts.META, "Beat(uint256)", [Contracts.PHOBOS_WAAT]),
	]
	var res: Array = await Chain.multicall.run(calls, ps.wallet, ps.block)
	var beat_res: Dictionary = res[1]
	if res[0].has("chunk_error"):
		r.state = "unknown"
		r.reason = "probe failed to run"
		return r
	if not beat_res["ok"]:
		var rev := Abi.decode_revert(beat_res["data"])
		match rev["name"]:
			"ZeroHoldings":
				r.state = "blocked"
				r.reason = "Your wallet holds 0 of its own YUE (ZeroHoldings): CHOA.Play mints 1."
			"NotStarted":
				r.state = "not-started"
				r.reason = "NotStarted: call SEI.Start."
			_:
				r.state = "not-ready"
				r.reason = rev["message"]
		return r
	var b = Multicall.value(beat_res, ["uint256", "uint256", "uint256", "uint256"])
	r.beat = {"dione": b[0], "charge": b[1], "deimos": b[2], "yeo": b[3]}
	var s = Multicall.value(res[0], ["uint256", "uint256", "uint256"])
	if s != null:
		r.su = {"charge": s[0], "hypobar": s[1], "epibar": s[2]}
	# Standalone Beat: if it fails while the Code-order probe passes → fragile.
	var solo := await Chain.rpc.eth_call(Contracts.META, Abi.encode_call("Beat(uint256)", [Contracts.PHOBOS_WAAT]), ps.wallet, ps.block)
	if not solo["ok"]:
		r.state = "fragile"
		r.fragile_reason = "Passes in Code order but a standalone Beat fails: %s" % solo.get("revert", {}).get("message", "error")
	else:
		r.state = "ready"
	r.reason = "Range (Yeo) at Phobos: %s%s." % [BigInt.to_decimal(BigInt.from_hex(r.beat["yeo"])),
		" (centre cell only)" if BigInt.is_zero(BigInt.from_hex(r.beat["yeo"])) else ""]
	return r


## Per-holding verdicts (the site's world-ready cards).
static func verdicts(ps: PlayerState) -> Dictionary:
	var v := {}
	var milli := BigInt.from_decimal(MILLI)
	for tk in ["fomalhaute", "fornax"]:
		var on_lau := ps.balance(tk, "lau")
		var elsewhere := BigInt.add(ps.balance(tk, "wallet"), ps.balance(tk, "yue"))
		var thin_at := BigInt.from_decimal(FORNAX_THIN) if tk == "fornax" else BigInt.from_int(1)
		if BigInt.cmp(on_lau, milli) >= 0:
			v[tk] = {"verdict": "ok", "detail": "on your LAU"}
		elif BigInt.cmp(on_lau, thin_at) > 0:
			v[tk] = {"verdict": "thin", "detail": "on your LAU but under 0.001"}
		elif not BigInt.is_zero(on_lau):
			v[tk] = {"verdict": "low", "detail": "only dust on your LAU"}
		elif not BigInt.is_zero(elsewhere):
			v[tk] = {"verdict": "wrong-place", "detail": "held, but not on your LAU (it must be on the LAU)"}
		else:
			v[tk] = {"verdict": "missing", "detail": "none held"}
	for tk2 in ["tethys", "qzu"]:
		var y := ps.yuan(tk2)
		if BigInt.is_zero(ps.total(tk2)):
			v[tk2] = {"verdict": "missing", "detail": "none held (any of wallet, LAU, YUE counts)"}
		elif tk2 == "qzu" and is_round(y):
			v[tk2] = {"verdict": "round", "detail": "a perfectly round total can fail; add 1 wei"}
		elif BigInt.cmp(ps.total(tk2), milli) < 0:
			v[tk2] = {"verdict": "thin", "detail": "held, under 0.001"}
		else:
			v[tk2] = {"verdict": "ok", "detail": "held"}
	if BigInt.cmp(ps.balance("qzu", "lau"), BigInt.from_hex("1b48eb57e000")) > 0:  # > 3e13 wei
		v["qzu"]["detail"] += "; qZů on your LAU shrinks your range everywhere"
	return v


## True when n's only prime factors are 2 and 5 (a "round" decimal amount).
static func is_round(n: PackedInt64Array) -> bool:
	if BigInt.is_zero(n):
		return false
	var x := n
	for d in [2, 5]:
		while true:
			var qr := BigInt.divmod_small(x, d)
			if qr[1] != 0:
				break
			x = qr[0]
	return BigInt.cmp(x, BigInt.from_int(1)) == 0
