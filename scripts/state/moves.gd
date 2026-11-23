class_name Moves
extends RefCounted
## Previews for the live moves (WP 5.1/5.3/5.5). A preview is a simulation from
## the player's wallet (tx.origin matters), pinned to one block, plus a gas
## quote. Nothing here signs; the caller hands the calldata to Wallet.send.
##
## Preview shape: {ok, block, to, data, lines: [String], values: {…}, gas: {…}}
## or {ok: false, message, revert?}.

const SU := "Su(address)"
const BEAT := "Beat(uint256)"


## CHEON.Su(qing): Bar(qing) before and Su's return (Charge, Hypobar, Epibar:
## the totals AFTER the Su) in one Multicall from the wallet, so the delta is
## exact for this block. +1 YUE is minted to the wallet.
static func su_preview(wallet: String, yue: String, qing: String) -> Dictionary:
	var head := await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "message": "chain head unavailable"}
	var calls := [
		Multicall.make_call(yue, "Bar(address)", [qing]),
		Multicall.make_call(Contracts.CHEON, SU, [qing]),
	]
	var res: Array = await Chain.multicall.run(calls, wallet, head)
	if res[0].has("chunk_error"):
		return {"ok": false, "message": "the simulation did not run (RPC)"}
	if not res[1]["ok"]:
		var rev := Abi.decode_revert(res[1]["data"])
		return {"ok": false, "message": "Su would revert: " + String(rev["message"]), "revert": rev}
	var before = Multicall.value(res[0], ["uint256", "uint256"])
	var after = Multicall.value(res[1], ["uint256", "uint256", "uint256"])
	if before == null or after == null:
		return {"ok": false, "message": "unexpected return data"}
	var v := su_delta(before, after)
	var data := Abi.encode_call(SU, [qing])
	var p := {"ok": true, "block": head, "to": Contracts.CHEON, "data": data, "values": v}
	p["lines"] = [
		"+%s Hypobar here  (Ω, the same for everyone)" % TokenFormat.group(BigInt.to_decimal(v["d_hypo"])),
		"+%s Epibar here  (your own Fornax ÷ your entropy)" % TokenFormat.group(BigInt.to_decimal(v["d_epi"])),
		"Charge %s%s" % [TokenFormat.group(BigInt.to_decimal(v["charge"])), charge_note(v["charge"])],
		"+1 YUE to your wallet · CHEON pays 0 (capped)",
		"Your bars here after: %s Hypobar · %s Epibar" % [TokenFormat.group(BigInt.to_decimal(v["hypo_after"])), TokenFormat.group(BigInt.to_decimal(v["epi_after"]))],
	]
	p["gas"] = await gas_quote(wallet, Contracts.CHEON, data)
	p["lines"].append(p["gas"]["line"])
	return p


## Pure: the deltas of a Su from Bar(before) = [hypo, epi] and Su's return
## [charge, hypo_after, epi_after] (hex strings).
static func su_delta(before: Array, after: Array) -> Dictionary:
	var hb := BigInt.from_hex(before[0])
	var eb := BigInt.from_hex(before[1])
	var ha := BigInt.from_hex(after[1])
	var ea := BigInt.from_hex(after[2])
	return {
		"charge": BigInt.from_hex(after[0]),
		"hypo_before": hb, "epi_before": eb, "hypo_after": ha, "epi_after": ea,
		"d_hypo": BigInt.sub(ha, hb) if BigInt.cmp(ha, hb) >= 0 else PackedInt64Array(),
		"d_epi": BigInt.sub(ea, eb) if BigInt.cmp(ea, eb) >= 0 else PackedInt64Array(),
	}


static func charge_note(charge: PackedInt64Array) -> String:
	if BigInt.is_zero(charge):
		return "  (0: no Fomalhaute on your LAU, or this territory holds no Eris)"
	if BigInt.cmp(charge, BigInt.from_int(1)) == 0:
		return "  (1: you hold none of this territory's token on your LAU)"
	return "  (pseudo-random per block, below your LAU's Fomalhaute)"


## META.Beat(waat) from the wallet: (Dione, Charge, Deimos, Yeo).
static func beat_preview(wallet: String, waat_decimal: String) -> Dictionary:
	var head := await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "message": "chain head unavailable"}
	var waat := BigInt.from_decimal(waat_decimal)
	var data := Abi.encode_call(BEAT, ["0x" + BigInt.to_hex(waat)])
	var r := await Chain.rpc.eth_call(Contracts.META, data, wallet, head)
	if not r["ok"]:
		if r.get("kind") == "revert":
			return {"ok": false, "message": "Beat would revert: " + String(r["revert"]["message"]), "revert": r["revert"]}
		return {"ok": false, "message": "the simulation did not run (RPC)"}
	if Abi.strip0x(String(r["result"])).length() < 256:
		return {"ok": false, "message": "unexpected return data"}
	var b := Abi.decode(["uint256", "uint256", "uint256", "uint256"], r["result"])
	var dec := func(h): return TokenFormat.group(BigInt.to_decimal(BigInt.from_hex(h)))
	var yeo := BigInt.from_hex(b[3])
	var p := {"ok": true, "block": head, "to": Contracts.META, "data": data,
		"values": {"dione": b[0], "charge": b[1], "deimos": b[2], "yeo": b[3]}}
	p["lines"] = [
		"Dione %s  (VITUS per future Code here: Tethys held here ÷ Entropy)" % dec.call(b[0]),
		"Charge %s" % dec.call(b[1]),
		"Deimos %s  (creator credit)" % dec.call(b[2]),
		"Yeo %s  (WORLD range here%s)" % [dec.call(b[3]), ": centre cell only" if BigInt.is_zero(yeo) else ""],
	]
	p["gas"] = await gas_quote(wallet, Contracts.META, data)
	p["lines"].append(p["gas"]["line"])
	return p


## Gas estimate × gas price → {ok, gas, cost_wei, line}. A failure is reported, not guessed.
static func gas_quote(from: String, to: String, data: String) -> Dictionary:
	var g := await Chain.rpc.estimate_gas(from, to, data)
	var pr := await Chain.rpc.gas_price()
	if not g["ok"] or not pr["ok"]:
		return {"ok": false, "line": "Gas: — (estimate unavailable)"}
	var cost := BigInt.mul(BigInt.from_int(int(g["gas"])), pr["wei"])
	return {"ok": true, "gas": int(g["gas"]), "cost_wei": cost,
		"line": "Gas ≈ %s units · ≈ %s PLS at the current price" % [TokenFormat.group(str(g["gas"])), TokenFormat.wei_to_tokens(cost)]}
