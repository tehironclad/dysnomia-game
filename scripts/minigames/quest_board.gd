class_name QuestBoard
extends RefCounted
## Daily QING quests, the visit streak and unlockable titles.
##
## Every QING posts its own board each UTC day. The board is deterministic from
## (QING, UTC date, fair tier): two bears standing in the same QING on the same day see
## the same quests. Once a board is first opened for the day it is locked, so a Standing
## change at 15:00 doesn't reshuffle anyone's half-done quests.
##
## Rewards are cosmetic: titles, a streak and bragging rights. Nothing here mints, pays
## or claims anything on chain. Rides and drinks are the visitor's own on-chain choices;
## quests only count them once the game reports they happened.
##
## Feed it from anywhere:
##   QuestBoard.report("ride", {"id": "rocket"})
##   QuestBoard.report("drink", {"id": "rho_rocks"})
##   QuestBoard.report("chat", {"text": "gm"})
## Supported events and their data keys are listed in EVENTS.
##
## Listen:  QuestBoard.bus.changed / quest_completed(quest) / title_unlocked(title) / streak_changed(n)

class Bus extends RefCounted:
	signal changed
	signal quest_completed(quest: Dictionary)
	signal title_unlocked(title: Dictionary)
	signal streak_changed(streak: int)

const VERSION := 1
const QUESTS_PER_DAY := 4
const KEEP_DAYS := 4

## event → data keys it understands (all optional unless noted)
## Older / alternative spellings accepted by report()
const ALIASES := {"rocket_watch": "rocket_watched", "board_posted": "board_post", "ride_boarded": "ride",
	"drink_served": "drink", "invite": "invite_sent", "chat_sent": "chat"}

const EVENTS := {
	"ride": "id: rocket | wheel | drop | carousel",
	"drink": "id: AttractionCatalog drink id (pi_shot, rho_rocks, generator_lager, alpha_sour, beta_blocker, upsilon_fizz, house_round)",
	"minigame_played": "game: entropy_dice | waat_slots | territory_trivia | card_match, score",
	"minigame_win": "game, score",
	"minigame_score": "game, score, jackpot (bool), perfect (bool)",
	"visit_qing": "qing (address, required), name",
	"chat": "text",
	"rocket_watched": "(none) — a rocket launch was watched from the ground",
	"terraform": "op: pi | rho | generate | alpha | beta | upsilon (the player's own confirmed call)",
	"beat": "(none) — the player's META.Beat confirmed",
	"board_post": "wing, caption — a community media board / guestbook post",
	"invite_sent": "(none) — shared this QING's Telegram invite",
	"emote": "id",
	"photo": "(none) — photo mode capture",
}

## Quest templates. cat: fair / cantina / social / explore.
## t: [min, max] target, f: filter conditions, d: count distinct values of this data key,
## g: progress comes from a day-wide counter instead of this QING's board.
const TEMPLATES := [
	{"id": "ride_any", "cat": "fair", "ev": "ride", "t": [2, 3], "tier": 1,
		"text": "Ride %d attractions at the fair", "where": "Affection Fair"},
	{"id": "ride_carousel", "cat": "fair", "ev": "ride", "t": [1, 1], "tier": 1, "f": {"id": "carousel"},
		"text": "Take a spin on the Orbital Carousel", "where": "Affection Fair"},
	{"id": "ride_wheel", "cat": "fair", "ev": "ride", "t": [1, 1], "tier": 2, "f": {"id": "wheel"},
		"text": "Orbit the fairground on the Rho Wheel", "where": "Affection Fair"},
	{"id": "ride_drop", "cat": "fair", "ev": "ride", "t": [1, 1], "tier": 2, "f": {"id": "drop"},
		"text": "Survive the Pi Drop Tower", "where": "Affection Fair"},
	{"id": "ride_rocket", "cat": "fair", "ev": "ride", "t": [1, 1], "tier": 3, "f": {"id": "rocket"},
		"text": "Strap into the Upsilon Rocket", "where": "Affection Fair"},
	{"id": "rocket_watch", "cat": "fair", "ev": "rocket_watched", "t": [1, 1], "tier": 3,
		"text": "Watch a rocket launch from the bleachers", "where": "Rocket pad"},
	{"id": "drink_rho", "cat": "cantina", "ev": "drink", "t": [1, 1], "f": {"id": "rho_rocks"},
		"text": "Order a Rho on the Rocks", "where": "Cantina bar"},
	{"id": "drink_pi", "cat": "cantina", "ev": "drink", "t": [1, 1], "f": {"id": "pi_shot"},
		"text": "Knock back a Pi Shot", "where": "Cantina bar"},
	{"id": "drink_upsilon", "cat": "cantina", "ev": "drink", "t": [1, 1], "f": {"id": "upsilon_fizz"},
		"text": "Try the Upsilon Fizz (twist of phi)", "where": "Cantina bar"},
	{"id": "drink_lager", "cat": "cantina", "ev": "drink", "t": [1, 1], "f": {"id": "generator_lager"},
		"text": "Pour a Generator Lager", "where": "Cantina bar"},
	{"id": "dice_win", "cat": "cantina", "ev": "minigame_win", "t": [1, 2], "f": {"game": "entropy_dice"},
		"text": "Beat the house line at Entropy Dice %d×", "where": "Cantina table 1"},
	{"id": "slots_score", "cat": "cantina", "ev": "minigame_score", "t": [1, 1],
		"f": {"game": "waat_slots", "score>=": 150},
		"text": "Cash out 150+ SAAT at WAAT Slots", "where": "Cantina table 2"},
	{"id": "trivia_win", "cat": "cantina", "ev": "minigame_win", "t": [1, 1], "f": {"game": "territory_trivia"},
		"text": "Pass Territory Trivia (6/10 or better)", "where": "Cantina table 3"},
	{"id": "card_win", "cat": "cantina", "ev": "minigame_win", "t": [1, 1], "f": {"game": "card_match"},
		"text": "Clear two rounds of Contract Match", "where": "Cantina table 4"},
	{"id": "play_variety", "cat": "cantina", "ev": "minigame_played", "t": [2, 3], "d": "game",
		"text": "Play %d different Cantina games", "where": "Cantina tables"},
	{"id": "say_gm", "cat": "social", "ev": "chat", "t": [1, 1], "f": {"text~": "gm"},
		"text": "Say gm in this QING's chat", "where": "Chat (Enter)"},
	{"id": "chat_n", "cat": "social", "ev": "chat", "t": [3, 5],
		"text": "Send %d messages in this QING's chat", "where": "Chat (Enter)"},
	{"id": "emote_n", "cat": "social", "ev": "emote", "t": [2, 4],
		"text": "Emote at other bears %d×", "where": "Hold Q"},
	{"id": "board_post", "cat": "social", "ev": "board_post", "t": [1, 1],
		"text": "Pin a post on this QING's media board", "where": "Media boards / Guestbook (B)"},
	{"id": "invite", "cat": "social", "ev": "invite_sent", "t": [1, 1],
		"text": "Invite a friend to this QING", "where": "Telegram invite (K)"},
	{"id": "visit_qings", "cat": "explore", "ev": "visit_qing", "t": [2, 3], "d": "qing", "g": true,
		"text": "Visit %d QINGs today", "where": "World map (M) / shuttle"},
	{"id": "terraform", "cat": "explore", "ev": "terraform", "t": [1, 1],
		"text": "Terraform here at the Monument", "where": "Monument (T)"},
	{"id": "beat", "cat": "explore", "ev": "beat", "t": [1, 1],
		"text": "Beat the Resonance Array", "where": "Meta Resonance Array"},
	{"id": "photo", "cat": "explore", "ev": "photo", "t": [1, 1],
		"text": "Snap a postcard of this QING", "where": "Photo mode (F6)"},
]

## Cosmetic titles. stat is a key in totals, or "best_streak".
const TITLES := [
	{"id": "fresh_regolith", "name": "Fresh Regolith", "stat": "", "need": 0, "desc": "Every bear starts here."},
	{"id": "gm_bear", "name": "gm Bear", "stat": "gm", "need": 7, "desc": "Said gm on 7 occasions."},
	{"id": "moonwalker", "name": "Moonwalker", "stat": "best_streak", "need": 3, "desc": "3-day quest streak."},
	{"id": "lunar_local", "name": "Lunar Local", "stat": "best_streak", "need": 7, "desc": "7-day quest streak."},
	{"id": "eris_devotee", "name": "Eris Devotee", "stat": "best_streak", "need": 30, "desc": "30-day quest streak."},
	{"id": "cantina_regular", "name": "Cantina Regular", "stat": "quests_completed", "need": 10, "desc": "10 quests done."},
	{"id": "questkeeper", "name": "Questkeeper", "stat": "quests_completed", "need": 50, "desc": "50 quests done."},
	{"id": "full_board", "name": "Full Board", "stat": "full_boards", "need": 5, "desc": "Cleared a whole QING board 5 times."},
	{"id": "qing_hopper", "name": "QING Hopper", "stat": "qings_visited", "need": 10, "desc": "Visited 10 different QINGs."},
	{"id": "entropy_whisperer", "name": "Entropy Whisperer", "stat": "dice_wins", "need": 25, "desc": "25 Entropy Dice wins."},
	{"id": "motzkin_touched", "name": "Motzkin-Touched", "stat": "slots_jackpots", "need": 1, "desc": "Hit the Motzkin jackpot."},
	{"id": "sage_of_eris", "name": "Sage of Eris", "stat": "trivia_perfect", "need": 1, "desc": "10/10 at Territory Trivia."},
	{"id": "contract_shark", "name": "Contract Shark", "stat": "card_wins", "need": 10, "desc": "10 Contract Match wins."},
	{"id": "rocket_witness", "name": "Rocket Witness", "stat": "rocket_watched", "need": 3, "desc": "Watched 3 launches."},
	{"id": "herald", "name": "Herald of Eris", "stat": "invites", "need": 5, "desc": "Shared 5 QING invites."},
	{"id": "fair_regular", "name": "Fair Regular", "stat": "rides", "need": 20, "desc": "20 rides."},
]

static var save_path: String = "user://quest_board.json"
static var now_override: int = -1          # tests: freeze the clock (unix seconds)
static var tier: int = 1                   # current QING's fair tier (installer keeps this fresh)
static var autosave: bool = true
static var bus: Bus = Bus.new()
static var _data: Dictionary = {}
static var _loaded: bool = false
static var _gm_re: RegEx


# ─── Time ───────────────────────────────────────────────────────────────

static func now() -> int:
	return now_override if now_override >= 0 else int(Time.get_unix_time_from_system())


static func utc_date(unix: int = -1) -> String:
	if unix < 0:
		unix = now()
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func day_number(date: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(date + "T00:00:00")) / 86400


static func seconds_until_reset(unix: int = -1) -> int:
	if unix < 0:
		unix = now()
	return 86400 - (unix % 86400)


static func reset_countdown() -> String:
	var s := seconds_until_reset()
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]


# ─── Deterministic generation ──────────────────────────────────────────

static func seed_for(qing_key: String, date: String) -> int:
	var b := ("dysnomia-quests|%s|%s" % [qing_key.to_lower(), date]).sha256_buffer()
	return b.decode_s64(0)


static func generate(qing_key: String, date: String, fair_tier: int) -> Array:
	## The day's board for a QING. Pure: same inputs → same quests.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(qing_key, date)
	var by_cat := {"fair": [], "cantina": [], "social": [], "explore": []}
	for t in TEMPLATES:
		if int(t.get("tier", 0)) <= fair_tier:
			by_cat[t["cat"]].append(t)
	var order := ["fair", "cantina", "social", "explore"]
	if by_cat["fair"].is_empty():
		order = ["cantina", "social", "explore", "cantina"]
	var picked: Array = []
	var used := {}
	for cat in order:
		var pool: Array = by_cat[cat].filter(func(x): return not used.has(x["id"]))
		if pool.is_empty():
			continue
		var t: Dictionary = pool[rng.randi() % pool.size()]
		used[t["id"]] = true
		picked.append(_instantiate(t, rng))
		if picked.size() >= QUESTS_PER_DAY:
			break
	return picked


static func _instantiate(t: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var lo: int = t["t"][0]
	var hi: int = t["t"][1]
	var target := rng.randi_range(lo, hi)
	var text: String = t["text"]
	if text.contains("%d"):
		text = text % target
	return {"id": t["id"], "cat": t["cat"], "event": t["ev"], "target": target, "text": text,
		"where": t.get("where", ""), "filter": t.get("f", {}), "distinct": t.get("d", ""),
		"global": t.get("g", false)}


# ─── Board state ────────────────────────────────────────────────────────

static func board(qing_key: String = "", date: String = "") -> Dictionary:
	## Today's board for a QING: {date, qing, quests: [quest + progress/done]}. Creates and locks it.
	_ensure()
	if qing_key.is_empty():
		qing_key = DysnomiaLore.qing_key()
	if date.is_empty():
		date = utc_date()
	var day := _day(date)
	if not day.has(qing_key):
		var qs := generate(qing_key, date, tier)
		var progress := []
		var seen := []
		var done := []
		for _q in qs:
			progress.append(0)
			seen.append([])
			done.append(false)
		day[qing_key] = {"tier": tier, "quests": qs, "progress": progress, "seen": seen, "done": done}
		_prune()
		_save()
	var b: Dictionary = day[qing_key]
	var out := []
	var g: Dictionary = day["_global"]
	for i in b["quests"].size():
		var q: Dictionary = b["quests"][i].duplicate()
		var p: int = int(b["progress"][i])
		if q.get("global", false) and q["event"] == "visit_qing":
			p = g["visited"].size()
		q["progress"] = mini(p, int(q["target"]))
		q["done"] = bool(b["done"][i])
		out.append(q)
	return {"date": date, "qing": qing_key, "tier": int(b.get("tier", tier)), "quests": out}


static func report(event: String, data: Dictionary = {}) -> Array:
	## Feed a game event. Returns the quests it completed (usually empty).
	_ensure()
	event = ALIASES.get(event, event)
	if not EVENTS.has(event):
		push_warning("[QuestBoard] unknown event '%s'" % event)
		return []
	var date := utc_date()
	var qing_key: String = str(data.get("at_qing", "")) if data.has("at_qing") else DysnomiaLore.qing_key()
	_count_totals(event, data)
	var day := _day(date)
	if event == "visit_qing":
		var q := str(data.get("qing", "")).to_lower()
		if not q.is_empty() and not day["_global"]["visited"].has(q):
			day["_global"]["visited"].append(q)
	board(qing_key, date)  # make sure it exists
	var b: Dictionary = day[qing_key]
	var completed := []
	for i in b["quests"].size():
		if b["done"][i]:
			continue
		var q: Dictionary = b["quests"][i]
		if q["event"] != event or not _matches(q.get("filter", {}), data):
			continue
		if q.get("global", false) and event == "visit_qing":
			b["progress"][i] = day["_global"]["visited"].size()
		elif str(q.get("distinct", "")) != "":
			var v := str(data.get(q["distinct"], ""))
			if v.is_empty() or b["seen"][i].has(v):
				continue
			b["seen"][i].append(v)
			b["progress"][i] = b["seen"][i].size()
		else:
			b["progress"][i] = int(b["progress"][i]) + maxi(1, int(data.get("count", 1)))
		if int(b["progress"][i]) >= int(q["target"]):
			b["done"][i] = true
			completed.append(q)
	if not completed.is_empty():
		var t: Dictionary = _data["totals"]
		t["quests_completed"] = int(t.get("quests_completed", 0)) + completed.size()
		if not b["done"].has(false):
			t["full_boards"] = int(t.get("full_boards", 0)) + 1
		_touch_streak(date)
	var new_titles := _check_titles()
	_data["updated_at"] = now()
	_save()
	for q in completed:
		bus.quest_completed.emit(q)
	for tt in new_titles:
		bus.title_unlocked.emit(tt)
	bus.changed.emit()
	return completed


static func _matches(filter: Dictionary, data: Dictionary) -> bool:
	for k in filter:
		var want = filter[k]
		if k.ends_with(">="):
			if float(data.get(k.trim_suffix(">="), 0)) < float(want):
				return false
		elif k.ends_with("~"):
			if not _has_word(str(data.get(k.trim_suffix("~"), "")), str(want)):
				return false
		elif str(data.get(k, "")) != str(want):
			return false
	return true


static func _has_word(text: String, word: String) -> bool:
	if word == "gm":
		if _gm_re == null:
			_gm_re = RegEx.create_from_string("(?i)(^|[^a-z])g+m+([^a-z]|$)")
		return _gm_re.search(text) != null
	return (" " + text.to_lower() + " ").contains(" " + word.to_lower() + " ")


static func _count_totals(event: String, data: Dictionary) -> void:
	var t: Dictionary = _data["totals"]
	var bump := func(k: String) -> void: t[k] = int(t.get(k, 0)) + 1
	bump.call("ev_" + event)
	match event:
		"ride": bump.call("rides")
		"rocket_watched": bump.call("rocket_watched")
		"invite_sent": bump.call("invites")
		"chat":
			if _has_word(str(data.get("text", "")), "gm"):
				bump.call("gm")
		"visit_qing":
			var q := str(data.get("qing", "")).to_lower()
			if not q.is_empty() and not _data["visited_ever"].has(q):
				_data["visited_ever"][q] = now()
			t["qings_visited"] = _data["visited_ever"].size()
		"minigame_win":
			match str(data.get("game", "")):
				"entropy_dice": bump.call("dice_wins")
				"card_match": bump.call("card_wins")
				"territory_trivia": bump.call("trivia_wins")
				"waat_slots": bump.call("slots_wins")
		"minigame_score":
			if data.get("jackpot", false):
				bump.call("slots_jackpots")
			if data.get("perfect", false):
				bump.call("trivia_perfect")


# ─── Streak ─────────────────────────────────────────────────────────────

static func _touch_streak(date: String) -> void:
	## Called when a quest completes on `date`. Consecutive UTC days keep the streak alive.
	var s: Dictionary = _data["streak"]
	var last: String = s.get("last_day", "")
	if last == date:
		return
	if not last.is_empty() and day_number(last) == day_number(date) - 1:
		s["current"] = int(s.get("current", 0)) + 1
	else:
		s["current"] = 1
	s["last_day"] = date
	s["best"] = maxi(int(s.get("best", 0)), int(s["current"]))
	bus.streak_changed.emit(int(s["current"]))


static func streak() -> Dictionary:
	## {current, best, last_day, done_today, at_risk}. current reads 0 once a day is missed.
	_ensure()
	var s: Dictionary = _data["streak"]
	var today := utc_date()
	var last: String = s.get("last_day", "")
	var cur := int(s.get("current", 0))
	var alive := not last.is_empty() and day_number(today) - day_number(last) <= 1
	return {"current": cur if alive else 0, "best": int(s.get("best", 0)), "last_day": last,
		"done_today": last == today, "at_risk": alive and last != today and cur > 0}


# ─── Titles ─────────────────────────────────────────────────────────────

static func _stat(key: String) -> int:
	if key.is_empty():
		return 0
	if key == "best_streak":
		return int(_data["streak"].get("best", 0))
	return int(_data["totals"].get(key, 0))


static func _check_titles() -> Array:
	var unlocked: Dictionary = _data["titles"]["unlocked"]
	var fresh := []
	for t in TITLES:
		if unlocked.has(t["id"]):
			continue
		if _stat(t["stat"]) >= int(t["need"]):
			unlocked[t["id"]] = now()
			if int(t["need"]) > 0:   # the starter title isn't news
				fresh.append(t)
	return fresh


static func titles() -> Array:
	## All titles with {unlocked, progress, need}. Locked ones show how close you are.
	_ensure()
	_check_titles()
	var out := []
	for t in TITLES:
		var e: Dictionary = t.duplicate()
		e["unlocked"] = _data["titles"]["unlocked"].has(t["id"])
		e["progress"] = mini(_stat(t["stat"]), int(t["need"]))
		out.append(e)
	return out


static func selected_title() -> String:
	_ensure()
	var id: String = _data["titles"].get("selected", "")
	if id.is_empty() or not _data["titles"]["unlocked"].has(id):
		# Highest unlocked by default
		var best := "Fresh Regolith"
		for t in TITLES:
			if _data["titles"]["unlocked"].has(t["id"]):
				best = t["name"]
		return best
	for t in TITLES:
		if t["id"] == id:
			return t["name"]
	return "Fresh Regolith"


static func select_title(id: String) -> bool:
	_ensure()
	if not _data["titles"]["unlocked"].has(id):
		return false
	_data["titles"]["selected"] = id
	_save()
	bus.changed.emit()
	return true


static func totals() -> Dictionary:
	_ensure()
	return _data["totals"].duplicate()


static func export_state() -> Dictionary:
	## The whole save, for a server to sync later.
	_ensure()
	return _data.duplicate(true)


# ─── Persistence ───────────────────────────────────────────────────────

static func reset(path: String = "") -> void:
	## Tests: fresh state (optionally at another path).
	if not path.is_empty():
		save_path = path
	_data = _empty()
	_loaded = true


static func _empty() -> Dictionary:
	return {"version": VERSION, "updated_at": 0,
		"streak": {"current": 0, "best": 0, "last_day": ""},
		"totals": {}, "visited_ever": {},
		"titles": {"unlocked": {}, "selected": ""},
		"days": {}}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _empty()
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary and int(d.get("version", 0)) == VERSION:
				for k in _data:
					if d.has(k) and typeof(d[k]) == typeof(_data[k]):
						_data[k] = d[k]
	_check_titles()


static func _day(date: String) -> Dictionary:
	var days: Dictionary = _data["days"]
	if not days.has(date):
		days[date] = {"_global": {"visited": []}}
	return days[date]


static func _prune() -> void:
	var days: Dictionary = _data["days"]
	var keys := days.keys()
	keys.sort()
	while keys.size() > KEEP_DAYS:
		days.erase(keys.pop_front())


static func _save() -> void:
	if not autosave:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "\t"))
