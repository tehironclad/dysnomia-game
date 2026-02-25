extends Node3D
## Spawns alien creatures across the territory surface.
## Creature types and spawn density are derived from territory seed.
## Creatures respawn after being killed (after a delay).

const CreatureScript = preload("res://scripts/world/creature.gd")

signal player_damaged(damage: float)
signal creature_killed(type: int, position: Vector3)

@export var max_creatures: int = 8
@export var spawn_radius: float = 120.0       # How far from center to spawn
@export var min_spawn_distance: float = 30.0   # Min distance from player to spawn
@export var respawn_delay: float = 30.0        # Seconds before a dead creature respawns

var _creatures: Array[CharacterBody3D] = []
var _player: Node3D
var _terrain: Node3D
var _seed: int = 0
var _spawn_timer: float = 0.0
var _respawn_queue: Array[Dictionary] = []  # [{time, type, pos}]
var _total_killed: int = 0


func initialize(seed_value: int, player: Node3D, terrain: Node3D) -> void:
	_seed = seed_value
	_player = player
	_terrain = terrain

	# Determine creature density from seed (some territories are more dangerous)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var creature_count := rng.randi_range(3, max_creatures)

	# Spawn initial creatures at random positions
	for i in range(creature_count):
		var type := rng.randi_range(0, 3)
		var pos := _random_spawn_position(rng)
		_spawn_creature(type, pos)


func _process(delta: float) -> void:
	_spawn_timer += delta

	# Process respawn queue
	var now := Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []
	for i in range(_respawn_queue.size()):
		if now >= _respawn_queue[i].time:
			var entry: Dictionary = _respawn_queue[i]
			var new_pos := _random_spawn_position_near_player()
			_spawn_creature(entry.type, new_pos)
			to_remove.append(i)

	# Remove processed respawns (reverse order to maintain indices)
	for i in range(to_remove.size() - 1, -1, -1):
		_respawn_queue.remove_at(to_remove[i])

	# Clean up freed creatures from the list
	var valid: Array[CharacterBody3D] = []
	for c in _creatures:
		if is_instance_valid(c):
			valid.append(c)
	_creatures = valid


func _spawn_creature(type: int, pos: Vector3) -> void:
	if not _player or not is_instance_valid(_player):
		return

	var creature := CharacterBody3D.new()
	creature.set_script(CreatureScript)
	creature.name = "Creature_%d" % _creatures.size()
	add_child(creature)
	creature.initialize(type, pos, _player, _terrain)

	# Connect signals
	creature.creature_died.connect(_on_creature_died)
	creature.creature_attacked_player.connect(_on_creature_attacked_player)

	_creatures.append(creature)


func _on_creature_died(creature: CharacterBody3D) -> void:
	_total_killed += 1
	var type: int = creature.creature_type if creature.has_method("take_damage") else 0
	creature_killed.emit(type, creature.global_position)

	# Queue respawn
	var respawn_time := Time.get_ticks_msec() / 1000.0 + respawn_delay
	_respawn_queue.append({"time": respawn_time, "type": type, "pos": Vector3.ZERO})


func _on_creature_attacked_player(damage: float) -> void:
	player_damaged.emit(damage)


func _random_spawn_position(rng: RandomNumberGenerator) -> Vector3:
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(min_spawn_distance, spawn_radius)
	var x := cos(angle) * dist
	var z := sin(angle) * dist
	var y := 0.0
	if _terrain and _terrain.has_method("get_height_at"):
		y = _terrain.get_height_at(x, z) + 1.0
	return Vector3(x, y, z)


func _random_spawn_position_near_player() -> Vector3:
	## Spawn at a position visible-ish to the player but not too close.
	if not _player or not is_instance_valid(_player):
		var rng := RandomNumberGenerator.new()
		return _random_spawn_position(rng)

	var angle := randf() * TAU
	var dist := randf_range(40.0, spawn_radius)
	var base := _player.global_position
	var x := base.x + cos(angle) * dist
	var z := base.z + sin(angle) * dist
	# Clamp to territory bounds
	x = clampf(x, -180.0, 180.0)
	z = clampf(z, -180.0, 180.0)
	var y := 0.0
	if _terrain and _terrain.has_method("get_height_at"):
		y = _terrain.get_height_at(x, z) + 1.0
	return Vector3(x, y, z)


func get_nearby_creatures(pos: Vector3, radius: float) -> Array[CharacterBody3D]:
	## Get all living creatures within radius of pos (for weapon targeting).
	var result: Array[CharacterBody3D] = []
	for c in _creatures:
		if is_instance_valid(c) and c.has_method("take_damage"):
			if c.health > 0 and c.global_position.distance_to(pos) < radius:
				result.append(c)
	return result


func get_total_killed() -> int:
	return _total_killed
