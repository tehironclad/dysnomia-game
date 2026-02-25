# Copyright (c) 2020-2025 Mansur Isaev and contributors - MIT License
# Adapted for Dysnomia Game from godot-console plugin.

## Default container for Console output/input.
extends VBoxContainer


var _console: Node  # Console autoload

var _console_output: RichTextLabel
var _console_input: LineEdit

var _tooltip_label: RichTextLabel

# Cycle through the autocomplete options.
var _autocomplete_index: int = -1
var _autocomplete_prompt: String = ""


func _init() -> void:
	# Semi-transparent dark background
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.02, 0.05, 0.85)
	panel.border_color = Color(0.3, 0.4, 0.6, 0.6)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(8)
	add_theme_stylebox_override("panel", panel)

	_console_output = RichTextLabel.new()
	_console_output.size_flags_vertical = SIZE_EXPAND_FILL
	_console_output.scroll_following = true
	_console_output.selection_enabled = true
	_console_output.focus_mode = Control.FOCUS_NONE
	_console_output.bbcode_enabled = true
	_console_output.add_theme_font_size_override("normal_font_size", 13)
	self.add_child(_console_output, false, Node.INTERNAL_MODE_FRONT)

	_console_input = LineEdit.new()
	_console_input.context_menu_enabled = false
	_console_input.clear_button_enabled = true
	_console_input.caret_blink = true
	_console_input.placeholder_text = "Enter command..."
	_console_input.editable = false

	_console_input.text_changed.connect(_on_input_text_changed)
	_console_input.gui_input.connect(_on_input_gui_event)
	_console_output.meta_clicked.connect(_set_input_text)

	self.add_child(_console_input, false, Node.INTERNAL_MODE_FRONT)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.set_autowrap_mode(TextServer.AUTOWRAP_OFF)
	_tooltip_label.set_fit_content(true)
	_tooltip_label.set_v_grow_direction(Control.GROW_DIRECTION_BEGIN)
	_tooltip_label.set_offset(SIDE_LEFT, 4.0)
	_tooltip_label.set_offset(SIDE_BOTTOM, -4.0)
	_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_tooltip_label.hide()
	_console_input.add_child(_tooltip_label)


func _enter_tree() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_set_console(get_node_or_null(^"/root/Console"))


func _exit_tree() -> void:
	_set_console(null)


func _set_console(console: Node) -> void:
	if is_same(_console, console):
		return

	if is_instance_valid(_console):
		if _console.printed_line.is_connected(_console_output.append_text):
			_console.printed_line.disconnect(_console_output.append_text)
		if _console.cleared.is_connected(_console_output.clear):
			_console.cleared.disconnect(_console_output.clear)

	if is_instance_valid(console):
		if not console.printed_line.is_connected(_console_output.append_text):
			console.printed_line.connect(_console_output.append_text)
		if not console.cleared.is_connected(_console_output.clear):
			console.cleared.connect(_console_output.clear)

	_console = console
	_console_input.editable = is_instance_valid(_console)


func _set_input_text(text: String) -> void:
	_console_input.set_text(text)
	_console_input.set_caret_column(text.length())
	_console_input.text_changed.emit(text)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_console_input.grab_focus()
		_console_input.accept_event()


func _show_autocomplete(text: String) -> void:
	if not is_instance_valid(_console):
		return
	var autocomplete: PackedStringArray
	if text.is_empty():
		autocomplete = PackedStringArray()
	else:
		autocomplete = _console.autocomplete_list(text, _autocomplete_index)
	if autocomplete.is_empty():
		_tooltip_label.hide()
	else:
		_tooltip_label.set_text("\n".join(autocomplete))
		_tooltip_label.show()


func _on_input_text_changed(text: String) -> void:
	_show_autocomplete(text if _autocomplete_prompt.is_empty() else _autocomplete_prompt)


func _cycle_autocomplete(direction: int) -> void:
	if not is_instance_valid(_console):
		return
	var autocomplete: PackedStringArray = _console.autocomplete_list(_autocomplete_prompt)
	if autocomplete.is_empty():
		return
	_autocomplete_index = wrapi(_autocomplete_index + direction, 0, autocomplete.size())
	_set_input_text(_console.autocomplete_command(_autocomplete_prompt, _autocomplete_index))


func _on_input_gui_event(event: InputEvent) -> void:
	if not is_instance_valid(_console):
		return

	if event.is_action_type() and not event.is_action(&"ui_text_indent"):
		_autocomplete_index = -1
		_autocomplete_prompt = ""
		_show_autocomplete(_console_input.text)

	if event.is_action_pressed(&"ui_text_submit"):
		_console.execute(_console_input.text)
		_console_input.clear()
	elif event.is_action_pressed(&"ui_text_completion_accept"):
		if _autocomplete_prompt.is_empty():
			_autocomplete_prompt = _console_input.text
		_cycle_autocomplete(-1 if Input.is_key_pressed(KEY_SHIFT) else 1)
	elif event.is_action_pressed(&"ui_text_caret_up"):
		_set_input_text(_console.get_prev_command())
	elif event.is_action_pressed(&"ui_text_caret_down"):
		_set_input_text(_console.get_next_command())
	else:
		return

	_console_input.accept_event()
