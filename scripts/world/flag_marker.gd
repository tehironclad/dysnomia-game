extends Node3D
## A territory flag planted by a player.
## CylinderMesh pole + QuadMesh flag with waving animation shader.
## Label3D shows the planter's name and message.
## Color derived from wallet address hash.

const FLAG_SHADER = preload("res://assets/shaders/flag_cloth.gdshader")

var _wallet: String = ""
var _username: String = ""
var _message: String = ""
var _flag_color: Color = Color.RED
var _flag_mesh: MeshInstance3D
var _name_label: Label3D
var _message_label: Label3D


func initialize(data: Dictionary) -> void:
	## Build the flag from data dict:
	## {wallet, username, message, position: {x, y, z}, timestamp}
	_wallet = data.get("wallet", "")
	_username = data.get("username", "Explorer")
	_message = data.get("message", "")

	# Position
	var pos_data = data.get("position", {})
	if pos_data is Dictionary:
		position = Vector3(
			float(pos_data.get("x", 0.0)),
			float(pos_data.get("y", 0.0)),
			float(pos_data.get("z", 0.0))
		)

	# Derive flag color from wallet address hash
	_flag_color = _wallet_to_color(_wallet)

	_build_flag()


func _wallet_to_color(wallet: String) -> Color:
	## Deterministic color from wallet address (last 6 hex chars → RGB).
	if wallet.length() < 8:
		return Color(0.7, 0.3, 0.2)  # Default red-brown

	var hex_part := wallet.right(6)
	var r_hex := hex_part.substr(0, 2)
	var g_hex := hex_part.substr(2, 2)
	var b_hex := hex_part.substr(4, 2)

	var r := float("0x" + r_hex if r_hex.is_valid_hex_number(true) else "128") / 255.0
	var g := float("0x" + g_hex if g_hex.is_valid_hex_number(true) else "128") / 255.0
	var b := float("0x" + b_hex if b_hex.is_valid_hex_number(true) else "128") / 255.0

	# Boost saturation — make flags vibrant
	var hsv_h := Color(r, g, b).h
	var hsv_s := maxf(Color(r, g, b).s, 0.5)
	var hsv_v := maxf(Color(r, g, b).v, 0.5)
	return Color.from_hsv(hsv_h, hsv_s, hsv_v)


func _build_flag() -> void:
	# ─── Pole ─────────────────────────────────────────────────────────
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.03
	pole_mesh.bottom_radius = 0.04
	pole_mesh.height = 2.5
	pole_mesh.radial_segments = 6
	pole.mesh = pole_mesh
	pole.position.y = 1.25  # Center of pole

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.6, 0.6, 0.6)
	pole_mat.metallic = 0.7
	pole_mat.roughness = 0.3
	pole_mesh.surface_set_material(0, pole_mat)
	add_child(pole)

	# Pole top cap (small sphere)
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.06
	cap_mesh.height = 0.12
	cap_mesh.radial_segments = 8
	cap_mesh.rings = 4
	cap.mesh = cap_mesh
	cap.position.y = 2.5
	cap_mesh.surface_set_material(0, pole_mat)
	add_child(cap)

	# ─── Flag cloth ───────────────────────────────────────────────────
	_flag_mesh = MeshInstance3D.new()
	var flag_quad := QuadMesh.new()
	flag_quad.size = Vector2(1.2, 0.7)
	_flag_mesh.mesh = flag_quad
	_flag_mesh.position = Vector3(0.6, 2.1, 0.0)  # Offset from pole

	if FLAG_SHADER:
		var flag_mat := ShaderMaterial.new()
		flag_mat.shader = FLAG_SHADER
		flag_mat.set_shader_parameter("flag_color", Vector3(_flag_color.r, _flag_color.g, _flag_color.b))
		flag_mat.set_shader_parameter("wave_speed", 2.0)
		flag_mat.set_shader_parameter("wave_amplitude", 0.06)
		flag_mat.set_shader_parameter("wave_frequency", 4.0)
		flag_quad.surface_set_material(0, flag_mat)
	else:
		var fallback_mat := StandardMaterial3D.new()
		fallback_mat.albedo_color = _flag_color
		fallback_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flag_quad.surface_set_material(0, fallback_mat)

	_flag_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_flag_mesh)

	# ─── Name label ───────────────────────────────────────────────────
	_name_label = Label3D.new()
	_name_label.text = _username if not _username.is_empty() else _truncate_wallet(_wallet)
	_name_label.font_size = 40
	_name_label.outline_size = 8
	_name_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	_name_label.position = Vector3(0.0, 2.8, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.pixel_size = 0.005
	add_child(_name_label)

	# ─── Message label (below name) ───────────────────────────────────
	if not _message.is_empty():
		_message_label = Label3D.new()
		_message_label.text = '"%s"' % _message
		_message_label.font_size = 32
		_message_label.outline_size = 6
		_message_label.modulate = Color(0.9, 0.85, 0.7, 0.8)
		_message_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.6)
		_message_label.position = Vector3(0.0, 2.55, 0.0)
		_message_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_message_label.no_depth_test = true
		_message_label.pixel_size = 0.004
		_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message_label.width = 400.0
		add_child(_message_label)


func _truncate_wallet(wallet: String) -> String:
	if wallet.length() > 12:
		return wallet.left(6) + "..." + wallet.right(4)
	return wallet
