extends PanelContainer
## Guestbook panel — shows visitor flags/messages, allows planting a new flag.
## B key toggle. Scrollable list of past visitors + input for new message.

signal panel_closed
signal plant_flag_requested(message: String)

var _content_label: RichTextLabel
var _message_input: LineEdit
var _plant_button: Button
var _status_label: Label
var _close_button: Button
var _flag_count_label: Label


func _ready() -> void:
	_build_ui()
	visible = false


func _build_ui() -> void:
	name = "GuestbookPanel"
	custom_minimum_size = Vector2(420.0, 500.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.94)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 0.7, 1.0, 0.5)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)

	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-210.0, -250.0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Header row
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Territory Guestbook [B]"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_flag_count_label = Label.new()
	_flag_count_label.text = "0 flags"
	_flag_count_label.add_theme_font_size_override("font_size", 13)
	_flag_count_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	header.add_child(_flag_count_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.pressed.connect(func() -> void: panel_closed.emit())
	header.add_child(_close_button)

	vbox.add_child(header)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable content
	_content_label = RichTextLabel.new()
	_content_label.bbcode_enabled = true
	_content_label.scroll_active = true
	_content_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_label.custom_minimum_size = Vector2(400.0, 300.0)
	_content_label.add_theme_font_size_override("normal_font_size", 14)
	_content_label.add_theme_color_override("default_color", Color(0.85, 0.87, 0.9))
	vbox.add_child(_content_label)

	# Plant flag section
	var plant_header := Label.new()
	plant_header.text = "Plant Your Flag"
	plant_header.add_theme_font_size_override("font_size", 15)
	plant_header.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	vbox.add_child(plant_header)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)

	_message_input = LineEdit.new()
	_message_input.placeholder_text = "Leave a message (80 chars max)..."
	_message_input.max_length = 80
	_message_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_input.text_submitted.connect(func(_text: String) -> void: _on_plant_pressed())
	input_row.add_child(_message_input)

	_plant_button = Button.new()
	_plant_button.text = "Plant Flag"
	_plant_button.pressed.connect(_on_plant_pressed)
	input_row.add_child(_plant_button)

	vbox.add_child(input_row)

	# Status label
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.5))
	vbox.add_child(_status_label)

	add_child(vbox)


func populate(flags: Array) -> void:
	## Fill the guestbook with flag data.
	_content_label.clear()

	if flags.is_empty():
		_content_label.text = "[center][color=#667]No flags planted yet.\nBe the first to leave your mark![/color][/center]"
		_flag_count_label.text = "0 flags"
		return

	_flag_count_label.text = "%d flag%s" % [flags.size(), "s" if flags.size() != 1 else ""]

	for flag in flags:
		if not flag is Dictionary:
			continue

		var username: String = flag.get("username", "")
		var wallet: String = flag.get("wallet", "")
		var message: String = flag.get("message", "")
		var timestamp = flag.get("timestamp", 0)

		# Format display name
		var display_name := username if not username.is_empty() else _truncate_wallet(wallet)

		# Format timestamp
		var time_str := ""
		if timestamp is float or timestamp is int:
			var dt := Time.get_datetime_dict_from_unix_time(int(timestamp))
			time_str = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

		# Build entry
		_content_label.append_text("[b][color=#8af]%s[/color][/b]" % display_name)
		if not time_str.is_empty():
			_content_label.append_text("  [color=#556]%s[/color]" % time_str)
		_content_label.append_text("\n")
		if not message.is_empty():
			_content_label.append_text("[color=#bbc]  \"%s\"[/color]\n" % message)
		_content_label.append_text("\n")


func set_status(text: String) -> void:
	_status_label.text = text


func _on_plant_pressed() -> void:
	var msg := _message_input.text.strip_edges()
	if msg.is_empty():
		msg = "I was here!"  # Default message
	_message_input.text = ""
	_plant_button.disabled = true
	_status_label.text = "Planting flag..."
	plant_flag_requested.emit(msg)

	# Re-enable after a brief delay
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		_plant_button.disabled = false
	)


func _truncate_wallet(wallet: String) -> String:
	if wallet.length() > 12:
		return wallet.left(6) + "..." + wallet.right(4)
	return wallet
