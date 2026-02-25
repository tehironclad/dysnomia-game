extends CharacterBody3D
## Alien creature on Dysnomia's surface.
## Procedurally built from primitives, patrols/chases/attacks the player.
## Each creature type is derived from the territory seed for determinism.

signal creature_died(creature: CharacterBody3D)
signal creature_attacked_player(damage: float)

enum CreatureState { IDLE, PATROL, CHASE, ATTACK, HURT, DEAD }

# ─── Stats ──────────────────────────────────────────────────────────────
var creature_type: int = 0  # 0=Stalker, 1=Crawler, 2=Floater, 3=Burrower
var max_health: float = 50.0
var health: float = 50.0
var damage: float = 10.0
var move_speed: float = 4.0
var chase_speed: float = 7.0
var detect_range: float = 30.0
var attack_range: float = 2.5
var patrol_radius: float = 20.0

# ─── State ──────────────────────────────────────────────────────────────
var _state: int = CreatureState.IDLE
var _state_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _hurt_timer: float = 0.0
var _player: Node3D
var _spawn_pos: Vector3
var _patrol_target: Vector3
var _territory_gen: Node3D
var _anim_time: float = 0.0

# ─── Mesh References ───────────────────────────────────────────────────
var _body_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _eye_left: MeshInstance3D
var _eye_right: MeshInstance3D
var _leg_nodes: Array[Node3D] = []
var _body_mat: StandardMaterial3D
var _body_shader_mat: ShaderMaterial
var _eye_mat: StandardMaterial3D
var _model_root: Node3D  # Root of the new detailed model

const GRAVITY: float = 3.2  # Same low-g as player
const CREATURE_SHADER = preload("res://assets/shaders/creature.gdshader")


func initialize(type: int, spawn_position: Vector3, player: Node3D, terrain: Node3D) -> void:
	creature_type = type
	_spawn_pos = spawn_position
	position = spawn_position
	_player = player
	_territory_gen = terrain
	_patrol_target = spawn_position

	# Set stats per creature type
	match type:
		0:  # Stalker — fast, medium health, ambush predator
			max_health = 40.0
			damage = 12.0
			move_speed = 5.0
			chase_speed = 9.0
			detect_range = 35.0
			attack_range = 2.5
		1:  # Crawler — slow, tanky, strong melee
			max_health = 80.0
			damage = 20.0
			move_speed = 2.5
			chase_speed = 4.0
			detect_range = 20.0
			attack_range = 3.0
		2:  # Floater — aerial, weak, ranged-ish
			max_health = 25.0
			damage = 8.0
			move_speed = 6.0
			chase_speed = 8.0
			detect_range = 40.0
			attack_range = 5.0
		3:  # Burrower — ambush from underground
			max_health = 60.0
			damage = 15.0
			move_speed = 3.0
			chase_speed = 7.0
			detect_range = 15.0
			attack_range = 2.0

	health = max_health
	_build_model()
	_start_patrol()


func _build_model() -> void:
	## Build creature from primitives based on type, using CreatureModel.

	# Use the new detailed creature model builders
	match creature_type:
		0: _model_root = CreatureModel.build_stalker()
		1: _model_root = CreatureModel.build_crawler()
		2: _model_root = CreatureModel.build_floater()
		3: _model_root = CreatureModel.build_burrower()
		_: _model_root = CreatureModel.build_stalker()

	_model_root.name = "CreatureModel"
	add_child(_model_root)

	# Keep legacy material refs for animation/damage compatibility
	_body_mat = StandardMaterial3D.new()
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.emission_enabled = true

	match creature_type:
		0:
			_body_mat.albedo_color = Color(0.15, 0.12, 0.18)
			_eye_mat.emission = Color(1.0, 0.15, 0.1)
		1:
			_body_mat.albedo_color = Color(0.35, 0.28, 0.22)
			_eye_mat.emission = Color(1.0, 0.6, 0.1)
		2:
			_body_mat.albedo_color = Color(0.4, 0.42, 0.5, 0.8)
			_eye_mat.emission = Color(0.2, 0.8, 1.0)
		3:
			_body_mat.albedo_color = Color(0.2, 0.22, 0.2)
			_eye_mat.emission = Color(0.3, 1.0, 0.2)

	# Collision shape
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.2
	col_shape.shape = capsule
	col_shape.position.y = 0.8
	add_child(col_shape)


func _physics_process(delta: float) -> void:
	if _state == CreatureState.DEAD:
		return

	_anim_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_state_timer += delta

	# Apply gravity
	if not is_on_floor() and creature_type != 2:  # Floater ignores gravity
		velocity.y -= GRAVITY * delta
		velocity.y = maxf(velocity.y, -15.0)

	# State machine
	match _state:
		CreatureState.IDLE:
			_process_idle(delta)
		CreatureState.PATROL:
			_process_patrol(delta)
		CreatureState.CHASE:
			_process_chase(delta)
		CreatureState.ATTACK:
			_process_attack(delta)
		CreatureState.HURT:
			_process_hurt(delta)

	move_and_slide()
	_animate(delta)


func _process_idle(delta: float) -> void:
	## Idle: wait briefly, then patrol.
	velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta)

	if _state_timer > 2.0 + randf() * 3.0:
		_start_patrol()

	# Check for player
	if _player and _distance_to_player() < detect_range:
		_state = CreatureState.CHASE
		_state_timer = 0.0


func _process_patrol(delta: float) -> void:
	## Patrol: move toward patrol target, then idle.
	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 2.0 or _state_timer > 10.0:
		_state = CreatureState.IDLE
		_state_timer = 0.0
		return

	# Check for player
	if _player and _distance_to_player() < detect_range:
		_state = CreatureState.CHASE
		_state_timer = 0.0
		return

	var dir := to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_face_direction(dir)


func _process_chase(delta: float) -> void:
	## Chase: pursue the player.
	if not _player or not is_instance_valid(_player):
		_state = CreatureState.IDLE
		_state_timer = 0.0
		return

	var dist := _distance_to_player()

	# Lost player — return to patrol
	if dist > detect_range * 1.5:
		_start_patrol()
		return

	# In attack range
	if dist < attack_range:
		_state = CreatureState.ATTACK
		_state_timer = 0.0
		return

	# Chase toward player
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dir := to_player.normalized()
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	# Floaters hover at player head height
	if creature_type == 2:
		var target_y := _player.global_position.y + 2.0
		velocity.y = (target_y - global_position.y) * 3.0

	_face_direction(dir)


func _process_attack(delta: float) -> void:
	## Attack: deal damage to player, then brief cooldown.
	if not _player or not is_instance_valid(_player):
		_state = CreatureState.IDLE
		_state_timer = 0.0
		return

	var dist := _distance_to_player()

	# Player moved out of range
	if dist > attack_range * 1.5:
		_state = CreatureState.CHASE
		_state_timer = 0.0
		return

	# Attack on cooldown
	if _attack_cooldown <= 0.0:
		creature_attacked_player.emit(damage)
		_attack_cooldown = 1.5  # Attack every 1.5 seconds
		# Lunge effect
		var to_player := (_player.global_position - global_position).normalized()
		velocity = to_player * chase_speed * 0.5
	else:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)


func _process_hurt(delta: float) -> void:
	## Hurt: brief stun, then resume chase.
	_hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	if _hurt_timer <= 0.0:
		if health <= 0:
			_die()
		else:
			_state = CreatureState.CHASE
			_state_timer = 0.0


func take_damage(amount: float, from_direction: Vector3 = Vector3.ZERO) -> void:
	## Apply damage and knockback.
	if _state == CreatureState.DEAD:
		return

	health -= amount
	_state = CreatureState.HURT
	_hurt_timer = 0.3

	# Knockback
	if from_direction.length() > 0.1:
		velocity += from_direction.normalized() * 8.0
		velocity.y += 3.0

	# Flash red via new model or legacy shader
	if _model_root:
		CreatureModel.apply_hurt_flash(_model_root)
	elif _body_shader_mat:
		_body_shader_mat.set_shader_parameter("damage_flash", 1.0)
		get_tree().create_timer(0.2).timeout.connect(_reset_flash)
	elif _body_mat:
		_body_mat.emission_enabled = true
		_body_mat.emission = Color(1.0, 0.2, 0.1)
		_body_mat.emission_energy_multiplier = 1.5
		get_tree().create_timer(0.2).timeout.connect(_reset_flash)


func _reset_flash() -> void:
	if _body_shader_mat and _state != CreatureState.DEAD:
		_body_shader_mat.set_shader_parameter("damage_flash", 0.0)
	elif _body_mat and _state != CreatureState.DEAD:
		_body_mat.emission_enabled = false


func _die() -> void:
	_state = CreatureState.DEAD
	velocity = Vector3.ZERO

	creature_died.emit(self)

	# Death dissolve using new model system
	if _model_root:
		CreatureModel.apply_death_dissolve(_model_root)
		get_tree().create_timer(1.5).timeout.connect(queue_free)
	elif _body_shader_mat:
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void:
			if _body_shader_mat:
				_body_shader_mat.set_shader_parameter("death_dissolve", v)
		, 0.0, 1.0, 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(queue_free)
	else:
		# Legacy fallback
		if _body_mat:
			_body_mat.emission_enabled = true
			_body_mat.emission = Color(1.0, 0.5, 0.2)
			_body_mat.emission_energy_multiplier = 2.0
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 2.0)
		tween.tween_callback(queue_free)


func _start_patrol() -> void:
	_state = CreatureState.PATROL
	_state_timer = 0.0
	# Pick random patrol point near spawn
	var angle := randf() * TAU
	var dist := randf_range(5.0, patrol_radius)
	_patrol_target = _spawn_pos + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	# Snap patrol target to terrain height
	if _territory_gen and _territory_gen.has_method("get_height_at"):
		_patrol_target.y = _territory_gen.get_height_at(_patrol_target.x, _patrol_target.z)


func _distance_to_player() -> float:
	if not _player or not is_instance_valid(_player):
		return INF
	return global_position.distance_to(_player.global_position)


func _face_direction(dir: Vector3) -> void:
	if dir.length_squared() > 0.01:
		var target_angle := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 0.1)


func _animate(_delta: float) -> void:
	var t := _anim_time

	# Eye glow pulse
	if _eye_mat:
		var intensity := 1.5 + sin(t * 3.0) * 0.5
		if _state == CreatureState.CHASE or _state == CreatureState.ATTACK:
			intensity += 1.0  # Brighter when aggressive
		_eye_mat.emission_energy_multiplier = intensity

	# Body bob
	if _body_mesh and _state != CreatureState.DEAD:
		var bob_speed := 2.0
		var bob_amount := 0.05
		if _state == CreatureState.CHASE:
			bob_speed = 6.0
			bob_amount = 0.1
		elif _state == CreatureState.ATTACK:
			bob_speed = 8.0
			bob_amount = 0.15
		_body_mesh.position.y = (_body_mesh.mesh as CapsuleMesh).height * 0.5 + 0.2 + sin(t * bob_speed) * bob_amount

	# Leg animation
	for i in range(_leg_nodes.size()):
		var leg: Node3D = _leg_nodes[i]
		var phase := float(i) * PI / 2.0
		var swing_speed := 4.0 if _state == CreatureState.PATROL else (8.0 if _state == CreatureState.CHASE else 1.0)
		leg.rotation_degrees.x = sin(t * swing_speed + phase) * 15.0

	# Floater hover effect
	if creature_type == 2 and _body_mesh:
		_body_mesh.rotation_degrees.z = sin(t * 1.5) * 5.0
		_body_mesh.rotation_degrees.x = sin(t * 1.2 + 1.0) * 3.0
