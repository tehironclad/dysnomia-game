class_name DailySeed
extends RefCounted
## Reads the daily challenge's seed block from the chain (read-only): the first PulseChain block
## whose timestamp is ≥ 00:00 UTC on the day, found by DailyChallenge.Search over block
## timestamps (BlockClock.read: eth_getBlockByNumber, one request at a time, never a batch).
## Found blocks are cached here for the session and, on a client, in user://daily.cfg
## (DailyLocal), so a restart doesn't search again. Nothing is ever guessed: a failed read is
## {state: "failed"} and every screen shows "—" (practice only).
##
## The game server uses the same search for its own seed (it never takes the client's).
## `override` (tools/net_selftest.gd only) answers for the chain in a self-test with no network.

static var _cache := {}      ## day → {state: "ok", …}
static var _busy := {}       ## day → true while a search runs
static var _failed := {}     ## day → {state: "failed", error, at}
static var override: Callable = Callable()
static var use_file := true  ## the client keeps found blocks in DailyLocal; the server doesn't
const RETRY_S := 30.0        ## a failed day is searched again after this


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## What is known now, without reading: {state: "ok", day, block, hash, timestamp, seed} |
## {state: "failed", day, error} | {state: "checking", day}.
static func peek(day: String) -> Dictionary:
	if _cache.has(day):
		return _cache[day]
	if use_file:
		var c := DailyLocal.cached_seed(day)
		if not c.is_empty():
			_cache[day] = _ok(day, c)
			return _cache[day]
	if _failed.has(day) and not _busy.has(day):
		return _failed[day]
	return {"state": "checking", "day": day}


## Finds the day's seed block (await). Returns peek()'s shape, never "checking".
static func find(day: String) -> Dictionary:
	var known := peek(day)
	if known["state"] == "ok":
		return known
	if known["state"] == "failed" and Time.get_ticks_msec() / 1000.0 - float(known.get("at", 0.0)) < RETRY_S:
		return known
	var tree := _tree()
	if _busy.has(day):
		while _busy.has(day) and tree:
			await tree.process_frame
		return peek(day)
	_busy[day] = true
	var r: Dictionary = await _search(day)
	_busy.erase(day)
	if r["state"] == "ok":
		_cache[day] = r
		_failed.erase(day)
		if use_file:
			DailyLocal.cache_seed(day, r)
	else:
		r["at"] = Time.get_ticks_msec() / 1000.0
		_failed[day] = r
	return r


static func _ok(day: String, b: Dictionary) -> Dictionary:
	var h := String(b.get("hash", "")).to_lower()
	return {"state": "ok", "day": day, "block": int(b.get("block", b.get("number", 0))), "hash": h,
		"timestamp": int(b.get("timestamp", 0)), "seed": DailyChallenge.seed_from_hash(day, h)}


static func _fail(day: String, why: String) -> Dictionary:
	return {"state": "failed", "day": day, "error": why}


static func _search(day: String) -> Dictionary:
	var target := DailyChallenge.day_start(day)
	if target < 0:
		return _fail(day, "bad day")
	if override.is_valid():
		var o: Dictionary = await override.call(day)
		if o.get("ok", false) and DailyChallenge.valid_hash(String(o.get("hash", "")).to_lower()):
			return _ok(day, o)
		return _fail(day, String(o.get("error", "—")))
	var head: Dictionary = await BlockClock.read("latest")
	if head.is_empty():
		return _fail(day, "the latest block could not be read: —")
	var s := DailyChallenge.Search.new(target, int(head["number"]), int(head["timestamp"]))
	while not s.done:
		var n := s.next()
		if n < 0:
			break
		var b: Dictionary = await BlockClock.read(n)
		if b.is_empty():
			s.fail("block %d could not be read: —" % n)
			break
		s.feed(n, int(b["timestamp"]))
	if s.found < 0:
		return _fail(day, s.error if s.error != "" else "the day's first block was not found: —")
	var fb: Dictionary = await BlockClock.read(s.found)
	if fb.is_empty() or int(fb["timestamp"]) < target:
		return _fail(day, "block %d could not be read: —" % s.found)
	return _ok(day, {"block": int(fb["number"]), "hash": String(fb["hash"]), "timestamp": int(fb["timestamp"])})


## Tests and tools: forget what was found this session.
static func clear() -> void:
	_cache.clear()
	_failed.clear()
