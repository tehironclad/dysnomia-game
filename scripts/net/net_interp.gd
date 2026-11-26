class_name NetInterp
extends RefCounted
## A remote player's motion: snapshots arrive about 10 times a second (each
## stamped with the sender's own clock, u16 ms), and the avatar is drawn
## DELAY_MS in the past, interpolated between the two snapshots around that
## moment. Past the newest snapshot it extrapolates briefly, then holds.
##
## The sender's clock is mapped onto ours with the smallest (arrival − sent)
## seen, which tracks the fastest path; it relaxes slowly so a clock drift or
## a route change can't freeze it. Pure (times are passed in), so tests drive it.

const DELAY_MS := 150.0
const MAX_EXTRAP_MS := 250.0
const KEEP := 24
const TELEPORT_M := 25.0

var _snaps: Array = []        # [{t (local ms), pos, yaw, flags, anim}] oldest first
var _last_raw := -1
var _unwrapped := 0
var _offset := INF            # local − sender, ms
var _offset_at := 0.0
var _stale := 0               # snapshots in a row that looked older than the last one
const STALE_RESYNC := 3


## A snapshot from the wire (t16: sender ms, u16), received at local `now_ms`.
func push(t16: int, pos: Vector3, yaw: float, flags: int, anim: int, now_ms: float) -> void:
	if _last_raw < 0:
		_unwrapped = t16
	else:
		var d := (t16 - _last_raw) & 0xFFFF
		if d >= 0x8000:
			_stale += 1
			if _stale < STALE_RESYNC:
				return  # older than the last one (out of order): drop
			# Several in a row: the sender's u16 clock moved on by more than half a wrap
			# (a stall of 33 s or more), not a reorder. Start over from this one instead
			# of freezing the avatar until the clock comes round again.
			_snaps.clear()
			_offset = INF
			_unwrapped = t16
		else:
			_unwrapped += d
	_stale = 0
	_last_raw = t16
	var off := now_ms - _unwrapped
	if off < _offset:
		_offset = off
		_offset_at = now_ms
	elif now_ms - _offset_at > 1000.0:
		_offset += 2.0  # relax 2 ms a second
		_offset_at = now_ms
	var t := _unwrapped + _offset
	if not _snaps.is_empty() and (pos - _snaps[-1]["pos"]).length() > TELEPORT_M:
		_snaps.clear()  # a jump (border crossing, respawn): don't slide across the map
	_snaps.append({"t": t, "pos": pos, "yaw": yaw, "flags": flags, "anim": anim})
	while _snaps.size() > KEEP:
		_snaps.pop_front()


func has_data() -> bool:
	return not _snaps.is_empty()


## {pos, yaw, vel, flags, anim} at local time `now_ms` ({} before any snapshot).
func sample(now_ms: float) -> Dictionary:
	if _snaps.is_empty():
		return {}
	var rt := now_ms - DELAY_MS
	var first: Dictionary = _snaps[0]
	if rt <= first["t"] or _snaps.size() == 1:
		return {"pos": first["pos"], "yaw": first["yaw"], "vel": Vector3.ZERO, "flags": first["flags"], "anim": first["anim"]}
	for i in range(_snaps.size() - 1, 0, -1):
		var a: Dictionary = _snaps[i - 1]
		var b: Dictionary = _snaps[i]
		if rt >= a["t"]:
			var span := maxf(1.0, b["t"] - a["t"])
			var vel: Vector3 = (b["pos"] - a["pos"]) / (span / 1000.0)
			var u: float = (rt - a["t"]) / span
			if u > 1.0:
				# past the newest: extrapolate a little, then hold
				var extra: float = minf(rt - b["t"], MAX_EXTRAP_MS)
				var moving: bool = rt - b["t"] <= MAX_EXTRAP_MS
				return {"pos": b["pos"] + vel * (extra / 1000.0), "yaw": b["yaw"],
					"vel": vel if moving else Vector3.ZERO, "flags": b["flags"], "anim": b["anim"]}
			return {"pos": (a["pos"] as Vector3).lerp(b["pos"], u), "yaw": lerp_angle(a["yaw"], b["yaw"], u),
				"vel": vel, "flags": b["flags"] if u > 0.5 else a["flags"], "anim": b["anim"] if u > 0.5 else a["anim"]}
	return {}
