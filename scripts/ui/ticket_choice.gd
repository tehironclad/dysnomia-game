class_name TicketChoice
extends PanelContainer
## What to buy at a stall or cabinet: one play, or a ticket strip (one approval, gas once), with
## the prices from Prices. Opened over everything like AccessSteps.popup (mouse visible; Esc or
## Cancel closes and restores the mouse). It only chooses: the caller pays through ArcadePay.buy.
##   TicketChoice.popup(self, "ENTROPY TOSS · buy a ticket", "why", [
##       {"text": Prices.play_button(), "note": "…", "do": func(): _buy(…)}, …])

signal closed
signal chosen(index: int)

static var _ref: WeakRef = null

var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _col: VBoxContainer
var buttons: Array[Button] = []


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(Color(1.0, 0.82, 0.48, 0.55))
	sb.bg_color.a = 0.97
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 10)
	add_child(_col)


func _label(text: String, variation: String, size: int, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.text = text
	_col.add_child(l)
	return l


## options: [{text, note?, do: Callable, disabled?}]
func fill(title: String, subtitle: String, options: Array) -> void:
	_label(title, "DisplayLabel", 22, Color(1.0, 0.82, 0.48))
	if subtitle != "":
		_label(subtitle, "MutedLabel", 14)
	for i in options.size():
		var o: Dictionary = options[i]
		var b := Button.new()
		b.text = String(o["text"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(520, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.disabled = bool(o.get("disabled", false))
		b.focus_mode = Control.FOCUS_NONE  # a click buys, never a stray Space/Enter
		var cb: Callable = o.get("do", Callable())
		b.pressed.connect(func():
			chosen.emit(i)
			close()
			if cb.is_valid():
				cb.call())
		_col.add_child(b)
		buttons.append(b)
		if String(o.get("note", "")) != "":
			var n := _label(String(o["note"]), "MutedLabel", 13)
			n.custom_minimum_size = Vector2(500, 0)
	var cancel := Button.new()
	cancel.text = "Not now (Esc)"
	cancel.pressed.connect(close)
	_col.add_child(cancel)


static func popup(host: Node, title: String, subtitle: String, options: Array) -> TicketChoice:
	close_popup()
	var layer := CanvasLayer.new()
	layer.layer = 94
	layer.name = "TicketChoiceLayer"
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var p := TicketChoice.new()
	p._prev_mouse = Input.mouse_mode
	p.fill(title, subtitle, options)
	center.add_child(p)
	host.add_child(layer)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	p.closed.connect(func():
		layer.queue_free())
	_ref = weakref(p)
	return p


static func close_popup() -> void:
	var p := current()
	if p != null:
		p.close()
	_ref = null


static func current() -> TicketChoice:
	if _ref == null:
		return null
	var p = _ref.get_ref()
	return p if p != null and is_instance_valid(p) and p.visible else null


func close() -> void:
	if not visible:
		return
	visible = false
	Input.set_mouse_mode(_prev_mouse)
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
