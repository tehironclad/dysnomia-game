extends Node3D
## Manages 1-3 active dust devils drifting across the terrain.
## More active territories spawn more / larger dust devils.

const DustDevilScript = preload("res://scripts/world/dust_devil.gd")
const MAX_DEVILS: int = 3
const SPAWN_INTERVAL_BASE: float = 15.0  # Seconds between spawn attempts
const TERRITORY_HALF: float = 200.0

var _terrain_gen: Node3D
var _player: Node3D
var _activity: float = 0.0
var _spawn_timer: float = 5.0  # First devil spawns after 5s
var _active_devils: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func initialize(terrain_gen: Node3D, p_player: Node3D) -> void:
	_terrain_gen = terrain_gen
	_player = p_player
	_rng.seed = Time.get_ticks_msec()


func set_activity(activity: float) -> void:
	_activity = activity


func _process(delta: float) -> void:
	# Clean up freed devils
	_active_devils = _active_devils.filter(func(d): return is_instance_valid(d))

	if _activity < 0.05:
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL_BASE / (0.5 + _activity)
		_try_spawn_devil()


func _try_spawn_devil() -> void:
	var max_count := int(ceilf(lerpf(1.0, float(MAX_DEVILS), _activity)))
	if _active_devils.size() >= max_count:
		return

	# Spawn at random position within territory, within 150m of player
	var px := _player.global_position.x if _player and is_instance_valid(_player) else 0.0
	var pz := _player.global_position.z if _player and is_instance_valid(_player) else 0.0
	var spawn_x := clampf(px + _rng.randf_range(-100.0, 100.0), -TERRITORY_HALF, TERRITORY_HALF)
	var spawn_z := clampf(pz + _rng.randf_range(-100.0, 100.0), -TERRITORY_HALF, TERRITORY_HALF)
	var spawn_y := 0.0
	if _terrain_gen and is_instance_valid(_terrain_gen) and _terrain_gen.has_method("get_height_at"):
		spawn_y = _terrain_gen.get_height_at(spawn_x, spawn_z) + 0.5

	var devil := GPUParticles3D.new()
	devil.set_script(DustDevilScript)
	devil.name = "DustDevil_%d" % _active_devils.size()
	add_child(devil)

	var p_lifetime := _rng.randf_range(15.0, 30.0)
	var drift_dir := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
	var drift_speed := _rng.randf_range(1.0, 3.0)
	var scale_mult := lerpf(0.6, 1.5, _activity) * _rng.randf_range(0.8, 1.2)

	devil.initialize(_terrain_gen, Vector3(spawn_x, spawn_y, spawn_z),
		p_lifetime, drift_dir, drift_speed, scale_mult)

	_active_devils.append(devil)
