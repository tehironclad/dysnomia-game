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


## Flat floor for the player controller's height queries.
func get_height_at(_x: float, _z: float) -> float:
	return floor_y


func setup_player(spawn: Vector3, yaw: float) -> void:
	player = $Player
	player.position = spawn
	player.rotation.y = yaw
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
	root.add_child(prompt_label)
	var hint := Label.new()
	hint.theme_type_variation = "MutedLabel"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -36)
	hint.text = "%s  speak   ·   %s  at the exit: leave   ·   %s  controls" % [
		ControlsHelp.key_of("chat"), ControlsHelp.key_of("interact"), ControlsHelp.key_of("controls_help")]
	root.add_child(hint)


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


## Places draw their board here.
func on_lines(_lines: Array, _fresh: Array) -> void:
	pass


func _process(_delta: float) -> void:
	if player == null or chat_ctl == null or chat_ctl.is_open():
		return
	var near := Vector2(player.global_position.x - exit_at.x, player.global_position.z - exit_at.z).length() < exit_radius
	if near != _near_exit:
		_near_exit = near
		prompt_label.text = ("%s  leave, back to %s" % [ControlsHelp.key_of("interact"), GameManager.territory_name]) if near else ""
	if player.global_position.y < floor_y - 25.0:  # fell off the edge of the Void
		player.global_position = exit_at + Vector3(0, 1.5, -2.0)
		player.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if chat_ctl == null or chat_ctl.is_open():
		return
	if event.is_action_pressed("chat"):
		get_viewport().set_input_as_handled()
		chat_ctl.open()
	elif event.is_action_pressed("interact") and _near_exit:
		get_viewport().set_input_as_handled()
		Travel.go(get_tree(), GameManager.territory_address)
	elif event.is_action_pressed("controls_help"):
		pass


static func load_piece(name: String) -> Node3D:
	return (load("res://assets/buildings/scifi/%s.gltf" % name) as PackedScene).instantiate()
