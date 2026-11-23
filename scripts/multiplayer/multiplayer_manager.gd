extends Node
## Manages remote player instances for multiplayer presence.
##
## Transport (default → fallback):
##   1. NATIVE — realtime_client.gd talks to Supabase Realtime directly over WebSocketPeer.
##      Works for everyone, including Telegram newcomers with no wallet (guest id).
##   2. BRIDGE — the original path: wallet_bridge WS → assets/web/wallet.html → supabase-js.
##      Used only for wallet players when the native socket can't join within FALLBACK_AFTER.
## Both use the same channel ('qing:' + qing.to_lower().left(12)), presence key (wallet or
## guest id), presence payload {wallet, username, tier, x, y, z, yaw, vx, vz, ts} and `pos`
## broadcast {w, x, y, z, r, vx, vz}, so browser-bridge and native players see each other.
##
## Extra broadcast events on the QING channel (native only):
##   say   {w, n, t}  — chat bubble above the sender's head
##   emote {w, e}     — emote icon + pose on the sender's avatar
##   moment           — see community_hub.gd
##
## Position: ≤ 10 Hz, only when moved (plus a 5 s keepalive so idle players don't go stale).
##
## The public API and signals below are unchanged from the bridge-only version; main.gd's
## existing wiring (ChainManager.mp_* → on_*) keeps working and is ignored while native is live.
## Guests: if set_local_player() is never called with a wallet, the manager finds the local
## player (group "player") on its own and joins as a guest.

signal player_count_changed(count: int)
signal player_joined(wallet: String, username: String)
signal player_left(wallet: String, username: String)
# ── Additive signals ──
signal chat_received(key: String, username: String, text: String)
signal emote_received(key: String, emote_id: int)
signal identity_changed(key: String, username: String, tier: int)
signal transport_changed(mode: String)  # "native" | "bridge" | "offline"

const RemotePlayerScript = preload("res://scripts/multiplayer/remote_player.gd")
const RealtimeClientScript = preload("res://scripts/multiplayer/realtime_client.gd")
const CommunityIdentityScript = preload("res://scripts/multiplayer/community_identity.gd")
const CommunityHubScript = preload("res://scripts/multiplayer/community_hub.gd")
const WalletBridgeScript = preload("res://scripts/chain/wallet_bridge.gd")

const GLOBAL_CHANNEL: String = "dysnomia:global"
const MAX_REMOTE_PLAYERS: int = 40
const BROADCAST_INTERVAL: float = 0.1   # ≤ 10 Hz
const KEEPALIVE_INTERVAL: float = 5.0   # idle players still ping (remote stale timeout is 30 s)
const RETRACK_INTERVAL: float = 20.0    # refresh presence position so late joiners place us right
const FALLBACK_AFTER: float = 8.0       # native not joined after this → use the wallet bridge
const STATE_POLL: float = 0.5
const SAY_COOLDOWN: float = 1.0
const EMOTE_COOLDOWN: float = 0.8

## Set false before add_child to keep the old bridge-only behaviour.
var use_native: bool = true
## Create the CommunityHub (as a sibling named "CommunityHub") if none exists.
var auto_create_hub: bool = true
## Announce an "arrival" moment the first time we join a QING channel.
var auto_announce_arrival: bool = true

# ── State ──
var _remote_players: Dictionary = {}  # key (lowercase wallet / guest id) → RemotePlayer node
var _broadcast_timer: float = 0.0
var _local_player: CharacterBody3D = null
var _local_wallet: String = ""
var _local_username: String = ""
var _local_tier: int = 0
var _parent_3d: Node3D = null  # Where to spawn remote player nodes
var _active: bool = false
var _deactivated: bool = false

var _rt: Node = null              # RealtimeClient
var _hub: Node = null
var _local_key: String = ""       # presence key (wallet or guest id)
var _local_name: String = ""
var _eff_tier: int = 0
var _is_guest: bool = true
var _qing_address: String = ""
var _qing_channel: String = ""
var _native_joined: bool = false
var _native_wait: float = 0.0
var _bridge_engaged: bool = false
var _mode: String = ""
var _poll_t: float = 0.0
var _since_send: float = 999.0
var _since_track: float = 0.0
var _force_send: bool = false
var _last_sent_pos: Vector3 = Vector3(INF, INF, INF)
var _last_sent_yaw: float = 0.0
var _last_sent_moving: bool = false
var _last_track_pos: Vector3 = Vector3.ZERO
var _last_say_ms: int = -100000
var _last_emote_ms: int = -100000
var _local_bubble: Label3D = null
var _local_bubble_t: float = 0.0
var _arrived_in: Dictionary = {}  # qing channel → true
## Diagnostics: number of position broadcasts sent (tests check the rate limit).
var pos_broadcasts_sent: int = 0


func _ready() -> void:
	_rt = RealtimeClientScript.new()
	_rt.name = "RealtimeClient"
	add_child(_rt)
	_rt.presence_joined.connect(_on_rt_presence_joined)
	_rt.presence_updated.connect(_on_rt_presence_updated)
	_rt.presence_left.connect(_on_rt_presence_left)
	_rt.presence_synced.connect(_on_rt_presence_synced)
	_rt.broadcast_received.connect(_on_rt_broadcast)
	_rt.channel_joined.connect(_on_rt_channel_joined)
	if auto_create_hub:
		_ensure_hub.call_deferred()
	_auto_start.call_deferred()


func _ensure_hub() -> void:
	var existing := get_tree().get_first_node_in_group("community_hub")
	if existing:
		_hub = existing
		if _hub.has_method("bind") and _hub.get("_mm") == null:
			_hub.bind(self)
		return
	_hub = CommunityHubScript.new()
	_hub.name = "CommunityHub"
	# main.gd looks for Main/CommunityHub → make it a sibling when we have a parent.
	var host := get_parent() if get_parent() else self
	host.add_child(_hub)
	_hub.bind(self)


func _auto_start() -> void:
	## Guests: main.gd only activates us for wallet players, so self-activate.
	if _deactivated or not is_inside_tree():
		return
	if _local_player == null:
		var p := get_tree().get_first_node_in_group("player")
		if p is CharacterBody3D:
			_local_player = p
		elif get_parent() and get_parent().get("player") is CharacterBody3D:
			_local_player = get_parent().get("player")
	if _parent_3d == null and get_parent() is Node3D:
		_parent_3d = get_parent()
	if _local_player:
		_active = true
		_refresh_state()


func set_local_player(player: CharacterBody3D, wallet: String, username: String, tier: int) -> void:
	_local_player = player
	_local_wallet = wallet.to_lower()
	_local_username = username
	_local_tier = tier
	if _active:
		_refresh_state()


func set_spawn_parent(parent: Node3D) -> void:
	_parent_3d = parent


func activate() -> void:
	_active = true
	_deactivated = false
	_broadcast_timer = 0.0
	_refresh_state()


func deactivate() -> void:
	_active = false
	_deactivated = true
	if _rt:
		_rt.leave_all()
	_qing_channel = ""
	_qing_address = ""
	_set_native_joined(false)
	remove_all_players()


func _process(delta: float) -> void:
	if not _active:
		return
	_poll_t += delta
	if _poll_t >= STATE_POLL:
		_poll_t = 0.0
		_refresh_state()
	_update_transport(delta)
	_tick_broadcast(delta)
	if _local_bubble_t > 0.0:
		_local_bubble_t -= delta
		if _local_bubble_t <= 0.0 and _local_bubble and is_instance_valid(_local_bubble):
			_local_bubble.queue_free()
			_local_bubble = null


# ── Identity / channel bookkeeping ──────────────────────────────────────

func _refresh_state() -> void:
	if not _active or _rt == null:
		return
	var wallet := _local_wallet
	var cm := _chain_manager()
	if wallet.is_empty() and cm:
		wallet = str(cm.get("connected_wallet")).to_lower()
	var uname := _local_username
	var gm := _game_manager()
	if (uname.is_empty() or uname == "Anonymous") and gm:
		uname = str(gm.get("player_identity"))
	var id: Dictionary = CommunityIdentityScript.resolve(wallet, uname)
	var tier := _local_tier
	if cm and cm.has_method("get_cached_progression"):
		tier = maxi(tier, int(cm.get_cached_progression().get("evolutionTier", 0)))

	var key_changed: bool = id.key != _local_key
	var ident_changed: bool = key_changed or id.name != _local_name or tier != _eff_tier
	_local_key = id.key
	_local_name = id.name
	_is_guest = id.guest
	_eff_tier = tier

	var qing := ""
	if gm:
		qing = str(gm.get("territory_address")).to_lower()
	var channel := qing_channel_for(qing)

	if channel != _qing_channel or key_changed:
		if not _qing_channel.is_empty():
			_rt.leave(_qing_channel)
			remove_all_players()
			if _bridge_engaged and cm:
				cm.leave_multiplayer_channel()
				_bridge_engaged = false
		_qing_channel = channel
		_qing_address = qing
		_native_wait = 0.0
		if use_native and not channel.is_empty():
			_rt.join(channel, _local_key, _qing_presence_payload())
			_since_track = 0.0
	elif ident_changed and not _qing_channel.is_empty():
		_rt.track(_qing_channel, _qing_presence_payload())
		_since_track = 0.0

	if use_native and (key_changed or ident_changed or not _rt.has_channel(GLOBAL_CHANNEL)):
		_rt.join(GLOBAL_CHANNEL, _local_key, _global_presence_payload())
	if ident_changed:
		identity_changed.emit(_local_key, _local_name, _eff_tier)


static func qing_channel_for(qing_address: String) -> String:
	## Same as wallet.html: 'qing:' + qingAddress.toLowerCase().slice(0, 12)
	var q := qing_address.strip_edges().to_lower()
	if not q.begins_with("0x") or q.length() < 6 or q == "0x0":
		return ""
	return "qing:" + q.left(12)


func _qing_presence_payload() -> Dictionary:
	var pos := Vector3(0, 1.3, 0)
	var yaw := 0.0
	if _local_player and is_instance_valid(_local_player) and _local_player.is_inside_tree():
		pos = _local_player.global_position
		yaw = _local_player.rotation.y
	_last_track_pos = pos
	return {
		"wallet": _local_key, "username": _local_name, "tier": _eff_tier,
		"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "z": snappedf(pos.z, 0.01),
		"yaw": snappedf(yaw, 0.01), "vx": 0, "vz": 0,
		"ts": int(Time.get_unix_time_from_system() * 1000.0),
	}


func _global_presence_payload() -> Dictionary:
	return {"wallet": _local_key, "username": _local_name, "tier": _eff_tier}


func _update_transport(delta: float) -> void:
	var joined: bool = use_native and not _qing_channel.is_empty() and _rt.is_joined(_qing_channel)
	if joined != _native_joined:
		_set_native_joined(joined)
	if joined or _qing_channel.is_empty():
		return
	_native_wait += delta
	if _native_wait >= FALLBACK_AFTER and not _bridge_engaged and not _is_guest:
		var cm := _chain_manager()
		if cm and cm.has_method("join_multiplayer_channel"):
			_bridge_engaged = true
			cm.join_multiplayer_channel(_qing_address)
			_set_mode("bridge")
	elif _native_wait >= FALLBACK_AFTER and _mode != "bridge":
		_set_mode("offline")


func _set_native_joined(joined: bool) -> void:
	_native_joined = joined
	WalletBridgeScript.native_mp_active = joined
	if joined:
		# Make sure the browser page isn't also in the channel under the same wallet.
		var cm := _chain_manager()
		if cm and not _is_guest and cm.has_method("leave_multiplayer_channel"):
			cm.leave_multiplayer_channel()
		_bridge_engaged = false
		_force_send = true
		_set_mode("native")
	else:
		_native_wait = 0.0


func _set_mode(m: String) -> void:
	if m == _mode:
		return
	_mode = m
	transport_changed.emit(m)


func _native_live() -> bool:
	## Joined right now (doesn't wait for the next _process to flip _native_joined).
	return use_native and _rt != null and not _qing_channel.is_empty() and _rt.is_joined(_qing_channel)


func _on_rt_channel_joined(channel: String) -> void:
	if channel != _qing_channel:
		return
	_update_transport(0.0)
	_force_send = true
	if auto_announce_arrival and not _arrived_in.has(channel):
		_arrived_in[channel] = true
		if _hub and is_instance_valid(_hub) and _hub.has_method("announce"):
			_hub.announce("arrival", {})


# ── Position broadcast ──────────────────────────────────────────────────

func _tick_broadcast(delta: float) -> void:
	_since_send += delta
	_since_track += delta
	_broadcast_timer += delta
	if _broadcast_timer < BROADCAST_INTERVAL:
		return
	_broadcast_timer = 0.0
	if not _local_player or not is_instance_valid(_local_player) or not _local_player.is_inside_tree():
		return
	if not _native_joined and (_is_guest or (_local_wallet.is_empty() and not _bridge_engaged)):
		return
	var pos := _local_player.global_position
	var yaw := _local_player.rotation.y
	var vel := _local_player.velocity
	var moving := Vector2(vel.x, vel.z).length() > 0.05
	var moved := pos.distance_to(_last_sent_pos) > 0.03 or absf(angle_difference(yaw, _last_sent_yaw)) > 0.02
	var stopped := _last_sent_moving and not moving
	if not (moved or stopped or _force_send or _since_send >= KEEPALIVE_INTERVAL):
		return
	_force_send = false
	_since_send = 0.0
	_last_sent_pos = pos
	_last_sent_yaw = yaw
	_last_sent_moving = moving
	_broadcast_position()
	if _native_joined and _since_track >= RETRACK_INTERVAL and pos.distance_to(_last_track_pos) > 2.0:
		_since_track = 0.0
		_rt.track(_qing_channel, _qing_presence_payload())


func _broadcast_position() -> void:
	if not _local_player:
		return
	var pos := _local_player.global_position
	var vel := _local_player.velocity
	var yaw := _local_player.rotation.y
	pos_broadcasts_sent += 1
	if _native_live():
		_rt.send_broadcast(_qing_channel, "pos", {
			"w": _local_key,
			"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "z": snappedf(pos.z, 0.01),
			"r": snappedf(yaw, 0.01),
			"vx": snappedf(vel.x, 0.01), "vz": snappedf(vel.z, 0.01),
		})
	elif not _local_wallet.is_empty() or _bridge_engaged:
		var cm := _chain_manager()
		if cm and cm.has_method("send_multiplayer_position"):
			cm.send_multiplayer_position(pos.x, pos.y, pos.z, yaw, vel.x, vel.z)


# ── Native realtime events ──────────────────────────────────────────────

func _on_rt_presence_joined(channel: String, key: String, meta: Dictionary) -> void:
	if channel != _qing_channel or key == _local_key:
		return
	_spawn_remote_player(key.to_lower(), meta)
	_force_send = true  # let the newcomer see where we are right away


func _on_rt_presence_updated(channel: String, key: String, meta: Dictionary) -> void:
	if channel != _qing_channel or not _remote_players.has(key):
		return
	var rp: Node3D = _remote_players[key]
	rp.set_presence_info(_presence_name(key, meta), int(meta.get("tier", rp.tier)))


func _on_rt_presence_left(channel: String, key: String) -> void:
	if channel != _qing_channel:
		return
	_remove_remote_player(key.to_lower())


func _on_rt_presence_synced(channel: String, state: Dictionary) -> void:
	if channel != _qing_channel:
		return
	var players: Array = []
	for k in state:
		var p: Dictionary = state[k].duplicate()
		p["wallet"] = str(k)
		players.append(p)
	_handle_sync(players)


func _on_rt_broadcast(channel: String, event: String, p: Dictionary) -> void:
	if channel != _qing_channel:
		return
	var w := str(p.get("w", "")).to_lower()
	if w.is_empty() or w == _local_key:
		return
	match event:
		"pos":
			_handle_position(w, float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)),
				float(p.get("r", 0)), float(p.get("vx", 0)), float(p.get("vz", 0)))
		"say":
			var text: String = CommunityIdentityScript.sanitize_text(str(p.get("t", "")))
			if text.is_empty():
				return
			var uname := str(p.get("n", ""))
			if _remote_players.has(w):
				_remote_players[w].show_chat(text)
				uname = _remote_players[w].username
			chat_received.emit(w, CommunityIdentityScript.sanitize_text(uname, 32), text)
		"emote":
			var eid := int(p.get("e", -1))
			if eid < 0 or eid > 7:
				return
			if _remote_players.has(w):
				_remote_players[w].show_emote(eid)
			emote_received.emit(w, eid)


func _presence_name(key: String, presence: Dictionary) -> String:
	var n := CommunityIdentityScript.sanitize_text(str(presence.get("username", "")), 32)
	if n.is_empty() or n == "<null>":
		if CommunityIdentityScript.is_guest_key(key):
			return CommunityIdentityScript.guest_display_name(key)
		return CommunityIdentityScript.short_wallet(key)
	return n


# ── Incoming Events from wallet_bridge (fallback path) ──────────────────
# main.gd connects ChainManager.mp_* here. While the native client owns the channel these
# are ignored so the two transports never fight over the avatar list.

func on_player_sync(players: Array) -> void:
	if _native_joined:
		return
	_handle_sync(players)


func on_player_join(wallet: String, presence: Dictionary) -> void:
	if _native_joined:
		return
	var w := wallet.to_lower()
	if w == _local_key or w == _local_wallet or w.is_empty() or _remote_players.has(w):
		return
	_spawn_remote_player(w, presence)


func on_player_leave(wallet: String) -> void:
	if _native_joined:
		return
	var w := wallet.to_lower()
	if w == _local_key or w == _local_wallet:
		return
	_remove_remote_player(w)


func on_position_update(wallet: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
	if _native_joined:
		return
	_handle_position(wallet.to_lower(), x, y, z, yaw, vx, vz)


func on_speaking_update(wallet: String, speaking: bool) -> void:
	## Called when voice chat speaking status changes.
	var w := wallet.to_lower()
	if not _remote_players.has(w):
		return
	_remote_players[w].set_speaking(speaking)


func _handle_sync(players: Array) -> void:
	## Full presence list → spawn missing, refresh known, remove absent.
	var synced: Dictionary = {}
	for p in players:
		if not (p is Dictionary):
			continue
		var w: String = str(p.get("wallet", "")).to_lower()
		if w.is_empty() or w == _local_key or w == _local_wallet:
			continue
		synced[w] = true
		if not _remote_players.has(w):
			_spawn_remote_player(w, p)
		else:
			var rp: Node3D = _remote_players[w]
			rp.set_presence_info(_presence_name(w, p), int(p.get("tier", rp.tier)))
	var to_remove: Array[String] = []
	for w: String in _remote_players:
		if not synced.has(w):
			to_remove.append(w)
	for w in to_remove:
		_remove_remote_player(w)


func _handle_position(w: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
	if w == _local_key or w == _local_wallet or not _remote_players.has(w):
		return  # Not yet spawned via presence — ignore position until join
	_remote_players[w].update_position(Vector3(x, y, z), yaw, vx, vz)


# ── Spawn / Remove ─────────────────────────────────────────────────────

func _spawn_remote_player(wallet: String, presence: Dictionary) -> void:
	if _remote_players.has(wallet):
		return
	if _remote_players.size() >= MAX_REMOTE_PLAYERS:
		return  # Silently cap — the counter UI still shows the full number

	var rp := Node3D.new()
	rp.set_script(RemotePlayerScript)
	rp.name = "RemotePlayer_%s" % wallet.replace(":", "_").left(14)

	if _parent_3d and is_instance_valid(_parent_3d):
		_parent_3d.add_child(rp)
	else:
		add_child(rp)

	var username := _presence_name(wallet, presence)
	var tier := int(presence.get("tier", 0))
	var level := int(presence.get("level", 1))

	rp.initialize(wallet, username, tier, level)

	var px := float(presence.get("x", 0))
	var py := float(presence.get("y", 1.3))
	var pz := float(presence.get("z", 0))
	rp.position = Vector3(px, py, pz)
	rp.target_position = Vector3(px, py, pz)
	rp.rotation.y = float(presence.get("yaw", 0.0))
	rp.target_yaw = float(presence.get("yaw", 0.0))

	rp.stale_timeout.connect(_on_player_stale.bind(wallet))
	_remote_players[wallet] = rp

	print("[MP] Spawned remote player: %s (%s) tier=%d" % [username, wallet.left(10), tier])
	player_joined.emit(wallet, username)
	player_count_changed.emit(_remote_players.size())


func _remove_remote_player(wallet: String) -> void:
	if not _remote_players.has(wallet):
		return
	var rp: Node3D = _remote_players[wallet]
	var username: String = rp.username
	if is_instance_valid(rp):
		rp.cleanup()
	_remote_players.erase(wallet)

	print("[MP] Removed remote player: %s (%s)" % [username, wallet.left(10)])
	player_left.emit(wallet, username)
	player_count_changed.emit(_remote_players.size())


func remove_all_players() -> void:
	## Remove all remote players (e.g., on territory leave).
	var wallets := _remote_players.keys()
	for w in wallets:
		_remove_remote_player(w)


func _on_player_stale(wallet: String) -> void:
	## Called when a remote player hasn't sent updates for STALE_TIMEOUT.
	_remove_remote_player(wallet)


# ── Social actions (chat bubbles / emotes) ──────────────────────────────

func send_say(text: String) -> bool:
	## Show a chat bubble over our head here and on everyone else's screen in this QING.
	var t: String = CommunityIdentityScript.sanitize_text(text)
	if t.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - _last_say_ms < int(SAY_COOLDOWN * 1000.0):
		return false
	_last_say_ms = now
	show_local_chat(t)
	if _native_live():
		return _rt.send_broadcast(_qing_channel, "say", {"w": _local_key, "n": _local_name, "t": t})
	return false


func send_emote(emote_id: int) -> bool:
	if emote_id < 0 or emote_id > 7:
		return false
	var now := Time.get_ticks_msec()
	if now - _last_emote_ms < int(EMOTE_COOLDOWN * 1000.0):
		return false
	_last_emote_ms = now
	if _native_live():
		return _rt.send_broadcast(_qing_channel, "emote", {"w": _local_key, "e": emote_id})
	return false


func show_local_chat(text: String) -> void:
	if not _local_player or not is_instance_valid(_local_player):
		return
	if _local_bubble and is_instance_valid(_local_bubble):
		_local_bubble.queue_free()
	_local_bubble = RemotePlayerScript.make_bubble(text)
	_local_bubble.name = "CommunityChatBubble"
	_local_bubble.position = Vector3(0, 2.4, 0)
	_local_player.add_child(_local_bubble)
	_local_bubble_t = 6.0 + text.length() * 0.04


func play_emote_on_all(emote_id: int) -> void:
	## Local-only flourish (e.g. everyone claps for a house round).
	for k in _remote_players:
		var rp = _remote_players[k]
		if is_instance_valid(rp):
			rp.show_emote(emote_id)


# ── Queries ─────────────────────────────────────────────────────────────

func get_player_count() -> int:
	return _remote_players.size()


func get_remote_players() -> Dictionary:
	return _remote_players.duplicate()


func get_remote_player(key: String) -> Node3D:
	return _remote_players.get(key.to_lower())


func find_remote_by_name(uname: String) -> Node3D:
	var n := uname.strip_edges().to_lower()
	if n.is_empty():
		return null
	for k in _remote_players:
		var rp = _remote_players[k]
		if is_instance_valid(rp) and str(rp.username).to_lower() == n:
			return rp
	return null


func get_realtime() -> Node:
	return _rt


func get_local_key() -> String:
	return _local_key


func get_local_name() -> String:
	return _local_name


func get_local_tier() -> int:
	return _eff_tier


func is_guest() -> bool:
	return _is_guest


func get_qing_channel() -> String:
	return _qing_channel


func get_qing_address() -> String:
	return _qing_address


func is_native_joined() -> bool:
	return _native_joined


func get_transport_mode() -> String:
	return _mode


# ── Helpers ─────────────────────────────────────────────────────────────

func _chain_manager() -> Node:
	return get_node_or_null("/root/ChainManager") if is_inside_tree() else null


func _game_manager() -> Node:
	return get_node_or_null("/root/GameManager") if is_inside_tree() else null


func _exit_tree() -> void:
	if _native_joined:
		WalletBridgeScript.native_mp_active = false
