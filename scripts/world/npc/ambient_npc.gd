class_name AmbientNPC
extends Node3D
## A background citizen built from the game's own teddy-astronaut model (player_model.gd),
## so locals look like players. Purely visual: no physics body, no chain state.
##
##   var npc := AmbientNPC.new()
##   parent.add_child(npc)
##   npc.setup(rng_seed, [Vector3(...), Vector3(...)])   # walks a loop between points
##   npc.setup(rng_seed, [], Vector3.FORWARD)            # stands idle facing a direction
##
## Points are in the parent's local space; y is the floor height there.

const PlayerModelScript = preload("res://scripts/player/player_model.gd")

@export var walk_speed: float = 1.4
@export var pause_range: Vector2 = Vector2(1.5, 6.0)  # Seconds to linger at each point

var _model: Node3D
var _points: Array = []
var _target_idx: int = 0
var _pause: float = 0.0
var _rng := RandomNumberGenerator.new()
var _height_fn: Callable = Callable()  # Optional (x, z) -> floor y in parent space


func setup(seed_value: int, points: Array = [], facing: Vector3 = Vector3.FORWARD, height_fn: Callable = Callable()) -> void:
	_rng.seed = seed_value
	_points = points
	_height_fn = height_fn
	_model = Node3D.new()
	_model.set_script(PlayerModelScript)
	_model.name = "Model"
	_model.rotation.y = PI  # player_model faces +Z; we steer with -Z forward like the player scene
	add_child(_model)
	_model.apply_appearance(PlayerAppearance.generate([
		_rng.randi(), _rng.randi(), _rng.randi()]))
	# Locals don't carry the player's crow or shoulder turret
	for n in ["CrowPivot", "LaserMountPivot"]:
		var c := _model.find_child(n, true, false)
		if c:
			c.visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
	walk_speed *= _rng.randf_range(0.8, 1.2)
	if _points.size() > 0:
		position = _points[0]
		_target_idx = 1 % _points.size()
		_pause = _rng.randf_range(0.0, pause_range.y)
	elif facing.length() > 0.01:
		look_at(global_position - facing, Vector3.UP)


func _process(delta: float) -> void:
	if _model == null:
		return
	if _points.size() < 2:
		_model.update_movement(Vector3.ZERO, true, false)
		return
	if _pause > 0.0:
		_pause -= delta
		_model.update_movement(Vector3.ZERO, true, false)
		return
	var target: Vector3 = _points[_target_idx]
	var to := target - position
	to.y = 0.0
	if to.length() < 0.25:
		_target_idx = (_target_idx + 1) % _points.size()
		_pause = _rng.randf_range(pause_range.x, pause_range.y)
		return
	var dir := to.normalized()
	position += dir * walk_speed * delta
	if _height_fn.is_valid():
		position.y = _height_fn.call(position.x, position.z)
	else:
		position.y = lerpf(position.y, target.y, clampf(delta * 2.0, 0.0, 1.0))
	# Turn smoothly toward travel direction (-Z forward)
	var want := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * 6.0, 0.0, 1.0))
	_model.update_movement(dir * walk_speed, true, false)
