class_name DetailCull
extends Node
## Screen-size culling for the territory's props (perf, 2026-11-24). Every
## GeometryInstance3D under a watched root gets a visibility range that ends where
## it would cover only a few pixels: end = K × its world size (K from the quality
## level), never under MIN_END. Big things (towers, the terrain, the Burj) are left
## alone, so is anything that already has its own range, and anything under a
## skipped node (state-sized geometry: the skyline towers, development). Tiny props
## also stop casting shadows. Nodes added later (fair visitors, rides at a higher
## tier, chat bubbles) are handled as they enter the tree.
##
## The range depends only on the camera's distance, never on who is looking.

## K per quality level (Potato … Ultra): with a 60° FOV a prop of size s metres is
## ≈ 620·s/d pixels tall at 720p, so K = 250 ends it at ≈ 2.5 px.
const K_BY_QUALITY := [110.0, 140.0, 190.0, 240.0, 400.0]
## Shadow LOD: a prop casts into the sun's shadow maps only while the camera is within
## SHADOW_K × its size (a 2 m prop: 40 m at High, a 5 m stall wall 100 m). Past that its shadow is a few pixels, but it
## would still be drawn once per cascade; the fair behind you at the Core was ~900 casters.
const SHADOW_K_BY_QUALITY := [12.0, 15.0, 16.0, 20.0, 50.0]
const SHADOW_CHUNK := 300     ## casters re-checked per frame
const MIN_END := 24.0
const SKIP_SIZE := 24.0       ## a prop this big (m) or bigger is never culled by size
const NO_SHADOW_SIZE := 1.2   ## props smaller than this cast no shadow (bulbs, prizes, crates, heads:
                              ## their shadows are a few pixels; each caster is redrawn per cascade)
const META := "dc_size"

var _roots: Array[Node] = []
var _skip: Array[Node] = []
var _pending: Array[GeometryInstance3D] = []
var _retry: Array[GeometryInstance3D] = []
var _retry_t := 0.0
var _casters: Array = []      ## [GeometryInstance3D, size, its own shadow setting, on now]
var _caster_i := 0
var _shadow_k := 40.0
var _k := 240.0
var culled := 0  ## instances with a range set (for perf notes)


func _ready() -> void:
	_k = _k_now()
	_shadow_k = _shadow_k_now()
	get_tree().node_added.connect(_on_added)
	var cfg := get_node_or_null("/root/Config")
	if cfg and cfg.has_signal("applied"):
		cfg.applied.connect(_on_quality)


## Cull under `root` (now and for nodes added later).
func watch(root: Node) -> void:
	if root and not _roots.has(root):
		_roots.append(root)
		_scan(root)


## Never touch anything under `node` (its size follows state).
func skip(node: Node) -> void:
	if node and not _skip.has(node):
		_skip.append(node)


func _shadow_k_now() -> float:
	var cfg := get_node_or_null("/root/Config")
	var q: int = int(cfg.graphics_quality) if cfg else 2
	return SHADOW_K_BY_QUALITY[clampi(q, 0, SHADOW_K_BY_QUALITY.size() - 1)]


func _k_now() -> float:
	var cfg := get_node_or_null("/root/Config")
	var q: int = int(cfg.graphics_quality) if cfg else 2
	return K_BY_QUALITY[clampi(q, 0, K_BY_QUALITY.size() - 1)]


func _scan(n: Node) -> void:
	if _skip.has(n):
		return
	if n is GeometryInstance3D:
		_queue(n)
	for c in n.get_children():
		_scan(c)


func _on_added(n: Node) -> void:
	if n is GeometryInstance3D and _covered(n):
		_queue(n)


func _covered(n: Node) -> bool:
	for s in _skip:
		if is_instance_valid(s) and (s == n or s.is_ancestor_of(n)):
			return false
	for r in _roots:
		if is_instance_valid(r) and r.is_ancestor_of(n):
			return true
	return false


func _queue(gi: GeometryInstance3D) -> void:
	if _pending.is_empty():
		_flush.call_deferred()
	_pending.append(gi)


func _flush() -> void:
	var list := _pending
	_pending = []
	for gi in list:
		if is_instance_valid(gi) and gi.is_inside_tree():
			_apply(gi)


func _process(delta: float) -> void:
	_update_shadows()
	if _retry.is_empty():
		return
	_retry_t += delta
	if _retry_t < 1.5:
		return
	_retry_t = 0.0
	var list := _retry
	_retry = []
	for gi in list:
		if is_instance_valid(gi) and gi.is_inside_tree():
			_apply(gi, true)


## World size of an instance (its AABB's diagonal), or -1 if it can't be judged yet.
static func world_size(gi: GeometryInstance3D) -> float:
	var b := gi.global_transform.basis
	var s := b.get_scale()
	if minf(absf(s.x), minf(absf(s.y), absf(s.z))) < 0.25:
		return -1.0  # scaled down (popping in, or hidden by scale): judge it later
	return (b * gi.get_aabb().size).length()


## The range for a prop of `size` metres (0 = none).
static func end_for(size: float, k: float) -> float:
	if size <= 0.0 or size >= SKIP_SIZE:
		return 0.0
	return maxf(MIN_END, size * k)


func _apply(gi: GeometryInstance3D, retried: bool = false) -> void:
	if gi.has_meta(META):
		return
	if gi.visibility_range_end > 0.0 or gi.visibility_parent != NodePath():
		return  # its own range (ambient NPCs, prizes): theirs stands
	if gi is Label3D and ((gi as Label3D).fixed_size or (gi as Label3D).billboard != BaseMaterial3D.BILLBOARD_DISABLED):
		return  # screen-sized, or kept legible by LegibleLabels (which gives it its own range)
	var size := world_size(gi)
	if size < 0.0:
		if not retried:
			_retry.append(gi)
		return
	var end := end_for(size, _k)
	if end <= 0.0:
		return
	gi.set_meta(META, size)
	gi.visibility_range_end = end
	gi.visibility_range_end_margin = end * 0.06
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	if size < NO_SHADOW_SIZE:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		_casters.append([gi, size, gi.cast_shadow, true])
	culled += 1


## Pure: does a prop of `size` metres at distance `d` cast into the shadow maps?
static func casts_at(size: float, d: float, shadow_k: float) -> bool:
	return d < size * shadow_k


## A slice of the casters per frame: shadows on near the camera, off far from it.
func _update_shadows() -> void:
	if _casters.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	var n := mini(SHADOW_CHUNK, _casters.size())
	for j in n:
		if _caster_i >= _casters.size():
			_caster_i = 0
		var e: Array = _casters[_caster_i]
		var gi: GeometryInstance3D = e[0] if is_instance_valid(e[0]) else null
		if gi == null:
			_casters.remove_at(_caster_i)
			if _casters.is_empty():
				return
			continue
		var on := casts_at(float(e[1]), at.distance_to(gi.global_position), _shadow_k)
		if on != bool(e[3]):
			e[3] = on
			gi.cast_shadow = e[2] if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_caster_i += 1


func _on_quality() -> void:
	_shadow_k = _shadow_k_now()
	var k := _k_now()
	if is_equal_approx(k, _k):
		return
	_k = k
	for r in _roots:
		if is_instance_valid(r):
			_rescale(r)


func _rescale(n: Node) -> void:
	if n is GeometryInstance3D and n.has_meta(META):
		var gi := n as GeometryInstance3D
		var end := end_for(float(gi.get_meta(META)), _k)
		gi.visibility_range_end = end
		gi.visibility_range_end_margin = end * 0.06
	for c in n.get_children():
		_rescale(c)
