class_name MinigameBase
extends PanelContainer
## Base class for all pub minigames. Provides common UI framework:
## dark panel, accent border, header with title + close, score display.

signal game_started
signal game_ended(score: int)
signal game_closed

var _score: int = 0
var _score_label: Label
var _high_score: int = 0
var _game_name: String = "Minigame"
var _content_vbox: VBoxContainer


func _init_ui(title: String) -> void:
	_game_name = title

	# Panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.09, 0.96)
	style.set_corner_radius_all(10)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.3, 0.7, 0.7)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	# Size and center
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(420, 480)
	size = Vector2(420, 480)
	position = Vector2(-210, -240)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer_vbox)

	# Header
	var header := _build_header(title)
	outer_vbox.add_child(header)

	# Score
	_score_label = Label.new()
	_score_label.text = "Score: 0"
	_score_label.add_theme_font_size_override("font_size", 16)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(_score_label)

	# Content area
	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_content_vbox)


func _build_header(title: String) -> HBoxContainer:
	var header := HBoxContainer.new()

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.65, 0.55, 0.98))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(func(): game_closed.emit())
	header.add_child(close_btn)

	return header


func _update_score(points: int) -> void:
	_score += points
	if _score_label:
		_score_label.text = "Score: %d  |  High: %d" % [_score, _high_score]


func _set_high_score(hs: int) -> void:
	_high_score = hs
	_update_score(0)


func start_game() -> void:
	_score = 0
	_update_score(0)
	game_started.emit()


func end_game() -> void:
	game_ended.emit(_score)
