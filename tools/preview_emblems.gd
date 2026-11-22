extends SceneTree
## Renders a contact sheet of real territories' Deep Field pictures with the CPU
## reference renderer (no GPU needed), one per style/power combination.
##   godot --headless --path . -s res://tools/preview_emblems.gd -- --out=/abs/dir [--size=160]
## Writes <out>/emblems.png plus one PNG per territory, and prints which
## territory each tile is.


func _initialize() -> void:
	_run.call_deferred()  # autoloads are ready after the first idle


func _run() -> void:
	var out := ""
	var size := 160
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--size="):
			size = int(a.substr(7))
	if out == "":
		push_error("pass --out=/absolute/dir")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var registry = root.get_node("Registry")
	var seen := {}
	var picks: Array = []
	for q in registry.all():
		var p := DeepField.for_territory(q)
		var key := "%s/%d" % [p["style"], p["power"]]
		if seen.has(key):
			continue
		seen[key] = true
		picks.append([q, p])
	picks.sort_custom(func(x, y): return String(x[1]["style"]) + str(x[1]["power"]) < String(y[1]["style"]) + str(y[1]["power"]))
	var cols := 4
	var rows := ceili(picks.size() / float(cols))
	var sheet := Image.create(cols * size, rows * size, false, Image.FORMAT_RGB8)
	for i in picks.size():
		var q: Dictionary = picks[i][0]
		var p: Dictionary = picks[i][1]
		var img := Julia.render_image(p, size, size)
		img.save_png(out.path_join("%02d_%s_%s_d%d.png" % [i, String(q["symbol"]).validate_filename(), p["style"], p["power"]]))
		sheet.blit_rect(img, Rect2i(0, 0, size, size), Vector2i((i % cols) * size, (i / cols) * size))
		print("%2d  %-28s %-7s D=%d %-9s %s" % [i, q["name"], p["style"], p["power"], p["tier"], q["address"]])
	sheet.save_png(out.path_join("emblems.png"))
	print("wrote ", out.path_join("emblems.png"))
	quit()
