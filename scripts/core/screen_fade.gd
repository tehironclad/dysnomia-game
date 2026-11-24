class_name ScreenFade
extends CanvasLayer
## A black veil over everything, kept on the tree's root so it survives a scene
## change (a door's fade to black carries into the next place's fade in).
## It never traps the screen: if nobody has set it for HOLD_S it fades itself
## out (a scene that failed to load, an arrival that never ran).

const HOLD_S := 0.9

var _rect: ColorRect
var _alpha := 0.0
var _touched_ms := 0


## The tree's veil (made on first use).
static func of(tree: SceneTree) -> ScreenFade:
	var n := tree.root.get_node_or_null("ScreenFade")
	if n is ScreenFade:
		return n
	var f := ScreenFade.new()
	f.name = "ScreenFade"
	tree.root.add_child(f)
	return f


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	visible = false


## 0 clear … 1 black.
func set_alpha(a: float) -> void:
	_alpha = clampf(a, 0.0, 1.0)
	_touched_ms = Time.get_ticks_msec()
	_rect.color.a = _alpha
	visible = _alpha > 0.001


func alpha() -> float:
	return _alpha


func _process(delta: float) -> void:
	if _alpha <= 0.0:
		return
	if Time.get_ticks_msec() - _touched_ms > int(HOLD_S * 1000.0):
		_alpha = maxf(0.0, _alpha - minf(delta, 0.05) * 2.5)
		_rect.color.a = _alpha
		visible = _alpha > 0.001
