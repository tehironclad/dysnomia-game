extends Node
## Dynamic weather event system for Dysnomia territories.
## State machine cycles between CLEAR and random weather events.
## Events are weighted by territory activity (terraform count, power levels).
## Creates child event nodes (DustStorm, MeteorShower, SolarFlare, StaticDischarge)
## that self-manage their visuals and gameplay effects.

const DustStormScript = preload("res://scripts/world/dust_storm.gd")
const MeteorShowerScript = preload("res://scripts/world/meteor_shower.gd")
const SolarFlareScript = preload("res://scripts/world/solar_flare.gd")
const StaticDischargeScript = preload("res://scripts/world/static_discharge.gd")

signal weather_changed(state: int)

enum WeatherState {
	CLEAR = 0,
	DUST_STORM = 1,
	METEOR_SHOWER = 2,
	SOLAR_FLARE = 3,
	STATIC_DISCHARGE = 4,
}

# ─── Timing Constants ────────────────────────────────────────────────────
const CLEAR_DURATION_MIN: float = 180.0   # 3 minutes minimum calm
const CLEAR_DURATION_MAX: float = 480.0   # 8 minutes maximum calm
const EVENT_DURATION_MIN: float = 30.0    # Shortest event
const EVENT_DURATION_MAX: float = 120.0   # Longest event
const TERRITORY_HALF: float = 200.0       # 400m / 2

# ─── Default event weights (higher = more likely) ────────────────────────
# Weights can be shifted by territory activity via set_activity()
const BASE_WEIGHTS: Dictionary = {
	WeatherState.DUST_STORM: 35,
	WeatherState.METEOR_SHOWER: 30,
	WeatherState.SOLAR_FLARE: 20,
	WeatherState.STATIC_DISCHARGE: 15,
}

# ─── State ───────────────────────────────────────────────────────────────
var _current_state: int = WeatherState.CLEAR
var _state_timer: float = 0.0
var _event_duration: float = 0.0
var _player: Node3D
var _terrain_gen: Node3D
var _sun: DirectionalLight3D
var _structure_positions: Array[Vector3] = []

var _active_event_node: Node = null
var _activity: float = 0.0          # 0..1 territory activity level
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _initialized: bool = false
var _event_weights: Dictionary = BASE_WEIGHTS.duplicate()


func initialize(player: Node3D, terrain_gen: Node3D) -> void:
	_player = player
	_terrain_gen = terrain_gen
	_rng.seed = Time.get_ticks_msec()
	_state_timer = _rng.randf_range(CLEAR_DURATION_MIN, CLEAR_DURATION_MAX)
	_current_state = WeatherState.CLEAR
	_initialized = true


func set_sun(sun: DirectionalLight3D) -> void:
	## Store a reference to the scene's DirectionalLight3D for SolarFlare events.
	_sun = sun


func set_structure_positions(positions: Array[Vector3]) -> void:
	## Provide world-space positions of structures for StaticDischarge arcs.
	_structure_positions = positions


func set_activity(activity: float) -> void:
	## Territory activity level (0..1). Higher activity biases toward
	## more dramatic events (meteor showers, static discharges).
	_activity = clampf(activity, 0.0, 1.0)
	_recalculate_weights()


func get_current_weather() -> int:
	return _current_state


func get_weather_name() -> String:
	match _current_state:
		WeatherState.CLEAR:
			return "Clear"
		WeatherState.DUST_STORM:
			return "Dust Storm"
		WeatherState.METEOR_SHOWER:
			return "Meteor Shower"
		WeatherState.SOLAR_FLARE:
			return "Solar Flare"
		WeatherState.STATIC_DISCHARGE:
			return "Static Discharge"
	return "Unknown"


func force_weather(state: int) -> void:
	## Debug: immediately transition to a specific weather state.
	## Pass WeatherState.CLEAR to end current event.
	if state == WeatherState.CLEAR:
		_end_current_event()
		_transition_to_clear()
		return
	_end_current_event()
	var duration := _rng.randf_range(EVENT_DURATION_MIN, EVENT_DURATION_MAX)
	_start_event(state, duration)


func _process(delta: float) -> void:
	if not _initialized:
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _current_state == WeatherState.CLEAR:
			_pick_and_start_event()
		else:
			_end_current_event()
			_transition_to_clear()


# ─── State Transitions ───────────────────────────────────────────────────

func _transition_to_clear() -> void:
	_current_state = WeatherState.CLEAR
	_state_timer = _rng.randf_range(CLEAR_DURATION_MIN, CLEAR_DURATION_MAX)
	_event_duration = 0.0
	weather_changed.emit(WeatherState.CLEAR)


func _pick_and_start_event() -> void:
	var chosen_state := _weighted_random_event()
	var duration := _rng.randf_range(EVENT_DURATION_MIN, EVENT_DURATION_MAX)

	# Higher activity = slightly longer events
	duration *= lerpf(0.8, 1.3, _activity)
	duration = clampf(duration, EVENT_DURATION_MIN, EVENT_DURATION_MAX)

	_start_event(chosen_state, duration)


func _start_event(state: int, duration: float) -> void:
	_current_state = state
	_state_timer = duration
	_event_duration = duration

	# Create the appropriate event child node
	match state:
		WeatherState.DUST_STORM:
			_spawn_dust_storm(duration)
		WeatherState.METEOR_SHOWER:
			_spawn_meteor_shower(duration)
		WeatherState.SOLAR_FLARE:
			_spawn_solar_flare(duration)
		WeatherState.STATIC_DISCHARGE:
			_spawn_static_discharge(duration)

	weather_changed.emit(state)


func _end_current_event() -> void:
	if _active_event_node and is_instance_valid(_active_event_node):
		# Give event a chance to clean up (restore sun, etc.)
		if _active_event_node.has_method("cleanup"):
			_active_event_node.cleanup()
		_active_event_node.queue_free()
		_active_event_node = null


# ─── Event Spawners ──────────────────────────────────────────────────────

func _spawn_dust_storm(duration: float) -> void:
	var storm := Node3D.new()
	storm.set_script(DustStormScript)
	storm.name = "DustStorm"
	add_child(storm)
	storm.set_duration(duration)
	storm.initialize(_player)
	_active_event_node = storm


func _spawn_meteor_shower(duration: float) -> void:
	var shower := Node3D.new()
	shower.set_script(MeteorShowerScript)
	shower.name = "MeteorShower"
	add_child(shower)
	shower.set_duration(duration)
	shower.initialize(_player)
	_active_event_node = shower


func _spawn_solar_flare(duration: float) -> void:
	var flare := Node.new()
	flare.set_script(SolarFlareScript)
	flare.name = "SolarFlare"
	add_child(flare)
	flare.set_duration(duration)
	flare.initialize(_player, _sun)
	_active_event_node = flare


func _spawn_static_discharge(duration: float) -> void:
	var discharge := Node3D.new()
	discharge.set_script(StaticDischargeScript)
	discharge.name = "StaticDischarge"
	add_child(discharge)
	discharge.set_duration(duration)

	# Build structure positions if not explicitly provided
	var positions := _structure_positions.duplicate()
	if positions.is_empty():
		positions = _generate_fallback_positions()
	discharge.initialize(_player, positions)
	_active_event_node = discharge


# ─── Weight Calculation ──────────────────────────────────────────────────

func _recalculate_weights() -> void:
	## Adjust event weights based on territory activity.
	## Higher activity → more dramatic events (meteor, static).
	## Lower activity → more calm events (dust storm, solar flare).
	_event_weights = BASE_WEIGHTS.duplicate()

	# Activity shifts: dramatic events get boosted
	var dramatic_boost := int(_activity * 15.0)
	var calm_boost := int((1.0 - _activity) * 10.0)

	_event_weights[WeatherState.DUST_STORM] += calm_boost
	_event_weights[WeatherState.SOLAR_FLARE] += calm_boost
	_event_weights[WeatherState.METEOR_SHOWER] += dramatic_boost
	_event_weights[WeatherState.STATIC_DISCHARGE] += dramatic_boost


func _weighted_random_event() -> int:
	## Pick a random weather event using weighted probabilities.
	var total_weight: int = 0
	for w in _event_weights.values():
		total_weight += w

	if total_weight <= 0:
		return WeatherState.DUST_STORM

	var roll := _rng.randi_range(1, total_weight)
	var cumulative: int = 0
	for state in _event_weights:
		cumulative += _event_weights[state]
		if roll <= cumulative:
			return state

	return WeatherState.DUST_STORM


# ─── Helpers ─────────────────────────────────────────────────────────────

func _generate_fallback_positions() -> Array[Vector3]:
	## If no structure positions were provided, generate some random elevated
	## points across the territory for lightning arc endpoints.
	var positions: Array[Vector3] = []
	var fallback_rng := RandomNumberGenerator.new()
	fallback_rng.seed = Time.get_ticks_msec() + 7919

	for i in range(8):
		var x := fallback_rng.randf_range(-TERRITORY_HALF * 0.7, TERRITORY_HALF * 0.7)
		var z := fallback_rng.randf_range(-TERRITORY_HALF * 0.7, TERRITORY_HALF * 0.7)
		var y := 10.0
		if _terrain_gen and is_instance_valid(_terrain_gen) and _terrain_gen.has_method("get_height_at"):
			y = _terrain_gen.get_height_at(x, z) + fallback_rng.randf_range(5.0, 15.0)
		positions.append(Vector3(x, y, z))
	return positions


func get_event_time_remaining() -> float:
	## Returns seconds remaining in current event, or 0 if clear.
	if _current_state == WeatherState.CLEAR:
		return 0.0
	return maxf(_state_timer, 0.0)


func get_event_progress() -> float:
	## Returns 0..1 how far through the current event we are.
	if _current_state == WeatherState.CLEAR or _event_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _state_timer / _event_duration, 0.0, 1.0)


func get_clear_time_remaining() -> float:
	## Returns seconds until next event, or 0 if an event is active.
	if _current_state != WeatherState.CLEAR:
		return 0.0
	return maxf(_state_timer, 0.0)
