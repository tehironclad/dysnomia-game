extends SceneTree
## Headless logic test for the attraction flow:
##   godot --headless --path . -s tools/test_attractions.gd
## Loads main.tscn, adds a test ride, walks the player into its booth, presses interact
## (offline → free preview), lets the ride run, and checks the player is set back down.

class TestRide extends RideBase:
	func _init() -> void:
		ride_id = "drop"
		booth_local_position = Vector3(0, 0, 6)
		exit_local_position = Vector3(3, 0.5, 6)
	func get_seat_transform(t: float) -> Transform3D:
		return Transform3D(Basis(), global_position + Vector3(0, 10.0 + t, 0))
	func ride_duration() -> float:
		return 1.5

var _main: Node
var _ride: TestRide
var _frames := 0
var _fails := 0
var _phase := 0
var _seen_high := false

func _initialize() -> void:
	_check("to_base_units 2.5/18", AffectionEconomy_to("2.5", 18) == "2500000000000000000")
	_check("to_base_units 1/18", AffectionEconomy_to("1", 18) == "1000000000000000000")
	_check("to_base_units 0.000001/6", AffectionEconomy_to("0.000001", 6) == "1")
	_check("to_base_units garbage", AffectionEconomy_to("abc", 18) == "0")
	change_scene_to_file.call_deferred("res://scenes/main.tscn")

func AffectionEconomy_to(a: String, d: int) -> String:
	return load("res://scripts/chain/affection_economy.gd").to_base_units(a, d)

func _check(name: String, ok: bool) -> void:
	print("[test] %s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1

func _process(_d: float) -> bool:
	_frames += 1
	if current_scene == null:
		return false
	var player: CharacterBody3D = current_scene.get("player")
	var director = current_scene.get("_attraction_director")
	if _phase == 0 and _frames > 5 and director:
		_check("director created", director != null)
		_check("attraction ui created", current_scene.get("_attraction_ui") != null)
		_check("player in group", player.is_in_group("player"))
		_ride = TestRide.new()
		current_scene.add_child(_ride)
		_ride.global_position = Vector3(30, current_scene.territory.get_height_at(30, 30), 30)
		_ride.setup(1)
		director.register_ride(_ride)
		_phase = 1
	elif _phase == 1 and _frames > 10:
		# Walk into the booth
		player.global_position = _ride.to_global(_ride.booth_local_position) + Vector3(0, 0.2, 0)
		_phase = 2
	elif _phase == 2 and _frames > 20:
		_check("ticket card shown in booth", current_scene._attraction_ui.is_ticket_visible())
		player._try_interact()
		_phase = 3
	elif _phase == 3:
		if _ride.is_riding() and player.global_position.y > _ride.global_position.y + 9.0:
			_seen_high = true
		if _frames > 400 or (_seen_high and not _ride.is_riding()):
			_check("ride started (preview) and carried player", _seen_high)
			_check("ride finished", not _ride.is_riding())
			_check("player physics restored", player.is_physics_processing())
			var exit := _ride.to_global(_ride.exit_local_position)
			_check("player set down at exit", player.global_position.distance_to(exit) < 2.0)
			_check("director idle", not director.is_riding())
			_test_paid_path()
			_test_standing()
			_test_travel_guards()
			_test_pub_bar()
			_test_boards()
			_phase = 4
			_frames = 0
	elif _phase == 4:
		if _frames == 1:
			var pad: Vector3 = Vector3(0, current_scene.territory.get_height_at(0, 100) + 1.0, 100)
			player.global_position = pad
		if _frames == 20:
			_check("shuttle terminal active on pad", current_scene._at_shuttle_terminal)
			_check("E at pad opens shuttle map", player._interact_handler.is_valid())
			print("[test] %s" % ("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails))
			quit(_fails)
	return false


func _test_paid_path() -> void:
	## Simulate a confirmed AFFECTION ticket: granted as "paid", then a state re-read
	## produces a bar report with the measured delta.
	var eco = root.get_node("ChainManager").economy
	var gm = root.get_node("GameManager")
	var got := {}
	eco.purchase_granted.connect(func(pid, item, mode): got["mode"] = mode, CONNECT_ONE_SHOT)
	eco.bar_report.connect(func(r): got["report"] = r, CONNECT_ONE_SHOT)
	gm.territory_hypobar = 1000
	gm.territory_epibar = 500
	gm.has_territory_state = true
	eco._track(9001, 77, AttractionCatalog.ride("rocket"))
	root.get_node("ChainManager").tx_confirmed.emit(9001, "0xabc")
	_check("paid ticket granted", got.get("mode", "") == "paid")
	gm.load_territory_state({"hypobar": 1250, "epibar": 480})
	var r: Dictionary = got.get("report", {})
	_check("bar report delta hypo +250", r.get("d_hypo", 0) == 250)
	_check("bar report delta epi -20", r.get("d_epi", 0) == -20)
	var ui = current_scene._attraction_ui
	ui.show_bar_report(r, "Test QING")
	_check("bar report card visible", ui._report.visible)


func _test_standing() -> void:
	var cm = root.get_node("ChainManager")
	var gm = root.get_node("GameManager")
	var st = current_scene._standing
	_check("standing node exists", st != null)
	_check("tier thresholds 0/149/150/400/750", _QS().tier_for_score(0)["tier"] == 0
		and _QS().tier_for_score(149)["tier"] == 0 and _QS().tier_for_score(150)["tier"] == 1
		and _QS().tier_for_score(400)["tier"] == 2 and _QS().tier_for_score(750)["tier"] == 3)
	# Quiet QING: nothing on-chain → Outpost, fair is just a surveyed lot
	gm.territory_address = "0x1111111111111111111111111111111111111111"
	gm.territory_charge = 0
	st.refresh()
	_check("quiet QING is tier 0", st.current()["tier"] == 0)
	# Activity from on-chain chat: 3 messages, 2 unique souls, one duplicate ignored
	var promoted := {}
	st.standing_changed.connect(func(s): promoted["tier"] = s["tier"])
	for m in [{"soul": "7", "username": "a", "message": "gm", "block": 1},
			{"soul": "7", "username": "a", "message": "gm again", "block": 2},
			{"soul": "9", "username": "b", "message": "hi", "block": 3},
			{"soul": "9", "username": "b", "message": "hi", "block": 3}]:
		cm._count_qing_activity(m)
	cm._emit_qing_activity(gm.territory_address.to_lower())
	var a: Dictionary = cm.get_qing_activity(gm.territory_address)
	_check("activity dedup: 3 messages", a["messages"] == 3)
	_check("activity unique visitors: 2", a["unique_visitors"] == 2)
	# A busy, terraformed QING: big charge + many visitors → top tiers
	gm.territory_charge = 900_000_000_000
	st._visitors = 12
	st._messages = 80
	st._keeper_hypo = 400_000_000_000
	st._keeper_epi = 300_000_000_000
	st.recompute()
	var s: Dictionary = st.current()
	print("[test] busy QING standing = ", s["score"], " tier ", s["tier"], " parts ", s["parts"])
	_check("busy QING reaches tier 3", s["tier"] == 3)
	_check("fair rebuilt at tier 3", current_scene._funfair != null and current_scene._fair_tier == 3)
	if current_scene._funfair:
		_check("tier 3 fair has 4 rides", current_scene._funfair.get_rides().size() == 4)
	_check("promotion signal fired", promoted.get("tier", -1) == 3)
	_check("console override works", current_scene.cmd_standing(1).contains("tier 1"))
	_check("tier 1 fair = carousel only", current_scene._funfair.get_rides().size() == 1)
	current_scene.cmd_standing(0)
	_check("tier 0 fair = surveyed lot, no rides", current_scene._funfair.get_rides().size() == 0)
	current_scene.cmd_standing(-1)
	_check("override cleared", st.current()["tier"] == 3)


func _QS() -> GDScript:
	return load("res://scripts/world/qing_standing.gd")


func _test_travel_guards() -> void:
	var gm = root.get_node("GameManager")
	var here: String = gm.territory_address
	var other := "0x2222222222222222222222222222222222222222"
	current_scene._at_shuttle_terminal = false
	current_scene._on_map_territory_selected(other)
	_check("no warping from the field", gm.territory_address == here)
	current_scene._at_shuttle_terminal = true
	current_scene._on_map_territory_selected(other)
	_check("no shuttle to unjoined QING", gm.territory_address == here)
	current_scene._at_shuttle_terminal = false
	var wm = current_scene.hud.world_map
	wm.set_travel_context(false, {other: true})
	_check("map knows joined QINGs", wm._is_joined(other) and not wm._is_joined(here))


func _test_pub_bar() -> void:
	var pub = current_scene._pub_building
	var ui = current_scene._attraction_ui
	_check("pub has bar_focus signal", pub.has_signal("bar_focus"))
	pub.bar_focus.emit(true)
	_check("bar menu opens at the bar", ui._menu.visible)
	pub.play_drink_served("rho_rocks")
	pub.play_drink_served("house_round")
	pub.play_house_cheer()
	_check("pub sign text", not pub.get_sign_text().is_empty())
	pub.bar_focus.emit(false)


func _test_boards() -> void:
	var feed = current_scene._board_feed
	var gm = root.get_node("GameManager")
	_check("5 media boards spawned", current_scene._media_boards.size() == 5)
	var BF = load("res://scripts/world/board_feed.gd")
	_check("1 AFFECTION in hex", BF._dec_to_hex("1000000000000000000") == "de0b6b3a7640000")
	var keeper := "0x" + "ab".repeat(20)
	var payer := "0x" + "cd".repeat(20)
	gm.territory_owner = keeper
	var token: String = root.get_node("ChainManager").AFFECTION_TOKEN_ADDRESS
	var rcpt := {"status": "0x1", "logs": [{"address": token.to_lower(), "data": "0x" + "de0b6b3a7640000".lpad(64, "0"),
		"topics": [BF.TRANSFER_TOPIC, "0x" + payer.substr(2).lpad(64, "0"), "0x" + keeper.substr(2).lpad(64, "0")]}]}
	_check("payment to keeper recognised", feed._paid_keeper(rcpt, keeper) == payer)
	var cheap := rcpt.duplicate(true)
	cheap["logs"][0]["data"] = "0x" + "1".lpad(64, "0")
	_check("underpayment rejected", feed._paid_keeper(cheap, keeper) == "")
	_check("payment to someone else rejected", feed._paid_keeper(rcpt, "0x" + "ee".repeat(20)) == "")
	var line: String = BF.format_post("fair", "0x" + "11".repeat(32), "gm fair", "https://example.org/a.png")
	_check("post line format", line.begins_with("[[BOARD v1 wing=fair pay=0x") and line.ends_with("|| https://example.org/a.png"))
	_check("http image rejected", not BF.valid_image_url("http://x/y.png"))
	var now := int(Time.get_unix_time_from_system())
	feed._accept({"wing": "fair", "pay": "0x" + "11".repeat(32), "caption": "gm fair", "url": "", "poster": "a", "chat_tx": "0x" + "21".repeat(32)}, payer, now - 60)
	feed._accept({"wing": "fair", "pay": "0x" + "11".repeat(32), "caption": "dupe", "url": "", "poster": "b", "chat_tx": "0x" + "22".repeat(32)}, payer, now - 30)
	feed._accept({"wing": "fair", "pay": "0x" + "12".repeat(32), "caption": "old", "url": "", "poster": "c", "chat_tx": "0x" + "23".repeat(32)}, payer, now - 90000)
	var posts: Array = feed.active_posts("fair")
	_check("fresh post shown once, stale and reused payments ignored", posts.size() == 1 and posts[0]["caption"] == "gm fair")
	feed._hidden["0x" + "11".repeat(32)] = true
	_check("keeper take-down hides post", feed.active_posts("fair").is_empty())
	# Walk up to the cantina board and open the form
	var board = current_scene._media_boards[0]
	board.board_focus.emit(board, true)
	_check("board card shown", current_scene._attraction_ui.is_ticket_visible())
	current_scene.player._try_interact()
	_check("E opens the post form", current_scene._board_post_ui.is_open())
	current_scene._board_post_ui.close()
	board.board_focus.emit(board, false)
