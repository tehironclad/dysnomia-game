class_name FairProgress
extends RefCounted
## Which of the seven fair games a wallet has played (paid) at a QING, read from the chain.
##
## Each ticket's amount says what it bought (TicketCode): one play is 1 Ⓐ + the game's code in
## wei (MidwaySim.code: striker 1 … saat 7); a strip is 10 Ⓐ + (10 × 100 + code) wei, and an
## any-game strip 10 Ⓐ + 1008 wei. The rocket's rule (LEARNINGS §14 "Ticket strips"):
##   a game counts as played when the chain shows
##   (a) a ticket for that game: a single ticket or a per-game strip, AFFECTION Transfer(wallet →
##       QING) read by eth_getLogs with topics [Transfer, wallet, QING] from FROM_BLOCK, or
##   (b) a verified 🎪 room line of that game signed by the wallet (FairBoard): this is how an
##       any-game strip's plays count, one game per posted play.
## All seven unlock the Upsilon Rocket for that wallet at that QING. Old tickets keep counting.
##
## Cached per wallet@QING in user:// with the block it was read to (past logs never change), and
## only the newer tail is read after that. A failed read is never cached. The strips found in the
## logs are cached too: ArcadePay.sync_strip makes the plays left derivable on any computer.

const ORDER := ["striker", "entropy", "regolith", "crystal", "motzkin", "waat", "saat"]
const FROM_BLOCK := 28136000  ## the coded ticket starts here (chain head when it shipped: 28,136,751)
const FILE := "user://fair_progress.cfg"
const ONE := "1000000000000000000"


## The single-ticket price of a game in wei: Prices.PLAY Ⓐ + its code (1 Ⓐ + k today).
static func fee_wei(game: String) -> String:
	return Prices.ticket_wei(maxi(0, MidwaySim.code(game)), 1)


## A strip of Prices.STRIP_PLAYS for one game (or "any"): its price + code, in wei.
static func strip_wei(game: String) -> String:
	return Prices.ticket_wei(strip_item(game), Prices.STRIP_PLAYS)


## The ticket item for a game's strip: its code, or TicketCode.FAIR_ANY for "any".
static func strip_item(game: String) -> int:
	return TicketCode.FAIR_ANY if game == "any" else MidwaySim.code(game)


## The game code (1..7) a transfer value pays for: a single ticket or a per-game strip that covers
## its price; 0 for anything else (a plain Ⓐ, an any-game strip, the rocket, a drink, no code).
static func code_of(value: PackedInt64Array) -> int:
	var d := TicketCode.decode(value)
	if not d["ok"] or not Prices.covers(d):
		return 0
	var k := int(d["item"])
	return k if k >= 1 and k <= ORDER.size() else 0


static func _transfers(logs: Array) -> Array:
	var out: Array = []
	for lg in logs:
		if String(lg.get("address", "")).to_lower() != Contracts.AFFECTION:
			continue
		var t: Array = lg.get("topics", [])
		if t.size() < 3 or String(t[0]).to_lower() != Contracts.TOPIC_TRANSFER:
			continue
		out.append(lg)
	return out


## Codes found in AFFECTION Transfer logs (already filtered to wallet → QING by topics): rule (a).
static func codes_from_logs(logs: Array) -> Array:
	var out: Array = []
	for lg in _transfers(logs):
		var k := code_of(BigInt.from_hex(String(lg.get("data", "0x0"))))
		if k > 0 and not out.has(k):
			out.append(k)
	out.sort()
	return out


## Fair strips in those logs (per-game and any-game, paid in full): [{tx, block, item, plays}].
static func strips_from_logs(logs: Array) -> Array:
	var out: Array = []
	for lg in _transfers(logs):
		var d := TicketCode.decode(BigInt.from_hex(String(lg.get("data", "0x0"))))
		if not d["ok"] or not d["strip"] or not TicketCode.is_fair(int(d["item"])) or not Prices.covers(d):
			continue
		out.append({"tx": String(lg.get("transactionHash", "")).to_lower(), "block": String(lg.get("blockNumber", "0x0")).hex_to_int(),
			"item": int(d["item"]), "plays": int(d["plays"])})
	return out


## Rule (b): the games of verified 🎪 lines signed by `wallet` (FairBoard rows).
static func posted_codes(rows: Array, wallet: String) -> Array:
	var out: Array = []
	var w := wallet.to_lower()
	for r in rows:
		if r.get("verified", false) and String(r.get("wallet", "")).to_lower() == w:
			var k := MidwaySim.code(String(r.get("game", "")))
			if k > 0 and not out.has(k):
				out.append(k)
	out.sort()
	return out


## The play indices of strip `tx` that `wallet` has posted (verified rows): spent, from the chain.
static func posted_indices(rows: Array, wallet: String, tx: String) -> Array:
	var out: Array = []
	for r in rows:
		if r.get("verified", false) and String(r.get("wallet", "")).to_lower() == wallet.to_lower() \
				and String(r.get("ticket", "")) == tx.to_lower() and int(r.get("index", -1)) >= 0:
			out.append(int(r["index"]))
	return out


## Every game played: (a) ∪ (b).
static func played(log_codes: Array, rows: Array, wallet: String) -> Array:
	return merge(log_codes, posted_codes(rows, wallet))


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


## {codes (rule a), strips ([{tx, block, item, plays}]), block}: block -1 when nothing was read yet.
static func cached(wallet: String, qing: String) -> Dictionary:
	var c := ConfigFile.new()
	c.load(FILE)
	var v = c.get_value("progress", _key(wallet, qing), {})
	if not (v is Dictionary) or not v.has("block"):
		return {"codes": [], "strips": [], "block": -1}
	return {"codes": Array(v.get("codes", [])), "strips": Array(v.get("strips", [])), "block": int(v["block"])}


static func _save(wallet: String, qing: String, codes: Array, block: int, strips: Array = []) -> void:
	var c := ConfigFile.new()
	c.load(FILE)
	c.set_value("progress", _key(wallet, qing), {"codes": codes, "block": block, "strips": strips})
	c.save(FILE)


static func _merge_strips(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for s in b:
		if out.filter(func(x): return String(x["tx"]) == String(s["tx"])).is_empty():
			out.append(s)
	return out


## A ticket whose receipt ArcadePay verified: its code counts now (the block stays where the
## logs were read to, so the next refresh still reads that block).
static func add_verified(wallet: String, qing: String, code: int, _block: int) -> void:
	if code < 1 or code > ORDER.size():
		return
	var c := cached(wallet, qing)
	_save(wallet, qing, merge(c["codes"], [code]), int(c["block"]), c["strips"])


## Reads the newer tail of Transfer(wallet → QING) logs and merges it into the cache.
## {ok, codes, strips, block (read to), error?}; on failure the cached ones with ok false.
static func refresh(wallet: String, qing: String) -> Dictionary:
	var c := cached(wallet, qing)
	var head: int = await Chain.refresh_head()
	if head < 0:
		return {"ok": false, "codes": c["codes"], "strips": c["strips"], "block": c["block"], "error": "the chain head could not be read"}
	var from := maxi(FROM_BLOCK, int(c["block"]) + 1)
	if from > head:
		return {"ok": true, "codes": c["codes"], "strips": c["strips"], "block": int(c["block"])}
	var r: Dictionary = await Chain.logs.scan(Contracts.AFFECTION, topics(wallet, qing), from, head)
	if not r["ok"]:
		return {"ok": false, "codes": c["codes"], "strips": c["strips"], "block": c["block"], "error": "eth_getLogs failed"}
	var codes := merge(c["codes"], codes_from_logs(r["logs"]))
	var strips := _merge_strips(c["strips"], strips_from_logs(r["logs"]))
	_save(wallet, qing, codes, head, strips)
	return {"ok": true, "codes": codes, "strips": strips, "block": head}
