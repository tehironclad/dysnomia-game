extends Node
## Tracks local player statistics for achievement thresholds.
## Distance, jumps, altitude, session time, territories visited.
## Persists cumulative stats to user://stats.json across sessions.

signal distance_milestone(id: String, distance: float)
signal jump_milestone(count: int)
signal altitude_milestone(altitude: float)
signal session_milestone(id: String, minutes: float)
signal chat_sent_first()
signal territory_visited(count: int)

# ── Cumulative (persisted) ──────────────────────────────────────────────
var total_distance: float = 0.0       # All-time horizontal meters
var total_jumps: int = 0
var total_territories: Array[String] = []  # Distinct QING addresses ever visited

# ── Session (reset each scene load) ────────────────────────────────────
var session_distance: float = 0.0
var session_jumps: int = 0
var session_max_altitude: float = 0.0
var session_start_time: float = 0.0

# ── Internal ────────────────────────────────────────────────────────────
var _player: CharacterBody3D
var _last_pos2d: Vector2 = Vector2.ZERO
var _initialized: bool = false
var _save_timer: float = 0.0
const SAVE_INTERVAL: float = 30.0  # Auto-save every 30s
const STATS_PATH: String = "user://stats.json"

# ── Distance milestones (meters) ────────────────────────────────────────
const DISTANCE_MILESTONES: Array[Dictionary] = [
	{"id": "dist_500", "threshold": 500.0, "name": "First 500m"},
	{"id": "dist_2k", "threshold": 2000.0, "name": "Two Kilometers"},
	{"id": "dist_5k", "threshold": 5000.0, "name": "5K Runner"},
	{"id": "dist_10k", "threshold": 10000.0, "name": "Marathon Walker"},
	{"id": "dist_50k", "threshold": 50000.0, "name": "Ultramarathon"},
]

var _distance_unlocked: Dictionary = {}  # id -> true

# ── Jump milestones ─────────────────────────────────────────────────────
const JUMP_THRESHOLD: int = 100  # jump_100

# ── Altitude milestones ─────────────────────────────────────────────────
const ALTITUDE_THRESHOLD: float = 30.0  # alt_30

# ── Session milestones (seconds) ────────────────────────────────────────
const SESSION_MILESTONES: Array[Dictionary] = [
	{"id": "sess_30m", "threshold": 1800.0, "name": "Committed"},
	{"id": "sess_60m", "threshold": 3600.0, "name": "Dedicated"},
]
var _session_unlocked: Dictionary = {}  # id -> true


func initialize(player: CharacterBody3D) -> void:
	_player = player
	_last_pos2d = Vector2(player.position.x, player.position.z)
	session_start_time = Time.get_unix_time_from_system()
	_initialized = true
	load_stats()

	# Connect jump signal
	if player.has_signal("player_jumped"):
		player.player_jumped.connect(_on_player_jumped)


func _physics_process(_delta: float) -> void:
	if not _initialized or not _player:
		return

	# ── Distance tracking ───────────────────────────────────────────────
	var pos2d := Vector2(_player.position.x, _player.position.z)
	var frame_dist := pos2d.distance_to(_last_pos2d)
	# Clamp to prevent teleportation spikes (e.g., scene reload, respawn)
	if frame_dist < 5.0:
		session_distance += frame_dist
		total_distance += frame_dist
	_last_pos2d = pos2d

	# ── Altitude tracking ───────────────────────────────────────────────
	if _player.position.y > session_max_altitude:
		session_max_altitude = _player.position.y


func _process(delta: float) -> void:
	if not _initialized:
		return

	# ── Check milestones periodically (not every frame) ─────────────────
	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_check_all_milestones()
		save_stats()


func _check_all_milestones() -> void:
	_check_distance_milestones()
	_check_jump_milestone()
	_check_altitude_milestone()
	_check_session_milestones()


func _check_distance_milestones() -> void:
	for m: Dictionary in DISTANCE_MILESTONES:
		var mid: String = m["id"]
		if _distance_unlocked.has(mid):
			continue
		if total_distance >= m["threshold"]:
			_distance_unlocked[mid] = true
			distance_milestone.emit(mid, m["threshold"])


func _check_jump_milestone() -> void:
	if total_jumps >= JUMP_THRESHOLD:
		jump_milestone.emit(total_jumps)


func _check_altitude_milestone() -> void:
	if session_max_altitude >= ALTITUDE_THRESHOLD:
		altitude_milestone.emit(session_max_altitude)


func _check_session_milestones() -> void:
	var session_elapsed: float = Time.get_unix_time_from_system() - session_start_time
	for m: Dictionary in SESSION_MILESTONES:
		var mid: String = m["id"]
		if _session_unlocked.has(mid):
			continue
		if session_elapsed >= m["threshold"]:
			_session_unlocked[mid] = true
			session_milestone.emit(mid, session_elapsed / 60.0)


func _on_player_jumped() -> void:
	session_jumps += 1
	total_jumps += 1


func add_territory_visited(qing_address: String) -> void:
	## Called when entering a territory. Tracks distinct QINGs visited.
	var addr := qing_address.to_lower()
	if addr in total_territories:
		return
	total_territories.append(addr)
	territory_visited.emit(total_territories.size())


func on_chat_sent() -> void:
	## Called when player sends their first on-chain chat.
	chat_sent_first.emit()


# ── Persistence ─────────────────────────────────────────────────────────

func save_stats() -> void:
	var data := {
		"total_distance": total_distance,
		"total_jumps": total_jumps,
		"total_territories": total_territories,
		"distance_unlocked": _distance_unlocked.keys(),
	}
	var file := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func load_stats() -> void:
	if not FileAccess.file_exists(STATS_PATH):
		return
	var file := FileAccess.open(STATS_PATH, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	total_distance = data.get("total_distance", 0.0)
	total_jumps = data.get("total_jumps", 0)
	var terrs: Variant = data.get("total_territories", [])
	if terrs is Array:
		total_territories.clear()
		for t: Variant in terrs:
			if t is String:
				total_territories.append(t)
	var unlocked: Variant = data.get("distance_unlocked", [])
	if unlocked is Array:
		for uid: Variant in unlocked:
			if uid is String:
				_distance_unlocked[uid] = true


func get_session_elapsed_seconds() -> float:
	return Time.get_unix_time_from_system() - session_start_time


func get_stats_summary() -> Dictionary:
	return {
		"total_distance": total_distance,
		"session_distance": session_distance,
		"total_jumps": total_jumps,
		"session_jumps": session_jumps,
		"max_altitude": session_max_altitude,
		"session_time": get_session_elapsed_seconds(),
		"territories_count": total_territories.size(),
	}
