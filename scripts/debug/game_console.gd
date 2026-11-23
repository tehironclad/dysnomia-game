class_name GameConsole
## Registers Dysnomia-specific debug commands with the Console singleton.
## Created by main.gd and given references to player, terrain, etc.

var _player: CharacterBody3D
var _terrain_material: ShaderMaterial
var _sky_material: ShaderMaterial


func initialize(player: CharacterBody3D, terrain_mat: ShaderMaterial, sky_mat: ShaderMaterial) -> void:
	_player = player
	_terrain_material = terrain_mat
	_sky_material = sky_mat
	_register_commands()


func _register_commands() -> void:
	var console := Engine.get_singleton("Console") if Engine.has_singleton("Console") else null
	if console == null:
		console = _get_console_autoload()
	if console == null:
		push_warning("GameConsole: Console autoload not found, skipping command registration.")
		return

	console.create_command("tp", _cmd_teleport, "Teleport player to X Z coordinates.")
	console.create_command("time", _cmd_time, "Set time of day (0.0 to 1.0).")
	console.create_command("power", _cmd_power, "Set territory power (0.0 to 1.0).")
	console.create_command("activity", _cmd_activity, "Set territory activity (0.0 to 1.0).")
	console.create_command("clouds", _cmd_clouds, "Set cloud density (0.0 to 1.0).")
	console.create_command("fog", _cmd_fog, "Toggle fog (on/off).")
	console.create_command("fps", _cmd_fps, "Show current FPS.")
	console.create_command("pos", _cmd_pos, "Print player position.")
	console.create_command("seed", _cmd_seed, "Print current terrain seed.")
	console.create_command("gravity", _cmd_gravity, "Set gravity multiplier.")
	console.create_command("speed", _cmd_speed, "Set day cycle speed.")
	console.create_command("wallet", _cmd_wallet, "Print connected wallet address.")


func _get_console_autoload() -> Node:
	# Try to find Console in the scene tree
	var root := Engine.get_main_loop()
	if root is SceneTree:
		return root.root.get_node_or_null("/root/Console")
	return null


func _cmd_teleport(x: float, z: float) -> String:
	if not is_instance_valid(_player):
		return "Error: Player not available."
	_player.position = Vector3(x, _player.position.y + 5.0, z)
	return "Teleported to (%.1f, %.1f)" % [x, z]


func _cmd_time(t: float) -> String:
	GameManager.time_of_day = clampf(t, 0.0, 1.0)
	return "Time set to %.2f" % GameManager.time_of_day


func _cmd_power(p: float) -> String:
	p = clampf(p, 0.0, 1.0)
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("territory_power", p)
	return "Territory power set to %.2f" % p


func _cmd_activity(a: float) -> String:
	a = clampf(a, 0.0, 1.0)
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("territory_activity", a)
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter("atmo_activity", a)
	return "Territory activity set to %.2f" % a


func _cmd_clouds(d: float) -> String:
	d = clampf(d, 0.0, 1.0)
	if is_instance_valid(_sky_material):
		_sky_material.set_shader_parameter("cloud_density", d)
	if is_instance_valid(_terrain_material):
		_terrain_material.set_shader_parameter("cloud_shadow_density", d)
	return "Cloud density set to %.2f" % d


func _cmd_fog(state: String) -> String:
	var world_env := _find_world_environment()
	if world_env == null:
		return "Error: WorldEnvironment not found."
	if state == "on":
		world_env.environment.fog_enabled = true
		return "Fog enabled."
	elif state == "off":
		world_env.environment.fog_enabled = false
		return "Fog disabled."
	return "Usage: fog on|off"


func _cmd_fps() -> String:
	return "FPS: %.1f" % Performance.get_monitor(Performance.TIME_FPS)


func _cmd_pos() -> String:
	if not is_instance_valid(_player):
		return "Error: Player not available."
	var p := _player.global_position
	return "Position: (%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


func _cmd_seed() -> String:
	return "Territory: %s (%s); ground = its Julia set (JuliaHeightfield)" % [GameManager.territory_name, GameManager.territory_address]


func _cmd_gravity(g: float) -> String:
	# Modify the player's gravity scale if available
	return "Gravity multiplier: %.2f (restart required to take full effect)" % g


func _cmd_speed(s: float) -> String:
	GameManager.day_cycle_speed = maxf(s, 0.0)
	return "Day cycle speed: %.4f" % GameManager.day_cycle_speed


func _cmd_wallet() -> String:
	if Session.wallet.is_empty():
		return "No wallet connected."
	return "Wallet: %s\nLAU: %s" % [Session.wallet, Session.player.lau if Session.player else "—"]


func _find_world_environment() -> WorldEnvironment:
	var root: MainLoop = Engine.get_main_loop()
	if root is SceneTree:
		var tree: SceneTree = root as SceneTree
		var sky: Node = tree.root.get_node_or_null("Main/Sky")
		if sky:
			for child in sky.get_children():
				if child is WorldEnvironment:
					return child
	return null
