extends Node
## Client for the alliance/guild system via the entropy API.
## GET  /api/alliance?wallet=ADDRESS  — fetch alliance info for a wallet
## POST /api/alliance {wallet, action, data}  — perform alliance actions
##   Actions: "create", "join", "leave", "invite", "kick", "promote"

signal alliance_loaded(data: Dictionary)
signal alliance_action_result(success: bool, data: Dictionary)

## The Entropy site's Redis-backed endpoints (achievements, XP, flags, alliances,
## daily/challenges, presence, online players, leaderboard) are empty in
## production and their old host is gone (docs/LEARNINGS.md §8). Requests are
## switched off and report "unavailable" through the normal failure path until
## Phase 7 removes these features.
const LEGACY_API_ENABLED := false
const ENTROPY_API_BASE: String = ""  # old host is gone
const API_BASE: String = ""

# ── State ───────────────────────────────────────────────────────────────
var _http_get: HTTPRequest
var _http_post: HTTPRequest
var _alliance_cache: Dictionary = {}
var _is_posting: bool = false
var _post_queue: Array[Dictionary] = []


func _ready() -> void:
	_http_get = HTTPRequest.new()
	_http_get.name = "AllianceGetHTTP"
	_http_get.timeout = 15.0
	add_child(_http_get)
	_http_get.request_completed.connect(_on_get_response)

	_http_post = HTTPRequest.new()
	_http_post.name = "AlliancePostHTTP"
	_http_post.timeout = 15.0
	add_child(_http_post)
	_http_post.request_completed.connect(_on_post_response)


# ── Public API ──────────────────────────────────────────────────────────

func fetch_alliance(wallet: String) -> void:
	## Fetch current alliance data for the given wallet address.
	if wallet.is_empty():
		print("[AllianceClient] fetch_alliance called with empty wallet")
		alliance_loaded.emit({})
		return

	if not LEGACY_API_ENABLED:
		_on_get_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	var url := ENTROPY_API_BASE + "/api/alliance?wallet=" + wallet.to_lower()
	var err := _http_get.request(url)
	if err != OK:
		print("[AllianceClient] fetch_alliance HTTP error: %d" % err)
		alliance_loaded.emit({})


func send_alliance_action(wallet: String, action: String, data: Dictionary = {}) -> void:
	## Queue an alliance action POST.  Result arrives via alliance_action_result signal.
	## Valid actions: create, join, leave, invite, kick, promote
	if wallet.is_empty() or action.is_empty():
		print("[AllianceClient] send_alliance_action called with empty wallet or action")
		alliance_action_result.emit(false, {"reason": "Missing wallet or action"})
		return

	var payload := {
		"wallet": wallet.to_lower(),
		"action": action,
		"data": data,
	}
	_post_queue.append(payload)
	_process_post_queue()


func get_alliance_cache() -> Dictionary:
	return _alliance_cache


# ── POST queue (sequential, one at a time) ─────────────────────────────

func _process_post_queue() -> void:
	if _is_posting or _post_queue.is_empty():
		return
	_is_posting = true

	var payload: Dictionary = _post_queue.pop_front()
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not LEGACY_API_ENABLED:
		_on_post_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	var url := ENTROPY_API_BASE + "/api/alliance"
	var err := _http_post.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[AllianceClient] POST HTTP error: %d" % err)
		_is_posting = false
		alliance_action_result.emit(false, {"reason": "HTTP error %d" % err})
		_process_post_queue()


# ── Response handlers ───────────────────────────────────────────────────

func _on_get_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		print("[AllianceClient] GET /api/alliance returned HTTP %d" % code)
		alliance_loaded.emit({})
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		print("[AllianceClient] GET /api/alliance returned invalid JSON")
		alliance_loaded.emit({})
		return

	_alliance_cache = parsed as Dictionary
	print("[AllianceClient] Alliance loaded: %s" % _alliance_cache.get("name", "(none)"))
	alliance_loaded.emit(_alliance_cache)


func _on_post_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_posting = false

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed if parsed is Dictionary else {}

	if code != 200:
		print("[AllianceClient] POST /api/alliance returned HTTP %d" % code)
		alliance_action_result.emit(false, data)
		_process_post_queue()
		return

	var success: bool = data.get("success", false)
	if success:
		print("[AllianceClient] Action succeeded: %s" % data.get("action", ""))
	else:
		print("[AllianceClient] Action failed: %s" % data.get("reason", "unknown"))

	alliance_action_result.emit(success, data)
	_process_post_queue()
