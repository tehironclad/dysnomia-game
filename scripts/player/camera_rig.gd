extends Node3D
## Third-person camera rig with SpringArm3D for collision avoidance.
## Three camera modes:
##   0 = Third-Person (yaw rotates player body, camera follows behind)
##   1 = Free Orbit (yaw rotates camera around player, 360° view)
##   2 = First-Person (camera at head, no spring arm)
##
## Z key cycles: 3rd Person → Free Orbit → 1st Person → 3rd Person

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
var _yaw: float = 0.0     # Only used in free orbit mode (local yaw on rig)
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

	# Apply config sensitivity if available
	if Config:
		mouse_sensitivity = Config.mouse_sensitivity
		base_fov = Config.fov
		camera.fov = base_fov

	GameManager.camera_mode_changed.connect(_on_camera_mode_changed)


func _unhandled_input(event: InputEvent) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Mouse look
	if event is InputEventMouseMotion:
		var invert_mult: float = -1.0 if Config and Config.invert_y else 1.0

		match _camera_mode:
			CameraMode.THIRD_PERSON:
				# Yaw rotates the player body
				get_parent().rotate_y(-event.relative.x * mouse_sensitivity)
				_pitch -= event.relative.y * mouse_sensitivity * invert_mult
				_pitch = clampf(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

			CameraMode.FREE_ORBIT:
				# Yaw rotates the camera rig (orbit around player)
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
	# Apply pitch to spring arm
	spring_arm.rotation.x = _pitch

	# Apply yaw to rig in free orbit mode
	if _camera_mode == CameraMode.FREE_ORBIT:
		rotation.y = _yaw
	else:
		# Smoothly return rig yaw to 0 when leaving free orbit
		if absf(rotation.y) > 0.001:
			rotation.y = lerpf(rotation.y, 0.0, 8.0 * delta)
		else:
			rotation.y = 0.0

	# Sprint FOV effect
	var target_fov: float = sprint_fov if Input.is_action_pressed("sprint") else base_fov
	camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)


func _on_camera_mode_changed(_first_person: bool) -> void:
	# Cycle through 3 modes: 3rd → Free → 1st → 3rd
	_camera_mode = (_camera_mode + 1) % 3

	match _camera_mode:
		CameraMode.THIRD_PERSON:
			spring_arm.spring_length = follow_distance
			# Transfer free orbit yaw back to player body so transition is seamless
			if absf(_yaw) > 0.01:
				get_parent().rotate_y(_yaw)
				_yaw = 0.0
				rotation.y = 0.0
			GameManager.is_first_person = false

		CameraMode.FREE_ORBIT:
			spring_arm.spring_length = follow_distance
			# Start free orbit from current player-relative position (yaw = 0)
			_yaw = 0.0
			rotation.y = 0.0
			GameManager.is_first_person = false

		CameraMode.FIRST_PERSON:
			spring_arm.spring_length = 0.0
			# Transfer yaw back to player body
			if absf(_yaw) > 0.01:
				get_parent().rotate_y(_yaw)
				_yaw = 0.0
				rotation.y = 0.0
			GameManager.is_first_person = true


func get_camera_mode_name() -> String:
	match _camera_mode:
		CameraMode.THIRD_PERSON: return "3RD"
		CameraMode.FREE_ORBIT: return "FREE"
		CameraMode.FIRST_PERSON: return "1ST"
	return "3RD"
