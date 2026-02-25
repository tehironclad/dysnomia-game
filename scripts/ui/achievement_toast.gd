extends Control
## Achievement toast notification — slides in from top, shows name + XP, slides out.
## Queue-based: multiple achievements unlocking at once display sequentially.

var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _queue: Array[Dictionary] = []
var _is_showing: bool = false


func _ready() -> void:
	# Anchor to top-center, don't block input
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	size = Vector2(0, 0)

	# Build the toast panel
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(320, 60)
	_panel.position = Vector2(0, -80)  # Start off-screen

	# Style: dark semi-transparent with gold border
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.14, 0.92)
	style.border_color = Color(1.0, 0.84, 0.0, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# VBox for title + subtitle
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
	vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 12)
	_subtitle_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	vbox.add_child(_subtitle_label)

	# Center panel horizontally
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-160, -80)  # half-width left, off-screen top


func show_achievement(achievement_name: String, description: String, xp: int = 50) -> void:
	## Queue an achievement toast. Shows immediately if nothing is currently displayed.
	_queue.append({
		"title": achievement_name,
		"subtitle": "%s  (+%d XP)" % [description, xp],
	})
	if not _is_showing:
		_show_next()


func show_tier_up(tier: int, title: String) -> void:
	## Special toast for tier/evolution change.
	_queue.append({
		"title": "Evolution: %s" % title,
		"subtitle": "Tier %d reached!" % tier,
	})
	if not _is_showing:
		_show_next()


func show_generic(title: String, subtitle: String) -> void:
	## Generic toast for any notification.
	_queue.append({"title": title, "subtitle": subtitle})
	if not _is_showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_is_showing = false
		return

	_is_showing = true
	var data: Dictionary = _queue.pop_front()
	_title_label.text = data.get("title", "Achievement!")
	_subtitle_label.text = data.get("subtitle", "")

	# Slide in from top, hold, slide out
	var tween := create_tween()
	# Slide in (0.35s, ease-out)
	tween.tween_property(_panel, "position:y", 16.0, 0.35) \
		.from(-80.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Hold (3.5s)
	tween.tween_interval(3.5)
	# Slide out (0.3s, ease-in)
	tween.tween_property(_panel, "position:y", -80.0, 0.3) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Brief pause before next
	tween.tween_interval(0.3)
	# Show next in queue
	tween.tween_callback(_show_next)
