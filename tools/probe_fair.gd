extends SceneTree
## Headless: walk the player into every fair booth and stall, press Use, report what happens.
##   godot --headless --path . -s res://tools/probe_fair.gd [-- --qing=0x… --wallet=0x…]
## Every midway game is played through in first person (practice: no wallet, nothing paid),
## its score is replayed from the round's input log, and the rocket's lock and progress are
## read from the chain for --wallet (read-only: nothing is signed).
var _qing := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
var _wallet := "0x0000000000000000000000000000000000000369"
var _fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7)
		elif a.begins_with("--wallet="):
			_wallet = a.substr(9).to_lower()
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	Travel.go(self, _qing)
	var t0 := Time.get_ticks_msec()
	var fair = null
	while Time.get_ticks_msec() - t0 < 90000:
		fair = root.find_child("AffectionFair", true, false)
		if fair and fair._fair != null and fair._tier >= 2:
			break
		await process_frame
	var player = get_first_node_in_group("player")
	print("fair=%s tier=%s player=%s" % [fair, fair._tier if fair else -1, player])
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
		await _press("interact")
		print("%-22s booth %s focus=%s riding=%s" % [r.item.get("name", r.ride_id), booth, focus_ok, r.is_riding()])
		if r.is_riding():
			r.end_ride()
			for i in 5:
				await process_frame
	# Every midway game: walk up, Use, play it through in first person
	var played := 0
	for g in fair._fair.game_spots:
		player.global_position = fair._fair.to_global(g["pos"]) + Vector3.UP * 1.0
		player.velocity = Vector3.ZERO
		for i in 10:
			await physics_frame
		await process_frame
		var key = fair._focus_key
		await _press("interact")
		var mp = fair._game
		if mp == null:
			_check(false, "game %s opened (focus %s)" % [g["id"], key])
			continue
		var t1 := Time.get_ticks_msec()
		while not mp.seat.is_inside() and Time.get_ticks_msec() - t1 < 5000:
			await process_frame
		await _press("interact")  # start (after the how-to)
		var board_text: String = g["board"].text if g.get("board") else ""
		t1 = Time.get_ticks_msec()
		var presses := 0
		while mp.phase == "play" and Time.get_ticks_msec() - t1 < 60000:
			# A human-ish player: wait a little in each throw, wiggle the aim, press
			if mp.sim.accepts() and (mp.sim.phase_t > 24 or mp.sim.game == "motzkin" and mp.sim.tick % 23 == 0):
				mp.set_aim(Vector2((presses * 97) % 600 - 300, (presses * 53) % 400 - 200))
				await _press("table_shoot" if presses % 2 == 0 else "interact")
				presses += 1
			await process_frame
		var sc: int = mp.sim.score
		var rep := MidwaySim.replay(mp.game, mp.sim.seed_v, mp.sim.events)
		var log := MidwaySim.encode_log(mp.game, mp.sim.events)
		_check(mp.phase == "result" and rep == sc, "game %-9s played: %d presses, %d ticks, score %d, replay %d, log %d chars \"%s\"" % [
			g["id"], mp.sim.events.size(), mp.sim.tick, sc, rep, log.length(), log.left(40)])
		_check(board_text.begins_with("ROOM BOARD"), "game %-9s has its room board sign: %s" % [g["id"], board_text.replace("\n", " | ").left(110)])
		await _press("interact")  # leave the result screen
		t1 = Time.get_ticks_msec()
		while fair._game != null and Time.get_ticks_msec() - t1 < 5000:
			await process_frame
		_check(fair._game == null and player.is_physics_processing(), "game %-9s closed, the player walks again" % g["id"])
		played += 1
	_check(played == 7, "all seven games played (%d)" % played)
	# The rocket: free preview without a wallet; locked with one until all seven are on chain
	var rk = fair._fair.get_rides().filter(func(x): return x.ride_id == "rocket")
	if rk.is_empty():
		print("no rocket at this tier")
	else:
		var rocket = rk[0]
		_check(not fair._rocket_locked(rocket), "no wallet: the rocket is the free preview")
		var wallet_node = root.get_node("Wallet")
		var fp = load("res://scripts/world/funfair/fair_progress.gd")
		wallet_node.address = _wallet
		await fair.refresh_progress()
		print("progress for %s: %s · %s" % [_wallet, fair._progress, fair._progress_line()])
		_check(fair._progress["state"] == "ok", "the wallet's tickets were read from the chain (eth_getLogs from block %d)" % fp.FROM_BLOCK)
		var locked: bool = fair._rocket_locked(rocket)
		_check(locked == not fp.unlocked(fair._progress["codes"]), "the lock follows the chain (locked=%s)" % locked)
		var lights = rocket.get_node_or_null("RocketLights")
		_check(lights != null and lights._status.text != "", "the 7-light board: %s" % (lights._status.text if lights else "—"))
		player.global_position = rocket.to_global(rocket.booth_local_position) + Vector3.UP
		for i in 20:
			await physics_frame
		await process_frame
		var prompt: String = fair._hud.prompt.text
		print("rocket prompt: ", prompt)
		await _press("interact")
		_check(not rocket.is_riding() and not fair._paying, "a locked rocket sells no ticket and doesn't start")
		wallet_node.address = ""
		fair.refresh_progress()
	print("\n%d failed" % _fails)
	quit(1 if _fails > 0 else 0)


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
