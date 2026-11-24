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
const K_BY_QUALITY := [120.0, 170.0, 240.0, 320.0, 420.0]
const MIN_END := 24.0
const SKIP_SIZE := 24.0       ## a prop this big (m) or bigger is never culled by size
const NO_SHADOW_SIZE := 0.3   ## props smaller than this cast no shadow
const META := "dc_size"

var _roots: Array[Node] = []
var _skip: Array[Node] = []
var _pending: Array[GeometryInstance3D] = []
var _retry: Array[GeometryInstance3D] = []
var _retry_t := 0.0
var _k := 240.0
var culled := 0  ## instances with a range set (for perf notes)


func _ready() -> void:
	_k = _k_now()
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
	if gi is Label3D and (gi as Label3D).fixed_size:
		return
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
	culled += 1


func _on_quality() -> void:
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
