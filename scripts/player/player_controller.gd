extends CharacterBody3D
## Player controller with ground mode (walk/run/jump/crouch) and fly mode (6DOF).
## Dysnomia is a moon with low gravity (~0.02g) — movement feels floaty and bounding.
## Reads terrain height for ground-snapping when exiting fly mode.
## Crouch mechanics and headbob adapted from FPC (character3D) plugin.

# Movement speeds — higher than Earth because low gravity = long strides
@export var walk_speed: float = 6.0
@export var run_speed: float = 14.0
@export var crouch_speed: float = 3.0
@export var fly_speed: float = 20.0
@export var fly_sprint_speed: float = 55.0

# Jump and gravity — Dysnomia surface gravity ~0.02g (we use artistic ~0.5g for gameplay)
@export var jump_velocity: float = 8.0       # Higher jumps in low gravity
@export var gravity: float = 3.2             # ~0.33x Earth gravity (artistic low-g)
@export var acceleration: float = 8.0        # Slightly slower accel (less traction on regolith)
@export var friction: float = 5.0            # Less friction on dusty surface
@export var air_control: float = 3.0         # Can steer mid-air (jetpack suit thrusters)
@export var max_jumps: int = 3               # Triple jump — suits have short-burst thrusters

# Crouch
@export var crouch_height: float = 1.0       # Capsule height when crouching
@export var stand_height: float = 1.8        # Normal capsule height
@export var crouch_transition_speed: float = 8.0  # How fast crouch/stand animation plays

# Headbob — gentle lunar bounding (low frequency, soft amplitude)
@export var headbob_enabled: bool = true
@export var headbob_walk_intensity: float = 0.015  # Very subtle vertical bob — lunar float
@export var headbob_run_intensity: float = 0.025   # Slightly more at sprint — bounding strides
@export var headbob_walk_frequency: float = 3.0    # Slow bob — long low-gravity strides
@export var headbob_run_frequency: float = 4.5     # Still slow — moon sprint is bounding

# Slope/climbing
@export var max_walkable_slope: float = 50.0  # Degrees — steep regolith
@export var slide_speed: float = 4.0          # Slide down steep slopes

const SAFETY_TELEPORT_THRESHOLD: float = 5.0
const BOUNDARY_MARGIN: float = 5.0
const TERRAIN_HALF_SIZE: float = JuliaHeightfield.SIZE_M * 0.5  # 512 m territories

signal player_jumped

var is_flying: bool = false
var is_crouching: bool = false
var _camera_rig: Node3D
var _terrain_generator: Node3D  # TerritoryManager (also handles height queries)
var _jumps_remaining: int = 3
var _wall_slide_cooldown: float = 0.0
var _safety_cooldown: float = 0.0
var _coyote_timer: float = 0.0  # Grace period after leaving ground
var _jump_buffer_timer: float = 0.0  # Pre-press jump buffering
var _was_on_floor: bool = false
var _sprint_momentum: float = 0.0  # Accumulated sprint momentum for bunny-hopping
var _wall_climb_timer: float = 0.0  # Time spent on wall (limits wall climbing)

# Crouch internals
var _collision_shape: CollisionShape3D
var _current_height: float = 1.8    # Smoothly interpolated capsule height
var _ceiling_ray: RayCast3D          # Prevents standing up under low ceilings
var _crouch_camera_offset: float = 0.0  # Camera dips when crouching

# Headbob internals
var _headbob_timer: float = 0.0
var _headbob_offset: float = 0.0

# Landing camera punch
var _land_punch: float = 0.0        # Camera dip on landing
var _land_punch_velocity: float = 0.0

# Flashlight — bright SpotLight3D that auto-enables at night, toggle with F
var _flashlight: SpotLight3D
var _flashlight_pivot: Node3D
var _flashlight_on: bool = false
var _flashlight_auto: bool = false  # Manual only — press F to toggle

const COYOTE_TIME: float = 0.2   # Seconds of grace after leaving ledge
const JUMP_BUFFER: float = 0.15  # Seconds to buffer a jump press
const MAX_WALL_CLIMB: float = 1.5  # Seconds of wall climbing before sliding


func _ready() -> void:
	_camera_rig = $CameraRig
	_collision_shape = $CollisionShape3D
	_current_height = stand_height
	GameManager.fly_mode_changed.connect(_on_fly_mode_changed)
	_create_flashlight()
	_create_ceiling_ray()


func set_terrain_generator(gen: Node3D) -> void:
	_terrain_generator = gen


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fly"):
		GameManager.toggle_fly_mode()

	if event.is_action_pressed("toggle_camera"):
		GameManager.toggle_camera_mode()

	# Flashlight (the territory scene handles "interact": the live moves)
	if event.is_action_pressed("flashlight"):
		_toggle_flashlight()

	# Jump buffer — record the press for buffered jumping
	if event.is_action_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER

	# Crouch toggle — Ctrl key
	if event.is_action_pressed("crouch_descend") and not is_flying:
		_toggle_crouch()

	# Escape to release/capture mouse
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	_update_flashlight()

	if is_flying:
		_fly_movement(delta)
	else:
		_ground_movement(delta)

	# Update crouch collision shape smoothly
	_update_crouch(delta)

	# Update headbob
	_update_headbob(delta)

	# Update landing camera punch
	_update_land_punch(delta)

	move_and_slide()

	# Boundary clamping — prevent escaping past territory edges
	# Expands in directions where a neighbor has been joined
	var margin := TERRAIN_HALF_SIZE + BOUNDARY_MARGIN
	var x_min := -margin
	var x_max := margin
	var z_min := -margin
	var z_max := margin
	if _terrain_generator and _terrain_generator.has_method("is_direction_joined"):
		if _terrain_generator.is_direction_joined(3):  # WEST
			x_min = -(TERRAIN_HALF_SIZE * 2.0 + TERRAIN_HALF_SIZE + BOUNDARY_MARGIN)
		if _terrain_generator.is_direction_joined(2):  # EAST
			x_max = TERRAIN_HALF_SIZE * 2.0 + TERRAIN_HALF_SIZE + BOUNDARY_MARGIN
		if _terrain_generator.is_direction_joined(0):  # NORTH
			z_min = -(TERRAIN_HALF_SIZE * 2.0 + TERRAIN_HALF_SIZE + BOUNDARY_MARGIN)
		if _terrain_generator.is_direction_joined(1):  # SOUTH
			z_max = TERRAIN_HALF_SIZE * 2.0 + TERRAIN_HALF_SIZE + BOUNDARY_MARGIN
	position.x = clampf(position.x, x_min, x_max)
	position.z = clampf(position.z, z_min, z_max)

	# Safety teleport with cooldown — break fall loops
	_safety_cooldown = maxf(0.0, _safety_cooldown - delta)
	if _terrain_generator and _terrain_generator.has_method("get_height_at"):
		var terrain_h: float = _terrain_generator.get_height_at(position.x, position.z)
		if position.y < terrain_h - SAFETY_TELEPORT_THRESHOLD and _safety_cooldown <= 0.0:
			position.y = terrain_h + 3.0
			velocity = Vector3.ZERO
			_safety_cooldown = 1.0

	# Pass movement data to PlayerModel for animation
	var model: Node3D = get_node_or_null("PlayerModel")
	if model and model.has_method("update_movement"):
		model.update_movement(velocity, is_on_floor(), is_flying)


func _ground_movement(delta: float) -> void:
	var on_floor := is_on_floor()

	# ── Coyote time: grace period after leaving edge ──
	if on_floor:
		_coyote_timer = COYOTE_TIME
		_jumps_remaining = max_jumps
		_wall_climb_timer = 0.0
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	# ── Gravity — low-g with terminal velocity ──
	if not on_floor:
		velocity.y -= gravity * delta
		# Terminal velocity — prevents infinite acceleration in deep craters
		velocity.y = maxf(velocity.y, -25.0)

	# Track floor transition for landing effects
	if on_floor and not _was_on_floor:
		# Landing — transfer some horizontal speed as bonus momentum
		_sprint_momentum = minf(Vector2(velocity.x, velocity.z).length() * 0.1, 3.0)
		# Camera landing punch — gentle on the moon (low gravity = soft landings)
		var fall_speed: float = absf(_was_on_floor_velocity_y) if _was_on_floor_velocity_y < -3.0 else 0.0
		_land_punch = -clampf(fall_speed * 0.004, 0.0, 0.06)
		_land_punch_velocity = 0.0
	_was_on_floor = on_floor
	if not on_floor:
		_was_on_floor_velocity_y = velocity.y

	# ── Jump buffer timer ──
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	# ── Crouching prevents jumping ──
	var can_attempt_jump := not is_crouching

	# ── Jump / multi-jump / coyote jump ──
	var can_jump := _jumps_remaining > 0 and (_coyote_timer > 0.0 or _jumps_remaining < max_jumps)
	if _jump_buffer_timer > 0.0 and can_jump and can_attempt_jump:
		# Variable jump height: higher when sprinting
		var jump_boost := 1.0
		if Input.is_action_pressed("sprint"):
			jump_boost = 1.2
		velocity.y = jump_velocity * jump_boost
		_jumps_remaining -= 1
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		player_jumped.emit()
		# Preserve sprint momentum through jump (bunny-hopping)
		_sprint_momentum = minf(_sprint_momentum + 1.0, 4.0)
		# Auto-uncrouch on jump
		if is_crouching:
			_set_crouch(false)

	# ── Wall interactions — climbing, sliding, and wall-jumping ──
	_wall_slide_cooldown = maxf(0.0, _wall_slide_cooldown - delta)
	if is_on_wall() and not on_floor and _wall_slide_cooldown <= 0.0:
		_wall_climb_timer += delta

		var forward_input := Input.get_axis("move_back", "move_forward")
		var is_pressing_into_wall := forward_input > 0.3

		if _wall_climb_timer < MAX_WALL_CLIMB and is_pressing_into_wall:
			# Active climbing — hold forward to scramble up the wall
			var climb_speed := lerpf(2.0, 3.5, clampf(forward_input, 0.0, 1.0))
			# Ramp down as stamina depletes
			climb_speed *= 1.0 - (_wall_climb_timer / MAX_WALL_CLIMB) * 0.5
			velocity.y = maxf(velocity.y, climb_speed)
			# Slight horizontal stick to prevent sliding off
			var wall_normal := get_wall_normal()
			velocity.x -= wall_normal.x * 2.0 * delta
			velocity.z -= wall_normal.z * 2.0 * delta
		elif _wall_climb_timer < MAX_WALL_CLIMB:
			# Wall sliding — slow descent (not pressing forward, just touching wall)
			velocity.y = maxf(velocity.y, -2.0)
		else:
			# Exhausted — slide faster but not free-fall
			velocity.y = maxf(velocity.y, -4.0)

		# Wall jump — push away and up (more powerful, feels good)
		if Input.is_action_just_pressed("jump"):
			var wall_normal := get_wall_normal()
			velocity += wall_normal * 6.0
			velocity.y = jump_velocity * 1.0  # Full jump power off wall
			player_jumped.emit()
			_jumps_remaining = maxi(_jumps_remaining, 2)  # Restore 2 jumps for chaining
			_wall_slide_cooldown = 0.25
			_wall_climb_timer = 0.0
	elif on_floor:
		_wall_climb_timer = 0.0

	# ── Horizontal movement ──
	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var is_sprinting := Input.is_action_pressed("sprint") and not is_crouching
	var target_speed: float
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = run_speed
	else:
		target_speed = walk_speed

	# Sprint momentum bonus (bunny-hopping reward)
	if is_sprinting and _sprint_momentum > 0.0:
		target_speed += _sprint_momentum
	_sprint_momentum = maxf(0.0, _sprint_momentum - delta * 2.0)  # Decay momentum

	if _camera_rig:
		var cam_basis := _camera_rig.global_transform.basis
		var forward := -cam_basis.z
		var right := cam_basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()

		var direction := (right * input_dir.x + forward * input_dir.y).normalized()

		# In free orbit mode, rotate player body to face movement direction
		if direction.length() > 0.1:
			var rig = _camera_rig as Node3D
			if rig and rig.has_method("get_camera_mode_name") and rig.get_camera_mode_name() == "FREE":
				var target_yaw := atan2(direction.x, direction.z)
				var current_yaw := rotation.y
				var diff := wrapf(target_yaw - current_yaw, -PI, PI)
				rotation.y += diff * minf(10.0 * delta, 1.0)

		if direction.length() > 0.1:
			if on_floor:
				# Ground acceleration — responsive but not instant (regolith traction)
				velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta * target_speed)
				velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta * target_speed)
			else:
				# Air control — can steer mid-air with suit thrusters (less than ground)
				velocity.x = move_toward(velocity.x, direction.x * target_speed, air_control * delta * target_speed)
				velocity.z = move_toward(velocity.z, direction.z * target_speed, air_control * delta * target_speed)
		else:
			if on_floor:
				# Ground friction — decelerate on dusty regolith
				velocity.x = move_toward(velocity.x, 0.0, friction * delta * target_speed)
				velocity.z = move_toward(velocity.z, 0.0, friction * delta * target_speed)
			else:
				# Minimal air drag — preserve momentum in low gravity
				velocity.x = move_toward(velocity.x, 0.0, 0.5 * delta * target_speed)
				velocity.z = move_toward(velocity.z, 0.0, 0.5 * delta * target_speed)

	# ── Slope sliding — steep regolith slides with gradual ramp-up ──
	if on_floor:
		var floor_normal := get_floor_normal()
		var slope_angle := rad_to_deg(acos(clampf(floor_normal.y, -1.0, 1.0)))
		if slope_angle > max_walkable_slope:
			# Gradual slide force — ramps with slope steepness
			var overshoot := (slope_angle - max_walkable_slope) / (90.0 - max_walkable_slope)
			var slide_force := slide_speed * (0.3 + overshoot * 0.7)  # Gentler on near-limit slopes
			var slide_dir := Vector3(floor_normal.x, 0.0, floor_normal.z).normalized()
			velocity += slide_dir * slide_force * delta
		elif slope_angle > max_walkable_slope * 0.7:
			# Approaching limit — slightly reduce speed (feels like struggling uphill)
			var struggle := (slope_angle - max_walkable_slope * 0.7) / (max_walkable_slope * 0.3)
			var speed_penalty := 1.0 - struggle * 0.3
			velocity.x *= lerpf(1.0, speed_penalty, delta * 4.0)
			velocity.z *= lerpf(1.0, speed_penalty, delta * 4.0)


func _fly_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var is_sprinting := Input.is_action_pressed("sprint")
	var speed := fly_sprint_speed if is_sprinting else fly_speed

	var direction := Vector3.ZERO
	if _camera_rig:
		var cam: Camera3D = _camera_rig.get_node("SpringArm3D/Camera3D")
		if cam:
			var cam_basis := cam.global_transform.basis
			direction += cam_basis.x * input_dir.x
			direction -= cam_basis.z * input_dir.y

	# Vertical movement
	if Input.is_action_pressed("jump"):
		direction.y += 1.0
	if Input.is_action_pressed("crouch_descend"):
		direction.y -= 1.0

	if direction.length() > 0.1:
		direction = direction.normalized()
		# Smooth acceleration with momentum — feels like jetpack thrust
		var lerp_speed := 6.0 if is_sprinting else 8.0
		velocity = velocity.lerp(direction * speed, lerp_speed * delta)
	else:
		# Gradual slowdown — momentum in space-like environment
		velocity = velocity.lerp(Vector3.ZERO, 3.0 * delta)


# ─── Crouch System ─────────────────────────────────────────────────────

var _was_on_floor_velocity_y: float = 0.0

func _toggle_crouch() -> void:
	## Toggle crouch state. Can't uncrouch if ceiling is too low.
	if is_crouching:
		# Check if there's room to stand
		if _ceiling_ray and _ceiling_ray.is_colliding():
			return  # Ceiling too low, stay crouched
		_set_crouch(false)
	else:
		_set_crouch(true)


func _set_crouch(crouching: bool) -> void:
	is_crouching = crouching


func _update_crouch(delta: float) -> void:
	## Smoothly transition collision shape and camera between standing/crouching.
	var target_h: float = crouch_height if is_crouching else stand_height
	_current_height = move_toward(_current_height, target_h, crouch_transition_speed * delta)

	# Update capsule shape
	if _collision_shape:
		var shape: CapsuleShape3D = _collision_shape.shape as CapsuleShape3D
		if shape:
			if absf(shape.height - _current_height) > 0.01:
				shape = shape.duplicate() as CapsuleShape3D
				shape.height = _current_height
				_collision_shape.shape = shape
			_collision_shape.position.y = _current_height / 2.0

	# Camera offset — smoothly dips down when crouching
	var target_cam_y: float = 0.0
	if is_crouching:
		target_cam_y = -(stand_height - crouch_height) * 0.6
	_crouch_camera_offset = move_toward(_crouch_camera_offset, target_cam_y, crouch_transition_speed * delta * 0.8)

	# Apply camera crouch offset + headbob + landing punch to spring arm
	if _camera_rig:
		var spring_arm: SpringArm3D = _camera_rig.get_node_or_null("SpringArm3D")
		if spring_arm:
			var base_y: float = stand_height * 0.83  # Default camera height (1.5 for 1.8 tall)
			spring_arm.position.y = base_y + _crouch_camera_offset + _headbob_offset + _land_punch

	# Update ceiling detection ray length
	if _ceiling_ray:
		_ceiling_ray.target_position = Vector3(0, stand_height - _current_height + 0.1, 0)
		_ceiling_ray.position.y = _current_height


func _create_ceiling_ray() -> void:
	## RayCast3D that checks if there's room to stand up from crouch.
	_ceiling_ray = RayCast3D.new()
	_ceiling_ray.name = "CeilingDetection"
	_ceiling_ray.target_position = Vector3(0, 0.9, 0)
	_ceiling_ray.position.y = stand_height
	_ceiling_ray.enabled = true
	_ceiling_ray.collision_mask = 1  # World collision layer
	add_child(_ceiling_ray)


# ─── Headbob System ────────────────────────────────────────────────────

func _update_headbob(delta: float) -> void:
	## Procedural view bobbing — smooth lunar bounding feel.
	## Low frequency + sine-eased curve = long floating strides on the moon.
	if not headbob_enabled or is_flying:
		_headbob_offset = lerpf(_headbob_offset, 0.0, delta * 3.0)
		return

	var on_floor := is_on_floor()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if on_floor and horizontal_speed > 1.0:
		var is_sprinting := Input.is_action_pressed("sprint") and not is_crouching
		var freq: float = headbob_run_frequency if is_sprinting else headbob_walk_frequency
		var intensity: float = headbob_run_intensity if is_sprinting else headbob_walk_intensity

		# Scale gently with speed — don't amplify too much
		var speed_factor := clampf(horizontal_speed / run_speed, 0.4, 1.0)
		intensity *= speed_factor

		# Crouching has reduced bob
		if is_crouching:
			intensity *= 0.4
			freq *= 0.7

		_headbob_timer += delta * freq
		# Smooth sine curve — longer hang at top and bottom of each stride
		var raw_bob := sin(_headbob_timer * TAU)
		# Ease the sine for a floaty, lunar feel (soften peaks)
		var eased_bob := raw_bob * absf(raw_bob)  # Smooths transitions, lingers at peaks
		_headbob_offset = lerpf(_headbob_offset, eased_bob * intensity, delta * 6.0)
	else:
		# Not moving — gently settle to neutral (no sudden stop)
		_headbob_offset = lerpf(_headbob_offset, 0.0, delta * 2.0)
		# Slowly reset timer so resumption doesn't jump
		if horizontal_speed < 0.5:
			_headbob_timer = lerpf(_headbob_timer, 0.0, delta * 2.0)


# ─── Landing Camera Punch ──────────────────────────────────────────────

func _update_land_punch(delta: float) -> void:
	## Spring-based camera dip on landing — soft and floaty for lunar gravity.
	if absf(_land_punch) > 0.0005:
		# Soft spring: low stiffness + heavy damping = gentle cushioned landing
		_land_punch_velocity += -_land_punch * 20.0 * delta  # Lower stiffness (was 40)
		_land_punch_velocity *= 0.90  # More damping (was 0.85) — absorbs bounce
		_land_punch += _land_punch_velocity * delta
	else:
		_land_punch = 0.0
		_land_punch_velocity = 0.0


# ─── Appearance ────────────────────────────────────────────────────────

func apply_appearance(appearance: Dictionary) -> void:
	## Apply identity-driven appearance to the player model.
	var model: Node3D = $PlayerModel
	if model and model.has_method("apply_appearance"):
		model.apply_appearance(appearance)

	# Update collision shape to match height
	var target_height: float = appearance.get("height", 1.8)
	var target_radius: float = appearance.get("radius", 0.3)
	stand_height = target_height
	_current_height = target_height
	var col_shape: CollisionShape3D = $CollisionShape3D
	if col_shape:
		var shape := col_shape.shape as CapsuleShape3D
		if shape:
			shape = shape.duplicate() as CapsuleShape3D
			shape.height = target_height
			shape.radius = target_radius
			col_shape.shape = shape
		col_shape.position.y = target_height / 2.0


func _on_fly_mode_changed(flying: bool) -> void:
	is_flying = flying
	# Exit crouch when entering fly mode
	if is_flying and is_crouching:
		_set_crouch(false)
	# When returning to ground, snap to terrain
	if not is_flying and _terrain_generator and _terrain_generator.has_method("get_height_at"):
		var terrain_h: float = _terrain_generator.get_height_at(position.x, position.z)
		position.y = terrain_h + 1.0
		velocity = Vector3.ZERO


# ─── Flashlight ──────────────────────────────────────────────────────────

func _create_flashlight() -> void:
	## Create a bright SpotLight3D mounted on the player's helmet.
	## Attached to a dedicated pivot that follows camera yaw+pitch so the beam
	## always illuminates what the player is looking at (forward, not the back).
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.light_energy = 3.5
	_flashlight.light_color = Color(0.95, 0.93, 0.87)  # Warm white
	_flashlight.spot_range = 60.0
	_flashlight.spot_angle = 32.0
	_flashlight.spot_attenuation = 0.7
	_flashlight.shadow_enabled = true
	_flashlight.shadow_bias = 0.04
	_flashlight.visible = false
	_flashlight.light_cull_mask = 0xFFFFFFFD  # Exclude layer 2 (player model)

	# Create a pivot node at helmet height that copies camera pitch.
	# The pivot is a child of the camera_rig (which already yaw-follows the player).
	# SpotLight3D shines along -Z in local space, and the pivot's -Z faces forward.
	var flash_pivot := Node3D.new()
	flash_pivot.name = "FlashlightPivot"
	_camera_rig.add_child(flash_pivot)
	# Position at head height
	flash_pivot.position = Vector3(0.0, 1.6, 0.0)

	flash_pivot.add_child(_flashlight)
	# Gentle downward tilt to light the ground ahead
	_flashlight.rotation_degrees.x = -5.0
	# Offset well forward + slightly right (helmet lamp style) to clear the bear's head geometry
	_flashlight.position = Vector3(0.15, 0.0, 1.2)

	# Store reference so we can update pitch each frame
	_flashlight_pivot = flash_pivot


func _toggle_flashlight() -> void:
	## Manual toggle — also disables auto-mode so it stays how the player wants.
	if not _flashlight:
		return
	_flashlight_auto = false
	_flashlight_on = not _flashlight_on
	_flashlight.visible = _flashlight_on


func _update_flashlight() -> void:
	## Auto-enable flashlight at night if auto-mode is active.
	## Also sync flashlight pivot pitch with camera pitch each frame.
	if _flashlight_pivot:
		var spring_arm: SpringArm3D = _camera_rig.get_node_or_null("SpringArm3D") if _camera_rig else null
		if spring_arm:
			_flashlight_pivot.rotation.x = spring_arm.rotation.x

	if not _flashlight or not _flashlight_auto:
		return

	var t := GameManager.time_of_day
	var should_be_on := t < 0.22 or t > 0.78

	if should_be_on != _flashlight_on:
		_flashlight_on = should_be_on
		_flashlight.visible = _flashlight_on
