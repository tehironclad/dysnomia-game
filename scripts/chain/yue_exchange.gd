class_name YueExchange
extends RefCounted
## The YUE exchange desk (LEARNINGS §19): every YUE is a public desk for QING
## tokens at the territory's fixed market rate.
##   Hong(SpendAsset, QingAsset, Amount): you pay Amount·Rate/10^18 of the asset
##     (transferFrom you → the YUE) and get Amount QING tokens out of that YUE's stock.
##   Hung(QingAsset, ReceiveAsset, Amount): you pay Amount QING tokens into the YUE
##     and get Amount·Rate/10^18 of the asset out of its stock.
## Rate = YUE.GetAssetRate(QING, asset) (the same on every YUE: it is the QING's
## GetMarketRate(asset), set by its owners with AddMarketRate; rates only rise).
## The spender to approve is the YUE you trade with. Any YUE works, for anyone; it
## pays only from what it holds. Live 2026-11-24: 14 of 942 QINGs have a rate; no
## QING's asset is itself a QING, so no rate walks up a hierarchy today.
##
## Pure helpers plus read_desk() / rated_scan() (Multicall3, one pinned block).

const ONE := "1000000000000000000"  ## the rate's unit (every rated pair is 18/18 decimals, read live)

static var _rated_cache := {}   ## {block, rows} from rated_scan(), per session


## Amount · Rate / 10^18, rounded down (what Hong charges, or what Hung pays out).
static func cost(amount: PackedInt64Array, rate: PackedInt64Array) -> PackedInt64Array:
	return BigInt.div(BigInt.mul(amount, rate), BigInt.from_decimal(ONE))


static func hong_call(spend_asset: String, qing: String, amount: PackedInt64Array) -> String:
	return Abi.encode_call("Hong(address,address,uint256)", [spend_asset, qing, BigInt.to_decimal(amount)])


static func hung_call(qing: String, receive_asset: String, amount: PackedInt64Array) -> String:
	return Abi.encode_call("Hung(address,address,uint256)", [qing, receive_asset, BigInt.to_decimal(amount)])


## What the trade needs and gives: {pay_token, pay, get_token, get, approve_token}.
static func legs(kind: String, qing: String, asset: String, amount: PackedInt64Array, rate: PackedInt64Array) -> Dictionary:
	if kind == "hong":
		return {"pay_token": asset, "pay": cost(amount, rate), "get_token": qing, "get": amount}
	return {"pay_token": qing, "pay": amount, "get_token": asset, "get": cost(amount, rate)}


## The receipt proves both legs: pay_token wallet → YUE and get_token YUE → wallet.
## {ok, paid, got, message}. Pure.
static func verify(receipt: Dictionary, wallet: String, yue: String, l: Dictionary) -> Dictionary:
	if String(receipt.get("status", "")) != "0x1":
		return {"ok": false, "message": "the receipt's status is not 1"}
	var paid := PulseX.moved(receipt, l["pay_token"], wallet, yue)
	var got := PulseX.moved(receipt, l["get_token"], yue, wallet)
	if BigInt.cmp(paid, l["pay"]) < 0:
		return {"ok": false, "paid": paid, "got": got, "message": "the receipt shows %s paid in, not %s" % [PulseX.fmt(paid), PulseX.fmt(l["pay"])]}
	if BigInt.cmp(got, l["get"]) < 0:
		return {"ok": false, "paid": paid, "got": got, "message": "the receipt shows %s paid out to you, not %s" % [PulseX.fmt(got), PulseX.fmt(l["get"])]}
	return {"ok": true, "paid": paid, "got": got, "message": ""}


## The best desk for a trade: the YUE holding the most of what you receive, if it
## holds at least `need`; your own YUE wins a tie. {} if none can pay.
static func pick_desk(desks: Array, kind: String, need: PackedInt64Array) -> Dictionary:
	var key := "stock_qing" if kind == "hong" else "stock_asset"
	var best := {}
	for d in desks:
		if d.get("verified", true) == false:
			continue  # not CHAN.Yan(wallet): never a desk to approve or pay
		var s = d.get(key)
		if s == null or BigInt.cmp(s, need) < 0 or BigInt.is_zero(s):
			continue
		if best.is_empty() or BigInt.cmp(s, best[key]) > 0 or (BigInt.cmp(s, best[key]) == 0 and d.get("own", false)):
			best = d
	return best


## The known YUEs: every player in the registry plus `own_yue`. [{yue, wallet, own}]
static func known_yues(own_yue: String = "", own_wallet: String = "") -> Array:
	var out: Array = []
	var seen := {}
	if own_yue != "":
		out.append({"yue": own_yue.to_lower(), "wallet": own_wallet.to_lower(), "own": true})
		seen[own_yue.to_lower()] = true
	for p in Players.all():
		var y := String(p.get("yue", "")).to_lower()
		if y == "" or seen.has(y):
			continue
		seen[y] = true
		out.append({"yue": y, "wallet": String(p.get("wallet", "")).to_lower(), "own": false})
	return out


## One territory's desk, at one block: the QING's asset (QING.Asset(), plus one
## level up if that asset is itself a QING), the market rate, YUE.GetAssetRate and
## IsValidAsset (read on one YUE; the same on all), symbols, every known YUE's
## stock of both tokens, and the wallet's balances and allowance to each desk.
## {ok, block, qing, pairs: [{asset, rate, market_rate, valid, symbol}], qing_symbol,
##  desks: [{yue, wallet, own, stock_qing, stock_asset}], wallet: {qing, asset}, error}
static func read_desk(qing: String, asset_hint: String, wallet: String = "", own_yue: String = "") -> Dictionary:
	qing = qing.to_lower()
	var head: int = await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "block": -1, "error": "the chain did not answer (block number)"}
	var mc: Multicall = Chain.multicall
	var r0: Array = await mc.run([Multicall.make_call(qing, "Asset()"), Multicall.make_call(qing, "symbol()")], "", head)
	var av = Multicall.value(r0[0], ["address"])
	var asset := String(av[0]).to_lower() if av != null else asset_hint.to_lower()
	if asset == "" or asset.trim_prefix("0x").replace("0", "") == "":
		return {"ok": false, "block": head, "error": "QING.Asset() did not read"}
	var assets: Array = [asset]
	var up: Dictionary = Registry.get_territory(asset) if Registry.has_method("get_territory") else {}
	if not up.is_empty() and String(up.get("asset", "")) != "":
		assets.append(String(up["asset"]).to_lower())  # the hierarchy: the asset is itself a QING
	# Every YUE here must be CHAN.Yan(its wallet) on chain: the list comes from the bundled
	# snapshot and the site accelerator, and a desk is a contract the player approves
	# tokens to and calls. A YUE the chain doesn't confirm is never a desk.
	var listed := known_yues(own_yue, wallet)
	var yan_calls: Array = []
	for y in listed:
		yan_calls.append(Multicall.make_call(Contracts.CHAN, "Yan(address)", [y["wallet"]]) if String(y["wallet"]).length() == 42
			else Multicall.make_call(Contracts.CHAN, "Yan(address)", ["0x0000000000000000000000000000000000000000"]))
	var yan_r: Array = await mc.run(yan_calls, "", head) if not yan_calls.is_empty() else []
	if not listed.is_empty() and (yan_r.is_empty() or yan_r[0].has("chunk_error")):
		return {"ok": false, "block": head, "error": "CHAN.Yan (which YUE is whose) did not read at block %d" % head}
	var yan: Array = []
	for x in yan_r:
		var yv = Multicall.value(x, ["address"])
		yan.append(String(yv[0]) if yv != null else "")
	var yues := verified_yues(listed, yan)
	var probe: String = yues[0]["yue"] if not yues.is_empty() else ""
	var calls: Array = []
	for a in assets:
		calls.append(Multicall.make_call(qing, "GetMarketRate(address)", [a]))
		calls.append(Multicall.make_call(a, "symbol()"))
		if probe != "":
			calls.append(Multicall.make_call(probe, "GetAssetRate(address,address)", [qing, a]))
			calls.append(Multicall.make_call(probe, "IsValidAsset(address,address)", [qing, a]))
	for y in yues:
		calls.append(Multicall.make_call(qing, "balanceOf(address)", [y["yue"]]))
		calls.append(Multicall.make_call(asset, "balanceOf(address)", [y["yue"]]))
	if wallet != "":
		calls.append(Multicall.make_call(qing, "balanceOf(address)", [wallet]))
		calls.append(Multicall.make_call(asset, "balanceOf(address)", [wallet]))
	var r: Array = await mc.run(calls, "", head)
	if r.is_empty() or r[0].has("chunk_error"):
		return {"ok": false, "block": head, "error": "Multicall3 did not answer at block %d" % head}
	var i := 0
	var pairs: Array = []
	for a in assets:
		var mr = Multicall.value(r[i], ["uint256"])
		var sym = PulseX._str(r[i + 1])
		i += 2
		var rate = null
		var valid = null
		if probe != "":
			var gr = Multicall.value(r[i], ["uint256"])
			var vv = Multicall.value(r[i + 1], ["bool"])
			rate = BigInt.coerce(gr[0]) if gr != null else null
			valid = bool(vv[0]) if vv != null else null
			i += 2
		pairs.append({"asset": a, "symbol": sym if sym != null else "", "market_rate": BigInt.coerce(mr[0]) if mr != null else null,
			"rate": rate, "valid": valid})
	var desks: Array = []
	for y in yues:
		var sq = Multicall.value(r[i], ["uint256"])
		var sa = Multicall.value(r[i + 1], ["uint256"])
		i += 2
		desks.append({"yue": y["yue"], "wallet": y["wallet"], "own": y["own"], "verified": true,
			"stock_qing": BigInt.coerce(sq[0]) if sq != null else null, "stock_asset": BigInt.coerce(sa[0]) if sa != null else null})
	var wb := {"qing": null, "asset": null}
	if wallet != "":
		var bq = Multicall.value(r[i], ["uint256"])
		var ba = Multicall.value(r[i + 1], ["uint256"])
		wb = {"qing": BigInt.coerce(bq[0]) if bq != null else null, "asset": BigInt.coerce(ba[0]) if ba != null else null}
	var qs = PulseX._str(r0[1])
	return {"ok": true, "block": head, "qing": qing, "asset": asset, "qing_symbol": qs if qs != null else "", "pairs": pairs,
		"desks": desks, "wallet": wb, "probe_yue": probe, "unverified": listed.size() - yues.size()}


## Pure: the listed YUEs ({yue, wallet, own}) whose CHAN.Yan(wallet) read (`yan`, same
## order; "" when unread) is that YUE, each marked verified. The rest are dropped.
static func verified_yues(listed: Array, yan: Array) -> Array:
	var out: Array = []
	for i in listed.size():
		var y: Dictionary = listed[i]
		var got := String(yan[i]).to_lower() if i < yan.size() else ""
		if got != "" and got == String(y["yue"]).to_lower() and String(y["wallet"]).length() == 42:
			var v := y.duplicate()
			v["verified"] = true
			out.append(v)
	return out


## Every known QING with a market rate for its own asset (QING.GetMarketRate(Asset)),
## at one block; cached for the session. [{qing, name, symbol, asset, rate}] or null on failure.
static func rated_scan() -> Variant:
	if not _rated_cache.is_empty():
		return _rated_cache["rows"]
	var head: int = await Chain.refresh_head()
	if head < 0:
		return null
	var terr: Array = Registry.all()
	var calls: Array = []
	for q in terr:
		var a := String(q.get("asset", ""))
		if a == "":
			a = "0x0000000000000000000000000000000000000000"
		calls.append(Multicall.make_call(q["address"], "GetMarketRate(address)", [a]))
	var r: Array = await Chain.multicall.run(calls, "", head)
	var rows: Array = []
	var failed := 0
	for i in terr.size():
		if i >= r.size() or not (r[i] is Dictionary):  # the multicall failed or came back short: those rates are unread, not zero
			failed += 1
			continue
		var v = Multicall.value(r[i], ["uint256"])
		if v == null:
			failed += 1
			continue
		var rate := BigInt.coerce(v[0])
		if BigInt.is_zero(rate):
			continue
		rows.append({"qing": String(terr[i]["address"]).to_lower(), "name": String(terr[i].get("name", "")), "symbol": String(terr[i].get("symbol", "")),
			"asset": String(terr[i].get("asset", "")).to_lower(), "rate": rate})
	if failed * 2 > terr.size():
		return null  # never cache an outage
	_rated_cache = {"block": head, "rows": rows, "failed": failed}
	return rows


static func rated_block() -> int:
	return int(_rated_cache.get("block", -1))
