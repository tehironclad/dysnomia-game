class_name PulseX
extends RefCounted
## PulseX (PulseChain's main DEX): the pools behind the Swap Hall, as numbers.
## Addresses are in Contracts (verified on chain 2026-11-24: code, router.factory(),
## router.WPLS()). Everything here is pure except read_board(), which reads every
## pool and balance at ONE pinned block through Multicall3 (no JSON-RPC batches).
##
## Amounts are BigInt (PackedInt64Array) in the token's smallest unit; never floats.
## A token with no pair on either factory is "no pool on PulseX": no price is shown.

const FEE_NUM := 9971   ## 0.29% fee: getAmountOut(1e6, 1e30, 1e30) = 997,099 on both routers [live]
const FEE_DEN := 10000
const DEFAULT_SLIPPAGE_BPS := 100  ## 1%
const DEADLINE_S := 1200           ## 20 minutes from the head block's timestamp
const VERSIONS := ["V1", "V2"]

## What the Swap Hall lists, in this order; the territory's own QING token and its
## asset join at runtime. Labels are fallbacks: symbol() read from the chain wins.
const TOKENS := [
	["0x24f0154c1dce548adf15da2098fdd8b8a3b8151d", "AFFECTION"],
	["0xf6c50ffe7efbdee63a92e52a4d5e9aff7fb4a4d7", "Fornax"],
	["0x7ae73c498a308247be73688c09c96b3fd06ddb84", "Fomalhaute"],
	["0xe843765114992e18061498aed708537ce9d924fa", "Eris"],
	["0xb6be11f0a788014c1f68c92f8d6ccc1abf78f2ab", "Tethys (CHO)"],
	["0xb0ba7d36b7f0505879179ece7401f24eb653c6e1", "qZů (Phobos)"],
	["0x583d1c1427308f7f96bfd3e0d7a3f9674d8bf8ec", "Zürich asset"],
	["0xb680f0cc810317933f234f67eb6a9e923407f05d", "MATH"],
	["0x174a0ad99c60c20d9b3d94c3095bc1fb9ddefd62", "NoNukes"],
	["0x203e366a1821570b2f84ff5ae8b3bdeb48dc4fa1", "CROWS"],
	["0x965b0d74591bf30327075a247c47dbf487dcff08", "VOID"],
	["0x3d23084ca3f40465553797b5138cfc456e61fb5d", "CHEON"],
	["0x43136735603d4060f226c279613a4dd97146937c", "SIU"],
]

const ERROR_TEXT := {
	"PulseXRouter: EXPIRED": "the deadline passed before it was mined; quote again",
	"PulseXRouter: INSUFFICIENT_OUTPUT_AMOUNT": "the price moved past your slippage limit; quote again or allow more slippage",
	"PulseXLibrary: INSUFFICIENT_INPUT_AMOUNT": "the amount is zero",
	"PulseXLibrary: INSUFFICIENT_LIQUIDITY": "the pool has no liquidity",
	"PulseX: K": "the token takes a fee on transfer; the fee-on-transfer swap is needed",
	"TransferHelper::transferFrom: transferFrom failed": "the router could not take your tokens: approve first, or you hold too little",
	"TransferHelper: TRANSFER_FROM_FAILED": "the router could not take your tokens: approve first, or you hold too little",
	"TransferHelper: ETH_TRANSFER_FAILED": "the router could not send you PLS",
	"ERC20: insufficient allowance": "not approved for that much yet: approve first",
	"ERC20: transfer amount exceeds balance": "you hold too little of that token",
	"ERC20: insufficient balance": "you hold too little of that token",
}


static func router_of(version: String) -> String:
	return Contracts.PULSEX_V1_ROUTER if version == "V1" else Contracts.PULSEX_V2_ROUTER


static func factory_of(version: String) -> String:
	return Contracts.PULSEX_V1_FACTORY if version == "V1" else Contracts.PULSEX_V2_FACTORY


# --- Pure maths (the router's own formulas, in BigInt) -----------------------

## PulseXLibrary.getAmountOut: in·9971·rOut / (rIn·10000 + in·9971). Zero when a side is empty.
static func amount_out(amount_in: PackedInt64Array, reserve_in: PackedInt64Array, reserve_out: PackedInt64Array) -> PackedInt64Array:
	if BigInt.is_zero(amount_in) or BigInt.is_zero(reserve_in) or BigInt.is_zero(reserve_out):
		return BigInt.zero()
	var in_fee := BigInt.mul_small(amount_in, FEE_NUM)
	var num := BigInt.mul(in_fee, reserve_out)
	var den := BigInt.add(BigInt.mul_small(reserve_in, FEE_DEN), in_fee)
	return BigInt.div(num, den)


## Along a path of hops [[reserve_in, reserve_out], …]: [in, out1, out2, …] (getAmountsOut).
static func amounts_out(amount_in: PackedInt64Array, hops: Array) -> Array:
	var out: Array = [amount_in]
	var cur := amount_in
	for h in hops:
		cur = amount_out(cur, h[0], h[1])
		out.append(cur)
	return out


## Price impact of one hop in basis points: how much less you get than at the
## pool's mid price (in·rOut/rIn), fee included. 0..10000.
static func impact_bps(amount_in: PackedInt64Array, reserve_in: PackedInt64Array, reserve_out: PackedInt64Array) -> int:
	if BigInt.is_zero(amount_in) or BigInt.is_zero(reserve_in) or BigInt.is_zero(reserve_out):
		return 0
	var mid := BigInt.div(BigInt.mul(amount_in, reserve_out), reserve_in)
	if BigInt.is_zero(mid):
		return 10000
	var got := amount_out(amount_in, reserve_in, reserve_out)
	var short := BigInt.sub(mid, got) if BigInt.cmp(mid, got) > 0 else BigInt.zero()
	return BigInt.to_int(BigInt.div(BigInt.mul_small(short, 10000), mid))


## The least you accept: out · (10000 − slippage) / 10000, rounded down.
static func min_out(out: PackedInt64Array, slippage_bps: int) -> PackedInt64Array:
	return BigInt.div(BigInt.mul_small(out, 10000 - clampi(slippage_bps, 0, 10000)), BigInt.from_int(10000))


## PLS (wei) per one whole token at a pool's mid price: wpls·10^dec / token.
static func price_wei(wpls_reserve: PackedInt64Array, token_reserve: PackedInt64Array, decimals: int) -> PackedInt64Array:
	if BigInt.is_zero(token_reserve):
		return BigInt.zero()
	return BigInt.div(BigInt.mul(wpls_reserve, pow10(decimals)), token_reserve)


static func pow10(n: int) -> PackedInt64Array:
	return BigInt.from_decimal("1" + "0".repeat(maxi(n, 0)))


## "1.5" → 1.5·10^decimals as a BigInt; {} for anything that is not a plain
## non-negative decimal with at most `decimals` fractional digits.
static func parse_units(text: String, decimals: int = 18) -> Dictionary:
	var s := text.strip_edges().replace(",", "").replace("_", "")
	if s == "" or s == ".":
		return {}
	var parts := s.split(".")
	if parts.size() > 2:
		return {}
	var ip := parts[0] if parts[0] != "" else "0"
	var fp := parts[1] if parts.size() == 2 else ""
	for c in ip + fp:
		if c < "0" or c > "9":
			return {}
	if fp.length() > decimals:
		return {}
	return {"wei": BigInt.from_decimal(ip + fp.rpad(decimals, "0"))}


static func fmt(wei: PackedInt64Array, decimals: int = 18, frac: int = 6) -> String:
	return TokenFormat.wei_to_tokens(wei, decimals, frac)


# --- Calldata -------------------------------------------------------------------

static func amounts_out_call(amount_in: PackedInt64Array, path: Array) -> String:
	return Abi.encode_call("getAmountsOut(uint256,address[])", [BigInt.to_decimal(amount_in), path])


## Decoded getAmountsOut return: [BigInt, …], or [] if it did not decode.
static func decode_amounts(result_hex: String) -> Array:
	if Abi.strip0x(result_hex).length() < 128:
		return []
	var out: Array = []
	for v in Abi.decode(["uint256[]"], result_hex)[0]:
		out.append(BigInt.coerce(v))
	return out


## The swap call. `kind`: "buy" (PLS → token, payable), "sell" (token → PLS) or
## "cross" (token → WPLS → token). `fot` picks the fee-on-transfer variant.
static func swap_call(kind: String, amount_in: PackedInt64Array, min_out_wei: PackedInt64Array, path: Array, to: String, deadline: int, fot: bool = false) -> String:
	var dl := str(deadline)
	match kind:
		"buy":
			var sig := "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)" if fot else "swapExactETHForTokens(uint256,address[],address,uint256)"
			return Abi.encode_call(sig, [BigInt.to_decimal(min_out_wei), path, to, dl])
		"sell":
			var sig2 := "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" if fot else "swapExactTokensForETH(uint256,uint256,address[],address,uint256)"
			return Abi.encode_call(sig2, [BigInt.to_decimal(amount_in), BigInt.to_decimal(min_out_wei), path, to, dl])
	var sig3 := "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" if fot else "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"
	return Abi.encode_call(sig3, [BigInt.to_decimal(amount_in), BigInt.to_decimal(min_out_wei), path, to, dl])


static func path_for(kind: String, token_in: String, token_out: String) -> Array:
	match kind:
		"buy": return [Contracts.WPLS, token_out]
		"sell": return [token_in, Contracts.WPLS]
	return [token_in, Contracts.WPLS, token_out]


## A router revert in plain words (Error(string) from the router, pair or token).
static func explain(message: String) -> String:
	for k in ERROR_TEXT:
		if message.contains(k):
			return "%s (%s)" % [ERROR_TEXT[k], k]
	return message


## Did the simulation fail in a way the fee-on-transfer variant could fix?
static func wants_fot(message: String) -> bool:
	return message.contains("PulseX: K") or message.contains("TRANSFER_FAILED")


# --- Receipt checks (pure) ---------------------------------------------------------

## Every ERC-20 Transfer `token` emitted in a receipt: [{from, to, value}].
static func transfers(receipt: Dictionary, token: String) -> Array:
	var out: Array = []
	for lg in receipt.get("logs", []):
		if String(lg.get("address", "")).to_lower() != token.to_lower():
			continue
		var t: Array = lg.get("topics", [])
		if t.size() < 3 or String(t[0]).to_lower() != Contracts.TOPIC_TRANSFER:
			continue
		out.append({"from": "0x" + String(t[1]).to_lower().right(40), "to": "0x" + String(t[2]).to_lower().right(40),
			"value": BigInt.from_hex(String(lg.get("data", "0x0")))})
	return out


## Sum of `token` moved from → to in the receipt ("" matches anyone).
static func moved(receipt: Dictionary, token: String, from: String, to: String) -> PackedInt64Array:
	var total := BigInt.zero()
	for tr in transfers(receipt, token):
		if (from == "" or tr["from"] == from.to_lower()) and (to == "" or tr["to"] == to.to_lower()):
			total = BigInt.add(total, tr["value"])
	return total


## WPLS Deposit (PLS in) or Withdrawal (PLS out) amounts in a receipt.
static func wpls_event(receipt: Dictionary, topic: String) -> PackedInt64Array:
	var total := BigInt.zero()
	for lg in receipt.get("logs", []):
		if String(lg.get("address", "")).to_lower() != Contracts.WPLS:
			continue
		var t: Array = lg.get("topics", [])
		if t.size() >= 1 and String(t[0]).to_lower() == topic:
			total = BigInt.add(total, BigInt.from_hex(String(lg.get("data", "0x0"))))
	return total


## What a swap receipt proves: {ok, sent, received, message}. Token sides are
## Transfer logs to/from the wallet; the PLS side is WPLS Deposit/Withdrawal
## (the native PLS leg itself leaves no log; the caller re-reads the balance).
static func verify_swap(receipt: Dictionary, kind: String, wallet: String, token_in: String, token_out: String) -> Dictionary:
	if String(receipt.get("status", "")) != "0x1":
		return {"ok": false, "message": "the receipt's status is not 1"}
	var sent := wpls_event(receipt, Contracts.TOPIC_WPLS_DEPOSIT) if kind == "buy" else moved(receipt, token_in, wallet, "")
	var got := wpls_event(receipt, Contracts.TOPIC_WPLS_WITHDRAWAL) if kind == "sell" else moved(receipt, token_out, "", wallet)
	if BigInt.is_zero(sent):
		return {"ok": false, "sent": sent, "received": got, "message": "the receipt shows nothing paid in"}
	if BigInt.is_zero(got):
		return {"ok": false, "sent": sent, "received": got, "message": "the receipt shows nothing paid out to you"}
	return {"ok": true, "sent": sent, "received": got, "message": ""}


# --- The board: every pool and balance at one block (async) ----------------------

## Reads the routers (factory(), WPLS() — the addresses checked live), each token's
## symbol/decimals/pairs on both factories, their reserves, and (with a wallet) its
## balances and PLS, all pinned to one block. Returns
## {ok, block, routers_ok, wallet, pls, tokens: [{address, label, symbol, decimals,
##  balance, pools: {V1|V2: {pair, wpls, token}}, best}], error}.
## Unread values stay null ("—"); a token with no pair has best = "".
static func read_board(tokens: Array, wallet: String = "") -> Dictionary:
	var head: int = await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "block": -1, "error": "the chain did not answer (block number)"}
	var mc: Multicall = Chain.multicall
	var calls: Array = []
	for v in VERSIONS:
		calls.append(Multicall.make_call(router_of(v), "factory()"))
		calls.append(Multicall.make_call(router_of(v), "WPLS()"))
	var per := 4 + (1 if wallet != "" else 0)
	for t in tokens:
		var a: String = t[0]
		calls.append(Multicall.make_call(a, "symbol()"))
		calls.append(Multicall.make_call(a, "decimals()"))
		for v in VERSIONS:
			calls.append(Multicall.make_call(factory_of(v), "getPair(address,address)", [Contracts.WPLS, a]))
		if wallet != "":
			calls.append(Multicall.make_call(a, "balanceOf(address)", [wallet]))
	if wallet != "":
		calls.append(Multicall.make_call(Contracts.MULTICALL3, "getEthBalance(address)", [wallet]))
	var r: Array = await mc.run(calls, "", head)
	if r.is_empty() or r[0].has("chunk_error"):
		return {"ok": false, "block": head, "error": "Multicall3 did not answer at block %d" % head}
	var routers_ok := true
	for i in VERSIONS.size():
		var f = Multicall.value(r[i * 2], ["address"])
		var w = Multicall.value(r[i * 2 + 1], ["address"])
		if f == null or w == null or String(f[0]) != factory_of(VERSIONS[i]) or String(w[0]) != Contracts.WPLS:
			routers_ok = false
	var rows: Array = []
	var pair_calls: Array = []
	var pair_refs: Array = []
	for j in tokens.size():
		var base := 4 + j * per
		var sym = _str(r[base])
		var dec = Multicall.value(r[base + 1], ["uint8"])
		var row := {"address": String(tokens[j][0]).to_lower(), "label": tokens[j][1], "symbol": sym if sym != null and sym != "" else tokens[j][1],
			"name": String(tokens[j][1]) if String(tokens[j][1]) != "" else (String(sym) if sym != null else "—"),
			"decimals": int(BigInt.to_int(BigInt.coerce(dec[0]))) if dec != null else -1, "balance": null, "pools": {}, "best": ""}
		if wallet != "":
			var b = Multicall.value(r[base + 4], ["uint256"])
			row["balance"] = BigInt.coerce(b[0]) if b != null else null
		for k in VERSIONS.size():
			var p = Multicall.value(r[base + 2 + k], ["address"])
			if p != null and String(p[0]).trim_prefix("0x").replace("0", "") != "":
				pair_calls.append(Multicall.make_call(p[0], "getReserves()"))
				pair_calls.append(Multicall.make_call(p[0], "token0()"))
				pair_refs.append([j, VERSIONS[k], String(p[0])])
		rows.append(row)
	var pls = null
	if wallet != "":
		var e = Multicall.value(r[r.size() - 1], ["uint256"])
		pls = BigInt.coerce(e[0]) if e != null else null
	if not pair_calls.is_empty():
		var r2: Array = await mc.run(pair_calls, "", head)
		for i in pair_refs.size():
			var res = Multicall.value(r2[i * 2], ["uint112", "uint112", "uint32"])
			var t0 = Multicall.value(r2[i * 2 + 1], ["address"])
			if res == null or t0 == null:
				continue
			var w_is0: bool = String(t0[0]) == Contracts.WPLS
			var r0 := BigInt.coerce(res[0])
			var r1 := BigInt.coerce(res[1])
			var row: Dictionary = rows[pair_refs[i][0]]
			row["pools"][pair_refs[i][1]] = {"pair": pair_refs[i][2], "wpls": r0 if w_is0 else r1, "token": r1 if w_is0 else r0}
	for row in rows:
		row["best"] = best_pool(row["pools"])
	return {"ok": true, "block": head, "routers_ok": routers_ok, "wallet": wallet, "pls": pls, "tokens": rows}


## The deeper pool (more WPLS behind it) with both sides non-zero, or "".
static func best_pool(pools: Dictionary) -> String:
	var best := ""
	for v in VERSIONS:
		if not pools.has(v):
			continue
		var p: Dictionary = pools[v]
		if BigInt.is_zero(p["wpls"]) or BigInt.is_zero(p["token"]):
			continue
		if best == "" or BigInt.cmp(p["wpls"], pools[best]["wpls"]) > 0:
			best = v
	return best


## The router two tokens share for a cross swap (both have a live pool there), the
## one whose thinner side is deeper; "" if none.
static func shared_router(a: Dictionary, b: Dictionary) -> String:
	var best := ""
	var best_depth := BigInt.zero()
	for v in VERSIONS:
		if not (a["pools"].has(v) and b["pools"].has(v)):
			continue
		var da: PackedInt64Array = a["pools"][v]["wpls"]
		var db: PackedInt64Array = b["pools"][v]["wpls"]
		if BigInt.is_zero(da) or BigInt.is_zero(db):
			continue
		var depth := da if BigInt.cmp(da, db) < 0 else db
		if best == "" or BigInt.cmp(depth, best_depth) > 0:
			best = v
			best_depth = depth
	return best


static func _str(res: Dictionary):
	if not res.get("ok", false):
		return null
	var d := Abi.strip0x(String(res.get("data", "")))
	if d.length() < 128:
		return null
	return String(Abi.decode(["string"], res["data"])[0]).strip_edges()
