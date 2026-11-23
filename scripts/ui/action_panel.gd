class_name ActionPanel
extends PanelContainer
## The one modal for a live move (WP 5.1+): title, preview (simulated from the
## wallet, with its block), a primary button that signs, and the write's
## stages as they happen (simulate → sign → pending → confirmed / failed).
## The panel never claims success; the caller decides after the receipt and
## the re-read.

signal closed

var _title: Label
var _body: Label
var _status: Label
var _primary: Button
var _close: Button
var _action: Callable
var _label := ""


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.95  # a modal over the 3D scene: readable first
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 0)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.add_theme_font_size_override("font_size", 18)
	col.add_child(_title)
	_body = Label.new()
	_body.theme_type_variation = "MonoLabel"
	_body.add_theme_font_size_override("font_size", 13)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(520, 0)
	col.add_child(_body)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	col.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_primary = Button.new()
	_primary.custom_minimum_size = Vector2(220, 40)
	_primary.pressed.connect(func(): if _action.is_valid(): _action.call())
	row.add_child(_primary)
	_close = Button.new()
	_close.text = "Close (Esc)"
	_close.pressed.connect(close)
	row.add_child(_close)


func _ready() -> void:
	Wallet.tx_stage.connect(_on_stage)


func show_panel(title: String, body: String = "Simulating from your wallet…") -> void:
	_title.text = title
	_body.text = body
	_status.text = ""
	_status.remove_theme_color_override("font_color")
	set_primary("", false, Callable())
	_label = ""
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func set_body(text: String) -> void:
	_body.text = text


func set_status(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	_status.text = text
	if color.a > 0.0:
		_status.add_theme_color_override("font_color", color)
	else:
		_status.remove_theme_color_override("font_color")


## An empty `text` hides the button.
func set_primary(text: String, enabled: bool, action: Callable) -> void:
	_primary.visible = text != ""
	_primary.text = text
	_primary.disabled = not enabled
	_action = action


## Follow this Wallet.send label's stages in the status line.
func track(label: String) -> void:
	_label = label


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if not visible or label != _label:
		return
	match stage:
		"simulate":
			set_status("1/4  Simulating again from your wallet…")
		"sign":
			set_status("2/4  Waiting for your signature in the browser wallet…", DeepFieldTheme.ICE)
		"pending":
			set_status("3/4  Sent %s. Waiting for the receipt from the chain…" % String(info.get("hash", "")), DeepFieldTheme.ICE)
		"confirmed":
			set_status("4/4  Receipt: mined in block %d, status 1. Re-reading state…" % int(info.get("block", -1)), Color("#64e3a8"))
		"failed":
			set_status("Stopped at %s: %s" % [String(info.get("stage", "?")), String(info.get("message", ""))], Color("#ff8fa0"))


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
