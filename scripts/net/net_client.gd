class_name NetClient
extends Node
## One connection to the game server (NetProto). No autoloads used, so the
## scripted test clients (tools/net_selftest.gd) run two of these side by side;
## the Net autoload wraps one for the game.
##
## Sign-in: `signer` is a Callable(message: String) -> String (0x… signature;
## may be a coroutine; "" = refused) for the wallet `signer_wallet`. The Net
## autoload passes the browser wallet's personal_sign; tests pass a fake key.
## The text signed is built HERE (NetProto.login_message: this client's own host,
## the server's nonce and time, checked for shape), never taken from the server.
## The session token is kept for the URL that issued it only.
## Everything a server sends that is shown (names, chat, invites) is cleaned here too:
## the server is somebody's laptop, not a trusted party.

signal status_changed(status: String)          # offline | connecting | online
signal welcomed(id: int)
signal auth_changed(wallet: String)              # "" = guest
signal auth_failed(reason: String)
signal peer_joined(id: int, info: Dictionary)    # also when a peer's profile changes
signal peer_left(id: int)
signal chat(id: int, wallet: String, name: String, text: String, pos: Vector3)
signal voice(id: int, codec: int, data: PackedByteArray)
signal notice(code: String, text: String)
signal room_joined(room: String, count: int)
signal online_list(ok: bool, rows: Array, error: String)  # S_ONLINE: who is signed in
signal invite_update(invite: Dictionary)          # S_INVITE: an invite you sent or got, in its new state
signal match_update(record: Dictionary)           # S_MATCH: a head-to-head game's full record (log included)
signal match_move(match_id: String, move: Dictionary)  # S_MOVE: one new move {seq, by, op, a, t}
signal refused(what: String, error: String)       # S_REFUSED: an invite, answer or move the server refused

signal bump_received(from_id: int, target_id: int, yaw: float, level: int)  # NetBump
signal event(ev: Dictionary)                      # NetEvents.S_EVENT, cleaned (the activity feed)
signal tg_line(line: Dictionary)                  # NetTg.S_TG: one Telegram line (an edit replaces its id), cleaned
signal tg_history(lines: Array)                   # NetTg.S_TG_HISTORY: the last lines, after the welcome
signal tg_status(d: Dictionary)                   # NetTg.S_TG_STATUS: {what: send|prefs, ok, error, retry_s, moments}

const STATE_INTERVAL_MS := 100   # 10 Hz
const STATE_HEARTBEAT_MS := 1000 # resend unchanged state once a second
const PING_S := 15.0
const CONNECT_TIMEOUT_S := 10.0

var url := ""
var status := "offline"
var my_id := -1
var wallet := ""        # verified by the server; "" = guest
var token := ""         # session token from the server (no new signature on reconnect)
var token_pending := false  # a token sign-in was sent and its S_AUTH hasn't come back yet
var server_name := ""
var nonce := ""
var issued := 0         # the server's unix time for this nonce (the sign-in expires LOGIN_TTL_S later)
var login_message := ""  # built by this client (see login_for)
var _token_url := ""     # the URL whose server issued `token`
var room := ""
var profile := {"name": "", "head": "bear", "acc": [], "body": "male"}
var peers := {}         # id → {id, wallet, name, guest, head, acc, body, interp: NetInterp}
var signer: Callable
var signer_wallet := ""
var rtt_ms := -1
var last_info := {}       # the last S_INFO (the server's counts; tools)
var last_voice_seq := -1  # the seq of the voice frame being emitted (tools measure loss and order with it)
var voice_radius := 40.0
var features: Array = []  # what the server understands beyond v1 (S_WELCOME)
var boot := ""            # the server run that welcomed us ("" = an older server that doesn't say)
var counters := {"bytes_in": 0, "bytes_out": 0, "msgs_in": 0, "msgs_out": 0, "state_out": 0, "voice_out": 0,
	"state_bytes_in": 0, "voice_bytes_in": 0, "voice_bytes_out": 0, "state_bytes_out": 0}

var _ws: WebSocketPeer
var _t0 := 0.0
var _polls := 0
var _ping_at := 0.0
var _last_state_ms := -100000
var _last_state := PackedByteArray()
var _signing := false
var _req := 1
var _lb_waiting := {}


func _now_ms() -> int:
	return Time.get_ticks_msec()


func connect_to(p_url: String) -> bool:
	close()
	if p_url != _token_url:
		token = ""  # a session token goes back only to the server that issued it
	url = p_url
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 256 * 1024
	_ws.outbound_buffer_size = 256 * 1024
	_ws.max_queued_packets = 1024
	if _ws.connect_to_url(url) != OK:
		_ws = null
		_set_status("offline")
		return false
	_t0 = _now_ms() / 1000.0
	_polls = 0
	_set_status("connecting")
	return true


func close() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_reset()
	_set_status("offline")


func _reset() -> void:
	my_id = -1
	wallet = ""
	token_pending = false
	room = ""
	_clear_peers()
	for r in _lb_waiting.keys():
		_lb_waiting[r] = {"ok": false, "error": "—"}


func is_online() -> bool:
	return status == "online"


func _set_status(s: String) -> void:
	if s != status:
		status = s
		status_changed.emit(s)


func _send(msg: PackedByteArray) -> bool:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	if _ws.send(msg) != OK:
		return false
	counters["bytes_out"] += msg.size()
	counters["msgs_out"] += 1
	return true


# ── API ────────────────────────────────────────────────────────────────────

func join(p_room: String, p_profile: Dictionary = {}) -> void:
	var to := NetProto.clean_room(p_room)
	if to != room:
		_clear_peers()  # the server tells the old room we left, not us that they did
	room = to
	if not p_profile.is_empty():
		profile = p_profile
	if room != "" and is_online():
		var b := profile.duplicate()
		b["room"] = room
		_send(NetProto.json_msg(NetProto.C_JOIN, b))
		_last_state_ms = -100000


func leave() -> void:
	room = ""
	_send(PackedByteArray([NetProto.C_LEAVE]))
	_clear_peers()


func _clear_peers() -> void:
	for id in peers.keys():
		peers.erase(id)
		peer_left.emit(id)


func set_profile(p_profile: Dictionary) -> void:
	profile = p_profile
	_send(NetProto.json_msg(NetProto.C_PROFILE, profile))


## Throttled to 10 Hz; an unchanged state goes once a second. True if sent.
func send_state(pos: Vector3, yaw: float, flags: int, anim: int = 0, force: bool = false) -> bool:
	if not is_online() or room == "":
		return false
	var now := _now_ms()
	if not force and now - _last_state_ms < STATE_INTERVAL_MS:
		return false
	var body := NetProto.pack_state(pos, yaw, flags, anim)
	if not force and body == _last_state and now - _last_state_ms < STATE_HEARTBEAT_MS:
		return false
	_last_state = body
	_last_state_ms = now
	var msg := NetProto.state_msg(now, pos, yaw, flags, anim)
	if _send(msg):
		counters["state_out"] += 1
		counters["state_bytes_out"] += msg.size()
		return true
	return false


func send_chat(text: String) -> bool:
	text = NetProto.clean_text(text, NetProto.CHAT_MAX_CHARS)
	if text == "" or room == "":
		return false
	return _send(NetProto.json_msg(NetProto.C_CHAT, {"text": text}))


func send_voice(seq: int, codec: int, data: PackedByteArray) -> bool:
	var msg := NetProto.voice_msg(seq, codec, data)
	if _send(msg):
		counters["voice_out"] += 1
		counters["voice_bytes_out"] += msg.size()
		return true
	return false


## A saved session token for the server at `p_url` (Net keeps them between launches,
## per URL and wallet). It is only ever sent to that URL (connect_to drops it otherwise).
func use_token(p_url: String, p_token: String) -> void:
	token = p_token.left(128)
	_token_url = p_url
	if is_online() and url == p_url and wallet == "" and token != "" and not token_pending:
		token_pending = true
		_send(NetProto.json_msg(NetProto.C_AUTH, {"token": token}))


func is_signing() -> bool:
	return _signing


## Signs the server's login message with `signer` and sends it. Returns at
## once if already signed in or a signature is in progress.
func sign_in() -> void:
	if not is_online() or wallet != "" or _signing:
		return
	if token != "":
		token_pending = true
		_send(NetProto.json_msg(NetProto.C_AUTH, {"token": token}))
		return
	if not signer.is_valid() or signer_wallet == "":
		auth_failed.emit("no wallet to sign with")
		return
	if login_message == "":
		auth_failed.emit("this server sent no valid sign-in nonce and time (an older server?), so nothing was signed")
		return
	_signing = true
	var msg := login_message
	var sig = await signer.call(msg)
	_signing = false
	if not (sig is String) or String(sig) == "":
		auth_failed.emit("the signature was refused")
		return
	if not is_online() or msg != login_message:
		return  # reconnected meanwhile: the nonce changed
	_send(NetProto.json_msg(NetProto.C_AUTH, {"wallet": signer_wallet, "sig": String(sig), "host": NetProto.login_host(url)}))


## Pure: the sign-in text for a server at `p_url` that sent (name, nonce, issued), or
## "" when the nonce or time is malformed. Whatever "login" text a server sends is ignored.
static func login_for(p_url: String, p_server_name: String, p_nonce: String, p_issued: int) -> String:
	var host := NetProto.login_host(p_url)
	if host == "" or not NetProto.valid_nonce(p_nonce) or p_issued <= 1600000000:
		return ""
	return NetProto.login_message(p_server_name, host, p_nonce, p_issued)


# ── invites and head-to-head games (signed-in only; the server checks) ──────

func request_online() -> bool:
	_req += 1
	return _send(NetProto.json_msg(NetProto.C_ONLINE, {"req": _req}))


## Invites `to` (an online wallet) to `game` (InviteBook.GAMES) at the table behind
## `door` in territory `room` (a QING address). `stake`: Ⓐ as text, "" for none.
func invite(to: String, game: String, stake: String, p_room: String, door: String = "arcade") -> bool:
	return _send(NetProto.json_msg(NetProto.C_INVITE, {"to": to, "game": game, "stake": stake, "room": p_room, "door": door}))


## accept | decline (an invite you got) or cancel (one you sent).
func answer_invite(id: String, what: String) -> bool:
	return _send(NetProto.json_msg(NetProto.C_ANSWER, {"id": id, "answer": what}))


func send_move(match_id: String, op: String, args: Array = []) -> bool:
	return _send(NetProto.json_msg(NetProto.C_MOVE, {"match": match_id, "op": op, "a": args}))


func send_result(match_id: String, winner: int, digest: String) -> bool:
	return _send(NetProto.json_msg(NetProto.C_RESULT, {"match": match_id, "winner": winner, "digest": digest}))


## {ok, rows} | {ok: false, error}
func lb_top(board: String, n: int = 10) -> Dictionary:
	return await _lb_request(NetProto.C_LB_TOP, {"board": board, "n": n})


## {ok, rank, row} | {ok: false, error}
func lb_submit(board: String, entry: Dictionary) -> Dictionary:
	return await _lb_request(NetProto.C_LB_SUBMIT, {"board": board, "entry": entry})


# ── the daily challenge (NetDaily) ─────────────────────────────────────────

## True when this server runs the daily board (its welcome lists "daily").
func has_daily() -> bool:
	return is_online() and features.has("daily")


## Spends one of today's scored attempts: {ok, attempt, left, seed} | {ok: false, error}.
func daily_start(day: String) -> Dictionary:
	if not has_daily():
		return {"ok": false, "error": "—"}
	return await _lb_request(NetDaily.C_DAILY_START, {"day": day})


## The run's input log (the server replays it): {ok, score, rank, verified, check} | {ok: false, error}.
func daily_submit(day: String, attempt: int, score: int, log_text: String) -> Dictionary:
	if not has_daily():
		return {"ok": false, "error": "—"}
	return await _lb_request(NetDaily.C_DAILY_SUBMIT, {"day": day, "attempt": attempt, "score": score, "log": log_text})


## The day's board, cleaned (NetDaily.clean_board).
func daily_board(day: String, n: int = DailyChallenge.BOARD_SHOW) -> Dictionary:
	if not has_daily():
		return {"ok": false, "error": "—"}
	var b: Dictionary = await _lb_request(NetDaily.C_DAILY_BOARD, {"day": day, "n": n})
	if not b.get("ok", false):
		return {"ok": false, "error": NetProto.clean_text(NetProto.str_of(b.get("error", "—")), 160)}
	return NetDaily.clean_board(b)


func _lb_request(type: int, body: Dictionary) -> Dictionary:
	if not is_online():
		return {"ok": false, "error": "—"}
	var req := _req
	_req += 1
	body["req"] = req
	_lb_waiting[req] = null
	if not _send(NetProto.json_msg(type, body)):
		_lb_waiting.erase(req)
		return {"ok": false, "error": "—"}
	var t0 := _now_ms()
	while _lb_waiting.get(req) == null and _now_ms() - t0 < 20000 and is_inside_tree():
		await get_tree().process_frame
	var res = _lb_waiting.get(req)
	_lb_waiting.erase(req)
	return res if res is Dictionary else {"ok": false, "error": "—"}


## Interpolated pose of a peer at `now_ms` ({} if none yet).
func peer_pose(id: int, now_ms: float) -> Dictionary:
	var p: Dictionary = peers.get(id, {})
	if p.is_empty():
		return {}
	return (p["interp"] as NetInterp).sample(now_ms)


# ── loop ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING:
		_polls += 1
		# wall time and polls both: a loading hitch (seconds without a frame) is not a timeout
		if _now_ms() / 1000.0 - _t0 > CONNECT_TIMEOUT_S and _polls > 30:
			close()
		return
	if st == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_reset()
		_set_status("offline")
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	while _ws and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		counters["bytes_in"] += pkt.size()
		counters["msgs_in"] += 1
		if pkt.size() > 0:
			_handle(pkt)
	var now := _now_ms() / 1000.0
	if is_online() and now - _ping_at > PING_S:
		_ping_at = now
		_send(NetProto.ping_msg(NetProto.C_PING, _now_ms()))


func _handle(m: PackedByteArray) -> void:
	match int(m[0]):
		NetProto.S_STATES:
			counters["state_bytes_in"] += m.size()
			var now := float(_now_ms())
			for e in NetProto.unpack_states(m):
				var p: Dictionary = peers.get(int(e["id"]), {})
				if not p.is_empty():
					(p["interp"] as NetInterp).push(int(e["t"]), e["pos"], e["yaw"], e["flags"], e["anim"], now)
		NetProto.S_VOICE:
			counters["voice_bytes_in"] += m.size()
			var v := NetProto.unpack_voice(m)
			if not v.is_empty() and peers.has(int(v["id"])):
				last_voice_seq = int(v["seq"])
				voice.emit(int(v["id"]), int(v["codec"]), v["data"])
		NetProto.S_PONG:
			if m.size() >= 5:
				rtt_ms = (_now_ms() - m.decode_u32(1)) & 0xFFFFFFFF
		NetProto.S_WELCOME:
			var b := NetProto.json_body(m)
			my_id = NetProto.int_of(b.get("id", -1))
			nonce = NetProto.str_of(b.get("nonce", ""))
			server_name = NetProto.login_name(NetProto.str_of(b.get("server", "")))
			issued = NetProto.int_of(b.get("issued", 0))
			login_message = login_for(url, server_name, nonce, issued)
			voice_radius = clampf(NetProto.num_of(b.get("voice_radius", 40.0), 40.0), 5.0, 500.0)
			features = b.get("features", []) if b.get("features") is Array else []
			var bt := NetProto.str_of(b.get("boot", ""))
			boot = bt if bt.length() <= 32 and NetProto.is_hex(bt) else ""
			# The token goes BEFORE anything joins a room (Net joins on "online"): the server
			# answers a token at once, so the room meets a signed-in player, not a "guest" who
			# signs in a moment later (a "guest arrived" line, the tag flicking guest → name).
			if token != "":
				token_pending = true
				_send(NetProto.json_msg(NetProto.C_AUTH, {"token": token}))
			_set_status("online")
			welcomed.emit(my_id)
			if room != "":
				join(room)
		NetProto.S_AUTH:
			var b := NetProto.json_body(m)
			token_pending = false
			if NetProto.flag_of(b.get("ok", false)):
				wallet = NetProto.clean_wallet(NetProto.str_of(b.get("wallet", "")))
				token = NetProto.str_of(b.get("token", token)).left(128)
				_token_url = url
				auth_changed.emit(wallet)
			else:
				if b.has("nonce"):
					nonce = String(b["nonce"])
					issued = NetProto.int_of(b.get("issued", 0))
					login_message = login_for(url, server_name, nonce, issued)
				if b.get("token_expired", false):
					token = ""
				auth_failed.emit(NetProto.str_of(b.get("reason", "refused")))
		NetProto.S_PEER:
			var b := NetProto.json_body(m)
			var id := NetProto.int_of(b.get("id", -1))
			if id < 0 or id == my_id:
				return
			var p: Dictionary = peers.get(id, {})
			if p.is_empty():
				p = {"interp": NetInterp.new()}
				peers[id] = p
			for k in ["wallet", "name", "guest", "head", "acc", "body"]:
				p[k] = b.get(k, "")
			p["wallet"] = NetProto.clean_wallet(NetProto.str_of(p["wallet"]))
			p["guest"] = p["guest"] if p["guest"] is bool else p["wallet"] == ""
			p["name"] = NetProto.clean_text(NetProto.str_of(p["name"]), NetProto.NAME_MAX_CHARS)
			p["head"] = NetProto.clean_text(NetProto.str_of(p["head"]), 24)
			p["body"] = NetProto.clean_text(NetProto.str_of(p["body"]), 24)
			p["acc"] = (p["acc"] as Array).slice(0, 8).map(func(x): return NetProto.clean_text(str(x), 24)) if p["acc"] is Array else []
			p["id"] = id
			peer_joined.emit(id, p)
		NetProto.S_PEER_LEAVE:
			if m.size() >= 3:
				var id := m.decode_u16(1)
				if peers.erase(id):
					peer_left.emit(id)
		NetProto.S_CHAT:
			var b := NetProto.json_body(m)
			var pa: Array = b.get("pos", []) if b.get("pos") is Array else []
			var pos := Vector3(NetProto.num_of(pa[0]), NetProto.num_of(pa[1]), NetProto.num_of(pa[2])) if pa.size() == 3 else Vector3.INF
			chat.emit(NetProto.int_of(b.get("id", -1)), NetProto.clean_wallet(NetProto.str_of(b.get("wallet", ""))), NetProto.clean_text(NetProto.str_of(b.get("name", "")), NetProto.NAME_MAX_CHARS),
				NetProto.clean_text(NetProto.str_of(b.get("text", "")), NetProto.CHAT_MAX_CHARS), pos)
		NetProto.S_NOTICE:
			var b := NetProto.json_body(m)
			notice.emit(NetProto.clean_text(NetProto.str_of(b.get("code", "")), 24), NetProto.clean_text(NetProto.str_of(b.get("text", "")), 240))
		NetProto.S_LB, NetDaily.S_DAILY_START, NetDaily.S_DAILY_RESULT, NetDaily.S_DAILY_BOARD:
			var b := NetProto.json_body(m)
			var req := NetProto.int_of(b.get("req", 0))
			if _lb_waiting.has(req):
				_lb_waiting[req] = b
		NetEvents.S_EVENT:
			var ev := NetEvents.clean_event(NetProto.json_body(m).get("ev"))
			if not ev.is_empty():
				event.emit(ev)
		NetTg.S_TG:
			var l := NetTg.clean_line(NetProto.json_body(m).get("line"))
			if not l.is_empty():
				tg_line.emit(l)
		NetTg.S_TG_HISTORY:
			var raw = NetProto.json_body(m).get("lines", [])
			var ls: Array = []
			var got: Array = []
			if raw is Array:
				got = (raw as Array).slice(-NetTg.HISTORY)
			for d in got:
				var l := NetTg.clean_line(d)
				if not l.is_empty():
					ls = NetTg.merge(ls, l)
			tg_history.emit(ls)
		NetTg.S_TG_STATUS:
			var b := NetProto.json_body(m)
			var what := NetProto.str_of(b.get("what", ""))
			if what in ["send", "prefs"]:
				tg_status.emit({"what": what, "ok": NetProto.flag_of(b.get("ok", false)), "error": NetProto.clean_text(NetProto.str_of(b.get("error", "")), 200),
					"retry_s": clampi(NetProto.int_of(b.get("retry_s", 0)), 0, 3600), "code": NetProto.clean_text(NetProto.str_of(b.get("code", "")), 16),
					"moments": NetProto.flag_of(b.get("moments", true)) if b.get("moments") is bool else true})
		NetBump.S_BUMP:
			var d := NetBump.unpack_relay(m)
			if not d.is_empty():
				bump_received.emit(int(d["from"]), int(d["target"]), float(d["dir"]), int(d["level"]))
		NetProto.S_ROOM:
			var b := NetProto.json_body(m)
			room_joined.emit(NetProto.str_of(b.get("room", "")), NetProto.int_of(b.get("peers", 0)))
		NetProto.S_ONLINE:
			var b := NetProto.json_body(m)
			var rows: Array = []
			for r in (b.get("players", []) if b.get("players") is Array else []).slice(0, 500):
				var w := NetProto.clean_wallet(NetProto.str_of(r.get("wallet", ""))) if r is Dictionary else ""
				if w != "":
					rows.append({"wallet": w, "name": NetProto.clean_text(NetProto.str_of(r.get("name", "")), NetProto.NAME_MAX_CHARS),
						"room": NetProto.clean_room(NetProto.str_of(r.get("room", ""))).get_slice("/", 0), "busy": NetProto.flag_of(r.get("busy", false))})
			online_list.emit(NetProto.flag_of(b.get("ok", false)), rows, NetProto.clean_text(NetProto.str_of(b.get("error", "")), 200))
		NetProto.S_INVITE:
			var b := NetProto.json_body(m)
			var inv := clean_invite(b.get("invite"))
			if not inv.is_empty():
				invite_update.emit(inv)
		NetProto.S_MATCH:
			var b := NetProto.json_body(m)
			if b.get("match") is Dictionary:
				match_update.emit(b["match"])
		NetProto.S_MOVE:
			var b := NetProto.json_body(m)
			if b.get("move") is Dictionary:
				match_move.emit(NetProto.str_of(b.get("match", "")), b["move"])
		NetProto.S_INFO:
			last_info = NetProto.json_body(m)  # counts only (tools/net_load.gd reads it)
		NetProto.S_REFUSED:
			var b := NetProto.json_body(m)
			refused.emit(NetProto.clean_text(NetProto.str_of(b.get("what", "")), 24), NetProto.clean_text(NetProto.str_of(b.get("error", "")), 200))



## Pure: an S_INVITE's invite, shape-checked ({} when it isn't one this game knows):
## the server is somebody's laptop, and these fields end up in notes and on screen.
static func clean_invite(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var id := NetProto.str_of(d.get("id", ""))
	var from := NetProto.clean_wallet(NetProto.str_of(d.get("from", "")))
	var to := NetProto.clean_wallet(NetProto.str_of(d.get("to", "")))
	var game := NetProto.str_of(d.get("game", ""))
	var state := NetProto.str_of(d.get("state", ""))
	var door := NetProto.str_of(d.get("door", ""))
	var room := NetProto.clean_room(NetProto.str_of(d.get("room", "")))
	if id == "" or id.length() > 16 or not NetProto.is_hex(id) or from == "" or to == "" or not InviteBook.game_ok(game):
		return {}
	if not InviteBook.STATES.has(state) or room == "" or not (door in ["", "room", "arcade"]):
		return {}
	var stake := InviteBook.clean_stake(NetProto.str_of(d.get("stake", "")))
	var mid := NetProto.str_of(d.get("match", ""))
	return {"id": id, "from": from, "from_name": NetProto.clean_text(NetProto.str_of(d.get("from_name", "")), NetProto.NAME_MAX_CHARS),
		"to": to, "to_name": NetProto.clean_text(NetProto.str_of(d.get("to_name", "")), NetProto.NAME_MAX_CHARS), "game": game,
		"stake": stake if stake != "!" else "", "room": room, "door": door, "state": state,
		"created": _num(d.get("created")), "expires": _num(d.get("expires")), "at": _num(d.get("at")),
		"match": mid if mid.length() <= 16 and mid.is_valid_identifier() else ""}


static func _num(v) -> int:
	return int(v) if (v is float or v is int) else 0


# ── bumps (NetBump) ─────────────────────────────────────────────────────────

var _bump_sent := {}      ## target id → ms of the last bump sent


## Tells the room we ran into `target_id` (pushed along `yaw`). Only to a server
## that relays bumps, at most once a NetBump.CLIENT_COOLDOWN_S per target.
func send_bump(target_id: int, yaw: float, level: int) -> bool:
	if not is_online() or room == "" or not features.has("bump"):
		return false
	var now := _now_ms()
	if now - NetProto.int_of(_bump_sent.get(target_id, -100000)) < int(NetBump.CLIENT_COOLDOWN_S * 1000.0):
		return false
	_bump_sent[target_id] = now
	return _send(NetBump.bump_msg(target_id, yaw, level))


# ── the activity feed (NetEvents) ───────────────────────────────────────────

var _place_sent := {}     ## "place|room" → ms of the last one sent


## Tells the server this player walked into `place` (NetEvents.PLACES) of QING `p_room`,
## so players there see "X entered the arcade". Only to a server with "events".
func send_place(place: String, p_room: String) -> bool:
	if not is_online() or wallet == "" or not features.has("events"):
		return false
	var key := place + "|" + p_room
	var now := _now_ms()
	if now - NetProto.int_of(_place_sent.get(key, -1000000)) < int(NetEvents.PLACE_REPEAT_S * 1000.0):
		return false
	_place_sent[key] = now
	return _send(NetEvents.place_msg(place, NetProto.clean_room(p_room)))


## True when this server bridges a Telegram group (S_WELCOME "telegram").
func has_telegram() -> bool:
	return is_online() and features.has(NetTg.FEATURE)


## A line to the server's Telegram group (signed-in players only: the server checks).
func send_tg(text: String) -> bool:
	text = NetProto.clean_text(text, NetTg.OUT_MAX)
	if text == "" or not has_telegram():
		return false
	return _send(NetTg.send_msg(text))


## Whether the server may post this player's game moments to Telegram.
func send_tg_prefs(moments: bool) -> bool:
	if not has_telegram() or wallet == "":
		return false
	return _send(NetTg.prefs_msg(moments))


## A claim the server relays to everyone; each receiver checks it on the chain before showing it.
func send_claim(claim: String, p_room: String) -> bool:
	if not is_online() or wallet == "" or not features.has("events"):
		return false
	return _send(NetEvents.claim_msg(claim, NetProto.clean_room(p_room)))
