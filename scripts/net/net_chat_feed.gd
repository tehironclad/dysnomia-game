class_name NetChatFeed
extends VBoxContainer
## The HUD's online line (Net): the game server's status, its notices
## ("guests can't talk", "signed in"…) and the talking mark while push-to-talk
## is held. Free chat itself goes through the QING chat bar (ChatFeed: T, Tab
## for "say"), whose feed shows Net.chat_received lines. Notices fade out.

const KEEP := 4
const LINE_S := 14.0

var status: Label
var _lines: VBoxContainer
var _talk: Label
var _st := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(460, 0)
	add_theme_constant_override("separation", 2)
	theme = DeepFieldTheme.get_theme()
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)
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
	Net.notice.connect(func(t): add_line(t, Color("#ffd27a")))
	Net.speaking_changed.connect(func(on): _talk.visible = on)
	Net.status_changed.connect(func(_s): _refresh_status())
	_refresh_status()


func add_line(text: String, col: Color) -> void:
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(460, 0)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.text = text
	l.set_meta("t", LINE_S)
	_lines.add_child(l)
	while _lines.get_child_count() > KEEP:
		_lines.get_child(0).free()


func _refresh_status() -> void:
	status.text = Net.status_text() if Net.client and Net.client.status != "offline" else ""


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
