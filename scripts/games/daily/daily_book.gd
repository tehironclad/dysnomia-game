class_name DailyBook
extends RefCounted
## The game server's record of the daily challenge (who started which scored attempt, who
## submitted which, everyone's streak). Pure state with the clock passed in, so tests drive it
## directly; GameServer's DailyServer keeps one and saves it as JSON.
##
## An attempt is spent when it STARTS (C_DAILY_START), not when a score comes in, so a player
## can't play many runs and send only the best. Each started attempt takes at most one score.
## Days older than KEEP_DAYS are forgotten (prune).

const KEEP_DAYS := 3

var days := {}      ## day → {wallet → {started: int, at: [unix of each start], submitted: [attempt n…], best: int}}
var streaks := {}   ## wallet → {last: day, streak: int, best: int}
var dirty := false


func _rec(day: String, wallet: String) -> Dictionary:
	var d: Dictionary = days.get(day, {})
	if not days.has(day):
		days[day] = d
	var r: Dictionary = d.get(wallet, {})
	if not d.has(wallet):
		r = {"started": 0, "at": [], "submitted": [], "best": -1}
		d[wallet] = r
	return r


## How many scored attempts `wallet` has started on `day`.
func used(day: String, wallet: String) -> int:
	return int((days.get(day, {}) as Dictionary).get(wallet, {}).get("started", 0))


## Spends one attempt: {ok, attempt (1-based), left} or {ok: false, error}. Counts the day
## toward the streak (playing is what keeps it).
func start_attempt(day: String, wallet: String, now_unix: int = 0) -> Dictionary:
	if not DailyChallenge.valid_day(day) or NetProto.clean_wallet(wallet) == "":
		return {"ok": false, "error": "bad day or wallet"}
	var r := _rec(day, wallet)
	if int(r["started"]) >= DailyChallenge.ATTEMPTS:
		return {"ok": false, "error": "no scored attempts left today (%d a day; practice is unlimited)" % DailyChallenge.ATTEMPTS, "left": 0}
	r["started"] = int(r["started"]) + 1
	if not (r.get("at") is Array):
		r["at"] = []
	(r["at"] as Array).append(now_unix)
	_played(day, wallet)
	dirty = true
	return {"ok": true, "attempt": int(r["started"]), "left": DailyChallenge.ATTEMPTS - int(r["started"])}


## "" when attempt `n` of `wallet` on `day` may take a score now, else why not. `play_s`: how
## long the run took to play (its steps / 60); a run can't arrive sooner than that after its start.
func can_submit(day: String, wallet: String, n: int, play_s: float = 0.0, now_unix: int = 0) -> String:
	var r: Dictionary = (days.get(day, {}) as Dictionary).get(wallet, {})
	if r.is_empty() or n < 1 or n > int(r.get("started", 0)):
		return "that attempt was never started"
	if (r.get("submitted", []) as Array).has(n):
		return "that attempt already has its score"
	var at: Array = r.get("at", []) if r.get("at") is Array else []
	if play_s > 0.0 and n <= at.size() and float(now_unix - int(at[n - 1])) < play_s:
		return "that run is longer than the time since its attempt started"
	return ""


func mark_submitted(day: String, wallet: String, n: int, score: int) -> void:
	var r := _rec(day, wallet)
	(r["submitted"] as Array).append(n)
	r["best"] = maxi(int(r.get("best", -1)), score)
	dirty = true


func _played(day: String, wallet: String) -> void:
	var s: Dictionary = streaks.get(wallet, {"last": "", "streak": 0, "best": 0})
	var nx: Array = DailyChallenge.streak_after(String(s.get("last", "")), int(s.get("streak", 0)), day)
	s["last"] = nx[0]
	s["streak"] = nx[1]
	s["best"] = maxi(int(s.get("best", 0)), int(nx[1]))
	streaks[wallet] = s


## The wallet's streak as it stands on `today` ({streak, best}).
func streak_of(wallet: String, today: String) -> Dictionary:
	var s: Dictionary = streaks.get(wallet, {})
	return {"streak": DailyChallenge.streak_now(String(s.get("last", "")), int(s.get("streak", 0)), today), "best": int(s.get("best", 0))}


## Forgets days older than KEEP_DAYS before `today`. Returns the days dropped.
func prune(today: String) -> Array:
	var keep := {}
	var d := today
	for i in KEEP_DAYS:
		keep[d] = true
		d = DailyChallenge.prev_day(d)
	var dropped: Array = []
	for k in days.keys():
		if not keep.has(k):
			days.erase(k)
			dropped.append(k)
	if not dropped.is_empty():
		dirty = true
	return dropped


func to_dict() -> Dictionary:
	return {"v": 1, "days": days, "streaks": streaks}


func from_dict(j) -> void:
	days = {}
	streaks = {}
	if not (j is Dictionary):
		return
	var dd = j.get("days", {})
	if dd is Dictionary:
		for day in dd:
			if not DailyChallenge.valid_day(String(day)) or not (dd[day] is Dictionary):
				continue
			var out := {}
			for w in dd[day]:
				var r = dd[day][w]
				if NetProto.clean_wallet(String(w)) == "" or not (r is Dictionary):
					continue
				var ats: Array = []
				for t in (r.get("at", []) if r.get("at") is Array else []):
					ats.append(NetProto.int_of(t))
				var subs: Array = []
				for n in (r.get("submitted", []) if r.get("submitted") is Array else []):
					subs.append(NetProto.int_of(n))
				out[String(w)] = {"started": clampi(NetProto.int_of(r.get("started", 0)), 0, DailyChallenge.ATTEMPTS),
					"at": ats, "submitted": subs, "best": NetProto.int_of(r.get("best", -1), -1)}
			days[String(day)] = out
	var ss = j.get("streaks", {})
	if ss is Dictionary:
		for w in ss:
			var s = ss[w]
			if NetProto.clean_wallet(String(w)) != "" and s is Dictionary:
				streaks[String(w)] = {"last": NetProto.str_of(s.get("last", "")), "streak": maxi(0, NetProto.int_of(s.get("streak", 0))),
					"best": maxi(0, NetProto.int_of(s.get("best", 0)))}
