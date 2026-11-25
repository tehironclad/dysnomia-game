class_name LoadingCover
extends CanvasLayer
## A plain cover while a territory builds in stages when no warp brought the player
## there (back from the Field, out of a building's door). Dark, a line naming what is
## being built, a thin bar; it fades once the world is built (and its first frames have
## compiled their pipelines). Cheap to draw: no shader, so it doesn't slow the build.

const HOLD_FRAMES := 6
const FADE_S := 0.4

var _rect: ColorRect
var _label: Label
var _bar: ProgressBar
var _done := false
var _hold := 0
var _fade := 0.0


func _init() -> void:
	layer = 99  # under the warp (100) and a door's fade (120)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.012, 0.016, 0.03, 1.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_label = Label.new()
	_label.theme = DeepFieldTheme.get_theme()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.position = Vector2(-300, -24)
	_label.size = Vector2(600, 30)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", DeepFieldTheme.INK)
	_label.add_theme_font_size_override("font_size", DeepFieldTheme.FS_BODY)
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.set_anchors_preset(Control.PRESET_CENTER)
	_bar.position = Vector2(-160, 14)
	_bar.size = Vector2(320, 4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	var fg := StyleBoxFlat.new()
	fg.bg_color = DeepFieldTheme.ICE
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fg)
	add_child(_bar)


## Follows a territory scene's build (signals build_progress and built).
func follow(scene: Node, place_name: String) -> void:
	_label.text = place_name
	scene.build_progress.connect(func(f: float, text: String):
		_bar.value = maxf(_bar.value, f)
		_label.text = "%s · %s" % [place_name, text] if place_name != "" else text)
	scene.built.connect(func(): _done = true)
	scene.tree_exiting.connect(queue_free)


func _process(delta: float) -> void:
	if not _done:
		return
	if _hold < HOLD_FRAMES:
		_hold += 1
		return
	_fade += delta / FADE_S
	var a := clampf(1.0 - _fade, 0.0, 1.0)
	_rect.color.a = a
	_label.modulate.a = a
	_bar.modulate.a = a
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _fade >= 1.0:
		queue_free()
