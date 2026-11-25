class_name HeadBadge
extends Control
## A speaker's face in the 2D UI: their avatar head (HeadIcons) on a disc in
## their colour, with a thin ring. `pulse()` rings it once (a new line).

var kind := "bear"
var color := DeepFieldTheme.ICE
var _tex: Texture2D
var _pulse := 0.0


func _init(p_kind: String = "bear", p_color: Color = DeepFieldTheme.ICE, px: float = 34.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_face(p_kind, p_color)


func set_face(p_kind: String, p_color: Color) -> void:
	kind = p_kind
	color = p_color
	_tex = HeadIcons.texture(kind)
	queue_redraw()


func pulse() -> void:
	_pulse = 1.0
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 0.8)
	queue_redraw()
	if _pulse <= 0.0:
		set_process(false)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(s, s) * 0.5
	var r := s * 0.5
	draw_circle(c, r, Color(color.darkened(0.55), 0.85))
	if _tex:
		var inset := s * 0.04
		draw_texture_rect(_tex, Rect2(Vector2(inset, inset - s * 0.04), Vector2(s - inset * 2.0, s - inset * 2.0)), false)
	draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(color, 0.75 + 0.25 * _pulse), 1.5 + 2.0 * _pulse, true)
	if _pulse > 0.0:
		draw_arc(c, r + 3.0 * (1.0 - _pulse) + 1.0, 0.0, TAU, 40, Color(color, _pulse * 0.8), 2.0, true)
