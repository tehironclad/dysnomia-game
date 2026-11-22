extends Node
## Fetches daily challenge and challenge list data from the entropy API.
## GET /api/daily   — current daily challenge set (rotates every 24h UTC)
## GET /api/challenges — full challenge catalogue with progress for a wallet

signal daily_loaded(data: Dictionary)
signal challenges_loaded(challenges: Array)

## The Entropy site's Redis-backed endpoints (achievements, XP, flags, alliances,
## daily/challenges, presence, online players, leaderboard) are empty in
## production and their old host is gone (docs/LEARNINGS.md §8). Requests are
## switched off and report "unavailable" through the normal failure path until
## Phase 7 removes these features.
const LEGACY_API_ENABLED := false
const ENTROPY_API_BASE: String = ""  # old host is gone
const API_BASE: String = ""

# ── State ───────────────────────────────────────────────────────────────
var _http_daily: HTTPRequest
var _http_challenges: HTTPRequest
var _wallet: String = ""
var _daily_cache: Dictionary = {}
var _challenges_cache: Array = []
var _last_daily_fetch: float = 0.0
var _last_challenges_fetch: float = 0.0

## Minimum seconds between repeated fetches (avoid hammering the API).
const CACHE_TTL: float = 30.0


func _ready() -> void:
	_http_daily = HTTPRequest.new()
	_http_daily.name = "DailyHTTP"
	_http_daily.timeout = 15.0
	add_child(_http_daily)
	_http_daily.request_completed.connect(_on_daily_response)

	_http_challenges = HTTPRequest.new()
	_http_challenges.name = "ChallengesHTTP"
	_http_challenges.timeout = 15.0
	add_child(_http_challenges)
	_http_challenges.request_completed.connect(_on_challenges_response)


func set_wallet(wallet_address: String) -> void:
	_wallet = wallet_address.to_lower()


# ── Public API ──────────────────────────────────────────────────────────

func fetch_daily() -> void:
	## Fetch today's daily challenge set.  Result arrives via daily_loaded signal.
	var now := Time.get_unix_time_from_system()
	if now - _last_daily_fetch < CACHE_TTL and not _daily_cache.is_empty():
		daily_loaded.emit(_daily_cache)
		return

	if not LEGACY_API_ENABLED:
		_on_daily_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	var url := ENTROPY_API_BASE + "/api/daily"
	if not _wallet.is_empty():
		url += "?wallet=" + _wallet
	var err := _http_daily.request(url)
	if err != OK:
		print("[DailyChallenges] fetch_daily HTTP error: %d" % err)
		daily_loaded.emit({})


func fetch_challenges() -> void:
	## Fetch the full challenge catalogue (optionally with wallet progress).
	var now := Time.get_unix_time_from_system()
	if now - _last_challenges_fetch < CACHE_TTL and not _challenges_cache.is_empty():
		challenges_loaded.emit(_challenges_cache)
		return

	if not LEGACY_API_ENABLED:
		_on_challenges_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return
	var url := ENTROPY_API_BASE + "/api/challenges"
	if not _wallet.is_empty():
		url += "?wallet=" + _wallet
	var err := _http_challenges.request(url)
	if err != OK:
		print("[DailyChallenges] fetch_challenges HTTP error: %d" % err)
		challenges_loaded.emit([])


func get_daily_cache() -> Dictionary:
	return _daily_cache


func get_challenges_cache() -> Array:
	return _challenges_cache


# ── Response handlers ───────────────────────────────────────────────────

func _on_daily_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		print("[DailyChallenges] /api/daily returned HTTP %d" % code)
		daily_loaded.emit({})
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		print("[DailyChallenges] /api/daily returned invalid JSON")
		daily_loaded.emit({})
		return

	_daily_cache = parsed as Dictionary
	_last_daily_fetch = Time.get_unix_time_from_system()
	print("[DailyChallenges] Daily loaded: %d challenges" % _daily_cache.get("challenges", []).size())
	daily_loaded.emit(_daily_cache)


func _on_challenges_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		print("[DailyChallenges] /api/challenges returned HTTP %d" % code)
		challenges_loaded.emit([])
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)

	# API may return {challenges: [...]} or a bare array
	if parsed is Dictionary:
		var dict: Dictionary = parsed
		var arr: Variant = dict.get("challenges", [])
		if arr is Array:
			_challenges_cache = arr
		else:
			_challenges_cache = []
	elif parsed is Array:
		_challenges_cache = parsed as Array
	else:
		print("[DailyChallenges] /api/challenges returned invalid JSON")
		challenges_loaded.emit([])
		return

	_last_challenges_fetch = Time.get_unix_time_from_system()
	print("[DailyChallenges] Challenges loaded: %d entries" % _challenges_cache.size())
	challenges_loaded.emit(_challenges_cache)


# ── Convenience helpers ─────────────────────────────────────────────────

func get_daily_time_remaining() -> int:
	## Seconds until the daily challenge resets (next UTC midnight).
	var unix := int(Time.get_unix_time_from_system())
	var seconds_into_day := unix % 86400
	return 86400 - seconds_into_day


func format_time_remaining() -> String:
	## Human-readable time until daily reset (e.g. "5h 23m").
	var secs := get_daily_time_remaining()
	var hours := secs / 3600
	var minutes := (secs % 3600) / 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes


func is_challenge_complete(challenge: Dictionary) -> bool:
	## Returns true if challenge progress >= target.
	var progress: int = challenge.get("progress", 0)
	var target: int = challenge.get("target", 1)
	return progress >= target
