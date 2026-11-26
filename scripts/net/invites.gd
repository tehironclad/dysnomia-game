extends Node
## Autoload "Invites": game invites, head-to-head games over the game server and
## their honour-bound wagers, plus this session's notifications (docs/SERVER.md
## §8b, LEARNINGS §18). The notification panel (NotificationPanel) draws what is
## here; the tables (GamesPlace, PoolSeat, CardSeat) play the games.
##
## - Invites: InviteBook on the server; here a mirror of the ones you sent or got.
## - Games: the server orders and stamps moves; NetMatch replays them on this
##   machine (cards wait for their block: BlockClock). When a game ends this
##   machine reports its replay's fingerprint; the server marks it agreed when
##   both machines report the same.
## - Wagers: no escrow. The loser pays with TableBook.pay_debt (AFFECTION.transfer
##   through the write pipeline: simulate → sign → receipt check), and a wager is
##   "paid" only once an AFFECTION Transfer(loser → winner) log at or after the
##   game's end block is read from the chain (TableBook.allocate). Unread = "—".
## Offline (no server, or a server without "invites"): quiet; the panel says so.
## Notifications live for this session only (memory, across scene changes).

signal notes_changed
signal note_added(note: Dictionary)
signal match_changed(id: String)
signal online_changed

const AUTO_TAKE_S := 120     # a game opened this recently takes both players to the table
const CHECK_FIRST_S := 30.0  # wager checks: every 30 s for 10 minutes, then every 2 minutes
const CHECK_LATER_S := 120.0
const MAX_NOTES := 200

var notes: Array = []        # newest last: {n, kind, text, at, read, ref, game}
var invites := {}            # id → the invite as the server last sent it
var matches := {}            # id → NetMatch
var online: Array = []       # rows from S_ONLINE
var online_state := ""       # "" | "loading" | "ok" | an error
var pending_seat := {}       # {match, kind, room}: sit down at this table on arrival
var pending_join := {}       # {room, door, from}: a "Join me" accepted: through that door on arrival
const ONLINE_POLL_S := 30.0  # who is online, asked again this often while signed in (the feed's header)
var _online_at := -1000000

var _n := 0
var _replaying := {}
var _retry_at := {}
var _check_at := {}
var _checking := {}
var _ended_note := {}
var _result_sent := {}
var _taken := {}
var _sat := {}
var _bound := false
var _test_key := ""
var _boot := ""              # the server run our games are on (NetClient.boot)
var _catchup := {}           # match id → log entries it already had when we first heard of it
var _last_move_match := ""   # the game of the last move sent (a "No such game." refusal names none)
const NO_SUCH_GAME := "No such game."


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--server"):
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-key="):  # tests and screenshots only: a throwaway key signs the free sign-in
			if not OS.is_debug_build():
				push_warning("[Net] --net-key is ignored: it exists for test runs of the editor build only. Never put a real key on a command line.")
				continue
			_test_key = a.substr(10)
			print("[Net] TEST MODE (--net-key): a throwaway key on the command line signs the server sign-in. Debug builds only; never a real key.")
	_bind.call_deferred()


func _bind() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or net.client == null or _bound:
		return
	_bound = true
	var c: NetClient = net.client
	c.invite_update.connect(_on_invite)
	c.match_update.connect(_on_match)
	c.match_move.connect(_on_move)
	c.online_list.connect(_on_online)
	c.refused.connect(_on_refused)
	c.status_changed.connect(_on_status)
	c.welcomed.connect(func(_id): _on_welcome(c.boot))
	if net.names:
		net.names.resolved.connect(_on_name_resolved)
	c.auth_changed.connect(func(_w): online_changed.emit(); notes_changed.emit())
	if _test_key != "":
		c.signer_wallet = EthSign.address_of_private(_test_key)
		var key := _test_key
		c.signer = func(message: String) -> String: return EthSign.sign_personal(message, key)


func _on_refused(what: String, err: String) -> void:
	_note("refused", "The server refused that %s: %s" % [what, err], "", "", false)
	if what == "move" and err == NO_SUCH_GAME and _last_move_match != "":
		forget_lost([_last_move_match])  # an older server restarted (it doesn't say its boot): that game is gone


## The server's welcome: a different run of the server than the one our games were on
## means it lost them (invites and games live in its memory only).
func _on_welcome(boot: String) -> void:
	if boot != "" and _boot != "" and boot != _boot:
		forget_lost(matches.keys())
		for id in invites:
			if String(invites[id].get("state", "")) == "pending":
				invites[id]["state"] = "expired"
		notes_changed.emit()
	if boot != "":
		_boot = boot


## Games the server no longer has (it restarted): live ones can't go on. Each is marked
## abandoned, nobody owes anything on it, and the table lets the players go.
func forget_lost(ids: Array) -> void:
	for id in ids:
		var nm: NetMatch = matches.get(id)
		if nm == null or nm.over() or nm.m.get("abandoned", false) or nm.m.get("disputed", false):
			continue
		nm.m["abandoned"] = true
		nm.rec["status"] = "abandoned"
		if NetProto.str_of(pending_seat.get("match", "")) == String(id):
			pending_seat = {}
		_note("result", "#%s can't go on: the game server restarted and no longer has it. Nobody owes anything on it." % id, String(id), nm.m["kind"], false)
		match_changed.emit(String(id))


## The names a game's tables and notes show: each wallet's name read from the chain
## (Net.names), never the name the server passes on (the player's own claim: anyone can
## call themselves "Sunny"). "" until it is read: the tables then show the short wallet.
func _chain_names(nm: NetMatch) -> void:
	var net := get_node_or_null("/root/Net")
	var names: LauNames = net.names if net else null
	for i in 2:
		var w := String(nm.m["players"][i])
		var shown := NetNames.shown(w, names.record(w) if names and w != "" else {})
		nm.m["names"][i] = "" if shown == NetProto.short_wallet(w) or shown == "guest" else shown


func _on_name_resolved(w: String) -> void:
	for id in matches:
		var nm: NetMatch = matches[id]
		if nm.index_of(w) >= 0:
			_chain_names(nm)
			match_changed.emit(String(id))


func _client() -> NetClient:
	var net := get_node_or_null("/root/Net")
	return net.client if net else null


func _on_status(s: String) -> void:
	if s == "online" and _test_key != "":
		# Net sets the signer to the browser wallet on every connect: the test key goes back in here.
		var key := _test_key
		_client().signer_wallet = EthSign.address_of_private(key)
		_client().signer = func(message: String) -> String: return EthSign.sign_personal(message, key)
		_client().sign_in()
	online_changed.emit()
	notes_changed.emit()


# --- State for the panel --------------------------------------------------------

## The signed-in wallet the server verified ("" when offline or a guest).
func me() -> String:
	var c := _client()
	return c.wallet if c and c.is_online() else ""


## The wallet that plays `m` on this machine: for a game over the game server, the one
## the server verified (it sends the moves; in a test run it has no browser wallet); else
## the session's (a room-line game is signed in that wallet).
func wallet_for(m: Dictionary) -> String:
	if m.get("net", false) and me() != "":
		return me()
	return String(get_node("/root/Session").wallet)


## "" when invites work now; otherwise why not, in words.
func blocker() -> String:
	var c := _client()
	if c == null or not c.is_online():
		return "Invites need the game server, and it isn't answering: you are playing single-player. (F2 · Online & voice sets the server.)"
	if not c.features.has("invites"):
		return "This game server is older and has no invites."
	if c.wallet == "":
		return "Sign in to the game server with your wallet (a free signature, not a transaction) to invite players and be invited."
	return ""


func unread() -> int:
	var n := 0
	for x in notes:
		if not x["read"]:
			n += 1
	return n


func mark_all_read() -> void:
	var any := false
	for x in notes:
		if not x["read"]:
			x["read"] = true
			any = true
	if any:
		notes_changed.emit()


func _note(kind: String, text: String, ref: String, game: String, read: bool) -> Dictionary:
	_n += 1
	var x := {"n": _n, "kind": kind, "text": text, "at": int(Time.get_unix_time_from_system()), "read": read, "ref": ref, "game": game}
	notes.append(x)
	if notes.size() > MAX_NOTES:
		notes = notes.slice(notes.size() - MAX_NOTES)
	notes_changed.emit()
	if not read:
		note_added.emit(x)
	return x


static func game_title(game: String) -> String:
	return InviteBook.title_of(game)


func place_name(room: String) -> String:
	if room == Contracts.VOID:
		return "the Void"  # its presence room (PlaceBase): everyone in the Void, whatever QING they came from
	var reg := get_node_or_null("/root/Registry")
	var t: Dictionary = reg.get_territory(room) if reg else {}
	return NetProto.str_of(t.get("name", NetMatch.short(room)))


## A wallet as the panel names it: the chain's name for it (Net.names) and the short
## wallet. The name the server passes on (`_name`) is the player's own claim: not shown.
func _who(wallet: String, _name: String) -> String:
	var net := get_node_or_null("/root/Net")
	if net and net.names and NetProto.clean_wallet(wallet) != "":
		return NetNames.tag(wallet, false, net.names.record(wallet))
	return NetMatch.short(wallet)


## For the tables: `wallet`'s name as the server knows it in any of our games.
func display(wallet: String) -> String:
	for nm in matches.values():
		var i: int = nm.index_of(wallet)
		if i >= 0 and String(nm.m["names"][i]) != "":
			return _who(wallet, String(nm.m["names"][i]))
	return NetMatch.short(wallet)


# --- Asking the server ------------------------------------------------------------

func refresh_online() -> void:
	var c := _client()
	if blocker() != "":
		online = []
		online_state = blocker()
		online_changed.emit()
		return
	online_state = "loading"
	online_changed.emit()
	c.request_online()


func _on_online(ok: bool, rows: Array, error: String) -> void:
	online = rows if ok else []
	online_state = "ok" if ok else (error if error != "" else "—")
	online_changed.emit()


## Invites `wallet` to `game` at the table of the territory you are in. "" or why not.
func invite(wallet: String, game: String, stake_text: String) -> String:
	var b := blocker()
	if b != "":
		return b
	if not InviteBook.game_ok(game):
		return "Unknown game."
	if game == InviteBook.JOIN:
		var at := join_target()
		if at.has("error"):
			return String(at["error"])
		if NetProto.clean_wallet(wallet) == "" or wallet.to_lower() == me():
			return "Pick another player."
		_client().invite(wallet.to_lower(), game, "", String(at["room"]), String(at["door"]))
		return ""
	var st := InviteBook.clean_stake(stake_text)
	if st == "!":
		return "The stake is a number of Ⓐ, like 5 or 0.25 (or empty for none)."
	var room := String(get_node("/root/GameManager").territory_address).to_lower()
	if NetProto.clean_room(room) == "":
		return "Go to a territory first: the game is played at its %s." % ("arcade" if InviteBook.GAMES[game]["door"] == "arcade" else "table")
	if NetProto.clean_wallet(wallet) == "" or wallet.to_lower() == me():
		return "Pick another player."
	_client().invite(wallet.to_lower(), game, st, room, String(InviteBook.GAMES[game]["door"]))
	return ""


## Where a "Join me" would bring someone: {room (this QING), door ("" the territory, "room" its
## hall, "arcade" its arcade or pub)} or {error}. Never the Void or the Field (no QING there).
func join_target() -> Dictionary:
	var room := String(get_node("/root/GameManager").territory_address).to_lower()
	if NetProto.clean_room(room) == "" or room.contains("/"):
		return {"error": "Go to a territory first: a join request brings them to the QING you are in."}
	var cs := get_tree().current_scene if get_tree() else null
	var path := String(cs.scene_file_path) if cs else ""
	match path:
		Travel.TERRITORY_SCENE: return {"room": room, "door": ""}
		Travel.HALL_SCENE: return {"room": room, "door": "room"}
		Travel.ARCADE_SCENE, Travel.PUB_SCENE: return {"room": room, "door": "arcade"}
	return {"error": "Join requests work from a territory, its QING room or its arcade, not from here."}


## Pure: where a join request leads, in words ("Zürich QING", "the arcade of Zürich QING").
static func join_where(place: String, door: String) -> String:
	match door:
		"room": return "the QING room of %s" % place
		"arcade": return "the arcade of %s" % place
	return place


## accept | decline | cancel
func answer(id: String, what: String) -> void:
	if blocker() == "":
		_client().answer_invite(id, what)


## Both players confirm a proposed stake (or play without it). A confirmation sent
## from here is remembered on this computer (AGREED_PATH): pay() pays only a stake
## this computer agreed to, so a dishonest game server can't invent a debt.
func confirm_stake(match_id: String, ok: bool) -> bool:
	var sent := send_move(match_id, "stake_ok" if ok else "stake_no")
	var nm: NetMatch = matches.get(match_id)
	if sent and ok and nm != null:
		remember_agreed(match_id, me(), String(nm.m.get("stake_text", "")))
	return sent


const AGREED_PATH := "user://wagers_agreed.cfg"


## Records that `wallet` agreed to `stake_text` Ⓐ on match `match_id` from this computer.
static func remember_agreed(match_id: String, wallet: String, stake_text: String, path: String = AGREED_PATH) -> void:
	if match_id == "" or wallet == "" or stake_text == "":
		return
	var c := ConfigFile.new()
	c.load(path)
	c.set_value("agreed", "%s|%s" % [match_id, wallet.to_lower()], stake_text)
	c.save(path)


## The stake `wallet` agreed to on `match_id` from this computer ("" if none).
static func agreed_stake(match_id: String, wallet: String, path: String = AGREED_PATH) -> String:
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return ""
	return String(c.get_value("agreed", "%s|%s" % [match_id, wallet.to_lower()], ""))


## Pure: "" when `w` may pay the debt of match `m` as the game server describes it,
## given the stake this computer recorded `w` agreeing to; else why not. The server is
## somebody's laptop: the recipient must be the other player of the match, the stake
## a valid one that this computer agreed to, and `w` the loser.
static func pay_refusal(m: Dictionary, w: String, agreed: String) -> String:
	var players: Array = m.get("players", [])
	var winner := NetProto.clean_wallet(NetProto.str_of(m.get("winner", "")))
	var loser := NetProto.clean_wallet(NetProto.str_of(m.get("loser", "")))
	if players.size() != 2 or winner == "" or loser == "" or winner == loser or not players.has(winner) or not players.has(loser):
		return "the server's record of this game is not two players with a winner and a loser"
	if w != loser:
		return "the connected wallet is not the one that lost"
	var st := InviteBook.clean_stake(NetProto.str_of(m.get("stake_text", "")))
	if st == "" or st == "!" or BigInt.cmp(NetMatch.stake_wei(st), m.get("stake", BigInt.zero())) != 0:
		return "the stake in the server's record is not a valid amount of Ⓐ"
	if agreed != st:
		return ("this computer has no record of you agreeing to a %s Ⓐ stake on this game (the server says you did). " % st) + \
			"Wagers are honour-bound: if you did agree, you can pay it yourself with a plain transfer from your wallet"
	return ""


func send_move(match_id: String, op: String, args: Array = []) -> bool:
	var c := _client()
	if c == null or not c.is_online() or c.wallet == "":
		return false
	_last_move_match = match_id
	return c.send_move(match_id, op, args)


func _on_invite(inv: Dictionary) -> void:
	var id := NetProto.str_of(inv.get("id", ""))
	var prev: Dictionary = invites.get(id, {})
	invites[id] = inv
	var state := NetProto.str_of(inv.get("state", ""))
	if not prev.is_empty() and prev.get("state") == state:
		notes_changed.emit()
		return
	var mine := me()
	var from_me := NetProto.str_of(inv.get("from", "")) == mine
	var them := _who(String(inv["to"]), NetProto.str_of(inv.get("to_name", ""))) if from_me else _who(String(inv["from"]), NetProto.str_of(inv.get("from_name", "")))
	var is_join := String(inv["game"]) == InviteBook.JOIN
	var what := "%s at %s%s" % [game_title(String(inv["game"])), place_name(String(inv["room"])),
		(" · stake %s Ⓐ (honour-bound)" % inv["stake"]) if NetProto.str_of(inv.get("stake", "")) != "" else ""]
	if is_join:
		what = "join them at " + join_where(place_name(String(inv["room"])), NetProto.str_of(inv.get("door", "")))
	_feed_invite(inv, state, from_me, them, what)
	if is_join:
		match state:
			"pending":
				if from_me:
					_note("sent", "You asked %s to join you (%s)." % [them, join_where(place_name(String(inv["room"])), NetProto.str_of(inv.get("door", "")))], id, InviteBook.JOIN, true)
				else:
					_note("invite", "%s asks you to %s." % [them, what], id, InviteBook.JOIN, false)
			"accepted":
				if from_me:
					_note("accepted", "%s accepted: on the way to you." % them, id, InviteBook.JOIN, false)
				else:
					_note("accepted", "You accepted: on the way to %s." % them, id, InviteBook.JOIN, true)
					go_join(inv)
			"declined":
				_note("declined", ("%s declined to join you." % them) if from_me else ("You declined %s's request." % them), id, InviteBook.JOIN, not from_me)
			"cancelled":
				_note("cancelled", ("You withdrew your request to %s." % them) if from_me else ("%s withdrew their request." % them), id, InviteBook.JOIN, from_me)
			"expired":
				_note("expired", ("Your request to %s expired unanswered." % them) if from_me else ("%s's request expired." % them), id, InviteBook.JOIN, false)
		return
	match state:
		"pending":
			if from_me:
				_note("sent", "You invited %s to %s." % [them, what], id, String(inv["game"]), true)
			else:
				_note("invite", "%s invites you to %s." % [them, what], id, String(inv["game"]), false)
		"accepted":
			_note("accepted", ("%s accepted your invite: %s. To the table!" % [them, what]) if from_me else ("You accepted %s's invite: %s." % [them, what]), id, String(inv["game"]), not from_me)
		"declined":
			_note("declined", ("%s declined your invite to %s." % [them, what]) if from_me else ("You declined %s's invite." % them), id, String(inv["game"]), not from_me)
		"cancelled":
			_note("cancelled", ("You cancelled your invite to %s." % them) if from_me else ("%s cancelled their invite to %s." % [them, what]), id, String(inv["game"]), from_me)
		"expired":
			_note("expired", ("Your invite to %s expired unanswered." % them) if from_me else ("%s's invite to %s expired." % [them, what]), id, String(inv["game"]), false)


## The activity feed's line for an invite you sent or got, sent or accepted (Net.activity; from the
## server's S_INVITE: a fact the server holds, about you).
func _feed_invite(inv: Dictionary, state: String, from_me: bool, _them: String, what: String) -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or net.activity == null or not state in ["pending", "accepted"]:
		return
	net.activity.add_local({"k": "invite", "w": String(inv["to"] if from_me else inv["from"]), "state": state, "mine": from_me, "what": what,
		"key": ControlsHelp.key_of("notifications"), "room": NetProto.str_of(inv.get("room", "")), "game": NetProto.str_of(inv.get("game", "")),
		"text": NetProto.str_of(inv.get("id", "")) + state})


## A "Join me" you accepted: there through the normal ways in (a warp to the QING, then its door).
func go_join(inv: Dictionary) -> void:
	var room := String(inv["room"]).to_lower()
	var door := NetProto.str_of(inv.get("door", ""))
	var tree := get_tree()
	var reg := get_node("/root/Registry")
	if not reg.has_territory(room):
		_note("refused", "That QING (%s) is not in this game's territory list." % NetMatch.short(room), String(inv["id"]), InviteBook.JOIN, false)
		return
	var gm := get_node("/root/GameManager")
	var cs := tree.current_scene
	var path := String(cs.scene_file_path) if cs else ""
	var same_qing := String(gm.territory_address).to_lower() == room
	if same_qing and path == Travel.TERRITORY_SCENE:
		if door != "":
			Travel.through_door(tree, door)  # already here: in through the door
		return
	if same_qing and Travel.place_scene(door, room) == path and door != "":
		return  # already there
	if same_qing and path in [Travel.HALL_SCENE, Travel.ARCADE_SCENE, Travel.PUB_SCENE]:
		pending_join = {"room": room, "door": door}
		Travel.out_door(tree, Travel.door_of_scene(path))  # out of this building, then in through theirs
		return
	pending_join = {"room": room, "door": door}
	Warp.to(tree, room)


## The territory scene arrived at `qing` (NetPresence): a join's door, if any, is walked through now.
func arrived_in(qing: String) -> void:
	if pending_join.is_empty() or String(pending_join["room"]) != qing.to_lower():
		return
	var door := String(pending_join["door"])
	pending_join = {}
	if door == "":
		return
	await get_tree().create_timer(1.5).timeout  # the arrival settles (the warp's card fades) first
	var gm := get_node("/root/GameManager")
	if String(gm.territory_address).to_lower() == qing.to_lower() and String(get_tree().current_scene.scene_file_path) == Travel.TERRITORY_SCENE:
		Travel.through_door(get_tree(), door)


## Who is online, asked again now and then while signed in (the feed's "N to invite").
func poll_online() -> void:
	var now := Time.get_ticks_msec()
	if blocker() != "" or now - _online_at < int(ONLINE_POLL_S * 1000.0):
		return
	_online_at = now
	_client().request_online()


# --- Games --------------------------------------------------------------------------

func _on_match(rec: Dictionary) -> void:
	var id := NetProto.str_of(rec.get("id", ""))
	if id == "":
		return
	var nm: NetMatch = matches.get(id)
	var fresh := nm == null
	if fresh:
		nm = NetMatch.new(rec.duplicate(true))
		matches[id] = nm
		# Moves already in the log when we first hear of a game (a reconnect, a second
		# window, a game that ended meanwhile) are history: no "sat down" / "confirm the
		# stake" notes for them, only what happens from now on (and the result).
		_catchup[id] = (rec.get("log", []) as Array).size() if rec.get("log") is Array else 0
		_chain_names(nm)
	else:
		var mine: Array = nm.rec["log"]
		var theirs: Array = rec.get("log", [])
		for i in range(mine.size(), theirs.size()):
			mine.append(theirs[i])
		nm.rec["status"] = rec.get("status", "")
		nm.rec["result"] = rec.get("result", {})
	var st := NetProto.str_of(rec.get("status", ""))
	if st == "disputed" and not nm.m.get("disputed", false):
		nm.m["disputed"] = true
		_note("result", "#%s: the two tables replayed the game differently, so there is no result and nobody owes anything." % id, id, nm.m["kind"], false)
	elif st == "abandoned" and not nm.over() and not nm.m.get("abandoned", false):
		nm.m["abandoned"] = true
		_note("result", "#%s was abandoned: no move for %d minutes." % [id, GameServer.MATCH_IDLE_S / 60], id, nm.m["kind"], false)
	elif st == "over" and NetProto.flag_of(rec.get("result", {}).get("agreed", false)):
		nm.m["agreed"] = true
	match_changed.emit(id)
	_replay(id)
	if fresh and st == "live" and nm.index_of(me()) >= 0:
		var age := Time.get_unix_time_from_system() * 1000.0 - NetProto.num_of(rec.get("created", 0))
		if age < AUTO_TAKE_S * 1000.0 and not _taken.has(id):
			_taken[id] = true
			go_to_table.call_deferred(id)


func _on_move(match_id: String, mv: Dictionary) -> void:
	var nm: NetMatch = matches.get(match_id)
	if nm == null:
		return
	var lg: Array = nm.rec["log"]
	if NetProto.int_of(mv.get("seq", 0)) == lg.size() + 1:
		lg.append(mv)
		_replay(match_id)


## Replays every move not replayed yet, in order; a card waits for its block.
func _replay(id: String) -> void:
	if _replaying.get(id, false):
		return
	var nm: NetMatch = matches.get(id)
	if nm == null:
		return
	_replaying[id] = true
	while is_inside_tree():
		if nm.needs_block() >= 0:
			nm.m["waiting"] = "the deal: waiting for the first block at or after %s" % Time.get_datetime_string_from_unix_time(nm.needs_block(), true)
			match_changed.emit(id)
			var b: Dictionary = await BlockClock.first_at(nm.needs_block())
			if not b.get("ok", false):
				nm.m["waiting"] = "the deal's block can't be read yet: — (trying again)"
				_retry_at[id] = Time.get_ticks_msec() + 10000
				break
			nm.deal(b)
			nm.m["waiting"] = ""
			match_changed.emit(id)
			continue
		var lg: Array = nm.rec["log"]
		if nm.applied >= lg.size():
			break
		var e: Dictionary = lg[nm.applied]
		var anchor := nm.hash_anchor(e)
		var blk := {}
		if anchor >= 0:
			nm.m["waiting"] = "%s hit: the card is the first block at or after %s" % [nm.name_of(NetProto.int_of(e.get("by", 0))), Time.get_datetime_string_from_unix_time(anchor, true)]
			match_changed.emit(id)
			blk = await BlockClock.first_at(anchor)
			if not blk.get("ok", false):
				nm.m["waiting"] = "the card's block can't be read yet: — (trying again)"
				_retry_at[id] = Time.get_ticks_msec() + 10000
				break
		var before := String(nm.m["status"])
		var r := nm.apply(e, blk)
		nm.m["waiting"] = ""
		_note_move(nm, e, r, before)
		match_changed.emit(id)
	_replaying[id] = false
	if nm.over():
		_on_over(id)


func _note_move(nm: NetMatch, e: Dictionary, r: Dictionary, before: String) -> void:
	if NetProto.int_of(e.get("seq", 0)) <= int(_catchup.get(nm.id(), 0)):
		return
	var mine := nm.index_of(me())
	var by := NetProto.int_of(e.get("by", -1))
	if mine < 0 or by == mine or not r.get("ok", false):
		return
	var who := nm.name_of(by)
	match NetProto.str_of(e.get("op", "")):
		"sit":
			_note("joined", "%s sat down at your %s table (#%s)." % [who, game_title(nm.m["kind"]), nm.id()], nm.id(), nm.m["kind"], false)
		"stake_ok":
			if nm.m["status"] == "confirm":
				_note("stake", "%s confirmed the %s stake for #%s: confirm it too, or play without it." % [who, NetMatch.fmt(nm.m["stake"]), nm.id()], nm.id(), nm.m["kind"], false)
		"stake_no":
			_note("stake", "%s chose to play #%s without a stake." % [who, nm.id()], nm.id(), nm.m["kind"], false)
	if before == "confirm" and nm.m["status"] == "playing" and NetProto.str_of(e.get("op", "")) == "stake_ok":
		_note("stake", "Stake agreed for #%s: %s, honour-bound." % [nm.id(), NetMatch.fmt(nm.m["stake"])], nm.id(), nm.m["kind"], true)


func _on_over(id: String) -> void:
	var nm: NetMatch = matches[id]
	var c := _client()
	if not _result_sent.has(id) and c and c.is_online() and nm.index_of(c.wallet) >= 0:
		_result_sent[id] = true
		c.send_result(id, nm.winner_index(), nm.digest())
	if _ended_note.has(id):
		return
	_ended_note[id] = true
	var mine := nm.index_of(me())
	var head := "#%s %s" % [id, game_title(nm.m["kind"])]
	var verdict := "push"
	if not nm.m["push"]:
		verdict = ("you won" if nm.m["winner"] == me() else "you lost") if mine >= 0 else "%s won" % display(nm.m["winner"])
	var vs := "%s vs %s" % [nm.name_of(0), nm.name_of(1)]
	_note("result", "%s · %s · %s. %s" % [head, vs, verdict, Wager.text(nm.m, me(), display)], id, nm.m["kind"], false)
	if not Wager.debt(nm.m).is_empty():
		_check_at[id] = 0


# --- Wagers -----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _bound:
		poll_online()
	for id in _retry_at.keys():
		if now >= int(_retry_at[id]):
			_retry_at.erase(id)
			_replay(id)
	for id in _check_at.keys():
		if now >= int(_check_at[id]) and not _checking.get(id, false):
			var nm: NetMatch = matches.get(id)
			if nm == null or nm.m.get("paid") == true or Wager.debt(nm.m).is_empty():
				_check_at.erase(id)
				continue
			check_wager(id)


## Reads AFFECTION Transfer(loser → winner) logs from the game's end block and
## marks the wager ✓ paid / ⚠ unpaid (null and "—" when the chain can't be read).
func check_wager(id: String) -> void:
	var nm: NetMatch = matches.get(id)
	if nm == null or _checking.get(id, false):
		return
	var m := nm.m
	if Wager.debt(m).is_empty():
		return
	_checking[id] = true
	var since_end := Time.get_unix_time_from_system() - int(m["end_t"]) / 1000.0
	_check_at[id] = Time.get_ticks_msec() + int((CHECK_FIRST_S if since_end < 600.0 else CHECK_LATER_S) * 1000.0)
	if int(m["end_block"]) < 0:
		var b: Dictionary = await BlockClock.first_at(int(ceil(int(m["end_t"]) / 1000.0)))
		if not b.get("ok", false):
			m["check_note"] = "the game's end block can't be read yet: —"
			_checking[id] = false
			match_changed.emit(id)
			return
		m["end_block"] = int(b["number"])
	var chain := get_node("/root/Chain")
	var head: int = await chain.refresh_head()
	if head < 0:
		m["check_note"] = "the chain head can't be read: —"
		_checking[id] = false
		match_changed.emit(id)
		return
	# Every net game between this loser and this winner (this session), oldest debt first.
	var list: Array = []
	for other in matches.values():
		var d := Wager.debt(other.m)
		if not d.is_empty() and d["loser"] == m["loser"] and d["winner"] == m["winner"] and int(d["end_block"]) >= 0:
			list.append(d)
	list.sort_custom(func(a, b): return int(a["end_block"]) < int(b["end_block"]))
	var topics := [Contracts.TOPIC_TRANSFER, "0x" + Abi.strip0x(m["loser"]).lpad(64, "0"), "0x" + Abi.strip0x(m["winner"]).lpad(64, "0")]
	var r: Dictionary = await chain.logs.scan(Contracts.AFFECTION, topics, int(list[0]["end_block"]), head)
	_checking[id] = false
	if not r.get("ok", false):
		m["check_note"] = "the Transfer logs can't be read now: —"
		match_changed.emit(id)
		return
	var transfers: Array = []
	for lg in r["logs"]:
		transfers.append({"block": NetProto.str_of(lg.get("blockNumber", "0x0")).hex_to_int(), "value": BigInt.from_hex(NetProto.str_of(lg.get("data", "0x0")))})
	var res := TableBook.allocate(list, transfers)
	for i in list.size():
		var dm: Dictionary = list[i]["match"]
		var was = dm.get("paid")
		dm["paid"] = res[i]["paid"]
		dm["paid_block"] = res[i]["paid_block"]
		dm["checked_block"] = head
		dm["check_note"] = ""
		var mid := String(dm["id"])
		if was != true and dm["paid"] == true:
			_note("wager", "#%s wager settled: %s" % [mid, Wager.text(dm, me(), display)], mid, String(dm["kind"]), false)
			var net := get_node_or_null("/root/Net")
			if net and net.activity:  # the chain's Transfer log: a fact this machine read
				net.activity.add_local({"k": "paid", "w": String(dm["loser"]), "w2": String(dm["winner"]), "stake": NetMatch.fmt(dm["stake"]).trim_suffix(" Ⓐ"),
					"block": NetProto.int_of(dm.get("paid_block", head)), "room": NetProto.str_of(dm.get("room", ""))})
			_check_at.erase(mid)
		elif was == null and dm["paid"] == false:
			_note("wager", "#%s: %s · checked to block %d" % [mid, Wager.text(dm, me(), display), head], mid, String(dm["kind"]), dm["winner"] != me() and dm["loser"] != me())
		match_changed.emit(mid)


## The loser pays the stake: AFFECTION.transfer(winner, stake) through the write
## pipeline (TableBook.pay_debt: simulate → sign → receipt → the receipt's Transfer
## log), then the debt is re-read from the chain's Transfer logs. {ok, …} or the failure.
func pay(id: String) -> Dictionary:
	var nm: NetMatch = matches.get(id)
	if nm == null or Wager.debt(nm.m).is_empty():
		return {"ok": false, "message": "Nothing is owed on that game."}
	var w := String(get_node("/root/Wallet").address).to_lower()
	if w == "":
		return {"ok": false, "stage": "wallet", "message": "Connect your wallet first (the wallet button on the front door)."}
	if w != String(nm.m["loser"]):
		return {"ok": false, "stage": "wallet", "message": "The connected wallet is not the one that lost #%s." % id}
	var why := pay_refusal(nm.m, w, agreed_stake(id, w))
	if why != "":
		return {"ok": false, "stage": "precondition", "message": "Not paid: %s." % why}
	var r: Dictionary = await TableBook.pay_debt(nm.m["winner"], nm.m["stake"])
	if r.get("ok", false):
		_note("wager", "#%s: your %s transfer is in block %d. Re-reading the debt from the chain…" % [id, NetMatch.fmt(nm.m["stake"]), int(r["block"])], id, nm.m["kind"], true)
		_check_at.erase(id)
		await check_wager(id)
	return r


# --- Going to the table -----------------------------------------------------------------

## The live game (confirming or playing) you are in at `qing`'s `kind` table, or {}.
func table_match(qing: String, kind: String, wallet: String) -> Dictionary:
	wallet = wallet.to_lower()
	var best: Dictionary = {}
	for nm in matches.values():
		var m: Dictionary = nm.m
		if m["kind"] == kind and String(m["room"]) == qing.to_lower() and nm.index_of(wallet) >= 0 and m["status"] in ["confirm", "playing"] \
				and not m.get("abandoned", false):
			best = m
	return best


func match_dict(id: String) -> Dictionary:
	var nm: NetMatch = matches.get(id)
	return nm.m if nm else {}


## Takes the player to the table of game `id` (the territory's arcade door, as a
## walk through the door) and sits them down there.
func go_to_table(id: String) -> void:
	var nm: NetMatch = matches.get(id)
	if nm == null:
		return
	var room := String(nm.m["room"])
	var kind := String(nm.m["kind"])
	pending_seat = {"match": id, "kind": kind, "room": room}
	var tree := get_tree()
	var cs := tree.current_scene
	if cs is GamesPlace and String(cs.qing) == room:
		cs.seat_for_invite()
		return
	var reg := get_node("/root/Registry")
	if not reg.has_territory(room):
		_note("refused", "#%s is played at %s, which is not in this game's territory list." % [id, NetMatch.short(room)], id, kind, false)
		pending_seat = {}
		return
	var gm := get_node("/root/GameManager")
	gm.territory_address = room
	gm.territory_name = String(reg.get_territory(room).get("name", ""))
	Travel.through_door(tree, String(nm.m.get("door", "arcade")))


## A GamesPlace asks on arrival: the kind of table to sit at here ("" for none).
func take_seat(qing: String) -> String:
	if pending_seat.is_empty() or String(pending_seat["room"]) != qing.to_lower():
		return ""
	var kind := String(pending_seat["kind"])
	pending_seat = {}
	return kind


## The table tells the other player you sat down (once per game).
func sat_down(match_id: String) -> void:
	if _sat.has(match_id):
		return
	if send_move(match_id, "sit"):
		_sat[match_id] = true

