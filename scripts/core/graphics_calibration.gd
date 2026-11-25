class_name GraphicsCalibration
extends RefCounted
## First-launch calibration: which quality level this computer holds, by measuring
## it (pure decisions; CalibrationRun renders and measures, Config applies).
##
## Start at the hardware's guess (Config.recommend). Each step renders the arriving
## territory at one level with V-Sync off, the window's render scale fixed at that
## level's nominal value, and measures the median frame time (the cost). Then:
## - over budget (cost > target × OVER): one level down, unless that level already
##   measured fine, or this is Potato (done; the target drops to 30 fps if even
##   Potato can't hold 60);
## - lots of headroom (cost < target × HEADROOM): one level up, up to High; Ultra
##   only if High itself costs under target × ULTRA_HEADROOM;
## - otherwise this level is it.
## At most MAX_STEPS measurements; a level is never measured twice.

const OVER := 1.05
const HEADROOM := 0.6
const ULTRA_HEADROOM := 0.4
const MAX_STEPS := 5
const TARGET_FPS := 60
const WEAK_TARGET_FPS := 30


## `results`: {level: cost_ms} measured so far (including this one).
## Returns {"done": bool, "level": int} (the level to measure next, or the answer).
static func next(level: int, cost_ms: float, results: Dictionary, target_ms: float, top: int = 4) -> Dictionary:
	var steps := results.size()
	if cost_ms > target_ms * OVER:
		if level <= 0:
			return {"done": true, "level": 0}
		var down := level - 1
		if results.has(down) or steps >= MAX_STEPS:
			return {"done": true, "level": down}
		return {"done": false, "level": down}
	var cap := mini(top, 3)
	if level >= 3 and top >= 4 and cost_ms < target_ms * ULTRA_HEADROOM:
		cap = 4
	if cost_ms < target_ms * HEADROOM and level < cap:
		var up := level + 1
		if results.has(up):
			return {"done": true, "level": level if float(results[up]) > target_ms * OVER else up}
		if steps >= MAX_STEPS:
			return {"done": true, "level": level}
		return {"done": false, "level": up}
	return {"done": true, "level": level}


## The frame-rate target once a level is chosen: 60, or 30 on a machine whose
## lightest level still can't hold 60 (dynamic resolution then holds 30).
static func target_fps_for(level: int, results: Dictionary, target_ms: float) -> int:
	if level <= 0 and results.has(0) and float(results[0]) > target_ms * OVER:
		return WEAK_TARGET_FPS
	return TARGET_FPS


## Which renderer measured better: {renderer: {"level": int, "cost_ms": float}}.
## The higher level wins; at the same level, the cheaper frame. "" if fewer than two.
static func better_renderer(records: Dictionary) -> String:
	var best := ""
	var best_level := -1
	var best_cost := INF
	if records.size() < 2:
		return ""
	for r in records:
		var rec: Dictionary = records[r]
		var lv := int(rec.get("level", -1))
		var c := float(rec.get("cost_ms", INF))
		if lv > best_level or (lv == best_level and c < best_cost):
			best = String(r)
			best_level = lv
			best_cost = c
	return best


## One line for the player: what was measured and what was picked.
static func describe(results: Dictionary, level: int, fps: int, names: Array) -> String:
	var parts: Array = []
	var keys := results.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %.1f ms" % [String(names[int(k)]).split(" ")[0], float(results[k])])
	return "%s at %d fps (measured: %s)" % [String(names[level]).split(" ")[0], fps, ", ".join(parts)]
