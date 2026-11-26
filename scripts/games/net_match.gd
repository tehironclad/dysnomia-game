class_name NetMatch
extends RefCounted
## A head-to-head game played over the game server (docs/SERVER.md §8b), replayed
## the same way on both players' machines. The server only orders and stamps the
## moves (seq, who, op, integer args, its clock in ms); every machine replays that
## log through the same deterministic rules TableBook uses for room lines:
##   pool   a shot is [dx, dy, power] into EightBall/PoolSim (integer physics);
##   cards  Duel21, each card from a block hash. The block is the first one whose
##          timestamp is at least CARD_MARGIN_S after the server stamped the move
##          that asks for it (the deal: the move that started the game; a hit:
##          the hit). Nobody, the server included, can know that hash when the move
##          is made; both machines read the same block from the chain (BlockClock).
## Pure (no autoloads: the bot and the server's tests use it too): block hashes are passed in. `m` has the shape of a TableBook match, so
## the tables (PoolSeat, CardSeat, GamesPlace) draw it like any other game, plus
## {net: true, names, seated, stake_state, stake_ok, end_t, moves}.
##
## Stakes are honour-bound and confirmed by both: while a stake is proposed the
## match is "confirm"; stake_ok from both → "playing" with the stake; stake_no from
## either → "playing" without one. Game moves before that are ignored.

const CARD_MARGIN_S := 2
const IDLE_CLAIM_MS := 600000  # 10 min without a move: the waiting player may claim the game

var rec := {}        # the server's record: {id, game, players, names, stake, room, door, created, log, …}
var m := {}          # the TableBook-shaped match
var applied := 0     # log entries replayed so far
var deal_anchor := -1  # cards: the unix second whose first block deals; -1 = no deal pending
var _last_move_t := 0


func _init(record: Dictionary = {}) -> void:
	rec = record
	var players: Array = record.get("players", ["", ""]) if record.get("players") is Array and record["players"].size() == 2 else ["", ""]
	var names: Array = record.get("names", ["", ""]) if record.get("names") is Array and record["names"].size() == 2 else ["", ""]
	# The record comes from the game server: wallets and names are shape-checked, and a
	# stake that is not a valid amount of Ⓐ (InviteBook's rule) is no stake at all.
	players = [NetProto.clean_wallet(String(players[0])), NetProto.clean_wallet(String(players[1]))]
	names = [NetProto.clean_text(String(names[0]), NetProto.NAME_MAX_CHARS), NetProto.clean_text(String(names[1]), NetProto.NAME_MAX_CHARS)]
	var stake := InviteBook.clean_stake(NetProto.str_of(record.get("stake", "")))
	if stake == "!":
		stake = ""
	m = {"id": NetProto.str_of(record.get("id", "")), "kind": NetProto.str_of(record.get("game", "")), "net": true,
		"challenger": String(players[0]), "invite": String(players[1]), "stake": stake_wei(stake), "stake_text": stake,
		"players": [String(players[0]), String(players[1])], "names": [String(names[0]), String(names[1])],
		"status": "confirm" if stake != "" else "playing", "game": null, "winner": "", "loser": "", "push": false,
		"created_block": -1, "last_block": -1, "end_block": -1, "deal_block": -1, "events": [], "paid": null,
		"seated": [false, false], "stake_ok": [false, false], "stake_state": "proposed" if stake != "" else "none",
		"end_t": -1, "moves": 0, "room": NetProto.str_of(record.get("room", "")), "door": NetProto.str_of(record.get("door", "arcade"))}
	_last_move_t = NetProto.int_of(record.get("created", 0))
	m["game"] = EightBall.new() if m["kind"] == "pool" else Duel21.new()
	if m["status"] == "playing":
		_begin(_last_move_t)


# --- helpers (TableBook's, without its chain reads) ------------------------------

## "5" / "0.25" Ⓐ → wei (18 decimals). "" → 0.
static func stake_wei(s: String) -> PackedInt64Array:
	if s == "":
		return BigInt.zero()
	var parts := s.split(".")
	var digits := (parts[0] + (parts[1] if parts.size() > 1 else "").left(18).rpad(18, "0")).lstrip("0")
	return BigInt.from_decimal(digits if digits != "" else "0")


static func fmt(wei: PackedInt64Array) -> String:
	return "%s Ⓐ" % TokenFormat.wei_to_tokens(wei)


static func short(wallet: String) -> String:
	return wallet.left(6) + "…" + wallet.right(4) if wallet.length() == 42 else wallet


## Whose move it is (0/1), or -1 when nobody's.
static func turn_of(match_dict: Dictionary) -> int:
	if match_dict.get("status") != "playing" or match_dict.get("game") == null:
		return -1
	return int(match_dict["game"].turn)


static func describe_shot(r: Dictionary) -> String:
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


func id() -> String:
	return String(m["id"])


func log_entries() -> Array:
	return rec.get("log", [])


## The server's ms stamp of the last move that counted (or of the start): the idle clock for a claim.
func last_move_t() -> int:
	return _last_move_t


## True when `who` may claim the game now (`now_ms` on the server's clock, roughly ours).
func claimable_by(who: int, now_ms: int) -> bool:
	return m["status"] == "playing" and turn_of(m) >= 0 and turn_of(m) != who and now_ms - _last_move_t >= IDLE_CLAIM_MS


func over() -> bool:
	return m["status"] == "over"


## The player index of `wallet` (-1 if not playing).
func index_of(wallet: String) -> int:
	return (m["players"] as Array).find(wallet.to_lower()) if wallet != "" else -1


func name_of(i: int) -> String:
	var n := String(m["names"][i])
	return n if n != "" else short(String(m["players"][i]))


static func anchor_of(t_ms: int) -> int:
	return int(ceil(t_ms / 1000.0)) + CARD_MARGIN_S


func _begin(t_ms: int) -> void:
	m["status"] = "playing"
	_last_move_t = t_ms
	if m["kind"] == "cards":
		deal_anchor = anchor_of(t_ms)
		m["events"].append("the deal: the first block at or after %s" % _clock(deal_anchor))
	else:
		m["events"].append("the break: %s" % name_of(0))


static func _clock(unix_s: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_s, true) + " UTC"


## Cards: the replay waits for this block (the deal) before any more moves. -1 = nothing pending.
func needs_block() -> int:
	return deal_anchor


## The deal's block: {hash, number}. Returns false if the hash is unusable.
func deal(block: Dictionary) -> bool:
	if deal_anchor < 0:
		return false
	var h := NetProto.str_of(block.get("hash", ""))
	if not (h.begins_with("0x") and h.length() == 66):
		return false
	(m["game"] as Duel21).deal(h)
	deal_anchor = -1
	m["deal_block"] = NetProto.int_of(block.get("number", -1))
	m["created_block"] = m["deal_block"]
	m["last_block"] = m["deal_block"]
	m["events"].append("dealt from block %d" % m["deal_block"])
	return true


## The unix second whose first block draws a card for log entry `e`, or -1 if it draws none.
func hash_anchor(e: Dictionary) -> int:
	if m["kind"] != "cards" or m["status"] != "playing" or NetProto.str_of(e.get("op", "")) != "hit":
		return -1
	var d: Duel21 = m["game"]
	var who := NetProto.int_of(e.get("by", -1))
	if d.over() or not d.dealt or who != d.turn:
		return -1
	return anchor_of(NetProto.int_of(e.get("t", 0)))


## Replays one log entry ({seq, by, op, a, t}). `block` ({hash, number}) when
## hash_anchor(e) asked for one. Returns {ok, why?}; a refused move changes nothing.
func apply(e: Dictionary, block: Dictionary = {}) -> Dictionary:
	applied += 1
	m["moves"] = applied
	var who := NetProto.int_of(e.get("by", -1))
	var op := NetProto.str_of(e.get("op", ""))
	var a: Array = e.get("a", []) if e.get("a") is Array else []
	var t := NetProto.int_of(e.get("t", 0))
	if who != 0 and who != 1:
		return {"ok": false, "why": "not a player"}
	if deal_anchor >= 0:
		return {"ok": false, "why": "the deal is not read yet"}  # the caller deals first
	match op:
		"sit":
			m["seated"][who] = true
			return {"ok": true}
		"stake_ok", "stake_no":
			if m["status"] != "confirm":
				return {"ok": false, "why": "no stake to confirm"}
			if op == "stake_no":
				m["stake"] = BigInt.zero()
				m["stake_state"] = "dropped"
				m["events"].append("%s played without the stake" % name_of(who))
				_begin(t)
				return {"ok": true}
			m["stake_ok"][who] = true
			if m["stake_ok"][0] and m["stake_ok"][1]:
				m["stake_state"] = "agreed"
				m["events"].append("stake agreed: %s (honour-bound)" % fmt(m["stake"]))
				_begin(t)
			return {"ok": true}
		"concede":
			if m["status"] == "over":
				return {"ok": false, "why": "the game is over"}
			if m["status"] == "confirm":  # a stake nobody agreed to is owed by nobody
				m["stake"] = BigInt.zero()
				m["stake_state"] = "dropped"
			_finish(1 - who, t, "%s conceded" % name_of(who))
			return {"ok": true}
		"claim":
			if m["status"] != "playing" or turn_of(m) == who or t - _last_move_t < IDLE_CLAIM_MS:
				return {"ok": false, "why": "not claimable"}
			_finish(who, t, "claimed after %d s without a move" % ((t - _last_move_t) / 1000))
			return {"ok": true}
	if m["status"] != "playing":
		return {"ok": false, "why": "not playing"}
	if m["kind"] == "pool" and op == "shot" and a.size() == 3:
		var g: EightBall = m["game"]
		var before := g.sim.snapshot()
		var dx := clampi(int(a[0]), -100000, 100000)
		var dy := clampi(int(a[1]), -100000, 100000)
		var pw := clampi(int(a[2]), 1, 1000)
		var r := g.shot(who, dx, dy, pw)
		if not r["ok"]:
			return {"ok": false, "why": r["why"]}
		_last_move_t = t
		m["last_shot"] = {"player": who, "dx": dx, "dy": dy, "power": pw, "block": -1, "before": before,
			"tx": "net:%s:%d" % [m["id"], NetProto.int_of(e.get("seq", applied))]}
		m["events"].append(describe_shot(r))  # as TableBook words it: the tables call it out
		if g.over():
			_finish(g.winner, t, NetProto.str_of(r.get("result", "")))
		return {"ok": true}
	if m["kind"] == "cards" and (op == "hit" or op == "stand"):
		var d: Duel21 = m["game"]
		var r: Dictionary
		if op == "hit":
			var h := NetProto.str_of(block.get("hash", ""))
			if hash_anchor(e) < 0 or not (h.begins_with("0x") and h.length() == 66):
				return {"ok": false, "why": "no card block"}
			r = d.hit(who, h)
			if r["ok"]:
				m["last_block"] = NetProto.int_of(block.get("number", -1))
		else:
			r = d.stand(who)
		if not r["ok"]:
			return {"ok": false, "why": r.get("why", "")}
		_last_move_t = t
		m["events"].append("%s %s%s" % [name_of(who), op, (" → %s%s (block %d)" % [Duel21.card_name(r["card"]), " bust" if r["bust"] else "", m["last_block"]]) if r.has("card") else ""])
		if d.over():
			if d.winner == 2:
				m["status"] = "over"
				m["push"] = true
				m["end_t"] = t
				m["events"].append("push: %d each" % Duel21.total(d.hands[0]))
			else:
				_finish(d.winner, t, "%d vs %d" % [Duel21.total(d.hands[0]), Duel21.total(d.hands[1])])
		return {"ok": true}
	return {"ok": false, "why": "unknown move"}


func _finish(winner_index: int, t: int, why: String) -> void:
	m["status"] = "over"
	m["winner"] = m["players"][winner_index]
	m["loser"] = m["players"][1 - winner_index]
	m["end_t"] = t
	if why != "":
		m["events"].append(why)
	m["events"].append("%s won" % name_of(winner_index))


## Who won: 0 / 1, 2 for a push, -1 while not over.
func winner_index() -> int:
	if not over():
		return -1
	if m["push"]:
		return 2
	return int(m["players"].find(m["winner"]))


## A fingerprint of the replayed outcome. Both machines send theirs to the server
## (C_RESULT); equal fingerprints mean both tables agree on every ball and card.
func digest() -> String:
	var state := ""
	if m["kind"] == "pool":
		state = str(Array((m["game"] as EightBall).sim.snapshot()))
	else:
		state = str((m["game"] as Duel21).hands)
	return ("%s|%s|%d|%s" % [m["id"], m["status"], winner_index(), state]).sha256_text().left(32)


## Pure replay of a whole log with a hash source: `hash_for.call(unix_s)` → {hash, number}.
## For tests and tools; the game replays as moves arrive (Invites).
static func replay(record: Dictionary, hash_for: Callable) -> NetMatch:
	var nm := NetMatch.new(record)
	for e in record.get("log", []):
		if nm.needs_block() >= 0:
			nm.deal(hash_for.call(nm.needs_block()))
		var a := nm.hash_anchor(e)
		nm.apply(e, hash_for.call(a) if a >= 0 else {})
	if nm.needs_block() >= 0:
		nm.deal(hash_for.call(nm.needs_block()))
	return nm
