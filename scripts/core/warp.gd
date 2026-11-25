class_name Warp
extends CanvasLayer
## The warp (WP 3.2): a dive into the destination territory's Julia set
## (the site's endless-dive idea), then the territory loads underneath.
## Lives on the root so it survives the scene change, then fades out.
##
## Loading (2026-11-24): the destination's ground (JuliaHeightfield, cached on disk
## after the first visit) is computed on a worker thread during the dive, then its
## neighbours' grounds seen beyond the borders, so a first visit never freezes the
## game. While that runs the dive holds and a loading card shows real progress (from
## the compute itself) and lore from the project's own words. After the scene change
## the overlay stays up for a few rendered frames, so the new scene's shaders and
## pipelines compile behind it instead of hitching the first seconds of play.

const DURATION := 1.4
const WARM_FRAMES := 12   ## frames the new scene renders behind the overlay before it fades
const TIP_S := 5.5
## Lore and how-to, curated (LEARNINGS §12, the game's own rules). Nothing chain-shaped.
const TIPS := [
	"You stand on Dysnomia, Eris's moon at the edge of the solar system. Eris fills the sky; the sun is just another star.",
	"Every territory's ground is its QING's Entropy drawn as a Julia set: inside the set a plateau, its boundary a crest.",
	"Exploration is not about combat, it is about presence.",
	"Nothing is wiped clean. Entropy only increases. Your history is your substance.",
	"Rod and Cone, the twin pylons at every Core, are paired SHAs that must mirror, or the transaction reverts.",
	"META.Beat either beats or it doesn't. The Heart at the Core shows which.",
	"Fomalhaute, Fornax, Tethys and Phobos light up in your sky only when you truly hold them.",
	"A Dysnomia day is 34 hours of 100-minute hours, kept by block time, so every player shares the same sky.",
	"Enter the Void. Get a Soul. Find a territory.",
	"The Void's board is one chat for everyone, immutable: what is said there stays.",
	"Every number in the world carries its source and block. A failed read shows \"—\", never a guess.",
	"WORLD and WAR are not deployed yet. Where they would stand, the world shows them honestly absent.",
	"A crow rides your shoulder only if you truly hold 25 CROWS or more.",
	"The skyline grows from the Hypobar total: bars never shrink, so neither does the city.",
]

var _view: DeepFieldView
var _label: Label
var _card: PanelContainer
var _stage: Label
var _bar: ProgressBar
var _pct: Label
var _tip: Label
var _p: Dictionary
var _dive = null
var _t := 0.0
var _tip_t := 0.0
var _tip_i := 0
var _address := ""
var _changed := false
var _warm := 0
var _q: Dictionary = {}
var _neighbours: Array = []  ## Registry records of the neighbours whose ground isn't cached
var _thread: Thread
var _ground_ready := false
var _done_n := 0             ## neighbours finished (written by the worker; an int, read for display)


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
	w._start_ground(tree)


## Pure: the loading bar's value (0..1) from the main ground's progress (-1 = not running)
## and how many of the neighbours' grounds are done. The main ground is 80 % of the bar.
static func overall(main: float, main_done: bool, done_n: int, total_n: int) -> float:
	var m := 1.0 if main_done else clampf(main, 0.0, 1.0)
	if total_n <= 0:
		return m
	return 0.8 * m + 0.2 * clampf(float(done_n) / float(total_n), 0.0, 1.0)


func _start_ground(tree: SceneTree) -> void:
	var main_cached := FileAccess.file_exists(JuliaHeightfield.cache_path(_address, DeepFieldTerrain.SAMPLES))
	# The neighbours beyond the borders (BorderRing would compute them after arrival).
	var found := Neighbours.find(_q, tree.root.get_node("Registry").all())
	for side in found:
		var nq: Dictionary = tree.root.get_node("Registry").get_territory(String(found[side]["address"]))
		if not nq.is_empty() and not FileAccess.file_exists(JuliaHeightfield.cache_path(String(nq["address"]), BorderRing.SAMPLES)):
			_neighbours.append(nq.duplicate())
	if main_cached and _neighbours.is_empty():
		_ground_ready = true
		return
	_card.visible = not main_cached  # a first visit: show what is being built
	_tip_i = int(String(_address).hash()) % TIPS.size() if not TIPS.is_empty() else 0
	_tip_i = absi(_tip_i)
	_tip.text = TIPS[_tip_i]
	_thread = Thread.new()
	_thread.start(_build.bind(_q, _neighbours.duplicate()))


## Worker thread: the ground, then the neighbours' grounds (each cached on disk).
func _build(q: Dictionary, nbs: Array) -> void:
	JuliaHeightfield.for_territory(q, DeepFieldTerrain.SAMPLES)
	for nq in nbs:
		JuliaHeightfield.for_territory(nq, BorderRing.SAMPLES)
		_done_n += 1


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
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_build_card()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.theme = DeepFieldTheme.get_theme()
	_card.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style(DeepFieldTheme.ICE * Color(1, 1, 1, 0.45)))
	_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card.custom_minimum_size = Vector2(640, 0)
	_card.position = Vector2(-320, -200)
	_card.visible = false
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_stage = Label.new()
	_stage.text = "First visit: building this territory's ground from its Entropy…"
	_stage.add_theme_color_override("font_color", DeepFieldTheme.INK)
	_stage.add_theme_font_size_override("font_size", DeepFieldTheme.FS_BODY)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stage)
	_pct = Label.new()
	_pct.add_theme_font_override("font", DeepFieldTheme.mono_font())
	_pct.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_pct.text = "0 %"
	row.add_child(_pct)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = DeepFieldTheme.ICE
	fg.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(_bar)
	_tip = Label.new()
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	_tip.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	_tip.custom_minimum_size = Vector2(600, 44)
	box.add_child(_tip)
	var note := Label.new()
	note.text = "Computed once on this computer, then cached: later visits load at once."
	note.add_theme_color_override("font_color", DeepFieldTheme.DIM)
	note.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	box.add_child(note)


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
	if not _changed:
		_view.set_view(center * ease, ext * lerpf(1.0, 0.04, ease), angle)
	if not _ground_ready and _thread != null:
		_show_progress(delta)
		if not _thread.is_alive():
			_thread.wait_to_finish()
			_thread = null
			_ground_ready = true
	if k >= 1.0 and not _ground_ready:
		_t = DURATION  # hold at the end of the dive, still turning, until the ground is built
	if k >= 1.0 and not _changed and _ground_ready:
		_changed = true
		if _card.visible:
			_bar.value = 1.0
			_pct.text = "100 %"
			_stage.text = "Entering…"
		Travel.go(get_tree(), _address)
		return
	if _changed:
		# Hold opaque while the new scene renders its first frames (shader warm-up), then fade.
		if _warm < WARM_FRAMES:
			_warm += 1
			_t = DURATION
			return
		var fade := clampf((_t - DURATION) / 0.6, 0.0, 1.0)
		_view.modulate.a = 1.0 - fade
		_label.modulate.a = 1.0 - fade
		_card.modulate.a = 1.0 - fade
		if fade >= 1.0:
			queue_free()


func _show_progress(delta: float) -> void:
	var main := JuliaHeightfield.progress_of(_address, DeepFieldTerrain.SAMPLES)
	var main_done := main < 0.0 and FileAccess.file_exists(JuliaHeightfield.cache_path(_address, DeepFieldTerrain.SAMPLES))
	var v := overall(main, main_done, _done_n, _neighbours.size())
	_bar.value = maxf(_bar.value, v)
	_pct.text = "%d %%" % int(_bar.value * 100.0)
	if main_done and not _neighbours.is_empty():
		_stage.text = "The neighbours' ground beyond the borders (%d of %d)…" % [mini(_done_n + 1, _neighbours.size()), _neighbours.size()]
	_tip_t += delta
	if _tip_t >= TIP_S:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = TIPS[_tip_i]


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
