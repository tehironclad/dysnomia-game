extends Node3D
## Camera rig with SpringArm3D for collision avoidance. Two modes:
##   Third person (default, GTA-style): the mouse orbits the camera freely around
##     the player (its yaw is held in world space); the body turns to face the
##     direction it moves (player_controller), never the camera.
##   First person: the camera sits at the head and the mouse turns the body.
## The toggle_camera action switches between them.

@export var mouse_sensitivity: float = 0.003
@export var follow_distance: float = 3.5
@export var min_distance: float = 1.0
@export var max_distance: float = 15.0
@export var pitch_min_deg: float = -80.0
@export var pitch_max_deg: float = 80.0
@export var base_fov: float = 70.0
@export var sprint_fov: float = 78.0
@export var fov_lerp_speed: float = 5.0

enum CameraMode { THIRD_PERSON, FREE_ORBIT, FIRST_PERSON }

var _pitch: float = -0.2  # Slight downward angle
var _yaw: float = 0.0     # third person: the camera's WORLD yaw (independent of the body)
var _yaw_ready := false
var _camera_mode: int = CameraMode.THIRD_PERSON

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	spring_arm.spring_length = follow_distance

	# Exclude the player's own body from spring arm collision detection
	var player := get_parent()
	if player is CharacterBody3D:
		spring_arm.add_excluded_object(player.get_rid())

	_apply_config()
	Config.applied.connect(_apply_config)

	GameManager.camera_mode_changed.connect(_on_camera_mode_changed)


func _apply_config() -> void:
	mouse_sensitivity = Config.mouse_sensitivity
	base_fov = Config.fov
	camera.fov = base_fov
	camera.far = Config.render_distance


## Keyboard / gamepad look speed (radians per second): arrow keys and the
## right stick turn the camera, which works while running (laptop touchpads
## are often switched off while keys are held).
const KEY_LOOK_SPEED := 2.4


func _unhandled_input(event: InputEvent) -> void:
	# Click into the game to grab the mouse for looking around (Esc releases it).
	# Clicks on open panels and buttons never get here: the GUI takes them first.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
		return

	# Mouse look
	if event is InputEventMouseMotion:
		var invert_mult: float = -1.0 if Config and Config.invert_y else 1.0

		match _camera_mode:
			CameraMode.THIRD_PERSON, CameraMode.FREE_ORBIT:
				# Orbit the camera; the body is not turned by the mouse.
				_yaw -= event.relative.x * mouse_sensitivity
				_pitch -= event.relative.y * mouse_sensitivity * invert_mult
				_pitch = clampf(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

			CameraMode.FIRST_PERSON:
				# Same as 3rd person — yaw rotates player
				get_parent().rotate_y(-event.relative.x * mouse_sensitivity)
				_pitch -= event.relative.y * mouse_sensitivity * invert_mult
				_pitch = clampf(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

	# Scroll to adjust distance (3rd person and free orbit only)
	if event is InputEventMouseButton and _camera_mode != CameraMode.FIRST_PERSON:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			follow_distance = maxf(min_distance, follow_distance - 0.5)
			spring_arm.spring_length = follow_distance
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			follow_distance = minf(max_distance, follow_distance + 0.5)
			spring_arm.spring_length = follow_distance


func _process(delta: float) -> void:
	# Arrow keys / right stick look (any time, including while running).
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.05:
		var invert_mult: float = -1.0 if Config and Config.invert_y else 1.0
		if _camera_mode == CameraMode.FIRST_PERSON:
			get_parent().rotate_y(-look.x * KEY_LOOK_SPEED * delta)
		else:
			_yaw -= look.x * KEY_LOOK_SPEED * delta
		_pitch = clampf(_pitch - look.y * KEY_LOOK_SPEED * 0.6 * delta * invert_mult, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	# Apply pitch to spring arm
	spring_arm.rotation.x = _pitch

	if not _yaw_ready:
		_yaw = get_parent().global_rotation.y
		_yaw_ready = true
	if _camera_mode == CameraMode.FIRST_PERSON:
		rotation.y = 0.0
	else:
		# Hold the camera's yaw in world space while the body turns under it.
		global_rotation.y = _yaw

	# Sprint FOV effect
	var target_fov: float = sprint_fov if Input.is_action_pressed("sprint") else base_fov
	camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)


func _on_camera_mode_changed(_first_person: bool) -> void:
	# Third person (free camera) ↔ first person.
	_camera_mode = CameraMode.FIRST_PERSON if _camera_mode != CameraMode.FIRST_PERSON else CameraMode.THIRD_PERSON

	match _camera_mode:
		CameraMode.THIRD_PERSON:
			spring_arm.spring_length = follow_distance
			_yaw = get_parent().global_rotation.y  # start behind where the body faces
			GameManager.is_first_person = false

		CameraMode.FREE_ORBIT:
			spring_arm.spring_length = follow_distance
			# Start free orbit from current player-relative position (yaw = 0)
			_yaw = 0.0
			rotation.y = 0.0
			GameManager.is_first_person = false

		CameraMode.FIRST_PERSON:
			spring_arm.spring_length = 0.0
			# The body turns to where the camera was looking.
			get_parent().global_rotation.y = _yaw
			rotation.y = 0.0
			GameManager.is_first_person = true


func get_camera_mode_name() -> String:
	match _camera_mode:
		CameraMode.THIRD_PERSON: return "3RD"
		CameraMode.FREE_ORBIT: return "FREE"
		CameraMode.FIRST_PERSON: return "1ST"
	return "3RD"
