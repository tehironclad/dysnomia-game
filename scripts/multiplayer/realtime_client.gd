class_name RealtimeClient
extends Node
## Native Supabase Realtime client (Phoenix channels over Godot's WebSocketPeer).
##
## Speaks the same wire protocol supabase-js uses (serializer vsn 1.0.0, JSON objects):
##   connect   wss://<project>.supabase.co/realtime/v1/websocket?apikey=<anon>&vsn=1.0.0
##   join      {topic:"realtime:<channel>", event:"phx_join", ref, join_ref,
##              payload:{config:{broadcast:{self:false, ack:false}, presence:{key:<id>},
##                       postgres_changes:[], private:false}, access_token:<anon>}}
##   heartbeat {topic:"phoenix", event:"heartbeat", payload:{}, ref}   every 25 s
##   track     {topic, event:"presence", payload:{type:"presence", event:"track", payload:{...}}}
##   broadcast {topic, event:"broadcast", payload:{type:"broadcast", event:<name>, payload:{...}}}
##   server →  phx_reply, presence_state {key:{metas:[...]}}, presence_diff {joins, leaves},
##             broadcast {type, event, payload}, phx_error / phx_close, system
##
## Because the protocol is identical, players on the browser bridge (wallet.html +
## supabase-js) and players on this native client share channels and see each other.
##
## Degrades silently: an unreachable / unresolvable / unconfigured URL logs ONE line,
## then retries with exponential backoff capped at 60 s. Nothing is queued while offline
## (positions are ephemeral); joined channels and tracked presence are replayed on reconnect.
##
## URL / key resolution (first wins):
##   env DYSNOMIA_REALTIME_URL / DYSNOMIA_REALTIME_KEY
##   cmdline user args  -- --realtime-url=<url> --realtime-key=<key>
##   Config.realtime_url / Config.realtime_anon_key   (user://settings.cfg [multiplayer])
## Accepts a bare project URL (https://x.supabase.co), a ws(s):// URL, or a full
## .../realtime/v1/websocket URL. Set realtime_url to "" (or realtime_enabled=false) to disable.

signal connection_changed(connected: bool)
signal channel_joined(channel: String)
signal channel_left(channel: String)
## Full presence state after (re)join. state: key → first meta (phx_ref stripped).
signal presence_synced(channel: String, state: Dictionary)
## A key appeared in the channel (first meta for that key).
signal presence_joined(channel: String, key: String, meta: Dictionary)
## An existing key re-tracked (e.g. username/tier/position changed).
signal presence_updated(channel: String, key: String, meta: Dictionary)
## The last meta for a key left (disconnect, untrack, leave).
signal presence_left(channel: String, key: String)
signal broadcast_received(channel: String, event: String, payload: Dictionary)

const HEARTBEAT_INTERVAL: float = 25.0
const CONNECT_TIMEOUT: float = 12.0
const JOIN_TIMEOUT: float = 10.0
const BACKOFF_STEPS: Array[float] = [1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 60.0]
const VSN: String = "1.0.0"

enum State { IDLE, RESOLVING, CONNECTING, OPEN }

# ── Configuration ──
var endpoint: String = ""      # Resolved ws(s)://.../websocket?apikey=..&vsn=..
var anon_key: String = ""
var enabled: bool = true
var verbose: bool = false      # Extra logging (tests)

# ── Connection state ──
var _ws: WebSocketPeer = null
var _state: int = State.IDLE
var _state_since: float = 0.0
var _resolve_id: int = -1
var _host: String = ""
var _attempt: int = 0
var _next_attempt_at: float = 0.0
var _failure_logged: bool = false
var _was_open: bool = false
var _ref: int = 0
var _hb_elapsed: float = 0.0
var _hb_pending_ref: String = ""

# ── Channels ──
## channel → {key, track, joined, join_ref, join_sent_at, rejoin_at, presence:{key:[metas]}}
var _channels: Dictionary = {}


func _ready() -> void:
	if endpoint.is_empty():
		configure()


func configure(url: String = "", key: String = "") -> void:
	## Resolve the endpoint. Empty args → env / cmdline / Config.
	var u := url
	var k := key
	if u.is_empty():
		u = OS.get_environment("DYSNOMIA_REALTIME_URL")
	if k.is_empty():
		k = OS.get_environment("DYSNOMIA_REALTIME_KEY")
	for arg in OS.get_cmdline_user_args():
		if u.is_empty() and arg.begins_with("--realtime-url="):
			u = arg.substr(15)
		elif k.is_empty() and arg.begins_with("--realtime-key="):
			k = arg.substr(15)
	var cfg := _config_node()
	if cfg:
		if u.is_empty():
			u = str(cfg.get("realtime_url"))
		if k.is_empty():
			k = str(cfg.get("realtime_anon_key"))
		if cfg.get("realtime_enabled") == false:
			enabled = false
	if u == "<null>":
		u = ""
	if k == "<null>":
		k = ""
	anon_key = k
	endpoint = build_endpoint(u, k)
	if endpoint.is_empty():
		enabled = false
	_host = _extract_host(endpoint)
	# A new endpoint gets a fresh connection + fresh "log once" budget.
	if _ws != null:
		_drop_socket()
	_attempt = 0
	_next_attempt_at = 0.0
	_failure_logged = false


static func build_endpoint(url: String, key: String) -> String:
	var u := url.strip_edges()
	if u.is_empty():
		return ""
	if u.begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.begins_with("http://"):
		u = "ws://" + u.substr(7)
	elif not (u.begins_with("ws://") or u.begins_with("wss://")):
		u = "wss://" + u
	var query := ""
	var qpos := u.find("?")
	if qpos >= 0:
		query = u.substr(qpos + 1)
		u = u.left(qpos)
	while u.ends_with("/"):
		u = u.left(u.length() - 1)
	if u.ends_with("/realtime/v1"):
		u += "/websocket"
	elif not u.contains("/realtime/v1") and u.count("/") <= 2:
		u += "/realtime/v1/websocket"
	var params: PackedStringArray = []
	if not query.is_empty():
		params.append(query)
	if not key.is_empty() and not query.contains("apikey="):
		params.append("apikey=" + key.uri_encode())
	if not query.contains("vsn="):
		params.append("vsn=" + VSN)
	return u + "?" + "&".join(params)


static func _extract_host(ep: String) -> String:
	var s := ep
	var p := s.find("://")
	if p >= 0:
		s = s.substr(p + 3)
	for sep in ["/", "?"]:
		var i := s.find(sep)
		if i >= 0:
			s = s.left(i)
	if s.begins_with("["):
		return s.substr(1, s.find("]") - 1)
	var c := s.rfind(":")
	if c >= 0:
		s = s.left(c)
	return s


func _config_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("Config")
	return null


# ─── Public API ─────────────────────────────────────────────────────────

func is_open() -> bool:
	return _state == State.OPEN


func is_joined(channel: String) -> bool:
	return _channels.has(channel) and _channels[channel].joined


func has_channel(channel: String) -> bool:
	return _channels.has(channel)


func join(channel: String, presence_key: String, track_payload: Dictionary = {}) -> void:
	## Join (or re-key) a channel. track_payload is tracked as presence once joined.
	if _channels.has(channel):
		var ch: Dictionary = _channels[channel]
		if ch.key == presence_key:
			if not track_payload.is_empty():
				track(channel, track_payload)
			return
		leave(channel)  # Presence key changed → rejoin under the new key
	_channels[channel] = {
		"key": presence_key, "track": track_payload.duplicate(), "joined": false,
		"join_ref": "", "join_sent_at": -1.0, "rejoin_at": 0.0, "presence": {},
	}
	if _state == State.OPEN:
		_send_join(channel)


func leave(channel: String) -> void:
	if not _channels.has(channel):
		return
	var ch: Dictionary = _channels[channel]
	if _state == State.OPEN and ch.joined:
		_push(_topic(channel), "phx_leave", {}, ch.join_ref)
	var was_joined: bool = ch.joined
	var keys: Array = ch.presence.keys()
	_channels.erase(channel)
	for k in keys:
		presence_left.emit(channel, k)
	if was_joined:
		channel_left.emit(channel)


func leave_all() -> void:
	for c in _channels.keys():
		leave(c)


func track(channel: String, payload: Dictionary) -> void:
	## Set (and send if joined) this client's presence payload for the channel.
	if not _channels.has(channel):
		return
	_channels[channel].track = payload.duplicate()
	if _channels[channel].joined:
		_push(_topic(channel), "presence",
			{"type": "presence", "event": "track", "payload": payload},
			_channels[channel].join_ref)


func send_broadcast(channel: String, event: String, payload: Dictionary) -> bool:
	## Fire-and-forget broadcast. Returns false (silently) when not joined.
	if _state != State.OPEN or not is_joined(channel):
		return false
	_push(_topic(channel), "broadcast",
		{"type": "broadcast", "event": event, "payload": payload},
		_channels[channel].join_ref)
	return true


func presence_keys(channel: String) -> Array:
	if not _channels.has(channel):
		return []
	return _channels[channel].presence.keys()


func presence_count(channel: String) -> int:
	if not _channels.has(channel):
		return 0
	return _channels[channel].presence.size()


func presence_meta(channel: String, key: String) -> Dictionary:
	if not _channels.has(channel):
		return {}
	var metas: Array = _channels[channel].presence.get(key, [])
	return _clean_meta(metas[0]) if not metas.is_empty() else {}


func close() -> void:
	## Leave everything and drop the socket.
	leave_all()
	_drop_socket()


func get_status_text() -> String:
	match _state:
		State.OPEN: return "online"
		State.RESOLVING, State.CONNECTING: return "connecting"
	return "offline" if enabled else "disabled"


# ─── Main loop ──────────────────────────────────────────────────────────

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			if enabled and not _channels.is_empty() and _now() >= _next_attempt_at:
				_begin_connect()
		State.RESOLVING:
			_poll_resolve()
		State.CONNECTING, State.OPEN:
			_poll_socket(delta)


func _begin_connect() -> void:
	_set_state(State.RESOLVING)
	if _host.is_empty():
		_fail("no host in realtime URL")
		return
	if _host.is_valid_ip_address() or _host == "localhost":
		_open_socket()
		return
	# Resolve ourselves first so DNS failures are silent (no engine error spam).
	_resolve_id = IP.resolve_hostname_queue_item(_host)
	if _resolve_id < 0:
		_fail("DNS queue full")


func _poll_resolve() -> void:
	var st := IP.get_resolve_item_status(_resolve_id)
	if st == IP.RESOLVER_STATUS_WAITING:
		if _now() - _state_since > CONNECT_TIMEOUT:
			IP.erase_resolve_item(_resolve_id)
			_resolve_id = -1
			_fail("DNS timeout for %s" % _host)
		return
	var ok := st == IP.RESOLVER_STATUS_DONE and not IP.get_resolve_item_addresses(_resolve_id).is_empty()
	IP.erase_resolve_item(_resolve_id)
	_resolve_id = -1
	if ok:
		_open_socket()
	else:
		_fail("cannot resolve %s" % _host)


func _open_socket() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 17
	_ws.heartbeat_interval = 0.0
	var err := _ws.connect_to_url(endpoint)
	if err != OK:
		_ws = null
		_fail("connect error %d" % err)
		return
	_set_state(State.CONNECTING)


func _poll_socket(_delta: float) -> void:
	if _ws == null:
		_set_state(State.IDLE)
		return
	_ws.poll()
	var rs := _ws.get_ready_state()
	if _state == State.CONNECTING:
		if rs == WebSocketPeer.STATE_OPEN:
			_on_open()
		elif rs == WebSocketPeer.STATE_CLOSED:
			_ws = null
			_fail("unreachable (%s)" % _host)
			return
		elif _now() - _state_since > CONNECT_TIMEOUT:
			_drop_socket()
			_fail("connect timeout (%s)" % _host)
			return
	if _state != State.OPEN:
		return
	if rs == WebSocketPeer.STATE_CLOSED:
		var code := _ws.get_close_code()
		_ws = null
		_on_closed("socket closed (code %d)" % code)
		return
	while _ws and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		_handle_text(pkt.get_string_from_utf8())
	if _state != State.OPEN:
		return
	# Heartbeat
	_hb_elapsed += _delta
	if _hb_elapsed >= HEARTBEAT_INTERVAL:
		_hb_elapsed = 0.0
		if not _hb_pending_ref.is_empty():
			_drop_socket()
			_on_closed("heartbeat timeout")
			return
		_hb_pending_ref = _push("phoenix", "heartbeat", {})
	# Join timeouts / scheduled rejoins
	var now := _now()
	for c in _channels:
		var ch: Dictionary = _channels[c]
		if ch.joined:
			continue
		if ch.join_sent_at >= 0.0 and now - ch.join_sent_at > JOIN_TIMEOUT:
			ch.join_sent_at = -1.0
			ch.rejoin_at = now + 5.0
		elif ch.join_sent_at < 0.0 and now >= ch.rejoin_at:
			_send_join(c)


func _on_open() -> void:
	_set_state(State.OPEN)
	_attempt = 0
	_hb_elapsed = 0.0
	_hb_pending_ref = ""
	if _failure_logged or verbose or not _was_open:
		print("[Realtime] Connected to %s" % _host)
	_failure_logged = false
	_was_open = true
	for c in _channels:
		_channels[c].joined = false
		_send_join(c)
	connection_changed.emit(true)


func _on_closed(reason: String) -> void:
	## Lost an established connection → mark channels unjoined, schedule reconnect.
	var had_open := _state == State.OPEN
	_set_state(State.IDLE)
	for c in _channels:
		var ch: Dictionary = _channels[c]
		if ch.joined:
			channel_left.emit(c)
		ch.joined = false
		ch.join_sent_at = -1.0
	_schedule_retry()
	if not _failure_logged:
		print("[Realtime] Disconnected: %s — retrying in background" % reason)
		_failure_logged = true
	if had_open:
		connection_changed.emit(false)


func _fail(reason: String) -> void:
	## A connect attempt failed (never opened). Log once, back off.
	_set_state(State.IDLE)
	_schedule_retry()
	if not _failure_logged:
		print("[Realtime] Offline: %s — multiplayer will retry quietly (backoff ≤ 60 s)" % reason)
		_failure_logged = true
	elif verbose:
		print("[Realtime] retry failed: %s (next in %.0fs)" % [reason, _next_attempt_at - _now()])


func _schedule_retry() -> void:
	var step: float = BACKOFF_STEPS[mini(_attempt, BACKOFF_STEPS.size() - 1)]
	_attempt += 1
	_next_attempt_at = _now() + step * randf_range(0.8, 1.2)


func get_retry_in() -> float:
	return maxf(0.0, _next_attempt_at - _now()) if _state == State.IDLE else 0.0


func get_attempts() -> int:
	return _attempt


func _drop_socket() -> void:
	if _ws:
		_ws.close()
		_ws = null
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1
	var was_open := _state == State.OPEN
	_set_state(State.IDLE)
	if was_open:
		for c in _channels:
			if _channels[c].joined:
				_channels[c].joined = false
				channel_left.emit(c)
			_channels[c].join_sent_at = -1.0
		connection_changed.emit(false)


func _set_state(s: int) -> void:
	_state = s
	_state_since = _now()


# ─── Protocol ───────────────────────────────────────────────────────────

func _topic(channel: String) -> String:
	return "realtime:" + channel


func _channel_of(topic: String) -> String:
	return topic.substr(9) if topic.begins_with("realtime:") else ""


func _push(topic: String, event: String, payload: Dictionary, join_ref: String = "") -> String:
	if _ws == null or _state != State.OPEN:
		return ""
	_ref += 1
	var ref := str(_ref)
	var msg := {"topic": topic, "event": event, "payload": payload, "ref": ref}
	if not join_ref.is_empty():
		msg["join_ref"] = join_ref
	_ws.send_text(JSON.stringify(msg))
	return ref


func _send_join(channel: String) -> void:
	var ch: Dictionary = _channels[channel]
	_ref += 1
	var ref := str(_ref)
	ch.join_ref = ref
	ch.join_sent_at = _now()
	var payload := {
		"config": {
			"broadcast": {"self": false, "ack": false},
			"presence": {"key": ch.key},
			"postgres_changes": [],
			"private": false,
		},
	}
	if not anon_key.is_empty():
		payload["access_token"] = anon_key
	if _ws:
		_ws.send_text(JSON.stringify({
			"topic": _topic(channel), "event": "phx_join",
			"payload": payload, "ref": ref, "join_ref": ref,
		}))


func _handle_text(text: String) -> void:
	var parsed = JSON.parse_string(text)
	var msg: Dictionary
	if parsed is Dictionary:
		msg = parsed
	elif parsed is Array and parsed.size() >= 5:
		# vsn 2.0.0 array form [join_ref, ref, topic, event, payload] — tolerate it
		msg = {"join_ref": parsed[0], "ref": parsed[1], "topic": parsed[2], "event": parsed[3], "payload": parsed[4]}
	else:
		return
	var topic: String = str(msg.get("topic", ""))
	var event: String = str(msg.get("event", ""))
	var payload = msg.get("payload", {})
	if not (payload is Dictionary):
		payload = {}
	var ref := "" if msg.get("ref") == null else str(msg.get("ref"))

	if topic == "phoenix":
		if event == "phx_reply" and ref == _hb_pending_ref:
			_hb_pending_ref = ""
		return

	var channel := _channel_of(topic)
	if not _channels.has(channel):
		return
	var ch: Dictionary = _channels[channel]
	var mjr = msg.get("join_ref")
	# Ignore stale messages for a previous join of this topic
	if mjr != null and str(mjr) != ch.join_ref and event != "broadcast":
		return

	match event:
		"phx_reply":
			if ref == ch.join_ref and not ch.joined:
				ch.join_sent_at = -1.0
				if str(payload.get("status", "")) == "ok":
					ch.joined = true
					if verbose:
						print("[Realtime] joined %s as %s" % [channel, ch.key])
					if not ch.track.is_empty():
						track(channel, ch.track)
					channel_joined.emit(channel)
				else:
					ch.rejoin_at = _now() + 10.0
					if not _failure_logged:
						print("[Realtime] Join refused for %s: %s" % [channel, JSON.stringify(payload.get("response", {})).left(160)])
						_failure_logged = true
		"presence_state":
			_apply_presence_state(channel, payload)
		"presence_diff":
			_apply_presence_diff(channel, payload)
		"broadcast":
			var ev: String = str(payload.get("event", ""))
			var inner = payload.get("payload", {})
			if inner is Dictionary and not ev.is_empty():
				broadcast_received.emit(channel, ev, inner)
		"phx_error", "phx_close":
			if ch.joined:
				ch.joined = false
				channel_left.emit(channel)
			ch.join_sent_at = -1.0
			ch.rejoin_at = _now() + 3.0
		_:
			pass  # "system", "presence" acks, postgres_changes…


func _apply_presence_state(channel: String, state: Dictionary) -> void:
	var ch: Dictionary = _channels[channel]
	var old: Dictionary = ch.presence
	var fresh: Dictionary = {}
	for k in state:
		var entry = state[k]
		if entry is Dictionary and entry.get("metas") is Array and not entry.metas.is_empty():
			fresh[str(k)] = entry.metas.duplicate()
	ch.presence = fresh
	for k in old:
		if not fresh.has(k):
			presence_left.emit(channel, k)
	for k in fresh:
		if not old.has(k):
			presence_joined.emit(channel, k, _clean_meta(fresh[k][0]))
		else:
			presence_updated.emit(channel, k, _clean_meta(fresh[k][0]))
	var flat := {}
	for k in fresh:
		flat[k] = _clean_meta(fresh[k][0])
	presence_synced.emit(channel, flat)


func _apply_presence_diff(channel: String, diff: Dictionary) -> void:
	# Same order as phoenix.js Presence.syncDiff: joins first, then leaves.
	var pres: Dictionary = _channels[channel].presence
	var joins = diff.get("joins", {})
	var leaves = diff.get("leaves", {})
	if joins is Dictionary:
		for k in joins:
			var metas = joins[k].get("metas", []) if joins[k] is Dictionary else []
			if not (metas is Array) or metas.is_empty():
				continue
			var key := str(k)
			var is_new := not pres.has(key)
			var cur: Array = pres.get(key, [])
			for m in metas:
				cur.append(m)
			pres[key] = cur
			if is_new:
				presence_joined.emit(channel, key, _clean_meta(metas[metas.size() - 1]))
			else:
				presence_updated.emit(channel, key, _clean_meta(metas[metas.size() - 1]))
	if leaves is Dictionary:
		for k in leaves:
			var key := str(k)
			if not pres.has(key):
				continue
			var metas = leaves[k].get("metas", []) if leaves[k] is Dictionary else []
			var gone := {}
			for m in metas:
				if m is Dictionary:
					gone[str(m.get("phx_ref", ""))] = true
			var remaining: Array = []
			for m in pres[key]:
				if not (m is Dictionary and gone.has(str(m.get("phx_ref", "")))):
					remaining.append(m)
			if remaining.is_empty():
				pres.erase(key)
				presence_left.emit(channel, key)
			else:
				pres[key] = remaining


static func _clean_meta(m) -> Dictionary:
	if not (m is Dictionary):
		return {}
	var d: Dictionary = m.duplicate()
	d.erase("phx_ref")
	d.erase("phx_ref_prev")
	return d


func _exit_tree() -> void:
	if _ws:
		_ws.close()
		_ws = null
	if _resolve_id >= 0:
		IP.erase_resolve_item(_resolve_id)
		_resolve_id = -1
