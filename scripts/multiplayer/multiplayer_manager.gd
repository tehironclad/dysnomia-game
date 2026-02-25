extends Node
## Manages remote player instances for multiplayer presence.
## Receives position updates from wallet_bridge (via Supabase channel in browser)
## and broadcasts local player position every 100ms.
##
## Data flow:
##   Local player moves → broadcast_timer fires every 100ms
##     → wallet_bridge WS → wallet.html → Supabase broadcast
##     → Other players' wallet.html → WS → wallet_bridge
##     → multiplayer_manager.on_position_update() → remote_player interpolation

signal player_count_changed(count: int)
signal player_joined(wallet: String, username: String)
signal player_left(wallet: String, username: String)

const RemotePlayerScript = preload("res://scripts/multiplayer/remote_player.gd")

const MAX_REMOTE_PLAYERS: int = 20
const BROADCAST_INTERVAL: float = 0.1  # 100ms between position broadcasts

# ── State ──
var _remote_players: Dictionary = {}  # wallet (lowercase) → RemotePlayer node
var _broadcast_timer: float = 0.0
var _local_player: CharacterBody3D = null
var _local_wallet: String = ""
var _local_username: String = ""
var _local_tier: int = 0
var _parent_3d: Node3D = null  # Where to spawn remote player nodes
var _active: bool = false


func set_local_player(player: CharacterBody3D, wallet: String, username: String, tier: int) -> void:
	_local_player = player
	_local_wallet = wallet.to_lower()
	_local_username = username
	_local_tier = tier


func set_spawn_parent(parent: Node3D) -> void:
	_parent_3d = parent


func activate() -> void:
	_active = true
	_broadcast_timer = 0.0


func deactivate() -> void:
	_active = false
	remove_all_players()


func _process(delta: float) -> void:
	if not _active:
		return

	# Broadcast local player position at fixed interval
	_broadcast_timer += delta
	if _broadcast_timer >= BROADCAST_INTERVAL and _local_player and not _local_wallet.is_empty():
		_broadcast_timer = 0.0
		_broadcast_position()


# ── Incoming Events from wallet_bridge ──────────────────────────────────

func on_player_sync(players: Array) -> void:
	## Called on initial presence sync — full list of players in the channel.
	## Spawn any we don't have, mark any not in list as stale.
	var synced_wallets: Dictionary = {}
	for p in players:
		if not (p is Dictionary):
			continue
		var w: String = p.get("wallet", "").to_lower()
		if w.is_empty() or w == _local_wallet:
			continue
		synced_wallets[w] = true
		if not _remote_players.has(w):
			_spawn_remote_player(w, p)
		else:
			# Update existing player's presence data
			var rp: Node3D = _remote_players[w]
			rp.update_position(
				Vector3(p.get("x", 0), p.get("y", 0), p.get("z", 0)),
				p.get("yaw", 0.0),
				p.get("vx", 0.0),
				p.get("vz", 0.0),
			)

	# Remove players not in sync
	var to_remove: Array[String] = []
	for w: String in _remote_players:
		if not synced_wallets.has(w):
			to_remove.append(w)
	for w in to_remove:
		_remove_remote_player(w)


func on_player_join(wallet: String, presence: Dictionary) -> void:
	## Called when a new player joins the territory channel.
	var w := wallet.to_lower()
	if w == _local_wallet or w.is_empty():
		return
	if _remote_players.has(w):
		return  # Already spawned
	_spawn_remote_player(w, presence)


func on_player_leave(wallet: String) -> void:
	## Called when a player leaves the territory channel.
	var w := wallet.to_lower()
	if w == _local_wallet:
		return
	_remove_remote_player(w)


func on_position_update(wallet: String, x: float, y: float, z: float, yaw: float, vx: float, vz: float) -> void:
	## Called on each 100ms position broadcast from a remote player.
	var w := wallet.to_lower()
	if w == _local_wallet:
		return
	if not _remote_players.has(w):
		return  # Not yet spawned via presence — ignore position until join
	var rp: Node3D = _remote_players[w]
	rp.update_position(Vector3(x, y, z), yaw, vx, vz)


func on_speaking_update(wallet: String, speaking: bool) -> void:
	## Called when voice chat speaking status changes.
	var w := wallet.to_lower()
	if not _remote_players.has(w):
		return
	_remote_players[w].set_speaking(speaking)


# ── Spawn / Remove ─────────────────────────────────────────────────────

func _spawn_remote_player(wallet: String, presence: Dictionary) -> void:
	if _remote_players.size() >= MAX_REMOTE_PLAYERS:
		push_warning("[MP] Max remote players (%d) reached, ignoring %s" % [MAX_REMOTE_PLAYERS, wallet.left(8)])
		return

	var rp := Node3D.new()
	rp.set_script(RemotePlayerScript)
	rp.name = "RemotePlayer_%s" % wallet.left(8)

	if _parent_3d:
		_parent_3d.add_child(rp)
	else:
		add_child(rp)

	var username: String = presence.get("username", wallet.left(6) + ".." + wallet.right(4))
	var tier: int = presence.get("tier", 0)
	var level: int = presence.get("level", 1)

	rp.initialize(wallet, username, tier, level)

	# Set initial position
	var px: float = presence.get("x", 0)
	var py: float = presence.get("y", 1.3)
	var pz: float = presence.get("z", 0)
	rp.position = Vector3(px, py, pz)
	rp.target_position = Vector3(px, py, pz)
	rp.rotation.y = presence.get("yaw", 0.0)
	rp.target_yaw = presence.get("yaw", 0.0)

	rp.stale_timeout.connect(_on_player_stale.bind(wallet))
	_remote_players[wallet] = rp

	print("[MP] Spawned remote player: %s (%s) tier=%d" % [username, wallet.left(8), tier])
	player_joined.emit(wallet, username)
	player_count_changed.emit(_remote_players.size())


func _remove_remote_player(wallet: String) -> void:
	if not _remote_players.has(wallet):
		return
	var rp: Node3D = _remote_players[wallet]
	var username: String = rp.username
	rp.cleanup()
	_remote_players.erase(wallet)

	print("[MP] Removed remote player: %s (%s)" % [username, wallet.left(8)])
	player_left.emit(wallet, username)
	player_count_changed.emit(_remote_players.size())


func remove_all_players() -> void:
	## Remove all remote players (e.g., on territory leave).
	var wallets := _remote_players.keys()
	for w in wallets:
		_remove_remote_player(w)


func _on_player_stale(wallet: String) -> void:
	## Called when a remote player hasn't sent updates for STALE_TIMEOUT.
	push_warning("[MP] Player stale (30s no updates): %s" % wallet.left(8))
	_remove_remote_player(wallet)


# ── Local Position Broadcast ────────────────────────────────────────────

func _broadcast_position() -> void:
	## Send local player's position to wallet_bridge for Supabase broadcast.
	if not _local_player or _local_wallet.is_empty():
		return

	var pos := _local_player.global_position
	var vel := _local_player.velocity
	ChainManager.send_multiplayer_position(pos.x, pos.y, pos.z, _local_player.rotation.y, vel.x, vel.z)


func get_player_count() -> int:
	return _remote_players.size()


func get_remote_players() -> Dictionary:
	return _remote_players.duplicate()
