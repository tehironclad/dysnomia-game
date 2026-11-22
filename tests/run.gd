extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run.gd [-- --filter=<substring>]
## Runs every test_* method of every res://tests/test_*.gd. Exit code 0 = all passed.
## Tests need no network. They run after the first idle frame so autoloads
## (Registry, Inspector…) have finished _ready().


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var dir := DirAccess.open("res://tests")
	var files: PackedStringArray = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	for f in files:
		var script = load("res://tests/" + f)
		if not (script is GDScript) or not script.can_instantiate():
			total += 1
			failed += 1
			print("FAIL %s: script failed to load (parse error?)" % f)
			continue
		var inst = script.new()
		for m in inst.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + "::" + name).contains(filter):
				continue
			total += 1
			inst.current = f + "::" + name
			var before: int = inst.failures.size()
			var t0 := Time.get_ticks_msec()
			inst.call(name)
			var ms := Time.get_ticks_msec() - t0
			if inst.failures.size() > before:
				failed += 1
				print("FAIL %s (%d ms)" % [inst.current, ms])
				for i in range(before, mini(inst.failures.size(), before + 10)):
					print("     " + inst.failures[i])
			else:
				print("ok   %s (%d ms)" % [inst.current, ms])
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
