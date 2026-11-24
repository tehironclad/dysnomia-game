class_name BarTab
extends RefCounted
## Sunny's bar menu ("AFFECTION ON TAP"). Every drink is the visitor's OWN real
## contract call, signed from their wallet through the write rule (Wallet.send:
## simulate from the wallet → sign → receipt read from the chain), then measured:
##
## - The six AFFECTION ops (Pi, Rho, Generate, Alpha, Beta, Upsilon) are real and
##   permissionless [live, simulated 2026-11-24 from a player wallet: all six
##   pass]. They mint AFFECTION into the AFFECTION contract's own reserve and do
##   not touch bars, Charge or range (LEARNINGS §1). The pub says so, and proves
##   it: after the receipt it re-reads YUE.Bar(this QING) at the block before and
##   the receipt's block and shows the measured change (+0 is the honest answer),
##   and it sums the AFFECTION Transfer(0x0 → …) mints found in the receipt.
## - The House Su is CHEON.Su(this QING), the move that does grow your bars here.
## - A round for the house is ArcadePay.transfer_to_qing: 1 Ⓐ to this QING.
## A failed read shows "—". Nothing here invents a number.

const KIND_OP := "op"
const KIND_SU := "su"

const DRINKS := [
	{"id": "pi_shot", "kind": KIND_OP, "sig": "Pi()", "name": "Pi Shot",
		"blurb": "AFFECTION.Pi(), neat.", "look": [Color(1.0, 0.72, 0.18), "shot"]},
	{"id": "rho_rocks", "kind": KIND_OP, "sig": "Rho()", "name": "Rho on the Rocks",
		"blurb": "AFFECTION.Rho() over regolith ice.", "look": [Color(0.95, 0.45, 0.1), "rocks"]},
	{"id": "generator_lager", "kind": KIND_OP, "sig": "Generate()", "name": "Generator Lager",
		"blurb": "AFFECTION.Generate(), drawn from the tap.", "look": [Color(1.0, 0.68, 0.12), "pint"]},
	{"id": "alpha_sour", "kind": KIND_OP, "sig": "Alpha(uint64)", "name": "Alpha Sour",
		"blurb": "AFFECTION.Alpha(seed), shaken with your lucky number.", "look": [Color(0.55, 1.0, 0.3), "coupe"]},
	{"id": "beta_blocker", "kind": KIND_OP, "sig": "Beta(uint64)", "name": "Beta Blocker",
		"blurb": "AFFECTION.Beta(seed), long and blue.", "look": [Color(0.25, 0.55, 1.0), "highball"]},
	{"id": "upsilon_fizz", "kind": KIND_OP, "sig": "Upsilon(uint64,bool)", "name": "Upsilon Fizz",
		"blurb": "AFFECTION.Upsilon(seed, phi), with or without a twist of phi.", "look": [Color(1.0, 0.3, 0.85), "fizz"]},
	{"id": "house_su", "kind": KIND_SU, "sig": "Su(address)", "name": "The House Su",
		"blurb": "CHEON.Su(this QING): the one that grows your bars here, +1 YUE.", "look": [Color(1.0, 0.85, 0.3), "pint"]},
]
const ROUND := {"id": "house_round", "name": "Round for the House",
	"blurb": "1 Ⓐ from your wallet to this QING (AFFECTION.transfer), verified in the receipt. The room cheers.",
	"look": [Color(1.0, 0.68, 0.12), "pint"]}

const OP_NOTE := "AFFECTION ops mint into AFFECTION's own reserve; they don't move your bars, Charge or range."
const SEED_MAX := 999999999


static func drink(id: String) -> Dictionary:
	for d in DRINKS:
		if d["id"] == id:
			return d
	return ROUND if id == ROUND["id"] else {}


static func takes_seed(d: Dictionary) -> bool:
	return String(d.get("sig", "")).contains("uint64")


static func takes_phi(d: Dictionary) -> bool:
	return String(d.get("sig", "")).contains("bool")


static func target(d: Dictionary) -> String:
	return Contracts.CHEON if d.get("kind") == KIND_SU else Contracts.AFFECTION


## The exact call: "AFFECTION.Alpha(4242)", "CHEON.Su(0x2b78…)".
static func call_text(d: Dictionary, qing: String, seed_value: int, phi: bool) -> String:
	var fn := String(d["sig"]).split("(")[0]
	match String(d["sig"]):
		"Su(address)": return "CHEON.Su(%s…%s)" % [qing.substr(0, 6), qing.right(4)]
		"Alpha(uint64)", "Beta(uint64)": return "AFFECTION.%s(%d)" % [fn, seed_value]
		"Upsilon(uint64,bool)": return "AFFECTION.Upsilon(%d, %s)" % [seed_value, "true" if phi else "false"]
	return "AFFECTION.%s()" % fn


## Calldata for a drink. Pure.
static func calldata(d: Dictionary, qing: String, seed_value: int, phi: bool) -> String:
	var sig := String(d["sig"])
	match sig:
		"Su(address)": return Abi.encode_call(sig, [qing.to_lower()])
		"Alpha(uint64)", "Beta(uint64)": return Abi.encode_call(sig, [clampi(seed_value, 0, SEED_MAX)])
		"Upsilon(uint64,bool)": return Abi.encode_call(sig, [clampi(seed_value, 0, SEED_MAX), phi])
	return Abi.encode_call(sig)


## AFFECTION Transfer(0x0 → anyone) logs in a receipt read from the chain: what
## this transaction minted. {count, total (BigInt wei), to: [addresses]}. Pure.
static func minted_in_receipt(receipt: Dictionary) -> Dictionary:
	var total := BigInt.zero()
	var n := 0
	var to: Array = []
	for lg in receipt.get("logs", []):
		if String(lg.get("address", "")).to_lower() != Contracts.AFFECTION:
			continue
		var topics: Array = lg.get("topics", [])
		if topics.size() < 3 or String(topics[0]).to_lower() != Contracts.TOPIC_TRANSFER:
			continue
		if not BigInt.is_zero(BigInt.from_hex(String(topics[1]))):
			continue
		total = BigInt.add(total, BigInt.from_hex(String(lg.get("data", "0x0"))))
		n += 1
		var addr := "0x" + String(topics[2]).to_lower().right(40)
		if not (addr in to):
			to.append(addr)
	return {"count": n, "total": total, "to": to}


## "Hypobar 1,204 → 1,215 (+11) · Epibar 88 → 90 (+2)", or "—" where a read failed.
## before/after: {ok, hypo, epi} (BigInts). Pure.
static func bars_change_text(before: Dictionary, after: Dictionary) -> String:
	if not after.get("ok", false):
		return "Your bars here: — (the re-read failed)"
	var parts: PackedStringArray = []
	for k in [["hypo", "Hypobar"], ["epi", "Epibar"]]:
		var a: PackedInt64Array = after[k[0]]
		if not before.get("ok", false):
			parts.append("%s %s (change: —)" % [k[1], TokenFormat.group(BigInt.to_decimal(a))])
			continue
		var b: PackedInt64Array = before[k[0]]
		var up := BigInt.cmp(a, b) >= 0
		var d := BigInt.sub(a, b) if up else BigInt.sub(b, a)
		parts.append("%s %s → %s (%s%s)" % [k[1], TokenFormat.group(BigInt.to_decimal(b)), TokenFormat.group(BigInt.to_decimal(a)),
			"+" if up else "−", TokenFormat.group(BigInt.to_decimal(d))])
	return " · ".join(parts)


# --- Chain (async) ----------------------------------------------------------------

## YUE.Bar(qing) at `block`: {ok, hypo, epi, block} or {ok:false}.
static func read_bars(yue: String, qing: String, block) -> Dictionary:
	if yue == "":
		return {"ok": false}
	var r: Dictionary = await Chain.rpc.call_decoded(yue, "Bar(address)", [qing], ["uint256", "uint256"], "", block)
	if not r["ok"]:
		return {"ok": false}
	return {"ok": true, "hypo": BigInt.from_hex(r["values"][0]), "epi": BigInt.from_hex(r["values"][1]), "block": block}


## Simulates the drink from `wallet` at the head block (tx.origin = the wallet)
## and quotes gas. {ok, block, to, data, lines} or {ok:false, message, revert?}.
static func preview(d: Dictionary, wallet: String, qing: String, seed_value: int, phi: bool) -> Dictionary:
	var head := await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "message": "Chain head unavailable: —"}
	var to := target(d)
	var data := calldata(d, qing, seed_value, phi)
	var r: Dictionary = await Chain.rpc.eth_call(to, data, wallet, head)
	if not r["ok"]:
		if r.get("kind") == "revert":
			return {"ok": false, "message": "Simulated from your wallet at block %d: it would revert (%s)." % [head, r["revert"]["message"]], "revert": r["revert"]}
		return {"ok": false, "message": "The simulation did not run (RPC): —"}
	var lines: PackedStringArray = ["Simulated from your wallet at block %d: it would succeed." % head]
	var g: Dictionary = await Moves.gas_quote(wallet, to, data)
	lines.append(g["line"])
	return {"ok": true, "block": head, "to": to, "data": data, "lines": lines}


## Pours: Wallet.send (simulate → sign → receipt), then the measurement. Returns
## {ok, hash, block, before, after, minted} or the Wallet.send failure.
static func pour(d: Dictionary, label: String, qing: String, yue: String, seed_value: int, phi: bool) -> Dictionary:
	var res: Dictionary = await Wallet.send(label, target(d), calldata(d, qing, seed_value, phi))
	if not res["ok"]:
		return res
	var block: int = res["block"]
	var before := await read_bars(yue, qing, block - 1)
	var after := await read_bars(yue, qing, block)
	return {"ok": true, "hash": res["hash"], "block": block, "before": before, "after": after,
		"minted": minted_in_receipt(res["receipt"])}


## The confirmed drink, in words, from what was measured.
static func report(d: Dictionary, r: Dictionary) -> String:
	var lines: PackedStringArray = ["Confirmed in block %d (receipt status 1)." % r["block"]]
	if d.get("kind") == KIND_OP:
		var m: Dictionary = r["minted"]
		if m["count"] > 0:
			lines.append("The receipt shows AFFECTION minting %s into %s (%d Transfer log%s from 0x0)." % [
				ArcadePay.fmt(m["total"]), "its own reserve" if m["to"] == [Contracts.AFFECTION] else "%d address(es)" % m["to"].size(),
				m["count"], "" if m["count"] == 1 else "s"])
		else:
			lines.append("No AFFECTION mint log in this receipt.")
	lines.append("Read at blocks %d → %d: %s" % [r["block"] - 1, r["block"], bars_change_text(r["before"], r["after"])])
	if d.get("kind") == KIND_OP:
		lines.append(OP_NOTE)
	return "\n".join(lines)
