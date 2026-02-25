extends Node3D
## Lunar Cantina — social pub building with bar, tables, game tables, and neon sign.
## Procedural from territory seed, follows same pattern as monument.gd / beat_station.gd.

signal player_entered_range
signal player_exited_range
signal player_entered_interior
signal player_exited_interior
signal game_table_interacted(table_index: int)

var _params: Dictionary
var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _furniture_mat: StandardMaterial3D
var _bar_mat: StandardMaterial3D
var _game_table_mats: Array[StandardMaterial3D] = []
var _sign_shader: ShaderMaterial
var _display_shader: ShaderMaterial

var _proximity_area: Area3D
var _interior_area: Area3D
var _game_table_areas: Array[Area3D] = []
var _glow_light: OmniLight3D
var _sign_light: OmniLight3D
var _interior_lights: Array[OmniLight3D] = []

var _player_in_range: bool = false
var _player_inside: bool = false
var _player_near_table: int = -1  # Index of game table player is near (-1 = none)


func initialize(seed_value: int) -> void:
	_params = PubGenerator.get_pub_params(seed_value)
	_create_materials()
	_build_foundation()
	_build_walls()
	_build_roof()
	_build_doorway()
	_build_bar_counter()
	_build_bar_stools()
	_build_tables()
	_build_game_tables()
	_build_neon_sign()
	_build_display_screen()
	_build_interior_lights()
	_build_interaction_areas()


func _process(delta: float) -> void:
	# Update shaders
	var t := Time.get_ticks_msec() / 1000.0
	if _sign_shader:
		_sign_shader.set_shader_parameter("time", t)
	if _display_shader:
		_display_shader.set_shader_parameter("time", t)


func _create_materials() -> void:
	var accent: Color = _params["accent_color"]
	var accent_dark: Color = _params["accent_dark"]

	# Walls — dark metallic
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.12, 0.12, 0.16)
	_wall_mat.roughness = 0.75
	_wall_mat.metallic = 0.2

	# Floor — slightly lighter
	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.18, 0.17, 0.20)
	_floor_mat.roughness = 0.6
	_floor_mat.metallic = 0.3

	# Accent — colored trim
	_accent_mat = StandardMaterial3D.new()
	_accent_mat.albedo_color = accent
	_accent_mat.roughness = 0.4
	_accent_mat.metallic = 0.5
	_accent_mat.emission_enabled = true
	_accent_mat.emission = accent
	_accent_mat.emission_energy_multiplier = 0.3

	# Furniture — warm wood-like
	_furniture_mat = StandardMaterial3D.new()
	_furniture_mat.albedo_color = Color(0.25, 0.18, 0.12)
	_furniture_mat.roughness = 0.8
	_furniture_mat.metallic = 0.05

	# Bar counter — polished dark
	_bar_mat = StandardMaterial3D.new()
	_bar_mat.albedo_color = Color(0.08, 0.06, 0.04)
	_bar_mat.roughness = 0.3
	_bar_mat.metallic = 0.4

	# Game table surfaces — distinct colors per table
	var game_colors := [
		Color(0.15, 0.5, 0.15),  # Green felt (dice)
		Color(0.5, 0.12, 0.12),  # Red felt (slots)
		Color(0.12, 0.2, 0.5),   # Blue felt (trivia)
		Color(0.4, 0.3, 0.12),   # Gold felt (cards)
	]
	for gc in game_colors:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = gc
		mat.roughness = 0.85
		mat.metallic = 0.05
		_game_table_mats.append(mat)

	# Neon sign shader
	var neon_shader = load("res://assets/shaders/neon_sign.gdshader")
	if neon_shader:
		_sign_shader = ShaderMaterial.new()
		_sign_shader.shader = neon_shader
		_sign_shader.set_shader_parameter("sign_color", Vector3(
			_params["sign_color"].r, _params["sign_color"].g, _params["sign_color"].b))
	else:
		push_warning("[PubBuilding] Failed to load neon_sign.gdshader")

	# Display screen shader
	var display_shader = load("res://assets/shaders/pub_display.gdshader")
	if display_shader:
		_display_shader = ShaderMaterial.new()
		_display_shader.shader = display_shader
	else:
		push_warning("[PubBuilding] Failed to load pub_display.gdshader")


func _build_foundation() -> void:
	var w: float = _params["room_width"] * 0.5 + 1.5
	var d: float = _params["room_depth"] * 0.5 + 1.5
	var step_h: float = 0.15

	# Two-step platform
	for i in range(2):
		var shrink := float(i) * 0.3
		var mesh := BoxMesh.new()
		mesh.size = Vector3((w - shrink) * 2.0, step_h, (d - shrink) * 2.0)
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _floor_mat
		inst.position = Vector3(0, step_h * 0.5 + step_h * float(i), 0)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(inst)


func _build_walls() -> void:
	var w: float = _params["room_width"] * 0.5
	var d: float = _params["room_depth"] * 0.5
	var h: float = _params["wall_height"]
	var base_y: float = 0.3 + h * 0.5
	var thickness: float = 0.25

	# Back wall (full)
	_add_box(Vector3(w * 2.0, h, thickness), Vector3(0, base_y, -d), _wall_mat)

	# Left wall
	_add_box(Vector3(thickness, h, d * 2.0), Vector3(-w, base_y, 0), _wall_mat)

	# Right wall
	_add_box(Vector3(thickness, h, d * 2.0), Vector3(w, base_y, 0), _wall_mat)

	# Front wall — two sections with gap for doorway (3m wide)
	var door_half: float = 1.5
	var side_w: float = (w - door_half)
	if side_w > 0.5:
		# Left section
		_add_box(Vector3(side_w, h, thickness),
			Vector3(-w + side_w * 0.5, base_y, d), _wall_mat)
		# Right section
		_add_box(Vector3(side_w, h, thickness),
			Vector3(w - side_w * 0.5, base_y, d), _wall_mat)

	# Lintel above door
	_add_box(Vector3(door_half * 2.0 + 0.5, 0.3, thickness),
		Vector3(0, 0.3 + h - 0.15, d), _accent_mat)

	# Accent strip along base of all walls
	_add_box(Vector3(w * 2.0 + 0.1, 0.08, thickness + 0.02),
		Vector3(0, 0.3 + 0.04, -d), _accent_mat)
	_add_box(Vector3(thickness + 0.02, 0.08, d * 2.0 + 0.1),
		Vector3(-w, 0.3 + 0.04, 0), _accent_mat)
	_add_box(Vector3(thickness + 0.02, 0.08, d * 2.0 + 0.1),
		Vector3(w, 0.3 + 0.04, 0), _accent_mat)


func _build_roof() -> void:
	var w: float = _params["room_width"] * 0.5 + 0.3
	var d: float = _params["room_depth"] * 0.5 + 0.3
	var h: float = _params["wall_height"] + 0.3
	var style: int = _params["roof_style"]

	if style == 0:
		# Flat slab
		_add_box(Vector3(w * 2.0, 0.2, d * 2.0), Vector3(0, h, 0), _wall_mat)
	elif style == 1:
		# Dome — use a squashed sphere
		var mesh := SphereMesh.new()
		mesh.radius = maxf(w, d)
		mesh.height = 2.5
		mesh.radial_segments = 24
		mesh.rings = 12
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _wall_mat
		inst.position = Vector3(0, h - 0.5, 0)
		inst.scale = Vector3(w / maxf(w, d), 1.0, d / maxf(w, d))
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(inst)
	else:
		# Vault — elongated half-cylinder
		var mesh := CylinderMesh.new()
		mesh.top_radius = d + 0.5
		mesh.bottom_radius = d + 0.5
		mesh.height = w * 2.0
		mesh.radial_segments = 16
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _wall_mat
		inst.position = Vector3(0, h - 0.3, 0)
		inst.rotation_degrees = Vector3(0, 0, 90)  # Rotate to span width
		inst.scale = Vector3(1.0, 1.0, 0.4)  # Squash into half-cylinder look
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(inst)


func _build_doorway() -> void:
	var d: float = _params["room_depth"] * 0.5

	# Threshold accent strip
	_add_box(Vector3(3.2, 0.05, 0.5), Vector3(0, 0.31, d + 0.2), _accent_mat)


func _build_bar_counter() -> void:
	var bar_len: float = _params["bar_length"]
	var bar_h: float = _params["bar_height"]
	var d: float = _params["room_depth"] * 0.5

	# Main bar top (long counter along back-left)
	_add_box(Vector3(bar_len, 0.08, 0.6),
		Vector3(-bar_len * 0.2, 0.3 + bar_h, -d + 1.5), _bar_mat)

	# Bar front panel
	_add_box(Vector3(bar_len, bar_h - 0.1, 0.08),
		Vector3(-bar_len * 0.2, 0.3 + (bar_h - 0.1) * 0.5, -d + 1.8), _wall_mat)

	# Bar back panel (shelving)
	_add_box(Vector3(bar_len, bar_h + 0.5, 0.08),
		Vector3(-bar_len * 0.2, 0.3 + (bar_h + 0.5) * 0.5, -d + 0.5), _wall_mat)

	# Accent strip on bar edge
	_add_box(Vector3(bar_len + 0.1, 0.04, 0.62),
		Vector3(-bar_len * 0.2, 0.3 + bar_h + 0.04, -d + 1.5), _accent_mat)

	# A few "bottles" on back shelf (small cylinders)
	for i in range(5):
		var bx := -bar_len * 0.2 - bar_len * 0.3 + float(i) * bar_len * 0.15
		var bottle := CylinderMesh.new()
		bottle.top_radius = 0.04
		bottle.bottom_radius = 0.06
		bottle.height = 0.3
		var binst := MeshInstance3D.new()
		binst.mesh = bottle
		binst.material_override = _accent_mat
		binst.position = Vector3(bx, 0.3 + bar_h + 0.15, -d + 0.5)
		add_child(binst)


func _build_bar_stools() -> void:
	var count: int = _params["stool_count"]
	var bar_len: float = _params["bar_length"]
	var d: float = _params["room_depth"] * 0.5
	var spacing: float = bar_len / float(count + 1)

	for i in range(count):
		var sx := -bar_len * 0.2 - bar_len * 0.5 + spacing * float(i + 1)
		var sz := -d + 2.4

		# Seat (cylinder)
		var seat := CylinderMesh.new()
		seat.top_radius = 0.18
		seat.bottom_radius = 0.18
		seat.height = 0.06
		var sinst := MeshInstance3D.new()
		sinst.mesh = seat
		sinst.material_override = _furniture_mat
		sinst.position = Vector3(sx, 0.3 + 0.7, sz)
		add_child(sinst)

		# Leg (thin cylinder)
		var leg := CylinderMesh.new()
		leg.top_radius = 0.03
		leg.bottom_radius = 0.04
		leg.height = 0.68
		var linst := MeshInstance3D.new()
		linst.mesh = leg
		linst.material_override = _accent_mat
		linst.position = Vector3(sx, 0.3 + 0.34, sz)
		add_child(linst)

		# Foot ring (torus)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.12
		ring.outer_radius = 0.15
		var rinst := MeshInstance3D.new()
		rinst.mesh = ring
		rinst.material_override = _accent_mat
		rinst.position = Vector3(sx, 0.3 + 0.25, sz)
		rinst.scale = Vector3(1.0, 0.3, 1.0)
		add_child(rinst)


func _build_tables() -> void:
	var count: int = _params["table_count"]
	var w: float = _params["room_width"] * 0.5
	var d: float = _params["room_depth"] * 0.5

	# Place tables in the right side of the room
	for i in range(count):
		var tx: float = w * 0.4 + float(i % 2) * 2.5 - 1.0
		var tz: float = -d + 3.0 + float(i / 2) * 3.0

		# Table top (cylinder = round table)
		var top := CylinderMesh.new()
		top.top_radius = 0.5
		top.bottom_radius = 0.5
		top.height = 0.05
		var tinst := MeshInstance3D.new()
		tinst.mesh = top
		tinst.material_override = _furniture_mat
		tinst.position = Vector3(tx, 0.3 + 0.75, tz)
		add_child(tinst)

		# Table leg
		var leg := CylinderMesh.new()
		leg.top_radius = 0.05
		leg.bottom_radius = 0.06
		leg.height = 0.73
		var linst := MeshInstance3D.new()
		linst.mesh = leg
		linst.material_override = _wall_mat
		linst.position = Vector3(tx, 0.3 + 0.365, tz)
		add_child(linst)

		# 2 chairs per table
		for c in range(2):
			var cx := tx + (0.7 if c == 0 else -0.7)
			_add_chair(Vector3(cx, 0.3, tz))


func _build_game_tables() -> void:
	var count: int = _params["game_table_count"]
	var w: float = _params["room_width"] * 0.5
	var d: float = _params["room_depth"] * 0.5

	# Place game tables along the left side
	for i in range(count):
		var gx: float = -w * 0.4
		var gz: float = -d + 3.5 + float(i) * 2.8

		# Table top with colored felt
		var top := BoxMesh.new()
		top.size = Vector3(1.2, 0.06, 0.8)
		var tinst := MeshInstance3D.new()
		tinst.mesh = top
		var mat_idx := mini(i, _game_table_mats.size() - 1)
		tinst.material_override = _game_table_mats[mat_idx]
		tinst.position = Vector3(gx, 0.3 + 0.78, gz)
		add_child(tinst)

		# Table frame
		_add_box(Vector3(1.24, 0.08, 0.84), Vector3(gx, 0.3 + 0.74, gz), _wall_mat)

		# 4 legs
		for lx in [-0.5, 0.5]:
			for lz in [-0.3, 0.3]:
				var leg := CylinderMesh.new()
				leg.top_radius = 0.03
				leg.bottom_radius = 0.03
				leg.height = 0.72
				var linst := MeshInstance3D.new()
				linst.mesh = leg
				linst.material_override = _wall_mat
				linst.position = Vector3(gx + lx, 0.3 + 0.36, gz + lz)
				add_child(linst)

		# Interaction area for this game table
		var area := Area3D.new()
		area.name = "GameTable%d" % i
		var coll := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 2.0
		coll.shape = shape
		area.add_child(coll)
		area.position = Vector3(gx, 0.3 + 1.0, gz)
		add_child(area)
		_game_table_areas.append(area)

		var table_idx := i
		area.body_entered.connect(func(body: Node3D):
			if body.is_in_group("player"):
				_player_near_table = table_idx)
		area.body_exited.connect(func(body: Node3D):
			if body.is_in_group("player") and _player_near_table == table_idx:
				_player_near_table = -1)


func _build_neon_sign() -> void:
	var d: float = _params["room_depth"] * 0.5
	var h: float = _params["wall_height"]

	# Sign backing (dark panel)
	_add_box(Vector3(4.0, 0.8, 0.1), Vector3(0, h + 0.9, d + 0.2), _wall_mat)

	# Sign text (Label3D)
	var label := Label3D.new()
	label.text = "LUNAR CANTINA"
	label.font_size = 72
	label.modulate = _params["sign_color"]
	label.position = Vector3(0, h + 0.9, d + 0.28)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	add_child(label)

	# Sign glow light
	_sign_light = OmniLight3D.new()
	_sign_light.light_color = _params["sign_color"]
	_sign_light.light_energy = 2.5
	_sign_light.omni_range = 12.0
	_sign_light.position = Vector3(0, h + 0.9, d + 1.0)
	_sign_light.shadow_enabled = false
	add_child(_sign_light)


func _build_display_screen() -> void:
	var d: float = _params["room_depth"] * 0.5
	var h: float = _params["wall_height"]

	# Large display screen on back wall
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 1.8)
	var inst := MeshInstance3D.new()
	inst.mesh = quad
	if _display_shader:
		inst.material_override = _display_shader
	inst.position = Vector3(0, 0.3 + h * 0.55, -d + 0.14)
	add_child(inst)


func _build_interior_lights() -> void:
	var w: float = _params["room_width"] * 0.5
	var d: float = _params["room_depth"] * 0.5
	var h: float = _params["wall_height"]

	# Warm ceiling lights (3 evenly spaced)
	for i in range(3):
		var lx := -w * 0.5 + float(i) * w * 0.5
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6)  # Warm
		light.light_energy = 1.8
		light.omni_range = 8.0
		light.position = Vector3(lx, h - 0.3, 0)
		light.shadow_enabled = false
		add_child(light)
		_interior_lights.append(light)

		# Light fixture (small sphere)
		var fixture := SphereMesh.new()
		fixture.radius = 0.1
		var finst := MeshInstance3D.new()
		finst.mesh = fixture
		finst.material_override = _accent_mat
		finst.position = Vector3(lx, h - 0.25, 0)
		add_child(finst)


func _build_interaction_areas() -> void:
	# Proximity area (exterior detection — 20m radius)
	_proximity_area = Area3D.new()
	_proximity_area.name = "PubProximity"
	var prox_coll := CollisionShape3D.new()
	var prox_shape := SphereShape3D.new()
	prox_shape.radius = 20.0
	prox_coll.shape = prox_shape
	_proximity_area.add_child(prox_coll)
	_proximity_area.position = Vector3(0, 2.0, 0)
	add_child(_proximity_area)
	_proximity_area.body_entered.connect(_on_proximity_entered)
	_proximity_area.body_exited.connect(_on_proximity_exited)

	# Interior area (inside the building — box matching room)
	_interior_area = Area3D.new()
	_interior_area.name = "PubInterior"
	var int_coll := CollisionShape3D.new()
	var int_shape := BoxShape3D.new()
	var w: float = _params["room_width"] * 0.5
	var d: float = _params["room_depth"] * 0.5
	var h: float = _params["wall_height"]
	int_shape.size = Vector3(w * 2.0 - 0.5, h, d * 2.0 - 0.5)
	int_coll.shape = int_shape
	_interior_area.add_child(int_coll)
	_interior_area.position = Vector3(0, 0.3 + h * 0.5, 0)
	add_child(_interior_area)
	_interior_area.body_entered.connect(_on_interior_entered)
	_interior_area.body_exited.connect(_on_interior_exited)

	# Static body for walls/floor collision
	var static_body := StaticBody3D.new()
	static_body.name = "PubCollision"
	add_child(static_body)

	# Floor collision
	var floor_coll := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(w * 2.0 + 3.0, 0.3, d * 2.0 + 3.0)
	floor_coll.shape = floor_shape
	floor_coll.position = Vector3(0, 0.15, 0)
	static_body.add_child(floor_coll)

	# Wall collisions
	var thickness: float = 0.25
	# Back wall
	_add_wall_collision(static_body, Vector3(w * 2.0, h, thickness), Vector3(0, 0.3 + h * 0.5, -d))
	# Left wall
	_add_wall_collision(static_body, Vector3(thickness, h, d * 2.0), Vector3(-w, 0.3 + h * 0.5, 0))
	# Right wall
	_add_wall_collision(static_body, Vector3(thickness, h, d * 2.0), Vector3(w, 0.3 + h * 0.5, 0))
	# Front wall sections (with doorway gap)
	var door_half: float = 1.5
	var side_w: float = (w - door_half)
	if side_w > 0.5:
		_add_wall_collision(static_body, Vector3(side_w, h, thickness),
			Vector3(-w + side_w * 0.5, 0.3 + h * 0.5, d))
		_add_wall_collision(static_body, Vector3(side_w, h, thickness),
			Vector3(w - side_w * 0.5, 0.3 + h * 0.5, d))


func _add_wall_collision(parent: StaticBody3D, sz: Vector3, pos: Vector3) -> void:
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	coll.shape = shape
	coll.position = pos
	parent.add_child(coll)


func _add_chair(pos: Vector3) -> void:
	# Seat
	_add_box(Vector3(0.35, 0.04, 0.35), pos + Vector3(0, 0.45, 0), _furniture_mat)
	# Back
	_add_box(Vector3(0.35, 0.35, 0.04), pos + Vector3(0, 0.65, -0.15), _furniture_mat)
	# 4 legs
	for lx in [-0.13, 0.13]:
		for lz in [-0.13, 0.13]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.015
			leg.bottom_radius = 0.015
			leg.height = 0.43
			var linst := MeshInstance3D.new()
			linst.mesh = leg
			linst.material_override = _wall_mat
			linst.position = pos + Vector3(lx, 0.215, lz)
			add_child(linst)


func _add_box(sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)
	return inst


func update_territory_state() -> void:
	var power: float = 0.0
	if GameManager.has_territory_state:
		power = clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)

	# Interior lights scale with power
	for light in _interior_lights:
		light.light_energy = 1.0 + power * 2.0

	# Display screen territory power
	if _display_shader:
		_display_shader.set_shader_parameter("territory_power", power)

	# Sign glow
	if _sign_light:
		_sign_light.light_energy = 1.5 + power * 2.0


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
	var names := ["Entropy Dice", "WAAT Slots", "Territory Trivia", "Card Match"]
	if table_idx >= 0 and table_idx < names.size():
		return names[table_idx]
	return "Minigame"
