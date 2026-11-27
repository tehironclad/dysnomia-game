class_name DailyLocal
extends RefCounted
## What THIS computer keeps about the daily challenge (user://daily.cfg): scored attempts started
## today by a player the server doesn't count (a guest, or offline), the best score of each day
## (scored and practice apart), the streak of days played, and the seed blocks found
## (DailySeed's cache: the chain's own block number, hash and time). Never sent anywhere; the
## board's numbers come from the server. `path` is a parameter so tests use their own file.

const FILE := "user://daily.cfg"
const KEEP_DAYS := 7


static func _load(path: String) -> ConfigFile:
	var c := ConfigFile.new()
	c.load(path)
	return c


## Scored attempts started on `day` by `who` (a wallet, or "guest").
static func used(day: String, who: String, path: String = FILE) -> int:
	return int(_load(path).get_value("used", "%s|%s" % [day, who.to_lower()], 0))


## Spends a local attempt. Returns {ok, attempt, left} or {ok: false, error}.
static func start_attempt(day: String, who: String, path: String = FILE) -> Dictionary:
	var c := _load(path)
	var k := "%s|%s" % [day, who.to_lower()]
	var n := int(c.get_value("used", k, 0))
	if n >= DailyChallenge.ATTEMPTS:
		return {"ok": false, "error": "no scored attempts left today (%d a day; practice is unlimited)" % DailyChallenge.ATTEMPTS, "left": 0}
	c.set_value("used", k, n + 1)
	_played(c, day)
	_prune(c, day)
	c.save(path)
	return {"ok": true, "attempt": n + 1, "left": DailyChallenge.ATTEMPTS - n - 1}


## Mirrors the server's count (a signed-in player's attempts are the server's).
static func set_used(day: String, who: String, n: int, path: String = FILE) -> void:
	var c := _load(path)
	c.set_value("used", "%s|%s" % [day, who.to_lower()], clampi(n, 0, DailyChallenge.ATTEMPTS))
	if n > 0:
		_played(c, day)
	c.save(path)


## Records a finished run: {score, practice, at, block?, verified?, rank?}. Returns true when it is
## this computer's best of that kind today.
static func record(day: String, who: String, e: Dictionary, path: String = FILE) -> bool:
	var c := _load(path)
	var kind := "practice" if bool(e.get("practice", false)) else "scored"
	var k := "%s|%s|%s" % [day, who.to_lower(), kind]
	var old = c.get_value("best", k, {})
	var s := int(e.get("score", 0))
	var better: bool = not (old is Dictionary) or old.is_empty() or s > int(old.get("score", -1))
	if better:
		c.set_value("best", k, e)
	_played(c, day)
	c.save(path)
	return better


## This computer's best of `day` ({} when none): practice=false → scored runs only.
static func best(day: String, who: String, practice: bool = false, path: String = FILE) -> Dictionary:
	var v = _load(path).get_value("best", "%s|%s|%s" % [day, who.to_lower(), "practice" if practice else "scored"], {})
	return v if v is Dictionary else {}


## {streak, best} of days played on this computer, as of `today`.
static func streak(today: String, path: String = FILE) -> Dictionary:
	var c := _load(path)
	return {"streak": DailyChallenge.streak_now(String(c.get_value("streak", "last", "")), int(c.get_value("streak", "n", 0)), today),
		"best": int(c.get_value("streak", "best", 0))}


static func _played(c: ConfigFile, day: String) -> void:
	var nx: Array = DailyChallenge.streak_after(String(c.get_value("streak", "last", "")), int(c.get_value("streak", "n", 0)), day)
	c.set_value("streak", "last", nx[0])
	c.set_value("streak", "n", nx[1])
	c.set_value("streak", "best", maxi(int(c.get_value("streak", "best", 0)), int(nx[1])))


static func _prune(c: ConfigFile, today: String) -> void:
	var oldest := today
	for i in KEEP_DAYS:
		oldest = DailyChallenge.prev_day(oldest)
	for sec in ["used", "best", "seed", "practice"]:
		if not c.has_section(sec):
			continue
		for k in c.get_section_keys(sec):
			var day := k.get_slice("|", 0)
			if DailyChallenge.valid_day(day) and day < oldest:
				c.erase_section_key(sec, k)


# --- The seed blocks found (DailySeed) ---------------------------------------------

static func cached_seed(day: String, path: String = FILE) -> Dictionary:
	var v = _load(path).get_value("seed", day, {})
	if not (v is Dictionary) or not DailyChallenge.valid_hash(String(v.get("hash", ""))):
		return {}
	return v


static func cache_seed(day: String, r: Dictionary, path: String = FILE) -> void:
	var c := _load(path)
	c.set_value("seed", day, {"block": int(r.get("block", 0)), "hash": String(r.get("hash", "")), "timestamp": int(r.get("timestamp", 0))})
	_prune(c, day)
	c.save(path)


## The practice counter (each practice run gets a new seed).
static func next_practice(day: String, path: String = FILE) -> int:
	var c := _load(path)
	var n := int(c.get_value("practice", day, 0)) + 1
	c.set_value("practice", day, n)
	c.save(path)
	return n
