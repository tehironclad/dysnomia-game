class_name FairProgress
extends RefCounted
## Which of the seven fair games a wallet has played (paid) at a QING, read from the chain.
##
## Each game's ticket is 1 Ⓐ plus its code in wei (MidwaySim.code: striker 1 … saat 7), so a
## ticket says which stall it bought: AFFECTION Transfer(wallet → QING, 1e18 + k). The UI still
## shows "1 Ⓐ". Progress = the k's found by eth_getLogs on AFFECTION with topics
## [Transfer, wallet, QING] from FROM_BLOCK (no coded ticket can be older). All seven unlock
## the Upsilon Rocket for that wallet at that QING.
##
## Cached per wallet@QING in user:// with the block it was read to (past logs never change), and
## only the newer tail is read after that. A failed read is never cached.

const ORDER := ["striker", "entropy", "regolith", "crystal", "motzkin", "waat", "saat"]
const FROM_BLOCK := 28136000  ## the coded ticket starts here (chain head when it shipped: 28,136,751)
const FILE := "user://fair_progress.cfg"
const ONE := "1000000000000000000"


## The ticket price of a game in wei: 1 Ⓐ + its code.
static func fee_wei(game: String) -> String:
	return BigInt.to_decimal(BigInt.add(BigInt.from_decimal(ONE), BigInt.from_int(maxi(0, MidwaySim.code(game)))))


## The game code a transfer value carries (1..7), or 0 when it isn't a coded ticket.
static func code_of(value: PackedInt64Array) -> int:
	var one := BigInt.from_decimal(ONE)
	if BigInt.cmp(value, one) <= 0:
		return 0
	var k := BigInt.sub(value, one)
	if not BigInt.fits_int(k):
		return 0
	var n := BigInt.to_int(k)
	return n if n >= 1 and n <= ORDER.size() else 0


## Codes found in AFFECTION Transfer logs (already filtered to wallet → QING by topics).
static func codes_from_logs(logs: Array) -> Array:
	var out: Array = []
	for lg in logs:
		if String(lg.get("address", "")).to_lower() != Contracts.AFFECTION:
			continue
		var t: Array = lg.get("topics", [])
		if t.size() < 3 or String(t[0]).to_lower() != Contracts.TOPIC_TRANSFER:
			continue
		var k := code_of(BigInt.from_hex(String(lg.get("data", "0x0"))))
		if k > 0 and not out.has(k):
			out.append(k)
	out.sort()
	return out


static func merge(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for k in b:
		if not out.has(int(k)):
			out.append(int(k))
	out.sort()
	return out


static func unlocked(codes: Array) -> bool:
	for i in ORDER.size():
		if not codes.has(i + 1):
			return false
	return true


## The next game not yet played (its id), "" when all are.
static func next_game(codes: Array) -> String:
	for i in ORDER.size():
		if not codes.has(i + 1):
			return ORDER[i]
	return ""


## "Rocket: 4 / 7 games played · next: Crystal Shy"
static func text(codes: Array) -> String:
	var n := 0
	for i in ORDER.size():
		if codes.has(i + 1):
			n += 1
	if n >= ORDER.size():
		return "Rocket: 7 / 7 games played · unlocked"
	return "Rocket: %d / %d games played · next: %s" % [n, ORDER.size(), MidwayGame.title(next_game(codes)).capitalize()]


static func topics(wallet: String, qing: String) -> Array:
	return [Contracts.TOPIC_TRANSFER, "0x" + Abi.strip0x(wallet).to_lower().lpad(64, "0"), "0x" + Abi.strip0x(qing).to_lower().lpad(64, "0")]


# --- The cache ------------------------------------------------------------------------------

static func _key(wallet: String, qing: String) -> String:
	return "%s@%s" % [wallet.to_lower(), qing.to_lower()]


## {codes, block}: block -1 when nothing was read yet.
static func cached(wallet: String, qing: String) -> Dictionary:
	var c := ConfigFile.new()
	c.load(FILE)
	var v = c.get_value("progress", _key(wallet, qing), {})
	if not (v is Dictionary) or not v.has("block"):
		return {"codes": [], "block": -1}
	return {"codes": Array(v.get("codes", [])), "block": int(v["block"])}


static func _save(wallet: String, qing: String, codes: Array, block: int) -> void:
	var c := ConfigFile.new()
	c.load(FILE)
	c.set_value("progress", _key(wallet, qing), {"codes": codes, "block": block})
	c.save(FILE)


## A ticket whose receipt ArcadePay verified: its code counts now (the block stays where the
## logs were read to, so the next refresh still reads that block).
static func add_verified(wallet: String, qing: String, code: int, _block: int) -> void:
	if code < 1 or code > ORDER.size():
		return
	var c := cached(wallet, qing)
	_save(wallet, qing, merge(c["codes"], [code]), int(c["block"]))


## Reads the newer tail of Transfer(wallet → QING) logs and merges it into the cache.
## {ok, codes, block (read to), error?}; on failure the cached codes with ok false.
static func refresh(wallet: String, qing: String) -> Dictionary:
	var c := cached(wallet, qing)
	var head: int = await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "codes": c["codes"], "block": c["block"], "error": "the chain head could not be read"}
	var from := maxi(FROM_BLOCK, int(c["block"]) + 1)
	if from > head:
		return {"ok": true, "codes": c["codes"], "block": int(c["block"])}
	var r: Dictionary = await Chain.logs.scan(Contracts.AFFECTION, topics(wallet, qing), from, head)
	if not r["ok"]:
		return {"ok": false, "codes": c["codes"], "block": c["block"], "error": "eth_getLogs failed"}
	var codes := merge(c["codes"], codes_from_logs(r["logs"]))
	_save(wallet, qing, codes, head)
	return {"ok": true, "codes": codes, "block": head}
