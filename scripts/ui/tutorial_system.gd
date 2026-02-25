extends CanvasLayer
## Step-based tutorial system for Dysnomia onboarding.
## Guides new players through movement, interaction, and core mechanics.
## State saved to user://tutorial_complete.cfg — auto-starts on first launch.
## Each step shows an instruction label and optional arrow pointing at target.
## Steps auto-advance when the player completes the required action.

const TutorialArrowScript = preload("res://scripts/ui/tutorial_arrow.gd")

signal tutorial_completed
signal tutorial_step_changed(step: int)

enum TutorialStep {
	WELCOME = 0,
	MOVE = 1,
	LOOK = 2,
	JUMP = 3,
	SPRINT = 4,
	FLY = 5,
	MONUMENT = 6,
	TERRAFORM = 7,
	PUB = 8,
	MINIMAP = 9,
	COMPLETE = 10,
}

const SAVE_PATH: String = "user://tutorial_complete.cfg"
const STEP_TIMEOUT: float = 30.0  # Auto-advance stuck steps after 30s

# ─── Step Definitions ────────────────────────────────────────────────────
# Each step has: instruction text, required action (tracked via signals/polling),
# optional target world position, and a minimum dwell time.

const STEP_DATA: Array[Dictionary] = [
	{  # WELCOME
		"text": "Welcome to Dysnomia!\nA frozen moon orbiting Eris, deep in the outer solar system.\n\nYou are an astronaut exploring procedurally-generated territories\ndriven by on-chain state from PulseChain.\n\n[Press any key to continue]",
		"action": "any_key",
		"min_time": 1.0,
	},
	{  # MOVE
		"text": "Move with [b]W A S D[/b] keys.\nTry walking around!",
		"action": "move_distance",
		"target_value": 10.0,  # Move 10 meters
		"min_time": 0.5,
	},
	{  # LOOK
		"text": "Move the [b]mouse[/b] to look around.\nHold [b]Right Click[/b] to adjust camera zoom.",
		"action": "look_rotation",
		"target_value": 2.0,  # Rotate 2 radians total
		"min_time": 1.0,
	},
	{  # JUMP
		"text": "Press [b]Space[/b] to jump!\nDysnomia has low gravity — you can jump very high.\nTry a [b]triple jump[/b] by pressing Space in the air!",
		"action": "jump_count",
		"target_value": 3.0,  # Jump 3 times
		"min_time": 0.5,
	},
	{  # SPRINT
		"text": "Hold [b]Shift[/b] to sprint!\nPress [b]R[/b] to toggle jetpack flight mode.",
		"action": "sprint_or_fly",
		"min_time": 2.0,
	},
	{  # FLY
		"text": "In flight mode, use [b]Space[/b] to fly up and [b]Ctrl[/b] to descend.\nPress [b]R[/b] again to return to ground mode.\n\nExplore the terrain!",
		"action": "fly_duration",
		"target_value": 3.0,  # Fly for 3 seconds
		"min_time": 1.0,
	},
	{  # MONUMENT
		"text": "The [b]Monument[/b] is the territory's centerpiece.\nWalk toward it — the large structure to the north.\nPress [b]E[/b] near it to interact.",
		"action": "monument_interact",
		"world_target": Vector3(0.0, 0.0, -40.0),
		"min_time": 1.0,
	},
	{  # TERRAFORM
		"text": "Press [b]T[/b] to open the Terraform panel.\nTerraforming changes the territory's on-chain state,\nwhich alters the terrain, weather, and atmosphere.\n\n(Requires a connected wallet with PulseChain gas)",
		"action": "open_terraform",
		"min_time": 2.0,
	},
	{  # PUB
		"text": "Visit the [b]Lunar Cantina[/b] (pub) to the east!\nYou can play minigames at the game tables inside.\nPress [b]E[/b] near a table to play.\n\nOther useful keys: [b]C[/b] Chat, [b]M[/b] Map, [b]I[/b] Inventory",
		"action": "timeout_or_key",
		"min_time": 3.0,
	},
	{  # MINIMAP
		"text": "Press [b]N[/b] to toggle the minimap.\nPress [b]H[/b] for a full list of controls.\n\nPress [b]P[/b] to view your achievements.\nPress [b]L[/b] for the leaderboard.",
		"action": "timeout_or_key",
		"min_time": 3.0,
	},
	{  # COMPLETE
		"text": "Tutorial complete!\n\nYou're ready to explore Dysnomia.\nConnect your wallet to terraform, chat, and leave your mark.\n\nGood luck, astronaut! 🚀",
		"action": "any_key",
		"min_time": 2.0,
	},
]

# ─── State ───────────────────────────────────────────────────────────────
var _current_step: int = TutorialStep.WELCOME
var _step_timer: float = 0.0
var _step_min_time: float = 0.0
var _active: bool = false
var _completed: bool = false

# Tracking vars for step completion
var _start_position: Vector3 = Vector3.ZERO
var _total_distance: float = 0.0
var _total_rotation: float = 0.0
var _jump_count: int = 0
var _has_sprinted: bool = false
var _has_flown: bool = false
var _fly_time: float = 0.0
var _monument_interacted: bool = false
var _terraform_opened: bool = false
var _player: Node3D
var _last_rotation_y: float = 0.0

# UI elements
var _instruction_panel: PanelContainer
var _instruction_label: RichTextLabel
var _skip_button: Button
var _step_indicator: Label
var _arrow: Control


func _ready() -> void:
	layer = 95  # Above most UI
	_build_ui()


func start_tutorial(player_ref: Node3D) -> void:
	## Begin the tutorial from step 0.
	_player = player_ref
	_current_step = TutorialStep.WELCOME
	_active = true
	_completed = false
	_reset_tracking()
	_show_step()
	visible = true
	print("[Tutorial] Started")


func is_active() -> bool:
	return _active


func is_completed_or_skipped() -> bool:
	return _completed


func skip_tutorial() -> void:
	## Skip remaining steps and mark as complete.
	_active = false
	_completed = true
	_save_completion()
	_hide_all()
	tutorial_completed.emit()
	print("[Tutorial] Skipped")


static func is_tutorial_complete() -> bool:
	## Check if tutorial was already completed (saved to disk).
	return FileAccess.file_exists(SAVE_PATH)


func _save_completion() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string("completed=true\nversion=1\n")
		file.close()


func _build_ui() -> void:
	# Semi-transparent instruction panel at bottom-center
	_instruction_panel = PanelContainer.new()
	_instruction_panel.name = "TutorialPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.15, 0.88)
	style.border_color = Color(0.4, 0.6, 1.0, 0.6)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	_instruction_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Step indicator
	_step_indicator = Label.new()
	_step_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_indicator.add_theme_font_size_override("font_size", 12)
	_step_indicator.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8, 0.7))
	vbox.add_child(_step_indicator)

	# Instruction text (BBCode)
	_instruction_label = RichTextLabel.new()
	_instruction_label.bbcode_enabled = true
	_instruction_label.fit_content = true
	_instruction_label.scroll_active = false
	_instruction_label.custom_minimum_size = Vector2(450.0, 60.0)
	_instruction_label.add_theme_font_size_override("normal_font_size", 15)
	_instruction_label.add_theme_font_size_override("bold_font_size", 16)
	_instruction_label.add_theme_color_override("default_color", Color(0.88, 0.9, 0.95))
	vbox.add_child(_instruction_label)

	# Skip button
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_skip_button = Button.new()
	_skip_button.text = "Skip Tutorial"
	_skip_button.add_theme_font_size_override("font_size", 13)
	_skip_button.pressed.connect(skip_tutorial)
	btn_row.add_child(_skip_button)
	vbox.add_child(btn_row)

	_instruction_panel.add_child(vbox)
	add_child(_instruction_panel)

	# Position at bottom-center
	_instruction_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_instruction_panel.position = Vector2(-250.0, -200.0)
	_instruction_panel.size = Vector2(500.0, 0.0)

	# Tutorial arrow overlay
	_arrow = Control.new()
	_arrow.set_script(TutorialArrowScript)
	_arrow.name = "TutorialArrow"
	_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrow)
	_arrow.hide_arrow()


func _show_step() -> void:
	if _current_step >= STEP_DATA.size():
		_finish_tutorial()
		return

	var data: Dictionary = STEP_DATA[_current_step]
	_instruction_label.text = "[center]%s[/center]" % data.text
	_step_indicator.text = "Step %d / %d" % [_current_step + 1, STEP_DATA.size()]
	_step_timer = 0.0
	_step_min_time = data.get("min_time", 0.5)

	# Reset per-step tracking
	if _player:
		_start_position = _player.global_position
		_last_rotation_y = _player.rotation.y
	_total_distance = 0.0
	_total_rotation = 0.0
	_jump_count = 0
	_has_sprinted = false
	_has_flown = false
	_fly_time = 0.0
	_monument_interacted = false
	_terraform_opened = false

	# Show/hide arrow for steps with world targets
	if data.has("world_target"):
		_update_arrow_to_world(data.world_target)
	else:
		_arrow.hide_arrow()

	_instruction_panel.visible = true
	tutorial_step_changed.emit(_current_step)
	print("[Tutorial] Step %d: %s" % [_current_step, data.get("action", "none")])


func _advance_step() -> void:
	_current_step += 1
	if _current_step >= STEP_DATA.size():
		_finish_tutorial()
	else:
		_show_step()


func _finish_tutorial() -> void:
	_active = false
	_completed = true
	_save_completion()
	_hide_all()
	tutorial_completed.emit()
	print("[Tutorial] Completed!")


func _hide_all() -> void:
	_instruction_panel.visible = false
	_arrow.hide_arrow()


func _reset_tracking() -> void:
	_total_distance = 0.0
	_total_rotation = 0.0
	_jump_count = 0
	_has_sprinted = false
	_has_flown = false
	_fly_time = 0.0
	_monument_interacted = false
	_terraform_opened = false


func _process(delta: float) -> void:
	if not _active:
		return

	_step_timer += delta

	# Update tracking
	if _player and is_instance_valid(_player):
		# Distance tracking
		var pos := _player.global_position
		_total_distance += pos.distance_to(_start_position) if _step_timer < 0.1 else pos.distance_to(_player.global_position - _player.velocity * delta)

		# Simple distance from start position for move step
		if _current_step == TutorialStep.MOVE:
			_total_distance = _player.global_position.distance_to(_start_position)

		# Rotation tracking
		var rot_diff := absf(_player.rotation.y - _last_rotation_y)
		if rot_diff > PI:
			rot_diff = TAU - rot_diff
		_total_rotation += rot_diff
		_last_rotation_y = _player.rotation.y

		# Flight tracking
		if GameManager.is_flying:
			_has_flown = true
			_fly_time += delta

		# Sprint tracking
		if _player.has_method("is_sprinting") and _player.is_sprinting():
			_has_sprinted = true
		elif _player.velocity.length() > 8.0:  # Rough sprint detection
			_has_sprinted = true

		# Update world arrow
		var data: Dictionary = STEP_DATA[_current_step] if _current_step < STEP_DATA.size() else {}
		if data.has("world_target"):
			_update_arrow_to_world(data.world_target)

	# Check step completion
	if _step_timer >= _step_min_time:
		_check_step_completion()

	# Auto-advance timeout for stuck steps
	if _step_timer > STEP_TIMEOUT:
		_advance_step()


func _check_step_completion() -> void:
	if _current_step >= STEP_DATA.size():
		return

	var data: Dictionary = STEP_DATA[_current_step]
	var action: String = data.get("action", "")

	match action:
		"any_key":
			pass  # Handled in _unhandled_input
		"move_distance":
			var target: float = data.get("target_value", 10.0)
			if _total_distance >= target:
				_advance_step()
		"look_rotation":
			var target: float = data.get("target_value", 2.0)
			if _total_rotation >= target:
				_advance_step()
		"jump_count":
			var target: float = data.get("target_value", 3.0)
			if _jump_count >= int(target):
				_advance_step()
		"sprint_or_fly":
			if _has_sprinted or _has_flown:
				_advance_step()
		"fly_duration":
			var target: float = data.get("target_value", 3.0)
			if _fly_time >= target:
				_advance_step()
		"monument_interact":
			if _monument_interacted:
				_advance_step()
		"open_terraform":
			if _terraform_opened:
				_advance_step()
		"timeout_or_key":
			if _step_timer > 8.0:  # Auto-advance after 8s
				_advance_step()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	# "any_key" steps advance on any press
	var data: Dictionary = STEP_DATA[_current_step] if _current_step < STEP_DATA.size() else {}
	var action: String = data.get("action", "")

	if action == "any_key" and event is InputEventKey and event.pressed and _step_timer >= _step_min_time:
		_advance_step()
		get_viewport().set_input_as_handled()
		return

	if action == "timeout_or_key" and event is InputEventKey and event.pressed and _step_timer >= _step_min_time:
		_advance_step()
		get_viewport().set_input_as_handled()
		return

	# Track jumps
	if event.is_action_pressed("jump"):
		_jump_count += 1


# ─── External Notifications ──────────────────────────────────────────────
# Called by main.gd/hud_controller.gd to inform the tutorial of player actions.

func notify_monument_interact() -> void:
	_monument_interacted = true


func notify_terraform_opened() -> void:
	_terraform_opened = true


func notify_sprint() -> void:
	_has_sprinted = true


# ─── Arrow Helpers ───────────────────────────────────────────────────────

func _update_arrow_to_world(world_pos: Vector3) -> void:
	## Project a world position to screen coordinates and point the arrow at it.
	if not _player or not is_instance_valid(_player):
		return

	var camera := _player.get_viewport().get_camera_3d()
	if not camera:
		return

	# Check if position is behind the camera
	if not camera.is_position_behind(world_pos):
		var screen_pos := camera.unproject_position(world_pos)
		# Clamp to visible screen area with margin
		var viewport_size := _player.get_viewport().get_visible_rect().size
		screen_pos.x = clampf(screen_pos.x, 40.0, viewport_size.x - 40.0)
		screen_pos.y = clampf(screen_pos.y, 40.0, viewport_size.y - 100.0)
		_arrow.show_at(screen_pos, true)
	else:
		# Target is behind camera — show arrow at top of screen pointing up
		_arrow.show_at(Vector2(_player.get_viewport().get_visible_rect().size.x * 0.5, 60.0), false)
