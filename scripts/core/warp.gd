class_name Warp
extends CanvasLayer
## The warp (WP 3.2): a dive into the destination territory's Julia set
## (the site's endless-dive idea), then the territory loads underneath.
## Lives on the root so it survives the scene change, then fades out.
## The destination's terrain (JuliaHeightfield, cached on disk after the first
## visit) is computed on a worker thread during the dive, so a first visit
## never freezes the game; the dive holds until the ground is ready.

const DURATION := 1.4

var _view: DeepFieldView
var _label: Label
var _p: Dictionary
var _dive = null
var _t := 0.0
var _address := ""
var _changed := false
var _q: Dictionary = {}
var _thread: Thread
var _ground_ready := false


static func to(tree: SceneTree, address: String) -> void:
	var q: Dictionary = tree.root.get_node("Registry").get_territory(address)
	if q.is_empty():
		return
	var w := Warp.new()
	w._address = String(q["address"])
	w._p = DeepField.for_territory(q)
	w._dive = DeepField.dive_point(w._p, w._address)
	if w._dive == null:  # power > 2: dive toward a boundary point instead
		w._dive = {"z": DeepField.boundary_point(w._p, float(w._p["hue"]) * TAU), "arg": 0.6}
	w._q = q.duplicate()
	tree.root.add_child(w)
	w._label.text = "→ %s" % String(q.get("name", "")).to_upper()
	w._start_ground()


func _start_ground() -> void:
	if FileAccess.file_exists(JuliaHeightfield.cache_path(_address, DeepFieldTerrain.SAMPLES)):
		_ground_ready = true
		return
	_thread = Thread.new()
	_thread.start(func(): JuliaHeightfield.for_territory(_q, DeepFieldTerrain.SAMPLES))


func _init() -> void:
	layer = 100
	_view = DeepFieldView.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_view)
	_label = Label.new()
	_label.theme = DeepFieldTheme.get_theme()
	_label.theme_type_variation = "DisplayLabel"
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.position = Vector2(-300, -20)
	_label.size = Vector2(600, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _ready() -> void:
	_view.max_iter = int(Config.preset().get("warp_iter", 160))
	_view.apply_params(_p)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var ext := float(_p["extent"])
	var center := Vector2.ZERO
	var angle := float(_p["rotation"])
	if _dive != null:
		center = Vector2(_dive["z"][0], _dive["z"][1])
		angle += float(_dive["arg"]) * k * 2.0
	var ease := k * k * (3.0 - 2.0 * k)
	_view.set_view(center * ease, ext * lerpf(1.0, 0.04, ease), angle)
	if not _ground_ready and _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		_ground_ready = true
	if k >= 1.0 and not _ground_ready:
		_t = DURATION  # hold at the end of the dive, still turning, until the ground is built
		_label.text = "→ %s · building its ground (first visit)…" % String(_q.get("name", "")).to_upper()
	if k >= 1.0 and not _changed and _ground_ready:
		_changed = true
		Travel.go(get_tree(), _address)
	if _changed:
		var fade := clampf((_t - DURATION) / 0.6, 0.0, 1.0)
		_view.modulate.a = 1.0 - fade
		_label.modulate.a = 1.0 - fade
		if fade >= 1.0:
			queue_free()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
