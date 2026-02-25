extends Node
## Client for unlocking achievements via the entropy API.
## POST /api/achievements {wallet, id} to unlock.
## Server validates on-chain/hybrid types; client types are trusted.
## Caches unlocked IDs locally to avoid redundant POSTs.

signal achievement_unlocked(id: String, data: Dictionary)
signal achievement_failed(id: String, reason: String)
signal tier_changed(tier: int, title: String)

const ENTROPY_API_BASE: String = "https://entropy-dysnomia.vercel.app"
const CACHE_PATH: String = "user://achievements.json"

# ── All 43 achievement definitions (mirrors api/achievements.js) ────────
const ACHIEVEMENTS: Dictionary = {
	# Distance milestones (client-validated)
	"dist_500":  {"name": "First 500m",       "desc": "Travel 500 meters",                "icon": "walking",  "xp": 50},
	"dist_2k":   {"name": "Two Kilometers",    "desc": "Travel 2,000 meters",              "icon": "running",  "xp": 50},
	"dist_5k":   {"name": "5K Runner",         "desc": "Travel 5,000 meters",              "icon": "running",  "xp": 50},
	"dist_10k":  {"name": "Marathon Walker",   "desc": "Travel 10,000 meters",             "icon": "medal",    "xp": 50},
	"dist_50k":  {"name": "Ultramarathon",     "desc": "Travel 50,000 meters",             "icon": "trophy",   "xp": 50},
	# Session milestones (client-validated)
	"jump_100":  {"name": "Kangaroo",          "desc": "Jump 100 times",                   "icon": "jump",     "xp": 50},
	"alt_30":    {"name": "Mountaineer",       "desc": "Reach 30m altitude",               "icon": "mountain", "xp": 50},
	"sess_30m":  {"name": "Committed",         "desc": "Play for 30 minutes",              "icon": "clock",    "xp": 50},
	"sess_60m":  {"name": "Dedicated",         "desc": "Play for 60 minutes",              "icon": "clock",    "xp": 50},
	# Gameplay (client-validated)
	"pioneer_3":     {"name": "Pioneer",           "desc": "Terraform 3 times in one session", "icon": "flag",   "xp": 50},
	"first_chat":    {"name": "Hello World",       "desc": "Send your first on-chain chat",    "icon": "chat",   "xp": 50},
	"explorer_5":    {"name": "Explorer",          "desc": "Visit 5 territories in one session","icon": "map",   "xp": 50},
	"first_quest":   {"name": "Questbound",        "desc": "Complete your first quest",        "icon": "quest",  "xp": 50},
	"all_quests":    {"name": "Completionist",     "desc": "Complete all quests",              "icon": "star",   "xp": 50},
	"resource_10":   {"name": "Collector",         "desc": "Collect 10 resources",             "icon": "gem",    "xp": 50},
	"anomaly_1":     {"name": "Anomaly Hunter",    "desc": "Interact with an anomaly",         "icon": "eye",    "xp": 50},
	"daily_complete":{"name": "Daily Driver",      "desc": "Complete all daily objectives",    "icon": "check",  "xp": 50},
	"first_emote":   {"name": "Expressive",        "desc": "Use your first emote",             "icon": "wave",   "xp": 50},
	"first_flag":    {"name": "Flagbearer",        "desc": "Plant a flag in a territory",      "icon": "flag",   "xp": 50},
	"challenge_1":   {"name": "Challenger",        "desc": "Complete a challenge",              "icon": "bolt",   "xp": 50},
	"challenge_all": {"name": "Champion",          "desc": "Complete all challenges",           "icon": "crown",  "xp": 50},
	# Terraform milestones (on-chain validated)
	"first_terraform": {"name": "First Terraform", "desc": "Perform your first terraform",     "icon": "terra",  "xp": 50},
	"terraform_10":    {"name": "Terraformer",     "desc": "Terraform 10 times",               "icon": "terra",  "xp": 50},
	"terraform_50":    {"name": "Landscaper",      "desc": "Terraform 50 times",               "icon": "terra",  "xp": 50},
	"terraform_100":   {"name": "World Shaper",    "desc": "Terraform 100 times",              "icon": "terra",  "xp": 50},
	# Beat milestones (on-chain validated)
	"first_beat":  {"name": "First Beat",      "desc": "Send your first META Beat",        "icon": "beat",   "xp": 50},
	"beat_10":     {"name": "Beatmaker",       "desc": "Send 10 META Beats",               "icon": "beat",   "xp": 50},
	"beat_50":     {"name": "Rhythm Master",   "desc": "Send 50 META Beats",               "icon": "beat",   "xp": 50},
	# Ranking (on-chain validated)
	"top_10_tf":   {"name": "Top 10 Terraform","desc": "Reach top 10 in terraform count",  "icon": "rank",   "xp": 50},
	"top_10_bt":   {"name": "Top 10 Beat",     "desc": "Reach top 10 in beat count",       "icon": "rank",   "xp": 50},
	# Level (on-chain validated)
	"level_5":     {"name": "Level 5",         "desc": "Reach level 5",                    "icon": "level",  "xp": 50},
	"level_10":    {"name": "Level 10",        "desc": "Reach level 10",                   "icon": "level",  "xp": 50},
	"level_20":    {"name": "Level 20",        "desc": "Reach level 20",                   "icon": "level",  "xp": 50},
	# Territory visits (hybrid validated)
	"terr_3":      {"name": "Tourist",         "desc": "Visit 3 different territories",    "icon": "map",    "xp": 50},
	"terr_10":     {"name": "Cartographer",    "desc": "Visit 10 different territories",   "icon": "map",    "xp": 50},
	"terr_25":     {"name": "World Traveler",  "desc": "Visit 25 different territories",   "icon": "map",    "xp": 50},
	# Streaks (hybrid validated)
	"streak_3":    {"name": "3-Day Streak",    "desc": "Play 3 days in a row",             "icon": "fire",   "xp": 50},
	"streak_7":    {"name": "Weekly Warrior",  "desc": "Play 7 days in a row",             "icon": "fire",   "xp": 50},
	"streak_14":   {"name": "Fortnight",       "desc": "Play 14 days in a row",            "icon": "fire",   "xp": 50},
	"streak_30":   {"name": "Monthly Master",  "desc": "Play 30 days in a row",            "icon": "fire",   "xp": 50},
	"streak_7_ach":   {"name": "Streak Keeper",   "desc": "Maintain a 7-day streak",       "icon": "fire",   "xp": 50},
	"terr_visit_10":  {"name": "Frequent Flyer",  "desc": "Visit 10 territories total",    "icon": "globe",  "xp": 50},
}

# ── Evolution tiers (mirrors api/achievements.js TITLE_TIERS) ───────────
const TITLE_TIERS: Array[Dictionary] = [
	{"threshold": 0,      "title": "Drifter",      "tier": 0},
	{"threshold": 100,    "title": "Wanderer",      "tier": 1},
	{"threshold": 500,    "title": "Scout",          "tier": 2},
	{"threshold": 1500,   "title": "Pathfinder",     "tier": 3},
	{"threshold": 4000,   "title": "Trailblazer",    "tier": 4},
	{"threshold": 10000,  "title": "Voidwalker",     "tier": 5},
	{"threshold": 25000,  "title": "Starcaller",     "tier": 6},
	{"threshold": 60000,  "title": "Architect",      "tier": 7},
	{"threshold": 150000, "title": "Celestial",      "tier": 8},
	{"threshold": 400000, "title": "Entropy Lord",   "tier": 9},
]

# ── State ───────────────────────────────────────────────────────────────
var _unlocked: Dictionary = {}  # id -> unix timestamp
var _http: HTTPRequest
var _pending_id: String = ""
var _post_queue: Array[String] = []  # Queue for sequential POSTs
var _is_posting: bool = false
var _total_xp: int = 0
var _current_tier: int = 0
var _current_title: String = "Drifter"
var _wallet: String = ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "AchievementHTTP"
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_post_response)


func set_wallet(wallet_address: String) -> void:
	_wallet = wallet_address.to_lower()
	_load_cache()


func try_unlock(achievement_id: String) -> void:
	## Queue an achievement unlock attempt. Skips if already unlocked.
	if achievement_id.is_empty() or not ACHIEVEMENTS.has(achievement_id):
		return
	if _unlocked.has(achievement_id):
		return
	if _wallet.is_empty():
		return
	if achievement_id in _post_queue:
		return
	_post_queue.append(achievement_id)
	_process_queue()


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)


func get_unlocked_count() -> int:
	return _unlocked.size()


func get_total_xp() -> int:
	return _total_xp


func get_tier() -> int:
	return _current_tier


func get_title() -> String:
	return _current_title


func get_all_unlocked() -> Dictionary:
	return _unlocked.duplicate()


# ── POST queue processing ───────────────────────────────────────────────

func _process_queue() -> void:
	if _is_posting or _post_queue.is_empty():
		return
	_is_posting = true
	_pending_id = _post_queue.pop_front()

	var body := JSON.stringify({"wallet": _wallet, "id": _pending_id})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := ENTROPY_API_BASE + "/api/achievements"
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("[AchievementClient] HTTP request failed for %s: %d" % [_pending_id, err])
		_is_posting = false
		_process_queue()


func _on_post_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var id := _pending_id
	_pending_id = ""
	_is_posting = false

	if code != 200:
		push_warning("[AchievementClient] POST failed for %s: HTTP %d" % [id, code])
		achievement_failed.emit(id, "HTTP %d" % code)
		_process_queue()
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		achievement_failed.emit(id, "Invalid response")
		_process_queue()
		return

	var data: Dictionary = parsed
	if data.get("unlocked", false):
		var ts := int(Time.get_unix_time_from_system())
		_unlocked[id] = ts
		_total_xp = data.get("totalXP", _total_xp)
		var old_tier := _current_tier
		_current_tier = data.get("tier", _current_tier)
		_current_title = data.get("title", _current_title)
		_save_cache()

		var ach: Dictionary = ACHIEVEMENTS.get(id, {})
		print("[AchievementClient] Unlocked: %s (%s) +%d XP | Total: %d XP | Tier %d: %s" % [
			id, ach.get("name", id), ach.get("xp", 50), _total_xp, _current_tier, _current_title])

		achievement_unlocked.emit(id, {
			"name": ach.get("name", id),
			"desc": ach.get("desc", ""),
			"xp": ach.get("xp", 50),
			"total_xp": _total_xp,
			"tier": _current_tier,
			"title": _current_title,
			"count": data.get("count", _unlocked.size()),
		})

		if _current_tier > old_tier:
			tier_changed.emit(_current_tier, _current_title)
	else:
		var reason: String = data.get("reason", "Validation failed")
		if reason != "Already unlocked":
			achievement_failed.emit(id, reason)
		else:
			# Server says already unlocked — cache it locally too
			_unlocked[id] = int(Time.get_unix_time_from_system())
			_save_cache()

	_process_queue()


# ── Bulk check helpers (called after terraform/beat/level changes) ──────

func check_terraform_milestones(terraform_count: int) -> void:
	## Call after terraform confirmations with running count.
	if terraform_count >= 1:
		try_unlock("first_terraform")
	if terraform_count >= 10:
		try_unlock("terraform_10")
	if terraform_count >= 50:
		try_unlock("terraform_50")
	if terraform_count >= 100:
		try_unlock("terraform_100")


func check_beat_milestones(beat_count: int) -> void:
	## Call after beat confirmations with running count.
	if beat_count >= 1:
		try_unlock("first_beat")
	if beat_count >= 10:
		try_unlock("beat_10")
	if beat_count >= 50:
		try_unlock("beat_50")


func check_level_milestones(level: int) -> void:
	## Call when player level is known.
	if level >= 5:
		try_unlock("level_5")
	if level >= 10:
		try_unlock("level_10")
	if level >= 20:
		try_unlock("level_20")


func check_territory_milestones(count: int) -> void:
	## Call when distinct territory visit count changes.
	if count >= 3:
		try_unlock("terr_3")
	if count >= 10:
		try_unlock("terr_10")
		try_unlock("terr_visit_10")
	if count >= 25:
		try_unlock("terr_25")


# ── Local cache ─────────────────────────────────────────────────────────

func _save_cache() -> void:
	var data := {
		"wallet": _wallet,
		"unlocked": _unlocked,
		"total_xp": _total_xp,
		"tier": _current_tier,
		"title": _current_title,
	}
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	# Only load cache if it's for the same wallet
	if data.get("wallet", "") != _wallet:
		return
	var unlocked_data: Variant = data.get("unlocked", {})
	if unlocked_data is Dictionary:
		_unlocked = unlocked_data
	_total_xp = data.get("total_xp", 0)
	_current_tier = data.get("tier", 0)
	_current_title = data.get("title", "Drifter")
	print("[AchievementClient] Loaded cache: %d unlocked, %d XP, tier %d (%s)" % [
		_unlocked.size(), _total_xp, _current_tier, _current_title])


func sync_from_server(server_data: Dictionary) -> void:
	## Called when GET /api/achievements returns — merge server state into local cache.
	var server_achievements: Variant = server_data.get("achievements", {})
	if server_achievements is Dictionary:
		for id: String in server_achievements:
			if not _unlocked.has(id):
				_unlocked[id] = server_achievements[id]
	_total_xp = server_data.get("totalXP", _total_xp)
	_current_tier = server_data.get("tier", _current_tier)
	_current_title = server_data.get("title", _current_title)
	_save_cache()


static func get_tier_for_xp(xp: int) -> Dictionary:
	## Returns {"tier": int, "title": String} for given XP.
	var result: Dictionary = TITLE_TIERS[0]
	for t: Dictionary in TITLE_TIERS:
		if xp >= t["threshold"]:
			result = t
	return result
