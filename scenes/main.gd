extends Node3D
## Main scene orchestrator. Initializes terrain, positions player,
## drives day/night cycle, and wires up shader parameters.

@onready var territory: Node3D = $Territory
@onready var territory_manager: Node3D = $TerritoryManager
@onready var player: CharacterBody3D = $Player
@onready var sky: Node3D = $Sky
@onready var hud: CanvasLayer = $HUD

const MonumentScript = preload("res://scripts/world/monument.gd")
const BeatStationScript = preload("res://scripts/world/beat_station.gd")
const CreatureSpawnerScript = preload("res://scripts/world/creature_spawner.gd")
const WeaponSystemScript = preload("res://scripts/player/weapon_system.gd")
const VehicleScript = preload("res://scripts/player/vehicle.gd")
const StatTrackerScript = preload("res://scripts/player/stat_tracker.gd")
const AchievementToastScript = preload("res://scripts/ui/achievement_toast.gd")
const MultiplayerManagerScript = preload("res://scripts/multiplayer/multiplayer_manager.gd")
const ConsoleContainerScript = preload("res://addons/godot_console/console_container.gd")
const MonitorOverlayScript = preload("res://scripts/debug/monitor_overlay.gd")
const GameConsoleScript = preload("res://scripts/debug/game_console.gd")
const PubBuildingScript = preload("res://scripts/world/pub_building.gd")
const DustParticlesScript = preload("res://scripts/world/dust_particles.gd")
const HeatShimmerScript = preload("res://scripts/world/heat_shimmer.gd")
const VegetationManagerScript = preload("res://scripts/world/vegetation_manager.gd")
const AtmosphericFogScript = preload("res://scripts/world/atmospheric_fog.gd")
const DustDevilSpawnerScript = preload("res://scripts/world/dust_devil_spawner.gd")
const RockScatterScript = preload("res://scripts/world/rock_scatter.gd")
const FootprintSystemScript = preload("res://scripts/world/footprint_system.gd")
const CrystalScatterScript = preload("res://scripts/world/crystal_scatter.gd")
const DebrisScatterScript = preload("res://scripts/world/debris_scatter.gd")
const AntennaArrayScript = preload("res://scripts/world/antenna_array.gd")
const LandingPadScript = preload("res://scripts/world/landing_pad.gd")
const PipeNetworkScript = preload("res://scripts/world/pipe_network.gd")
const SurfaceDetailScript = preload("res://scripts/world/surface_detail.gd")
const WeatherSystemScript = preload("res://scripts/world/weather_system.gd")
const TutorialSystemScript = preload("res://scripts/ui/tutorial_system.gd")
const FlagManagerScript = preload("res://scripts/world/flag_manager.gd")
const AttractionUIScript = preload("res://scripts/ui/attraction_ui.gd")
const AttractionDirectorScript = preload("res://scripts/world/attraction_director.gd")
const FUNFAIR_SCRIPT_PATH := "res://scripts/world/funfair/funfair.gd"
const QingStandingScript = preload("res://scripts/world/qing_standing.gd")

var _sun_light: DirectionalLight3D
var _sky_material: ShaderMaterial
var _terrain_material: ShaderMaterial
var _monument: Node3D
var _beat_station: Node3D
var _ripple_tween: Tween
var _creature_spawner: Node3D
var _weapon_system: Node3D
var _vehicle: CharacterBody3D
var _stat_tracker: Node
var _achievement_toast: Control
var _multiplayer_manager: Node
var _console_container: VBoxContainer
var _monitor_overlay: VBoxContainer
var _game_console: RefCounted
var _dust_particles: GPUParticles3D
var _heat_shimmer: MeshInstance3D
var _vegetation_manager: Node3D
var _atm_fog: GPUParticles3D
var _dust_devil_spawner: Node3D
var _ambient_audio: Node3D
var _rock_scatter: Node3D
var _footprint_system: Node3D
var _crystal_scatter: Node3D
var _pub_building: Node3D
var _debris_scatter: Node3D
var _antenna_array: Node3D
var _landing_pad: Node3D
var _pipe_network: Node3D
var _surface_detail: Node3D
var _weather_system: Node
var _tutorial_system: CanvasLayer
var _flag_manager: Node3D
const PUB_X: float = 60.0
const PUB_Z: float = 0.0
# Affection Fair — rides visitors pay for in AFFECTION (NW of spawn, rocket visible from spawn)
const FAIR_X: float = -100.0
const FAIR_Z: float = 80.0
var _funfair: Node3D
var _attraction_ui: CanvasLayer
var _attraction_director: Node
var _standing: Node  # QingStanding — decides how much fair this QING has earned
var _fair_tier: int = -1
var _fair_rebuild_pending: bool = false
var _veg_material: ShaderMaterial
var _beat_particles: GPUParticles3D
var _beat_camera_shake: float = 0.0
var _beat_camera_shake_velocity: float = 0.0
var _is_in_vehicle: bool = false
var _debug_territory_preset: int = -1  # -1 = off, 0..6 = test presets
var _pending_join_direction: int = -1  # Direction waiting for wallet tx confirmation
var _pending_join_tx_id: int = -1      # Tx ID for the join, used to filter signals


func _ready() -> void:
	# Find sky sub-nodes
	_sun_light = sky.get_node("SunLight")

	var world_env: WorldEnvironment = sky.get_node("WorldEnvironment")
	if world_env and world_env.environment:
		var sky_res: Sky = world_env.environment.sky
		if sky_res:
			_sky_material = sky_res.sky_material as ShaderMaterial
		# Apply quality preset to environment (SSR, SDFGI, volumetric fog, etc.)
		Config.apply_quality_to_environment(world_env.environment)

	# Apply quality preset to sun shadow distance
	if _sun_light:
		Config.apply_quality_to_sun(_sun_light)

	# Initialize terrain seed (may already be set from main menu)
	if GameManager.terrain_params.is_empty():
		GameManager.set_terrain_seed(GameManager.terrain_seed)

	# Build terrain material from biome data
	_setup_terrain_material()

	# Freeze player physics until terrain is ready
	player.set_physics_process(false)

	# Generate center terrain
	territory.set_shader_material(_terrain_material)
	territory.generate(GameManager.terrain_seed, GameManager.terrain_params)

	# Initialize neighbor territories + force fields
	territory_manager.initialize(
		territory, GameManager.terrain_seed,
		GameManager.territory_address, _terrain_material
	)

	# Flatten terrain for the mausoleum — carve a level building site
	_flatten_monument_site()

	# Flatten terrain for the beat station south of spawn
	_flatten_beat_station_site()

	# Flatten terrain for the pub east of spawn
	_flatten_pub_site()

	# Flatten the fairground
	_flatten_fair_site()

	# Spawn monument at center-north of territory
	_spawn_monument()

	# Spawn beat station south of player spawn
	_spawn_beat_station()

	# Spawn pub building east of player spawn
	_spawn_pub()

	# QING Standing decides how much fair this territory has earned, then spawn it
	# and wire every AFFECTION-spending spot (rides, bar)
	_init_standing()
	_spawn_funfair(_standing.current()["tier"])
	_init_attractions()

	# Position player at center, above terrain (after flattening)
	var spawn_height: float = territory.get_height_at(0.0, 0.0) + 2.0
	player.position = Vector3(0.0, spawn_height, 0.0)
	player.velocity = Vector3.ZERO

	# Wire up references — use territory_manager for height queries across territories
	player.set_terrain_generator(territory_manager)
	hud.set_player(player)

	# Wire monument interaction
	player.monument_interact.connect(_on_monument_interact)

	# Wire territory manager signals to HUD
	territory_manager.neighbor_join_prompt.connect(_on_join_prompt)
	territory_manager.neighbor_join_prompt_hide.connect(_on_join_prompt_hide)

	# Wire join completion: wait for on-chain confirmation before allowing transition
	territory_manager.join_started.connect(_on_join_started)
	territory_manager.join_completed.connect(_on_join_completed)
	territory_manager.join_rejected.connect(_on_join_rejected)
	ChainManager.tx_sent.connect(_on_join_tx_sent)
	ChainManager.tx_confirmed.connect(_on_join_tx_confirmed)
	ChainManager.tx_failed.connect(_on_join_tx_failed)

	# Wire neighbor discovery: chain discovers real QING neighbors → update territory manager
	ChainManager.neighbor_discovered.connect(_on_neighbor_discovered)

	# Wire territory crossing detection → HUD location indicator
	territory_manager.territory_entered.connect(_on_territory_entered)

	# Apply player appearance from identity (if loaded)
	if GameManager.has_identity:
		var appearance := PlayerAppearance.generate(GameManager.lau_saat)
		player.apply_appearance(appearance)

	# Connect territory state signal for shader updates
	GameManager.territory_state_changed.connect(_on_territory_state_changed)

	# If territory state was loaded before this scene, apply now
	if GameManager.has_territory_state:
		_apply_territory_state_to_shaders()
		_try_discover_neighbors()

	# Start global chat polling (independent of territory)
	ChainManager.start_global_chat_polling()

	# Spawn creatures across the territory
	_spawn_creatures()

	# Initialize weapon system on the player
	_init_weapon_system()

	# Spawn vehicle near the monument
	_spawn_vehicle()

	# Wire world map territory selection (Phase 10)
	hud.map_territory_selected.connect(_on_map_territory_selected)

	# Wire progression-based weapon/vehicle unlocks
	ChainManager.weapon_unlocked.connect(_on_weapon_unlocked_by_progression)
	ChainManager.vehicle_unlocked.connect(_on_vehicle_unlocked_by_progression)

	# Wire beat confirmation → beat station effect + terrain ripple
	ChainManager.beat_confirmed.connect(_on_beat_confirmed_visual)

	# Initialize stat tracker for achievement milestones
	_init_stat_tracker()

	# Initialize achievement toast (HUD overlay for unlock notifications)
	_init_achievement_toast()

	# Initialize multiplayer manager (Supabase presence via wallet.html)
	_init_multiplayer_manager()

	# Initialize debug tools (console + monitor overlay)
	_init_debug_tools()

	# Spawn ambient dust particles (follows player near ground)
	_spawn_dust_particles()

	# Spawn heat shimmer distortion overlay (visible during terraform)
	_spawn_heat_shimmer()

	# Spawn alien vegetation (emerges with terraforming)
	_spawn_vegetation()

	# Scatter boulders on steep terrain slopes
	_spawn_rock_scatter()

	# Spawn footstep dust puffs and landing clouds
	_spawn_footprint_system()

	# Spawn crystal mineral formations (grow with territory power)
	_spawn_crystal_scatter()

	# Spawn screen-space atmospheric fog (appears with terraforming)
	_spawn_atmospheric_fog()

	# Spawn dust devil system (swirling vortex columns)
	_spawn_dust_devils()

	# Spawn terrain-aware ambient audio
	_spawn_ambient_audio()

	# Phase 13H: World decorations
	_spawn_debris_scatter()
	_spawn_antenna_array()
	_spawn_landing_pad()
	_spawn_pipe_network()
	_spawn_surface_detail()

	# Phase 13I: Dynamic weather events
	_spawn_weather_system()

	# Phase 13L: Territory flags / guestbook
	_spawn_flag_manager()

	# Track current territory as visited
	if not GameManager.territory_address.is_empty():
		_stat_tracker.add_territory_visited(GameManager.territory_address)

	# Initialize minimap and register POIs
	_setup_minimap()

	# Phase 13J: Tutorial system — auto-start on first launch
	_init_tutorial()

	# Enable player physics after one frame (collision is in the tree now)
	await get_tree().physics_frame
	player.set_physics_process(true)


func _on_join_prompt(direction: int, _dir_name: String) -> void:
	## Show join prompt with QING name if discovered, otherwise direction name.
	var display_name: String = territory_manager.get_neighbor_name(direction)
	hud.show_interact_prompt("Press E to Join %s" % display_name)


func _on_join_prompt_hide() -> void:
	hud.hide_interact_prompt()


func _on_join_completed(direction: int) -> void:
	## Territory join finished (either via admitted check or tx confirmation).
	## Only show the "Joined X!" prompt if this was a manual E-key join
	## (not an auto-join from CoverCharge=0 during neighbor discovery).
	var was_manual: bool = _pending_join_direction >= 0
	_pending_join_direction = -1
	_pending_join_tx_id = -1
	if was_manual:
		var dir_labels := {0: "North", 1: "South", 2: "East", 3: "West"}
		hud.show_interact_prompt("Joined %s!" % dir_labels.get(direction, "territory"))
		await get_tree().create_timer(2.0).timeout
		hud.hide_interact_prompt()


func _on_join_rejected(reason: String) -> void:
	## Show rejection reason on HUD (wallet not connected, no address, etc.)
	hud.show_interact_prompt(reason)
	# Auto-hide after a few seconds
	await get_tree().create_timer(4.0).timeout
	hud.hide_interact_prompt()


func _on_join_started(direction: int) -> void:
	## Track which direction is pending a join (admitted check or wallet tx).
	_pending_join_direction = direction
	_pending_join_tx_id = -1  # Will be set when tx_sent fires
	hud.hide_interact_prompt()
	hud.show_interact_prompt("Checking admission...")


func _on_join_tx_sent(id: int, hash: String) -> void:
	## Tx was broadcast to mempool — now wait for on-chain confirmation.
	if _pending_join_direction < 0:
		return
	if hash.is_empty():
		return
	# Capture the tx ID so we only react to THIS transaction's confirmation/failure
	_pending_join_tx_id = id
	hud.show_interact_prompt("Transaction sent, waiting for confirmation...")


func _on_join_tx_confirmed(id: int, _hash: String) -> void:
	## Transaction mined and confirmed on-chain — complete the join.
	## Only act if this is the specific join tx we're waiting for.
	if _pending_join_direction < 0:
		return
	if _pending_join_tx_id >= 0 and id != _pending_join_tx_id:
		return  # Different tx — ignore (e.g., a terraform tx confirmed)
	# _complete_join will emit join_completed → _on_join_completed clears state
	territory_manager._complete_join(_pending_join_direction)


func _on_join_tx_failed(id: int, error: String) -> void:
	## Transaction failed or reverted on-chain.
	## Only act if this is the specific join tx we're waiting for.
	if _pending_join_direction < 0:
		return
	if _pending_join_tx_id >= 0 and id != _pending_join_tx_id:
		return  # Different tx — ignore (e.g., a terraform tx failed)
	_pending_join_direction = -1
	_pending_join_tx_id = -1
	hud.show_interact_prompt("Transaction failed: %s" % error)
	await get_tree().create_timer(4.0).timeout
	hud.hide_interact_prompt()


func _try_discover_neighbors() -> void:
	## Trigger real on-chain neighbor discovery if HECKE coordinates are available.
	if GameManager.territory_latitude_hex.is_empty() or GameManager.territory_longitude_hex.is_empty():
		return
	ChainManager.discover_neighbors()


func _on_neighbor_discovered(direction: int, data: Dictionary) -> void:
	## Chain discovered a real QING neighbor — update territory manager.
	territory_manager.set_neighbor_data(direction, data)


func _on_map_territory_selected(qing_address: String) -> void:
	## Player selected a QING from the world map — load it as a new territory.
	## This is essentially a teleport: reload the scene with the new QING data.
	if qing_address.is_empty() or qing_address == GameManager.territory_address.to_lower():
		hud.show_interact_prompt("You're already in this territory!")
		await get_tree().create_timer(2.0).timeout
		hud.hide_interact_prompt()
		return
	print("[Main] Map travel to QING: %s" % qing_address.left(14))
	hud.show_interact_prompt("Traveling to %s..." % qing_address.left(10))
	# Load the territory data — this will trigger territory_data_changed, then scene reload
	GameManager.territory_address = qing_address
	GameManager.is_chain_sourced = true
	ChainManager.load_territory(qing_address)
	# Wait for territory data, then reload the scene
	await ChainManager.territory_loaded
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_territory_entered(direction: int, territory_name: String, address: String) -> void:
	## Player crossed into a different territory — update HUD location display.
	hud.update_location(direction, territory_name, address)
	print("[Main] Player entered territory: %s (dir=%d)" % [territory_name, direction])


func _setup_terrain_material() -> void:
	var biome := BiomeSystem.get_biome(GameManager.terrain_seed)
	var shader := load("res://assets/shaders/terrain.gdshader") as Shader

	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = shader

	# Set biome colors
	_terrain_material.set_shader_parameter("grass_color", biome.grass_color)
	_terrain_material.set_shader_parameter("grass_color_2", biome.grass_color_2)
	_terrain_material.set_shader_parameter("rock_color", biome.rock_color)
	_terrain_material.set_shader_parameter("rock_color_2", biome.rock_color_2)
	_terrain_material.set_shader_parameter("soil_color", biome.soil_color)
	_terrain_material.set_shader_parameter("snow_color", biome.snow_color)
	_terrain_material.set_shader_parameter("water_color", biome.water_color)
	_terrain_material.set_shader_parameter("snow_line", biome.snow_line)
	_terrain_material.set_shader_parameter("water_level", biome.water_level)


var _was_near_game_table: bool = false

func _process(delta: float) -> void:
	_update_day_night_cycle(delta)
	# Track which territory the player is in (emits signal on change)
	if player:
		territory_manager.update_player_territory(player.global_position)

	# Pub game table proximity prompts
	if _pub_building and _pub_building.is_player_near_game_table():
		var table_idx: int = _pub_building.get_near_table_index()
		var game_name: String = _pub_building.get_game_name_for_table(table_idx)
		hud.show_interact_prompt("Press E to play %s" % game_name)
		player.set_near_game_table(true)
		_was_near_game_table = true
	elif _was_near_game_table:
		if _pub_building and _pub_building._player_inside:
			hud.hide_interact_prompt()
		player.set_near_game_table(false)
		_was_near_game_table = false

	# Weather system — update atmosphere storm fog during dust storms
	if _weather_system and _sky_material and _weather_system.get_current_weather() == 1:  # DUST_STORM
		var active_event: Node = _weather_system.get("_active_event_node")
		if active_event and active_event.has_method("get_elapsed"):
			var elapsed: float = active_event.get_elapsed()
			var duration: float = active_event.get("_duration") if active_event.get("_duration") else 60.0
			var fade := 1.0
			if elapsed < 3.0:
				fade = elapsed / 3.0
			elif elapsed > duration - 3.0:
				fade = (duration - elapsed) / 3.0
			fade = clampf(fade, 0.0, 1.0)
			_sky_material.set_shader_parameter("storm_intensity", fade * 0.6)

	# Beat camera shake — spring-physics roll + pitch
	if absf(_beat_camera_shake) > 0.0001 or absf(_beat_camera_shake_velocity) > 0.0001:
		_beat_camera_shake_velocity -= (_beat_camera_shake * 40.0 + _beat_camera_shake_velocity * 8.0) * delta
		_beat_camera_shake += _beat_camera_shake_velocity * delta
		var cam_rig: Node3D = player.get_node_or_null("CameraRig") if player else null
		if cam_rig:
			cam_rig.rotation.z = _beat_camera_shake
			cam_rig.rotation.x += _beat_camera_shake * 0.3 * delta
	elif _beat_camera_shake != 0.0:
		_beat_camera_shake = 0.0
		var cam_rig: Node3D = player.get_node_or_null("CameraRig") if player else null
		if cam_rig:
			cam_rig.rotation.z = 0.0


func _update_day_night_cycle(delta: float) -> void:
	# Advance time
	GameManager.time_of_day += delta * GameManager.day_cycle_speed
	if GameManager.time_of_day > 1.0:
		GameManager.time_of_day -= 1.0

	var t: float = GameManager.time_of_day

	# Sun angle: 0.0 = midnight (sun at bottom), 0.25 = sunrise, 0.5 = noon, 0.75 = sunset
	var sun_angle: float = t * TAU - PI / 2.0
	var sun_dir := Vector3(0.0, sin(sun_angle), -cos(sun_angle)).normalized()

	# Update directional light rotation
	if _sun_light:
		_sun_light.rotation.x = -sun_angle
		# Dysnomia is ~96 AU from the Sun — dimmer than Earth but bright enough to play
		# Artistic compromise: looks like a cold distant star but still lights the surface
		var sun_height: float = sun_dir.y
		var day_factor: float = smoothstep(-0.1, 0.2, sun_height)

		# Horizon extinction: when sun is low, light passes through more atmosphere
		# (even a thin one) and gets dimmer. This prevents sunset being brighter than noon.
		# At sun_height=1.0 (noon): extinction=1.0 (full brightness)
		# At sun_height=0.0 (horizon): extinction~0.35 (much dimmer)
		var extinction: float = clampf(smoothstep(-0.05, 0.5, sun_height), 0.0, 1.0)
		extinction = extinction * 0.65 + 0.35  # Remap: 0.35 at horizon, 1.0 at zenith

		# Peak energy ~1.2 during day at zenith, much less at horizon, 0.02 at night
		var light_energy: float = clampf(day_factor * 1.2 * extinction, 0.02, 1.2)
		_sun_light.light_energy = light_energy

		# Warm white light — slight colour shift at sunset
		var sunset_factor: float = exp(-pow(sun_height * 5.0, 2.0))
		_sun_light.light_color = Color(0.97, 0.96 - sunset_factor * 0.05, 0.94 - sunset_factor * 0.08)

	# Update sky shader
	if _sky_material:
		_sky_material.set_shader_parameter("sun_direction", sun_dir)
		_sky_material.set_shader_parameter("time_of_day", t)

	# Update cloud shadows on terrain — matches volumetric clouds overhead
	if _terrain_material:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		var effective_density := 0.02 + activity * 0.35
		_terrain_material.set_shader_parameter("cloud_shadow_density", effective_density)
		_terrain_material.set_shader_parameter("cloud_shadow_sun_dir", sun_dir)

	# Update atmospheric fog sun direction
	if _atm_fog and is_instance_valid(_atm_fog):
		_atm_fog.set_sun_direction(sun_dir)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t2: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t2 * t2 * (3.0 - 2.0 * t2)


func _on_territory_state_changed(_data: Dictionary) -> void:
	_apply_territory_state_to_shaders()
	# Territory state includes HECKE coordinates — discover real on-chain neighbors
	_try_discover_neighbors()
	# Update monument visuals to match territory state
	if _monument and _monument.has_method("update_territory_state"):
		_monument.update_territory_state()
	# Update beat station visuals to match territory state
	if _beat_station and _beat_station.has_method("update_territory_state"):
		_beat_station.update_territory_state()
	# Update pub visuals to match territory state
	if _pub_building and _pub_building.has_method("update_territory_state"):
		_pub_building.update_territory_state()
	# Update pipe network glow to match territory state
	if _pipe_network and _pipe_network.has_method("update_territory_state"):
		_pipe_network.update_territory_state()
	# Update weather system activity level
	if _weather_system and _weather_system.has_method("set_activity"):
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		_weather_system.set_activity(activity)


func _apply_territory_state_to_shaders() -> void:
	## Map on-chain territory state to shader uniforms.
	## Charge drives power glow, bars drive activity, latitude drives sky temperature.

	# Normalize charge to 0-1 range (MOTZKIN_PRIME max, but most values much smaller)
	var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)

	# Activity from accumulated terraform bars (hypobar + epibar)
	var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
	var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)

	# Power tint from FAUNG scalars (subtle color modulation)
	var scalars := GameManager.faung_scalars
	var tint_r := clampf(float(scalars.get("phi", 0)) / 1e15, 0.0, 0.3)
	var tint_g := clampf(float(scalars.get("eta", 0)) / 1e15, 0.0, 0.3)
	var tint_b := clampf(float(scalars.get("mu", 0)) / 1e15, 0.0, 0.3)

	# Terrain shader
	if _terrain_material:
		_terrain_material.set_shader_parameter("territory_power", power)
		_terrain_material.set_shader_parameter("territory_activity", activity)
		_terrain_material.set_shader_parameter("power_tint", Vector3(tint_r, tint_g, tint_b))

		# Apply latitude shift to biome colors (subtle temperature nudge)
		var latitude := GameManager.territory_latitude
		if absf(latitude) > 0.1:
			var biome := BiomeSystem.get_biome(GameManager.terrain_seed)
			var shifted := BiomeSystem.apply_latitude_shift(biome, latitude)
			_terrain_material.set_shader_parameter("grass_color", shifted.grass_color)
			_terrain_material.set_shader_parameter("grass_color_2", shifted.grass_color_2)
			_terrain_material.set_shader_parameter("snow_line", shifted.snow_line)

	# Sky shader — latitude drives temperature, activity drives clouds + scattering
	if _sky_material:
		var lat_factor := clampf(GameManager.territory_latitude / 90.0, -1.0, 1.0)
		_sky_material.set_shader_parameter("latitude_factor", lat_factor)
		_sky_material.set_shader_parameter("atmo_activity", activity)

		# Scattering thickness and intensity scale with activity
		# At low activity: thin wispy haze. At high activity: proper atmospheric glow.
		_sky_material.set_shader_parameter("atm_thickness", 0.1 + activity * 0.9)
		_sky_material.set_shader_parameter("atm_sun_intensity", 5.0 + activity * 15.0)

	# Ambient dust — more particles during active terraforming
	if _dust_particles and is_instance_valid(_dust_particles):
		_dust_particles.set_activity_level(activity)

	# Heat shimmer — distortion intensity scales with territory power
	if _heat_shimmer and is_instance_valid(_heat_shimmer):
		_heat_shimmer.set_power_level(power)

	# Alien vegetation — density scales with terraform activity
	if _vegetation_manager and is_instance_valid(_vegetation_manager):
		_vegetation_manager.set_territory_state(activity, power)

	# Atmospheric fog — fog density scales with terraform activity
	if _atm_fog and is_instance_valid(_atm_fog):
		_atm_fog.set_atmo_activity(activity)

	# Dust devils — more active territories get more/bigger dust devils
	if _dust_devil_spawner and is_instance_valid(_dust_devil_spawner):
		_dust_devil_spawner.set_activity(activity)

	# Crystal formations — scale grows with territory power
	if _crystal_scatter and is_instance_valid(_crystal_scatter):
		_crystal_scatter.set_territory_power(power)

	# Ambient audio — wind volume scales with activity
	if _ambient_audio and is_instance_valid(_ambient_audio):
		_ambient_audio.set_territory_activity(activity)


# ─── Creatures & Combat ─────────────────────────────────────────────────

func _spawn_creatures() -> void:
	## Spawn alien creatures across the territory surface.
	_creature_spawner = Node3D.new()
	_creature_spawner.set_script(CreatureSpawnerScript)
	_creature_spawner.name = "CreatureSpawner"
	add_child(_creature_spawner)
	_creature_spawner.initialize(GameManager.terrain_seed, player, territory_manager)
	_creature_spawner.player_damaged.connect(_on_player_damaged)
	_creature_spawner.creature_killed.connect(_on_creature_killed)


func _init_weapon_system() -> void:
	## Add weapon system to the player.
	_weapon_system = Node3D.new()
	_weapon_system.set_script(WeaponSystemScript)
	_weapon_system.name = "WeaponSystem"
	player.add_child(_weapon_system)
	_weapon_system.initialize(_creature_spawner)
	_weapon_system.health_changed.connect(_on_player_health_changed)
	_weapon_system.weapon_switched.connect(_on_weapon_switched)

	# Unlock mining laser by default (basic tool for the moon)
	_weapon_system.unlock_weapon(1)  # MINING_LASER


func _spawn_vehicle() -> void:
	## Spawn a lunar rover near the monument for player use.
	_vehicle = CharacterBody3D.new()
	_vehicle.set_script(VehicleScript)
	_vehicle.name = "LunarRover"
	add_child(_vehicle)

	# Place vehicle near the monument, offset to the side
	var vehicle_pos := Vector3(15.0, 0.0, -30.0)
	if territory and territory.has_method("get_height_at"):
		vehicle_pos.y = territory.get_height_at(vehicle_pos.x, vehicle_pos.z) + 0.5
	_vehicle.initialize(0, vehicle_pos, player, territory_manager)  # 0 = ROVER
	_vehicle.player_mounted.connect(func(): _is_in_vehicle = true)
	_vehicle.player_dismounted.connect(func(): _is_in_vehicle = false)


func _on_player_damaged(damage: float) -> void:
	## Creature attacked player — apply damage through weapon system.
	if _weapon_system and _weapon_system.has_method("take_damage"):
		_weapon_system.take_damage(damage)
	# Red vignette flash scaled by damage proportion
	var intensity := clampf(damage / 30.0, 0.2, 1.0)
	if hud and hud.has_method("flash_damage"):
		hud.flash_damage(intensity)
	# Trigger shield shimmer on player model
	var model: Node3D = player.get_node_or_null("PlayerModel") if player else null
	if model and model.has_method("trigger_shield_flash"):
		model.trigger_shield_flash()


func _on_creature_killed(_type: int, _pos: Vector3) -> void:
	## A creature was killed — could trigger XP, drops, etc.
	pass


func _on_player_health_changed(current: float, maximum: float) -> void:
	## Update HUD health display.
	hud.update_health(current, maximum)


func _on_weapon_switched(weapon_type: int) -> void:
	## Update HUD weapon display.
	if _weapon_system and _weapon_system.has_method("get_weapon_name"):
		hud.update_weapon(_weapon_system.get_weapon_name())


func _on_weapon_unlocked_by_progression(weapon_type: int, weapon_name: String) -> void:
	## Entropy API says player earned enough XP/terraforms to unlock a weapon.
	if _weapon_system and _weapon_system.has_method("unlock_weapon"):
		if not _weapon_system.is_weapon_unlocked(weapon_type):
			_weapon_system.unlock_weapon(weapon_type)
			print("[Main] Weapon unlocked by progression: %s (type=%d)" % [weapon_name, weapon_type])


func _on_vehicle_unlocked_by_progression(vehicle_type: int, vehicle_name: String) -> void:
	## Entropy API says player earned enough to unlock a new vehicle type.
	## Spawn it near the existing rover if not already spawned.
	print("[Main] Vehicle unlocked by progression: %s (type=%d)" % [vehicle_name, vehicle_type])
	# For now, announce only — vehicle spawning for additional types can be added later
	# The rover is always available; hoverbike and tank unlock via progression


# ─── Monument ───────────────────────────────────────────────────────────

func _flatten_monument_site() -> void:
	## Flatten the terrain around the monument location so the mausoleum
	## sits on level ground — like real mausoleums carved into mountainsides.
	## Also flattens a corridor from player spawn to the monument entrance.
	var monument_x: float = 0.0
	var monument_z: float = -40.0

	# Get mausoleum dimensions from the generator to compute footprint
	var params := MonumentGenerator.get_monument_params(GameManager.terrain_seed)
	var cw: float = params.get("chamber_width", 50.0)
	var cd: float = params.get("chamber_depth", 35.0)
	var brd: float = params.get("back_room_depth", 18.0)
	var wt: float = params.get("wall_thickness", 4.0)

	# Total mausoleum footprint (including spirit way approach)
	# The mausoleum extends from z=0 (entrance) to z=-(cd+brd) relative to monument
	# Spirit way extends from z=+25 to z=+85 relative to monument
	# So world coords: entrance at monument_z, back wall at monument_z-(cd+brd)
	# Spirit way starts at monument_z+25

	# Flatten the building site: center on the mausoleum midpoint
	var total_depth: float = cd + brd
	var site_center_z: float = monument_z - total_depth * 0.5
	var site_half_w: float = (cw + wt * 2.0) * 0.5 + 5.0  # +5m padding
	var site_half_d: float = total_depth * 0.5 + 5.0

	territory.flatten_area(monument_x, site_center_z, site_half_w, site_half_d, 20.0)

	# Flatten the approach path (spirit way + area between player spawn and entrance)
	# From player spawn (z=0) to monument entrance (z=-40), narrow corridor
	var approach_center_z: float = monument_z * 0.5  # midpoint between spawn and entrance
	var approach_half_w: float = 15.0  # 30m wide path
	var approach_half_d: float = absf(monument_z) * 0.5 + 5.0
	territory.flatten_area(monument_x, approach_center_z, approach_half_w, approach_half_d, 15.0)


func _spawn_monument() -> void:
	## Spawn the QING mausoleum north of center, on the flattened terrain surface.
	## Placed at z=-40 so the spirit way approach path passes through player spawn.
	_monument = Node3D.new()
	_monument.set_script(MonumentScript)
	_monument.name = "Monument"

	# Position: 40m north (negative Z) — terrain is pre-flattened by _flatten_monument_site()
	var monument_x: float = 0.0
	var monument_z: float = -40.0
	var monument_y: float = territory.get_height_at(monument_x, monument_z)
	_monument.position = Vector3(monument_x, monument_y, monument_z)

	add_child(_monument)
	_monument.initialize(GameManager.terrain_seed)

	# Connect proximity signals
	_monument.player_entered_range.connect(_on_monument_enter)
	_monument.player_exited_range.connect(_on_monument_exit)

	# Apply territory state if already loaded
	if GameManager.has_territory_state:
		_monument.update_territory_state()


func _on_monument_enter() -> void:
	player.set_near_monument(true)
	hud.show_interact_prompt("Press E to Terraform at Monument")


func _on_monument_exit() -> void:
	player.set_near_monument(false)
	hud.hide_interact_prompt()


func _on_monument_interact() -> void:
	## Player pressed E at monument — open terraform panel with batch mode.
	hud.open_terraform_from_monument()


# ─── Beat Station ────────────────────────────────────────────────────────

const BEAT_STATION_X: float = 0.0
const BEAT_STATION_Z: float = 60.0  # South of player spawn (positive Z)

func _flatten_beat_station_site() -> void:
	## Flatten the terrain around the beat station location.
	territory.flatten_area(BEAT_STATION_X, BEAT_STATION_Z, 15.0, 15.0, 15.0)


func _spawn_beat_station() -> void:
	## Spawn the Meta Resonance Array south of player spawn on flattened terrain.
	_beat_station = Node3D.new()
	_beat_station.set_script(BeatStationScript)
	_beat_station.name = "BeatStation"

	var station_y: float = territory.get_height_at(BEAT_STATION_X, BEAT_STATION_Z)
	_beat_station.position = Vector3(BEAT_STATION_X, station_y, BEAT_STATION_Z)

	add_child(_beat_station)
	_beat_station.initialize(GameManager.terrain_seed)

	# Connect proximity signals
	_beat_station.player_entered_range.connect(_on_beat_station_enter)
	_beat_station.player_exited_range.connect(_on_beat_station_exit)

	# Apply territory state if already loaded
	if GameManager.has_territory_state:
		_beat_station.update_territory_state()


func _on_beat_station_enter() -> void:
	hud.show_interact_prompt("Meta Resonance Array — Press T to Beat")


func _on_beat_station_exit() -> void:
	hud.hide_interact_prompt()


# ─── Pub Building ────────────────────────────────────────────────────────

func _flatten_pub_site() -> void:
	## Flatten the terrain around the pub location.
	territory.flatten_area(PUB_X, PUB_Z, 20.0, 15.0, 15.0)


func _spawn_pub() -> void:
	## Spawn the Lunar Cantina pub east of player spawn on flattened terrain.
	_pub_building = Node3D.new()
	_pub_building.set_script(PubBuildingScript)
	_pub_building.name = "PubBuilding"

	var pub_y: float = territory.get_height_at(PUB_X, PUB_Z)
	_pub_building.position = Vector3(PUB_X, pub_y, PUB_Z)

	add_child(_pub_building)
	_pub_building.initialize(GameManager.terrain_seed)

	# Connect proximity signals
	_pub_building.player_entered_range.connect(_on_pub_enter)
	_pub_building.player_exited_range.connect(_on_pub_exit)

	# Connect game table interactions → minigames
	_pub_building.game_table_interacted.connect(_on_game_table_interacted)
	_pub_building.player_entered_interior.connect(_on_pub_interior_enter)
	_pub_building.player_exited_interior.connect(_on_pub_interior_exit)

	# Wire player E-key interact → pub game table
	player.pub_game_interact.connect(_on_pub_game_interact)

	# Initialize minigame manager in HUD
	hud.create_minigame_manager()

	# Apply territory state if already loaded
	if GameManager.has_territory_state:
		_pub_building.update_territory_state()


# ─── Affection Fair & attractions ──────────────────────────────────────────

func _flatten_fair_site() -> void:
	territory.flatten_area(FAIR_X, FAIR_Z, 40.0, 40.0, 20.0)


func _init_standing() -> void:
	_standing = QingStandingScript.new()
	_standing.name = "QingStanding"
	add_child(_standing)
	_standing.standing_changed.connect(_on_standing_changed)


func _on_standing_changed(s: Dictionary) -> void:
	if _funfair and _funfair.has_method("set_unlock_hint"):
		_funfair.set_unlock_hint(QingStandingScript.unlock_hint(s))
	if _attraction_ui:
		_attraction_ui.show_standing(s, GameManager.territory_name)
	if _funfair == null or s["tier"] == _fair_tier:
		return
	# Tier changed: rebuild the fair — but never out from under someone mid-ride
	if _attraction_director and _attraction_director.is_riding():
		_fair_rebuild_pending = true
		return
	_rebuild_funfair(s["tier"])


func _rebuild_funfair(tier: int) -> void:
	_fair_rebuild_pending = false
	if _attraction_director:
		_attraction_director.clear_rides()
	if _funfair:
		_funfair.queue_free()
		_funfair = null
	_spawn_funfair(tier)
	if _attraction_director and _funfair and _funfair.has_method("get_rides"):
		for ride in _funfair.get_rides():
			_attraction_director.register_ride(ride)


func cmd_standing(tier: int) -> String:
	## Console: `standing 0..3` forces a tier for testing, `standing -1` returns to live data.
	_standing.tier_override = tier
	_standing.recompute()
	var s: Dictionary = _standing.current()
	return "Standing %d (%s) → tier %d %s%s" % [s["score"], s["title"], s["tier"], s["fair"],
		" [override]" if s["overridden"] else ""]


func _spawn_funfair(tier: int = 3) -> void:
	if not ResourceLoader.exists(FUNFAIR_SCRIPT_PATH):
		return
	_fair_tier = tier
	_funfair = Node3D.new()
	_funfair.set_script(load(FUNFAIR_SCRIPT_PATH))
	_funfair.name = "AffectionFair"
	var y: float = territory.get_height_at(FAIR_X, FAIR_Z)
	_funfair.position = Vector3(FAIR_X, y, FAIR_Z)
	add_child(_funfair)
	# Older fair builds take only a seed; tiered builds take (seed, tier)
	var init_args: int = 1
	for m in _funfair.get_method_list():
		if m["name"] == "initialize":
			init_args = m["args"].size()
	if init_args >= 2:
		_funfair.initialize(GameManager.terrain_seed, tier)
	else:
		_funfair.initialize(GameManager.terrain_seed)
	if _standing and _funfair.has_method("set_unlock_hint"):
		_funfair.set_unlock_hint(QingStandingScript.unlock_hint(_standing.current()))


func _init_attractions() -> void:
	## One director for every place a visitor can spend AFFECTION in this QING.
	_attraction_ui = CanvasLayer.new()
	_attraction_ui.set_script(AttractionUIScript)
	_attraction_ui.name = "AttractionUI"
	add_child(_attraction_ui)

	_attraction_director = Node.new()
	_attraction_director.set_script(AttractionDirectorScript)
	_attraction_director.name = "AttractionDirector"
	add_child(_attraction_director)
	_attraction_director.setup(player, _attraction_ui)
	_attraction_director.ride_state_changed.connect(_on_ride_state_changed)

	if _pub_building:
		_attraction_director.register_pub(_pub_building)
	if _funfair and _funfair.has_method("get_rides"):
		for ride in _funfair.get_rides():
			_attraction_director.register_ride(ride)


func _on_ride_state_changed(riding: bool) -> void:
	# No shooting from a ferris wheel gondola
	if _weapon_system:
		_weapon_system.set_process_unhandled_input(not riding)
	if riding:
		hud.hide_interact_prompt()
	elif _fair_rebuild_pending and _standing:
		_rebuild_funfair.call_deferred(_standing.current()["tier"])


func _on_pub_enter() -> void:
	hud.show_interact_prompt("Lunar Cantina — Walk inside")


func _on_pub_exit() -> void:
	hud.hide_interact_prompt()
	player.set_near_game_table(false)


func _on_pub_interior_enter() -> void:
	## Player entered the pub interior — start checking for game table proximity.
	pass  # Game table areas handle their own enter/exit


func _on_pub_interior_exit() -> void:
	## Player exited the pub interior — clear game table state.
	player.set_near_game_table(false)
	hud.hide_interact_prompt()


func _on_game_table_interacted(table_index: int) -> void:
	## Player pressed E at a game table — open the minigame.
	hud.open_minigame(table_index)


func _on_pub_game_interact() -> void:
	## Player pressed E while near a game table — forward to pub building.
	if _pub_building and _pub_building.is_player_near_game_table():
		_pub_building.interact_game_table()


func _on_beat_confirmed_visual(_tx_id: int) -> void:
	## Beat transaction confirmed on-chain — EARTH-SHATTERING event.
	## The hardest chain operation in the entire Dysnomia ecosystem deserves
	## a massive visual response: terrain shockwave, sky flash, vegetation surge,
	## camera shake, particle burst, and screen flash.
	if _beat_station and _beat_station.has_method("trigger_beat_effect"):
		_beat_station.trigger_beat_effect()

	_start_terrain_ripple_epic()
	_start_sky_beat_flash()
	_start_vegetation_beat_pulse()
	_start_beat_camera_shake()
	_spawn_beat_particles()
	if hud and hud.has_method("flash_screen_beat"):
		hud.flash_screen_beat()


func _start_terrain_ripple_epic() -> void:
	## Massive expanding energy ring with vertex displacement.
	if not _terrain_material:
		return

	# Kill any existing ripple tween
	if _ripple_tween and _ripple_tween.is_valid():
		_ripple_tween.kill()
		_reset_ripple()

	# Set ripple origin to beat station world position
	_terrain_material.set_shader_parameter("ripple_center",
		Vector3(BEAT_STATION_X, 0.0, BEAT_STATION_Z))

	# Ripple color from territory accent
	var params := MonumentGenerator.get_monument_params(GameManager.terrain_seed)
	var accent: Color = params.get("accent_color", Color.CYAN)
	_terrain_material.set_shader_parameter("ripple_color",
		Vector3(accent.r, accent.g, accent.b))

	# Set initial state — much more intense than before
	_terrain_material.set_shader_parameter("ripple_radius", 0.0)
	_terrain_material.set_shader_parameter("ripple_intensity", 1.5)
	_terrain_material.set_shader_parameter("ripple_vertex_height", 1.2)

	# Radius: expand 0 → 500 over 6s (wider, longer than before)
	_ripple_tween = create_tween()
	_ripple_tween.tween_method(_set_ripple_radius, 0.0, 500.0, 6.0) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_ripple_tween.chain()

	# Intensity: delay 3s, then fade over 4s
	var intensity_tween := create_tween()
	intensity_tween.tween_interval(3.0)
	intensity_tween.tween_method(_set_ripple_intensity, 1.5, 0.0, 4.0) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	intensity_tween.tween_callback(_reset_ripple)

	# Vertex displacement: 1.2 → 0.0 over 5s (ground settles back down)
	var vertex_tween := create_tween()
	vertex_tween.tween_method(func(v: float) -> void:
		if _terrain_material:
			_terrain_material.set_shader_parameter("ripple_vertex_height", v)
	, 1.2, 0.0, 5.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)


func _start_sky_beat_flash() -> void:
	## Flash the entire sky with accent color + sweep an energy ring from horizon to zenith.
	if not _sky_material:
		return
	var params := MonumentGenerator.get_monument_params(GameManager.terrain_seed)
	var accent: Color = params.get("accent_color", Color.CYAN)
	_sky_material.set_shader_parameter("beat_color",
		Vector3(accent.r, accent.g, accent.b))
	_sky_material.set_shader_parameter("beat_flash", 1.0)
	_sky_material.set_shader_parameter("beat_time", 0.0)

	# Flash fade: 1.0 → 0.0 over 3 seconds
	var flash_tween := create_tween()
	flash_tween.tween_method(func(v: float) -> void:
		if _sky_material:
			_sky_material.set_shader_parameter("beat_flash", v)
	, 1.0, 0.0, 3.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# beat_time: 0 → 8 over 8 seconds (drives ring sweep up the sky dome)
	var time_tween := create_tween()
	time_tween.tween_method(func(v: float) -> void:
		if _sky_material:
			_sky_material.set_shader_parameter("beat_time", v)
	, 0.0, 8.0, 8.0)
	time_tween.tween_callback(func() -> void:
		if _sky_material:
			_sky_material.set_shader_parameter("beat_flash", 0.0)
			_sky_material.set_shader_parameter("beat_time", 0.0)
	)


func _start_vegetation_beat_pulse() -> void:
	## All vegetation surges with bioluminescence and pushes outward.
	if not _veg_material:
		return
	_veg_material.set_shader_parameter("beat_origin",
		Vector3(BEAT_STATION_X, 0.0, BEAT_STATION_Z))
	_veg_material.set_shader_parameter("beat_flash", 1.0)
	var veg_tween := create_tween()
	veg_tween.tween_method(func(v: float) -> void:
		if _veg_material:
			_veg_material.set_shader_parameter("beat_flash", v)
	, 1.0, 0.0, 2.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _start_beat_camera_shake() -> void:
	## Spring-physics camera shake lasting ~1.5 seconds.
	_beat_camera_shake = 0.0
	_beat_camera_shake_velocity = 0.15


func _spawn_beat_particles() -> void:
	## Burst of bright energy particles from the beat station, scattering in a dome.
	if _beat_particles and is_instance_valid(_beat_particles):
		_beat_particles.queue_free()

	_beat_particles = GPUParticles3D.new()
	_beat_particles.name = "BeatParticles"
	_beat_particles.one_shot = true
	_beat_particles.explosiveness = 0.95
	_beat_particles.amount = 100
	_beat_particles.lifetime = 3.0
	_beat_particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.0
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 80.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 40.0
	mat.gravity = Vector3(0.0, -1.0, 0.0)
	mat.scale_min = 0.1
	mat.scale_max = 0.5
	mat.damping_min = 1.0
	mat.damping_max = 3.0

	# Color ramp: white → accent → fade
	var params := MonumentGenerator.get_monument_params(GameManager.terrain_seed)
	var accent: Color = params.get("accent_color", Color.CYAN)
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	color_ramp.add_point(0.2, accent)
	color_ramp.add_point(0.6, Color(accent.r, accent.g, accent.b, 0.5))
	color_ramp.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	_beat_particles.process_material = mat

	# Unshaded billboarded quad for draw pass
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_beat_particles.draw_pass_1 = quad
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.emission_enabled = true
	draw_mat.emission = accent
	draw_mat.emission_energy_multiplier = 3.0
	quad.surface_set_material(0, draw_mat)

	var station_y: float = territory.get_height_at(BEAT_STATION_X, BEAT_STATION_Z)
	_beat_particles.position = Vector3(BEAT_STATION_X, station_y + 10.0, BEAT_STATION_Z)
	add_child(_beat_particles)

	# Auto-free after particles expire
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if _beat_particles and is_instance_valid(_beat_particles):
			_beat_particles.queue_free()
			_beat_particles = null
	)


func _set_ripple_radius(value: float) -> void:
	if _terrain_material:
		_terrain_material.set_shader_parameter("ripple_radius", value)


func _set_ripple_intensity(value: float) -> void:
	if _terrain_material:
		_terrain_material.set_shader_parameter("ripple_intensity", value)


func _reset_ripple() -> void:
	## Clear all ripple uniforms after effect completes.
	if _terrain_material:
		_terrain_material.set_shader_parameter("ripple_radius", 0.0)
		_terrain_material.set_shader_parameter("ripple_intensity", 0.0)
		_terrain_material.set_shader_parameter("ripple_vertex_height", 0.0)


# ─── Achievements & Stat Tracking (Phase 12A) ───────────────────────────

func _init_stat_tracker() -> void:
	## Create stat tracker for local player statistics → achievement thresholds.
	_stat_tracker = Node.new()
	_stat_tracker.set_script(StatTrackerScript)
	_stat_tracker.name = "StatTracker"
	add_child(_stat_tracker)
	_stat_tracker.initialize(player)

	# Wire milestone signals → achievement client
	var ac: Node = ChainManager.achievement_client
	if ac:
		_stat_tracker.distance_milestone.connect(func(id: String, _dist: float) -> void:
			ac.try_unlock(id))
		_stat_tracker.jump_milestone.connect(func(_count: int) -> void:
			ac.try_unlock("jump_100"))
		_stat_tracker.altitude_milestone.connect(func(_alt: float) -> void:
			ac.try_unlock("alt_30"))
		_stat_tracker.session_milestone.connect(func(id: String, _mins: float) -> void:
			ac.try_unlock(id))
		_stat_tracker.territory_visited.connect(func(count: int) -> void:
			ac.check_territory_milestones(count))
		_stat_tracker.chat_sent_first.connect(func() -> void:
			ac.try_unlock("first_chat"))


func _init_achievement_toast() -> void:
	## Create the achievement toast overlay on the HUD.
	_achievement_toast = Control.new()
	_achievement_toast.set_script(AchievementToastScript)
	_achievement_toast.name = "AchievementToast"
	hud.add_child(_achievement_toast)

	# Wire achievement unlocked → toast display
	var ac: Node = ChainManager.achievement_client
	if ac:
		ac.achievement_unlocked.connect(_on_achievement_unlocked)
		ac.tier_changed.connect(_on_tier_changed)


func _on_achievement_unlocked(id: String, data: Dictionary) -> void:
	## Show toast when an achievement is unlocked.
	if _achievement_toast and _achievement_toast.has_method("show_achievement"):
		var name_str: String = data.get("name", id)
		var desc_str: String = data.get("desc", "")
		var xp_val: int = data.get("xp", 50)
		_achievement_toast.show_achievement(name_str, desc_str, xp_val)


func _on_tier_changed(tier: int, title: String) -> void:
	## Show special toast when evolution tier changes.
	if _achievement_toast and _achievement_toast.has_method("show_tier_up"):
		_achievement_toast.show_tier_up(tier, title)


# ─── Multiplayer Presence (Phase 12B) ────────────────────────────────────

func _init_multiplayer_manager() -> void:
	## Create the multiplayer manager and wire Supabase presence signals.
	_multiplayer_manager = Node.new()
	_multiplayer_manager.set_script(MultiplayerManagerScript)
	_multiplayer_manager.name = "MultiplayerManager"
	add_child(_multiplayer_manager)

	# Set spawn parent so remote players appear in the scene
	_multiplayer_manager.set_spawn_parent(self)

	# Wire ChainManager multiplayer signals → multiplayer_manager
	ChainManager.mp_sync_received.connect(_multiplayer_manager.on_player_sync)
	ChainManager.mp_player_joined.connect(_multiplayer_manager.on_player_join)
	ChainManager.mp_player_left.connect(_multiplayer_manager.on_player_leave)
	ChainManager.mp_position_received.connect(_multiplayer_manager.on_position_update)
	ChainManager.vc_speaking_received.connect(_multiplayer_manager.on_speaking_update)

	# Wire player count → HUD
	_multiplayer_manager.player_count_changed.connect(_on_mp_player_count_changed)
	_multiplayer_manager.player_joined.connect(_on_mp_player_joined)
	_multiplayer_manager.player_left.connect(_on_mp_player_left)

	# Set local player info and activate
	var wallet := ChainManager.connected_wallet
	var username := GameManager.player_identity
	var tier: int = ChainManager.get_cached_progression().get("evolutionTier", 0)
	if not wallet.is_empty():
		_multiplayer_manager.set_local_player(player, wallet, username, tier)
		_multiplayer_manager.activate()
		# Join the multiplayer channel for the current territory
		if not GameManager.territory_address.is_empty():
			ChainManager.join_multiplayer_channel(GameManager.territory_address)

	# If wallet connects later, join then
	ChainManager.wallet_connected.connect(_on_mp_wallet_connected)


func _on_mp_wallet_connected(address: String) -> void:
	## Wallet connected after scene was loaded — join multiplayer channel.
	if _multiplayer_manager:
		var username := GameManager.player_identity
		var tier: int = ChainManager.get_cached_progression().get("evolutionTier", 0)
		_multiplayer_manager.set_local_player(player, address, username, tier)
		_multiplayer_manager.activate()
		if not GameManager.territory_address.is_empty():
			ChainManager.join_multiplayer_channel(GameManager.territory_address)


func _on_mp_player_count_changed(count: int) -> void:
	## Update HUD player count indicator.
	if hud and hud.has_method("update_player_count"):
		hud.update_player_count(count)


func _on_mp_player_joined(wallet: String, username: String) -> void:
	## Show join toast.
	if _achievement_toast and _achievement_toast.has_method("show_generic"):
		_achievement_toast.show_generic(
			"%s joined" % username,
			wallet.left(6) + ".." + wallet.right(4),
		)


func _on_mp_player_left(wallet: String, username: String) -> void:
	## Show leave toast.
	if _achievement_toast and _achievement_toast.has_method("show_generic"):
		_achievement_toast.show_generic(
			"%s left" % username,
			wallet.left(6) + ".." + wallet.right(4),
		)


func _notification(what: int) -> void:
	## Clean up multiplayer on scene exit.
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if _multiplayer_manager and _multiplayer_manager.has_method("deactivate"):
			_multiplayer_manager.deactivate()
		ChainManager.leave_multiplayer_channel()


# ─── Debug Territory Presets (F9) ────────────────────────────────────────

const DEBUG_PRESETS: Array[Dictionary] = [
	{"name": "Low Power", "charge": 500_000_000_000, "hypo": 0, "epi": 0, "lat": 0.0, "phi": 0, "eta": 0, "mu": 0},
	{"name": "High Power", "charge": 900_000_000_000, "hypo": 0, "epi": 0, "lat": 0.0, "phi": 500_000_000_000_000, "eta": 200_000_000_000_000, "mu": 800_000_000_000_000},
	{"name": "High Activity", "charge": 100_000_000_000, "hypo": 600_000_000_000, "epi": 500_000_000_000, "lat": 0.0, "phi": 0, "eta": 0, "mu": 0},
	{"name": "Polar", "charge": 300_000_000_000, "hypo": 200_000_000_000, "epi": 100_000_000_000, "lat": 75.0, "phi": 0, "eta": 0, "mu": 300_000_000_000_000},
	{"name": "Equatorial", "charge": 300_000_000_000, "hypo": 200_000_000_000, "epi": 100_000_000_000, "lat": -10.0, "phi": 400_000_000_000_000, "eta": 100_000_000_000_000, "mu": 0},
	{"name": "All Max", "charge": 999_000_000_000, "hypo": 800_000_000_000, "epi": 700_000_000_000, "lat": 45.0, "phi": 900_000_000_000_000, "eta": 600_000_000_000_000, "mu": 900_000_000_000_000},
]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_territory"):
		_cycle_debug_territory()

	# V key: mount/dismount vehicle
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		_toggle_vehicle()

	# Backtick/tilde key: toggle console
	if event is InputEventKey and event.pressed and event.keycode == KEY_QUOTELEFT:
		_toggle_console()

	# F3 key: toggle performance monitor
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_toggle_monitor_overlay()


# ─── Debug Tools (Console & Monitor) ──────────────────────────────────

func _init_debug_tools() -> void:
	## Create console UI and performance monitor overlay.

	# Console container — bottom-left panel, hidden by default
	_console_container = VBoxContainer.new()
	_console_container.set_script(ConsoleContainerScript)
	_console_container.name = "ConsoleContainer"
	_console_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_console_container.anchor_left = 0.0
	_console_container.anchor_top = 0.55
	_console_container.anchor_right = 0.45
	_console_container.anchor_bottom = 1.0
	_console_container.offset_left = 8.0
	_console_container.offset_top = 0.0
	_console_container.offset_right = -8.0
	_console_container.offset_bottom = -8.0
	_console_container.visible = false
	hud.add_child(_console_container)

	# Monitor overlay — top-right, hidden by default
	_monitor_overlay = VBoxContainer.new()
	_monitor_overlay.set_script(MonitorOverlayScript)
	_monitor_overlay.name = "MonitorOverlay"
	_monitor_overlay.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_monitor_overlay.anchor_left = 0.78
	_monitor_overlay.anchor_top = 0.02
	_monitor_overlay.anchor_right = 0.99
	_monitor_overlay.anchor_bottom = 0.6
	_monitor_overlay.visible = false
	hud.add_child(_monitor_overlay)

	# Register game-specific console commands
	_game_console = GameConsole.new()
	_game_console.initialize(player, _terrain_material, _sky_material)
	var console_node := get_node_or_null("/root/Console")
	if console_node and console_node.has_method("create_command"):
		console_node.create_command("standing", cmd_standing,
			"Force QING Standing tier 0-3 (fair size); -1 = live on-chain data.")


func _toggle_console() -> void:
	## Toggle the debug console visibility.
	if _console_container:
		_console_container.visible = not _console_container.visible
		if _console_container.visible:
			# Pause game input while console is open (let typing work)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_monitor_overlay() -> void:
	## Toggle the performance monitor overlay.
	if _monitor_overlay:
		_monitor_overlay.visible = not _monitor_overlay.visible


# ─── Ambient Effects (Dust & Shimmer) ──────────────────────────────────

func _spawn_dust_particles() -> void:
	## Create ambient dust motes near the player, visible when walking on regolith.
	_dust_particles = GPUParticles3D.new()
	_dust_particles.set_script(DustParticlesScript)
	_dust_particles.name = "DustParticles"
	add_child(_dust_particles)
	_dust_particles.initialize(player)

	# Apply current activity level if territory state is already loaded
	if GameManager.has_territory_state:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		_dust_particles.set_activity_level(activity)


func _spawn_heat_shimmer() -> void:
	## Create heat distortion overlay that follows the player.
	## Only visible when territory has significant terraform power.
	_heat_shimmer = MeshInstance3D.new()
	_heat_shimmer.set_script(HeatShimmerScript)
	_heat_shimmer.name = "HeatShimmer"
	add_child(_heat_shimmer)
	_heat_shimmer.initialize(player)

	# Apply current power level if territory state is already loaded
	if GameManager.has_territory_state:
		var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
		_heat_shimmer.set_power_level(power)


func _spawn_vegetation() -> void:
	## Create chunked alien vegetation that emerges with terraforming.
	_vegetation_manager = Node3D.new()
	_vegetation_manager.set_script(VegetationManagerScript)
	_vegetation_manager.name = "VegetationManager"
	add_child(_vegetation_manager)

	var biome := BiomeSystem.get_biome(GameManager.terrain_seed)
	var cam := get_viewport().get_camera_3d()
	_vegetation_manager.initialize(territory, cam, biome)

	# Cache the vegetation shader material for beat flash control
	if _vegetation_manager.has_method("get_shader_material"):
		_veg_material = _vegetation_manager.get_shader_material()

	# Apply current state if territory data already loaded
	if GameManager.has_territory_state:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
		_vegetation_manager.set_territory_state(activity, power)


func _spawn_rock_scatter() -> void:
	## Scatter boulders on steep terrain slopes for visual detail.
	_rock_scatter = Node3D.new()
	_rock_scatter.set_script(RockScatterScript)
	_rock_scatter.name = "RockScatter"
	add_child(_rock_scatter)
	var biome := BiomeSystem.get_biome(GameManager.terrain_seed)
	_rock_scatter.initialize(GameManager.terrain_seed, territory, biome)


func _spawn_footprint_system() -> void:
	## Create footstep dust puffs and landing clouds.
	_footprint_system = Node3D.new()
	_footprint_system.set_script(FootprintSystemScript)
	_footprint_system.name = "FootprintSystem"
	add_child(_footprint_system)
	_footprint_system.initialize(player)


func _spawn_crystal_scatter() -> void:
	## Spawn crystalline mineral formations that grow with territory power.
	_crystal_scatter = Node3D.new()
	_crystal_scatter.set_script(CrystalScatterScript)
	_crystal_scatter.name = "CrystalScatter"
	add_child(_crystal_scatter)
	var biome := BiomeSystem.get_biome(GameManager.terrain_seed)
	_crystal_scatter.initialize(GameManager.terrain_seed, territory, biome)

	# Apply current power if territory state is already loaded
	if GameManager.has_territory_state:
		var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
		_crystal_scatter.set_territory_power(power)


func _spawn_atmospheric_fog() -> void:
	## Create volumetric atmospheric haze particles that appear with terraforming.
	_atm_fog = GPUParticles3D.new()
	_atm_fog.set_script(AtmosphericFogScript)
	_atm_fog.name = "AtmosphericFog"
	add_child(_atm_fog)
	_atm_fog.initialize(player)

	# Apply current activity if territory data already loaded
	if GameManager.has_territory_state:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		_atm_fog.set_atmo_activity(activity)


func _spawn_dust_devils() -> void:
	## Create dust devil spawner — swirling vortex columns drift across terrain.
	_dust_devil_spawner = Node3D.new()
	_dust_devil_spawner.set_script(DustDevilSpawnerScript)
	_dust_devil_spawner.name = "DustDevilSpawner"
	add_child(_dust_devil_spawner)
	_dust_devil_spawner.initialize(territory, player)

	if GameManager.has_territory_state:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		_dust_devil_spawner.set_activity(activity)


func _spawn_ambient_audio() -> void:
	## Create terrain-aware ambient audio with procedural sounds.
	var AmbientAudioScript = preload("res://scripts/audio/ambient_audio.gd")
	_ambient_audio = Node3D.new()
	_ambient_audio.set_script(AmbientAudioScript)
	_ambient_audio.name = "AmbientAudio"
	add_child(_ambient_audio)
	_ambient_audio.initialize(player, territory,
		Vector3(BEAT_STATION_X, 0.0, BEAT_STATION_Z))

	if GameManager.has_territory_state:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		_ambient_audio.set_territory_activity(activity)


const ANTENNA_X: float = -50.0
const ANTENNA_Z: float = 0.0
const LANDING_X: float = 0.0
const LANDING_Z: float = 100.0

func _spawn_debris_scatter() -> void:
	_debris_scatter = Node3D.new()
	_debris_scatter.set_script(DebrisScatterScript)
	_debris_scatter.name = "DebrisScatter"
	add_child(_debris_scatter)
	_debris_scatter.initialize(territory, GameManager.terrain_seed)


func _spawn_antenna_array() -> void:
	_antenna_array = Node3D.new()
	_antenna_array.set_script(AntennaArrayScript)
	_antenna_array.name = "AntennaArray"
	var ant_y: float = territory.get_height_at(ANTENNA_X, ANTENNA_Z)
	_antenna_array.position = Vector3(ANTENNA_X, ant_y, ANTENNA_Z)
	add_child(_antenna_array)
	_antenna_array.initialize(GameManager.terrain_seed)


func _spawn_landing_pad() -> void:
	# Flatten terrain for landing pad
	territory.flatten_area(LANDING_X, LANDING_Z, 18.0, 12.0, 12.0)
	_landing_pad = Node3D.new()
	_landing_pad.set_script(LandingPadScript)
	_landing_pad.name = "LandingPad"
	var pad_y: float = territory.get_height_at(LANDING_X, LANDING_Z)
	_landing_pad.position = Vector3(LANDING_X, pad_y, LANDING_Z)
	add_child(_landing_pad)
	_landing_pad.initialize(GameManager.terrain_seed)


func _spawn_pipe_network() -> void:
	_pipe_network = Node3D.new()
	_pipe_network.set_script(PipeNetworkScript)
	_pipe_network.name = "PipeNetwork"
	add_child(_pipe_network)
	_pipe_network.initialize(territory, GameManager.terrain_seed)
	if GameManager.has_territory_state:
		_pipe_network.update_territory_state()


func _spawn_surface_detail() -> void:
	_surface_detail = Node3D.new()
	_surface_detail.set_script(SurfaceDetailScript)
	_surface_detail.name = "SurfaceDetail"
	add_child(_surface_detail)
	_surface_detail.initialize(territory, GameManager.terrain_seed)


func _spawn_weather_system() -> void:
	_weather_system = Node.new()
	_weather_system.set_script(WeatherSystemScript)
	_weather_system.name = "WeatherSystem"
	add_child(_weather_system)

	# Pass sun reference for solar flare events
	if _sun_light:
		_weather_system.set_sun(_sun_light)

	# Pass structure positions for static discharge arcs
	var structure_positions: Array[Vector3] = []
	if _monument:
		structure_positions.append(_monument.position + Vector3(0.0, 15.0, 0.0))
	if _beat_station:
		structure_positions.append(_beat_station.position + Vector3(0.0, 10.0, 0.0))
	if _pub_building:
		structure_positions.append(_pub_building.position + Vector3(0.0, 8.0, 0.0))
	if _antenna_array:
		structure_positions.append(_antenna_array.position + Vector3(0.0, 20.0, 0.0))
	if _landing_pad:
		structure_positions.append(_landing_pad.position + Vector3(0.0, 5.0, 0.0))
	if structure_positions.size() >= 2:
		_weather_system.set_structure_positions(structure_positions)

	# Set initial activity level from territory state
	if GameManager.has_territory_state:
		var bar_sum := GameManager.territory_hypobar + GameManager.territory_epibar
		var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)
		_weather_system.set_activity(activity)

	# Initialize with player and terrain
	_weather_system.initialize(player, territory_manager)

	# Wire weather_changed signal to HUD for indicator + atmosphere shader
	_weather_system.weather_changed.connect(_on_weather_changed)


func _on_weather_changed(state: int) -> void:
	## Weather event started or ended — update HUD indicator and atmosphere shader.
	# Update HUD weather indicator
	if hud and hud.has_method("update_weather_indicator"):
		hud.update_weather_indicator(state, _weather_system.get_weather_name())

	# Update atmosphere shader for dust storm fog
	if _sky_material:
		var storm := 0.0
		if state == 1:  # DUST_STORM
			storm = 0.6  # Moderate fog density during dust storms
		_sky_material.set_shader_parameter("storm_intensity", storm)

	# Wire meteor impact signals for screen shake
	if state == 2:  # METEOR_SHOWER
		var active_event: Node = _weather_system.get("_active_event_node")
		if active_event and active_event.has_signal("meteor_impact"):
			if not active_event.meteor_impact.is_connected(_on_meteor_impact):
				active_event.meteor_impact.connect(_on_meteor_impact)

	# Wire static discharge signals for screen shake
	if state == 4:  # STATIC_DISCHARGE
		var active_event: Node = _weather_system.get("_active_event_node")
		if active_event and active_event.has_signal("discharge_flash"):
			if not active_event.discharge_flash.is_connected(_on_discharge_flash):
				active_event.discharge_flash.connect(_on_discharge_flash)


func _on_meteor_impact(impact_pos: Vector3) -> void:
	## Meteor hit ground — trigger screen shake proportional to distance.
	if not player:
		return
	var dist := player.global_position.distance_to(impact_pos)
	var shake_intensity := clampf(1.0 - dist / 100.0, 0.05, 0.5)
	_beat_camera_shake_velocity += shake_intensity * 2.0


func _on_discharge_flash(flash_pos: Vector3) -> void:
	## Lightning arc fired — trigger brief screen shake.
	if not player:
		return
	var dist := player.global_position.distance_to(flash_pos)
	var shake_intensity := clampf(1.0 - dist / 80.0, 0.02, 0.3)
	_beat_camera_shake_velocity += shake_intensity * 1.5

	# Brief white flash on HUD
	if hud and hud.has_method("flash_screen"):
		hud.flash_screen(Color(0.7, 0.8, 1.0, 0.1), 0.1)


func _spawn_flag_manager() -> void:
	_flag_manager = Node3D.new()
	_flag_manager.set_script(FlagManagerScript)
	_flag_manager.name = "FlagManager"
	add_child(_flag_manager)
	_flag_manager.initialize(territory_manager)

	# Wire flag loading from chain manager
	ChainManager.flags_loaded.connect(_on_flags_loaded_world)
	ChainManager.flag_planted.connect(_on_flag_planted_world)

	# Auto-fetch flags after territory loads
	if not GameManager.territory_address.is_empty():
		ChainManager.load_territory_flags()


func _on_flags_loaded_world(flags: Array) -> void:
	## Flags fetched from API — load into flag manager + update minimap.
	if _flag_manager:
		_flag_manager.load_flags(flags)
		# Update minimap with flag positions
		hud.update_minimap_flags(_flag_manager.get_flag_positions())


func _on_flag_planted_world(success: bool, _message: String) -> void:
	## Flag was planted — add local flag at player position + update minimap.
	if success and _flag_manager and player:
		var data := {
			"wallet": ChainManager.connected_wallet,
			"username": GameManager.player_identity,
			"message": _message,
		}
		_flag_manager.plant_flag_at(player.global_position, data)
		# Update minimap with new flag positions
		hud.update_minimap_flags(_flag_manager.get_flag_positions())


func _setup_minimap() -> void:
	## Initialize minimap on HUD and register all POIs.
	hud.create_minimap(territory)

	# Register monument
	if _monument:
		hud.register_minimap_poi("Monument", _monument.position,
			Color(0.8, 0.6, 1.0), 0)  # POIType.MONUMENT

	# Register beat station
	if _beat_station:
		hud.register_minimap_poi("Beat Station", _beat_station.position,
			Color(0.3, 0.8, 1.0), 1)  # POIType.BEAT_STATION

	# Register pub
	if _pub_building:
		hud.register_minimap_poi("Lunar Cantina", _pub_building.position,
			Color(1.0, 0.7, 0.3), 2)  # POIType.PUB

	# Register the fair
	if _funfair:
		hud.register_minimap_poi("Affection Fair", _funfair.position,
			Color(1.0, 0.45, 0.75), 2)

	# Register vehicle spawn
	if _vehicle:
		hud.register_minimap_poi("Vehicle", _vehicle.position,
			Color(0.6, 0.9, 0.4), 3)  # POIType.VEHICLE

	# Register antenna array
	if _antenna_array:
		hud.register_minimap_poi("Comm Array", _antenna_array.position,
			Color(0.9, 0.4, 0.4), 0)

	# Register landing pad
	if _landing_pad:
		hud.register_minimap_poi("Landing Pad", _landing_pad.position,
			Color(0.9, 0.9, 0.5), 0)


func _init_tutorial() -> void:
	## Initialize tutorial system — auto-starts on first launch.
	## Check the static method to see if tutorial was already completed.
	var TutSystemClass = load("res://scripts/ui/tutorial_system.gd")
	if TutSystemClass.is_tutorial_complete():
		return  # Already completed, skip

	_tutorial_system = CanvasLayer.new()
	_tutorial_system.set_script(TutorialSystemScript)
	_tutorial_system.name = "TutorialSystem"
	add_child(_tutorial_system)
	_tutorial_system.tutorial_completed.connect(_on_tutorial_completed)
	_tutorial_system.start_tutorial(player)

	# Wire monument interaction to tutorial notification
	player.monument_interact.connect(func() -> void:
		if _tutorial_system and _tutorial_system.is_active():
			_tutorial_system.notify_monument_interact()
	)


func start_tutorial_replay() -> void:
	## Called from settings menu to replay the tutorial.
	if _tutorial_system and _tutorial_system.is_active():
		return  # Already running

	if not _tutorial_system:
		_tutorial_system = CanvasLayer.new()
		_tutorial_system.set_script(TutorialSystemScript)
		_tutorial_system.name = "TutorialSystem"
		add_child(_tutorial_system)
		_tutorial_system.tutorial_completed.connect(_on_tutorial_completed)
	_tutorial_system.start_tutorial(player)


func _on_tutorial_completed() -> void:
	print("[Main] Tutorial completed or skipped")


func _toggle_vehicle() -> void:
	## Mount or dismount the lunar rover when pressing V.
	if not _vehicle or not is_instance_valid(_vehicle):
		return

	if _is_in_vehicle:
		# Dismount
		_vehicle.dismount()
		# Re-enable weapon system input when on foot
		if _weapon_system:
			_weapon_system.set_process_unhandled_input(true)
	else:
		# Check if player is close enough to mount
		var dist := player.global_position.distance_to(_vehicle.global_position)
		if dist > 8.0:
			hud.show_interact_prompt("Too far from vehicle")
			get_tree().create_timer(1.5).timeout.connect(func(): hud.hide_interact_prompt())
			return
		_vehicle.mount(player)
		# Disable weapon system input while driving
		if _weapon_system:
			_weapon_system.set_process_unhandled_input(false)
		hud.show_interact_prompt("Press V to dismount")
		get_tree().create_timer(2.0).timeout.connect(func(): hud.hide_interact_prompt())


func _cycle_debug_territory() -> void:
	_debug_territory_preset += 1
	if _debug_territory_preset >= DEBUG_PRESETS.size():
		# Reset to off
		_debug_territory_preset = -1
		GameManager.territory_charge = 0
		GameManager.territory_hypobar = 0
		GameManager.territory_epibar = 0
		GameManager.territory_latitude = 0.0
		GameManager.faung_scalars = {}
		GameManager.has_territory_state = false
		_apply_territory_state_to_shaders()
		if _monument and _monument.has_method("update_territory_state"):
			_monument.update_territory_state()
		if _beat_station and _beat_station.has_method("update_territory_state"):
			_beat_station.update_territory_state()
		print("[Debug] Territory effects: OFF")
		return

	var preset: Dictionary = DEBUG_PRESETS[_debug_territory_preset]
	GameManager.territory_charge = preset.charge
	GameManager.territory_hypobar = preset.hypo
	GameManager.territory_epibar = preset.epi
	GameManager.territory_latitude = preset.lat
	GameManager.faung_scalars = {"phi": preset.phi, "eta": preset.eta, "mu": preset.mu}
	GameManager.has_territory_state = true
	_apply_territory_state_to_shaders()
	if _monument and _monument.has_method("update_territory_state"):
		_monument.update_territory_state()
	if _beat_station and _beat_station.has_method("update_territory_state"):
		_beat_station.update_territory_state()
	print("[Debug] Territory preset: %s" % preset.name)
