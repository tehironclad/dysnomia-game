extends SceneTree
## Headless runtime check of the landmark and a base jump (read-only; nothing is
## signed: the jump is a practice jump). Loads a territory from the chain, waits
## for its landmark, rides the glass lift up, launches from the plank, opens the
## wingsuit, then the canopy, and lands. Prints each stage and the score card.
##   godot --headless --path . -s res://tools/live_basejump.gd [-- --qing=0x…]

var _qing := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"  # RatKing (a Capital)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7)
	_run.call_deferred()


func _run() -> void:
	Travel.go(self, _qing)
	var scene: Node = null
	var lm = null
	for i in 1200:
		await process_frame
		scene = current_scene
		if scene and scene.get("landmark") and scene.landmark.has_tower():
			lm = scene.landmark
			break
	if lm == null:
		print("no landmark built (tier below Settlement, or the chain did not answer)")
		quit(0)
		return
	var player: CharacterBody3D = scene.player
	var bj = scene.base_jump
	print("landmark: %s · roof %d m · lift at %s · ring %s" % [lm.spec["title"], int(lm.spec["roof"]), str(lm._car_global(0.0)), str(lm.ring_global())])
	# The glass lift: stand in the car and ride up
	player.global_position = lm._car_global(0.2)
	for i in 5:
		await physics_frame
	lm._start_ride(0.0, float(lm.spec["deck"]))
	var t0 := Time.get_ticks_msec()
	while lm._riding:
		await process_frame
	print("lift: at %.1f m above the plaza after %.1f s (wall clock) · physics back on: %s" % [player.global_position.y - lm.global_position.y, (Time.get_ticks_msec() - t0) / 1000.0, player.is_physics_processing()])
	# Walk to the plank tip, then launch (a practice jump: no wallet here)
	player.global_position = lm.plank_tip() + Vector3(0, 0.3, 0)
	for i in 10:
		await physics_frame
	print("on the plank: %s · focus %s" % [str(player.global_position.round()), lm._focus])
	lm._launch("practice", {})
	var stage := 0
	var frames := 0
	while bj.state == bj.FLYING and frames < 60 * 240:
		await physics_frame
		frames += 1
		if stage == 0 and bj.airtime > 3.0:
			var ev := InputEventAction.new()
			ev.action = "wingsuit"
			ev.pressed = true
			bj._unhandled_input(ev)
			stage = 1
			print("wingsuit at %.1f s · v %s" % [bj.airtime, str(player.velocity.round())])
		var agl: float = player.global_position.y - scene.terrain.get_height_at(player.global_position.x, player.global_position.z)
		if stage == 1 and agl < 80.0:
			var ev := InputEventAction.new()
			ev.action = "parachute"
			ev.pressed = true
			bj._unhandled_input(ev)
			stage = 2
			print("canopy at %.1f s · %d m AGL · v %s" % [bj.airtime, int(agl), str(player.velocity.round())])
	print("landed: %s after %.1f s of flight · %s" % [bj.state == bj.IDLE, bj.airtime, bj._card_label.text.replace("\n", " | ")])
	quit(0)
