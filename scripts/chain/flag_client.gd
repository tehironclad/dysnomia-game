extends Node
## API client for territory flag/guestbook system.
## GET /api/flags?qing=ADDRESS → load flags for a territory
## POST /api/flags {wallet, message, position, territory} → plant a new flag

const API_BASE: String = "https://entropy-dysnomia.vercel.app"
const CACHE_TTL: float = 60.0  # Cache flags for 60s

signal flags_loaded(flags: Array)
signal flag_planted(success: bool, message: String)

var _http_get: HTTPRequest
var _http_post: HTTPRequest
var _cached_flags: Array = []
var _cache_time: float = 0.0
var _post_queue: Array[Dictionary] = []
var _posting: bool = false


func _ready() -> void:
	_http_get = HTTPRequest.new()
	_http_get.name = "FlagGetHTTP"
	_http_get.timeout = 15.0
	add_child(_http_get)
	_http_get.request_completed.connect(_on_get_completed)

	_http_post = HTTPRequest.new()
	_http_post.name = "FlagPostHTTP"
	_http_post.timeout = 15.0
	add_child(_http_post)
	_http_post.request_completed.connect(_on_post_completed)


func load_flags(territory_address: String) -> void:
	## Fetch flags for the given territory.
	if territory_address.is_empty():
		flags_loaded.emit([])
		return

	# Check cache
	var now := Time.get_ticks_msec() / 1000.0
	if not _cached_flags.is_empty() and (now - _cache_time) < CACHE_TTL:
		flags_loaded.emit(_cached_flags)
		return

	var url := "%s/api/flags?qing=%s" % [API_BASE, territory_address]
	var err := _http_get.request(url)
	if err != OK:
		print("[FlagClient] GET request failed: %d" % err)
		flags_loaded.emit([])


func plant_flag(wallet: String, username: String, message: String,
		position: Vector3, territory: String) -> void:
	## Plant a flag at the player's position with a message.
	var payload := {
		"wallet": wallet,
		"username": username,
		"message": message.substr(0, 80),  # Cap at 80 chars
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"territory": territory,
		"timestamp": Time.get_unix_time_from_system(),
	}
	_post_queue.append(payload)
	_process_post_queue()


func _process_post_queue() -> void:
	if _posting or _post_queue.is_empty():
		return
	_posting = true
	var payload: Dictionary = _post_queue.pop_front()
	var json_str := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	var url := "%s/api/flags" % API_BASE
	var err := _http_post.request(url, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[FlagClient] POST request failed: %d" % err)
		_posting = false
		flag_planted.emit(false, "Request failed")
		_process_post_queue()


func _on_get_completed(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		print("[FlagClient] GET failed with status %d" % response_code)
		flags_loaded.emit([])
		return

	var json := JSON.new()
	var err := json.parse(body.get_string_from_utf8())
	if err != OK:
		print("[FlagClient] Failed to parse flags JSON")
		flags_loaded.emit([])
		return

	var data = json.data
	if data is Dictionary and data.has("flags"):
		_cached_flags = data.flags
	elif data is Array:
		_cached_flags = data
	else:
		_cached_flags = []

	_cache_time = Time.get_ticks_msec() / 1000.0
	flags_loaded.emit(_cached_flags)


func _on_post_completed(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	_posting = false

	if response_code >= 200 and response_code < 300:
		flag_planted.emit(true, "Flag planted!")
		# Invalidate cache so next load gets the new flag
		_cache_time = 0.0
	else:
		var msg := "Server error %d" % response_code
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			msg = json.data.get("error", msg)
		flag_planted.emit(false, msg)

	_process_post_queue()
