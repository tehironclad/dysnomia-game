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
##   sign_in(), sign_in_state(), can_sign_in(), announce_place(place, qing), claim(kind, qing)
##   names: LauNames (the chain's names for wallets), activity: NetActivity (the feed)
##
## Sign-in: once a wallet is connected and the server answers, the game signs in
## by itself: a saved session token for that server and wallet if there is one
## (no signature), else one line first (AUTO_PROMPT) and then the free personal_sign
## of the text the client builds (NetProto.login_message). Declined: stays a guest,
## never asked again for that wallet until the player clicks Sign in (F2 · Online,
## or the notification panel). A new wallet signs in again (a new connection).
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
const RETRY_FIRST_S := 5.0
const RETRY_MIN_S := 20.0
const RETRY_MAX_S := 300.0
const AUTO_PROMPT := "Sign in to the game server so others see your name: one free signature, not a transaction."
const AUTO_DELAY_S := 2.5        ## the prompt shows this long before the wallet asks
const TOKEN_MARGIN_S := 600      ## a saved token is not used in its last 10 minutes

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
var _retry_s := RETRY_FIRST_S
var _retry_timer: Timer
var _room := ""
var _pending_chat: Array = []
var _signing := false
var _logged_offline := false
var _url_override := ""
var names: LauNames
var activity: NetActivity
var declined := {}            # wallet → true: said no to the sign-in (asked again only by a click)
var _auto_key := ""           # the url|wallet|connection the automatic sign-in already ran for
var _auto_waiting := false    # the prompt is showing; the wallet asks next
var _last_sign_stage := ""    # the last Wallet.sign_message failure stage ("sign" = refused in the wallet)


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
	client.auth_failed.connect(_on_auth_failed)
	client.signer = _wallet_signer
	names = LauNames.new()
	names.name = "Names"
	add_child(names)
	activity = NetActivity.new()
	activity.name = "Activity"
	add_child(activity)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_connect)
	add_child(_retry_timer)
	mic = load("res://scripts/net/net_mic.gd").new()
	mic.name = "Mic"
	add_child(mic)
	Wallet.connected.connect(_on_wallet_connected)
	Wallet.disconnected.connect(func(): client.signer_wallet = "")
	Session.changed.connect(refresh_profile)  # a LAU switch or a fresh read: others see the new name and head


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
	_retry_s = RETRY_FIRST_S
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
			var who := ("signed in as " + NetNames.tag(client.wallet, false, names.record(client.wallet))) if client.wallet != "" else "guest (sign in so others see your name)"
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
	var saved := saved_token(url, Wallet.address)
	if saved != "":
		client.use_token(url, saved)  # sent with the welcome: no signature on this launch
	client.connect_to(url)


func _discover() -> String:
	if _url_override != "":
		return normalize_url(_url_override)
	if server_url.strip_edges() != "":
		return normalize_url(server_url)
	var r: Dictionary = await Chain.site.get_json(DISCOVERY_PATH)
	if r.get("ok", false) and r["data"] is Dictionary:
		return discovered_url(String(r["data"].get("url", "")))
	return ""


## Pure: a server address the SITE suggests must be wss:// (TLS), or ws:// to this
## computer; "" otherwise. (An address typed in Settings is the player's own choice.)
static func discovered_url(u: String) -> String:
	var n := normalize_url(u)
	if n.begins_with("wss://"):
		return n
	var host := NetProto.login_host(n)
	return n if n != "" and (host == "localhost" or host == "127.0.0.1") else ""


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
	_retry_s = clampf(_retry_s * 2.0, RETRY_MIN_S, RETRY_MAX_S)


func _on_status(s: String) -> void:
	if s == "online":
		_retry_s = RETRY_FIRST_S
		last_error = ""
		_logged_offline = false
		print("[Net] online: %s" % resolved_url)
		if _room != "":
			client.join(_room, profile())
		_auto_key = ""
		_auto_check_soon()
	elif s == "offline":
		_signing = false
		_auto_waiting = false
		if _started and _retry_timer.is_stopped() and not _connecting:
			_offline("no answer from " + resolved_url if resolved_url != "" else "offline")
	status_changed.emit(s)


# ── rooms and presence ─────────────────────────────────────────────────────

func enter_room(qing: String) -> void:
	_room = NetProto.clean_room(qing)
	if activity and _room != "":
		activity.here = _room.get_slice("/", 0)
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
## `auto`: the automatic sign-in (a click clears a decline and asks again).
func sign_in(auto: bool = false) -> void:
	if not auto and declined.has(Wallet.address):
		declined.erase(Wallet.address)
		save_settings()
	if not is_online() or client.wallet != "" or _signing:
		return
	if Wallet.address == "":
		notice.emit("Connect your wallet first (the wallet button on the front door).")
		return
	_signing = true
	_auto_waiting = false
	client.signer_wallet = Wallet.address
	notice.emit("Sign-in: approve the free signature in your wallet window (not a transaction).")
	client.sign_in()


func _wallet_signer(message: String) -> String:
	var r: Dictionary = await Wallet.sign_message(message)
	_last_sign_stage = "" if r.get("ok", false) else String(r.get("stage", ""))
	return String(r.get("signature", "")) if r.get("ok", false) else ""


func _on_auth(w: String) -> void:
	_signing = false
	_auto_waiting = false
	if w != "":
		notice.emit("Signed in as %s · others see your name; you can talk now" % NetProto.short_wallet(w))
		for t in _pending_chat:
			client.send_chat(t)
		if client.token != "":
			save_token(client.url, w, client.token)
		refresh_profile()  # the name and head again, now as a signed-in player
	_pending_chat.clear()


func _on_auth_failed(reason: String) -> void:
	var was_signing := _signing
	_signing = false
	_auto_waiting = false
	_pending_chat.clear()
	if reason == "token expired":
		forget_token(client.url, Wallet.address)
		_auto_key = ""
		_auto_check_soon()  # sign the new text instead (the prompt first)
		return
	if was_signing and reason == "the signature was refused" and _last_sign_stage == "sign" and Wallet.address != "":
		declined[Wallet.address] = true
		save_settings()
		notice.emit("Staying a guest: others see you as 'guest'. Sign in any time: F2 · Online, or the bell (%s)." % ControlsHelp.key_of("notifications"))
		return
	notice.emit("Sign-in failed: %s. You can still see everyone." % reason)


## "" | "prompt" (the line is showing; the wallet asks next) | "signing" | "declined" | "signed"
func sign_in_state() -> String:
	if client == null:
		return ""
	if client.wallet != "":
		return "signed"
	if _signing or client.is_signing() or client.token_pending:
		return "signing"
	if _auto_waiting:
		return "prompt"
	if declined.has(Wallet.address):
		return "declined"
	return ""


## Can the player sign in now (online, a wallet, not signed in)? For the Sign in buttons.
func can_sign_in() -> bool:
	return is_online() and client.wallet == "" and Wallet.address != "" and sign_in_state() in ["", "declined"]


func _auto_check_soon() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.8).timeout
	_auto_check()


## The automatic sign-in (see the top): once per connection and wallet.
func _auto_check() -> void:
	if client == null or not is_online() or client.wallet != "" or _signing or client.is_signing() or client.token_pending or _auto_waiting:
		return
	var w := Wallet.address
	if w == "" or declined.has(w) or (not client.features.has("invites") and not client.features.has("events")):
		return  # no wallet, said no, or a server too old to say who anyone is
	var key := "%s|%s|%d" % [client.url, w, client.my_id]
	if _auto_key == key:
		return
	_auto_key = key
	var saved := saved_token(client.url, w)
	if saved != "" and saved != client.token:
		client.use_token(client.url, saved)
		return
	if not Wallet.is_linked():
		return
	_auto_waiting = true
	notice.emit(AUTO_PROMPT)
	await get_tree().create_timer(AUTO_DELAY_S).timeout
	if not _auto_waiting or not is_online() or client.wallet != "" or Wallet.address != w:
		_auto_waiting = false
		return
	client.signer_wallet = w
	sign_in(true)


## A wallet was connected (or another one): sign in as it.
func _on_wallet_connected(_a: String) -> void:
	client.signer_wallet = Wallet.address
	if client.wallet != "" and client.wallet != Wallet.address:
		notice.emit("Another wallet: signing in to the game server again as %s." % NetProto.short_wallet(Wallet.address))
		client.token = ""
		restart()
		return
	_auto_key = ""
	_auto_check_soon()


# ── session tokens (24 h, per server URL and wallet; only ever sent to that URL) ──

func saved_token(url: String, w: String) -> String:
	if url == "" or w == "":
		return ""
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return ""
	var v = c.get_value("sessions", "%s|%s" % [url, w.to_lower()], {})
	if not (v is Dictionary) or int(v.get("exp", 0)) < int(Time.get_unix_time_from_system()) + TOKEN_MARGIN_S:
		return ""
	return String(v.get("token", ""))


func save_token(url: String, w: String, tok: String) -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_PATH)
	var k := "%s|%s" % [url, w.to_lower()]
	var old = c.get_value("sessions", k, {})
	if old is Dictionary and String(old.get("token", "")) == tok:
		return  # the same session (a token sign-in): its expiry stays
	c.set_value("sessions", k, {"token": tok, "exp": int(Time.get_unix_time_from_system()) + GameServer.TOKEN_TTL_S})
	c.save(SETTINGS_PATH)


func forget_token(url: String, w: String) -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return
	var k := "%s|%s" % [url, w.to_lower()]
	if c.has_section_key("sessions", k):
		c.erase_section_key("sessions", k)
		c.save(SETTINGS_PATH)


# ── the activity feed ───────────────────────────────────────────────────────

## This player walked into a place (NetEvents.PLACES) of QING `qing`: players there see it.
func announce_place(place: String, qing: String) -> void:
	if client and is_online():
		client.send_place(place, qing)


## A claim others check on the chain before they show it (NetEvents.CLAIMS).
func claim(kind: String, qing: String) -> void:
	if client and is_online():
		client.send_claim(kind, qing)


func _on_chat(_id: int, w: String, nm: String, text: String, pos: Vector3) -> void:
	if w != "":
		nm = names.display(w)  # the chain's name for the verified wallet, never the claimed one
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
		heard[w] = names.display(w)  # the chain's name (the mute list), never the claimed one
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
	for w in c.get_value("net", "signin_declined", []):
		declined[String(w)] = true


func save_settings() -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_PATH)
	c.set_value("net", "online", online_enabled)
	c.set_value("net", "server_url", server_url)
	c.set_value("net", "muted", muted.keys())
	c.set_value("net", "signin_declined", declined.keys())
	c.set_value("voice", "mic", mic_enabled)
	c.set_value("voice", "device", mic_device)
	c.set_value("voice", "volume", voice_volume)
	c.set_value("voice", "mute_others", mute_others)
	c.save(SETTINGS_PATH)
