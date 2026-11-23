class_name AttractionUI
extends CanvasLayer
## On-screen layer for attractions: ticket card at ride booths, the bar menu, big ride
## captions, and the "QING BARS" report showing the visitor's measured Hypobar/Epibar
## change after an on-chain purchase. Driven entirely by AttractionDirector.

signal drink_chosen(item: Dictionary)

const ACCENT := Color(0.95, 0.42, 0.72)      # AFFECTION pink
const PULSE := Color(0.62, 0.42, 1.0)        # PulseChain purple
const OK := Color(0.45, 0.95, 0.6)
const BAD := Color(1.0, 0.42, 0.4)
const DIM := Color(0.75, 0.75, 0.82)

var _card: PanelContainer
var _card_title: Label
var _card_price: Label
var _card_blurb: Label
var _card_cost: Label
var _card_meta: Label
var _card_action: Label
var _card_status: Label

var _menu: PanelContainer
var _menu_list: VBoxContainer
var _menu_status: Label
var _menu_items: Array = []

var _caption: Label
var _caption_tween: Tween

var _report: PanelContainer
var _report_body: RichTextLabel
var _report_timer: float = 0.0

var _toast: Label
var _toast_timer: float = 0.0

var _standing: PanelContainer
var _standing_body: RichTextLabel
var _standing_timer: float = 0.0
var _standing_last_tier: int = -1


func _ready() -> void:
	layer = 20
	_build_card()
	_build_menu()
	_build_caption()
	_build_report()
	_build_toast()
	_build_standing()


func _process(delta: float) -> void:
	if _report_timer > 0.0:
		_report_timer -= delta
		if _report_timer <= 0.0:
			_fade_out(_report)
	if _standing_timer > 0.0:
		_standing_timer -= delta
		if _standing_timer <= 0.0:
			_fade_out(_standing)
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_fade_out(_toast)


func _input(event: InputEvent) -> void:
	# Number keys order drinks while the bar menu is open (consumed so weapons don't swap)
	if not _menu.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_9:
		var idx := k - KEY_1
		if idx < _menu_items.size():
			drink_chosen.emit(_menu_items[idx])
			get_viewport().set_input_as_handled()


# ─── Ticket card ────────────────────────────────────────────────────────

func show_ticket(item: Dictionary, cost_line: String, balance: String, bars_line: String) -> void:
	_card_title.text = str(item.get("name", "Attraction")).to_upper()
	_card_price.text = AttractionCatalog.price_label(item)
	_card_blurb.text = str(item.get("blurb", ""))
	_card_cost.text = cost_line
	_card_meta.text = "Balance  %s AFFECTION     %s" % [balance, bars_line]
	_card_action.text = "[E]  Buy ticket & ride"
	_card_action.visible = true
	set_ticket_status("", DIM)
	_fade_in(_card)


func set_ticket_status(text: String, color: Color = DIM) -> void:
	_card_status.text = text
	_card_status.visible = not text.is_empty()
	_card_status.add_theme_color_override("font_color", color)
	_card_action.visible = text.is_empty() or color == BAD


func hide_ticket() -> void:
	_fade_out(_card)


func is_ticket_visible() -> bool:
	return _card.visible


# ─── Bar menu ───────────────────────────────────────────────────────────

func show_bar_menu(title: String, items: Array, footer: String) -> void:
	_menu_items = items
	for c in _menu_list.get_children():
		c.queue_free()
	var head := _label(title.to_upper(), 20, ACCENT)
	_menu_list.add_child(head)
	_menu_list.add_child(_label("Every drink is a real on-chain call. Your Hypobar/Epibar here are re-read after it lands.", 13, DIM, true))
	for i in items.size():
		var it: Dictionary = items[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var key := _label("[%d]" % (i + 1), 16, PULSE)
		key.custom_minimum_size.x = 34
		row.add_child(key)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label(str(it.get("name", "")), 16, Color.WHITE))
		col.add_child(_label(str(it.get("blurb", "")), 12, DIM, true))
		row.add_child(col)
		var price := _label(AttractionCatalog.price_label(it), 13, ACCENT)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(price)
		_menu_list.add_child(row)
	_menu_list.add_child(_label(footer, 12, DIM, true))
	set_menu_status("", DIM)
	_fade_in(_menu)


func set_menu_status(text: String, color: Color = DIM) -> void:
	_menu_status.text = text
	_menu_status.visible = not text.is_empty()
	_menu_status.add_theme_color_override("font_color", color)


func hide_bar_menu() -> void:
	_fade_out(_menu)


# ─── Captions / report / toast ──────────────────────────────────────────

func set_caption(text: String) -> void:
	if _caption_tween:
		_caption_tween.kill()
	if text.is_empty():
		_fade_out(_caption)
		return
	_kill_fade(_caption)
	_caption.text = text
	_caption.visible = true
	_caption.modulate.a = 1.0
	_caption.scale = Vector2(1.25, 1.25)
	_caption.pivot_offset = _caption.size * 0.5
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_bar_report(report: Dictionary, qing_label: String) -> void:
	var item: Dictionary = report.get("item", {})
	var dh: int = report.get("d_hypo", 0)
	var de: int = report.get("d_epi", 0)
	var t := "[color=#%s][b]QING BARS[/b][/color]  [color=#bbbbcc]%s · after %s[/color]\n" % [
		ACCENT.to_html(false), qing_label, item.get("name", "your order")]
	t += _bar_row("HYPOBAR", report.get("hypo_before", 0), report.get("hypo_after", 0), dh)
	t += _bar_row("EPIBAR", report.get("epi_before", 0), report.get("epi_after", 0), de)
	if dh == 0 and de == 0:
		t += "[color=#bbbbcc]No change to your bars from this one — they move with your AFFECTION calls here.[/color]"
	elif not report.get("baseline_known", true):
		t += "[color=#bbbbcc]First reading for this QING — change shown from zero.[/color]"
	_report_body.text = t
	_report_timer = 9.0
	_fade_in(_report)


func toast(text: String, color: Color = Color.WHITE, seconds: float = 4.0) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_timer = seconds
	_fade_in(_toast)


func show_standing(s: Dictionary, qing_name: String) -> void:
	## Arrival banner: this QING's Standing, what it has, and what it needs next.
	## Shown on the first reading and whenever the tier changes.
	if s.get("tier", 0) == _standing_last_tier:
		return
	var promoted: bool = _standing_last_tier >= 0 and s["tier"] > _standing_last_tier
	_standing_last_tier = s["tier"]
	var name := qing_name if not qing_name.is_empty() else "This QING"
	var t := "[color=#%s][b]%s[/b][/color]   [color=#bbbbcc]QING STANDING[/color]\n" % [PULSE.to_html(false), name.to_upper()]
	if promoted:
		t += "[color=#%s][b]PROMOTED![/b][/color]  " % OK.to_html(false)
	t += "[b]%d[/b] · %s · Affection Fair: [b]%s[/b]\n" % [s["score"], s["title"], s["fair"]]
	if s.get("next_tier", -1) >= 0:
		t += "[color=#bbbbcc]%d more to reach %s → %s.  %s[/color]" % [
			s["next_min"] - s["score"], s["next_title"], s["next_unlock"], s["best_lever"]]
	else:
		t += "[color=#bbbbcc]Top tier — one of the best QINGs on Dysnomia.[/color]"
	_standing_body.text = t
	_standing_timer = 10.0
	_fade_in(_standing)


static func format_big(v: int) -> String:
	var a := absi(v)
	var s := ""
	if a >= 1_000_000_000_000:
		s = "%.2fT" % (a / 1e12)
	elif a >= 1_000_000_000:
		s = "%.2fB" % (a / 1e9)
	elif a >= 1_000_000:
		s = "%.2fM" % (a / 1e6)
	elif a >= 10_000:
		s = "%.1fK" % (a / 1e3)
	else:
		s = str(a)
	return ("-" if v < 0 else "") + s


func _bar_row(name: String, before: int, after: int, delta: int) -> String:
	var col := OK if delta > 0 else (BAD if delta < 0 else DIM)
	var sign := "+" if delta > 0 else ""
	return "[b]%s[/b]  %s → [b]%s[/b]   [color=#%s]%s%s[/color]\n" % [
		name.rpad(8), format_big(before), format_big(after), col.to_html(false), sign, format_big(delta)]


# ─── Construction ───────────────────────────────────────────────────────

func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.08, 0.86)
	sb.border_color = border
	sb.border_width_left = 4
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_top_left = 2
	sb.corner_radius_bottom_left = 2
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 12
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _label(text: String, size: int, color: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 1)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_card() -> void:
	_card = _panel(ACCENT)
	_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.offset_left = -520
	_card.offset_right = -32
	_card.offset_top = -300
	_card.offset_bottom = -150
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_card.add_child(v)
	var top := HBoxContainer.new()
	_card_title = _label("", 22, Color.WHITE)
	_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_card_title)
	_card_price = _label("", 18, ACCENT)
	top.add_child(_card_price)
	v.add_child(top)
	_card_blurb = _label("", 14, DIM, true)
	v.add_child(_card_blurb)
	_card_cost = _label("", 14, Color(1, 0.88, 0.95), true)
	v.add_child(_card_cost)
	_card_meta = _label("", 12, DIM, true)
	v.add_child(_card_meta)
	_card_action = _label("", 18, OK)
	v.add_child(_card_action)
	_card_status = _label("", 14, DIM, true)
	v.add_child(_card_status)


func _build_menu() -> void:
	_menu = _panel(PULSE)
	_menu.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_menu.offset_left = -560
	_menu.offset_right = -32
	_menu.offset_top = -260
	_menu.offset_bottom = 260
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_menu.add_child(v)
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 8)
	v.add_child(_menu_list)
	_menu_status = _label("", 14, DIM, true)
	v.add_child(_menu_status)


func _build_caption() -> void:
	_caption = _label("", 64, Color.WHITE)
	_caption.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.12, 0.9))
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_caption.offset_left = -500
	_caption.offset_right = 500
	_caption.offset_top = 120
	_caption.offset_bottom = 210
	_caption.visible = false
	add_child(_caption)


func _build_report() -> void:
	_report = _panel(OK)
	_report.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_report.offset_left = -470
	_report.offset_right = -32
	_report.offset_top = 150
	_report.offset_bottom = 290
	_report_body = RichTextLabel.new()
	_report_body.bbcode_enabled = true
	_report_body.fit_content = true
	_report_body.scroll_active = false
	_report_body.custom_minimum_size = Vector2(400, 0)
	_report_body.add_theme_font_size_override("normal_font_size", 15)
	_report_body.add_theme_font_size_override("bold_font_size", 15)
	_report_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_report.add_child(_report_body)


func _build_standing() -> void:
	_standing = _panel(PULSE)
	_standing.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_standing.offset_left = -330
	_standing.offset_right = 330
	_standing.offset_top = 24
	_standing.offset_bottom = 120
	_standing_body = RichTextLabel.new()
	_standing_body.bbcode_enabled = true
	_standing_body.fit_content = true
	_standing_body.scroll_active = false
	_standing_body.custom_minimum_size = Vector2(620, 0)
	_standing_body.add_theme_font_size_override("normal_font_size", 15)
	_standing_body.add_theme_font_size_override("bold_font_size", 15)
	_standing_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standing.add_child(_standing_body)


func _build_toast() -> void:
	_toast = _label("", 18, Color.WHITE, true)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.offset_top = -230
	_toast.offset_bottom = -180
	_toast.visible = false
	add_child(_toast)


func _fade_in(c: CanvasItem) -> void:
	_kill_fade(c)
	if not c.visible:
		c.modulate.a = 0.0
	c.visible = true
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.18)
	c.set_meta("fade_tween", tw)


func _fade_out(c: CanvasItem) -> void:
	if not c.visible:
		return
	_kill_fade(c)
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: c.visible = false)
	c.set_meta("fade_tween", tw)


func _kill_fade(c: CanvasItem) -> void:
	if c.has_meta("fade_tween"):
		var old: Tween = c.get_meta("fade_tween")
		if old and old.is_valid():
			old.kill()
