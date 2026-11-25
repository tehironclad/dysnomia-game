class_name NetClient
extends Node
## One connection to the game server (NetProto). No autoloads used, so the
## scripted test clients (tools/net_selftest.gd) run two of these side by side;
## the Net autoload wraps one for the game.
##
## Sign-in: `signer` is a Callable(message: String) -> String (0x… signature;
## may be a coroutine; "" = refused) for the wallet `signer_wallet`. The Net
## autoload passes the browser wallet's personal_sign; tests pass a fake key.

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
signal bump_received(from_id: int, target_id: int, yaw: float, level: int)  # NetBump

const STATE_INTERVAL_MS := 100   # 10 Hz
const STATE_HEARTBEAT_MS := 1000 # resend unchanged state once a second
const PING_S := 15.0
const CONNECT_TIMEOUT_S := 10.0

var url := ""
var status := "offline"
var my_id := -1
var wallet := ""        # verified by the server; "" = guest
var token := ""         # session token from the server (no new signature on reconnect)
var server_name := ""
var nonce := ""
var login_message := ""
var room := ""
var profile := {"name": "", "head": "bear", "acc": [], "body": "male"}
var peers := {}         # id → {id, wallet, name, guest, head, acc, body, interp: NetInterp}
var signer: Callable
var signer_wallet := ""
var rtt_ms := -1
var voice_radius := 40.0
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
	room = ""
	for id in peers.keys():
		peers.erase(id)
		peer_left.emit(id)
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
	room = NetProto.clean_room(p_room)
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


## Signs the server's login message with `signer` and sends it. Returns at
## once if already signed in or a signature is in progress.
func sign_in() -> void:
	if not is_online() or wallet != "" or _signing:
		return
	if token != "":
		_send(NetProto.json_msg(NetProto.C_AUTH, {"token": token}))
		return
	if not signer.is_valid() or signer_wallet == "" or login_message == "":
		auth_failed.emit("no wallet to sign with")
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
	_send(NetProto.json_msg(NetProto.C_AUTH, {"wallet": signer_wallet, "sig": String(sig)}))


## {ok, rows} | {ok: false, error}
func lb_top(board: String, n: int = 10) -> Dictionary:
	return await _lb_request(NetProto.C_LB_TOP, {"board": board, "n": n})


## {ok, rank, row} | {ok: false, error}
func lb_submit(board: String, entry: Dictionary) -> Dictionary:
	return await _lb_request(NetProto.C_LB_SUBMIT, {"board": board, "entry": entry})


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
				voice.emit(int(v["id"]), int(v["codec"]), v["data"])
		NetProto.S_PONG:
			if m.size() >= 5:
				rtt_ms = (_now_ms() - m.decode_u32(1)) & 0xFFFFFFFF
		NetProto.S_WELCOME:
			var b := NetProto.json_body(m)
			my_id = int(b.get("id", -1))
			nonce = String(b.get("nonce", ""))
			server_name = String(b.get("server", ""))
			login_message = String(b.get("login", ""))
			voice_radius = float(b.get("voice_radius", 40.0))
			features = b.get("features", []) if b.get("features") is Array else []
			_set_status("online")
			welcomed.emit(my_id)
			if token != "":
				_send(NetProto.json_msg(NetProto.C_AUTH, {"token": token}))
			if room != "":
				join(room)
		NetProto.S_AUTH:
			var b := NetProto.json_body(m)
			if bool(b.get("ok", false)):
				wallet = String(b.get("wallet", ""))
				token = String(b.get("token", token))
				auth_changed.emit(wallet)
			else:
				if b.has("login"):
					login_message = String(b["login"])
				if b.get("token_expired", false):
					token = ""
				auth_failed.emit(String(b.get("reason", "refused")))
		NetProto.S_PEER:
			var b := NetProto.json_body(m)
			var id := int(b.get("id", -1))
			if id < 0 or id == my_id:
				return
			var p: Dictionary = peers.get(id, {})
			if p.is_empty():
				p = {"interp": NetInterp.new()}
				peers[id] = p
			for k in ["wallet", "name", "guest", "head", "acc", "body"]:
				p[k] = b.get(k, "")
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
			var pos := Vector3(float(pa[0]), float(pa[1]), float(pa[2])) if pa.size() == 3 else Vector3.INF
			chat.emit(int(b.get("id", -1)), String(b.get("wallet", "")), String(b.get("name", "")), String(b.get("text", "")), pos)
		NetProto.S_NOTICE:
			var b := NetProto.json_body(m)
			notice.emit(String(b.get("code", "")), String(b.get("text", "")))
		NetProto.S_LB:
			var b := NetProto.json_body(m)
			var req := int(b.get("req", 0))
			if _lb_waiting.has(req):
				_lb_waiting[req] = b
		NetBump.S_BUMP:
			var d := NetBump.unpack_relay(m)
			if not d.is_empty():
				bump_received.emit(int(d["from"]), int(d["target"]), float(d["dir"]), int(d["level"]))
		NetProto.S_ROOM:
			var b := NetProto.json_body(m)
			room_joined.emit(String(b.get("room", "")), int(b.get("peers", 0)))


# ── bumps (NetBump) ─────────────────────────────────────────────────────────

var features: Array = []  ## what the server said it understands (S_WELCOME)
var _bump_sent := {}      ## target id → ms of the last bump sent


## Tells the room we ran into `target_id` (pushed along `yaw`). Only to a server
## that relays bumps, at most once a NetBump.CLIENT_COOLDOWN_S per target.
func send_bump(target_id: int, yaw: float, level: int) -> bool:
	if not is_online() or room == "" or not features.has("bump"):
		return false
	var now := _now_ms()
	if now - int(_bump_sent.get(target_id, -100000)) < int(NetBump.CLIENT_COOLDOWN_S * 1000.0):
		return false
	_bump_sent[target_id] = now
	return _send(NetBump.bump_msg(target_id, yaw, level))
