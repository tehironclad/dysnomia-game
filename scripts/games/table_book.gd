class_name TableBook
extends RefCounted
## Pool and Twenty-One between players, played in a room's chat (QING room
## lines, CHOA.Chat). Every challenge, accept and move is a line anyone can
## read on the chain; every machine replays them to the same table.
##
## Lines (the text of a room line):
##   🎱 challenge anyone stake 5 Ⓐ        🃏 challenge 0x<wallet> stake 0.5 Ⓐ
##   🎱 #<id> accept    🎱 #<id> shot <dx> <dy> <power>    🃏 #<id> hit | stand
##   #<id> concede | decline | forfeit   (with the game's emoji in front)
## The id is the first 8 hex digits of the challenge line's transaction hash.
##
## Who said it: the wallet that signed the line's transaction (tx.from), read
## from the chain. Display names are not unique, so they are never trusted.
##
## Wagers are honour-bound: there is no escrow contract. When a game with a
## stake ends, the loser owes the stake in Ⓐ; settle() reads AFFECTION
## Transfer(loser → winner) logs after the game's last block, and everyone
## sees ✓ paid or ⚠ unpaid next to that wallet.

signal changed

const POOL := "🎱"
const CARDS := "🃏"
const TIMEOUT_BLOCKS := 8640  # about a day at 10 s a block: after that the other player may claim the game
const ANYONE := ""

var qing := ""
var matches: Array = []  # chain order
var by_id := {}
var names := {}  # wallet → last name seen on its lines
var head := -1
var _seen := {}
var _queue: Array = []
var _busy := false

static var _from_cache := {}  # tx hash → wallet
static var _hash_cache := {}  # block → block hash
static var _re_challenge: RegEx
static var _re_move: RegEx


static func _regexes() -> void:
	if _re_challenge == null:
		_re_challenge = RegEx.create_from_string("^(🎱|🃏) challenge (anyone|0x[0-9a-fA-F]{40})(?: stake ([0-9]+(?:\\.[0-9]+)?) ?Ⓐ)?\\s*$")
		_re_move = RegEx.create_from_string("^(🎱|🃏) #([0-9a-f]{8}) (accept|decline|concede|forfeit|hit|stand|shot (-?[0-9]+) (-?[0-9]+) ([0-9]+))\\s*$")


## Parses a line's text. {} if it isn't a table line; else
## {kind: "pool"|"cards", op: "challenge"|"accept"|…, …}.
static func parse(text: String) -> Dictionary:
	_regexes()
	text = text.strip_edges()
	var m := _re_challenge.search(text)
	if m:
		var who := m.get_string(2).to_lower()
		return {"kind": "pool" if m.get_string(1) == POOL else "cards", "op": "challenge",
			"invite": ANYONE if who == "anyone" else who, "stake": stake_wei(m.get_string(3))}
	m = _re_move.search(text)
	if m:
		var op := m.get_string(3)
		var out := {"kind": "pool" if m.get_string(1) == POOL else "cards", "id": m.get_string(2), "op": op.split(" ")[0]}
		if out["op"] == "shot":
			out["dx"] = clampi(int(m.get_string(4)), -100000, 100000)
			out["dy"] = clampi(int(m.get_string(5)), -100000, 100000)
			out["power"] = clampi(int(m.get_string(6)), 1, 1000)
		return out
	return {}


## "5" / "0.25" Ⓐ → wei (18 decimals). "" → 0.
static func stake_wei(s: String) -> PackedInt64Array:
	if s == "":
		return BigInt.zero()
	var parts := s.split(".")
	var frac := (parts[1] if parts.size() > 1 else "").left(18).rpad(18, "0")
	return BigInt.from_decimal((parts[0] + frac).lstrip("0") if (parts[0] + frac).lstrip("0") != "" else "0")


static func challenge_text(kind: String, invite: String, stake: String) -> String:
	var who := "anyone" if invite == ANYONE else invite.to_lower()
	var s := stake.strip_edges()
	return "%s challenge %s%s" % [POOL if kind == "pool" else CARDS, who, (" stake %s Ⓐ" % s) if s != "" and s != "0" else ""]


static func move_text(kind: String, id: String, op: String) -> String:
	return "%s #%s %s" % [POOL if kind == "pool" else CARDS, id, op]


static func shot_text(id: String, dx: int, dy: int, power: int) -> String:
	return move_text("pool", id, "shot %d %d %d" % [dx, dy, clampi(power, 1, 1000)])


static func game_id(tx: String) -> String:
	return Abi.strip0x(tx).to_lower().left(8)


func _init(p_qing: String = "") -> void:
	qing = p_qing.to_lower()


# --- Feeding lines ----------------------------------------------------------

## Room lines (chain order), as ChatLog gives them. Table lines are resolved
## (signer, block hash) and replayed in order; others are skipped.
func feed(lines: Array) -> void:
	for l in lines:
		var k := "%s:%d" % [l["tx"], l["log_index"]]
		if _seen.has(k):
			continue
		_seen[k] = true
		if parse(String(l.get("text", ""))).is_empty():
			continue
		_queue.append(l)
	if _busy:
		return
	_busy = true
	var any := false
	while not _queue.is_empty():
		var l: Dictionary = _queue.pop_front()
		var p := parse(String(l["text"]))
		var from := await tx_from(String(l["tx"]))
		if from == "":
			continue  # unreadable signer: the line can't count (shown nowhere rather than guessed)
		var hash := ""
		if p["kind"] == "cards" and (p["op"] == "accept" or p["op"] == "hit"):
			hash = await block_hash(int(l["block"]))
		var line := l.duplicate()
		line["from"] = from
		line["block_hash"] = hash
		ingest(line)
		any = true
	_busy = false
	if any:
		changed.emit()


## The wallet that signed a transaction (eth_getTransactionByHash → from).
static func tx_from(tx: String) -> String:
	if _from_cache.has(tx):
		return _from_cache[tx]
	var r: Dictionary = await Chain.rpc.request("eth_getTransactionByHash", [tx])
	if not r["ok"] or not (r["result"] is Dictionary):
		return ""
	var f := String(r["result"].get("from", "")).to_lower()
	_from_cache[tx] = f
	return f


static func block_hash(block: int) -> String:
	if _hash_cache.has(block):
		return _hash_cache[block]
	var r: Dictionary = await Chain.rpc.get_block(block)
	if not r["ok"] or not (r["result"] is Dictionary):
		return ""
	var h := String(r["result"].get("hash", ""))
	_hash_cache[block] = h
	return h


# --- Replay (pure: lines already carry from and block_hash) ----------------

## Applies one resolved line.
func ingest(l: Dictionary) -> void:
	var p := parse(String(l["text"]))
	if p.is_empty():
		return
	var from: String = l["from"]
	if String(l.get("name", "")) != "":
		names[from] = String(l["name"])
	head = maxi(head, int(l["block"]))
	if p["op"] == "challenge":
		var id := game_id(String(l["tx"]))
		if by_id.has(id) or p["invite"] == from:
			return
		var m := {"id": id, "kind": p["kind"], "challenger": from, "invite": p["invite"], "stake": p["stake"],
			"players": [from, ""], "status": "open", "game": null, "winner": "", "loser": "", "push": false,
			"created_block": int(l["block"]), "last_block": int(l["block"]), "end_block": -1, "events": [],
			"paid": null}
		matches.append(m)
		by_id[id] = m
		return
	if not by_id.has(p["id"]):
		return
	var m: Dictionary = by_id[p["id"]]
	if m["kind"] != p["kind"]:
		return
	var block := int(l["block"])
	match p["op"]:
		"accept":
			if m["status"] != "open" or from == m["challenger"] or (m["invite"] != ANYONE and from != m["invite"]):
				return
			if m["kind"] == "cards" and String(l.get("block_hash", "")) == "":
				return
			m["players"][1] = from
			m["status"] = "playing"
			m["last_block"] = block
			m["deal_block"] = block
			if m["kind"] == "pool":
				m["game"] = EightBall.new()
			else:
				var d := Duel21.new()
				d.deal(String(l["block_hash"]))
				m["game"] = d
			m["events"].append("accepted at block %d" % block)
		"decline":
			if m["status"] == "open" and (from == m["challenger"] or from == m["invite"]):
				m["status"] = "cancelled"
		"concede":
			var who := player_index(m, from)
			if m["status"] == "playing" and who >= 0:
				_finish(m, 1 - who, block, "%s conceded" % short(from))
		"forfeit":
			var who := player_index(m, from)
			if m["status"] == "playing" and who >= 0 and turn_index(m) != who and block - int(m["last_block"]) > TIMEOUT_BLOCKS:
				_finish(m, who, block, "claimed after %d blocks without a move" % (block - int(m["last_block"])))
		"shot":
			var who := player_index(m, from)
			if m["status"] != "playing" or who < 0 or m["kind"] != "pool":
				return
			var g: EightBall = m["game"]
			var before := g.sim.snapshot()
			var r := g.shot(who, p["dx"], p["dy"], p["power"])
			if not r["ok"]:
				return
			m["last_block"] = block
			m["last_shot"] = {"player": who, "dx": p["dx"], "dy": p["dy"], "power": p["power"], "block": block, "before": before, "tx": l["tx"]}
			m["events"].append(_describe_shot(r))
			if g.over():
				_finish(m, g.winner, block, String(r.get("result", "")))
		"hit", "stand":
			var who := player_index(m, from)
			if m["status"] != "playing" or who < 0 or m["kind"] != "cards":
				return
			var d: Duel21 = m["game"]
			var r := d.hit(who, String(l.get("block_hash", ""))) if p["op"] == "hit" else d.stand(who)
			if not r["ok"]:
				return
			m["last_block"] = block
			m["events"].append("%s %s%s" % [short(from), p["op"], (" → " + Duel21.card_name(r["card"]) + (" bust" if r["bust"] else "")) if r.has("card") else ""])
			if d.over():
				if d.winner == 2:
					m["status"] = "over"
					m["push"] = true
					m["end_block"] = block
				else:
					_finish(m, d.winner, block, "")


func _finish(m: Dictionary, winner_index: int, block: int, why: String) -> void:
	m["status"] = "over"
	m["winner"] = m["players"][winner_index]
	m["loser"] = m["players"][1 - winner_index]
	m["end_block"] = block
	if why != "":
		m["events"].append(why)


static func _describe_shot(r: Dictionary) -> String:
	var bits: Array = []
	var pot: Array = r["pocketed"].filter(func(b): return b != 0)
	if not pot.is_empty():
		bits.append("potted " + ", ".join(pot.map(func(b): return str(b))))
	if r["scratch"]:
		bits.append("scratch")
	elif r["foul"]:
		bits.append("foul")
	if r.has("assigned"):
		bits.append("takes " + String(r["assigned"]))
	return "shot: " + ("; ".join(bits) if not bits.is_empty() else "nothing down")


static func player_index(m: Dictionary, wallet: String) -> int:
	return m["players"].find(wallet) if wallet != "" else -1


## Whose move it is (0/1), or -1 when nobody's.
static func turn_index(m: Dictionary) -> int:
	if m["status"] != "playing" or m["game"] == null:
		return -1
	return int(m["game"].turn)


static func short(wallet: String) -> String:
	return wallet.left(6) + "…" + wallet.right(4) if wallet.length() == 42 else wallet


func display(wallet: String) -> String:
	if wallet == "":
		return "anyone"
	return "%s (%s)" % [names[wallet], short(wallet)] if names.has(wallet) else short(wallet)


## Open challenges, live games and finished ones of `kind`, newest first.
func of_kind(kind: String) -> Array:
	var out := matches.filter(func(m): return m["kind"] == kind and m["status"] != "cancelled")
	out.reverse()
	return out


# --- Wagers -------------------------------------------------------------------

## Debts from finished games with a stake (chain order): {match, loser, winner, stake, end_block}.
func debts() -> Array:
	var out: Array = []
	for m in matches:
		if m["status"] == "over" and not m["push"] and m["winner"] != "" and not BigInt.is_zero(m["stake"]):
			out.append({"match": m, "loser": m["loser"], "winner": m["winner"], "stake": m["stake"], "end_block": m["end_block"]})
	return out


## Pure: matches transfers (chain order: {block, value}) between one loser and
## one winner against their debts (chain order). A transfer pays the oldest
## unpaid debt that ended at or before its block; any remainder carries on.
## Returns [{paid: bool, remaining, paid_block}] per debt.
static func allocate(debt_list: Array, transfers: Array) -> Array:
	var out: Array = []
	for d in debt_list:
		out.append({"paid": false, "remaining": d["stake"], "paid_block": -1})
	for t in transfers:
		var left: PackedInt64Array = t["value"]
		for i in debt_list.size():
			if BigInt.is_zero(left):
				break
			if out[i]["paid"] or int(debt_list[i]["end_block"]) > int(t["block"]):
				continue
			var rem: PackedInt64Array = out[i]["remaining"]
			if BigInt.cmp(left, rem) >= 0:
				left = BigInt.sub(left, rem)
				out[i]["remaining"] = BigInt.zero()
				out[i]["paid"] = true
				out[i]["paid_block"] = int(t["block"])
			else:
				out[i]["remaining"] = BigInt.sub(rem, left)
				left = BigInt.zero()
	return out


## Reads AFFECTION Transfer(loser → winner) logs for every debt pair and marks
## each match's "paid": true / false (null while unread or when the read failed).
func settle(to_block: int) -> void:
	var pairs := {}
	for d in debts():
		var k: String = d["loser"] + ">" + d["winner"]
		if not pairs.has(k):
			pairs[k] = []
		pairs[k].append(d)
	for k in pairs:
		var list: Array = pairs[k]
		var from_block: int = list[0]["end_block"]
		var topics := [Contracts.TOPIC_TRANSFER, "0x" + Abi.strip0x(list[0]["loser"]).lpad(64, "0"), "0x" + Abi.strip0x(list[0]["winner"]).lpad(64, "0")]
		var r: Dictionary = await Chain.logs.scan(Contracts.AFFECTION, topics, from_block, to_block)
		if not r["ok"]:
			for d in list:
				d["match"]["paid"] = null
			continue
		var transfers: Array = []
		for lg in r["logs"]:
			transfers.append({"block": String(lg.get("blockNumber", "0x0")).hex_to_int(), "value": BigInt.from_hex(String(lg.get("data", "0x0")))})
		var res := allocate(list, transfers)
		for i in list.size():
			list[i]["match"]["paid"] = res[i]["paid"]
			list[i]["match"]["paid_block"] = res[i]["paid_block"]
	changed.emit()


## What `wallet` still owes (unpaid debts), for the ⚠ next to its name.
func unpaid_by(wallet: String) -> Array:
	return debts().filter(func(d): return d["loser"] == wallet and d["match"]["paid"] == false)


# --- Writes ---------------------------------------------------------------------

## Posts a table line in the room: CHOA.Chat(QING, text) through the write
## pipeline, then reads the line back from that block. {ok, line} or the failure.
static func post(p_qing: String, text: String, label: String) -> Dictionary:
	var res: Dictionary = await Wallet.send(label, Contracts.CHOA, Abi.encode_call("Chat(address,string)", [p_qing, text]))
	if not res["ok"]:
		return res
	var r: Dictionary = await ChatLog.tail(p_qing, true, res["block"] - 1, res["block"])
	var mine: Array = r["lines"].filter(func(l): return l["tx"] == res["hash"])
	if mine.is_empty():
		return {"ok": false, "stage": "verify", "message": "Mined in block %d, but the line was not found in that block's logs: —." % res["block"]}
	return {"ok": true, "line": mine[0], "block": res["block"], "hash": res["hash"]}


## The loser pays a stake: AFFECTION.transfer(winner, stake), then the
## receipt's Transfer log is checked. {ok, block} or the failure.
static func pay_debt(winner: String, stake: PackedInt64Array) -> Dictionary:
	var wallet := Wallet.address
	var res: Dictionary = await Wallet.send("Pay %s to %s" % [ArcadePay.fmt(stake), short(winner)], Contracts.AFFECTION,
		Abi.encode_call("transfer(address,uint256)", [winner, stake]))
	if not res["ok"]:
		return res
	var v := ArcadePay.verify_receipt(res["receipt"], wallet, winner, BigInt.to_decimal(stake))
	if not v["ok"]:
		return {"ok": false, "stage": "verify", "message": v["message"]}
	return {"ok": true, "block": res["block"], "hash": res["hash"]}
