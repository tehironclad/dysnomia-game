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
