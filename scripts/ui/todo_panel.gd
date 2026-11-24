class_name TodoPanel
extends PanelContainer
## "Things to do here" — the what-do-I-do-now answer for a bear who just arrived from
## Telegram. Toggle with Y. Shows today's QING quests with progress, what this QING has
## built (Cantina tables with their records, rides by fair tier, monument, array…), and
## how this QING's Standing actually rises (chain activity: visitors who chat, terraform
## charge, the keeper's bars). Quests and Cantina scores never change Standing.
##
## One-line install from main.gd (after the pub, Standing and attractions exist):
##   TodoPanel.install(hud, _standing, _pub_building)

const TOGGLE_KEY := KEY_Y
const PULSE := DysnomiaLore.PULSE
const PINK := DysnomiaLore.AFFECTION_PINK
const GOLD := DysnomiaLore.GOLD
const DIM := DysnomiaLore.DIM

## What each fair tier has built (mirrors Funfair._build_rides / QingStanding.UNLOCKS)
const FAIR_ITEMS := [
	{"tier": 1, "name": "Orbital Carousel", "what": "rocket-sleds round the orrery"},
	{"tier": 1, "name": "Night Market", "what": "stalls by the plaza"},
	{"tier": 2, "name": "Rho Wheel", "what": "lantern gondolas, 30 m up"},
	{"tier": 2, "name": "Pi Drop Tower", "what": "55 m, dropped in low gravity"},
	{"tier": 2, "name": "Bandstand", "what": "live music on the plaza"},
	{"tier": 3, "name": "Upsilon Rocket", "what": "400 m straight up, parachute home"},
	{"tier": 3, "name": "Launch bleachers", "what": "watch the rockets go"},
]

var _hud: CanvasLayer
var _standing: Node
var _scroll: ScrollContainer
var _body: VBoxContainer
var _title: Label
var _sub: Label
var _tracker: QuestTracker
var _open: bool = false


static func install(hud: CanvasLayer, standing: Node = null, pub_building: Node = null) -> TodoPanel:
	var p := TodoPanel.new()
	p.name = "TodoPanel"
	p._hud = hud
	p._standing = standing
	hud.add_child(p)
	var tr := QuestTracker.new()
	tr.name = "QuestTracker"
	hud.add_child(tr)
	p._tracker = tr
	if pub_building:
		TableRecordSigns.attach(pub_building)
	if standing and standing.has_signal("standing_changed"):
		standing.standing_changed.connect(p._on_standing)
		p._on_standing(standing.current())
	GameManager.territory_data_changed.connect(p._on_territory)
	p._report_visit()
	return p


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", DysnomiaLore.styled_panel(Color(PULSE, 0.75)))
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -470
	offset_right = -16
	offset_top = 70
	offset_bottom = -70

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	head.add_child(col)
	_title = _lbl("THINGS TO DO HERE", 20, PULSE.lightened(0.2))
	col.add_child(_title)
	_sub = _lbl("", 12, DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_sub)
	var x := Button.new()
	x.text = "X"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(32, 32)
	x.pressed.connect(close)
	head.add_child(x)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)

	var foot := _lbl("%s close · quests reset 00:00 UTC · rewards are titles & bragging rights" % OS.get_keycode_string(TOGGLE_KEY), 11, Color(0.5, 0.5, 0.6))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(foot)

	QuestBoard.bus.changed.connect(func() -> void:
		if _open:
			rebuild())


# ─── Open / close ───────────────────────────────────────────────────────

func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	rebuild()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if _hud and _hud.has_method("_try_recapture_mouse"):
		_hud.call("_try_recapture_mouse")


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != TOGGLE_KEY:
		return
	if _hud and (_hud.get("_chat_open") == true or _hud.get("_world_map_visible") == true):
		return
	toggle()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(_d: float) -> void:
	# Same rule as the HUD's own panels: recaptured mouse closes us
	if _open and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		close()


# ─── Data hooks ─────────────────────────────────────────────────────────

func _on_standing(s: Dictionary) -> void:
	QuestBoard.tier = int(s.get("tier", QuestBoard.tier))
	if _open:
		rebuild()


func _on_territory(_d: Dictionary) -> void:
	_report_visit()
	if _tracker:
		_tracker.refresh()
	if _open:
		rebuild()


func _report_visit() -> void:
	var a: String = GameManager.territory_address
	if HexUtils.is_valid_address(a):
		QuestBoard.report("visit_qing", {"qing": a.to_lower(), "name": GameManager.territory_name})


func _current_standing() -> Dictionary:
	if _standing and _standing.has_method("current"):
		return _standing.current()
	return {}


# ─── Content ────────────────────────────────────────────────────────────

func rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var s := _current_standing()
	var tier: int = s.get("tier", QuestBoard.tier)
	var streak := QuestBoard.streak()
	_title.text = "THINGS TO DO — %s" % DysnomiaLore.qing_label().to_upper()
	var st := "Standing: %s" % s.get("title", "?") if not s.is_empty() else "Standing: loading"
	if not s.is_empty():
		st += " (%d) · %s" % [int(s.get("score", 0)), s.get("fair", "")]
	_sub.text = "%s\nYou: %s · streak %d day%s (best %d) · new quests in %s" % [
		st, QuestBoard.selected_title(), streak["current"], "" if streak["current"] == 1 else "s",
		streak["best"], QuestBoard.reset_countdown()]

	# Quests
	_section("TODAY'S QING QUESTS", PINK)
	if streak["at_risk"]:
		_note("Your %d-day streak ends at 00:00 UTC — finish any quest to keep it." % streak["current"], GOLD)
	for q in QuestBoard.board()["quests"]:
		_body.add_child(_quest_row(q))

	# What's here
	_section("HERE IN THIS QING", PULSE.lightened(0.2))
	_item("Lunar Cantina", "Bar menu = your own AFFECTION calls (Pi, Rho, Generate…). Four game tables:", true)
	for i in TableRecordSigns.GAME_TYPES.size():
		var g: String = TableRecordSigns.GAME_TYPES[i]
		var rec := MinigameRecords.qing_record(g)
		var line := "unclaimed record" if rec.is_empty() else "record %d by %s" % [int(rec["score"]), rec["player"]]
		_note("   %s — %s · your best %d" % [TableRecordSigns.NAMES[i], line, MinigameRecords.personal_best(g)], DIM)
	if tier <= 0:
		_item("Surveyed Lot", "No fair yet. This QING needs Standing %d for a Night Market + Orbital Carousel." % QingStanding.TIERS[1]["min"], false)
	for f in FAIR_ITEMS:
		var have: bool = tier >= int(f["tier"])
		var why: String = f["what"] if have else "needs %s Standing" % QingStanding.TIERS[int(f["tier"])]["title"]
		_item(f["name"], why, have)
	_item("Monument", "Terraform with AFFECTION (T) — builds this QING's XIE charge", true)
	_item("Meta Resonance Array", "META.Beat(waat) — shake the ground", true)
	_item("Landing Pad", "Shuttle to any QING you've joined · World map (M)", true)
	_item("Guestbook & media boards", "Leave your mark (B)", true)

	# Standing
	_section("RAISE THIS QING'S STANDING", GOLD)
	_note("Standing is read from chain activity and is the same for every visitor. Quests, titles and Cantina scores don't change it — these do:", DIM)
	var parts: Dictionary = s.get("parts", {})
	_lever("Visitors who chat here", parts.get("visitors", 0.0), QingStanding.CAP_VISITORS,
		"Each LAU who chats in this QING counts. Bring friends (K invite).")
	_lever("Bar chatter", parts.get("chatter", 0.0), QingStanding.CAP_CHATTER, "Every chat message here (Enter).")
	_lever("Terraform charge (XIE)", parts.get("power", 0.0), QingStanding.CAP_POWER, "AFFECTION calls at the Monument build charge.")
	_lever("Keeper's bars (YUE)", parts.get("bars", 0.0), QingStanding.CAP_BARS, "The keeper's own Hypobar + Epibar in this QING.")
	if not s.is_empty():
		_note(QingStanding.unlock_hint(s) + ("" if s.get("next_unlock", "") == "" else " → " + s["next_unlock"]), GOLD)

	# Titles
	_section("TITLES", PINK)
	var shown := 0
	for t in QuestBoard.titles():
		if t["unlocked"]:
			continue
		_note("%s — %s  (%d/%d)" % [t["name"], t["desc"], t["progress"], t["need"]], DIM)
		shown += 1
		if shown >= 3:
			break
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	_body.add_child(row)
	for t in QuestBoard.titles():
		if not t["unlocked"]:
			continue
		var b := Button.new()
		b.text = t["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = t["desc"] + " — click to wear it"
		b.add_theme_font_size_override("font_size", 12)
		if t["name"] == QuestBoard.selected_title():
			b.add_theme_color_override("font_color", GOLD)
		var id: String = t["id"]
		b.pressed.connect(func(): QuestBoard.select_title(id))
		row.add_child(b)


func _section(text: String, color: Color) -> void:
	_body.add_child(_spacer(4))
	var l := _lbl(text, 14, color)
	_body.add_child(l)
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(color, 0.35)
	sep.add_theme_stylebox_override("separator", line)
	_body.add_child(sep)


func _note(text: String, color: Color) -> void:
	var l := _lbl(text, 12, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)


func _item(name: String, what: String, have: bool) -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_font_size_override("bold_font_size", 13)
	var mark := "[color=#73f29a]●[/color]" if have else "[color=#555566]○[/color]"
	l.text = "%s [b][color=%s]%s[/color][/b]  [color=#a8a8bc]%s[/color]" % [
		mark, "#e6e2ff" if have else "#77778a", name, what]
	_body.add_child(l)


func _lever(name: String, value: float, cap: float, how: String) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var top := HBoxContainer.new()
	v.add_child(top)
	var n := _lbl(name, 13, Color(0.92, 0.9, 1.0))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(n)
	top.add_child(_lbl("%d / %d" % [int(value), int(cap)], 12, GOLD))
	v.add_child(_bar(value / maxf(cap, 1.0), GOLD))
	var h := _lbl(how, 11, Color(0.62, 0.62, 0.72))
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(h)
	_body.add_child(v)


func _quest_row(q: Dictionary) -> Control:
	var p := PanelContainer.new()
	var done: bool = q["done"]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.22, 0.14, 0.6) if done else Color(0.12, 0.09, 0.2, 0.6)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 3
	sb.border_color = DysnomiaLore.OK if done else PINK
	sb.content_margin_left = 10
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := _lbl(("DONE  " if done else "") + str(q["text"]), 14, DysnomiaLore.OK if done else Color(0.95, 0.93, 1.0))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(t)
	top.add_child(_lbl("%d/%d" % [int(q["progress"]), int(q["target"])], 13, GOLD))
	v.add_child(_bar(float(q["progress"]) / maxf(1.0, float(q["target"])), DysnomiaLore.OK if done else PINK))
	v.add_child(_lbl(str(q.get("where", "")), 11, Color(0.6, 0.6, 0.72)))
	return p


func _bar(frac: float, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 6)
	b.max_value = 1.0
	b.step = 0.001
	b.value = clampf(frac, 0.0, 1.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.13, 0.24)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
