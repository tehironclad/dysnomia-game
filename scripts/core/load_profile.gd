class_name LoadProfile
extends RefCounted
## Stage timings of a scene build (the territory load): where the seconds go.
## `begin()` starts a run, `mark(stage)` closes the stage that just ran, `report()`
## prints one line ("[Load] terrain 412 ms · core 88 ms · …") and returns the stages.
## Main thread only. Costs a clock read per mark; prints once per load.

static var _t0 := 0
static var _last := 0
static var _stages: Array = []  ## [[name, ms], …] in order
static var last_report: Dictionary = {}  ## the latest finished run: {"total_ms", "stages": [[name, ms]…]}


static func begin() -> void:
	_t0 = Time.get_ticks_usec()
	_last = _t0
	_stages = []


static func mark(stage: String) -> void:
	if _t0 == 0:
		return
	var now := Time.get_ticks_usec()
	_stages.append([stage, (now - _last) / 1000.0])
	_last = now


## Ends the run: prints the stages (slowest first matters less than order here) and returns them.
static func report(label: String) -> Dictionary:
	if _t0 == 0:
		return {}
	var total := (Time.get_ticks_usec() - _t0) / 1000.0
	var parts: Array = []
	for s in _stages:
		if float(s[1]) >= 1.0:
			parts.append("%s %d" % [s[0], int(s[1])])
	print("[Load] %s %d ms: %s" % [label, int(total), " · ".join(parts)])
	last_report = {"total_ms": total, "stages": _stages.duplicate()}
	_t0 = 0
	return last_report
