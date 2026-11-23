extends Control
## "HAPPENING NOW" toast feed + online counter for CommunityHub.
##   ● 12 in Sunny's · 48 on Dysnomia
##   HAPPENING NOW
##   🍻 Alice bought a round for the house!
##   🚀 Bob boarded the Upsilon Rocket · SUNNY'S
## Sits on the left edge under the progression HUD; ignores the mouse; hides when idle.

const MAX_TOASTS: int = 4
const TOAST_TIME: float = 9.0
const WIDTH: float = 330.0

var _hub: Node = null
var _counter: Label
var _header: Label
var _list: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(14, 168)
	size = Vector2(WIDTH, 10)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(box)

	_counter = Label.new()
	_counter.name = "OnlineCounter"
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.add_theme_font_size_override("font_size", 13)
	_counter.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7, 0.92))
	_counter.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_counter.add_theme_constant_override("outline_size", 4)
	_counter.visible = false
	box.add_child(_counter)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.04, 0.12, 0.62)
	sb.border_color = Color(0.75, 0.5, 1.0, 0.45)
	sb.border_width_left = 3
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	box.add_child(_panel)

	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 3)
	_panel.add_child(inner)

	_header = Label.new()
	_header.text = "HAPPENING NOW"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_theme_font_size_override("font_size", 11)
	_header.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35, 0.95))
	inner.add_child(_header)

	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 2)
	inner.add_child(_list)


func bind(hub: Node) -> void:
	_hub = hub
	hub.moment_received.connect(_on_moment)
	hub.online_counts_changed.connect(_on_counts)


func _on_counts(_here: int, _total: int) -> void:
	var t: String = _hub.counter_text() if _hub else ""
	_counter.text = "● " + t if not t.is_empty() else ""
	_counter.visible = not t.is_empty()


func _on_moment(kind: String, data: Dictionary, from_name: String) -> void:
	# Arrivals elsewhere on Dysnomia would be noise; keep those to this QING.
	if kind == "arrival" and (not bool(data.get("here", false)) or bool(data.get("self", false))):
		return
	var shown_name := "You" if bool(data.get("self", false)) else from_name
	push_toast(_hub.describe(kind, data, shown_name) if _hub else kind)


func push_toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 24, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.95, 0.93, 1.0))
	l.modulate.a = 0.0
	_list.add_child(l)
	while _list.get_child_count() > MAX_TOASTS:
		var old := _list.get_child(0)
		_list.remove_child(old)
		old.queue_free()
	_panel.visible = true
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.25)
	tw.tween_interval(TOAST_TIME)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_expire.bind(l))


func _expire(l: Label) -> void:
	if is_instance_valid(l):
		l.queue_free()
	if get_toast_texts().is_empty():
		_panel.visible = false


func get_toast_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in _list.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append(c.text)
	return out


func get_counter_text() -> String:
	return _counter.text if _counter.visible else ""
