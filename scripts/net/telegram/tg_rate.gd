class_name TgRate
extends RefCounted
## Sliding-window limits for the Telegram bridge: each rule is [count, window_s]
## ("at most count in any window_s seconds"). Time is passed in (seconds), so the
## tests drive it. Pure.
##   per wallet:  TgRate.new([[1, 10.0], [30, 3600.0]])   one line every 10 s, 30 an hour
##   the group:   TgRate.new([[18, 60.0], [1, 1.0]])     under Telegram's ~20 a minute per group

var rules: Array = []
var _hits := {}  # key → Array[float] (times, oldest first)


func _init(p_rules: Array = []) -> void:
	rules = p_rules


## Seconds until `key` may go again (0.0 = now).
func wait_s(key: String, now: float) -> float:
	var hits: Array = _hits.get(key, [])
	var wait := 0.0
	for r in rules:
		var n := int(r[0])
		var win := float(r[1])
		var inside := 0
		for t in hits:
			if now - float(t) < win:
				inside += 1
		if inside >= n:
			# the oldest hit inside the window that must leave before one more fits
			var times: Array = hits.filter(func(t): return now - float(t) < win)
			wait = maxf(wait, float(times[inside - n]) + win - now)
	return maxf(0.0, wait)


## Records one at `now`.
func note(key: String, now: float) -> void:
	var hits: Array = _hits.get(key, [])
	hits.append(now)
	var longest := 0.0
	for r in rules:
		longest = maxf(longest, float(r[1]))
	while not hits.is_empty() and now - float(hits[0]) >= longest:
		hits.pop_front()
	_hits[key] = hits


## wait_s, and note when it is 0. Returns the wait (0.0 = taken).
func take(key: String, now: float) -> float:
	var w := wait_s(key, now)
	if w <= 0.0:
		note(key, now)
	return w


## Forgets keys with nothing inside any window (housekeeping).
func prune(now: float) -> void:
	var longest := 0.0
	for r in rules:
		longest = maxf(longest, float(r[1]))
	for k in _hits.keys():
		var hits: Array = _hits[k]
		if hits.is_empty() or now - float(hits[-1]) >= longest:
			_hits.erase(k)


func size() -> int:
	return _hits.size()
