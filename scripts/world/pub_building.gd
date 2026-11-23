extends Node3D
## The QING's cantina — a lived-in moon-base bar. Procedural from the territory seed
## (PubGenerator → PubLayout), dressed with CC0 Poly Haven models and PBR textures.
##   pub/pub_shell.gd     building, roof, porch, signage, yard, collision
##   pub/pub_interior.gd  bar, bottles, drinks board, game tables, lounge, lights
##   pub/pub_life.gd      bartender + patrons, drink service and house-cheer moments
## Door faces local +Z. main.gd wires the signals below; an AttractionDirector drives
## bar_focus / play_drink_served / play_house_cheer.

signal player_entered_range
signal player_exited_range
signal player_entered_interior
signal player_exited_interior
signal game_table_interacted(table_index: int)
signal bar_focus(inside: bool)   ## Player stepped into / out of the ordering spot at the counter

const GAME_NAMES := ["Entropy Dice", "WAAT Slots", "Territory Trivia", "Card Match"]
const DEFAULT_SIGN := "LUNAR CANTINA"
const NPC_VISIBLE_RANGE := 55.0

var _params: Dictionary
var _layout: PubLayout
var _shell: PubShell
var _interior: PubInterior
var _life: PubLife
var _body: StaticBody3D

var _proximity_area: Area3D
var _interior_area: Area3D
var _bar_area: Area3D
var _game_table_areas: Array[Area3D] = []

var _player_in_range: bool = false
var _player_inside: bool = false
var _player_at_bar: bool = false
var _player_near_table: int = -1  # Index of game table player is near (-1 = none)

var _power: float = 0.0
var _sign_text: String = ""
var _blink_t: float = 0.0
var _cull_t: float = 0.0
var _hvac_fans: Array[Node3D] = []


func initialize(seed_value: int) -> void:
	_params = PubGenerator.get_pub_params(seed_value)
	_layout = PubLayout.new(_params)

	_body = StaticBody3D.new()
	_body.name = "PubCollision"
	add_child(_body)

	_shell = PubShell.new()
	_shell.build(self, _layout, _body)
	_interior = PubInterior.new()
	_interior.build(self, _layout, _body)

	_life = PubLife.new()
	add_child(_life)
	_life.setup(_layout, _interior, _shell.neon_nodes, int(_params["detail_seed"]) + 4242)

	for i in 2:
		var fan := find_child("HvacFan%d" % i, true, false)
		if fan:
			_hvac_fans.append(fan)

	_build_interaction_areas()
	_refresh_sign()
	if not GameManager.territory_data_changed.is_connected(_on_territory_data_changed):
		GameManager.territory_data_changed.connect(_on_territory_data_changed)
	update_territory_state()


func _process(delta: float) -> void:
	if _layout == null:
		return
	_blink_t += delta
	# Antenna beacon: short double-blink every 2 s
	if _shell.beacon:
		var ph := fmod(_blink_t, 2.0)
		_shell.beacon.visible = ph < 0.12 or (ph > 0.3 and ph < 0.42)
	for f in _hvac_fans:
		f.rotate_y(delta * 9.0)
	if _interior.display_material:
		_interior.display_material.set_shader_parameter("time", _blink_t)
	# Only animate the crowd when someone could see it
	_cull_t -= delta
	if _cull_t <= 0.0:
		_cull_t = 0.5
		var cam := get_viewport().get_camera_3d()
		if cam and _life:
			var near := cam.global_position.distance_to(global_position) < NPC_VISIBLE_RANGE
			if near != _life.visible:
				_life.set_active(near)


# ─── Sign ──────────────────────────────────────────────────────────────────

static func sign_name_for(territory: String) -> String:
	## "Sunny QING" → "SUNNY'S CANTINA"; empty/offline → "LUNAR CANTINA".
	var n := territory.strip_edges()
	if n.to_upper().ends_with(" QING"):
		n = n.substr(0, n.length() - 5).strip_edges()
	elif n.to_upper() == "QING":
		n = ""
	if n.is_empty():
		return DEFAULT_SIGN
	n = n.to_upper()
	if n.ends_with("S"):
		return n + "' CANTINA"
	return n + "'S CANTINA"


func get_sign_text() -> String:
	return _sign_text


func _refresh_sign() -> void:
	var t := sign_name_for(GameManager.territory_name)
	if t == _sign_text:
		return
	_sign_text = t
	_shell.set_sign_text(t)


func _on_territory_data_changed(_data: Dictionary) -> void:
	_refresh_sign()


# ─── AttractionDirector hooks ──────────────────────────────────────────────

func play_drink_served(drink_id: String) -> void:
	## Bartender pours at the taps and slides a glowing glass down to the ordering spot.
	if _life:
		_life.play_drink_served(drink_id)


func play_house_cheer() -> void:
	## Round for the house: patrons hop and turn to the bar, lights flare, neon blinks, confetti.
	if _life == null:
		return
	var lights: Array[OmniLight3D] = _interior.lights.duplicate()
	var base: Array[float] = []
	for e in _interior.light_base:
		base.append(e * (0.75 + _power * 0.6))
	lights.append(_shell.sign_light)
	base.append(_shell.sign_light.light_energy)
	_life.play_house_cheer(lights, base)


func is_player_at_bar() -> bool:
	return _player_at_bar


# ─── Territory state ───────────────────────────────────────────────────────

func update_territory_state() -> void:
	if _interior == null:
		return
	_power = 0.0
	if GameManager.has_territory_state:
		_power = clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	# Interior rig brightens with territory power
	for i in _interior.lights.size():
		_interior.lights[i].light_energy = _interior.light_base[i] * (0.75 + _power * 0.6)
	if _interior.display_material:
		_interior.display_material.set_shader_parameter("territory_power", _power)
	if _shell.sign_light:
		_shell.sign_light.light_energy = 2.0 + _power * 1.5


# ─── Interaction areas ─────────────────────────────────────────────────────

func _build_interaction_areas() -> void:
	var L := _layout
	var fy := PubLayout.FY
	# Proximity (exterior detection — 20 m radius)
	_proximity_area = _make_area("PubProximity", _sphere_shape(20.0), Vector3(0, 2.0, 0))
	_proximity_area.body_entered.connect(_on_proximity_entered)
	_proximity_area.body_exited.connect(_on_proximity_exited)

	# Interior (the room itself)
	# Extends below the floor so a capsule standing on it never flickers in/out
	_interior_area = _make_area("PubInterior", _box_shape(Vector3(L.w * 2.0 - 0.4, L.h + 0.6, L.d * 2.0 - 0.3)),
		Vector3(0, fy + L.h * 0.5 - 0.3, 0))
	_interior_area.body_entered.connect(_on_interior_entered)
	_interior_area.body_exited.connect(_on_interior_exited)

	# Ordering spot in front of the counter (the gap between the stools)
	_bar_area = _make_area("BarOrderZone", _box_shape(Vector3(2.4, 2.0, 1.5)),
		Vector3(L.order_x, fy + 1.0, L.counter_front + 0.85))
	_bar_area.body_entered.connect(func(body: Node3D):
		if body.is_in_group("player") and not _player_at_bar:
			_player_at_bar = true
			bar_focus.emit(true))
	_bar_area.body_exited.connect(func(body: Node3D):
		if body.is_in_group("player") and _player_at_bar:
			_player_at_bar = false
			bar_focus.emit(false))

	# Game tables — the open (+Z) side is where you step up to play
	for i in L.game_tables.size():
		var gp: Vector3 = L.game_tables[i]
		var area := _make_area("GameTable%d" % i, _box_shape(Vector3(2.4, 2.0, 2.2)), gp + Vector3(0, 1.0, 0.6))
		_game_table_areas.append(area)
		var table_idx := i
		area.body_entered.connect(func(body: Node3D):
			if body.is_in_group("player"):
				_player_near_table = table_idx)
		area.body_exited.connect(func(body: Node3D):
			if body.is_in_group("player") and _player_near_table == table_idx:
				_player_near_table = -1)


func _make_area(n: String, shape: Shape3D, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = n
	a.monitorable = false
	var c := CollisionShape3D.new()
	c.shape = shape
	a.add_child(c)
	a.position = pos
	add_child(a)
	return a


func _sphere_shape(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _on_proximity_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		player_entered_range.emit()


func _on_proximity_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		player_exited_range.emit()


func _on_interior_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		player_entered_interior.emit()


func _on_interior_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		player_exited_interior.emit()


func is_player_near_game_table() -> bool:
	return _player_near_table >= 0


func get_near_table_index() -> int:
	return _player_near_table


func interact_game_table() -> void:
	## Called when player presses E near a game table. Emits the interaction signal.
	if _player_near_table >= 0:
		game_table_interacted.emit(_player_near_table)


func get_game_name_for_table(table_idx: int) -> String:
	## Return the minigame name for a given table index.
	if table_idx >= 0 and table_idx < GAME_NAMES.size():
		return GAME_NAMES[table_idx]
	return "Minigame"
