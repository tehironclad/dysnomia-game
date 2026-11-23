class_name BoardPostUI
extends CanvasLayer
## Posting form for a media board: caption + image link, shows the exact cost and what
## goes on-chain. Keeper gets "Take down"; anyone can "Hide for me".

signal submitted(caption: String, url: String)
signal take_down_requested(post: Dictionary)
signal mute_requested(post: Dictionary)
signal closed

const ACCENT := Color(0.95, 0.42, 0.72)
const PULSE := Color(0.62, 0.42, 1.0)

var _panel: PanelContainer
var _title: Label
var _cost: Label
var _caption: LineEdit
var _url: LineEdit
var _preview: Label
var _status: Label
var _post_btn: Button
var _down_btn: Button
var _mute_btn: Button
var _current: Dictionary = {}
var _prev_mouse: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 22
	_build()
	_panel.visible = false


func is_open() -> bool:
	return _panel.visible


func open(board_title: String, cost_line: String, current_post: Dictionary, is_keeper: bool) -> void:
	_current = current_post
	_title.text = "%s BOARD — post for 24 h" % board_title.to_upper()
	_cost.text = cost_line
	_caption.text = ""
	_url.text = ""
	_status.text = ""
	_down_btn.visible = is_keeper and not current_post.is_empty() and not current_post.get("pending", false)
	_mute_btn.visible = not current_post.is_empty() and not current_post.get("pending", false)
	_update_preview()
	_panel.visible = true
	_prev_mouse = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_caption.grab_focus()


func close() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	Input.set_mouse_mode(_prev_mouse if _prev_mouse != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED)
	closed.emit()


func set_status(text: String, color: Color = Color(0.8, 0.8, 0.88)) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _input(event: InputEvent) -> void:
	if _panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _update_preview(_t: String = "") -> void:
	var url := _url.text.strip_edges()
	var ok := BoardFeed.valid_image_url(url)
	_preview.text = "On-chain line: " + BoardFeed.format_post("…", "0x<payment>", _caption.text, url).left(160)
	_post_btn.disabled = _caption.text.strip_edges().is_empty() or not ok
	if not ok:
		set_status("Image link must start with https:// (PNG, JPG or WebP, under 2 MB)", Color(1, 0.6, 0.4))
	elif _status.text.begins_with("Image link"):
		set_status("")


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.08, 0.94)
	sb.border_color = ACCENT
	sb.border_width_left = 4
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -190
	_panel.offset_bottom = 190
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	_title = _lbl("", 20, Color.WHITE)
	v.add_child(_title)
	_cost = _lbl("", 14, Color(1, 0.88, 0.95))
	v.add_child(_cost)
	v.add_child(_lbl("Caption", 13, Color(0.75, 0.75, 0.82)))
	_caption = LineEdit.new()
	_caption.max_length = BoardFeed.MAX_CAPTION
	_caption.placeholder_text = "gm from the fair! Rocket launches at dusk"
	_caption.text_changed.connect(_update_preview)
	v.add_child(_caption)
	v.add_child(_lbl("Image link (optional)", 13, Color(0.75, 0.75, 0.82)))
	_url = LineEdit.new()
	_url.max_length = BoardFeed.MAX_URL
	_url.placeholder_text = "https://…/picture.png"
	_url.text_changed.connect(_update_preview)
	v.add_child(_url)
	_preview = _lbl("", 11, Color(0.6, 0.62, 0.72))
	v.add_child(_preview)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_post_btn = Button.new()
	_post_btn.text = "Pay 1 AFFECTION & post"
	_post_btn.pressed.connect(func() -> void:
		submitted.emit(_caption.text.strip_edges(), _url.text.strip_edges()))
	row.add_child(_post_btn)
	_down_btn = Button.new()
	_down_btn.text = "Take down current post (keeper)"
	_down_btn.pressed.connect(func() -> void: take_down_requested.emit(_current))
	row.add_child(_down_btn)
	_mute_btn = Button.new()
	_mute_btn.text = "Hide current post for me"
	_mute_btn.pressed.connect(func() -> void:
		mute_requested.emit(_current)
		close())
	row.add_child(_mute_btn)
	var cancel := Button.new()
	cancel.text = "Close (Esc)"
	cancel.pressed.connect(close)
	row.add_child(cancel)
	v.add_child(row)
	_status = _lbl("", 13, Color(0.8, 0.8, 0.88))
	v.add_child(_status)


func _lbl(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
