extends Control
## Animated tutorial arrow that points toward a world position (projected to screen)
## or a UI element. Bobs up and down to draw the player's attention.
## Used by TutorialSystem to highlight targets.

const ARROW_SIZE: float = 24.0
const BOB_SPEED: float = 3.0
const BOB_AMOUNT: float = 8.0
const ARROW_COLOR: Color = Color(1.0, 0.85, 0.3, 0.9)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.6)

var _target_pos: Vector2 = Vector2.ZERO
var _visible_arrow: bool = false
var _anim_time: float = 0.0
var _point_down: bool = true  # true = arrow points downward at target


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100


func show_at(screen_pos: Vector2, point_down_val: bool = true) -> void:
	_target_pos = screen_pos
	_point_down = point_down_val
	_visible_arrow = true
	visible = true


func hide_arrow() -> void:
	_visible_arrow = false
	visible = false


func _process(delta: float) -> void:
	if _visible_arrow:
		_anim_time += delta
		queue_redraw()


func _draw() -> void:
	if not _visible_arrow:
		return

	var bob_offset := sin(_anim_time * BOB_SPEED) * BOB_AMOUNT
	var tip := _target_pos
	var base_offset := ARROW_SIZE * 2.0 + bob_offset

	if _point_down:
		# Arrow above target, pointing down
		tip = _target_pos
		var left := tip + Vector2(-ARROW_SIZE * 0.6, -base_offset)
		var right := tip + Vector2(ARROW_SIZE * 0.6, -base_offset)
		var center_top := tip + Vector2(0.0, -base_offset - ARROW_SIZE * 0.3)
		# Outline
		draw_colored_polygon(
			PackedVector2Array([tip, left, center_top, right]),
			OUTLINE_COLOR
		)
		# Inner arrow (slightly smaller)
		var inset := 3.0
		var tip_in := tip + Vector2(0.0, -inset)
		var left_in := left + Vector2(inset, inset)
		var right_in := right + Vector2(-inset, inset)
		var center_in := center_top + Vector2(0.0, inset)
		draw_colored_polygon(
			PackedVector2Array([tip_in, left_in, center_in, right_in]),
			ARROW_COLOR
		)
	else:
		# Arrow below target, pointing up
		tip = _target_pos
		var left := tip + Vector2(-ARROW_SIZE * 0.6, base_offset)
		var right := tip + Vector2(ARROW_SIZE * 0.6, base_offset)
		var center_bot := tip + Vector2(0.0, base_offset + ARROW_SIZE * 0.3)
		draw_colored_polygon(
			PackedVector2Array([tip, left, center_bot, right]),
			OUTLINE_COLOR
		)
		var inset := 3.0
		var tip_in := tip + Vector2(0.0, inset)
		var left_in := left + Vector2(inset, -inset)
		var right_in := right + Vector2(-inset, -inset)
		var center_in := center_bot + Vector2(0.0, -inset)
		draw_colored_polygon(
			PackedVector2Array([tip_in, left_in, center_in, right_in]),
			ARROW_COLOR
		)
