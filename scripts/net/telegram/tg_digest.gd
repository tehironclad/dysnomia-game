class_name TgDigest
extends RefCounted
## The batch of game moments the bridge posts to Telegram: real server events
## (NetTg.MOMENT_KINDS) wait here and go as ONE bot message at most every
## MIN_GAP_S. The first moment waits GATHER_S for others to join it (a result and
## its record come together). A player's comings and goings (arrive, place) go at
## most once per REPEAT_S each; any other line once per DEDUPE_S. Old moments
## (STALE_S) are dropped: the group gets news, not a backlog. Time is passed in. Pure.

const MIN_GAP_S := 120.0
const GATHER_S := 15.0
const MAX_LINES := 6
const MAX_QUEUE := 40
const STALE_S := 1800.0
const REPEAT_S := 3 * 3600.0
const DEDUPE_S := 600.0

var events: Array = []      # [{ev, at}]
var last_post := -1.0e9
## The gap and the gather wait (tools/tg_selftest.gd shortens them; the server keeps the consts).
var min_gap_s := MIN_GAP_S
var gather_s := GATHER_S
var _seen := {}             # key → time it was queued


## Pure: the key a repeat is judged by.
static func key_of(ev: Dictionary) -> String:
	var k := String(ev.get("k", ""))
	var room := String(ev.get("room", "")).get_slice("/", 0)
	if k == "arrive":
		return "arrive|%s" % ev.get("w", "")
	if k == "place":
		return "place|%s|%s|%s" % [ev.get("w", ""), ev.get("place", ""), room]
	return "%s|%s|%s|%s|%s|%s|%s" % [k, ev.get("w", ""), ev.get("w2", ""), room, ev.get("game", ""), ev.get("board", ""), ev.get("score", "")]


## Queues a moment. False when it repeats one too soon or the queue is full.
func add(ev: Dictionary, now: float) -> bool:
	prune(now)
	var key := key_of(ev)
	var k := String(ev.get("k", ""))
	var gap := REPEAT_S if k in ["arrive", "place"] else DEDUPE_S
	if _seen.has(key) and now - float(_seen[key]) < gap:
		return false
	if events.size() >= MAX_QUEUE:
		return false
	_seen[key] = now
	events.append({"ev": ev, "at": now})
	return true


## Is a post due now?
func due(now: float) -> bool:
	if events.is_empty() or now - last_post < min_gap_s:
		return false
	return now - float(events[0]["at"]) >= gather_s


## Takes up to MAX_LINES moments for one post (the rest wait for the next) and
## starts the gap. Results and records first: they are the news.
func take(now: float) -> Array:
	prune(now)
	if events.is_empty():
		return []
	var order := {"result": 0, "daily_record": 1, "record": 2, "join": 3, "place": 4, "arrive": 5}
	var idx: Array = range(events.size())
	idx.sort_custom(func(a, b):
		var ka := int(order.get(String(events[a]["ev"].get("k", "")), 9))
		var kb := int(order.get(String(events[b]["ev"].get("k", "")), 9))
		return ka < kb if ka != kb else a < b)
	var pick: Array = idx.slice(0, MAX_LINES)
	var out: Array = []
	for i in pick:
		out.append(events[i]["ev"])
	pick.sort()
	for i in range(pick.size() - 1, -1, -1):
		events.remove_at(pick[i])
	last_post = now
	return out


## Drops stale moments and forgets old repeat keys.
func prune(now: float) -> void:
	while not events.is_empty() and now - float(events[0]["at"]) > STALE_S:
		events.pop_front()
	if _seen.size() > 500:
		for key in _seen.keys():
			if now - float(_seen[key]) > REPEAT_S:
				_seen.erase(key)
