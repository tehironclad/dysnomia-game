class_name PlayerRecord
extends RefCounted
## A player's record, from the chain: every Su (and CHOA.Play) mints 1 of the
## player's own YUE to the YUE contract (Transfer 0x0 → YUE) and the YUE then
## sends it to the wallet (Transfer YUE → wallet). We count the latter.
## From those logs:
## - reactions: how many mints were found (a floor if the scan stopped early);
## - days: the DysnomiaTime days (115,600 s, from block timestamps) with at
##   least one reaction; the current streak of consecutive days, the best,
##   whether today is done and how long today has left.
## Timestamps are read exactly, but only where a day boundary can fall: a run
## of mints whose first and last block share a day is all that day.

const MAX_LOGS := 2000

var ok := false
var error := ""
var block := -1
var reactions := 0
var complete := true    # false = the scan stopped early (counts are floors)
var days: Array = []     # sorted distinct day numbers
var current := 0
var best := 0
var today := -1
var today_done := false
var seconds_left := -1


static func topic_of(addr: String) -> String:
	return "0x" + Abi.strip0x(addr).to_lower().lpad(64, "0")


## Pure: streaks from distinct days and today's number. The current streak
## counts back from today, or from yesterday if today has no reaction yet
## (it is still alive until today ends).
static func streaks(day_list: Array, today_n: int) -> Dictionary:
	var set := {}
	for d in day_list:
		set[int(d)] = true
	var best_run := 0
	var run := 0
	var prev := -10
	var sorted: Array = set.keys()
	sorted.sort()
	for d in sorted:
		run = run + 1 if d == prev + 1 else 1
		best_run = maxi(best_run, run)
		prev = d
	var start := today_n if set.has(today_n) else today_n - 1
	var cur := 0
	while set.has(start - cur):
		cur += 1
	return {"current": cur, "best": best_run, "today_done": set.has(today_n)}


static func read(wallet: String, yue: String) -> PlayerRecord:
	var r := PlayerRecord.new()
	var head := await Chain.refresh_head()
	if head < 0 or yue == "":
		r.error = "no YUE" if yue == "" else "chain head unavailable"
		return r
	r.block = head
	var topics := [Contracts.TOPIC_TRANSFER, topic_of(yue), topic_of(wallet)]
	var logs: Array = []
	var end := head
	while end >= Contracts.VOID_CHAT_FROM_BLOCK and logs.size() < MAX_LOGS:
		var start := maxi(Contracts.VOID_CHAT_FROM_BLOCK, end - 500000 + 1)
		var s: Dictionary = await Chain.logs.scan(yue, topics, start, end)
		logs = s["logs"] + logs
		if not s["ok"]:
			r.complete = false
			break
		end = start - 1
	var blocks := {}
	for l in logs:
		if String(l.get("address", "")).to_lower() == yue.to_lower():
			blocks[String(l.get("blockNumber", "0x0")).hex_to_int()] = true
	r.reactions = logs.size()
	var bl: Array = blocks.keys()
	bl.sort()
	var ts := {}
	var head_b := await Chain.rpc.get_block(head)
	if not head_b["ok"]:
		r.error = "head block unreadable"
		return r
	var now := String(head_b["result"]["timestamp"]).hex_to_int()
	var t := DysnomiaTime.from_unix(now)
	r.today = int(t["day"])
	r.seconds_left = DysnomiaTime.DAY_SECONDS - (now % DysnomiaTime.DAY_SECONDS)
	var day_of := {}
	if not bl.is_empty():
		await _assign(bl, 0, bl.size() - 1, ts, day_of)
	var ds := {}
	for b in bl:
		if day_of.has(b):
			ds[int(day_of[b])] = true
	r.days = ds.keys()
	r.days.sort()
	var st := streaks(r.days, r.today)
	r.current = st["current"]
	r.best = st["best"]
	r.today_done = st["today_done"]
	r.ok = true
	return r


static func _day(b: int, ts: Dictionary) -> int:
	if not ts.has(b):
		var g := await Chain.rpc.get_block(b)
		ts[b] = String(g["result"]["timestamp"]).hex_to_int() if g["ok"] and g["result"] is Dictionary else -1
	return -1 if ts[b] < 0 else int(ts[b] / DysnomiaTime.DAY_SECONDS)


## Days for bl[lo..hi]: if both ends share a day, everything between does too.
static func _assign(bl: Array, lo: int, hi: int, ts: Dictionary, out: Dictionary) -> void:
	var dlo := await _day(bl[lo], ts)
	var dhi := await _day(bl[hi], ts)
	if dlo == dhi and dlo >= 0:
		for i in range(lo, hi + 1):
			out[bl[i]] = dlo
		return
	if hi - lo <= 1:
		if dlo >= 0:
			out[bl[lo]] = dlo
		if dhi >= 0:
			out[bl[hi]] = dhi
		return
	var mid := (lo + hi) / 2
	await _assign(bl, lo, mid, ts, out)
	await _assign(bl, mid, hi, ts, out)


func describe() -> String:
	if not ok:
		return "Record: — (%s)" % error
	var left := "%dh %02dm left today" % [seconds_left / 3600, (seconds_left % 3600) / 60] if seconds_left >= 0 else ""
	return "Streak %d day%s (best %d) · today %s · %s%d reactions%s" % [current, "" if current == 1 else "s", best,
		"done ✓" if today_done else "not yet · " + left, "≥ " if not complete else "", reactions,
		"" if complete else " (scan stopped early)"]
