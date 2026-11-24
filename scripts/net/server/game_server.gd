class_name GameServer
extends Node
## The free game server (docs/SERVER.md): runs headless on the owner's own
## laptop and is reached through a tunnel (Tailscale Funnel or Cloudflare
## Tunnel) that provides TLS and hides the laptop's IP. Listens on 127.0.0.1.
##
## What it does: rooms per QING (presence relayed at 10 Hz, quantised), free
## text chat, push-to-talk voice relayed within a radius, wallet sign-in by a
## free personal_sign (ecrecover here, on a worker thread), leaderboards.
## What it never does: sign, hold keys, or say anything about the chain.
##
## Limits: message size per type (NetProto.MAX_SIZE), a token bucket per
## connection for each kind of message and for bytes, a cap on connections
## (overall, per IP when not behind a tunnel, and still handshaking), a
## handshake and an idle timeout, strikes for malformed input, a global budget
## for signature checks. Logs to user://server/server.log (rotated at 5 MB).

const HANDSHAKE_S := 15.0  # a client loading a territory may not poll for seconds
const IDLE_S := 75.0
const TICK_S := 0.1
const TOKEN_TTL_S := 86400
const MAX_STRIKES := 20
const MAX_FLOOD := 400          # rate-limited drops in the flood window before a disconnect
const FLOOD_WINDOW_S := 20.0
const AUTH_ATTEMPTS := 5
const LOG_MAX_BYTES := 5 * 1024 * 1024
const SLOW_CLIENT_BYTES := 256 * 1024  # skip presence/voice to a client this far behind

var port := 8787
var bind_address := "127.0.0.1"
var server_name := "dysnomia"
var max_connections := 200
var max_pending := 32
var max_per_ip := 8
var room_cap := 64
var voice_radius := 40.0
var data_dir := "user://server"
var quiet := false

var lb: Leaderboards
var stats := {"connections": 0, "auths": 0, "auth_failures": 0, "chats": 0, "voice_frames": 0, "states": 0,
	"bytes_in": 0, "bytes_out": 0, "kicked": 0, "throttled": 0, "refused": 0}

var _tcp := TCPServer.new()
var _peers := {}               # id → Peer
var _rooms := {}               # room → {id: true}
var _next_id := 1
var _tokens := {}              # token → {wallet, exp}
var _auth_bucket := TokenBucket.new(4.0, 8.0)
var _tick := 0.0
var _stats_at := 0.0
var _save_at := 0.0
var _log: FileAccess
var _started_s := 0.0
var _mutex := Mutex.new()


class Peer:
	extends RefCounted
	var id := 0
	var ws: WebSocketPeer
	var ip := ""
	var opened := false
	var connected_s := 0.0
	var last_seen_s := 0.0
	var nonce := ""
	var wallet := ""
	var name := ""
	var head := "bear"
	var acc: Array = []
	var body := "male"
	var room := ""
	var state := PackedByteArray()   # 18 bytes: sender t u16 + NetProto state
	var state_dirty := false
	var pos := Vector3.ZERO
	var has_pos := false
	var strikes := 0
	var flood := 0
	var flood_at := 0.0
	var auth_task := -1
	var auth_claim := ""
	var auth_result := ""
	var auth_attempts := 0
	var guest_noticed := false
	var b_state := TokenBucket.new(15.0, 30.0)
	var b_voice := TokenBucket.new(60.0, 120.0)
	var b_chat := TokenBucket.new(1.0, 4.0)
	var b_ctrl := TokenBucket.new(5.0, 20.0)
	var b_lb := TokenBucket.new(0.5, 4.0)
	var b_bytes := TokenBucket.new(48000.0, 96000.0)
	var b_msgs := TokenBucket.new(120.0, 240.0)  # every message: 10 states + 50 voice frames a second leave room


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func start() -> bool:
	DirAccess.make_dir_recursive_absolute(data_dir)
	_open_log()
	# Precompute the curve and hash tables here: worker threads only read them.
	Keccak.digest(PackedByteArray())
	Secp256k1._setup()
	lb = Leaderboards.new(data_dir.path_join("leaderboards.json"))
	lb.add_verifier("*fair:*", FairVerifier.verify)
	_load_tokens()
	var err := _tcp.listen(port, bind_address)
	if err != OK:
		log_line("ERROR cannot listen on %s:%d (error %d). Is another server running?" % [bind_address, port, err])
		return false
	_started_s = _now()
	log_line("Dysnomia game server '%s' listening on ws://%s:%d (protocol v%d). Data: %s" % [
		server_name, bind_address, port, NetProto.VERSION, ProjectSettings.globalize_path(data_dir)])
	return true


func stop() -> void:
	for id in _peers.keys():
		var p: Peer = _peers[id]
		p.ws.close(1001, "server stopping")
	_tcp.stop()
	if lb:
		lb.save()
	_save_tokens()
	log_line("stopped")


func connection_count() -> int:
	return _peers.size()


# ── logging ────────────────────────────────────────────────────────────────

func _open_log() -> void:
	var path := data_dir.path_join("server.log")
	if FileAccess.file_exists(path):
		_log = FileAccess.open(path, FileAccess.READ_WRITE)
		if _log:
			_log.seek_end()
	else:
		_log = FileAccess.open(path, FileAccess.WRITE)


func log_line(text: String) -> void:
	var line := "%s  %s" % [Time.get_datetime_string_from_system(true, true), text]
	if not quiet:
		print(line)
	if _log == null:
		return
	_log.store_line(line)
	_log.flush()
	if _log.get_length() > LOG_MAX_BYTES:
		_log.close()
		var path := ProjectSettings.globalize_path(data_dir.path_join("server.log"))
		DirAccess.remove_absolute(path + ".1")
		DirAccess.rename_absolute(path, path + ".1")
		_log = FileAccess.open(data_dir.path_join("server.log"), FileAccess.WRITE)


# ── main loop ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _tcp.is_listening():
		return
	var now := _now()
	_accept(now)
	for id in _peers.keys():
		var p: Peer = _peers.get(id)
		if p != null:
			_poll_peer(p, now)
	_tick += delta
	if _tick >= TICK_S:
		_tick = 0.0
		_broadcast_states()
	if now - _save_at > 10.0:
		_save_at = now
		lb.save()
		_expire_tokens()
	if now - _stats_at > 300.0:
		_stats_at = now
		log_line("stats: %d connected, %d rooms, %s" % [_peers.size(), _rooms.size(), JSON.stringify(stats)])


func _accept(now: float) -> void:
	while _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		if conn == null:
			break
		var ip := conn.get_connected_host()
		var pending := 0
		var same_ip := 0
		for p in _peers.values():
			if not p.opened:
				pending += 1
			if p.ip == ip:
				same_ip += 1
		var loopback := ip == "127.0.0.1" or ip == "::1" or ip.begins_with("::ffff:127.")
		if _peers.size() >= max_connections or pending >= max_pending or (not loopback and same_ip >= max_per_ip):
			stats["refused"] += 1
			conn.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 2 * NetProto.MAX_MESSAGE + 1024
		ws.outbound_buffer_size = 1024 * 1024
		ws.max_queued_packets = 512
		if ws.accept_stream(conn) != OK:
			conn.disconnect_from_host()
			continue
		var p := Peer.new()
		p.id = _alloc_id()
		p.ws = ws
		p.ip = ip
		p.connected_s = now
		p.last_seen_s = now
		_peers[p.id] = p


func _alloc_id() -> int:
	for _i in 65535:
		var id := _next_id
		_next_id = 1 if _next_id >= 65535 else _next_id + 1
		if not _peers.has(id):
			return id
	return 0


func _poll_peer(p: Peer, now: float) -> void:
	p.ws.poll()
	var st := p.ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING:
		if now - p.connected_s > HANDSHAKE_S:
			_drop(p, "handshake timeout")
		return
	if st == WebSocketPeer.STATE_CLOSED:
		_drop(p, "closed %d" % p.ws.get_close_code())
		return
	if st != WebSocketPeer.STATE_OPEN:
		return
	if not p.opened:
		p.opened = true
		p.nonce = Crypto.new().generate_random_bytes(16).hex_encode()
		stats["connections"] += 1
		_send(p, NetProto.json_msg(NetProto.S_WELCOME, {"id": p.id, "nonce": p.nonce, "server": server_name,
			"v": NetProto.VERSION, "login": NetProto.login_message(server_name, p.nonce), "voice_radius": voice_radius,
			"features": NetProto.FEATURES}))
	var n := 0
	while p.ws.get_available_packet_count() > 0 and n < 200:
		n += 1
		var pkt := p.ws.get_packet()
		p.last_seen_s = now
		stats["bytes_in"] += pkt.size()
		if p.ws.was_string_packet():
			_strike(p, "text frame")
			continue
		if not p.b_bytes.take(now, pkt.size()) or not p.b_msgs.take(now):
			_throttled(p, now)
			continue
		if not NetProto.size_ok(pkt):
			_strike(p, "bad size or type (%d bytes, type %d)" % [pkt.size(), pkt[0] if pkt.size() > 0 else -1])
			continue
		_handle(p, pkt, now)
		if not _peers.has(p.id):
			return
	if p.auth_task >= 0 and WorkerThreadPool.is_task_completed(p.auth_task):
		WorkerThreadPool.wait_for_task_completion(p.auth_task)
		p.auth_task = -1
		_finish_auth(p)
	if now - p.last_seen_s > IDLE_S:
		_drop(p, "idle")


func _strike(p: Peer, why: String) -> void:
	p.strikes += 1
	if p.strikes == 1 or p.strikes % 5 == 0:
		log_line("peer %d (%s): %s [strike %d]" % [p.id, p.ip, why, p.strikes])
	if p.strikes >= MAX_STRIKES:
		stats["kicked"] += 1
		p.ws.close(1008, "too many malformed messages")
		_drop(p, "kicked: malformed input")


func _throttled(p: Peer, now: float) -> void:
	stats["throttled"] += 1
	if now - p.flood_at > FLOOD_WINDOW_S:
		p.flood_at = now
		p.flood = 0
	p.flood += 1
	if p.flood >= MAX_FLOOD:
		stats["kicked"] += 1
		p.ws.close(1008, "flooding")
		_drop(p, "kicked: flooding")


func _drop(p: Peer, why: String) -> void:
	if not _peers.has(p.id):
		return
	_leave_room(p)
	_peers.erase(p.id)
	if p.opened:
		log_line("peer %d left (%s) %s" % [p.id, p.wallet if p.wallet != "" else "guest", why])
	if p.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		p.ws.close()


func _send(p: Peer, msg: PackedByteArray) -> void:
	if p.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if p.ws.send(msg) == OK:
			stats["bytes_out"] += msg.size()


func _notice(p: Peer, code: String, text: String) -> void:
	_send(p, NetProto.json_msg(NetProto.S_NOTICE, {"code": code, "text": text}))


# ── messages ───────────────────────────────────────────────────────────────

func _handle(p: Peer, msg: PackedByteArray, now: float) -> void:
	var t: int = msg[0]
	match t:
		NetProto.C_STATE:
			if not p.b_state.take(now):
				_throttled(p, now)
				return
			p.state = msg.slice(1)
			var d := NetProto.unpack_state(msg, 3)
			p.pos = d["pos"]
			p.has_pos = true
			p.state_dirty = true
			stats["states"] += 1
		NetProto.C_VOICE:
			_voice(p, msg, now)
		NetProto.C_CHAT:
			_chat(p, msg, now)
		NetProto.C_PING:
			if p.b_ctrl.take(now):
				_send(p, NetProto.ping_msg(NetProto.S_PONG, msg.decode_u32(1)))
		NetProto.C_JOIN:
			if not p.b_ctrl.take(now):
				_throttled(p, now)
				return
			_join(p, NetProto.json_body(msg))
		NetProto.C_PROFILE:
			if not p.b_ctrl.take(now):
				_throttled(p, now)
				return
			_set_profile(p, NetProto.json_body(msg))
			if p.room != "":
				_room_send(p.room, _peer_msg(p), -1)
		NetProto.C_LEAVE:
			if not p.b_ctrl.take(now):
				_throttled(p, now)
				return
			_leave_room(p)
		NetProto.C_AUTH:
			if not p.b_ctrl.take(now):
				_throttled(p, now)
				return
			_auth(p, NetProto.json_body(msg), now)
		NetProto.C_LB_TOP:
			if not p.b_ctrl.take(now):
				_throttled(p, now)
				return
			var b := NetProto.json_body(msg)
			var board := Leaderboards.clean_board(String(b.get("board", "")))
			_send(p, NetProto.json_msg(NetProto.S_LB, {"req": int(b.get("req", 0)), "ok": board != "", "board": board,
				"rows": lb.top(board, int(b.get("n", 10))) if board != "" else [], "error": "" if board != "" else "bad board id"}))
		NetProto.C_LB_SUBMIT:
			_lb_submit(p, NetProto.json_body(msg), now)
		NetProto.C_INFO:
			if not p.b_ctrl.take(now):
				_throttled(p, now)
				return
			var b := NetProto.json_body(msg)
			_send(p, NetProto.json_msg(NetProto.S_INFO, info(int(b.get("req", 0)), now)))
		_:
			_strike(p, "unknown type %d" % t)


## What the server is doing, for the site's pulse node (entropy-ai-pulse/pulse-node)
## and anyone else who asks: counts only, never wallets or positions.
func info(req: int, now: float) -> Dictionary:
	var players := 0
	var signed_in := 0
	for p in _peers.values():
		if p.room != "":
			players += 1
			if p.wallet != "":
				signed_in += 1
	var rooms: Array = []
	for r in _rooms:
		rooms.append({"room": r, "players": (_rooms[r] as Dictionary).size()})
	rooms.sort_custom(func(a, b): return int(a["players"]) > int(b["players"]))
	var boards: Array = []
	for id in lb.boards:
		boards.append({"board": id, "rows": (lb.boards[id] as Array).size()})
	boards.sort_custom(func(a, b): return int(a["rows"]) > int(b["rows"]))
	return {"req": req, "server": server_name, "v": NetProto.VERSION, "uptime_s": int(now - _started_s),
		"connections": _peers.size(), "players": players, "signed_in": signed_in, "guests": players - signed_in,
		"rooms": rooms.slice(0, 200), "boards": boards.slice(0, 200)}


func _set_profile(p: Peer, b: Dictionary) -> void:
	p.name = NetProto.clean_text(String(b.get("name", "")), NetProto.NAME_MAX_CHARS)
	var head := String(b.get("head", "bear"))
	p.head = head if head.is_valid_identifier() and head.length() <= 16 else "bear"
	var body := String(b.get("body", "male"))
	p.body = body if body in ["male", "female"] else "male"
	p.acc = []
	if b.get("acc") is Array:
		for a in (b["acc"] as Array).slice(0, 4):
			if a is String and (a as String).is_valid_identifier() and (a as String).length() <= 16:
				p.acc.append(a)


func _peer_msg(p: Peer) -> PackedByteArray:
	return NetProto.json_msg(NetProto.S_PEER, {"id": p.id, "wallet": p.wallet, "guest": p.wallet == "",
		"name": p.name, "head": p.head, "acc": p.acc, "body": p.body})


func _join(p: Peer, b: Dictionary) -> void:
	var room := NetProto.clean_room(String(b.get("room", "")))
	if room == "":
		_notice(p, "room", "That room is not a QING address.")
		return
	_set_profile(p, b)
	if room == p.room:
		return
	_leave_room(p)
	var members: Dictionary = _rooms.get(room, {})
	if members.size() >= room_cap:
		_notice(p, "full", "This territory is full right now (%d players)." % room_cap)
		return
	members[p.id] = true
	_rooms[room] = members
	p.room = room
	p.state_dirty = p.state.size() == 18
	_send(p, NetProto.json_msg(NetProto.S_ROOM, {"room": room, "peers": members.size()}))
	var states: Array = []
	for id in members:
		if id == p.id:
			continue
		var o: Peer = _peers[id]
		_send(p, _peer_msg(o))
		if o.state.size() == 18:
			states.append([o.id, o.state])
	if not states.is_empty():
		_send(p, NetProto.states_msg(states))
	_room_send(room, _peer_msg(p), p.id)
	log_line("peer %d (%s) joined %s · %d here" % [p.id, p.wallet if p.wallet != "" else "guest", room, members.size()])


func _leave_room(p: Peer) -> void:
	if p.room == "":
		return
	var members: Dictionary = _rooms.get(p.room, {})
	members.erase(p.id)
	if members.is_empty():
		_rooms.erase(p.room)
	else:
		_room_send(p.room, NetProto.id_msg(NetProto.S_PEER_LEAVE, p.id), -1)
	p.room = ""


func _room_send(room: String, msg: PackedByteArray, except_id: int) -> void:
	for id in _rooms.get(room, {}):
		if id != except_id:
			_send(_peers[id], msg)


func _broadcast_states() -> void:
	for room in _rooms:
		var members: Dictionary = _rooms[room]
		var entries: Array = []
		for id in members:
			var p: Peer = _peers[id]
			if p.state_dirty and p.state.size() == 18:
				entries.append([id, p.state])
				p.state_dirty = false
		if entries.is_empty():
			continue
		for id in members:
			var to: Peer = _peers[id]
			if to.ws.get_current_outbound_buffered_amount() > SLOW_CLIENT_BYTES:
				continue
			var mine := entries.filter(func(e): return e[0] != id)
			while not mine.is_empty():
				_send(to, NetProto.states_msg(mine.slice(0, 255)))
				mine = mine.slice(255)


func _chat(p: Peer, msg: PackedByteArray, now: float) -> void:
	if p.room == "":
		return
	if p.wallet == "":
		_notice(p, "guest", "Guests can see everyone but can't talk. Sign in with your wallet (a free signature, F2 · Online).")
		return
	if not p.b_chat.take(now):
		stats["throttled"] += 1
		_notice(p, "slow", "Slow down: one message a second.")
		return
	var text := NetProto.clean_text(String(NetProto.json_body(msg).get("text", "")), NetProto.CHAT_MAX_CHARS)
	if text == "":
		return
	stats["chats"] += 1
	log_line("chat %s %s (%s): %s" % [p.room.left(10), p.wallet, p.name, text])
	_room_send(p.room, NetProto.json_msg(NetProto.S_CHAT, {"id": p.id, "wallet": p.wallet, "name": p.name, "text": text,
		"pos": [p.pos.x, p.pos.y, p.pos.z] if p.has_pos else []}), -1)


func _voice(p: Peer, msg: PackedByteArray, now: float) -> void:
	if p.wallet == "":
		if not p.guest_noticed:
			p.guest_noticed = true
			_notice(p, "guest", "Guests can listen but can't talk. Sign in with your wallet to use voice.")
		return
	if p.room == "" or not p.has_pos or msg.size() < 5:
		return
	if not p.b_voice.take(now):
		_throttled(p, now)
		return
	var codec: int = msg[3]
	if codec != NetProto.CODEC_ADPCM and codec != NetProto.CODEC_ULAW:
		_strike(p, "unknown codec %d" % codec)
		return
	stats["voice_frames"] += 1
	var out := NetProto.voice_relay(p.id, msg)
	var r2 := voice_radius * voice_radius
	for id in _rooms.get(p.room, {}):
		if id == p.id:
			continue
		var o: Peer = _peers[id]
		if o.has_pos and o.pos.distance_squared_to(p.pos) <= r2 and o.ws.get_current_outbound_buffered_amount() < SLOW_CLIENT_BYTES:
			_send(o, out)


# ── sign-in ────────────────────────────────────────────────────────────────

func _auth(p: Peer, b: Dictionary, now: float) -> void:
	if p.wallet != "" or p.auth_task >= 0:
		return
	var tok := String(b.get("token", ""))
	if tok != "":
		var rec: Dictionary = _tokens.get(tok, {})
		if not rec.is_empty() and int(rec["exp"]) > Time.get_unix_time_from_system():
			_authed(p, String(rec["wallet"]), tok)
		else:
			_send(p, NetProto.json_msg(NetProto.S_AUTH, {"ok": false, "reason": "token expired", "token_expired": true}))
		return
	p.auth_attempts += 1
	if p.auth_attempts > AUTH_ATTEMPTS:
		_send(p, NetProto.json_msg(NetProto.S_AUTH, {"ok": false, "reason": "too many attempts; reconnect"}))
		return
	var claim := NetProto.clean_wallet(String(b.get("wallet", "")))
	var sig := String(b.get("sig", ""))
	if claim == "" or sig.length() != 132:
		_send(p, NetProto.json_msg(NetProto.S_AUTH, {"ok": false, "reason": "malformed sign-in"}))
		return
	if not _auth_bucket.take(now):
		_send(p, NetProto.json_msg(NetProto.S_AUTH, {"ok": false, "reason": "server busy; try again in a moment"}))
		return
	p.auth_claim = claim
	var message := NetProto.login_message(server_name, p.nonce)
	p.auth_task = WorkerThreadPool.add_task(_auth_job.bind(p, message, sig), false, "ecrecover")


## Worker thread: pure math, writes only to this peer's auth_result.
func _auth_job(p: Peer, message: String, sig: String) -> void:
	var who := EthSign.recover_personal(message, sig)
	_mutex.lock()
	p.auth_result = who
	_mutex.unlock()


func _finish_auth(p: Peer) -> void:
	_mutex.lock()
	var who := p.auth_result
	_mutex.unlock()
	# A fresh nonce either way: a signature is good for one attempt.
	p.nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	if who != "" and who == p.auth_claim:
		var tok := Crypto.new().generate_random_bytes(24).hex_encode()
		_tokens[tok] = {"wallet": who, "exp": int(Time.get_unix_time_from_system()) + TOKEN_TTL_S}
		_save_tokens()
		_authed(p, who, tok)
	else:
		stats["auth_failures"] += 1
		log_line("peer %d sign-in refused: claimed %s, signature recovers %s" % [p.id, p.auth_claim, who if who != "" else "nothing"])
		_send(p, NetProto.json_msg(NetProto.S_AUTH, {"ok": false, "reason": "the signature does not match that wallet",
			"login": NetProto.login_message(server_name, p.nonce), "nonce": p.nonce}))


func _authed(p: Peer, wallet: String, tok: String) -> void:
	p.wallet = wallet
	stats["auths"] += 1
	log_line("peer %d signed in as %s" % [p.id, wallet])
	_send(p, NetProto.json_msg(NetProto.S_AUTH, {"ok": true, "wallet": wallet, "token": tok}))
	if p.room != "":
		_room_send(p.room, _peer_msg(p), -1)


func _expire_tokens() -> void:
	var now := int(Time.get_unix_time_from_system())
	for t in _tokens.keys():
		if int(_tokens[t]["exp"]) < now:
			_tokens.erase(t)


func _load_tokens() -> void:
	var path := data_dir.path_join("tokens.json")
	if not FileAccess.file_exists(path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if j is Dictionary:
		for t in j:
			if j[t] is Dictionary and NetProto.clean_wallet(String(j[t].get("wallet", ""))) != "":
				_tokens[String(t)] = {"wallet": String(j[t]["wallet"]), "exp": int(j[t].get("exp", 0))}


func _save_tokens() -> void:
	var f := FileAccess.open(data_dir.path_join("tokens.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_tokens))


# ── leaderboards ───────────────────────────────────────────────────────────

func _lb_submit(p: Peer, b: Dictionary, now: float) -> void:
	var req := int(b.get("req", 0))
	if p.wallet == "":
		_send(p, NetProto.json_msg(NetProto.S_LB, {"req": req, "ok": false, "error": "sign in to submit a score"}))
		return
	if not p.b_lb.take(now):
		_send(p, NetProto.json_msg(NetProto.S_LB, {"req": req, "ok": false, "error": "slow down"}))
		return
	var entry = b.get("entry", {})
	if not (entry is Dictionary):
		_send(p, NetProto.json_msg(NetProto.S_LB, {"req": req, "ok": false, "error": "entry must be an object"}))
		return
	var board := String(b.get("board", ""))
	var res: Dictionary = await lb.submit(board, entry, p.wallet, p.name)
	if not _peers.has(p.id):
		return
	res["req"] = req
	if res.get("ok", false):
		log_line("score %s %s %d (%s)" % [board, p.wallet, int(res["row"]["score"]), res["row"]["check"]])
	_send(p, NetProto.json_msg(NetProto.S_LB, res))
