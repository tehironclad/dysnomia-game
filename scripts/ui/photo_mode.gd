extends CanvasLayer
## Photo mode — free-camera mode with color filters, frames, DOF, and screenshot capture.
## F6 toggles photo mode. WASD/mouse for 6DOF free camera.
## Number keys 1-7 cycle filters. Enter captures screenshot.
## Arrow keys adjust DOF. F/G cycle frame overlays.

signal photo_mode_entered
signal photo_mode_exited

const FILTER_SHADER = preload("res://assets/shaders/photo_filter.gdshader")
const FRAME_SHADER = preload("res://assets/shaders/photo_frame.gdshader")

const MOVE_SPEED: float = 8.0
const MOVE_SPEED_FAST: float = 24.0
const LOOK_SENSITIVITY: float = 0.003
const DOF_STEP: float = 2.0
const DOF_MIN: float = 1.0
const DOF_MAX: float = 200.0

const FILTER_NAMES: Array[String] = [
	"None", "Sepia", "High Contrast", "Cool", "Warm", "Noir", "Infrared"
]
const FRAME_NAMES: Array[String] = [
	"None", "Film Strip", "Polaroid", "EVA Helmet"
]
const SCREENSHOT_DIR: String = "user://screenshots"

# ─── State ───────────────────────────────────────────────────────────────
var _active: bool = false
var _player: Node3D
var _original_camera: Camera3D
var _photo_camera: Camera3D
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0

var _current_filter: int = 0
var _current_frame: int = 0
var _dof_distance: float = 30.0
var _dof_enabled: bool = false
var _vignette: float = 0.0

# UI elements
var _filter_overlay: ColorRect
var _filter_material: ShaderMaterial
var _frame_overlay: ColorRect
var _frame_material: ShaderMaterial
var _controls_label: Label
var _status_label: Label
var _screenshot_count: int = 0


func _ready() -> void:
	layer = 80  # Below tutorial but above most game UI
	visible = false
	_build_ui()


func is_active() -> bool:
	return _active


func enter_photo_mode(player: Node3D) -> void:
	_player = player
	if _active:
		return

	_active = true
	visible = true

	# Freeze player
	if _player and _player.has_method("freeze"):
		_player.freeze()
	elif _player:
		_player.set_physics_process(false)

	# Get current camera and create free camera
	_original_camera = _player.get_viewport().get_camera_3d() if _player else null
	_create_photo_camera()

	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Reset state
	_current_filter = 0
	_current_frame = 0
	_dof_enabled = false
	_vignette = 0.0
	_update_filter()
	_update_frame()
	_update_controls_text()

	photo_mode_entered.emit()
	print("[PhotoMode] Entered")


func exit_photo_mode() -> void:
	if not _active:
		return

	_active = false
	visible = false

	# Remove photo camera
	if _photo_camera and is_instance_valid(_photo_camera):
		_photo_camera.clear_current()
		if _original_camera and is_instance_valid(_original_camera):
			_original_camera.make_current()
		_photo_camera.queue_free()
		_photo_camera = null

	# Unfreeze player
	if _player and is_instance_valid(_player):
		if _player.has_method("unfreeze"):
			_player.unfreeze()
		else:
			_player.set_physics_process(true)

	# Clear filter/frame
	_filter_material.set_shader_parameter("filter_mode", 0)
	_frame_material.set_shader_parameter("frame_mode", 0)

	photo_mode_exited.emit()
	print("[PhotoMode] Exited")


func _create_photo_camera() -> void:
	_photo_camera = Camera3D.new()
	_photo_camera.name = "PhotoCamera"

	# Position at current camera location
	if _original_camera and is_instance_valid(_original_camera):
		_photo_camera.global_transform = _original_camera.global_transform
		_photo_camera.fov = _original_camera.fov
		# Extract yaw/pitch from current rotation
		var basis := _original_camera.global_transform.basis
		var euler := basis.get_euler()
		_camera_pitch = euler.x
		_camera_yaw = euler.y
	else:
		_photo_camera.global_position = _player.global_position + Vector3(0, 2, 0) if _player else Vector3.ZERO
		_camera_yaw = 0.0
		_camera_pitch = 0.0

	# Add to scene tree at root level
	_player.get_parent().add_child(_photo_camera)
	_photo_camera.make_current()


func _build_ui() -> void:
	# Filter overlay (full-screen shader)
	_filter_overlay = ColorRect.new()
	_filter_overlay.name = "PhotoFilter"
	_filter_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_material = ShaderMaterial.new()
	_filter_material.shader = FILTER_SHADER
	_filter_material.set_shader_parameter("filter_mode", 0)
	_filter_material.set_shader_parameter("vignette_strength", 0.0)
	_filter_overlay.material = _filter_material
	add_child(_filter_overlay)

	# Frame overlay
	_frame_overlay = ColorRect.new()
	_frame_overlay.name = "PhotoFrame"
	_frame_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_material = ShaderMaterial.new()
	_frame_material.shader = FRAME_SHADER
	_frame_material.set_shader_parameter("frame_mode", 0)
	_frame_overlay.material = _frame_material
	add_child(_frame_overlay)

	# Controls label (bottom-left)
	_controls_label = Label.new()
	_controls_label.name = "PhotoControls"
	_controls_label.add_theme_font_size_override("font_size", 13)
	_controls_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8, 0.85))
	_controls_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_controls_label.add_theme_constant_override("shadow_offset_x", 1)
	_controls_label.add_theme_constant_override("shadow_offset_y", 1)
	_controls_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_controls_label.position = Vector2(16.0, -180.0)
	_controls_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_controls_label)

	# Status label (top-center) — shows "PHOTO MODE" and current settings
	_status_label = Label.new()
	_status_label.name = "PhotoStatus"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8, 0.9))
	_status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	_status_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_label.position = Vector2(-150.0, 8.0)
	_status_label.size = Vector2(300.0, 30.0)
	_status_label.text = "PHOTO MODE"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)


func _process(delta: float) -> void:
	if not _active or not _photo_camera or not is_instance_valid(_photo_camera):
		return

	# Camera movement (6DOF free camera)
	var speed := MOVE_SPEED_FAST if Input.is_key_pressed(KEY_SHIFT) else MOVE_SPEED
	var move_dir := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		move_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move_dir.x += 1.0
	if Input.is_key_pressed(KEY_SPACE):
		move_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL):
		move_dir.y -= 1.0

	if move_dir.length_squared() > 0.01:
		move_dir = move_dir.normalized()
		# Transform move direction by camera rotation
		var basis := Basis()
		basis = basis.rotated(Vector3.UP, _camera_yaw)
		basis = basis.rotated(basis.x, _camera_pitch)
		var world_move := basis * move_dir * speed * delta
		_photo_camera.global_position += world_move


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	# Mouse look
	if event is InputEventMouseMotion:
		_camera_yaw -= event.relative.x * LOOK_SENSITIVITY
		_camera_pitch -= event.relative.y * LOOK_SENSITIVITY
		_camera_pitch = clampf(_camera_pitch, -PI * 0.49, PI * 0.49)

		var basis := Basis()
		basis = basis.rotated(Vector3.UP, _camera_yaw)
		basis = basis.rotated(basis.x, _camera_pitch)
		_photo_camera.global_transform.basis = basis
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			# Number keys 1-7: select filter
			KEY_1:
				_set_filter(0)
			KEY_2:
				_set_filter(1)
			KEY_3:
				_set_filter(2)
			KEY_4:
				_set_filter(3)
			KEY_5:
				_set_filter(4)
			KEY_6:
				_set_filter(5)
			KEY_7:
				_set_filter(6)
			# F/G: cycle frame overlay
			KEY_F:
				_cycle_frame(-1)
			KEY_G:
				_cycle_frame(1)
			# V: toggle vignette
			KEY_V:
				_toggle_vignette()
			# Up/Down: DOF distance
			KEY_UP:
				_adjust_dof(DOF_STEP)
			KEY_DOWN:
				_adjust_dof(-DOF_STEP)
			# Enter: capture screenshot
			KEY_ENTER:
				_capture_screenshot()
			# Escape/F6: exit photo mode
			KEY_ESCAPE, KEY_F6:
				exit_photo_mode()

		get_viewport().set_input_as_handled()


func _set_filter(mode: int) -> void:
	_current_filter = clampi(mode, 0, FILTER_NAMES.size() - 1)
	_update_filter()
	_update_controls_text()


func _cycle_frame(direction: int) -> void:
	_current_frame = (_current_frame + direction) % FRAME_NAMES.size()
	if _current_frame < 0:
		_current_frame = FRAME_NAMES.size() - 1
	_update_frame()
	_update_controls_text()


func _toggle_vignette() -> void:
	if _vignette > 0.01:
		_vignette = 0.0
	else:
		_vignette = 0.5
	_filter_material.set_shader_parameter("vignette_strength", _vignette)
	_update_controls_text()


func _adjust_dof(amount: float) -> void:
	_dof_distance = clampf(_dof_distance + amount, DOF_MIN, DOF_MAX)
	_dof_enabled = true
	_update_dof()
	_update_controls_text()


func _update_filter() -> void:
	_filter_material.set_shader_parameter("filter_mode", _current_filter)


func _update_frame() -> void:
	_frame_material.set_shader_parameter("frame_mode", _current_frame)


func _update_dof() -> void:
	if not _photo_camera or not is_instance_valid(_photo_camera):
		return
	# DOF effect using camera near/far properties
	# Godot 4 has DOF blur via Environment — but since we may not own the
	# WorldEnvironment, we'll just note the DOF state. For a full implementation,
	# we'd need to modify the environment's DOF settings.
	# For now this is tracked as a camera metadata hint.
	_photo_camera.set_meta("dof_distance", _dof_distance)


func _update_controls_text() -> void:
	var filter_name := FILTER_NAMES[_current_filter] if _current_filter < FILTER_NAMES.size() else "Unknown"
	var frame_name := FRAME_NAMES[_current_frame] if _current_frame < FRAME_NAMES.size() else "Unknown"
	var vig_text := "ON" if _vignette > 0.01 else "OFF"

	_controls_label.text = """WASD  Move camera    Shift  Fast
Mouse  Look around
1-7  Filter: %s
F/G  Frame: %s
V  Vignette: %s
Up/Down  DOF: %.0fm
Enter  Capture screenshot
ESC/F6  Exit photo mode""" % [filter_name, frame_name, vig_text, _dof_distance]


func _capture_screenshot() -> void:
	## Save a screenshot to user://screenshots/ with timestamp.
	# Ensure screenshot directory exists
	if not DirAccess.dir_exists_absolute(SCREENSHOT_DIR):
		DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)

	# Temporarily hide UI for clean screenshot
	_controls_label.visible = false
	_status_label.visible = false

	# Wait one frame so the UI is hidden in the render
	await get_tree().process_frame
	await get_tree().process_frame

	# Capture viewport texture
	var image := get_viewport().get_texture().get_image()
	if image:
		_screenshot_count += 1
		var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		var filename := "dysnomia_%s_%03d.png" % [timestamp, _screenshot_count]
		var path := SCREENSHOT_DIR.path_join(filename)
		var err := image.save_png(path)
		if err == OK:
			print("[PhotoMode] Screenshot saved: %s" % path)
			_status_label.text = "Screenshot saved!"
		else:
			print("[PhotoMode] Screenshot failed: error %d" % err)
			_status_label.text = "Screenshot failed!"
	else:
		_status_label.text = "Capture failed!"

	# Re-show UI
	_controls_label.visible = true
	_status_label.visible = true

	# Reset status text after a moment
	await get_tree().create_timer(2.0).timeout
	if _active:
		_status_label.text = "PHOTO MODE"
