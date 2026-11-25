class_name SubtitleBar
extends PanelContainer
## One spoken line at the bottom of the screen: "SUNNY  Here you go. Enjoy." on a dark band, for
## `seconds`, then it fades. Subtitles always show, voiced or not (VoiceLines).

var _who: Label
var _words: Label
var _t := 0.0
var hold := false  ## previews: the line stays


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DeepFieldTheme.BLACK, 0.82)
	sb.border_color = Color(1.0, 0.8, 0.45, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_who = Label.new()
	_who.theme_type_variation = "DisplayLabel"
	_who.add_theme_font_size_override("font_size", 18)
	_who.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	_who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_who)
	_words = Label.new()
	_words.add_theme_font_size_override("font_size", 21)
	_words.add_theme_color_override("font_color", DeepFieldTheme.INK)
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.custom_minimum_size = Vector2(0, 0)
	row.add_child(_words)
	visible = false


func show_line(who: String, words: String, seconds: float) -> void:
	_who.text = who.to_upper()
	_words.text = words
	# Long lines wrap at ~900 px; short ones keep the band snug.
	_words.custom_minimum_size.x = minf(900.0, 11.0 * words.length())
	_t = seconds
	modulate.a = 1.0
	visible = words != ""
	reset_size()
	_place()


## Centred, BOTTOM px above the screen's bottom edge (clear of a controls strip).
const BOTTOM := 78.0


func _place() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	position = Vector2(roundf((vp.x - size.x) * 0.5), vp.y - BOTTOM - size.y)


func clear() -> void:
	_t = 0.0
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_place()  # the window may have been resized; the wrapped text may have grown
	if hold:
		return
	_t -= delta
	modulate.a = clampf(_t / 0.6, 0.0, 1.0)
	if _t <= 0.0:
		visible = false
