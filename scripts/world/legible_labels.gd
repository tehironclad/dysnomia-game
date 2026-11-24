class_name LegibleLabels
extends Node
## Keeps the territory's billboard labels (tower names, the Core's title, the wells, the Steward,
## chat markers) readable from afar (2026-11-24): a label grows with its distance from the camera
## so its letters stay at least MIN_PX tall on screen, up to MAX_SCALE × its own size; past the
## distance where even that is too small it ends (a visibility range) instead of smearing into
## an unreadable row of glyphs over the skyline. Signs fixed to a wall (billboard
## off) keep their size: they belong to their building. The same for every viewer: only the
## camera's distance matters.

const MIN_PX := 14.0  ## the em: numerals and lower case are about 0.7 of it
const MAX_SCALE := 4.0
const FAR_MIN_M := 40.0
const FAR_MAX_M := 900.0
const FOCAL_REF := 620.0  ## px: 720p at a 60° FOV (the range is set once; bigger screens read further)

var _items: Array = []  ## [Label3D, its own scale]
var _roots: Array[Node] = []


func _ready() -> void:
	get_tree().node_added.connect(_on_added)


func watch(root: Node) -> void:
	if root and not _roots.has(root):
		_roots.append(root)
		for l in root.find_children("*", "Label3D", true, false):
			_add(l)


## Pure: the scale that keeps a label of `em` metres (font_size × pixel_size) at least MIN_PX
## tall at distance `d` for a camera of focal length `focal_px`.
static func scale_for(em: float, d: float, focal_px: float) -> float:
	if em <= 0.0 or focal_px <= 0.0:
		return 1.0
	var px := em * focal_px / maxf(d, 0.01)
	return clampf(MIN_PX / px, 1.0, MAX_SCALE)


## Pure: where a label of `em` metres stops being readable even at MAX_SCALE.
static func far_for(em: float) -> float:
	return clampf(em * MAX_SCALE * FOCAL_REF / MIN_PX, FAR_MIN_M, FAR_MAX_M)


func _on_added(n: Node) -> void:
	if n is Label3D:
		for r in _roots:
			if is_instance_valid(r) and r.is_ancestor_of(n):
				_add.call_deferred(n)
				return


func _add(l: Label3D) -> void:
	if not is_instance_valid(l) or l.fixed_size or l.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
		return
	# Overlays that animate their own scale (chat bubbles, score pop-ups) are left alone.
	if l.no_depth_test or l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return
	for it in _items:
		if it[0] == l:
			return
	if l.visibility_range_end <= 0.0:
		l.visibility_range_end = far_for(l.font_size * l.pixel_size * l.scale.x)
		l.visibility_range_end_margin = l.visibility_range_end * 0.05
	_items.append([l, l.scale.x])


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _items.is_empty():
		return
	var h := get_viewport().get_visible_rect().size.y
	var focal := h * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
	var at := cam.global_position
	var i := _items.size() - 1
	while i >= 0:
		var it: Array = _items[i]
		var l: Label3D = it[0] if is_instance_valid(it[0]) else null
		if l == null or not l.is_inside_tree():
			if l == null:
				_items.remove_at(i)
			i -= 1
			continue
		if l.is_visible_in_tree():
			var base: float = it[1]
			var s := scale_for(l.font_size * l.pixel_size * base, at.distance_to(l.global_position), focal)
			l.scale = Vector3.ONE * base * s
		i -= 1
