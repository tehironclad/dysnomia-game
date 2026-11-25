extends TestCase
## GameHowto (every game's instructions and controls): the countdown never runs short, hints
## become key chips, only real presses dismiss the card, the help key is bound and listed,
## and the card / strip behave (open, dismiss, Esc, help). No network.


func test_countdown_never_short() -> void:
	eq(GameHowto.countdown_seconds(2.0), GameHowto.MIN_COUNTDOWN, "a short countdown is lengthened")
	eq(GameHowto.countdown_seconds(9.0), 9.0)
	check(GameHowto.MIN_COUNTDOWN >= 6.0, "long enough to read")
	var t := GameHowto.countdown_text(6.2, "drive")
	check(t.contains("7"), "rounded up: " + t)
	check(t.contains("DRIVE"), t)
	check(GameHowto.countdown_text(0.01).contains(" 1 "), "never shows 0 while open: " + GameHowto.countdown_text(0.01))


func test_parse_hint() -> void:
	var rows := GameHowto.parse_hint("E / click: swing at the top of the meter   ·   Esc: leave")
	eq(rows.size(), 2)
	eq(rows[0], ["E / click", "swing at the top of the meter"])
	eq(rows[1], ["Esc", "leave"])
	var r2 := GameHowto.parse_hint("E  ride the wheel · just words")
	eq(r2[0], ["E", "Ride the wheel"], "a HudV2 prompt shape")
	eq(r2[1], ["", "just words"], "no key: words only")
	eq(GameHowto.parse_hint(""), [], "empty")


func test_presses() -> void:
	var k := InputEventKey.new()
	k.pressed = true
	check(GameHowto.is_press(k), "a key down")
	k.echo = true
	check(not GameHowto.is_press(k), "not a repeat")
	var up := InputEventKey.new()
	check(not GameHowto.is_press(up), "not a key up")
	var mb := InputEventMouseButton.new()
	mb.pressed = true
	mb.button_index = MOUSE_BUTTON_LEFT
	check(GameHowto.is_press(mb), "a click")
	mb.button_index = MOUSE_BUTTON_WHEEL_UP
	check(not GameHowto.is_press(mb), "not the wheel")
	check(not GameHowto.is_press(InputEventMouseMotion.new()), "not a mouse move")
	var act := InputEventAction.new()
	act.action = "interact"
	act.pressed = true
	check(GameHowto.is_press(act), "an action fed in (the probes)")


func test_help_key_bound_and_listed() -> void:
	check(InputMap.has_action(GameHowto.HELP_ACTION), "the help action exists")
	check(ControlsHelp.key_of(GameHowto.HELP_ACTION) != "—", "and is bound")
	var listed := false
	for a in ControlsHelp.ACTIONS:
		listed = listed or a[0] == GameHowto.HELP_ACTION
	check(listed, "listed in ControlsHelp.ACTIONS")
	# No other gameplay action shares its key
	var key := ControlsHelp.key_of(GameHowto.HELP_ACTION)
	for a in ControlsHelp.ACTIONS:
		if a[0] != GameHowto.HELP_ACTION:
			check(ControlsHelp.key_of(a[0]) != key, "%s shares the help key %s" % [a[0], key])


func test_card_and_strip() -> void:
	var h := GameHowto.new()
	h.setup({"title": "Striker", "rules": ["Swing at the top"], "controls": [["E", "swing"], ["Esc", "leave"]], "esc": "leave"})
	var opened := []
	var dismissed := []
	h.opened.connect(func(m): opened.append(m))
	h.dismissed.connect(func(m): dismissed.append(m))
	check(not h.is_card_open())
	h.open_card(GameHowto.Mode.KEY)
	check(h.is_card_open(), "open")
	eq(opened, [GameHowto.Mode.KEY])
	h.close_card()
	eq(dismissed, [GameHowto.Mode.KEY], "dismissed once")
	h.close_card()
	eq(dismissed.size(), 1, "closing twice signals once")
	h.open_card(GameHowto.Mode.COUNTDOWN, 1.0)
	eq(h.left, GameHowto.MIN_COUNTDOWN, "countdown lengthened to the minimum")
	h.end()
	check(not h.is_card_open(), "end closes")
	eq(dismissed.size(), 1, "end doesn't signal")
	h.show_strip(true)
	check(h.strip_visible(), "strip on")
	var rows := h._strip_rows()
	eq(rows[-1][1], "how to play", "the strip ends with the help key")
	h.set_strip([])
	check(h.strip_visible(), "an empty strip list falls back to the card's controls")
	h.show_strip(false)
	check(not h.strip_visible())
	h.free()


## Every game's controls name bound keys (no "—", nothing empty), and each says how to leave.
func _keys_ok(rows: Array, what: String) -> void:
	check(not rows.is_empty(), what + " lists controls")
	for r in rows:
		check(String(r[0]) != "" and not String(r[0]).contains("—"), "%s: %s has a bound key" % [what, str(r)])
		check(String(r[1]) != "", "%s: %s says what it does" % [what, str(r)])


func test_every_game_lists_its_controls() -> void:
	for id in MidwayGame.GAMES:
		var mp := MidwayPlay.new()
		mp.game = id
		var rows := mp.play_controls()
		_keys_ok(rows, "midway " + id)
		eq(rows[-1][0], "Esc", id + " ends with how to leave")
		mp.free()
	for kind in VehicleSpecs.KINDS:
		var rows := GarageSite.controls(kind)
		_keys_ok(rows, "vehicle " + kind)
		check(rows.any(func(r): return r[0] == ControlsHelp.key_of("vehicle_enter")), kind + ": how to get out")
	_keys_ok(RocketVoyage.controls(), "rocket voyage")
	_keys_ok(BaseJump.all_controls(), "base jump")
	for m in [JumpPhysics.Mode.FREEFALL, JumpPhysics.Mode.WINGSUIT, JumpPhysics.Mode.CANOPY]:
		_keys_ok(BaseJump.mode_controls(m), "base jump mode %d" % m)
	_keys_ok(FairSite.ride_controls(), "rides")
