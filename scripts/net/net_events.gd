class_name NetEvents
extends RefCounted
## Online players' actions (the activity feed): what the game server tells
## everyone, and what each machine reads from the chain itself. Kept apart from
## NetProto's core types like NetBump: its own message numbers, well away from
## the sequential ones. Pure: the server, the client and the tests share it.
##
##   C_PLACE (client → server)  [41] json {place, room}   "I went into the arcade of this QING"
##   C_CLAIM (client → server)  [42] json {claim, room}   "I unlocked the rocket here" (receivers check the chain)
##   S_EVENT (server → clients) [105] json {ev: {k, w, n, w2, n2, room, place, game, stake, board, score, check, claim, t}}
##
## The server only says what it knows itself: who signed in or left (by the wallet
## the signature proved), who joined which QING room, where a player says they
## walked in, the head-to-head games it relayed and whose results both machines
## agreed, the leaderboard rows it took. A claim is never shown as a fact: every
## receiver reads the chain first (NetActivity) and drops it when the chain disagrees.
## Names in an event are what the player's game claimed; clients show the name read
## from the chain for the wallet instead (LauNames, NetNames).
##
## Scope (server): events about signed-in players go to signed-in connections
## (like S_ONLINE); "guest" and "place" go to the QING room they happen in.
## Limits: a token bucket per wallet and one for the whole server; a sign-in after
## a short drop is not "came online" again, nor a re-join of the same QING "arrived".

const C_PLACE := 41
const C_CLAIM := 42
const S_EVENT := 105
## Listed in S_WELCOME "features" by a server that sends events; a client sends
## C_PLACE / C_CLAIM only to such a server (an older one would count them as malformed).
const FEATURES := ["events"]
const SIZES := {C_PLACE: 160, C_CLAIM: 160}

## What the server sends.
const SERVER_KINDS := ["online", "offline", "arrive", "guest", "place", "match", "join", "result", "record", "claim", "daily_record"]
## What a machine adds from its own chain reads (shown to that player only).
const LOCAL_KINDS := ["fair", "hypobar", "paid", "rocket", "invite"]
## Places a player can say they walked into (PlaceBase kinds) and how a line names them.
const PLACES := {"arcade": "the arcade", "pub": "Sunny's Pub", "hall": "the QING room", "void": "the Void"}
## Where a "Join me" can lead (InviteBook.JOIN_DOORS → a place; "" = the territory itself).
const JOIN_PLACES := {"": "", "hall": "the QING room", "arcade": "the arcade"}
## Claims a receiver can check on the chain.
const CLAIMS := ["rocket"]

# Server limits.
const OFFLINE_GRACE_S := 20.0     ## a wallet gone this briefly (a reconnect) is not "went offline"
const ARRIVE_REPEAT_S := 600.0    ## the same wallet re-joining the same QING room this soon is not news
const PLACE_REPEAT_S := 120.0     ## nor walking into the same place again
const WALLET_RATE := 0.2          ## events about one wallet: one every 5 s…
const WALLET_BURST := 4.0         ## …after a burst of 4
const SERVER_RATE := 5.0          ## events from the whole server a second
const SERVER_BURST := 20.0
const SENDER_RATE := 0.2          ## C_PLACE / C_CLAIM from one connection
const SENDER_BURST := 4.0

# Client feed.
const FEED_TTL_S := 8.0           ## a line fades after this
const FEED_MAX := 5               ## lines on screen
const DEDUPE_S := 30.0            ## the same line again within this is dropped
const HISTORY := 100              ## kept for the notification panel (this session)


static func size_ok(msg: PackedByteArray) -> bool:
	return not msg.is_empty() and SIZES.has(int(msg[0])) and msg.size() >= 2 and msg.size() <= int(SIZES[int(msg[0])])


static func place_msg(place: String, room: String) -> PackedByteArray:
	return NetProto.json_msg(C_PLACE, {"place": place, "room": room})


static func claim_msg(claim: String, room: String) -> PackedByteArray:
	return NetProto.json_msg(C_CLAIM, {"claim": claim, "room": room})


## The server's check of C_PLACE / C_CLAIM: {place|claim, room (a QING)} or {}.
static func parse_place(msg: PackedByteArray) -> Dictionary:
	var b := NetProto.json_body(msg)
	var place := NetProto.str_of(b.get("place", ""))
	var room := NetProto.clean_room(NetProto.str_of(b.get("room", "")))
	if not PLACES.has(place) or room == "" or room.contains("/"):
		return {}
	return {"place": place, "room": room}


static func parse_claim(msg: PackedByteArray) -> Dictionary:
	var b := NetProto.json_body(msg)
	var claim := NetProto.str_of(b.get("claim", ""))
	var room := NetProto.clean_room(NetProto.str_of(b.get("room", "")))
	if not CLAIMS.has(claim) or room == "" or room.contains("/"):
		return {}
	return {"claim": claim, "room": room}


static func event_msg(ev: Dictionary) -> PackedByteArray:
	return NetProto.json_msg(S_EVENT, {"ev": ev})


## Client side: a server's event, cleaned (the server is somebody's laptop, not a
## trusted party): a known kind, wallets as 0x…40 hex, short printable texts,
## whole numbers. {} when it is not an event this game shows.
static func clean_event(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var k := String(d.get("k", ""))
	if not SERVER_KINDS.has(k):
		return {}
	var ev := {"k": k, "w": NetProto.clean_wallet(String(d.get("w", ""))), "n": NetProto.clean_text(String(d.get("n", "")), NetProto.NAME_MAX_CHARS),
		"t": maxi(0, int(d.get("t", 0)))}
	if k != "guest" and ev["w"] == "":
		return {}
	for f in ["w2"]:
		if d.has(f):
			ev[f] = NetProto.clean_wallet(String(d[f]))
	if d.has("n2"):
		ev["n2"] = NetProto.clean_text(String(d["n2"]), NetProto.NAME_MAX_CHARS)
	if d.has("room"):
		ev["room"] = NetProto.clean_room(String(d["room"]))
	for f in ["place", "game", "claim", "check"]:
		if d.has(f):
			ev[f] = NetProto.clean_text(String(d[f]), 40)
	if d.has("stake"):
		var st := NetProto.clean_text(String(d["stake"]), 24)
		ev["stake"] = st if st.is_valid_float() else ""
	if d.has("board"):
		ev["board"] = NetProto.clean_text(String(d["board"]), 96)
	if d.has("score"):
		ev["score"] = maxi(0, int(d["score"]))
	if d.has("push"):
		ev["push"] = bool(d["push"])
	if d.has("verified"):
		ev["verified"] = bool(d["verified"])
	if k == "place" and not PLACES.has(String(ev.get("place", ""))):
		return {}
	if k == "claim" and not CLAIMS.has(String(ev.get("claim", ""))):
		return {}
	if k == "join" and not JOIN_PLACES.has(String(ev.get("place", ""))):
		return {}
	if k in ["match", "result", "join"] and String(ev.get("w2", "")) == "":
		return {}
	return ev


## Pure: "1240" → "1,240".
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		out += s[i]
		var rem := s.length() - 1 - i
		if rem > 0 and rem % 3 == 0:
			out += ","
	return ("-" if n < 0 else "") + out


## Pure: a whole number as decimal text ("12345678901234567890") grouped by thousands.
static func grouped_dec(s: String) -> String:
	var neg := s.begins_with("-")
	s = s.trim_prefix("-")
	var out := ""
	for i in s.length():
		out += s[i]
		var rem := s.length() - 1 - i
		if rem > 0 and rem % 3 == 0:
			out += ","
	return ("-" if neg else "") + out


## Pure: a board's game in words: "<qing>/arcade:void_lanes" → "Void Lanes".
static func board_title(board: String) -> String:
	var id := board.get_slice("/", 1) if board.contains("/") else board
	if id.contains(":"):
		id = id.get_slice(":", 1)
	return id.replace("_", " ").capitalize() if id != "" else "a board"


## Pure: the feed line for an event. `ctx`:
##   me: this player's wallet ("You …");
##   name: Callable(wallet, claimed_name) -> String (the name to show for a wallet);
##   place: Callable(room) -> String (a QING's name);
##   game: Callable(game id) -> String ("pool" → "pool", "striker" → "Test Your Affection");
##   board: Callable(board id) -> String (defaults to board_title).
static func format(ev: Dictionary, ctx: Dictionary = {}) -> String:
	var me := String(ctx.get("me", ""))
	var who := func(w: String, claimed: String) -> String:
		if w != "" and w == me:
			return "You"
		if w == "":
			return "a guest"
		var f = ctx.get("name")
		return String(f.call(w, claimed)) if f is Callable else NetProto.short_wallet(w)
	var where := func(room: String) -> String:
		var f = ctx.get("place")
		var r := room.get_slice("/", 0)
		return String(f.call(r)) if f is Callable and r != "" else (NetProto.short_wallet(r) if r != "" else "a QING")
	var game := func(g: String) -> String:
		var f = ctx.get("game")
		return String(f.call(g)) if f is Callable else g
	var a: String = who.call(String(ev.get("w", "")), String(ev.get("n", "")))
	var b: String = who.call(String(ev.get("w2", "")), String(ev.get("n2", ""))) if ev.has("w2") else ""
	if b == "You":
		b = "you"  # the object of the line ("enteh beat you at pool")
	var room := String(ev.get("room", ""))
	var stake := String(ev.get("stake", ""))
	match String(ev.get("k", "")):
		"online":
			return "%s came online" % a
		"offline":
			return "%s went offline" % a
		"arrive":
			return "%s arrived in %s" % [a, where.call(room)]
		"guest":
			return "A guest arrived in %s" % where.call(room)
		"place":
			return "%s entered %s" % [a, String(PLACES.get(String(ev.get("place", "")), "a place"))]
		"match":
			return "%s and %s sat down to %s%s" % [a, b, game.call(String(ev.get("game", ""))), (" · stake %s Ⓐ" % stake) if stake != "" else ""]
		"join":
			var pl := String(JOIN_PLACES.get(String(ev.get("place", "")), ""))
			return "%s %s on the way to join %s at %s%s" % [a, "are" if a == "You" else "is", b, where.call(room), (" · " + pl) if pl != "" else ""]
		"invite":  # an invite you sent or got (Invites, from the server's S_INVITE): w = the other player
			var what := String(ev.get("what", ""))
			if String(ev.get("state", "")) == "accepted":
				return ("%s accepted your invite: %s" % [a, what]) if ev.get("mine", false) else ("You accepted %s's invite: %s" % [a, what])
			return ("You invited %s: %s" % [a, what]) if ev.get("mine", false) else ("%s invites you: %s (%s)" % [a, what, String(ev.get("key", "N"))])
		"result":
			if ev.get("push", false):
				return "%s and %s drew at %s" % [a, b, game.call(String(ev.get("game", "")))]
			return "%s beat %s at %s%s" % [a, b, game.call(String(ev.get("game", ""))), (" (%s Ⓐ stake, honour-bound)" % stake) if stake != "" else ""]
		"record":
			var bf = ctx.get("board")
			var bt: String = String(bf.call(String(ev.get("board", "")))) if bf is Callable else board_title(String(ev.get("board", "")))
			return "%s set a new #1 on %s: %s%s" % [a, bt, grouped(int(ev.get("score", 0))), " ✓" if ev.get("verified", false) else ""]
		"claim", "rocket":
			return "%s unlocked the Upsilon Rocket at %s" % [a, where.call(room)]
		"daily_record":  # NetDaily: a replayed run took #1 on today's board
			return "%s took #1 in the daily challenge (%s): %s%s" % [a, DailyChallenge.title_of(String(ev.get("game", ""))),
				grouped(int(ev.get("score", 0))), " ✓ replayed" if ev.get("verified", false) else ""]
		"fair":
			return "%s posted %s at %s" % [a, grouped(int(ev.get("score", 0))), game.call(String(ev.get("game", "")))]
		"hypobar":
			return "%s Hypobar here rose by %s (block %s)" % ["Your" if a == "You" else a + "'s", String(ev.get("amount", "?")), grouped(int(ev.get("block", 0)))]
		"paid":
			return "%s paid %s %s Ⓐ ✓ (Transfer log, block %s)" % [a, b, stake, grouped(int(ev.get("block", 0)))]
	return ""


## Pure: two events that say the same thing share a key (the feed drops repeats).
static func dedupe_key(ev: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s" % [ev.get("k", ""), ev.get("w", ""), ev.get("w2", ""), String(ev.get("room", "")).get_slice("/", 0),
		ev.get("place", ev.get("game", "")), ev.get("board", ""), ev.get("score", ev.get("block", "")), ev.get("text", "")]


## Pure: should this player see this event in the feed? Their own comings and goings
## are not news to them; a "place" or "guest" event from another QING is not either.
static func relevant(ev: Dictionary, me: String, here: String) -> bool:
	var k := String(ev.get("k", ""))
	var w := String(ev.get("w", ""))
	if me != "" and w == me and k in ["online", "offline", "arrive", "place", "claim"]:
		return false
	if k in ["place", "guest"]:
		return here != "" and String(ev.get("room", "")).get_slice("/", 0) == here
	return true


## The colour a kind of line is drawn in.
static func color_of(k: String) -> Color:
	match k:
		"online", "arrive":
			return Color("#9fe8ff")
		"offline":
			return Color(0.62, 0.66, 0.74)
		"guest", "place":
			return Color("#c9d8ee")
		"match", "result", "paid", "join", "invite":
			return Color("#ffd27a")
		"record", "fair", "daily_record":
			return Color("#ff9be6")
		"claim", "rocket":
			return Color("#ffb46b")
		"hypobar":
			return Color("#b9a3ff")
	return Color("#dfe8f5")


## The feed's gate (client): drops a line it showed within DEDUPE_S, and keeps the
## feed to a few lines a second however busy the server is. Time is passed in.
class Gate:
	extends RefCounted
	var _seen := {}   # key → last time shown (s)
	var _bucket := TokenBucket.new(1.0, 6.0)

	func admit(key: String, now: float) -> bool:
		if _seen.has(key) and now - float(_seen[key]) < DEDUPE_S:
			return false
		if not _bucket.take(now):
			return false
		_seen[key] = now
		if _seen.size() > 400:
			for k in _seen.keys():
				if now - float(_seen[k]) >= DEDUPE_S:
					_seen.erase(k)
		return true
