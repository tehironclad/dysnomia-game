extends Node
## Autoload "Net": free online play through the owner's game server
## (docs/SERVER.md). Optional: with no server reachable the game is
## single-player as before, quietly (one log line, retries with back-off).
##
## Public API (other features call these; keep them stable):
##   signal chat_received(wallet, name, text, world_pos)  — free chat, not on chain
##   send_chat(text) -> bool
##   top(board, n) -> {ok, rows} | {ok: false, error: "—"}
##   submit(board, entry) -> {ok, rank, row} | {ok: false, error}
##   is_online(), can_talk(), mute(wallet), unmute(wallet), is_muted(wallet)
##
## The server URL comes from Settings (F2 · Online) or, if blank, from the
## site: GET <site>/api/game-server → {"url": "wss://…"}. Autoloads do no
## network on their own: a territory calls start() when the player arrives.

signal chat_received(wallet: String, name: String, text: String, world_pos: Vector3)
signal status_changed(status: String)
signal notice(text: String)
signal voice_pcm(id: int, pcm: PackedFloat32Array, level: float)
signal speaking_changed(on: bool)

const SETTINGS_PATH := "user://net.cfg"
const DISCOVERY_PATH := "/api/game-server"
const SERVER_SCENE := "res://scenes/net/game_server.tscn"
const RETRY_MIN_S := 20.0
const RETRY_MAX_S := 300.0

# settings (user://net.cfg)
var online_enabled := true
var server_url := ""          # "" = ask the site
var mic_enabled := false      # opt-in
var mic_device := "Default"
var voice_volume := 0.8
var mute_others := false
var muted := {}               # wallet → true (local only)

var client: NetClient
var mic: Node
var resolved_url := ""
var last_error := ""
var heard := {}               # wallet → name: who spoke or wrote here (for the mute list)
var _started := false
var _connecting := false
var _retry_s := RETRY_MIN_S
var _retry_timer: Timer
var _room := ""
var _pending_chat: Array = []
var _signing := false
var _logged_offline := false
var _url_override := ""


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--server"):
		(func() -> void: get_tree().change_scene_to_file(SERVER_SCENE)).call_deferred()
		return
	_load_settings()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-url="):  # this session only (tests, screenshots)
			_url_override = a.substr(10)
	client = NetClient.new()
	client.name = "Client"
	add_child(client)
	client.status_changed.connect(_on_status)
	client.chat.connect(_on_chat)
	client.voice.connect(_on_voice)
	client.notice.connect(func(code, text):
		if code == "guest" and Wallet.address != "" and not _signing:
			return  # a sign-in is offered instead (send_chat)
		notice.emit(text))
	client.auth_changed.connect(_on_auth)
	client.auth_failed.connect(func(reason):
		_signing = false
		_pending_chat.clear()
		notice.emit("Sign-in failed: %s. You can still see everyone." % reason))
	client.signer = _wallet_signer
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_connect)
	add_child(_retry_timer)
	mic = load("res://scripts/net/net_mic.gd").new()
	mic.name = "Mic"
	add_child(mic)
	Wallet.connected.connect(func(_a): client.signer_wallet = Wallet.address)
	Wallet.disconnected.connect(func(): client.signer_wallet = "")


# ── connection ─────────────────────────────────────────────────────────────

## Starts online play (idempotent). Called by the territory when the player arrives.
func start() -> void:
	if client == null or not online_enabled:
		return
	_started = true
	if client.status == "offline" and not _connecting and _retry_timer.is_stopped():
		_connect()


func stop() -> void:
	_started = false
	if _retry_timer:
		_retry_timer.stop()
	if client:
		client.close()


func restart() -> void:
	stop()
	resolved_url = ""
	_retry_s = RETRY_MIN_S
	start()


func is_online() -> bool:
	return client != null and client.is_online()


## Signed in (a guest can see everyone but can't talk).
func can_talk() -> bool:
	return is_online() and client.wallet != ""


func status_text() -> String:
	if client == null:
		return "—"
	if not online_enabled:
		return "Online play is off"
	match client.status:
		"online":
			var who := ("signed in as " + NetProto.short_wallet(client.wallet)) if client.wallet != "" else "guest (sign in to talk)"
			return "Online · %s · %d here · %s%s" % [client.server_name, client.peers.size() + 1, who,
				(" · %d ms" % client.rtt_ms) if client.rtt_ms >= 0 else ""]
		"connecting":
			return "Connecting to %s…" % resolved_url
	return "Offline (single-player)%s" % ((" · " + last_error) if last_error != "" else "")


func _connect() -> void:
	if not _started or _connecting or client.status != "offline":
		return
	_connecting = true
	var url := await _discover()
	_connecting = false
	if not _started:
		return
	if url == "":
		_offline("no game server")
		return
	resolved_url = url
	client.signer_wallet = Wallet.address
	client.connect_to(url)


func _discover() -> String:
	if _url_override != "":
		return normalize_url(_url_override)
	if server_url.strip_edges() != "":
		return normalize_url(server_url)
	var r: Dictionary = await Chain.site.get_json(DISCOVERY_PATH)
	if r.get("ok", false) and r["data"] is Dictionary:
		return normalize_url(String(r["data"].get("url", "")))
	return ""


## https://x → wss://x; ws(s):// kept; anything else → "".
static func normalize_url(u: String) -> String:
	u = u.strip_edges()
	if u.begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.begins_with("http://"):
		u = "ws://" + u.substr(7)
	if not (u.begins_with("wss://") or u.begins_with("ws://")) or u.length() > 300 or u.contains(" "):
		return ""
	return u


func _offline(why: String) -> void:
	last_error = why
	if not _logged_offline:
		_logged_offline = true
		print("[Net] single-player: %s (retrying quietly)" % why)
	_retry_timer.start(_retry_s)
	_retry_s = minf(_retry_s * 2.0, RETRY_MAX_S)


func _on_status(s: String) -> void:
	if s == "online":
		_retry_s = RETRY_MIN_S
		last_error = ""
		_logged_offline = false
		print("[Net] online: %s" % resolved_url)
		if _room != "":
			client.join(_room, profile())
	elif s == "offline":
		_signing = false
		if _started and _retry_timer.is_stopped() and not _connecting:
			_offline("no answer from " + resolved_url if resolved_url != "" else "offline")
	status_changed.emit(s)


# ── rooms and presence ─────────────────────────────────────────────────────

func enter_room(qing: String) -> void:
	_room = NetProto.clean_room(qing)
	if client and client.is_online() and _room != "":
		client.join(_room, profile())


func leave_room() -> void:
	_room = ""
	if client and client.is_online():
		client.leave()


## Name, head and body sent to others (from this wallet's LAU, like the local avatar).
func profile() -> Dictionary:
	var p := {"name": "", "head": "bear", "acc": [], "body": "male"}
	var w := Session.wallet
	if w != "":
		p["body"] = AvatarHeads.local_body(w)
		var ps: PlayerState = Session.player
		if ps != null:
			p["name"] = ps.username
			var pick := AvatarHeads.local_choice(w)
			p["head"] = pick if pick != "" else ps.head_kind()
			p["acc"] = AvatarHeads.accessories_for(ps.username, ps.lau_name, ps.lau_symbol)
	return p


func refresh_profile() -> void:
	if is_online():
		client.set_profile(profile())


func send_state(pos: Vector3, yaw: float, flags: int, anim: int = 0) -> void:
	if client:
		if mic and mic.talking:
			flags |= NetProto.F_SPEAKING
		client.send_state(pos, yaw, flags, anim)


# ── chat ───────────────────────────────────────────────────────────────────

## Free chat to everyone in this territory (not on chain). True if it was sent,
## or queued behind a wallet sign-in (a guest with a wallet is asked to sign once).
func send_chat(text: String) -> bool:
	text = NetProto.clean_text(text, NetProto.CHAT_MAX_CHARS)
	if text == "" or not is_online():
		return false
	if client.wallet == "":
		if Wallet.address == "":
			notice.emit("Guests can see everyone but can't talk: connect your wallet, then sign in (a free signature).")
			return false
		_pending_chat.append(text)
		sign_in()
		return true
	return client.send_chat(text)


## One free personal_sign in the browser wallet (then a session token: no more prompts).
func sign_in() -> void:
	if not is_online() or client.wallet != "" or _signing:
		return
	if Wallet.address == "":
		notice.emit("Connect your wallet first (the wallet button on the front door).")
		return
	_signing = true
	client.signer_wallet = Wallet.address
	notice.emit("Sign-in: approve the free signature in your wallet window (not a transaction).")
	client.sign_in()


func _wallet_signer(message: String) -> String:
	var r: Dictionary = await Wallet.sign_message(message)
	return String(r.get("signature", "")) if r.get("ok", false) else ""


func _on_auth(w: String) -> void:
	_signing = false
	if w != "":
		notice.emit("Signed in as %s · you can talk now" % NetProto.short_wallet(w))
		for t in _pending_chat:
			client.send_chat(t)
	_pending_chat.clear()


func _on_chat(_id: int, w: String, nm: String, text: String, pos: Vector3) -> void:
	if w != "" and w != client.wallet:
		heard[w] = nm
	if is_muted(w):
		return
	chat_received.emit(w, nm, text, pos)


# ── voice ──────────────────────────────────────────────────────────────────

func _on_voice(id: int, codec: int, data: PackedByteArray) -> void:
	if mute_others:
		return
	var p: Dictionary = client.peers.get(id, {})
	var w := String(p.get("wallet", ""))
	if w != "":
		heard[w] = String(p.get("name", ""))
	if is_muted(w):
		return
	var pcm := VoiceCodec.decode(codec, data)
	if not pcm.is_empty():
		voice_pcm.emit(id, pcm, VoiceCodec.level(pcm))


# ── mute list (this computer only) ─────────────────────────────────────────

func mute(w: String) -> void:
	w = NetProto.clean_wallet(w)
	if w != "":
		muted[w] = true
		save_settings()


func unmute(w: String) -> void:
	muted.erase(w.to_lower())
	save_settings()


func is_muted(w: String) -> bool:
	return muted.has(w.to_lower())


# ── leaderboards ───────────────────────────────────────────────────────────

## The best `n` rows of a board, from the server; {ok: false, error: "—"} offline.
func top(board: String, n: int = 10) -> Dictionary:
	if not is_online():
		return {"ok": false, "error": "—"}
	return await client.lb_top(board, n)


## Submits {score, …}; needs a signed-in wallet. {ok: false, error} otherwise.
func submit(board: String, entry: Dictionary) -> Dictionary:
	if not is_online():
		return {"ok": false, "error": "—"}
	if client.wallet == "":
		return {"ok": false, "error": "sign in to submit a score"}
	return await client.lb_submit(board, entry)


# ── settings ───────────────────────────────────────────────────────────────

func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return
	online_enabled = bool(c.get_value("net", "online", online_enabled))
	server_url = String(c.get_value("net", "server_url", server_url))
	mic_enabled = bool(c.get_value("voice", "mic", mic_enabled))
	mic_device = String(c.get_value("voice", "device", mic_device))
	voice_volume = float(c.get_value("voice", "volume", voice_volume))
	mute_others = bool(c.get_value("voice", "mute_others", mute_others))
	for w in c.get_value("net", "muted", []):
		muted[String(w)] = true


func save_settings() -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_PATH)
	c.set_value("net", "online", online_enabled)
	c.set_value("net", "server_url", server_url)
	c.set_value("net", "muted", muted.keys())
	c.set_value("voice", "mic", mic_enabled)
	c.set_value("voice", "device", mic_device)
	c.set_value("voice", "volume", voice_volume)
	c.set_value("voice", "mute_others", mute_others)
	c.save(SETTINGS_PATH)
