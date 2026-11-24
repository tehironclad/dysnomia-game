extends SceneTree
## Headless: walk the player into every fair booth, press Use, report what happens.
##   godot --headless --path . -s res://tools/probe_fair.gd [-- --qing=0x…]
var _qing := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7)
	_run.call_deferred()


func _run() -> void:
	Travel.go(self, _qing)
	for i in 120:
		await process_frame
	var fair = root.find_child("AffectionFair", true, false)
	var player = get_first_node_in_group("player")
	print("fair=%s player=%s layer=%d" % [fair, player, player.collision_layer if player else -1])
	if fair == null or fair._fair == null:
		print("FAIL no fair")
		quit(1)
		return
	for r in fair._fair.get_rides():
		var booth: Vector3 = r.to_global(r.booth_local_position)
		player.global_position = booth + Vector3.UP * 1.0
		player.velocity = Vector3.ZERO
		for i in 20:
			await physics_frame
		var focus_ok = fair._focus == r
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		for i in 10:
			await process_frame
		var ev2 := InputEventAction.new()
		ev2.action = "interact"
		ev2.pressed = false
		Input.parse_input_event(ev2)
		for i in 5:
			await process_frame
		print("%-22s booth %s focus=%s riding=%s" % [r.item.get("name", r.ride_id), booth, focus_ok, r.is_riding()])
		if r.is_riding():
			r.end_ride()
			for i in 5:
				await process_frame
	# The rocket from its pad (not the booth)
	var rk = fair._fair.get_rides().filter(func(x): return x.ride_id == "rocket")
	if not rk.is_empty():
		player.global_position = rk[0].global_position + Vector3(8.0, 1.0, 0.0)
		for i in 10:
			await physics_frame
		await process_frame
		print("rocket from beside the pad: focus=%s" % (fair._focus == rk[0]))
	# Every midway game: walk up, Use, play it through with Use presses
	for g in fair._fair.game_spots:
		player.global_position = fair._fair.to_global(g["pos"]) + Vector3.UP * 1.0
		for i in 10:
			await physics_frame
		await process_frame
		var key = fair._focus_key
		await _press()
		var ov = fair._game
		var opened = ov != null
		var got := [-2]
		if opened:
			ov.finished.connect(func(x): got[0] = x)
			var t0 := Time.get_ticks_msec()
			while fair._game != null and Time.get_ticks_msec() - t0 < 45000:
				await _press()
				await create_timer(0.37).timeout
		var sc: int = got[0]
		print("game %-9s focus=%s opened=%s closed=%s score=%d" % [g["id"], key, opened, fair._game == null, sc])
	quit(0)


func _press() -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
