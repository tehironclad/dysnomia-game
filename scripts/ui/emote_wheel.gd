extends Control
## Radial emote wheel drawn with _draw().  Shows 8 segments in a circle.
## Mouse position determines the highlighted segment; releasing fires emote_selected.

signal emote_selected(emote_id: int)
signal wheel_closed

const EMOTE_LABELS: Array[String] = [
	"Wave", "Salute", "Dance", "Sit",
	"Point", "Laugh", "Shrug", "Clap",
]

const EMOTE_ICONS: Array[String] = [
	"\ud83d\udc4b", "\ud83e\udee1", "\ud83d\udc83", "\ud83e\ude91",
	"\ud83d\udc49", "\ud83d\ude02", "\ud83e\udd37", "\ud83d\udc4f",
]

const SEGMENT_COUNT: int = 8
const WHEEL_RADIUS: float = 120.0
const INNER_RADIUS: float = 40.0

const BG_COLOR := Color(0.08, 0.08, 0.14, 0.92)
const LINE_COLOR := Color(0.3, 0.25, 0.55, 0.6)
const HIGHLIGHT_COLOR := Color(0.45, 0.35, 0.85, 0.35)
const LABEL_COLOR := Color(0.9, 0.88, 1.0)
const ICON_COLOR := Color(1.0, 1.0, 1.0)

var _hovered_segment: int = -1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER)
	# Size large enough to contain the wheel + labels
	var diameter := int(WHEEL_RADIUS * 2 + 80)
	custom_minimum_size = Vector2(diameter, diameter)
	size = Vector2(diameter, diameter)
	position = Vector2(-diameter / 2, -diameter / 2)


func _process(_delta: float) -> void:
	if not visible:
		return
	var center := size / 2.0
	var mouse_pos := get_local_mouse_position()
	var offset := mouse_pos - center
	var dist := offset.length()

	if dist < INNER_RADIUS:
		_hovered_segment = -1
	else:
		# Angle from center (0 = right, counter-clockwise)
		var angle := fposmod(atan2(-offset.y, offset.x), TAU)
		# Shift so segment 0 is at top (12 o'clock)
		var segment_angle := TAU / SEGMENT_COUNT
		var shifted := fposmod(angle + segment_angle / 2.0 + PI / 2.0, TAU)
		_hovered_segment = int(shifted / segment_angle) % SEGMENT_COUNT

	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var segment_angle := TAU / SEGMENT_COUNT

	# Background circle
	draw_circle(center, WHEEL_RADIUS, BG_COLOR)

	# Inner dead zone circle (slightly darker)
	draw_circle(center, INNER_RADIUS, Color(0.05, 0.05, 0.1, 0.95))

	# Draw highlight for hovered segment
	if _hovered_segment >= 0:
		_draw_segment_fill(center, _hovered_segment, segment_angle, HIGHLIGHT_COLOR)

	# Draw segment divider lines
	for i in SEGMENT_COUNT:
		var angle := -PI / 2.0 + segment_angle * i - segment_angle / 2.0
		var inner_pt := center + Vector2(cos(angle), sin(angle)) * INNER_RADIUS
		var outer_pt := center + Vector2(cos(angle), sin(angle)) * WHEEL_RADIUS
		draw_line(inner_pt, outer_pt, LINE_COLOR, 1.0)

	# Draw icons and labels per segment
	for i in SEGMENT_COUNT:
		var angle := -PI / 2.0 + segment_angle * i
		var mid_radius := (INNER_RADIUS + WHEEL_RADIUS) / 2.0

		# Icon position (closer to center)
		var icon_pos := center + Vector2(cos(angle), sin(angle)) * (mid_radius - 8.0)
		_draw_text_centered(EMOTE_ICONS[i], icon_pos, 18, ICON_COLOR)

		# Label position (further out)
		var label_pos := center + Vector2(cos(angle), sin(angle)) * (mid_radius + 18.0)
		var col := LABEL_COLOR if i == _hovered_segment else Color(0.65, 0.6, 0.75)
		_draw_text_centered(EMOTE_LABELS[i], label_pos, 11, col)

	# Outer ring
	draw_arc(center, WHEEL_RADIUS, 0, TAU, 64, LINE_COLOR, 1.5)
	draw_arc(center, INNER_RADIUS, 0, TAU, 32, LINE_COLOR, 1.0)


func _draw_segment_fill(center: Vector2, segment: int, seg_angle: float, color: Color) -> void:
	## Draw a filled arc segment between inner and outer radius.
	var start_angle := -PI / 2.0 + seg_angle * segment - seg_angle / 2.0
	var steps := 16
	var points := PackedVector2Array()
	# Outer arc (forward)
	for s in steps + 1:
		var a := start_angle + seg_angle * (float(s) / steps)
		points.append(center + Vector2(cos(a), sin(a)) * WHEEL_RADIUS)
	# Inner arc (reverse)
	for s in range(steps, -1, -1):
		var a := start_angle + seg_angle * (float(s) / steps)
		points.append(center + Vector2(cos(a), sin(a)) * INNER_RADIUS)
	draw_colored_polygon(points, color)


func _draw_text_centered(text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var draw_pos := pos - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Close on mouse button release if a segment is hovered
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _hovered_segment >= 0:
				emote_selected.emit(_hovered_segment)
			wheel_closed.emit()
			hide_wheel()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			wheel_closed.emit()
			hide_wheel()
			get_viewport().set_input_as_handled()


# ── Public methods ──────────────────────────────────────────────────────

func show_wheel() -> void:
	_hovered_segment = -1
	visible = true
	queue_redraw()


func hide_wheel() -> void:
	visible = false
	_hovered_segment = -1


func get_hovered_segment() -> int:
	return _hovered_segment
