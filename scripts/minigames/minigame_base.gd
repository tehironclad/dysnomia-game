class_name MinigameBase
extends PanelContainer
## Base class for all Cantina table games.
## Dark translucent panel, PulseChain-purple header with the QING name, a score strip with
## personal best and the QING record, juice helpers (punch, shake, floating numbers, sfx)
## and an end-of-game results card with "play again".
##
## Subclasses: call _init_ui() in _ready, build into _content_vbox, call _update_score() /
## _set_score(), and finish(won, extra) when a game is over. The manager answers with
## show_result() once records and quests are tallied. Scores are fun-only: nothing here
## mints, pays or touches the chain.

signal game_started
signal game_ended(score: int)
signal game_result(result: Dictionary)   # {score, won, ...extra}
signal game_closed
signal replay_requested

const PULSE := DysnomiaLore.PULSE
const PINK := DysnomiaLore.AFFECTION_PINK
const GOLD := DysnomiaLore.GOLD

var _score: int = 0
var _score_label: Label
var _best_label: Label
var _record_label: Label
var _subtitle_label: Label
var _high_score: int = 0
var _qing_record: Dictionary = {}
var _game_name: String = "Minigame"
var _game_type: String = ""
var _score_unit: String = "pts"
var _content_vbox: VBoxContainer
var _fx_layer: Control
var _result_card: PanelContainer
var _result_body: RichTextLabel
var _finished: bool = false
var _shake_t: float = 0.0
var _shake_mag: float = 0.0


func _init_ui(title: String, subtitle: String = "", panel_size: Vector2 = Vector2(500, 600)) -> void:
	_game_name = title
	add_theme_stylebox_override("panel", DysnomiaLore.styled_panel(Color(PULSE, 0.75)))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = panel_size
	# Anchored at screen centre; offsets are relative to that anchor, growing both ways
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	offset_left = -panel_size.x * 0.5
	offset_right = panel_size.x * 0.5
	offset_top = -panel_size.y * 0.5
	offset_bottom = panel_size.y * 0.5

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	outer.add_child(_build_header(title, subtitle))

	# Score strip: score · best · QING record
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 14)
	outer.add_child(strip)
	_score_label = _label("0", 22, GOLD)
	strip.add_child(_score_label)
	_best_label = _label("", 12, DysnomiaLore.DIM)
	_best_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_best_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip.add_child(_best_label)
	_record_label = _label("", 12, PINK)
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_record_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip.add_child(_record_label)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _line_style(Color(PULSE, 0.35)))
	outer.add_child(sep)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_vbox.add_theme_constant_override("separation", 6)
	outer.add_child(_content_vbox)

	# Free-positioned layer for floating numbers (a plain Control, so no container layout)
	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	_build_result_card()
	_refresh_strip()


func _build_header(title: String, subtitle: String = "") -> Control:
	var header := HBoxContainer.new()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	header.add_child(col)
	var title_lbl := _label(title.to_upper(), 22, PULSE.lightened(0.2))
	col.add_child(title_lbl)
	_subtitle_label = _label(subtitle if not subtitle.is_empty() else DysnomiaLore.qing_label(), 12, DysnomiaLore.DIM)
	col.add_child(_subtitle_label)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.pressed.connect(func(): game_closed.emit())
	header.add_child(close_btn)
	return header


func _build_result_card() -> void:
	_result_card = PanelContainer.new()
	_result_card.visible = false
	_result_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := DysnomiaLore.styled_panel(Color(GOLD, 0.8), 10, 0.97)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 28
	_result_card.add_theme_stylebox_override("panel", sb)
	add_child(_result_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_card.add_child(v)
	_result_body = RichTextLabel.new()
	_result_body.bbcode_enabled = true
	_result_body.fit_content = true
	_result_body.scroll_active = false
	_result_body.add_theme_font_size_override("normal_font_size", 15)
	_result_body.add_theme_font_size_override("bold_font_size", 15)
	v.add_child(_result_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var again := _button("PLAY AGAIN", PULSE)
	again.pressed.connect(func(): replay_requested.emit())
	row.add_child(again)
	var leave := _button("LEAVE TABLE", Color(0.5, 0.5, 0.6))
	leave.pressed.connect(func(): game_closed.emit())
	row.add_child(leave)


# ─── Score / records ────────────────────────────────────────────────────

func _update_score(points: int) -> void:
	_score += points
	_refresh_strip()
	if points != 0 and _score_label:
		_punch(_score_label, 0.25 if absi(points) < 200 else 0.5)


func _set_score(v: int) -> void:
	_score = v
	_refresh_strip()


func _set_high_score(hs: int) -> void:
	_high_score = hs
	_refresh_strip()


func set_records(personal_best: int, qing_record: Dictionary) -> void:
	_high_score = personal_best
	_qing_record = qing_record
	_refresh_strip()


func _refresh_strip() -> void:
	if not _score_label:
		return
	_score_label.text = "%d %s" % [_score, _score_unit]
	_best_label.text = "Your best %d" % _high_score
	if _qing_record.is_empty():
		_record_label.text = "QING record: unclaimed"
	else:
		_record_label.text = "QING record %d · %s" % [int(_qing_record.get("score", 0)), str(_qing_record.get("player", "?"))]
	if _score > _high_score and _high_score > 0:
		_score_label.add_theme_color_override("font_color", DysnomiaLore.OK)
	else:
		_score_label.add_theme_color_override("font_color", GOLD)


func start_game() -> void:
	_score = 0
	_finished = false
	_refresh_strip()
	game_started.emit()


func end_game() -> void:
	## Legacy entry point — a finished game with no win/lose verdict.
	finish(false)


func finish(won: bool, extra: Dictionary = {}) -> void:
	if _finished:
		return
	_finished = true
	var r := extra.duplicate()
	r["score"] = _score
	r["won"] = won
	game_ended.emit(_score)
	game_result.emit(r)


func show_result(info: Dictionary) -> void:
	## Called by the manager after records + quests are tallied.
	##   info: {headline, lines: [String], personal_best, qing_record, quests: [quest], title}
	var t := "[center][font_size=26][color=%s][b]%s[/b][/color][/font_size]\n" % [
		DysnomiaLore.color_hex(GOLD), info.get("headline", "Game over")]
	t += "[font_size=34][color=#ffffff]%d %s[/color][/font_size]\n" % [_score, _score_unit]
	for line in info.get("lines", []):
		t += "[color=#c8c8d8]%s[/color]\n" % line
	if info.get("qing_record", false):
		t += "\n[color=%s][b]NEW QING RECORD[/b][/color]\n[color=#c8c8d8]Your name is on the %s table.[/color]\n" % [
			DysnomiaLore.color_hex(PINK), DysnomiaLore.qing_label()]
	elif info.get("personal_best", false):
		t += "\n[color=%s][b]NEW PERSONAL BEST[/b][/color]\n" % DysnomiaLore.color_hex(DysnomiaLore.OK)
	elif int(info.get("rank", -1)) > 0:
		t += "\n[color=#c8c8d8]#%d on this QING's board[/color]\n" % (int(info["rank"]) + 1)
	for q in info.get("quests", []):
		t += "\n[color=%s]Quest complete: %s[/color]" % [DysnomiaLore.color_hex(PULSE.lightened(0.3)), q.get("text", "")]
	if not str(info.get("title", "")).is_empty():
		t += "\n[color=%s]Title unlocked: %s[/color]" % [DysnomiaLore.color_hex(GOLD), info["title"]]
	t += "\n\n[font_size=11][color=#77778a]Cantina scores are for bragging rights only. No tokens are won or lost.[/color][/font_size][/center]"
	_result_body.text = t
	for f in _fx_layer.get_children():
		f.queue_free()
	_result_card.visible = true
	_result_card.modulate.a = 0.0
	_result_card.scale = Vector2(0.92, 0.92)
	_result_card.pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_result_card, "modulate:a", 1.0, 0.25)
	tw.tween_property(_result_card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if info.get("qing_record", false) or info.get("personal_best", false):
		_sfx("big")


# ─── Juice ──────────────────────────────────────────────────────────────

func _sfx(cue: String, pitch: float = 1.0) -> void:
	MinigameSfx.play(self, cue, -10.0, pitch)


func _punch(c: Control, amount: float = 0.3) -> void:
	if not is_inside_tree() or c == null:
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _shake(mag: float = 8.0, dur: float = 0.3) -> void:
	_shake_mag = mag
	_shake_t = dur


func _float_text(text: String, color: Color, from: Control = null, font_size: int = 26) -> void:
	if not is_inside_tree() or _fx_layer == null:
		return
	var l := _label(text, font_size, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	_fx_layer.add_child(l)
	var p := size * Vector2(0.5, 0.4)
	if from and from.is_inside_tree():
		p = from.get_global_rect().get_center() - _fx_layer.get_global_rect().position
	l.reset_size()
	l.position = p - l.size * 0.5
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)


func _flash(c: CanvasItem, color: Color, dur: float = 0.35) -> void:
	if c == null or not is_inside_tree():
		return
	c.modulate = color
	c.create_tween().tween_property(c, "modulate", Color.WHITE, dur)


func _base_process(delta: float) -> void:
	## Subclasses with their own _process should call this.
	if _shake_t > 0.0:
		_shake_t -= delta
		var k := maxf(0.0, _shake_t) * _shake_mag * 3.0
		if _content_vbox:
			_content_vbox.position.x = randf_range(-k, k)
		if _shake_t <= 0.0 and _content_vbox:
			_content_vbox.position.x = 0.0


func _process(delta: float) -> void:
	_base_process(delta)


# ─── Little UI helpers ──────────────────────────────────────────────────

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _center_label(text: String, font_size: int, color: Color) -> Label:
	var l := _label(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, color: Color, min_size: Vector2 = Vector2(150, 44)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var c := color
		match state:
			"hover": c = color.lightened(0.15)
			"pressed": c = color.darkened(0.2)
			"disabled": c = Color(0.25, 0.25, 0.3)
		sb.bg_color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, 0.95)
		sb.border_color = c
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.6))
	return b


func _line_style(c: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = c
	s.thickness = 1
	return s


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
