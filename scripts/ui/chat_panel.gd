class_name ChatPanel
extends PanelContainer
## A chat board (WP 5.3 rooms, 5.4 the Void): lines read from chain logs, each
## with its block; ✓ OG / ⚠ imposter badges from the speaker's Aura; a line
## editor that posts through Wallet.send (simulate → sign → verify), or the
## reason posting is not possible.

signal closed
signal post_requested(text: String)

const MAX_LEN := 280

var _title: Label
var _sub: Label
var _list: RichTextLabel
var _edit: LineEdit
var _send: Button
var _reason: Label
var _status: Label
var _label := ""
var lines: Array = []


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 1.0  # a modal over the 3D scene: readable first (the glowing board showed through 0.95)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(640, 460)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.add_theme_font_size_override("font_size", DeepFieldTheme.FS_LEAD)
	col.add_child(_title)
	_sub = Label.new()
	_sub.theme_type_variation = "MutedLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(600, 0)
	col.add_child(_sub)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.scroll_following = true
	_list.custom_minimum_size = Vector2(600, 280)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
	_list.add_theme_font_size_override("normal_font_size", DeepFieldTheme.FS_CAPTION)
	col.add_child(_list)
	_reason = Label.new()
	_reason.theme_type_variation = "MutedLabel"
	_reason.add_theme_color_override("font_color", Color("#ffd27a"))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(600, 0)
	col.add_child(_reason)
	var row := HBoxContainer.new()
	col.add_child(row)
	_edit = LineEdit.new()
	_edit.max_length = MAX_LEN
	_edit.placeholder_text = "a line, written on chain forever"
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_submitted.connect(func(_t): _on_send())
	row.add_child(_edit)
	_send = Button.new()
	_send.text = "Post"
	_send.pressed.connect(_on_send)
	row.add_child(_send)
	var close_btn := Button.new()
	close_btn.text = "Close (Esc)"
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	col.add_child(_status)


func _ready() -> void:
	Wallet.tx_stage.connect(_on_stage)


func show_panel(title: String, subtitle: String) -> void:
	_title.text = title
	_sub.text = subtitle
	_status.text = ""
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func set_subtitle(text: String) -> void:
	_sub.text = text


## "" enables posting; otherwise the reason is shown and Post is disabled.
func set_blocker(reason: String) -> void:
	_reason.text = reason
	_reason.visible = reason != ""
	_send.disabled = reason != ""
	_edit.editable = reason == ""


func set_status(text: String) -> void:
	_status.text = text


func set_lines(p_lines: Array, note: String = "") -> void:
	lines = p_lines.duplicate()
	_render(note)


func append_lines(more: Array) -> void:
	var seen := {}
	for l in lines:
		seen["%s:%d" % [l["tx"], l["log_index"]]] = true
	for l in more:
		if not seen.has("%s:%d" % [l["tx"], l["log_index"]]):
			lines.append(l)
	_render("")


func _render(note: String) -> void:
	_list.clear()
	if note != "":
		_list.append_text("[color=#5d6578]%s[/color]\n" % _esc(note))
	if lines.is_empty():
		_list.append_text("[color=#5d6578](no lines in the scanned range)[/color]")
		return
	for l in lines:
		var badge := ""
		if l.get("badge", "") == "og":
			badge = " [color=#64e3a8]✓ OG[/color]"
		elif l.get("badge", "") == "imposter":
			badge = " [color=#ff8fa0]⚠ imposter[/color]"
		var nm: String = l["name"] if l["name"] != "" else "?"
		_list.append_text("[color=#5d6578]%d[/color]  [color=#a8e6ff]%s[/color]%s  %s\n" % [l["block"], _esc(nm), badge, _esc(l["text"])])


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _on_send() -> void:
	var t := _edit.text.strip_edges()
	if t == "" or _send.disabled:
		return
	post_requested.emit(t)


## Called by the owner once a post is confirmed.
func clear_input() -> void:
	_edit.text = ""


func track(label: String) -> void:
	_label = label


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if not visible or label != _label:
		return
	match stage:
		"simulate": set_status("Simulating the post from your wallet…")
		"sign": set_status("Waiting for your signature in the browser wallet…")
		"pending": set_status("Sent %s · waiting for the receipt…" % String(info.get("hash", "")))
		"confirmed": set_status("Mined in block %d. Reading the new line back from the chain…" % int(info.get("block", -1)))
		"failed": set_status("Not posted (%s): %s" % [String(info.get("stage", "?")), String(info.get("message", ""))])


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
