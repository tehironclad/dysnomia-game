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
##
## Locals get a seeded suit colour (the player keeps PulseChain purple), can sit or lean
## (set_pose), and cull themselves beyond CULL_DISTANCE so crowds stay cheap.

const HumanAvatarScript = preload("res://scripts/player/human_avatar.gd")

const CULL_DISTANCE := 70.0
## Work and leisure suits seen around a QING — seeded per local
const SUIT_COLORS := [
	Color(0.22, 0.14, 0.38),  # PulseChain purple
	Color(0.20, 0.24, 0.30),  # slate
	Color(0.85, 0.42, 0.10),  # hi-vis orange (crew)
	Color(0.82, 0.83, 0.86),  # classic white
	Color(0.10, 0.36, 0.40),  # teal
	Color(0.48, 0.10, 0.14),  # crimson
	Color(0.30, 0.34, 0.18),  # olive
	Color(0.12, 0.16, 0.34),  # navy
]

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
	_model = HumanAvatarScript.new()
	_model.name = "Model"
	_model.body_kind = "female" if _rng.randf() < 0.5 else "male"
	_model.rotation.y = PI  # avatar faces +Z; we steer with -Z forward like the player
	add_child(_model)
	_model.apply_appearance(PlayerAppearance.generate([_rng.randi(), _rng.randi(), _rng.randi()]))
	var suit: Color = SUIT_COLORS[_rng.randi() % SUIT_COLORS.size()]
	set_suit_color(suit)
	_apply_culling(_model)
	walk_speed *= _rng.randf_range(0.8, 1.2)
	if _points.size() > 0:
		position = _points[0]
		_target_idx = 1 % _points.size()
		_pause = _rng.randf_range(0.0, pause_range.y)
	elif facing.length() > 0.01:
		look_at(global_position + facing, Vector3.UP)  # root -Z = model front


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


func go_to(point: Vector3, linger: float = 4.0) -> void:
	## Walk to one point (parent-local) and stand there; e.g. the bartender heading to the taps.
	_points = [position, point]
	_target_idx = 1
	_pause = 0.0
	pause_range = Vector2(linger, linger)


func set_suit_color(c: Color) -> void:
	if _model and _model.has_method("set_suit_colors"):
		_model.set_suit_colors(c, c.darkened(0.35))


func set_pose(pose: String) -> void:
	## "stand" | "sit" | "lean". On the Quaternius avatar these hold a still idle;
	## "sit" lowers the body onto the seat the caller placed it at.
	_points = []
	_model.update_movement(Vector3.ZERO, true, false)
	_model.position.y = -0.45 if pose == "sit" else 0.0


func _apply_culling(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		g.visibility_range_end = CULL_DISTANCE
		g.visibility_range_end_margin = 6.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_apply_culling(c)
