extends Node3D
## The Field (WP 3.1): the moon Dysnomia with every territory at its real
## coordinates (HECKE.Compliment(Waat), the site's projection). Drag to turn,
## wheel to zoom, click a point for its dossier, Warp to go there.
## The coordinates are a modular hash: neighbours on this globe share nothing
## on chain, and the map says so.

const RADIUS := 1.0
const POINT_SIZE := 0.0075

enum ColorMode { RARITY, HEAT, AGE }

@onready var camera: Camera3D = $Camera
@onready var points: MultiMeshInstance3D = $Points
@onready var ui: Control = $UI/Root

var territories: Array = []
var visible_mask := PackedByteArray()
var color_mode := ColorMode.RARITY
var rarity_filter := ""
var selected := -1
var hovered := -1
var _yaw := 0.4
var _pitch := 0.35
var _dist := 3.2
var _dragging := false
var _grow_index := -1  # founding replay cursor (-1 = off)
var _grow_t := 0.0
var _card: TerritoryCard
var _info: Label
var _count: FactLabel
var _search: LineEdit
var _results: ItemList
var _warp_btn: Button
var _tip: Label
var _params_cache := {}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	territories = Registry.all()
	_build_points()
	_build_ui()
	_apply_colors()
	_update_camera()
	var current := String(GameManager.territory_address).to_lower()
	for i in territories.size():
		if territories[i]["address"] == current:
			_select(i, true)
			break
	Registry.updated.connect(func(_n): _reload())
	Inspector.register(self, "The Field",
		"Each point is a QING at its HECKE.Compliment(Waat) coordinates, projected as the Entropy site does (lon = w0 mod 360e6 / 1e6 − 180, lat = w1 mod 180e6 / 1e6 − 90). The projection is a modular hash: nearness on this globe means nothing on chain.\nColour: rarity (Entropy against the site's cut-offs), heat (log Entropy) or age (founding block).")


func _reload() -> void:
	territories = Registry.all()
	_build_points()
	_apply_colors()


# --- Globe -------------------------------------------------------------------------

func _build_points() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var dot := SphereMesh.new()
	dot.radius = POINT_SIZE
	dot.height = POINT_SIZE * 2.0
	dot.radial_segments = 8
	dot.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	dot.material = mat
	mm.mesh = dot
	mm.instance_count = territories.size()
	visible_mask.resize(territories.size())
	visible_mask.fill(1)
	for i in territories.size():
		mm.set_instance_transform(i, Transform3D(Basis(), _pos(i)))
	points.multimesh = mm


func _pos(i: int) -> Vector3:
	var q: Dictionary = territories[i]
	return Coords.to_sphere(float(q.get("lat", 0.0)), float(q.get("lon", 0.0))) * (RADIUS + POINT_SIZE * 0.5)


func _tier(i: int) -> String:
	var e := String(territories[i].get("entropy", ""))
	return DeepField.tier_of(BigInt.from_decimal(e)) if e != "" else "Common"


func _color(i: int) -> Color:
	var q: Dictionary = territories[i]
	match color_mode:
		ColorMode.HEAT:
			var e := String(q.get("entropy", ""))
			var lg := BigInt.log10(BigInt.from_decimal(e)) if e != "" else 0.0
			var t := clampf((lg - log(8e11) / log(10.0)) / (log(4.4e14) / log(10.0) - log(8e11) / log(10.0)), 0.0, 1.0)
			return Color8(int(70 + 98 * pow(t, 0.75)), int(84 + 146 * t), int(104 + 151 * t))  # the site's globe heat
		ColorMode.AGE:
			var b0 := float(Contracts.MAP_FIRST_BLOCK)
			var t2 := clampf((float(q["block"]) - b0) / maxf(1.0, float(Registry.cursor_block) - b0), 0.0, 1.0)
			return DeepFieldTheme.ICE.lerp(Color("#ffb070"), t2)
	return DeepFieldTheme.rarity_color(_tier(i))


func _apply_colors() -> void:
	var mm := points.multimesh
	for i in territories.size():
		var c := _color(i)
		var shown := visible_mask[i] == 1 and (_grow_index < 0 or i <= _grow_index)
		if not shown:
			c = Color(0.08, 0.09, 0.12)
		if i == selected:
			c = Color.WHITE
		mm.set_instance_color(i, c)
		var s := 2.2 if i == selected else (1.5 if i == hovered else 1.0)
		if _grow_index >= 0 and i == _grow_index:
			s = 2.6
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), _pos(i)))


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_dist = clampf(_dist, 1.35, 6.0)
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	camera.position = dir * _dist
	camera.look_at(Vector3.ZERO, Vector3.UP)


## Turn the globe so a territory faces the camera.
func _face(i: int) -> void:
	var q: Dictionary = territories[i]
	_yaw = deg_to_rad(float(q.get("lon", 0.0)))
	_pitch = deg_to_rad(float(q.get("lat", 0.0)))
	_update_camera()


func _pick(mouse: Vector2) -> int:
	var best := -1
	var best_d := 14.0
	var cam_dir := camera.global_position.normalized()
	for i in territories.size():
		if visible_mask[i] == 0:
			continue
		var p := _pos(i)
		if p.normalized().dot(cam_dir) < 0.05:
			continue  # far side of the moon
		var sp := camera.unproject_position(p)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if _drag_moved < 4.0:
					var i := _pick(event.position)
					if i >= 0:
						_select(i, false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist *= 0.9
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist *= 1.1
			_update_camera()
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag_moved += event.relative.length()
			_yaw -= event.relative.x * 0.005 * _dist / 3.0
			_pitch += event.relative.y * 0.005 * _dist / 3.0
			_update_camera()
		else:
			var h := _pick(event.position)
			if h != hovered:
				hovered = h
				_apply_colors()
				_tip.text = "" if h < 0 else "%s · %s" % [territories[h].get("name", ""), _tier(h)]
				_tip.position = event.position + Vector2(14, 10)
	elif event.is_action_pressed("ui_cancel") and GameManager.is_chain_sourced:
		Travel.go(get_tree(), GameManager.territory_address)
	elif event.is_action_pressed("ui_accept") and selected >= 0 and not _search.has_focus():
		_warp()


var _drag_moved := 0.0


func _process(delta: float) -> void:
	if _grow_index >= 0:
		_grow_t += delta
		if _grow_t > 0.02:
			_grow_t = 0.0
			_grow_index += 3
			if _grow_index >= territories.size():
				_grow_index = -1
				_info.text = "Replay done: %d territories, founded from block %d." % [territories.size(), Contracts.MAP_FIRST_BLOCK]
			else:
				_info.text = "Founding replay · #%d %s · block %d" % [_grow_index + 1, territories[_grow_index].get("name", ""), int(territories[_grow_index]["block"])]
			_apply_colors()
	elif not _dragging and selected < 0:
		_yaw += delta * 0.03
		_update_camera()


# --- Selection & UI ------------------------------------------------------------------

func _select(i: int, quiet: bool) -> void:
	selected = i
	var q: Dictionary = territories[i]
	_card.show_territory(String(q["address"]))
	_card.visible = true
	_warp_btn.visible = true
	_warp_btn.text = "WARP TO %s" % String(q.get("symbol", "")).to_upper()
	if not quiet:
		_face(i)
	_apply_colors()


func _warp() -> void:
	if selected < 0:
		return
	Warp.to(get_tree(), String(territories[selected]["address"]))


func _build_ui() -> void:
	ui.theme = DeepFieldTheme.get_theme()
	var left := VBoxContainer.new()
	left.position = Vector2(20, 20)
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	ui.add_child(left)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = "THE FIELD"
	left.add_child(title)
	_count = FactLabel.new()
	_count.theme_type_variation = "MonoLabel"
	_count.set_fact(Fact.ok(territories.size(), "MAP NewQing logs (registry cursor block %d)" % Registry.cursor_block),
		func(v): return "%d territories" % v)
	left.add_child(_count)
	var note := Label.new()
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Positions are the chain's own coordinates; nearness here means nothing on chain."
	left.add_child(note)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, symbol, address…"
	_search.text_changed.connect(_on_search)
	left.add_child(_search)
	_results = ItemList.new()
	_results.custom_minimum_size = Vector2(330, 0)
	_results.auto_height = true
	_results.max_columns = 1
	_results.visible = false
	_results.item_selected.connect(func(idx): _select(int(_results.get_item_metadata(idx)), false))
	left.add_child(_results)
	var modes := HBoxContainer.new()
	left.add_child(modes)
	for m in [["Rarity", ColorMode.RARITY], ["Heat", ColorMode.HEAT], ["Age", ColorMode.AGE]]:
		var b := Button.new()
		b.text = m[0]
		b.pressed.connect(func():
			color_mode = m[1]
			_apply_colors())
		modes.add_child(b)
	var filters := HBoxContainer.new()
	left.add_child(filters)
	for t in ["All", "Rare", "Epic", "Legendary", "Mythic", "Cover"]:
		var fb := Button.new()
		fb.text = t
		fb.pressed.connect(_on_filter.bind(t))
		filters.add_child(fb)
	var grow := Button.new()
	grow.text = "▶ Watch it grow"
	grow.pressed.connect(func():
		_grow_index = 0
		_grow_t = 0.0)
	left.add_child(grow)
	_info = Label.new()
	_info.theme_type_variation = "MonoLabel"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_info)
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-360, 20)
	right.custom_minimum_size = Vector2(340, 0)
	ui.add_child(right)
	_card = TerritoryCard.new()
	_card.visible = false
	right.add_child(_card)
	_warp_btn = Button.new()
	_warp_btn.visible = false
	_warp_btn.pressed.connect(_warp)
	right.add_child(_warp_btn)
	var hint := Label.new()
	hint.theme_type_variation = "MutedLabel"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -36)
	hint.text = "drag  turn   ·   wheel  zoom   ·   click  select   ·   Enter  warp   ·   Esc  back   ·   H  how is this drawn"
	ui.add_child(hint)
	_tip = Label.new()
	_tip.theme_type_variation = "MonoLabel"
	ui.add_child(_tip)


func _on_search(text: String) -> void:
	_results.clear()
	if text.strip_edges().length() < 2:
		_results.visible = false
		return
	var hits: Array = Registry.search(text, 8)
	for q in hits:
		var idx := _results.add_item("%s  (%s)" % [q.get("name", ""), q.get("symbol", "")])
		_results.set_item_metadata(idx, territories.find(q))
	_results.visible = not hits.is_empty()


func _on_filter(t: String) -> void:
	rarity_filter = t
	var shown := 0
	for i in territories.size():
		var ok := true
		if t == "Cover":
			ok = String(territories[i].get("cover_charge", "0")) not in ["0", ""]
		elif t != "All":
			ok = _tier(i) == t
		visible_mask[i] = 1 if ok else 0
		shown += 1 if ok else 0
	_info.text = "%s: %d of %d" % [t, shown, territories.size()]
	_apply_colors()
