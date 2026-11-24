class_name ArcadePay
extends RefCounted
## Arcade credits. Every play on a cabinet costs FEE Ⓐ (AFFECTION, 18
## decimals), paid with AFFECTION.transfer(QING, FEE) to the QING contract of
## the territory the cabinet stands in: the territory's own balance.
##
## The pipeline is the game's write rule: Wallet.send simulates the transfer
## from the wallet, has it signed, and reads the receipt from the chain; then
## verify_receipt() finds AFFECTION's own Transfer(wallet → QING, ≥ FEE) log in
## that receipt, and the QING's AFFECTION balance is re-read at that block.
## Only then is one credit recorded (locally, keyed by the tx hash); starting
## a game spends it. A credit belongs to the QING it was paid to.

const FEE_WEI := "1000000000000000000"  # 1 Ⓐ per play
const SYMBOL := "Ⓐ"  # AFFECTION.symbol() on chain
const LEDGER := "user://arcade_credits.cfg"


static func fee_text() -> String:
	return "%s %s" % [TokenFormat.wei_to_tokens(BigInt.from_decimal(FEE_WEI)), SYMBOL]


static func fmt(wei: PackedInt64Array) -> String:
	return "%s %s" % [TokenFormat.wei_to_tokens(wei), SYMBOL]


## AFFECTION.balanceOf(holder) at `block` (default latest): {ok, balance, block} or {ok:false, error}.
static func read_balance(holder: String, block = "latest") -> Dictionary:
	var r: Dictionary = await Chain.rpc.call_decoded(Contracts.AFFECTION, "balanceOf(address)", [holder], ["uint256"], "", block)
	if not r["ok"]:
		return {"ok": false, "error": "AFFECTION.balanceOf could not be read"}
	return {"ok": true, "balance": BigInt.coerce(r["values"][0]), "block": block}


## Finds AFFECTION's Transfer(from → to, value ≥ FEE) in a receipt read from
## the chain. {ok, value} or {ok:false, message}. Pure: no network.
static func verify_receipt(receipt: Dictionary, from: String, to: String, fee_wei: String = FEE_WEI) -> Dictionary:
	var want_from := Abi.strip0x(from).to_lower()
	var want_to := Abi.strip0x(to).to_lower()
	for lg in receipt.get("logs", []):
		if String(lg.get("address", "")).to_lower() != Contracts.AFFECTION:
			continue
		var topics: Array = lg.get("topics", [])
		if topics.size() < 3 or String(topics[0]).to_lower() != Contracts.TOPIC_TRANSFER:
			continue
		if String(topics[1]).to_lower().right(40) != want_from or String(topics[2]).to_lower().right(40) != want_to:
			continue
		var value := BigInt.from_hex(String(lg.get("data", "0x0")))
		if BigInt.cmp(value, BigInt.from_decimal(fee_wei)) < 0:
			return {"ok": false, "message": "The transfer moved only %s; a play costs %s." % [fmt(value), fee_text()]}
		return {"ok": true, "value": value}
	return {"ok": false, "message": "The receipt has no AFFECTION Transfer from the wallet to the QING."}


## Pays one credit at `qing`. Returns {ok, hash, block, qing_balance} or the
## failure from Wallet.send / verification ({ok:false, stage, message}).
static func pay(qing: String, place_name: String) -> Dictionary:
	var r := await transfer_to_qing(qing, "Arcade credit at %s (%s)" % [place_name, fee_text()])
	if r["ok"]:
		add_credit(r["from"], qing.to_lower(), r["hash"], r["block"])
	return r


## FEE Ⓐ from the connected wallet to `qing`, through the write rule: Wallet.send
## (simulate → sign → receipt from the chain), then AFFECTION's own Transfer log
## found in that receipt, then the QING's balance re-read at the receipt's block.
## {ok, from, hash, block, qing_balance (null if the re-read failed)} or
## {ok:false, stage, message}. Sunny's "round for the house" uses it without a credit.
## `fee_wei` defaults to FEE_WEI; the fair's tickets add their game's code in the last wei
## (FairProgress.fee_wei), so the transfer itself says which stall it paid for.
static func transfer_to_qing(qing: String, label: String, fee_wei: String = FEE_WEI) -> Dictionary:
	qing = qing.to_lower()
	var wallet := Wallet.address
	print("[Pay] %s · AFFECTION.transfer(%s, %s wei) from %s" % [label, qing, fee_wei, wallet if wallet != "" else "(no wallet)"])
	var funds := await ensure_funds(fee_wei, label)
	if not funds["ok"]:
		return funds
	var data := Abi.encode_call("transfer(address,uint256)", [qing, fee_wei])
	var res: Dictionary = await Wallet.send(label, Contracts.AFFECTION, data)
	if not res["ok"]:
		return res
	var v := verify_receipt(res["receipt"], wallet, qing, fee_wei)
	if not v["ok"]:
		return Wallet.report_failure(label, "verify", "Mined in block %d, but: %s" % [res["block"], v["message"]])
	var after := await read_balance(qing, res["block"])
	print("[Pay] %s · paid and verified: %s wei in block %d (%s)" % [label, BigInt.to_decimal(v["value"]), res["block"], res["hash"]])
	return {"ok": true, "from": wallet, "hash": res["hash"], "block": res["block"], "qing_balance": after.get("balance", null), "value": v["value"]}


const TOPUP_WEI := "10000000000000000000"  # moved from the LAU when the wallet is short: 10 plays


## The wallet must hold the fee itself (AFFECTION.transfer spends msg.sender's
## balance; ERC20InsufficientBalance otherwise). Many players keep their Ⓐ on
## their LAU, so when the wallet is short and the session's LAU holds enough,
## this moves up to TOPUP_WEI with LAU.Withdraw(AFFECTION, amount) (the LAU's
## owner only; the LAU transfers to its owner) through the same write rule, and
## checks AFFECTION's Transfer(LAU → wallet) in the receipt. {ok} or {ok:false, stage:"funds", message}.
static func ensure_funds(fee_wei: String = FEE_WEI, label: String = "Payment") -> Dictionary:
	var wallet := Wallet.address
	if wallet == "":
		return {"ok": true}  # Wallet.send reports the missing wallet
	var fee := BigInt.from_decimal(fee_wei)
	var wb := await read_balance(wallet)
	if not wb["ok"]:
		print("[Pay] %s · the wallet's balance could not be read; the simulation decides" % label)
		return {"ok": true}  # can't tell: the simulation decides
	if BigInt.cmp(wb["balance"], fee) >= 0:
		return {"ok": true}
	var ps = Session.player
	var lau: String = ps.lau if ps != null and ps.has_lau() else ""
	if lau == "":
		return Wallet.report_failure(label, "funds", "This wallet holds %s and has no LAU to draw from; a play costs %s." % [fmt(wb["balance"]), fee_text()])
	var lb := await read_balance(lau)
	var need := BigInt.sub(fee, wb["balance"])
	if not lb["ok"]:
		return Wallet.report_failure(label, "funds", "This wallet holds %s; your LAU's balance could not be read. A play costs %s." % [fmt(wb["balance"]), fee_text()])
	if BigInt.cmp(lb["balance"], need) < 0:
		return Wallet.report_failure(label, "funds", "This wallet holds %s and your LAU %s holds %s; a play costs %s." % [
			fmt(wb["balance"]), _lau_label(ps), fmt(lb["balance"]), fee_text()])
	print("[Pay] %s · the wallet holds %s; moving some from the LAU first" % [label, fmt(wb["balance"])])
	var amount := BigInt.from_decimal(TOPUP_WEI)
	if BigInt.cmp(lb["balance"], amount) < 0:
		amount = lb["balance"]
	if BigInt.cmp(amount, need) < 0:
		amount = need
	var data := Abi.encode_call("Withdraw(address,uint256)", [Contracts.AFFECTION, BigInt.to_decimal(amount)])
	var res: Dictionary = await Wallet.send("Move %s from your LAU %s to this wallet (for 1 Ⓐ plays)" % [fmt(amount), _lau_label(ps)], lau, data)
	if not res["ok"]:
		res["stage"] = "funds · " + String(res.get("stage", ""))
		return res
	var v := verify_receipt(res["receipt"], lau, wallet, BigInt.to_decimal(amount))
	if not v["ok"]:
		return Wallet.report_failure(label, "funds", "Withdraw mined in block %d, but: %s" % [res["block"], v["message"]])
	return {"ok": true, "moved": amount, "block": res["block"]}


static func _lau_label(ps) -> String:
	var n := String(ps.lau_name) if ps != null else ""
	return n if n != "" else ArcadeScores.short(String(ps.lau)) if ps != null else ""


# --- The local credit ledger (one entry per verified payment) ---------------

static func _load() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(LEDGER)
	return c


static func _key(wallet: String, qing: String) -> String:
	return "%s@%s" % [wallet.to_lower(), qing.to_lower()]


static func add_credit(wallet: String, qing: String, tx: String, block: int) -> void:
	var c := _load()
	var list: Array = c.get_value("credits", _key(wallet, qing), [])
	for e in list:
		if e["tx"] == tx:
			return
	list.append({"tx": tx, "block": block, "used": false})
	c.set_value("credits", _key(wallet, qing), list)
	c.save(LEDGER)


## Unspent credits at this QING for this wallet.
static func credits(wallet: String, qing: String) -> int:
	if wallet == "":
		return 0
	var n := 0
	for e in _load().get_value("credits", _key(wallet, qing), []):
		if not e["used"]:
			n += 1
	return n


## Spends the oldest unspent credit; returns it ({tx, block}) or {} if none.
static func use_credit(wallet: String, qing: String) -> Dictionary:
	var c := _load()
	var list: Array = c.get_value("credits", _key(wallet, qing), [])
	for e in list:
		if not e["used"]:
			e["used"] = true
			c.set_value("credits", _key(wallet, qing), list)
			c.save(LEDGER)
			return e
	return {}
