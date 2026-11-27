class_name AwayCard
extends PanelContainer
## The "while you were away" card (AwayDiff's model): what really changed since
## your last visit on this computer, each line with its block or tx. Click a line to
## go there (warp to the QING, the room's history at that line). Used on the front
## door (right column), in the notification panel and, compact, on arrival (Alerts).
## Not modal: it never takes the keys.
##
## States: "reading" (comparing: loading is not empty), "ready" (the card), "hidden"
## (first visit, no wallet, or dismissed: nothing drawn).

signal go(target: Dictionary)
signal dismissed

const KIND_TAGS := {"mention": "MENTION", "room": "ROOM", "lead_lost": "LEAD LOST", "lead_gained": "LEAD", "tier": "TIER",
	"hypo": "HYPOBAR", "bars": "YOUR BARS", "new_qings": "NEW QINGS", "more": "MORE"}
const KIND_COLORS := {"mention": Color("#ffd27a"), "room": Color("#64e3a8"), "lead_lost": Color("#ff8fa0"),
	"lead_gained": Color("#ffd27a"), "tier": Color("#ff9be6"), "hypo": Color("#b9a3ff"), "bars": Color("#7fd3ff"),
	"new_qings": Color("#a8e6ff"), "more": DeepFieldTheme.MUTED}

var compact := false
var max_entries := 0          ## 0 = all
var max_body_h := 0.0         ## > 0: the lines scroll inside this height (the front door's column)
var dismissable := true
var width := 640.0
var state := "hidden"
var model: Dictionary = {}
var _col: VBoxContainer
var _head: Label
var _since: Label
var _close: Button
var _body: VBoxContainer
var _scroll: ScrollContainer
var _foot: Label


func _init(p_compact: bool = false, p_width: float = 640.0, p_max: int = 0) -> void:
	compact = p_compact
	width = p_width
	max_entries = p_max
	name = "AwayCard"


func _ready() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.accent_style(DeepFieldTheme.ICE, 0.9)
	sb.bg_color = Color(DeepFieldTheme.BLACK, 0.88)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(width, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 4 if compact else 6)
	add_child(_col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_col.add_child(top)
	_head = Label.new()
	_head.theme_type_variation = "DisplayLabel"
	_head.add_theme_font_size_override("font_size", DeepFieldTheme.FS_LEAD if compact else DeepFieldTheme.FS_TITLE - 2)
	_head.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_head.text = "WHILE YOU WERE AWAY"
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_head)
	_close = Button.new()
	_close.text = "×"
	_close.flat = true
	_close.focus_mode = Control.FOCUS_NONE
	_close.tooltip_text = "Dismiss (it stays in the notifications, %s)" % ControlsHelp.key_of("notifications")
	_close.add_theme_font_size_override("font_size", DeepFieldTheme.FS_LEAD)
	_close.pressed.connect(func(): dismissed.emit())
	top.add_child(_close)
	_since = _label("", "MutedLabel", DeepFieldTheme.FS_CAPTION)
	_col.add_child(_since)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3 if compact else 5)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if max_body_h > 0.0:
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.add_child(_body)
		_col.add_child(_scroll)
	else:
		_col.add_child(_body)
	_foot = _label("", "MutedLabel", DeepFieldTheme.FS_CAPTION)
	_col.add_child(_foot)
	_render()


func _label(text: String, variation: String, size: int, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", DeepFieldTheme.fs(size))
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width - 40, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## state: "reading" | "ready" | "hidden". `card` is AwayDiff.compute's model (or, while
## reading, {since} for the header).
func set_card(p_state: String, card: Dictionary) -> void:
	state = p_state
	model = card
	if is_node_ready():
		_render()


func _render() -> void:
	visible = state in ["reading", "ready"] and not bool(model.get("first", false))
	if not visible:
		return
	_close.visible = dismissable
	for c in _body.get_children():
		c.queue_free()
	_since.text = AwayDiff.since_text(model) + ((" · ≈ %s ago" % AwayDiff.ago_text(model)) if state == "ready" and AwayDiff.ago_text(model) != "—" else "")
	_foot.text = ""
	if state == "reading":
		_body.add_child(_label("Comparing with your last visit: reading your rooms, QINGs, bars and the registry from the chain…", "MonoLabel", DeepFieldTheme.FS_SMALL, DeepFieldTheme.MUTED))
		return
	var entries: Array = model.get("entries", [])
	var fails: Array = model.get("fails", [])
	if bool(model.get("quiet", false)):
		_body.add_child(_label(AwayDiff.quiet_text(model), "MonoLabel", DeepFieldTheme.FS_SMALL, DeepFieldTheme.INK))
	var shown := entries if max_entries <= 0 else entries.slice(0, max_entries)
	for e in shown:
		_body.add_child(_entry(e))
	for f in fails:
		_body.add_child(_label("—  " + String(f), "MonoLabel", DeepFieldTheme.FS_CAPTION, Color("#ffd27a")))
	if entries.is_empty() and not fails.is_empty():
		_body.add_child(_label("Nothing else that could be read changed.", "MutedLabel", DeepFieldTheme.FS_CAPTION))
	var hidden := entries.size() - shown.size()
	if hidden > 0 and not compact:
		var all := Button.new()
		all.text = "Show all (+%d)" % hidden
		all.focus_mode = Control.FOCUS_NONE
		all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		all.pressed.connect(func():
			max_entries = 0
			_render())
		_body.add_child(all)
	elif hidden > 0:
		_foot.text = "+%d more · %s opens the notifications" % [hidden, ControlsHelp.key_of("notifications")]
	elif compact:
		_foot.text = "%s opens the notifications (click a line there to go to it)" % ControlsHelp.key_of("notifications")
	_fit_scroll()


## The scroll box as tall as its lines, up to max_body_h.
func _fit_scroll() -> void:
	if _scroll == null:
		return
	_scroll.custom_minimum_size = Vector2(0, 0)
	await get_tree().process_frame
	if not is_instance_valid(_scroll):
		return
	_scroll.custom_minimum_size = Vector2(0, minf(_body.get_combined_minimum_size().y, max_body_h))


func _entry(e: Dictionary) -> Control:
	var kind := String(e.get("kind", ""))
	var col: Color = KIND_COLORS.get(kind, DeepFieldTheme.ICE)
	var p := Entry.new()
	var sb := DeepFieldTheme.accent_style(col, 0.55)
	sb.content_margin_top = 4 if compact else 6
	sb.content_margin_bottom = 4 if compact else 6
	sb.content_margin_left = 10
	p.add_theme_stylebox_override("panel", sb)
	p.base = sb
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(col, 0.16)
	p.hover = hov
	var target: Dictionary = e.get("go", {})
	p.clickable = not target.is_empty()
	if p.clickable:
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.tooltip_text = "Go there" + ((" · tx %s" % String(e["tx"])) if String(e.get("tx", "")) != "" else "")
		p.clicked.connect(func(): go.emit(target))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var tag := Label.new()
	tag.theme_type_variation = "MonoLabel"
	tag.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	tag.add_theme_color_override("font_color", col)
	tag.text = String(KIND_TAGS.get(kind, kind.to_upper()))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL if compact else DeepFieldTheme.FS_BODY)
	title.text = String(e.get("title", ""))
	if compact:  # one line each: the compact card must stay inside HudLayout's alerts slot
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.clip_text = true
		title.tooltip_text = title.text
	else:
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(width - 190 - (16 if _scroll else 0), 0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	if String(e.get("sub", "")) != "" and not (compact and kind == "more"):
		var sub := Label.new()
		sub.theme_type_variation = "MonoLabel"
		sub.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
		sub.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
		sub.text = String(e["sub"])
		if compact:
			sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			sub.clip_text = true
		else:
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(width - 50 - (16 if _scroll else 0), 0)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub)
	return p


## One clickable line (hover tint, a click emits `clicked`).
class Entry extends PanelContainer:
	signal clicked
	var clickable := false
	var base: StyleBox
	var hover: StyleBox

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS if clickable else Control.MOUSE_FILTER_IGNORE  # PASS: the wheel still scrolls the list
		mouse_entered.connect(func(): if clickable: add_theme_stylebox_override("panel", hover))
		mouse_exited.connect(func(): add_theme_stylebox_override("panel", base))

	func _gui_input(event: InputEvent) -> void:
		if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			clicked.emit()
