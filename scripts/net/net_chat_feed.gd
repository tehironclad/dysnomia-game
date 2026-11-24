class_name NetChatFeed
extends VBoxContainer
## The HUD's free-chat feed (Net): the last few lines of chat in this
## territory, notices ("guests can't talk"…), a status line, and the say line
## (the `say` action) for free chat that is not on chain. Lines fade out.

const KEEP := 7
const LINE_S := 22.0

var status: Label
var _lines: VBoxContainer
var _line: LineEdit
var _talk: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(460, 0)
	add_theme_constant_override("separation", 2)
	theme = DeepFieldTheme.get_theme()
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 1)
	add_child(_lines)
	_line = LineEdit.new()
	_line.placeholder_text = "say (free, not on chain) · Enter to send · Esc to cancel"
	_line.max_length = NetProto.CHAT_MAX_CHARS
	_line.visible = false
	_line.text_submitted.connect(_submit)
	add_child(_line)
	_talk = Label.new()
	_talk.theme_type_variation = "MonoLabel"
	_talk.add_theme_font_size_override("font_size", 12)
	_talk.add_theme_color_override("font_color", Color(0.45, 1.0, 0.7))
	_talk.text = "◉ talking"
	_talk.visible = false
	add_child(_talk)
	status = Label.new()
	status.theme_type_variation = "MutedLabel"
	status.add_theme_font_size_override("font_size", 11)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)


func _ready() -> void:
	Net.chat_received.connect(func(w, n, t, _p): add_line(_who(w, n), t, DeepFieldTheme.ICE))
	Net.notice.connect(func(t): add_line("", t, Color("#ffd27a")))
	Net.speaking_changed.connect(func(on): _talk.visible = on)
	_refresh_status()
	Net.status_changed.connect(func(_s): _refresh_status())


static func _who(w: String, n: String) -> String:
	return n if n != "" else NetProto.short_wallet(w)


func add_line(who: String, text: String, col: Color) -> void:
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(460, 0)
	l.add_theme_color_override("font_color", col if who == "" else Color(0.9, 0.93, 0.98))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.text = text if who == "" else "%s: %s" % [who, text]
	l.set_meta("t", LINE_S)
	_lines.add_child(l)
	while _lines.get_child_count() > KEEP:
		_lines.get_child(0).free()


func open_input() -> void:
	if not Net.is_online():
		add_line("", "Offline: free chat needs the game server (F2 · Online & voice).", Color("#ffd27a"))
		return
	_line.visible = true
	_line.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func is_typing() -> bool:
	return _line.visible


func _submit(text: String) -> void:
	if text.strip_edges() != "":
		Net.send_chat(text)
	_close_input()


func _close_input() -> void:
	_line.text = ""
	_line.visible = false
	_line.release_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if _line.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_input()


func _refresh_status() -> void:
	status.text = Net.status_text() if Net.client and Net.client.status != "offline" else ""


var _st := 0.0


func _process(delta: float) -> void:
	_st += delta
	if _st > 1.0:
		_st = 0.0
		_refresh_status()
	for l in _lines.get_children():
		var t: float = float(l.get_meta("t")) - delta
		l.set_meta("t", t)
		l.modulate.a = clampf(t / 3.0, 0.0, 1.0)
		if t <= 0.0:
			l.queue_free()
