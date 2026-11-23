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
	qing = qing.to_lower()
	var wallet := Wallet.address
	var data := Abi.encode_call("transfer(address,uint256)", [qing, FEE_WEI])
	var res: Dictionary = await Wallet.send("Arcade credit at %s (%s)" % [place_name, fee_text()], Contracts.AFFECTION, data)
	if not res["ok"]:
		return res
	var v := verify_receipt(res["receipt"], wallet, qing)
	if not v["ok"]:
		return {"ok": false, "stage": "verify", "message": "Mined in block %d, but: %s" % [res["block"], v["message"]]}
	var after := await read_balance(qing, res["block"])
	add_credit(wallet, qing, res["hash"], res["block"])
	return {"ok": true, "hash": res["hash"], "block": res["block"], "qing_balance": after.get("balance", null)}


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
