class_name LabelDeclutter
extends Node
## Keeps a set of billboard labels from piling up on screen (2026-11-24): the skyline's tower
## names over the Core read as one smear at mid range, 24 two-line labels overlapping. Each
## frame every tracked label's screen rectangle is estimated (its text box × its scale, through
## the camera); then, in priority order (the board's rank: #1 first), a label shows only if its
## rectangle doesn't overlap one already shown. The rest fade out, and fade back in as soon as
## there is room (moving closer, or round to a side where they spread out).
##
## What the towers are never changes: only which names are drawn, from where the camera is.
## A shown label keeps its place a little longer than a hidden one needs to come back
## (KEEP_SHRINK / ENTER_GROW), so labels don't flicker at the edge.

const FADE_S := 0.22       ## seconds to fade in or out
const PAD_PX := 6.0        ## clear space around each label
const KEEP_SHRINK := 0.85  ## a shown label claims this share of its box…
const ENTER_GROW := 1.1    ## …a hidden one needs this much room to come back
const MIN_PX := LegibleLabels.MIN_PX
const MAX_SCALE := LegibleLabels.MAX_SCALE

var _items: Array = []  ## [Label3D, priority, alpha, modulate alpha, outline alpha, shown]
var hidden_now := 0     ## labels held back this frame (tests and perf notes)


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--no-declutter"):
		set_process(false)  # before/after shots: every label drawn


## Track a label; lower `priority` wins (0 = most important).
func track(l: Label3D, priority: int) -> void:
	for it in _items:
		if it[0] == l:
			it[1] = priority
			return
	_items.append([l, priority, 1.0, l.modulate.a, l.outline_modulate.a, true])


func untrack(l: Label3D) -> void:
	for i in _items.size():
		if _items[i][0] == l:
			_items.remove_at(i)
			return


## Pure: given rectangles in priority order and whether each is showing now, which show next.
## A rectangle with no area (behind the camera, out of range) never shows and claims nothing.
static func resolve(rects: Array, shown: Array, pad: float = PAD_PX) -> Array:
	var out: Array = []
	var taken: Array[Rect2] = []
	for i in rects.size():
		var r: Rect2 = rects[i]
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			out.append(false)
			continue
		var test := _scaled(r, KEEP_SHRINK if bool(shown[i]) else ENTER_GROW).grow(pad * 0.5)
		var free := true
		for t in taken:
			if t.intersects(test):
				free = false
				break
		out.append(free)
		if free:
			taken.append(_scaled(r, KEEP_SHRINK).grow(pad * 0.5))
	return out


static func _scaled(r: Rect2, k: float) -> Rect2:
	var c := r.get_center()
	var s := r.size * k
	return Rect2(c - s * 0.5, s)


## The label's box on screen (pixels), or an empty Rect2 when it isn't drawn from here.
## Uses the scale LegibleLabels would give it at this distance (the same formula), so a
## faded-out label (scale not updated) still measures right.
static func screen_rect(l: Label3D, cam: Camera3D, focal: float) -> Rect2:
	var at := l.global_position
	if cam.is_position_behind(at):
		return Rect2()
	var d := cam.global_position.distance_to(at)
	if l.visibility_range_end > 0.0 and d > l.visibility_range_end:
		return Rect2()
	var box := l.get_aabb()  # local, unscaled (the text's extent in metres)
	var base := l.get_parent_node_3d().global_transform.basis.get_scale().x if l.get_parent_node_3d() else 1.0
	var em := l.font_size * l.pixel_size * base
	var s := base * LegibleLabels.scale_for(em, d, focal)
	var depth := maxf(0.01, -(cam.global_transform.affine_inverse() * at).z)
	var px := focal / depth * s
	var c := cam.unproject_position(at) + Vector2(box.get_center().x, -box.get_center().y) * px
	var size := Vector2(box.size.x, box.size.y) * px
	return Rect2(c - size * 0.5, size)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _items.is_empty():
		return
	var h := get_viewport().get_visible_rect().size.y
	var focal := h * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
	var i := _items.size() - 1
	while i >= 0:
		if not is_instance_valid(_items[i][0]):
			_items.remove_at(i)
		i -= 1
	_items.sort_custom(func(a, b): return a[1] < b[1])
	var rects: Array = []
	var shown: Array = []
	for it in _items:
		var l: Label3D = it[0]
		var on := l.is_inside_tree() and l.get_parent_node_3d() != null and l.get_parent_node_3d().is_visible_in_tree()
		rects.append(screen_rect(l, cam, focal) if on else Rect2())
		shown.append(it[5])
	var show := resolve(rects, shown)
	hidden_now = 0
	var step := delta / FADE_S
	for j in _items.size():
		var it: Array = _items[j]
		var l: Label3D = it[0]
		it[5] = show[j]
		if not show[j]:
			hidden_now += 1
		var a: float = move_toward(float(it[2]), 1.0 if show[j] else 0.0, step)
		if is_equal_approx(a, float(it[2])) and l.visible == (a > 0.0):
			continue
		it[2] = a
		l.modulate.a = float(it[3]) * a
		l.outline_modulate.a = float(it[4]) * a
		l.visible = a > 0.0
