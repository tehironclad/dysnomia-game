class_name PlaceBase
extends Node3D
## Shared by the places you visit to talk (the QING hall, the Void): the
## player on flat ground, a small HUD (title, facts, hints, prompt), the chat
## controller (T opens it), a speaker-echo ring, and an exit back to the
## territory you came from.

var player: CharacterBody3D
var chat_ctl: ChatController
var echoes: SpeakerEchoes
var hud_layer: CanvasLayer
var title_label: Label
var info_label: Label
var prompt_label: Label
var exit_at := Vector3.ZERO
var exit_radius := 2.5
var floor_y := 0.0
var _near_exit := false
## The entrance (add_door): a door on the +Z side, the way in and out.
var door: PassDoor
var _spawn := Vector3.ZERO
var help: ControlsHelp  ## F1 (the hint promises it)


## Flat floor for the player controller's height queries.
func get_height_at(_x: float, _z: float) -> float:
	return floor_y


func setup_player(spawn: Vector3, yaw: float) -> void:
	player = $Player
	player.position = spawn
	player.rotation.y = yaw
	_spawn = spawn
	# Came in through a door: walk in from the entrance (once the door is built).
	if Travel.take_door(true) != "":
		_arrive.call_deferred()
	if player.has_method("set_terrain_generator"):
		player.set_terrain_generator(self)
	var pc: Camera3D = player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
	if pc:
		pc.current = true


func setup_hud(title: String) -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DeepFieldTheme.get_theme()
	hud_layer.add_child(root)
	var box := VBoxContainer.new()
	box.position = Vector2(20, 18)
	root.add_child(box)
	title_label = Label.new()
	title_label.theme_type_variation = "DisplayLabel"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.text = title
	box.add_child(title_label)
	info_label = Label.new()
	info_label.theme_type_variation = "MutedLabel"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(520, 0)
	box.add_child(info_label)
	prompt_label = Label.new()
	prompt_label.theme_type_variation = "MonoLabel"
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-400, -110)
	prompt_label.size = Vector2(800, 30)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt_label.add_theme_constant_override("outline_size", 6)
	root.add_child(prompt_label)
	var hint := Label.new()
	hint.theme_type_variation = "MutedLabel"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -36)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))  # readable over the floor rings
	hint.add_theme_constant_override("outline_size", 6)
	hint.text = "%s  speak   ·   %s  at the exit: leave   ·   %s  controls" % [
		ControlsHelp.key_of("chat"), ControlsHelp.key_of("interact"), ControlsHelp.key_of("controls_help")]
	root.add_child(hint)
	help = ControlsHelp.new()
	help.position = Vector2(20, 130)
	root.add_child(help)
	add_child(NotificationPanel.new())  # invites, stakes, wagers: above a seated table too


func setup_chat(mode: String, q: Dictionary, history: int = 80) -> void:
	chat_ctl = ChatController.new()
	chat_ctl.name = "Chat"
	chat_ctl.history_limit = history
	add_child(chat_ctl)
	chat_ctl.setup(mode, q)
	chat_ctl.opened.connect(func(): player.process_mode = Node.PROCESS_MODE_DISABLED)
	chat_ctl.closed.connect(func(): player.process_mode = Node.PROCESS_MODE_INHERIT)
	echoes = SpeakerEchoes.new()
	echoes.name = "Echoes"
	add_child(echoes)
	chat_ctl.lines_changed.connect(func(ls, fresh):
		echoes.update_from(ls)
		on_lines(ls, fresh))


## The entrance: `style` "slide" or "curtain" (round = a disc), its threshold
## middle at `at` on the floor, facing ±Z. The player arrives through it and
## leaves through it (DoorSequence).
func add_door(style: String, width: float, height: float, at: Vector3, color := DeepFieldTheme.ICE, round := false, camera_stop := true) -> PassDoor:
	door = PassDoor.make(style, width, height, color, round)
	add_child(door)
	door.position = at
	if camera_stop:
		_camera_stop(width, height, at)
	return door


## A body in the doorway that only the camera's spring arm hits (never the player):
## behind a player who has just walked in, the arm would otherwise pass out through
## the gap in the wall and show the back of the shut door instead of the room.
const CAMERA_ONLY_LAYER := 1 << 15


func _camera_stop(width: float, height: float, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "DoorCameraStop"
	body.collision_layer = CAMERA_ONLY_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width + 0.4, height + 0.4, 0.3)
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	body.add_child(cs)
	body.position = at
	add_child(body)
	var arm: SpringArm3D = player.get_node_or_null("CameraRig/SpringArm3D") if player else null
	if arm:
		arm.collision_mask |= CAMERA_ONLY_LAYER


func _door_at() -> Vector3:
	return door.position if door else Vector3(exit_at.x, floor_y, exit_at.z + 0.7)


func _arrive() -> void:
	if player == null or not is_instance_valid(player):
		return
	var d := _door_at()
	if door:
		door.open = 1.0
	_near_exit = true  # no exit prompt flash on the way in
	DoorSequence.arrive(self, player, Vector3(d.x, _spawn.y, d.z - 0.35), _spawn, door)


## Use at the exit: walk out through the door, then back to the territory.
func _leave() -> void:
	if DoorSequence.active_in(self):
		return
	prompt_label.text = ""
	var d := _door_at()
	var kind := Travel.door_of_scene(scene_file_path)
	DoorSequence.enter(self, player, Vector3(d.x, floor_y, d.z + 0.25), door,
		func(): Travel.out_door(get_tree(), kind))


## Places draw their board here.
func on_lines(_lines: Array, _fresh: Array) -> void:
	pass


func _process(_delta: float) -> void:
	if player == null or chat_ctl == null or chat_ctl.is_open() or DoorSequence.active_in(self):
		return
	var near := Vector2(player.global_position.x - exit_at.x, player.global_position.z - exit_at.z).length() < exit_radius
	if near != _near_exit:
		_near_exit = near
		PromptFade.set_text(prompt_label, ("%s  leave, back to %s" % [ControlsHelp.key_of("interact"), GameManager.territory_name]) if near else "")
	if player.global_position.y < floor_y - 25.0:  # fell off the edge of the Void
		player.global_position = exit_at + Vector3(0, 1.5, -2.0)
		player.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if chat_ctl == null or chat_ctl.is_open() or DoorSequence.active_in(self):
		return
	if event.is_action_pressed("chat"):
		get_viewport().set_input_as_handled()
		chat_ctl.open()
	elif event.is_action_pressed("interact") and _near_exit:
		get_viewport().set_input_as_handled()
		_leave()
	elif event.is_action_pressed("controls_help") and help:
		get_viewport().set_input_as_handled()
		help.toggle()


static func load_piece(name: String) -> Node3D:
	return (load("res://assets/buildings/scifi/%s.gltf" % name) as PackedScene).instantiate()
