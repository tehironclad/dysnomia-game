extends SceneTree
## One prompt, never a dead one (read-only; nothing is paid, posted or signed):
##   godot --headless --path . -s res://tools/probe_prompts.gd [-- --only=arcade,pub]
## In the arcade and Sunny's Pub:
##  1. sweeps the floor on a 0.5 m grid: wherever a Use prompt shows, it names the spot Use acts on,
##     and a cabinet's floating title shows only with its own prompt (never a far "press E" alone);
##  2. for every spot (each cabinet, each table seat, the bar), stands at the far edge of where its
##     prompt shows, presses Use and checks it works from there: the walk-up, then the dive / the
##     seat / the menu; then backs out;
##  3. in the pub, the bar-menu key from across the room walks you up and opens the menu.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const SUNFLOWER := "0x2b78b345880807ac9be28c1309ab55d6fa8796de"

var _fails := 0
var _only: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).split(",")
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_fails += 1


func _ok(what: String) -> void:
	print("ok   " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


func _run() -> void:
	if _only.is_empty() or _only.has("arcade"):
		await _place(ILLINOIS, "res://scenes/places/arcade_place.tscn", 12.0, 8.0)
	if _only.is_empty() or _only.has("pub"):
		await _place(SUNFLOWER, "res://scenes/places/sunny_pub.tscn", 10.0, 8.0)
	print("\n%s (%d failed)" % ["ALL OK" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


func _place(addr: String, path: String, hx: float, hz: float) -> void:
	root.get_node("GameManager").territory_address = addr
	change_scene_to_file(path)
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or current_scene.scene_file_path != path) and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	await _frames(30)
	var place: Node = current_scene
	var label := path.get_file().get_basename()
	if place == null or place.scene_file_path != path:
		_check(false, "%s: scene loaded" % label)
		return
	var p: CharacterBody3D = place.player
	# 1. The sweep (the body held still: each sample is judged where it was put).
	p.process_mode = Node.PROCESS_MODE_DISABLED
	var shown := 0
	var bad := 0
	var x := -hx + 0.5
	while x < hx:
		var z := -hz + 0.5
		while z < hz:
			p.global_position = Vector3(x, 0.1, z)
			p.velocity = Vector3.ZERO
			await _frames(2)
			var i: int = place._near_spot
			var pos := p.global_position
			var want: int = -1 if place._near_exit else place.pick_spot(place._spots, pos)
			var title_cab = place._near_cab
			if i != want or (title_cab != null and title_cab != place.spot_cabinet(i)) or (i >= 0 and place.prompt_label.text == ""):
				bad += 1
				if bad <= 5:
					print("     at %s: spot %d (want %d), title %s, prompt '%s'" % [pos, i, want, title_cab, place.prompt_label.text])
			if i >= 0:
				shown += 1
			for c in place.cabinets:
				if c._near_on and c != place.spot_cabinet(i):
					bad += 1
			z += 0.5
		x += 0.5
	p.process_mode = Node.PROCESS_MODE_INHERIT
	_check(bad == 0, "%s: sweep: %d mismatches" % [label, bad])
	if bad == 0:
		_ok("%s: sweep: the prompt, the floating title and Use agree everywhere (%d places with a prompt)" % [label, shown])
	# 2. Every spot from the far edge of its prompt.
	for i in place._spots.size():
		var s: Dictionary = place._spots[i]
		var at: Vector3 = s["at"]
		var r: float = s["r"]
		var stood := false
		for k in 16:
			var a := TAU * k / 16.0
			var want := at + Vector3(sin(a), 0, cos(a)) * (r - 0.12)
			if absf(want.x) > hx - 0.4 or absf(want.z) > hz - 0.4:
				continue
			p.global_position = Vector3(want.x, 0.1, want.z)
			p.velocity = Vector3.ZERO
			await _frames(3)
			var got := Vector2(p.global_position.x - want.x, p.global_position.z - want.z).length()
			if got < 0.05 and place._near_spot == i and place.prompt_label.text != "":
				stood = true
				break
		if not stood:
			continue  # every point of its edge is inside furniture or nearer another spot
		var what := String(s["prompt"].call()).left(48)
		var from := p.global_position
		await _press("interact")
		var t1 := Time.get_ticks_msec()
		var opened := ""
		while Time.get_ticks_msec() - t1 < 6000:
			await process_frame
			if place.dive and place.dive.is_active():
				opened = "dive"
			elif place.seat and place.seat.is_active():
				opened = "seat"
			elif "bar_state" in place and place.bar_state == "menu":
				opened = "menu"
			if opened != "":
				break
		var dist := Vector2(from.x - at.x, from.z - at.z).length()
		_check(opened != "", "%s: spot %d '%s': Use from %.1f m does nothing" % [label, i, what, dist])
		if opened != "":
			_ok("%s: '%s' from %.1f m → %s" % [label, what, dist, opened])
		await _back_out(place)
	# 3. The pub's bar-menu key from across the room.
	if "bar_state" in place:
		p.global_position = Vector3(5.5, 0.1, 5.0)
		p.velocity = Vector3.ZERO
		await _frames(4)
		await _press("bar_menu")
		var t2 := Time.get_ticks_msec()
		while place.bar_state != "menu" and Time.get_ticks_msec() - t2 < 6000:
			await process_frame
		_check(place.bar_state == "menu", "%s: the bar-menu key from across the room opens the menu" % label)
		if place.bar_state == "menu":
			_ok("%s: the bar-menu key from across the room walks you up and opens the menu" % label)
		await _back_out(place)


func _back_out(place: Node) -> void:
	if place.dive and place.dive.is_active():
		var t := Time.get_ticks_msec()
		while not place.dive.is_inside() and Time.get_ticks_msec() - t < 5000:
			await process_frame
		place._close_play()
		while place.dive.is_active() and Time.get_ticks_msec() - t < 10000:
			await process_frame
	if place.seat and place.seat.is_active():
		var t := Time.get_ticks_msec()
		while not place.seat.is_inside() and Time.get_ticks_msec() - t < 5000:
			await process_frame
		await place._stand()
		while place.seat.is_active() and Time.get_ticks_msec() - t < 10000:
			await process_frame
	if "bar_state" in place and place.bar_state == "menu":
		place.bar_menu.close()
		await _frames(3)
	place._resume()
	await _frames(3)
