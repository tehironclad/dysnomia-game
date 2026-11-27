class_name AlertGate
extends RefCounted
## Alerts' pacing, pure (time is passed in): repeats of one kind in one place merge
## into the toast already showing ("3 new mentions in Qingston"), new toasts are
## rate-limited (held ones come out when there is room, merged too), and the sound
## and the taskbar flash have their own minimum gaps.
##
## An alert: {kind, group, place, who, text, ref, go}
##   kind  mention | invite | arrive | crown | game
##   group what merges: "mention|<qing>", "arrive|<qing>", "invite", "crown", "game"
## A toast: {id, kind, group, count, place, who, text, go, first, last, items: [alert]}

const KINDS := ["mention", "invite", "arrive", "crown"]  ## the kinds a player can switch off
const MERGE_S := 20.0         ## the same group again within this merges into one toast
const LIFE_S := 9.0           ## a toast shows this long after its last merge
const RATE := 0.25            ## new toasts a second (one every 4 s)…
const BURST := 3.0            ## …after a burst of 3
const SOUND_GAP_S := 3.0
const ATTENTION_GAP_S := 30.0
const HELD_MAX := 20

var toasts := {}      # group → toast (the live ones)
var held: Array = []  # alerts waiting for room (merged by group)
var _bucket := TokenBucket.new(RATE, BURST)
var _n := 0
var _sound_at := -1000.0
var _flash_at := -1000.0


## Takes an alert. {action: "merge" | "new" | "held", toast}.
func push(a: Dictionary, now: float) -> Dictionary:
	var group := String(a.get("group", a.get("kind", "")))
	var t: Dictionary = toasts.get(group, {})
	if not t.is_empty() and now - float(t["last"]) < MERGE_S:
		_merge(t, a, now)
		return {"action": "merge", "toast": t}
	for h in held:
		if String(h["group"]) == group:
			_merge(h, a, now)
			return {"action": "held", "toast": h}
	var nt := _toast(a, now)
	if _bucket.take(now):
		_n += 1
		nt["id"] = _n
		toasts[group] = nt
		return {"action": "new", "toast": nt}
	if held.size() < HELD_MAX:
		held.append(nt)
	return {"action": "held", "toast": nt}


## Held toasts that may show now (oldest first), and expired ones dropped.
func release(now: float) -> Array:
	for k in toasts.keys():
		if now - float(toasts[k]["last"]) > LIFE_S:
			toasts.erase(k)
	var out: Array = []
	while not held.is_empty() and _bucket.take(now):
		var t: Dictionary = held.pop_front()
		_n += 1
		t["id"] = _n
		t["last"] = now
		toasts[String(t["group"])] = t
		out.append(t)
	return out


func sound_ok(now: float) -> bool:
	if now - _sound_at < SOUND_GAP_S:
		return false
	_sound_at = now
	return true


func attention_ok(now: float) -> bool:
	if now - _flash_at < ATTENTION_GAP_S:
		return false
	_flash_at = now
	return true


func _toast(a: Dictionary, now: float) -> Dictionary:
	return {"id": 0, "kind": String(a.get("kind", "")), "group": String(a.get("group", a.get("kind", ""))), "count": 1,
		"place": String(a.get("place", "")), "who": String(a.get("who", "")), "text": String(a.get("text", "")),
		"go": a.get("go", {}), "first": now, "last": now, "items": [a]}


func _merge(t: Dictionary, a: Dictionary, now: float) -> void:
	t["count"] = int(t["count"]) + 1
	t["who"] = String(a.get("who", t["who"]))
	t["text"] = String(a.get("text", t["text"]))
	t["go"] = a.get("go", t["go"])
	t["last"] = now
	var items: Array = t["items"]
	items.append(a)
	if items.size() > 10:
		items.pop_front()


## The toast's words: one alert says itself; repeats say how many and the latest.
static func text_of(t: Dictionary) -> String:
	var n := int(t.get("count", 1))
	var place := String(t.get("place", ""))
	var who := String(t.get("who", ""))
	var text := String(t.get("text", ""))
	match String(t.get("kind", "")):
		"mention":
			if n == 1:
				return "%s named you in %s: “%s”" % [who, place, text]
			return "%d new mentions in %s · latest %s: “%s”" % [n, place, who, text]
		"arrive":
			if n == 1:
				return "%s arrived in %s" % [who, place]
			return "%d arrivals in %s · latest %s" % [n, place, who]
		"invite":
			return text if n == 1 else "%d invites and join requests · latest: %s" % [n, text]
		"crown":
			if n == 1:
				return text
			return "Leads lost at %d QINGs · latest: %s" % [n, text]
	return text if n == 1 else "%s (+%d more)" % [text, n - 1]


## The small caps over a toast.
static func title_of(kind: String) -> String:
	match kind:
		"mention": return "MENTION"
		"invite": return "INVITE"
		"arrive": return "ARRIVAL"
		"crown": return "CROWN"
	return "GAME"
