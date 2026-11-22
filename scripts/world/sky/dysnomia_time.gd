class_name DysnomiaTime
extends RefCounted
## DysnomiaTime (Maria's lore, glossary "DysnomiaTime"): 34 hours a day,
## 100 minutes an hour, 34 seconds a minute = 115,600 s per day. Derived from a
## block timestamp, so every player sees the same time of day.

const SECONDS_PER_MINUTE := 34
const MINUTES_PER_HOUR := 100
const HOURS_PER_DAY := 34
const DAY_SECONDS := SECONDS_PER_MINUTE * MINUTES_PER_HOUR * HOURS_PER_DAY  # 115,600


static func from_unix(ts: int) -> Dictionary:
	var s := posmod(ts, DAY_SECONDS)
	return {
		"day": ts / DAY_SECONDS,
		"hour": s / (SECONDS_PER_MINUTE * MINUTES_PER_HOUR),
		"minute": (s / SECONDS_PER_MINUTE) % MINUTES_PER_HOUR,
		"second": s % SECONDS_PER_MINUTE,
		"fraction": float(s) / DAY_SECONDS,
	}


static func format(ts: int) -> String:
	var t := from_unix(ts)
	return "day %d · %02d:%02d:%02d DT" % [t["day"], t["hour"], t["minute"], t["second"]]
