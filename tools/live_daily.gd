extends SceneTree
## Read-only live check of the daily challenge's seed (DailySeed): finds the first PulseChain block
## whose timestamp is ≥ 00:00 UTC today (and yesterday), checks the block before it is earlier, and
## prints the day's game and seed. Nothing is signed or sent.
##   godot --headless --path . -s res://tools/live_daily.gd [-- --day=YYYY-MM-DD]
## Exit code 0 when every day's block was found and checked.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dc = load("res://scripts/games/daily/daily_challenge.gd")
	var seed_s = load("res://scripts/games/daily/daily_seed.gd")
	var clock = load("res://scripts/net/block_clock.gd")
	seed_s.use_file = false  # search the chain, not this computer's cache
	var today: String = dc.day_of(int(Time.get_unix_time_from_system()))
	var days: Array = [today, dc.prev_day(today)]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--day="):
			days = [a.substr(6)]
	for day in days:
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = await seed_s.find(day)
		var ms := Time.get_ticks_msec() - t0
		print("day %s  game %s (%s)" % [day, dc.game_for(day), dc.title_of(dc.game_for(day))])
		if r.get("state", "") != "ok":
			print("  FAIL seed block: — (%s)" % r.get("error", "?"))
			_failures += 1
			continue
		var midnight: int = dc.day_start(day)
		var prev: Dictionary = await clock.read(int(r["block"]) - 1)
		var first_ok: bool = int(r["timestamp"]) >= midnight and not prev.is_empty() and int(prev["timestamp"]) < midnight
		print("  block %d  %s  timestamp %s (%+d s after 00:00 UTC)" % [int(r["block"]), r["hash"], Time.get_datetime_string_from_unix_time(int(r["timestamp"])) + "Z",
			int(r["timestamp"]) - midnight])
		print("  block %d  timestamp %s (the block before)" % [int(r["block"]) - 1, (Time.get_datetime_string_from_unix_time(int(prev["timestamp"])) + "Z") if not prev.is_empty() else "—"])
		print("  seed %d = SHA-256(\"daily:%s:<hash>\")[0:12]  · found in %d ms" % [int(r["seed"]), day, ms])
		print("  %s %s" % ["PASS" if first_ok else "FAIL", "it is the first block at or after midnight" if first_ok else "not the first block at or after midnight"])
		if not first_ok:
			_failures += 1
	quit(1 if _failures > 0 else 0)
