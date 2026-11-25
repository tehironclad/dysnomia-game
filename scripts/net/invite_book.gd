class_name InviteBook
extends RefCounted
## Game invites between signed-in players (docs/SERVER.md §8b). Pure: the game
## server holds the authoritative book; the tests drive it with their own clock.
##
##   pending ──accept (by `to`)──▶ accepted   (the server opens a match)
##           ──decline (by `to`)─▶ declined
##           ──cancel (by `from`)▶ cancelled
##           ──TTL_S passes──────▶ expired
## Every other transition is refused. An invite carries an optional stake in Ⓐ
## (a decimal string, "" = none): accepting it only agrees to *propose* it; both
## players still confirm it at the table (NetMatch: stake_ok / stake_no).
##
## Games: GAMES lists what can be played head to head and which moves each one
## takes. Pool and Twenty-One today. An arcade or fair head-to-head plugs in the
## same way: an id such as "arcade:void_lanes" or "fair:striker" with its moves
## (e.g. ["score"]) here, and its rules in NetMatch.apply. The server needs no
## other change: it relays moves it does not understand, it only checks the list.

const TTL_S := 90                 # an unanswered invite expires after this
const KEEP_S := 600               # finished invites are kept this long (reconnects see them)
const MAX_OPEN_PER_WALLET := 3    # invites one wallet may have pending at once
const MAX_STAKE_DIGITS := 7       # whole Ⓐ: at most 9,999,999
const STATES := ["pending", "accepted", "declined", "cancelled", "expired"]

## game id → {title, ops (the moves besides COMMON_OPS), door (the territory door its table is behind)}
const GAMES := {
	"pool": {"title": "Pool · eight-ball", "ops": ["shot"], "door": "arcade"},
	"cards": {"title": "Twenty-One", "ops": ["hit", "stand"], "door": "arcade"},
}
## Moves every game takes: sit (I'm at the table), the stake confirmations,
## concede, and claim (the waiting player claims a game idle for NetMatch.IDLE_CLAIM_MS).
const COMMON_OPS := ["sit", "stake_ok", "stake_no", "concede", "claim"]
## "Join me": not a game but a request to come to where the inviter is. Same book, limits
## and expiry; accepting opens no match: the invited player's game travels there through
## the normal warp and door (Invites.go_join). `door` says where in the QING room `room`:
## "" the territory itself, "room" the QING's hall, "arcade" its arcade (or Sunny's Pub).
const JOIN := "join"
const JOIN_DOORS := {"": "", "room": "hall", "arcade": "arcade"}

var invites := {}  # id → invite


static func game_ok(game: String) -> bool:
	return GAMES.has(game) or game == JOIN


static func title_of(game: String) -> String:
	if game == JOIN:
		return "Join me"
	return String(GAMES.get(game, {}).get("title", game))


## The NetEvents place a join door leads to ("" for the territory itself).
static func join_place(door: String) -> String:
	return String(JOIN_DOORS.get(door, ""))


static func ops_for(game: String) -> Array:
	if not GAMES.has(game):
		return []
	return COMMON_OPS + Array(GAMES[game]["ops"])


## A stake in Ⓐ as typed ("5", "0.25", " 2 Ⓐ"): normalised ("5", "0.25"), ""
## for none (empty or zero), or "!" when it is not a number of Ⓐ.
static func clean_stake(s: String) -> String:
	s = s.strip_edges().trim_suffix("Ⓐ").strip_edges()
	if s == "":
		return ""
	var re := RegEx.create_from_string("^([0-9]{1,%d})(?:\\.([0-9]{1,18}))?$" % MAX_STAKE_DIGITS)
	var m := re.search(s)
	if m == null:
		return "!"
	var whole := m.get_string(1).lstrip("0")
	var frac := m.get_string(2).rstrip("0")
	if whole == "" and frac == "":
		return ""
	return (whole if whole != "" else "0") + ("." + frac if frac != "" else "")


## Opens an invite. {ok, invite} or {ok: false, error}.
func create(id: String, from: String, from_name: String, to: String, to_name: String, game: String,
		stake: String, room: String, door: String, now: int) -> Dictionary:
	from = NetProto.clean_wallet(from)
	to = NetProto.clean_wallet(to)
	if from == "" or to == "":
		return {"ok": false, "error": "both players must be signed in with a wallet"}
	if from == to:
		return {"ok": false, "error": "you can't invite yourself"}
	if not game_ok(game):
		return {"ok": false, "error": "unknown game"}
	var st := clean_stake(stake)
	if st == "!":
		return {"ok": false, "error": "the stake must be a number of Ⓐ, like 5 or 0.25"}
	room = NetProto.clean_room(room)
	if room == "" or room.contains("/"):
		return {"ok": false, "error": "the table's territory is not a QING address"}
	if game == JOIN:
		if not JOIN_DOORS.has(door):
			return {"ok": false, "error": "you can't be joined there"}
		if st != "":
			return {"ok": false, "error": "a join request has no stake"}
	elif door != String(GAMES[game]["door"]):
		return {"ok": false, "error": "that game is not played there"}
	if invites.has(id):
		return {"ok": false, "error": "duplicate id"}
	var open := 0
	for v in invites.values():
		if v["state"] != "pending":
			continue
		if v["from"] == from:
			open += 1
			if v["to"] == to and v["game"] == game:
				return {"ok": false, "error": "you already asked them to join you" if game == JOIN else "you already invited them to that game"}
	if open >= MAX_OPEN_PER_WALLET:
		return {"ok": false, "error": "you have %d invites waiting already" % MAX_OPEN_PER_WALLET}
	var inv := {"id": id, "from": from, "from_name": NetProto.clean_text(from_name, NetProto.NAME_MAX_CHARS),
		"to": to, "to_name": NetProto.clean_text(to_name, NetProto.NAME_MAX_CHARS), "game": game, "stake": st,
		"room": room, "door": door, "state": "pending", "created": now, "expires": now + TTL_S, "match": "", "at": now}
	invites[id] = inv
	return {"ok": true, "invite": inv}


## accept | decline (by the invitee), cancel (by the inviter). {ok, invite} or {ok: false, error}.
func answer(id: String, by: String, what: String, now: int) -> Dictionary:
	var inv: Dictionary = invites.get(id, {})
	if inv.is_empty():
		return {"ok": false, "error": "no such invite"}
	if inv["state"] == "pending" and now >= int(inv["expires"]):
		_mark(inv, "expired", now)
	if inv["state"] != "pending":
		return {"ok": false, "error": "that invite is %s" % inv["state"], "invite": inv}
	by = NetProto.clean_wallet(by)
	match what:
		"accept", "decline":
			if by != inv["to"]:
				return {"ok": false, "error": "only the invited player can %s" % what}
			_mark(inv, "accepted" if what == "accept" else "declined", now)
		"cancel":
			if by != inv["from"]:
				return {"ok": false, "error": "only the inviter can cancel"}
			_mark(inv, "cancelled", now)
		_:
			return {"ok": false, "error": "unknown answer"}
	return {"ok": true, "invite": inv}


func _mark(inv: Dictionary, state: String, now: int) -> void:
	inv["state"] = state
	inv["at"] = now


## Pending invites past their time become "expired"; returns those (to notify both players).
func expire(now: int) -> Array:
	var out: Array = []
	for inv in invites.values():
		if inv["state"] == "pending" and now >= int(inv["expires"]):
			_mark(inv, "expired", now)
			out.append(inv)
	return out


## Forgets finished invites older than KEEP_S.
func prune(now: int) -> void:
	for id in invites.keys():
		var inv: Dictionary = invites[id]
		if inv["state"] != "pending" and now - int(inv["at"]) > KEEP_S:
			invites.erase(id)


## Invites a wallet sent or received (pending first, then newest).
func for_wallet(w: String) -> Array:
	w = w.to_lower()
	var out := invites.values().filter(func(v): return v["from"] == w or v["to"] == w)
	out.sort_custom(func(a, b):
		if (a["state"] == "pending") != (b["state"] == "pending"):
			return a["state"] == "pending"
		return int(a["created"]) > int(b["created"]))
	return out


## Seconds left on a pending invite (0 once it is due).
static func seconds_left(inv: Dictionary, now: int) -> int:
	return maxi(0, int(inv.get("expires", 0)) - now) if inv.get("state", "") == "pending" else 0
