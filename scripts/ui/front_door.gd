extends Control
## The front door: the title screen. Behind it, the moon Dysnomia carrying every
## QING at its chain coordinates (FieldGlobe: warm halos are developed QINGs), under
## a sky whose faint Mandelbrot Field marks the featured QING's c; the featured
## QING's own Julia set sits in the corner card. Everything drawn is a real number.
##
## Four doors, in this order: Connect wallet · Explore without a wallet · Continue to
## my QING · The Field. Then a territory search, the Void (identity), opportunities,
## the guide and settings. Right: who you are (an AccessSteps path in until you can
## play as yourself; then your LAU, your QINGs and your YUE). Bottom: news and the
## status strip (chain block, QINGs, WORLD, online players when the Net server is up).
## Keyboard: the arrow keys move between the doors, Enter opens one.

const SETTINGS := preload("res://scripts/ui/settings_menu.gd")
const SKY := preload("res://assets/shaders/deep_field_sky.gdshader")
const LAST_PATH := "user://travel.cfg"
const PANELS := ["summary", "void", "identity", "guide", "opps"]

var rows: Array = []
var featured := {}           ## the QING in the sky (a developed one when the snapshot has some)
var featured_row := {}
var _globe: FieldGlobe
var _vp: SubViewport
var _cam: Camera3D
var _sky_mat: ShaderMaterial
var _emblem: DeepFieldView
var _search: LineEdit
var _status: Label
var _news: Label
var _strip := {}
var _btn := {}
var _right: VBoxContainer
var _panels := {}
var _summary: VBoxContainer
var _sum_emblem: DeepFieldView
var _sum_name: Label
var _sum_lines: Label
var _sum_qings: HFlowContainer
var _sum_state: Label
var _path: AccessSteps
var _card: IdentityCard
var _onboarding: OnboardingPanel
var _guide: GuidePanel
var _opps: OpportunitiesPanel
var _settings: PanelContainer
var _back: Button
var _left: VBoxContainer
var _t := 0.0
var _head_timer := 0.0
var _lead_news := ""


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	theme = DeepFieldTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	rows = FieldIndex.build(Registry.all())
	_pick_featured()
	_build_backdrop()
	_build_left()
	_build_right()
	_build_bottom()
	Session.changed.connect(_refresh_identity)
	Session.lead_changed.connect(_on_leads)
	Wallet.connected.connect(func(_a): _set_status(""))
	Registry.updated.connect(func(_n): _refresh_news())
	_refresh_identity()
	_refresh_news()
	_refresh_strip()
	if not Registry.catching_up:
		Registry.catch_up()
	World.start()
	World.changed.connect(_refresh_strip)
	if Net.has_signal("status_changed"):
		Net.status_changed.connect(func(_s): _refresh_strip())
	_read_head()
	# Arrival: fade the doors in; a step elsewhere may have asked for a panel
	_left.modulate.a = 0.0
	create_tween().tween_property(_left, "modulate:a", 1.0, 0.7).set_delay(0.15)
	if AccessSteps.front_door_open != "":
		open_panel(AccessSteps.front_door_open)
		AccessSteps.front_door_open = ""
	(func(): _primary_button().grab_focus()).call_deferred()


# --- The featured QING and the backdrop -------------------------------------------

func _pick_featured() -> void:
	var all: Array = Registry.all()
	if all.is_empty():
		return
	var dev := FieldIndex.query(rows, "", {"min_tier": 2})
	var r: Dictionary = dev[randi() % dev.size()] if not dev.is_empty() else rows[randi() % rows.size()]
	featured_row = r
	featured = all[int(r["i"])]


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = DeepFieldTheme.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY
	sky.sky_material = _sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.8)
	env.ambient_light_energy = 0.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.96, 0.9)
	_vp.add_child(sun)
	sun.look_at_from_position(Vector3(3.0, 1.1, -0.7), Vector3.ZERO, Vector3.UP)
	_globe = FieldGlobe.new()
	_vp.add_child(_globe)
	_globe.set_moon_tone(0.42)
	_globe.setup(Registry.all(), rows)
	var cols := PackedColorArray()
	for r in rows:
		cols.append(DeepFieldTheme.rarity_color(String(r["rarity"])) if String(r["rarity"]) != "" else DeepFieldTheme.MUTED)
	_globe.paint(cols, PackedByteArray(), -1, -1, _mine(), _last_visited())
	_globe.rotation = Vector3(0.32, 0.0, 0.0)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.position = Vector3(0, 0.0, 4.1)
	_cam.h_offset = -0.12
	_cam.v_offset = -0.02
	_vp.add_child(_cam)
	_cam.current = true
	if not featured.is_empty():
		var p := DeepField.for_territory(featured)
		var c: Array = p["c"]
		_sky_mat.set_shader_parameter("c", Vector2(c[0], c[1]))
		_sky_mat.set_shader_parameter("star_seed", float(BigInt.mod_int(BigInt.from_hex(String(featured["address"])), 9973)))
		_sky_mat.set_shader_parameter("field_strength", 0.2)
		_sky_mat.set_shader_parameter("field_dir", Vector3(-0.62, 0.42, -0.66).normalized())
		_sky_mat.set_shader_parameter("neb_a", Vector3(p["color"][0], p["color"][1], p["color"][2]) * 0.6)
		_sky_mat.set_shader_parameter("neb_b", Vector3(p["color2"][0], p["color2"][1], p["color2"][2]) * 0.6)
		_sky_mat.set_shader_parameter("eris_dir", Vector3(0.75, 0.55, -0.35).normalized())
	# Readability: a dark wash under the doors (left) and the strip (bottom).
	add_child(_wash(Vector2(1, 0), [0.0, 0.42, 0.62], [0.9, 0.55, 0.0]))
	add_child(_wash(Vector2(0, -1), [0.0, 0.2, 0.32], [0.85, 0.35, 0.0]))


func _wash(dir: Vector2, offs: Array, alphas: Array) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offs)
	var cs := PackedColorArray()
	for a in alphas:
		cs.append(Color(DeepFieldTheme.BLACK, a))
	g.colors = cs
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill_from = Vector2(0, 0) if dir.x > 0 else Vector2(0, 1)
	t.fill_to = Vector2(1, 0) if dir.x > 0 else Vector2(0, 0)
	var r := TextureRect.new()
	r.texture = t
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# --- Left: title and the doors ----------------------------------------------------

func _label(text: String, variation: String, size: int, wrap: bool = true) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _door(key: String, title: String, sub: String, call: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(620, 66)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "   " + title
	b.add_theme_font_override("font", DeepFieldTheme.display_font())
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(call)
	var s := _label(sub, "MutedLabel", 14, false)
	s.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	s.offset_left = -330
	s.offset_right = -20
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.clip_text = true
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.name = "Sub"
	b.add_child(s)
	_btn[key] = b
	return b


func _style_door(b: Button, primary: bool) -> void:
	if primary:
		var sb := DeepFieldTheme.panel_style(DeepFieldTheme.ICE)
		sb.bg_color = Color(0.66, 0.9, 1.0, 0.17)
		var sh := sb.duplicate()
		sh.bg_color = Color(0.66, 0.9, 1.0, 0.28)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("focus", sh)
		b.add_theme_color_override("font_color", DeepFieldTheme.ICE)
		(b.get_node("Sub") as Label).add_theme_color_override("font_color", DeepFieldTheme.INK)
	else:
		(b.get_node("Sub") as Label).remove_theme_color_override("font_color")
		for k in ["normal", "hover", "focus"]:
			b.remove_theme_stylebox_override(k)
		b.remove_theme_color_override("font_color")


func _set_sub(key: String, text: String) -> void:
	(_btn[key].get_node("Sub") as Label).text = text


func _build_left() -> void:
	_left = VBoxContainer.new()
	_left.position = Vector2(112, 92)
	_left.custom_minimum_size = Vector2(620, 0)
	_left.add_theme_constant_override("separation", 12)
	add_child(_left)
	var kicker := _label("PULSECHAIN 369  ·  A MOON THAT COMPUTES ITSELF", "MonoLabel", 14, false)
	kicker.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_left.add_child(kicker)
	var title := _label("DYSNOMIA", "DisplayLabel", 104, false)
	_left.add_child(title)
	var lede := _label("Every territory here is a real QING on PulseChain, drawn from its own numbers. Walk them, react, talk in their rooms, play at their fairs: every change you see was made by a real transaction.", "MutedLabel", 18)
	lede.custom_minimum_size = Vector2(600, 0)
	_left.add_child(lede)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_left.add_child(gap)
	_left.add_child(_door("wallet", "CONNECT WALLET", "MetaMask, Rabby… · a small window", _toggle_wallet))
	_left.add_child(_door("explore", "EXPLORE WITHOUT A WALLET", "", _explore))
	_left.add_child(_door("continue", "CONTINUE TO MY QING", "", _continue))
	_left.add_child(_door("field", "THE FIELD", "%d QINGs · search · filters" % Registry.count(), func(): Travel.field(get_tree())))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_left.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a QING: name, symbol, #n or 0x…"
	_search.custom_minimum_size = Vector2(0, 44)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_x): _go())
	row.add_child(_search)
	var go := Button.new()
	go.text = "Warp"
	go.custom_minimum_size = Vector2(84, 44)
	go.pressed.connect(_go)
	row.add_child(go)
	var rnd := Button.new()
	rnd.text = "Random"
	rnd.custom_minimum_size = Vector2(96, 44)
	rnd.pressed.connect(func(): Warp.to(get_tree(), Travel.random_address(get_tree())))
	row.add_child(rnd)
	var more := HBoxContainer.new()
	more.add_theme_constant_override("separation", 8)
	_left.add_child(more)
	for m in [["The Void · identity", func(): open_panel("void")], ["Opportunities", func(): open_panel("opps")],
			["Guide", func(): open_panel("guide")], ["Settings", _toggle_settings], ["Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = m[0]
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(m[1])
		more.add_child(b)
	_status = _label("", "MonoLabel", 13)
	_status.custom_minimum_size = Vector2(600, 0)
	_status.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_left.add_child(_status)


func _primary_button() -> Button:
	return _btn["continue"] if Session.wallet != "" and not _btn["continue"].disabled else _btn["wallet"]


func _set_status(t: String) -> void:
	_status.text = t


# --- Right: who you are -------------------------------------------------------------

func _build_right() -> void:
	_right = VBoxContainer.new()
	_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right.position = Vector2(-112 - 600, 92)
	_right.custom_minimum_size = Vector2(600, 0)
	_right.add_theme_constant_override("separation", 10)
	add_child(_right)
	_back = Button.new()
	_back.text = "←  Back"
	_back.visible = false
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(func(): open_panel("summary"))
	_right.add_child(_back)
	# The summary: your identity (connected) and the path in (AccessSteps)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 10)
	_right.add_child(_summary)
	var idp := PanelContainer.new()
	_summary.add_child(idp)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	idp.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	col.add_child(top)
	_sum_emblem = DeepFieldView.new()
	_sum_emblem.custom_minimum_size = Vector2(104, 104)
	_sum_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_sum_emblem)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var k := _label("WHO YOU ARE", "MutedLabel", 11, false)
	k.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	info.add_child(k)
	_sum_name = _label("", "DisplayLabel", 24)
	info.add_child(_sum_name)
	_sum_lines = _label("", "MonoLabel", 13)
	info.add_child(_sum_lines)
	_sum_state = _label("", "MonoLabel", 13)
	col.add_child(_sum_state)
	_sum_qings = HFlowContainer.new()
	_sum_qings.add_theme_constant_override("h_separation", 6)
	_sum_qings.add_theme_constant_override("v_separation", 6)
	col.add_child(_sum_qings)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	col.add_child(brow)
	var full := Button.new()
	full.text = "Avatar & holdings"
	full.pressed.connect(func(): open_panel("identity"))
	brow.add_child(full)
	var fld := Button.new()
	fld.text = "My QINGs on the Field"
	fld.pressed.connect(func(): Travel.field(get_tree()))
	brow.add_child(fld)
	_panels["summary_id"] = idp
	_path = AccessSteps.new()
	_path.compact = true
	_path.custom_minimum_size = Vector2(600, 0)
	_summary.add_child(_path)
	_path.show_goal("identity", {"title": "Play as yourself", "subtitle": "Reading and exploring need no wallet. To react, talk and play, these come first; each one is checked on chain."},
		{"void": func(): open_panel("void"), "yue": func(): open_panel("void"), "front_door": func(): open_panel("identity")})
	_panels["summary"] = _summary
	_card = IdentityCard.new()
	_card.visible = false
	_right.add_child(_card)
	_panels["identity"] = _card
	_onboarding = OnboardingPanel.new()
	_onboarding.visible = false
	_right.add_child(_onboarding)
	_panels["void"] = _onboarding
	_guide = GuidePanel.new()
	_right.add_child(_guide)
	_panels["guide"] = _guide
	_opps = OpportunitiesPanel.new()
	_right.add_child(_opps)
	_panels["opps"] = _opps


## Shows one panel on the right ("summary" | "void" | "identity" | "guide" | "opps").
## AccessSteps sends players here for the Void and their holdings.
func open_panel(which: String) -> void:
	if which == "":
		which = "summary"
	for k in PANELS:
		var p: Control = _panels[k]
		var on: bool = k == which
		if k == "guide" or k == "opps":
			if on != p.visible:
				p.toggle()
		else:
			p.visible = on
	_back.visible = which != "summary"
	if which == "summary":
		_refresh_identity()


func _mine() -> Dictionary:
	var m := {}
	for a in Session.bars:
		m[String(a).to_lower()] = true
	return m


func _refresh_identity() -> void:
	var w := Session.wallet
	var connected := w != ""
	# Doors
	_btn["wallet"].text = "   " + ("WALLET  " + AccessGates.short(w) if connected else "CONNECT WALLET")
	_set_sub("wallet", "disconnect" if connected else "MetaMask, Rabby… · a small window")
	_btn["explore"].text = "   " + ("EXPLORE" if connected else "EXPLORE WITHOUT A WALLET")
	_set_sub("explore", ("%s · %s" % [String(featured.get("name", "—")), FieldIndex.tier_text(featured_row)]) if not featured.is_empty() else "—")
	var tgt := _continue_target()
	_btn["continue"].disabled = tgt.is_empty()
	_set_sub("continue", ("%s · %s" % [String(Registry.get_territory(tgt["address"]).get("name", "—")), tgt["why"]]) if not tgt.is_empty()
		else ("no bars yet: one Su makes a QING yours" if connected else "connect, or visit a QING first"))
	_style_door(_btn["wallet"], not connected)
	_style_door(_btn["continue"], connected and not tgt.is_empty())
	# Who you are
	var idp: Control = _panels["summary_id"]
	idp.visible = connected
	var ps: PlayerState = Session.player
	var complete := connected and ps != null and ps.ok and ps.has_lau() and ps.has_yue()
	_path.visible = not complete
	if not connected:
		return
	_sum_emblem.apply_params(DeepField.for_identity(w), "Your Aura, uint160(wallet) % 953,467,954,114,363 (the contract's formula), drawn as a Julia set.")
	if ps == null:
		_sum_name.text = "READING…"
		_sum_lines.text = "wallet %s\nLAU    checking…\nYUE    checking…" % AccessGates.short(w)
		_sum_state.text = ""
		_fill_qings([])
		return
	if ps.error != "":
		_sum_name.text = "—"
		_sum_lines.text = "wallet %s\nYour identity could not be read: %s" % [AccessGates.short(w), ps.error]
		return
	_sum_name.text = (ps.username if ps.username != "" else ("(no username)" if ps.has_lau() else "NO LAU YET")).to_upper()
	_sum_lines.text = "wallet %s\nLAU    %s%s\nYUE    %s\nblock  %d" % [AccessGates.short(w),
		AccessGates.short(ps.lau) if ps.has_lau() else "— (none registered)",
		("  %s · %s" % [ps.lau_name, ps.lau_symbol]) if ps.has_lau() and ps.lau_name != "" else "",
		AccessGates.short(ps.yue) if ps.has_yue() else "— (not started)", ps.block]
	var mine: Array = []
	for a in Session.bars:
		mine.append([String(a).to_lower(), Session.bars[a][0]])
	mine.sort_custom(func(x, y): return BigInt.cmp(x[1], y[1]) > 0)
	var rd: Readiness = Session.readiness
	var lines: PackedStringArray = []
	if ps.has_yue():
		lines.append("QINGs  %s with your bars%s%s" % [str(mine.size()) if Session.bars_block > 0 else "—",
			(" · leading %d (known players)" % Session.leading.size()) if not Session.leading.is_empty() else "",
			(" · block %d" % Session.bars_block) if Session.bars_block > 0 else " · checking…"])
	if rd != null:
		lines.append("WORLD  %s" % {"no-account": "no account", "not-started": "not started", "blocked": "blocked",
			"not-ready": "not ready", "fragile": "ready · fragile", "ready": "ready"}.get(rd.state, rd.state))
	if Session.record != null:
		lines.append(Session.record.describe())
	_sum_state.text = "\n".join(lines)
	_fill_qings(mine.slice(0, 4))


func _fill_qings(top: Array) -> void:
	for c in _sum_qings.get_children():
		c.queue_free()
	for m in top:
		var q: Dictionary = Registry.get_territory(m[0])
		var b := Button.new()
		b.text = "%s  ·  %s Hypobar" % [String(q.get("name", AccessGates.short(m[0]))), TokenFormat.group(BigInt.to_decimal(m[1]))]
		b.tooltip_text = "YUE.Bar(%s) at block %d. Warp there." % [m[0], Session.bars_block]
		b.pressed.connect(func(): Warp.to(get_tree(), m[0]))
		_sum_qings.add_child(b)


# --- The doors' actions -------------------------------------------------------------

func _explore() -> void:
	if featured.is_empty():
		_set_status("The registry is empty: —")
		return
	Warp.to(get_tree(), String(featured["address"]))


static func _last_visited() -> String:
	var c := ConfigFile.new()
	if c.load(LAST_PATH) != OK:
		return ""
	return String(c.get_value("travel", "last_qing", "")).to_lower()


## Where "Continue" goes: the QING you were last in (this machine), else your
## biggest bar, else one your wallet founded. {} when there is none.
func _continue_target() -> Dictionary:
	var last := _last_visited()
	if last != "" and Registry.has_territory(last):
		return {"address": last, "why": "last visited"}
	var best := ""
	var best_v := PackedInt64Array()
	for a in Session.bars:
		var hv: PackedInt64Array = Session.bars[a][0]
		if best == "" or BigInt.cmp(hv, best_v) > 0:
			best = String(a).to_lower()
			best_v = hv
	if best != "":
		return {"address": best, "why": "your biggest bar"}
	if Session.wallet != "":
		for r in rows:
			if String(r["creator"]) == Session.wallet:
				return {"address": r["address"], "why": "you founded it"}
	return {}


func _continue() -> void:
	var t := _continue_target()
	if not t.is_empty():
		Warp.to(get_tree(), String(t["address"]))


func _go() -> void:
	var addr := Travel.resolve(get_tree(), _search.text)
	if addr == "":
		_set_status("No QING matches \"%s\". The Field has search with filters." % _search.text)
		return
	Warp.to(get_tree(), addr)


func _toggle_wallet() -> void:
	if Session.wallet != "":
		Wallet.disconnect_wallet()
	elif Wallet.connect_wallet():
		_set_status("A wallet window opened in your browser. Approve the connection there.")
	else:
		_set_status("Could not start the local wallet relay (ports %d+ busy?)." % Config.wallet_bridge_port)


func _toggle_settings() -> void:
	if _settings == null:
		_settings = PanelContainer.new()
		_settings.set_script(SETTINGS)
		_settings.visible = false
		add_child(_settings)
		_settings.settings_closed.connect(func(): _settings.hide_menu())
	if _settings.visible:
		_settings.hide_menu()
	else:
		_settings.show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("settings"):
		get_viewport().set_input_as_handled()
		_toggle_settings()
	elif event.is_action_pressed("ui_cancel") and _back.visible:
		get_viewport().set_input_as_handled()
		open_panel("summary")


# --- Bottom: news, the featured QING, the status strip ------------------------------

func _build_bottom() -> void:
	# The featured QING (its own Julia set), bottom right
	var fc := PanelContainer.new()
	fc.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fc.position = Vector2(-112 - 600, -112 - 150)
	fc.custom_minimum_size = Vector2(600, 0)
	add_child(fc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	fc.add_child(row)
	_emblem = DeepFieldView.new()
	_emblem.custom_minimum_size = Vector2(118, 118)
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_emblem)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var k := _label("IN THE SKY TONIGHT", "MutedLabel", 11, false)
	k.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	col.add_child(k)
	var nm := _label(String(featured.get("name", "—")).to_upper(), "DisplayLabel", 17)
	col.add_child(nm)
	var p := DeepField.for_territory(featured) if not featured.is_empty() else {}
	var facts := _label("", "MonoLabel", 12)
	if not featured.is_empty():
		facts.text = "%s · %s · reactors %s%s\nThe sky's faint Field marks its c; its Julia set is this picture and its ground." % [
			String(p["tier"]), FieldIndex.tier_text(featured_row), FieldIndex.reactors_text(featured_row),
			(" (snapshot block %d)" % int(featured_row["dev_block"])) if int(featured_row["dev_block"]) > 0 else ""]
		_emblem.apply_params(p, DeepField.describe(p, "QING.Entropy()", String(featured["entropy"]), String(featured["address"])))
		nm.add_theme_color_override("font_color", DeepFieldTheme.rarity_color(String(p["tier"])))
	col.add_child(facts)
	var go := Button.new()
	go.text = "Explore it"
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	go.pressed.connect(_explore)
	col.add_child(go)
	# News, bottom left
	_news = _label("", "MonoLabel", 13)
	_news.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_news.position = Vector2(112, -112 - 92)
	_news.custom_minimum_size = Vector2(960, 0)
	add_child(_news)
	# The status strip
	var strip := PanelContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = 112
	strip.offset_right = -112
	strip.offset_top = -92
	strip.offset_bottom = -40
	add_child(strip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	strip.add_child(h)
	for key in ["chain", "qings", "world", "online"]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cell)
		var t := _label(key.to_upper() if key != "qings" else "QINGS", "MutedLabel", 10, false)
		t.add_theme_color_override("font_color", DeepFieldTheme.DIM)
		cell.add_child(t)
		var v := _label("checking…", "MonoLabel", 13, false)
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.clip_text = true
		cell.add_child(v)
		_strip[key] = v


func _refresh_strip() -> void:
	if _strip.is_empty():
		return
	_strip["chain"].text = ("PulseChain · block %s" % TokenFormat.group(str(Chain.head_block))) if Chain.head_block > 0 else "PulseChain · block —"
	_strip["qings"].text = "%d · NewQing logs to block %s%s" % [Registry.count(), TokenFormat.group(str(Registry.cursor_block)), " · catching up…" if Registry.catching_up else ""]
	_strip["world"].text = World.headline().trim_prefix("WORLD: ")
	_strip["world"].tooltip_text = World.headline()
	var online := Net.is_online()
	_strip["online"].text = ("%d online · %s" % [Net.client.peers.size() + 1, Net.client.server_name]) if online else Net.status_text()
	_strip["online"].tooltip_text = Net.status_text()


func _refresh_news() -> void:
	var parts: PackedStringArray = []
	var all: Array = Registry.all()
	if not all.is_empty():
		var newest: Dictionary = all[all.size() - 1]
		parts.append("Newest QING: %s (#%d, founded at block %s)" % [String(newest.get("name", "—")), all.size(), TokenFormat.group(str(int(newest.get("block", 0))))])
	var dev := FieldIndex.developed(rows)
	if not dev.is_empty():
		var top: Dictionary = dev[0]
		parts.append("Most developed: %s (%s, %s reactors) · %d developed of %d (snapshot block %s)" % [String(top["name"]), FieldIndex.tier_text(top),
			FieldIndex.reactors_text(top), dev.size(), rows.size(), TokenFormat.group(str(DevelopmentSnapshot.shipped_block()))])
	if _lead_news != "":
		parts.append(_lead_news)
	_news.text = "NEWS   " + "\n          ".join(parts)


func _on_leads(lost: Array, gained: Array, block: int) -> void:
	var parts: PackedStringArray = []
	for a in lost:
		parts.append("lost the lead at %s" % String(Registry.get_territory(a).get("name", a)))
	for a in gained:
		parts.append("took the lead at %s" % String(Registry.get_territory(a).get("name", a)))
	_lead_news = "Since you were last here (block %d): %s." % [block, "; ".join(parts)]
	_refresh_news()


func _read_head() -> void:
	await Chain.refresh_head()
	_refresh_strip()


func _process(delta: float) -> void:
	_t += delta
	if _globe:
		_globe.rotation.y = _t * 0.025
	_head_timer += delta
	if _head_timer > 10.0:
		_head_timer = 0.0
		_read_head()
	if _emblem and not _emblem.params.is_empty():
		var p: Dictionary = _emblem.params
		_emblem.set_view(Vector2.ZERO, float(p["extent"]) * (1.0 + 0.1 * sin(_t * 0.09)), float(p["rotation"]) + _t * 0.012)
