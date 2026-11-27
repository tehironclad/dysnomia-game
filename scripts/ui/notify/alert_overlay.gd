class_name AlertOverlay
extends CanvasLayer
## Alerts' layer: the toasts (a mention, an invite, an arrival, a lost crown; merged
## and paced by AlertGate) and, once on arrival, the compact "while you were away"
## card (a toast replaces it: the card stays in the notification panel). In a territory or a place they sit in HudLayout's "alerts" slot (right,
## under the act tracker, over the key row); on the front door between its columns.
## Above a seated table (layer 28) so they reach you while you play. Never modal.

const MAX_TOASTS := 3
const FRONT_W := 380.0
const CARD_ENTRIES := 3

var _root: Control
var _stack: VBoxContainer
var _card: AwayCard
var _card_until := 0.0
var _toasts := {}  # toast id → {node, label, title, until}
var _front := false


func _init() -> void:
	name = "AlertOverlay"


func _ready() -> void:
	layer = 28
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = DeepFieldTheme.get_theme()
	add_child(_root)
	_stack = VBoxContainer.new()
	_stack.name = "Stack"
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.add_theme_constant_override("separation", HudLayout.GAP)
	_root.add_child(_stack)
	_card = AwayCard.new(true, HudLayout.COL_W, CARD_ENTRIES)
	_card.visible = false
	_card.go.connect(func(t): Alerts.go(t))
	_card.dismissed.connect(func(): Alerts.dismiss_away())
	_stack.add_child(_card)
	place(false)


## In a game scene: HudLayout's "alerts" slot (bottom-right, growing up). On the front door:
## the gap between its two columns, from the top.
func place(front_door: bool) -> void:
	_front = front_door
	var w := FRONT_W if front_door else float(HudLayout.COL_W)
	if front_door:
		_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_stack.grow_vertical = Control.GROW_DIRECTION_END
		_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
		_stack.offset_left = 930 - 960 - w * 0.5
		_stack.offset_right = 930 - 960 + w * 0.5
		_stack.offset_top = 92
		_stack.offset_bottom = 92
	else:
		var s: Rect2 = HudLayout.slots()["alerts"]
		_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_stack.alignment = BoxContainer.ALIGNMENT_END
		_stack.offset_right = -HudLayout.MARGIN
		_stack.offset_left = -HudLayout.MARGIN - w
		_stack.offset_bottom = -(1080.0 - s.end.y)
		_stack.offset_top = -(1080.0 - s.end.y)
	_stack.custom_minimum_size = Vector2(w, 0)
	for id in _toasts:
		(_toasts[id]["node"] as Control).custom_minimum_size = Vector2(w, 0)
		(_toasts[id]["label"] as Label).custom_minimum_size = Vector2(w - 30, 0)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The compact card for `secs` seconds (the front door shows its own, full).
func show_card(card: Dictionary, secs: float) -> void:
	if _front:
		return
	_card.set_card("ready", card)
	_card.visible = true
	_card_until = _now() + secs
	_trim()


## While the notification panel is open the stack steps aside (the panel lists the same).
func set_hidden(on: bool) -> void:
	_stack.visible = not on
	if on:
		_card.visible = false


func hide_card() -> void:
	_card.visible = false


func card_visible() -> bool:
	return _card.visible


## Shows a new toast or updates a merged one (AlertGate's toast).
func show_toast(t: Dictionary) -> void:
	var id := int(t.get("id", 0))
	var until := _now() + AlertGate.LIFE_S
	if _toasts.has(id):
		var e: Dictionary = _toasts[id]
		e["label"].text = AlertGate.text_of(t)
		e["title"].text = _title(t)
		e["until"] = until
		(e["node"] as Control).modulate.a = 1.0
		return
	if _card.visible:
		_card.visible = false  # fresher news takes the slot; the card stays in the notifications (N)
	var kind := String(t.get("kind", ""))
	var col: Color = _color(kind)
	var p := AwayCard.Entry.new()
	var sb := DeepFieldTheme.accent_style(col, 0.92)
	sb.bg_color = Color(DeepFieldTheme.BLACK, 0.9)
	p.add_theme_stylebox_override("panel", sb)
	p.base = sb
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(col, 0.18)
	p.hover = hov
	var w := FRONT_W if _front else float(HudLayout.COL_W)
	p.custom_minimum_size = Vector2(w, 0)
	var go: Dictionary = t.get("go", {})
	p.clickable = true
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.clicked.connect(func():
		Alerts.go(_toasts[id]["go"] if _toasts.has(id) else go)
		_drop(id))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var title := Label.new()
	title.theme_type_variation = "MonoLabel"
	title.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	title.add_theme_color_override("font_color", col)
	title.text = _title(t)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w - 30, 0)
	l.text = AlertGate.text_of(t)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.max_lines_visible = 4
	v.add_child(l)
	_stack.add_child(p)
	_toasts[id] = {"node": p, "label": l, "title": title, "until": until, "go": go}
	_trim()
	p.modulate.a = 0.0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.2)


func _title(t: Dictionary) -> String:
	var n := int(t.get("count", 1))
	var parts: PackedStringArray = [AlertGate.title_of(String(t.get("kind", "")))]
	if n > 1:
		parts.append("×%d" % n)
	var items: Array = t.get("items", [])
	if not items.is_empty() and String(items[-1].get("note", "")) != "":
		parts.append(String(items[-1]["note"]))
	parts.append("%s notifications" % ControlsHelp.key_of("notifications"))
	return "  ·  ".join(parts)


static func _color(kind: String) -> Color:
	match kind:
		"mention": return Color("#ffd27a")
		"invite": return Color("#ffd27a")
		"arrive": return Color("#9fe8ff")
		"crown": return Color("#ff8fa0")
	return DeepFieldTheme.ICE


func _trim() -> void:
	var cap := 1 if _card.visible else MAX_TOASTS
	var ids: Array = _toasts.keys()
	ids.sort()
	while ids.size() > cap:
		_drop(ids.pop_front())


func _drop(id: int) -> void:
	if not _toasts.has(id):
		return
	var n: Control = _toasts[id]["node"]
	_toasts.erase(id)
	if is_instance_valid(n):
		n.queue_free()


func _process(_delta: float) -> void:
	var now := _now()
	for id in _toasts.keys():
		var e: Dictionary = _toasts[id]
		var left := float(e["until"]) - now
		if left <= 0.0:
			_drop(id)
		elif left < 1.0:
			(e["node"] as Control).modulate.a = left
	if _card.visible and _card_until > 0.0 and now > _card_until:
		_card.visible = false


func toast_count() -> int:
	return _toasts.size()
