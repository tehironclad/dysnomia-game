extends SceneTree
## Parse/compile every GDScript under res://scripts, res://scenes and res://addons.
##   godot --headless --path . -s tools/check_scripts.gd
## Prints "SCRIPT ERROR" lines from the engine for anything that fails, then a summary.

func _initialize() -> void:
	var bad := 0
	var total := 0
	for dir in ["res://scripts", "res://scenes", "res://addons"]:
		for path in _walk(dir):
			total += 1
			var s = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if s == null or (s is GDScript and not s.can_instantiate()):
				bad += 1
				print("[check] FAILED ", path)
	print("[check] %d scripts, %d failed" % [total, bad])
	quit(1 if bad > 0 else 0)

func _walk(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out += _walk(dir + "/" + sub)
	return out
