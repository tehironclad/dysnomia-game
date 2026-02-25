extends PanelContainer
## In-game panel showing daily challenges with progress bars.
## Opens via a keybind in HUD.  Fetches data from DailyChallenges node.

signal panel_closed

var _scroll: ScrollContainer
var _entries_vbox: VBoxContainer
var _title_label: Label
var _timer_label: Label
var _refresh_btn: Button
var _close_btn: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	# Panel styling (matches settings_menu.gd)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.09, 0.96)
	panel_style.set_corner_radius_all(10)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.3, 0.7, 0.7)
	panel_style.content_margin_left = 14
	panel_style.content_margin_right = 14
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", panel_style)

	# Size and position (centered)
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(420, 480)
	size = Vector2(420, 480)
	position = Vector2(-210, -240)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer_vbox)

	# ── Header row ──────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "DAILY CHALLENGES"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.65, 0.55, 0.98))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(32, 32)
	_close_btn.pressed.connect(_on_close)
	header.add_child(_close_btn)

	# Timer label (time until reset)
	_timer_label = Label.new()
	_timer_label.text = ""
	_timer_label.add_theme_font_size_override("font_size", 12)
	_timer_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	outer_vbox.add_child(_timer_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	outer_vbox.add_child(spacer)

	# ── Scroll area for challenge entries ───────────────────────────────
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(_scroll)

	_entries_vbox = VBoxContainer.new()
	_entries_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_entries_vbox)

	# ── Bottom row ──────────────────────────────────────────────────────
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 8)
	outer_vbox.add_child(bottom_spacer)

	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(bottom_row)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.custom_minimum_size = Vector2(100, 34)
	_refresh_btn.pressed.connect(_on_refresh)
	bottom_row.add_child(_refresh_btn)


# ── Public methods ──────────────────────────────────────────────────────

func show_panel() -> void:
	visible = true


func hide_panel() -> void:
	visible = false


func populate(data: Dictionary) -> void:
	## Populate the panel from a daily API response.
	## Expected keys: "challenges" (Array of {name, description, progress, target, reward}),
	## optionally "resetIn" (seconds until reset).

	# Clear existing entries
	for child in _entries_vbox.get_children():
		child.queue_free()

	# Update timer
	var reset_in: int = data.get("resetIn", 0)
	if reset_in > 0:
		var hours := reset_in / 3600
		var minutes := (reset_in % 3600) / 60
		_timer_label.text = "Resets in %dh %dm" % [hours, minutes]
	else:
		_timer_label.text = ""

	# Build entries
	var challenges: Variant = data.get("challenges", [])
	if not challenges is Array:
		_add_empty_label("No challenges available.")
		return

	var challenge_list: Array = challenges
	if challenge_list.is_empty():
		_add_empty_label("No challenges available.")
		return

	for entry: Variant in challenge_list:
		if entry is Dictionary:
			_add_challenge_entry(entry as Dictionary)


# ── Entry builder ───────────────────────────────────────────────────────

func _add_challenge_entry(challenge: Dictionary) -> void:
	var entry_vbox := VBoxContainer.new()
	entry_vbox.add_theme_constant_override("separation", 2)
	_entries_vbox.add_child(entry_vbox)

	# Name (bold via font size)
	var name_label := Label.new()
	var cname: String = challenge.get("name", "Challenge")
	var reward: String = str(challenge.get("reward", ""))
	if not reward.is_empty():
		name_label.text = cname + "  [" + reward + "]"
	else:
		name_label.text = cname
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.88, 1.0))
	entry_vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = challenge.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry_vbox.add_child(desc_label)

	# Progress bar
	var progress_val: int = challenge.get("progress", 0)
	var target_val: int = challenge.get("target", 1)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = target_val
	bar.value = mini(progress_val, target_val)
	bar.custom_minimum_size = Vector2(0, 18)
	bar.show_percentage = false

	# Style the progress bar
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.12, 0.18)
	bar_bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	if progress_val >= target_val:
		bar_fill.bg_color = Color(0.2, 0.75, 0.3)  # Green = complete
	else:
		bar_fill.bg_color = Color(0.45, 0.35, 0.85)  # Purple = in progress
	bar_fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", bar_fill)

	entry_vbox.add_child(bar)

	# Progress text
	var prog_label := Label.new()
	prog_label.text = "%d / %d" % [mini(progress_val, target_val), target_val]
	prog_label.add_theme_font_size_override("font_size", 11)
	prog_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	prog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry_vbox.add_child(prog_label)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	_entries_vbox.add_child(sep)


func _add_empty_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_entries_vbox.add_child(lbl)


# ── Callbacks ───────────────────────────────────────────────────────────

func _on_close() -> void:
	hide_panel()
	panel_closed.emit()


func _on_refresh() -> void:
	## Clear entries and signal that a refresh is wanted.
	## The parent (HUD or main) should call fetch_daily() then populate() again.
	for child in _entries_vbox.get_children():
		child.queue_free()
	_add_empty_label("Loading...")
	# Parent should connect to this button or poll; we just emit closed then reopen.
	# A simpler approach: directly call ChainManager if available as autoload.
	# Left to parent wiring — the panel itself is data-driven via populate().
