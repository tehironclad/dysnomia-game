extends SceneTree
## Headless: walk the player into every fair booth and stall, press Use, report what happens.
##   godot --headless --path . -s res://tools/probe_fair.gd [-- --qing=0x… --wallet=0x…]
## Every midway game is played through in first person (practice: no wallet, nothing paid),
## its score is replayed from the round's input log, and the rocket's lock and progress are
## read from the chain for --wallet (read-only: nothing is signed). Ticket strips: the stall's prices,
## the buy choice (cancelled), and a local fixture strip played twice (seeds, room lines, plays left).
var _qing := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
var _wallet := "0x0000000000000000000000000000000000000369"
var _fails := 0
const PROBE_BLOCK := 28136000  ## the block the probe's local fixture strip claims (never read from or written to the chain)


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
	load("res://scripts/core/travel.gd").go(self, _qing)  # by path: Travel uses autoloads (parse time)
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
			var t_b := Time.get_ticks_msec()
			while r.is_boarding() and Time.get_ticks_msec() - t_b < 4000:
				await process_frame
			var seat_d: float = player.global_position.distance_to(r.get_seat_transform(r._t).origin)
			r.end_ride()
			var t_a := Time.get_ticks_msec()
			while r.is_alighting() and Time.get_ticks_msec() - t_a < 4000:
				await process_frame
			var off_d: float = player.global_position.distance_to(r.to_global(r.exit_local_position))
			_check(seat_d < 0.5 and off_d < 0.5 and fair._riding == null and player.is_physics_processing(),
				"%-22s boarded by a step (seat %.2f m), stepped off to the exit (%.2f m), walks again" % [r.item.get("name", r.ride_id), seat_d, off_d])
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
		var crowd: int = mp.stage.crowd.count() if mp.stage.crowd else 0
		if mp.phase == "celebrate":  # a good round: the wide shot, the crowd, the prize
			_check(crowd >= 3 and mp.prize_kind != "", "game %-9s celebrates: %d onlookers cheer, prize %s" % [g["id"], crowd, mp.prize_kind])
			await _press("interact")
		else:
			print("     %-9s no celebration (score %d, prize \"%s\", %d onlookers)" % [g["id"], sc, mp.prize_kind, crowd])
		_check(mp.stage.fx != null and mp.stage.shelf != null, "game %-9s has its effects and a prize shelf" % g["id"])
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
	await _probe_strips(fair, player)
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
		if locked:
			# Locked: the unlock steps pop up, with a footer button for a free practice flight
			var steps_script = load("res://scripts/ui/access/access_steps.gd")
			var popup = steps_script._popup_ref.get_ref() if steps_script.popup_open() else null
			_check(popup != null, "a locked rocket shows the unlock steps")
			var fly: Button = null
			if popup != null:
				for b in popup._extra_btns:
					if is_instance_valid(b) and String(b.text).begins_with("Fly a free practice flight"):
						fly = b
			_check(fly != null, "the steps offer a free practice flight")
			if fly != null:
				fly.pressed.emit()
				for i in 5:
					await process_frame
		_check(not fair._paying and (rocket.is_riding() or not locked), "a locked rocket sells no ticket and flies a free practice flight")
		if rocket.is_riding():
			rocket.end_ride()
			for i in 5:
				await process_frame
		wallet_node.address = ""
		fair.refresh_progress()
	print("\n%d failed" % _fails)
	quit(1 if _fails > 0 else 0)


## Ticket strips at a stall, with --wallet connected (read-only: nothing is signed). The stall's
## prompt and plaque show the prices; Use with no plays opens the buy choice (one play / a strip
## for this game / for any game; cancelled here). Then a strip in the LOCAL ledger only (a probe
## fixture with a made-up tx, removed afterwards: nothing on chain claims it) plays twice without
## a payment: play #0 and #1, each seeded by SHA-256("<tx>#<i>"), its room line naming tx#i;
## after the strip's last play the next strip is offered.
func _probe_strips(fair, player) -> void:
	var AP = load("res://scripts/games/arcade_pay.gd")
	var TC = load("res://scripts/games/ticket_code.gd")
	var PR = load("res://scripts/games/prices.gd")
	var TCH = load("res://scripts/ui/ticket_choice.gd")
	var FB = load("res://scripts/world/funfair/fair_board.gd")
	var MG = load("res://scripts/world/funfair/midway_game.gd")
	var wallet_node = root.get_node("Wallet")
	var q: String = fair._qing
	var game := "waat"  # a short game
	var spot = fair._fair.game_spots.filter(func(x): return x["id"] == game)[0]
	var ledger_key := "%s@%s" % [_wallet, q]
	var saved := ConfigFile.new()
	var had := saved.load(AP.LEDGER) == OK and saved.has_section_key("credits", ledger_key)
	var saved_list = saved.get_value("credits", ledger_key, []) if had else []
	# The fixture's paid rounds would leave prizes and local scores naming its made-up tx: kept aside
	var kept := {}
	for f in ["user://fair_prizes.cfg", "user://arcade_scores.cfg"]:
		kept[f] = FileAccess.get_file_as_bytes(f) if FileAccess.file_exists(f) else null
	var clean := ConfigFile.new()
	clean.load(AP.LEDGER)
	if clean.has_section_key("credits", ledger_key):
		clean.erase_section_key("credits", ledger_key)
		clean.save(AP.LEDGER)
	wallet_node.address = _wallet
	player.global_position = fair._fair.to_global(spot["pos"]) + Vector3.UP * 1.0
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	await process_frame
	var prompt: String = fair._hud.prompt.text
	_check(prompt.contains(PR.menu_line()), "a stall's prompt shows the prices: %s" % prompt)
	var plaque: Label3D = fair._plaques.get(game)
	_check(plaque != null and plaque.text.begins_with(PR.menu_line().to_upper()), "its counter plaque: %s" % (plaque.text.replace("\n", " | ") if plaque else "—"))
	await _press("interact")
	var choice = TCH.current()
	var texts: Array = choice.buttons.map(func(b): return String(b.text)) if choice else []
	_check(choice != null and texts.size() == 3 and texts[0] == PR.play_button() and String(texts[1]).begins_with(PR.strip_button()) and String(texts[2]).contains("any fair game"),
		"no plays left: Use offers %s" % str(texts))
	_check(not fair._paying, "nothing is paid until a button is pressed")
	if choice:
		choice.close()
	# A local strip of 2 (fixture) for any fair game: two plays, no payment
	var fake_tx := "0x" + "57a1b5".repeat(10) + "0000"
	AP.add_credit(_wallet, q, fake_tx, PROBE_BLOCK, TC.FAIR_ANY, 2)
	fair._update_plaques()
	fair._focus_key = "?"
	for i in 3:
		await process_frame
	prompt = fair._hud.prompt.text
	_check(prompt.contains("strip: 2 plays left"), "the prompt shows the plays left: %s" % prompt)
	_check(plaque != null and plaque.text.contains("YOUR STRIP: 2 PLAYS LEFT"), "the plaque shows them: %s" % (plaque.text.replace("\n", " | ") if plaque else "—"))
	for play in 2:
		await _press("interact")
		var mp = fair._game
		_check(mp != null and mp.paid and int(mp.ticket.get("index", -9)) == play and String(mp.ticket.get("hash", "")) == fake_tx,
			"strip play #%d starts without a payment (%s)" % [play, str(mp.ticket) if mp else "no game"])
		if mp == null:
			break
		_check(mp.sim.seed_v == MG.seed_from_tx(TC.seed_tx(fake_tx, play)), "play #%d is seeded by SHA-256(\"<tx>#%d\")" % [play, play])
		var t1 := Time.get_ticks_msec()
		while not mp.seat.is_inside() and Time.get_ticks_msec() - t1 < 5000:
			await process_frame
		await _press("interact")
		await _play_round(mp)
		var line: String = FB.line_text(game, mp.sim.score, fake_tx, mp.sim.events, int(mp.ticket["index"]))
		var p: Dictionary = FB.parse(line)
		_check(int(p.get("index", -1)) == play and MidwaySim.replay(game, FB.seed_of(p), p["log"]) == mp.sim.score,
			"its room line names %s#%d and replays to %d (%d chars)" % [fake_tx.left(10), play, mp.sim.score, line.length()])
		if mp.phase == "celebrate":
			await _press("interact")
		await _press("interact")  # leave the result screen
		t1 = Time.get_ticks_msec()
		while fair._game != null and Time.get_ticks_msec() - t1 < 5000:
			await process_frame
		for i in 5:
			await process_frame
		_check(fair.plays_left(game) == 1 - play, "plays left after #%d: %d" % [play, fair.plays_left(game)])
	choice = TCH.current()
	_check(choice != null and String(choice.get_child(0).get_child(0).text).contains("USED UP"), "the strip's last play: the next strip is offered")
	if choice:
		choice.close()
	# Put the ledger back
	var back := ConfigFile.new()
	back.load(AP.LEDGER)
	if had:
		back.set_value("credits", ledger_key, saved_list)
	elif back.has_section_key("credits", ledger_key):
		back.erase_section_key("credits", ledger_key)
	back.save(AP.LEDGER)
	for f in kept:
		if kept[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_buffer(kept[f])
			fa.close()
	wallet_node.address = ""
	fair.refresh_progress()
	player.global_position += Vector3(0, 0, 30)
	for i in 5:
		await physics_frame


## Plays a started round through like a human-ish player.
func _play_round(mp) -> void:
	var t1 := Time.get_ticks_msec()
	var presses := 0
	while mp.phase == "play" and Time.get_ticks_msec() - t1 < 60000:
		if mp.sim.accepts() and (mp.sim.phase_t > 24 or mp.sim.game == "motzkin" and mp.sim.tick % 23 == 0):
			mp.set_aim(Vector2((presses * 97) % 600 - 300, (presses * 53) % 400 - 200))
			await _press("table_shoot" if presses % 2 == 0 else "interact")
			presses += 1
		await process_frame


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
