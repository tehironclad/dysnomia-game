extends Node3D
## The Field (WP 3.1): the moon Dysnomia with every territory at its real
## coordinates (HECKE.Compliment(Waat), the site's projection). Drag or the arrow
## keys to turn, wheel or = / - to zoom, click a point for its dossier, Warp to go.
##
## Finding a QING: search as you type (name, symbol, #n, 0x…), a results list
## (name, symbol, development tier, reactors), filters (mine, joined, developed ≥ N,
## a fair with rides, trades on YUE, near me), hover tooltips, keyboard ([ ] to step
## through results, Enter to fly, G to warp). Data: the Registry, the development
## snapshot (with its block), Session (your bars), and two live reads made only
## when their filter is used (Admitted(LAU) at the covered rooms; YUE market rates).
## A value that was not read shows "—".
## The coordinates are a modular hash: neighbours on this globe share nothing
## on chain, and the map says so ("near me" uses the raw plane: Neighbours).

const RADIUS := FieldGlobe.RADIUS
const RESULTS_MAX := 80
const FILTERS := ["mine", "joined", "fair", "yue", "near"]
const FILTER_LABELS := {"mine": "Mine", "joined": "Joined", "fair": "Has a fair", "yue": "Trades on YUE", "near": "Near me"}

enum ColorMode { RARITY, HEAT, AGE, DEVELOPMENT }

@onready var camera: Camera3D = $Camera
@onready var ui: Control = $UI/Root

var globe: FieldGlobe
var points: MultiMeshInstance3D   ## the dots (globe.dots)
var territories: Array = []
var rows: Array = []
var visible_mask := PackedByteArray()
var color_mode := ColorMode.RARITY
var rarity_filter := ""
var selected := -1
var hovered := -1
var filters := {}          ## active: mine/joined/fair/yue/near → true; min_tier → int
var results: Array = []    ## rows currently listed
var mine := {}             ## address → true (founded by your wallet, or your bars there)
var joined := {}           ## address → true (Admitted(LAU) at a covered room)
var joined_state := "idle" ## idle | reading | ok | failed
var joined_block := -1
var yue := {}              ## address → true (QING.GetMarketRate(Asset) > 0)
var yue_state := "idle"
var yue_block := -1
var near := {}             ## address → side ("north"…)
var near_anchor := ""
var here := ""
var _yaw := 0.4
var _pitch := 0.35
var _dist := 3.2
var _fly := {}             ## {from: Vector3(yaw,pitch,dist), to: …, t}
var _dragging := false
var _drag_moved := 0.0
var _grow_index := -1  # founding replay cursor (-1 = off)
var _grow_t := 0.0
var _card: TerritoryCard
var _dev: Label
var _info: Label
var _count: FactLabel
var _search: LineEdit
var _results: Tree
var _results_head: Label
var _note: Label
var _warp_btn: Button
var _chips := {}
var _tier_pick: OptionButton
var _tip: PanelContainer
var _tip_label: Label
var _params_cache := {}
var _armed := -1  ## Enter flew here; Enter again warps


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	globe = FieldGlobe.new()
	globe.name = "Globe"
	add_child(globe)
	points = globe.dots
	here = String(GameManager.territory_address).to_lower() if GameManager.is_chain_sourced else ""
	_load_rows()
	_build_ui()
	_update_mine()
	_apply_colors()
	_update_camera()
	for i in territories.size():
		if territories[i]["address"] == here:
			_select(i, true)
			break
	_refresh_results()
	Registry.updated.connect(func(_n): _reload())
	Session.changed.connect(func():
		_update_mine()
		_update_chips()
		_refresh_results()
		_apply_colors())
	Inspector.register(self, "The Field",
		"Each point is a QING at its HECKE.Compliment(Waat) coordinates, projected as the Entropy site does (lon = w0 mod 360e6 / 1e6 − 180, lat = w1 mod 180e6 / 1e6 − 90). The projection is a modular hash: nearness on this globe means nothing on chain.\nColour: rarity (Entropy against the site's cut-offs), heat (log Entropy), age (founding block) or development. A warm halo is a developed QING (tier from the Hypobar total in the development snapshot, block %d); an ice ring is yours (founded by your wallet, or your bars there); the white ring is where you are." % DevelopmentSnapshot.shipped_block())


func _load_rows() -> void:
	territories = Registry.all()
	rows = FieldIndex.build(territories)
	visible_mask.resize(territories.size())
	visible_mask.fill(1)
	globe.setup(territories, rows)


func _reload() -> void:
	var sel_addr := String(territories[selected]["address"]) if selected >= 0 and selected < territories.size() else ""
	_load_rows()
	selected = -1
	for i in territories.size():
		if territories[i]["address"] == sel_addr:
			selected = i
	_on_filter(rarity_filter if rarity_filter != "" else "All")
	_refresh_results()


# --- Globe -------------------------------------------------------------------------

func _pos(i: int) -> Vector3:
	return globe.pos(i)


func _tier(i: int) -> String:
	return String(rows[i]["rarity"]) if String(rows[i]["rarity"]) != "" else "Common"


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
		ColorMode.DEVELOPMENT:
			var td := int(rows[i]["tier"])
			if td < 0:
				return DeepFieldTheme.DIM
			return Color("#3a4258").lerp(Color("#ffd27a"), float(td) / 5.0) if td > 0 else Color("#3a4258")
	return DeepFieldTheme.rarity_color(_tier(i))


func _apply_colors() -> void:
	var cols := PackedColorArray()
	cols.resize(territories.size())
	var mask := visible_mask.duplicate()
	for i in territories.size():
		cols[i] = _color(i)
		if _grow_index >= 0 and i > _grow_index:
			mask[i] = 0
	globe.paint(cols, mask, selected, hovered, mine, here)
	if _grow_index >= 0 and _grow_index < territories.size():
		globe.dots.multimesh.set_instance_transform(_grow_index, Transform3D(Basis().scaled(Vector3.ONE * 2.6), _pos(_grow_index)))


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_dist = clampf(_dist, 1.35, 6.0)
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	camera.position = dir * _dist
	camera.look_at(Vector3.ZERO, Vector3.UP)


## Turn the globe so a territory faces the camera: at once, or a short flight.
func _face(i: int, fly: bool = true, dist: float = -1.0) -> void:
	var q: Dictionary = territories[i]
	var ty := deg_to_rad(float(q.get("lon", 0.0)))
	var tp := deg_to_rad(float(q.get("lat", 0.0)))
	var td := _dist if dist < 0.0 else dist
	# the short way round
	while ty - _yaw > PI:
		ty -= TAU
	while ty - _yaw < -PI:
		ty += TAU
	if not fly:
		_yaw = ty
		_pitch = tp
		_dist = td
		_fly = {}
		_update_camera()
		return
	_fly = {"from": Vector3(_yaw, _pitch, _dist), "to": Vector3(ty, tp, td), "t": 0.0}


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
		var d := sp.distance_to(mouse) - 2.0 * (globe.dev_scale(i) - 1.0)  # developed QINGs are bigger targets
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
				get_viewport().gui_release_focus()
			else:
				_dragging = false
				if _drag_moved < 4.0:
					var i := _pick(event.position)
					if i >= 0:
						_select(i, false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.1)
	elif event is InputEventMouseMotion:
		if _dragging:
			_drag_moved += event.relative.length()
			_fly = {}
			_yaw -= event.relative.x * 0.005 * _dist / 3.0
			_pitch += event.relative.y * 0.005 * _dist / 3.0
			_update_camera()
		else:
			_hover(_pick(event.position), event.position)
	elif event.is_action_pressed("field_search"):
		get_viewport().set_input_as_handled()
		_search.grab_focus()
		_search.select_all()
	elif event.is_action_pressed("field_next"):
		_step_result(1)
	elif event.is_action_pressed("field_prev"):
		_step_result(-1)
	elif event.is_action_pressed("field_warp"):
		_warp()
	elif event.is_action_pressed("field_zoom_in"):
		_zoom(0.85)
	elif event.is_action_pressed("field_zoom_out"):
		_zoom(1.18)
	elif event.is_action_pressed("ui_cancel"):
		if GameManager.is_chain_sourced and GameManager.territory_address != "":
			Travel.go(get_tree(), GameManager.territory_address)
		else:
			get_tree().change_scene_to_file("res://scenes/ui/front_door.tscn")
	elif event.is_action_pressed("ui_accept") and selected >= 0:
		_warp()


func _zoom(f: float) -> void:
	_fly = {}
	_dist *= f
	_update_camera()


func _hover(h: int, at: Vector2) -> void:
	if h != hovered:
		hovered = h
		_apply_colors()
	_tip.visible = h >= 0
	if h < 0:
		return
	_tip_label.text = _tip_text(h)
	_tip.reset_size()
	var vp := ui.get_viewport_rect().size
	var p := at + Vector2(18, 14)
	if p.x + _tip.size.x > vp.x - 8:
		p.x = at.x - _tip.size.x - 18
	if p.y + _tip.size.y > vp.y - 8:
		p.y = at.y - _tip.size.y - 14
	_tip.position = p


func _tip_text(i: int) -> String:
	var r: Dictionary = rows[i]
	var a: String = r["address"]
	var lines: PackedStringArray = []
	lines.append("%s  %s" % [String(r["name"]), String(r["symbol"])])
	lines.append("#%d · %s · %s" % [int(r["n"]), _tier(i), AccessGates.short(a)])
	lines.append("development  %s%s" % [FieldIndex.tier_text(r), (" · snapshot block %d" % int(r["dev_block"])) if int(r["dev_block"]) > 0 else " · not measured"])
	lines.append("reactors     %s%s" % [FieldIndex.reactors_text(r), " (known players)" if int(r["reactors"]) >= 0 else ""])
	lines.append("cover        %s" % ("yes: Join to post" if r["cover"] else "none: open to all"))
	var fair = FieldIndex.has_fair(r)
	lines.append("fair         %s" % ("—" if fair == null else ("rides built" if fair else "surveyed lot")))
	if yue_state == "ok":
		lines.append("YUE desk     %s" % ("rated" if yue.has(a) else "no rate"))
	var tags: PackedStringArray = []
	if a == here:
		tags.append("YOU ARE HERE")
	if mine.has(a):
		tags.append("YOURS")
	if joined.has(a):
		tags.append("JOINED")
	if near.has(a):
		tags.append("%s of you" % String(near[a]))
	if not tags.is_empty():
		lines.append(" · ".join(tags))
	return "\n".join(lines)


func _process(delta: float) -> void:
	if not _fly.is_empty():
		_fly["t"] = minf(1.0, float(_fly["t"]) + delta / 0.9)
		var k := ease(float(_fly["t"]), -2.2)
		var v: Vector3 = (_fly["from"] as Vector3).lerp(_fly["to"], k)
		_yaw = v.x
		_pitch = v.y
		_dist = v.z
		_update_camera()
		if float(_fly["t"]) >= 1.0:
			_fly = {}
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
	elif not _dragging and selected < 0 and _fly.is_empty():
		_yaw += delta * 0.03
		_update_camera()
	# keyboard turn (the arrow keys) when no text field has focus
	var fo := get_viewport().gui_get_focus_owner()
	if fo == null or fo is Tree:
		var turn := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_down", "ui_up"))
		if fo is Tree:
			turn.y = 0.0  # Up/Down move the results list
		if turn != Vector2.ZERO:
			_fly = {}
			_yaw += turn.x * delta * 1.2 * _dist / 3.0
			_pitch += turn.y * delta * 1.0 * _dist / 3.0
			_update_camera()


# --- Selection ----------------------------------------------------------------------

func _select(i: int, quiet: bool) -> void:
	selected = i
	var q: Dictionary = territories[i]
	var r: Dictionary = rows[i]
	_card.show_territory(String(q["address"]))
	_card.visible = true
	_dev.get_parent().visible = true
	_dev.text = "DEVELOPMENT  %s · reactors %s%s\nFAIR  %s   ·   COVER  %s%s" % [FieldIndex.tier_text(r), FieldIndex.reactors_text(r),
		("  (snapshot block %d)" % int(r["dev_block"])) if int(r["dev_block"]) > 0 else "  (not measured: —)",
		"—" if FieldIndex.has_fair(r) == null else ("rides built" if FieldIndex.has_fair(r) else "surveyed lot"),
		"yes" if r["cover"] else "none", "\nYOU ARE HERE" if r["address"] == here else ("\nYOURS" if mine.has(r["address"]) else "")]
	_warp_btn.visible = true
	_warp_btn.disabled = false
	_warp_btn.text = "WARP TO %s  ·  %s" % [String(q.get("name", "")).to_upper().left(26), key("field_warp")]
	if not quiet:
		_face(i, true, minf(_dist, 2.4))
	_apply_colors()
	_sync_tree_selection()


func _warp() -> void:
	if selected < 0:
		return
	Warp.to(get_tree(), String(territories[selected]["address"]))


func _step_result(d: int) -> void:
	if results.is_empty():
		return
	var cur := -1
	for k in results.size():
		if int(results[k]["i"]) == selected:
			cur = k
	cur = wrapi(cur + d, 0, results.size()) if cur >= 0 else (0 if d > 0 else results.size() - 1)
	_select(int(results[cur]["i"]), false)


# --- UI -----------------------------------------------------------------------------

func _label(text: String, variation: String = "MutedLabel", size: int = 0) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


func _inline(text: String) -> Label:
	var l := _label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(64, 0)
	return l


## A key's name as a player reads it ("[" rather than "BracketLeft").
static func key(action: String) -> String:
	var k := ControlsHelp.key_of(action)
	for pair in [["BracketLeft", "["], ["BracketRight", "]"], ["Equal", "="], ["Minus", "-"], ["Slash", "/"]]:
		k = k.replace(pair[0], pair[1])
	return k


func _build_ui() -> void:
	ui.theme = DeepFieldTheme.get_theme()
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(500, 0)
	ui.add_child(panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	panel.add_child(left)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 28)
	title.text = "THE FIELD"
	left.add_child(title)
	_count = FactLabel.new()
	_count.theme_type_variation = "MonoLabel"
	var dev_n := FieldIndex.developed(rows).size()
	_count.set_fact(Fact.ok(territories.size(), "MAP NewQing logs (registry cursor block %d); development: Σ YUE.Bar over known players at block %d" % [Registry.cursor_block, DevelopmentSnapshot.shipped_block()]),
		func(v): return "%d QINGs · %d developed (snapshot block %d)" % [v, dev_n, DevelopmentSnapshot.shipped_block()])
	left.add_child(_count)
	left.add_child(_label("Positions are the chain's own coordinates; nearness here means nothing on chain."))
	_search = LineEdit.new()
	_search.placeholder_text = "Find a QING: name, symbol, #n or 0x…   (%s)" % key("field_search")
	_search.custom_minimum_size = Vector2(0, 42)
	_search.add_theme_font_size_override("font_size", 18)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_results())
	_search.text_submitted.connect(func(_t): _choose_highlight())
	_search.gui_input.connect(_on_search_key)
	left.add_child(_search)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	left.add_child(chips)
	for k in FILTERS:
		var b := Button.new()
		b.toggle_mode = true
		b.text = FILTER_LABELS[k]
		b.toggled.connect(_on_chip.bind(k))
		chips.add_child(b)
		_chips[k] = b
	var trow := HBoxContainer.new()
	left.add_child(trow)
	trow.add_child(_inline("Developed ≥"))
	_tier_pick = OptionButton.new()
	_tier_pick.add_item("any tier")
	for t in range(1, Development.TIERS.size()):
		_tier_pick.add_item("%d · %s" % [t, Development.tier_name(t)])
	_tier_pick.item_selected.connect(func(ix):
		if ix > 0:
			filters["min_tier"] = ix
		else:
			filters.erase("min_tier")
		_refresh_results())
	_tier_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(_tier_pick)
	_results_head = _label("", "MonoLabel", 12)
	left.add_child(_results_head)
	_results = Tree.new()
	_results.columns = 3
	_results.hide_root = true
	_results.select_mode = Tree.SELECT_ROW
	_results.column_titles_visible = true
	_results.set_column_title(0, "QING")
	_results.set_column_title(1, "TIER")
	_results.set_column_title(2, "PLAYERS")
	_results.set_column_expand(0, true)
	_results.set_column_expand(1, false)
	_results.set_column_expand(2, false)
	_results.set_column_custom_minimum_width(1, 118)
	_results.set_column_custom_minimum_width(2, 84)
	_results.custom_minimum_size = Vector2(0, 380)
	_results.add_theme_font_override("font", DeepFieldTheme.body_font())
	_results.add_theme_font_size_override("font_size", 14)
	_results.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style(DeepFieldTheme.HAIRLINE))
	_results.add_theme_color_override("font_color", DeepFieldTheme.INK)
	_results.add_theme_color_override("title_button_color", DeepFieldTheme.MUTED)
	_results.item_selected.connect(func():
		var it := _results.get_selected()
		if it != null and int(it.get_metadata(0)) != selected:
			_select(int(it.get_metadata(0)), false))
	_results.item_activated.connect(_warp)
	left.add_child(_results)
	_note = _label("", "MutedLabel", 12)
	left.add_child(_note)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	left.add_child(modes)
	modes.add_child(_inline("Colour"))
	for m in [["Rarity", ColorMode.RARITY], ["Heat", ColorMode.HEAT], ["Age", ColorMode.AGE], ["Development", ColorMode.DEVELOPMENT]]:
		var b := Button.new()
		b.text = m[0]
		b.pressed.connect(func():
			color_mode = m[1]
			_apply_colors())
		modes.add_child(b)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 6)
	left.add_child(frow)
	frow.add_child(_inline("Rarity"))
	for t in ["All", "Rare", "Epic", "Legendary", "Mythic", "Cover"]:
		var fb := Button.new()
		fb.text = t
		fb.pressed.connect(_on_filter.bind(t))
		frow.add_child(fb)
	var grow := Button.new()
	grow.text = "▶ Watch it grow (founding replay)"
	grow.pressed.connect(func():
		_grow_index = 0
		_grow_t = 0.0)
	left.add_child(grow)
	_info = _label("", "MonoLabel", 12)
	left.add_child(_info)
	# Right: the dossier and the Warp button
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -440
	right.offset_right = -24
	right.offset_top = 24
	right.add_theme_constant_override("separation", 8)
	ui.add_child(right)
	_card = TerritoryCard.new()
	_card.visible = false
	right.add_child(_card)
	var devp := PanelContainer.new()
	devp.visible = false
	right.add_child(devp)
	_dev = _label("", "MonoLabel", 13)
	devp.add_child(_dev)
	_warp_btn = Button.new()
	_warp_btn.visible = false
	_warp_btn.custom_minimum_size = Vector2(0, 54)
	_warp_btn.clip_text = true
	_warp_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_warp_btn.add_theme_font_override("font", DeepFieldTheme.display_font())
	_warp_btn.add_theme_font_size_override("font_size", 16)
	var wsb := DeepFieldTheme.panel_style(DeepFieldTheme.ICE)
	wsb.bg_color = Color(0.66, 0.9, 1.0, 0.16)
	_warp_btn.add_theme_stylebox_override("normal", wsb)
	_warp_btn.pressed.connect(_warp)
	right.add_child(_warp_btn)
	var legend := PanelContainer.new()
	right.add_child(legend)
	legend.add_child(_label("●  dot colour: %s\n◌  warm halo: a developed QING (bigger = higher tier)\n◯  ice ring: yours (founded, or your bars)\n◎  white ring: you are here" % "rarity / heat / age / development", "MutedLabel", 12))
	var hint := _label("drag / arrows  turn   ·   wheel / %s %s  zoom   ·   click  select   ·   %s  search   ·   %s %s  next / previous   ·   Enter  fly · warp   ·   %s  warp   ·   Esc  back   ·   %s  how is this drawn" % [
		key("field_zoom_in"), key("field_zoom_out"), key("field_search"),
		key("field_prev"), key("field_next"), key("field_warp"), key("inspect")])
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -34)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.add_child(hint)
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var tsb := DeepFieldTheme.panel_style(DeepFieldTheme.ICE.darkened(0.3))
	tsb.bg_color.a = 0.9
	_tip.add_theme_stylebox_override("panel", tsb)
	_tip_label = _label("", "MonoLabel", 12)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip.add_child(_tip_label)
	ui.add_child(_tip)
	_update_chips()


func _update_chips() -> void:
	var has_w := Session.wallet != ""
	for k in ["mine", "joined"]:
		var b: Button = _chips[k]
		b.disabled = not has_w
		b.tooltip_text = "Connect a wallet at the front door first." if not has_w else \
			("QINGs your wallet founded, or where your YUE has bars (YUE.Bar, block %d)." % Session.bars_block if k == "mine"
			else "Rooms with a cover that admitted your LAU (QING.Admitted, read live). Rooms with no cover admit everyone.")
		if not has_w and b.button_pressed:
			b.set_pressed_no_signal(false)
			filters.erase(k)
	var anchor := _near_anchor()
	var nb: Button = _chips["near"]
	nb.disabled = anchor == ""
	nb.tooltip_text = "The QINGs bordering %s, from the raw HECKE plane (BigInt, the border rings' rule)." % String(Registry.get_territory(anchor).get("name", anchor)) if anchor != "" \
		else "Visit a territory first (or connect a wallet with bars): near is measured from where you are."
	_chips["fair"].tooltip_text = "The fair has rides from Settlement up (tier from the development snapshot, block %d)." % DevelopmentSnapshot.shipped_block()
	_chips["yue"].tooltip_text = "QINGs whose asset has a market rate (QING.GetMarketRate(Asset) > 0): their YUE desks trade. Read live."


func _update_mine() -> void:
	mine = {}
	var w := Session.wallet
	if w == "":
		return
	for r in rows:
		if String(r["creator"]) == w:
			mine[r["address"]] = true
	for a in Session.bars:
		mine[String(a).to_lower()] = true


## Where "near me" is measured from: where you are, else your biggest bar.
func _near_anchor() -> String:
	if here != "":
		return here
	var best := ""
	var best_v := PackedInt64Array()
	for a in Session.bars:
		var hv: PackedInt64Array = Session.bars[a][0]
		if best == "" or BigInt.cmp(hv, best_v) > 0:
			best = String(a).to_lower()
			best_v = hv
	return best


func _on_chip(on: bool, k: String) -> void:
	if on:
		filters[k] = true
	else:
		filters.erase(k)
	if on and k == "joined" and joined_state in ["idle", "failed"]:
		_read_joined()
	if on and k == "yue" and yue_state in ["idle", "failed"]:
		_read_yue()
	if on and k == "near":
		_find_near()
	_refresh_results()


func _find_near() -> void:
	near = {}
	near_anchor = _near_anchor()
	var q: Dictionary = Registry.get_territory(near_anchor)
	if q.is_empty():
		return
	var nb: Dictionary = Neighbours.find(q, territories)
	near[near_anchor] = "you"
	for side in nb:
		near[String(nb[side]["address"])] = String(Neighbours.NAMES.get(side, side))
	for i in territories.size():
		if territories[i]["address"] == near_anchor:
			_face(i, true, 2.0)


func _read_joined() -> void:
	var ps: PlayerState = Session.player
	if ps == null or not ps.has_lau():
		joined_state = "failed" if ps != null else "reading"
		_refresh_results()
		return
	joined_state = "reading"
	_refresh_results()
	var covered: Array = rows.filter(func(r): return r["cover"])
	var head: int = await Chain.refresh_head()
	if head < 0:
		joined_state = "failed"
		_refresh_results()
		return
	var calls: Array = []
	for r in covered:
		calls.append(Multicall.make_call(r["address"], "Admitted(address)", [ps.lau]))
	var res: Array = await Chain.multicall.run(calls, Session.wallet, head)
	var got := {}
	var answered := 0
	for k in covered.size():
		var v = Multicall.value(res[k], ["bool"]) if k < res.size() and res[k] is Dictionary else null
		if v == null:
			continue
		answered += 1
		if v[0]:
			got[covered[k]["address"]] = true
	if answered == 0 and not covered.is_empty():
		joined_state = "failed"
	else:
		joined = got
		joined_state = "ok"
		joined_block = head
	_refresh_results()


func _read_yue() -> void:
	yue_state = "reading"
	_refresh_results()
	var r = await YueExchange.rated_scan()
	if r == null:
		yue_state = "failed"
	else:
		yue = {}
		for row in r:
			yue[String(row["qing"])] = true
		yue_state = "ok"
		yue_block = YueExchange.rated_block()
	_refresh_results()


func _active_filters() -> Dictionary:
	var f := {}
	if filters.has("min_tier"):
		f["min_tier"] = filters["min_tier"]
	if filters.has("mine"):
		f["mine"] = mine
	if filters.has("joined"):
		f["joined"] = joined if joined_state == "ok" else {}
	if filters.has("fair"):
		f["fair"] = true
	if filters.has("yue"):
		f["yue"] = yue if yue_state == "ok" else {}
	if filters.has("near"):
		f["neighbours"] = near
	return f


func _refresh_results() -> void:
	if _results == null:
		return
	var text := _search.text
	var f := _active_filters()
	var all_hits := FieldIndex.query(rows, text, f)
	results = all_hits.slice(0, RESULTS_MAX)
	_results.clear()
	var root := _results.create_item()
	for r in results:
		var it := _results.create_item(root)
		var a: String = r["address"]
		var tag := ""
		if a == here:
			tag = "◎ "
		elif mine.has(a):
			tag = "◯ "
		var side := ("%s · " % String(near[a])) if filters.has("near") and near.has(a) else ""
		it.set_text(0, "%s%s%s   %s" % [tag, side, String(r["name"]), String(r["symbol"])])
		it.set_tooltip_text(0, "#%d · %s" % [int(r["n"]), a])
		it.set_text(1, FieldIndex.tier_text(r))
		it.set_text(2, FieldIndex.reactors_text(r))
		it.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		var t := int(r["tier"])
		it.set_custom_color(1, DeepFieldTheme.DIM if t <= 0 else Color("#3a4258").lerp(Color("#ffd27a"), 0.35 + 0.13 * t))
		it.set_custom_color(0, DeepFieldTheme.ICE if a == here or mine.has(a) else DeepFieldTheme.INK)
		it.set_custom_font(1, DeepFieldTheme.mono_font())
		it.set_custom_font(2, DeepFieldTheme.mono_font())
		it.set_metadata(0, int(r["i"]))
	_results_head.text = "%d match%s%s · best match, then most developed · players = reactors (known, snapshot)" % [all_hits.size(), "" if all_hits.size() == 1 else "es",
		(" (first %d shown)" % RESULTS_MAX) if all_hits.size() > RESULTS_MAX else ""]
	_note.text = _filter_note()
	_note.visible = _note.text != ""
	# The globe shows what the list shows (search + filters), dimming the rest.
	var shown := {}
	for r in all_hits:
		shown[int(r["i"])] = true
	var any_filter := text.strip_edges() != "" or not f.is_empty()
	for i in territories.size():
		var ok := (not any_filter or shown.has(i)) and _rarity_ok(i)
		visible_mask[i] = 1 if ok else 0
	_apply_colors()
	_sync_tree_selection()


func _filter_note() -> String:
	var parts: PackedStringArray = []
	if filters.has("joined"):
		match joined_state:
			"reading": parts.append("Joined: checking… (QING.Admitted(LAU) at the covered rooms)")
			"failed": parts.append("Joined: — (could not read Admitted%s)" % ("; no LAU yet" if Session.player != null and not Session.player.has_lau() else ""))
			"ok": parts.append("Joined: %d covered room%s admit your LAU (block %d); rooms with no cover admit everyone." % [joined.size(), "" if joined.size() == 1 else "s", joined_block])
	if filters.has("yue"):
		match yue_state:
			"reading": parts.append("Trades on YUE: checking… (QING.GetMarketRate for every QING)")
			"failed": parts.append("Trades on YUE: — (the rates could not be read)")
			"ok": parts.append("Trades on YUE: %d QING%s with a market rate (block %d)." % [yue.size(), "" if yue.size() == 1 else "s", yue_block])
	if filters.has("near"):
		parts.append("Near %s: the nearest QING in each quarter of the raw HECKE plane." % String(Registry.get_territory(near_anchor).get("name", "—")))
	if filters.has("mine"):
		parts.append("Mine: founded by %s, or bars at block %d." % [AccessGates.short(Session.wallet), Session.bars_block] if Session.bars_block > 0 else "Mine: founded by your wallet (your bars: checking…).")
	if filters.has("fair") or filters.has("min_tier"):
		parts.append("Development: snapshot block %d; QINGs founded later show —." % DevelopmentSnapshot.shipped_block())
	return "\n".join(parts)


func _rarity_ok(i: int) -> bool:
	match rarity_filter:
		"", "All":
			return true
		"Cover":
			return bool(rows[i]["cover"])
	return _tier(i) == rarity_filter


func _sync_tree_selection() -> void:
	if _results == null:
		return
	var root := _results.get_root()
	if root == null:
		return
	var it := root.get_first_child()
	while it != null:
		if int(it.get_metadata(0)) == selected:
			if not it.is_selected(0):
				it.select(0)
			_results.scroll_to_item(it)
			return
		it = it.get_next()
	_results.deselect_all()


func _on_search_key(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_search.accept_event()
		_step_result(1)
	elif event.is_action_pressed("ui_up"):
		_search.accept_event()
		_step_result(-1)
	elif event.is_action_pressed("ui_cancel"):
		_search.accept_event()
		if _search.text != "":
			_search.text = ""
			_refresh_results()
		else:
			_search.release_focus()


## Enter in the search: fly to the highlighted result (the top one if none); Enter
## again on the same one warps.
func _choose_highlight() -> void:
	if results.is_empty():
		return
	var listed := results.any(func(r): return int(r["i"]) == selected)
	if listed and _armed == selected:
		_warp()
		return
	if listed:
		_face(selected, true, minf(_dist, 2.4))
	else:
		_select(int(results[0]["i"]), false)
	_armed = selected


func _on_filter(t: String) -> void:
	rarity_filter = t
	var shown := 0
	for i in territories.size():
		var ok := _rarity_ok(i)
		visible_mask[i] = 1 if ok else 0
		shown += 1 if ok else 0
	_info.text = "%s: %d of %d" % [t, shown, territories.size()]
	_apply_colors()


## screenshot.gd --field-search=… --field-filter=mine,fair,tier:2: a preview of the finder.
func preview(text: String, fs: Array) -> void:
	for f in fs:
		var s := String(f)
		if s.begins_with("tier:"):
			_tier_pick.select(int(s.substr(5)))
			_tier_pick.item_selected.emit(int(s.substr(5)))
		elif _chips.has(s) and not _chips[s].disabled:
			_chips[s].button_pressed = true
	_search.text = text
	_refresh_results()
	if not results.is_empty():
		_select(int(results[0]["i"]), false)
		_fly = {}
		_face(selected, false, 2.2)
		var sp := camera.unproject_position(_pos(selected))
		_hover(selected, sp)
