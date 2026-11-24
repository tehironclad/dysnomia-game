extends SceneTree
## Writes hillshaded heightfield previews for real territories (CPU only).
##   godot --headless --path . -s res://tools/preview_terrain.gd -- --out=/abs/dir [--n=257] [--qing=0x…,0x…]
## Default: one territory per style/power. Writes <out>/terrain.png (contact
## sheet), relief.png (height-tinted hillshade, contours every 2 m) and
## per-territory PNGs, and prints timing, slope and height stats.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var n := 257
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--qing="):
			only = a.substr(7).split(",")
	if out == "":
		push_error("pass --out=/absolute/dir")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var registry = root.get_node("Registry")
	var picks: Array = []
	if only.is_empty():
		var seen := {}
		for q in registry.all():
			var p := DeepField.for_territory(q)
			var key := "%s/%d" % [p["style"], p["power"]]
			if not seen.has(key):
				seen[key] = true
				picks.append(q)
	else:
		for a in only:
			picks.append(registry.get_territory(a))
	var cols := 4
	var sheet := Image.create(cols * n, ceili(picks.size() / float(cols)) * n, false, Image.FORMAT_RGB8)
	var relief := Image.create(cols * n, ceili(picks.size() / float(cols)) * n, false, Image.FORMAT_RGB8)
	for i in picks.size():
		var q: Dictionary = picks[i]
		var t0 := Time.get_ticks_msec()
		var hf := JuliaHeightfield.compute(DeepField.for_territory(q), q["address"], n)
		var ms := Time.get_ticks_msec() - t0
		var ins := 0
		for b in hf.inside:
			ins += b
		var img := hf.preview_image()
		img.save_png(out.path_join("%02d_%s.png" % [i, String(q["symbol"]).validate_filename()]))
		sheet.blit_rect(img, Rect2i(0, 0, n, n), Vector2i((i % cols) * n, (i / cols) * n))
		relief.blit_rect(hf.relief_image(), Rect2i(0, 0, n, n), Vector2i((i % cols) * n, (i / cols) * n))
		var lo := INF
		var hi := -INF
		for h in hf.heights:
			lo = minf(lo, h)
			hi = maxf(hi, h)
		var st := hf.slope_stats()
		print("%2d %-30s %-7s D=%d  %5d ms  inside %4.1f%%  core %.1f m  slope p50 %.0f° p95 %.0f° max %.0f° >40°: %.1f%%  heights %.1f..%.1f m" % [i, q["name"], hf.params["style"], hf.params["power"], ms, 100.0 * ins / hf.inside.size(), hf.core_height, st["p50"], st["p95"], st["max"], st["steep_pct"], lo, hi])
	sheet.save_png(out.path_join("terrain.png"))
	relief.save_png(out.path_join("relief.png"))
	quit()
