class_name GameHowto
extends CanvasLayer
## How to play, and the controls, for every game a player can start: the midway games, the
## arcade dives, pool and Twenty-One, the vehicles, the rocket voyage, base jumps and the rides.
## One look everywhere (the owner, 2026-11-25: "the instructions … go away too fast and aren't
## that visible, along with the controls").
##
## The card: big and clear at the start, on a dark panel: the game's title, its rules, and every
## control as a key chip. It stays until a key is pressed (Mode.KEY: "press any key to start"),
## or counts down (Mode.COUNTDOWN: at least MIN_COUNTDOWN s, shown as a number; any key skips).
## Mode.HELP is the card brought back mid-game with the help key (HELP_ACTION); any key closes it.
##
## The strip: a compact row of key chips along the bottom for the whole game, always visible,
## ending with the help key. Hosts give their controls as [[key, words], …] (keys from
## ControlsHelp.key_of, never hard-coded).
##
## Presentation only: the host decides what a dismissed card means (start the round, unpause).
## Hosts with their own _input call `wants(event)` first and leave the event alone when true.

signal opened(mode: int)
signal dismissed(mode: int)

enum Mode { KEY, COUNTDOWN, HELP }

const LAYER := 42
const MIN_COUNTDOWN := 6.0
const HELP_ACTION := "game_help"
const CARD_W := 860.0
const GOLD := Color("#ffd36b")

var title := ""
var tag := ""                      ## a line under the title (where, practice / paid, …)
var rules: PackedStringArray = []
var controls: Array = []           ## [[key, words], …] on the card
var strip_controls: Array = []     ## [[key, words], …] on the strip ([] = the card's)
var accent := DeepFieldTheme.ICE
var verb := "start"                ## "press any key to <verb>"
var esc_words := ""                ## what Esc does here ("" = not shown on the card)
var help_enabled := true           ## the help key opens the card while the strip shows

var mode := Mode.KEY
var consume := true                ## the dismissing press is used up (KEY/HELP); COUNTDOWN may pass it on
var left := 0.0                    ## COUNTDOWN: seconds left
var hold := false                  ## previews: the countdown doesn't run

var _root: Control
var _dim: ColorRect
var _card: PanelContainer
var _c_title: Label
var _c_tag: Label
var _c_rules: VBoxContainer
var _c_keys: GridContainer
var _c_foot: Label
var _c_foot2: Label
var _strip: PanelContainer
var _strip_flow: HFlowContainer
var _card_open := false
var _strip_on := false
var _pulse := 0.0
var _shown_left := -1


func _init() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = DeepFieldTheme.get_theme()
	add_child(_root)
	_build_strip()
	_build_card()


## Fills in the game: {title, tag, rules: [lines], controls: [[key, words]], strip: [[key, words]],
## accent: Color, verb: "start", esc: "leave"}. Missing keys keep their values. Returns self.
func setup(spec: Dictionary) -> GameHowto:
	title = String(spec.get("title", title))
	tag = String(spec.get("tag", tag))
	if spec.has("rules"):
		rules = PackedStringArray(spec["rules"])
	if spec.has("controls"):
		controls = spec["controls"]
	if spec.has("strip"):
		strip_controls = spec["strip"]
	accent = spec.get("accent", accent)
	verb = String(spec.get("verb", verb))
	esc_words = String(spec.get("esc", esc_words))
	_fill_card()
	_fill_strip()
	return self


# --- The card -----------------------------------------------------------------------------

## Shows the card. KEY waits for a key; COUNTDOWN closes itself after `seconds` (never under
## MIN_COUNTDOWN) or on a key; HELP closes on a key. `p_consume`: the closing press is used up.
func open_card(p_mode: int = Mode.KEY, seconds: float = 8.0, p_consume: bool = true) -> void:
	mode = p_mode
	consume = p_consume
	left = countdown_seconds(seconds) if mode == Mode.COUNTDOWN else 0.0
	_shown_left = -1
	_fill_card()
	_card_open = true
	_card.visible = true
	_dim.visible = mode != Mode.COUNTDOWN
	_card.modulate.a = 1.0
	_foot()
	opened.emit(mode)


func close_card(emit: bool = true) -> void:
	if not _card_open:
		return
	_card_open = false
	_card.visible = false
	_dim.visible = false
	if emit:
		dismissed.emit(mode)


func is_card_open() -> bool:
	return _card_open


## The strip on or off (its chips: `strip_controls`, else `controls`, then the help key).
func show_strip(on: bool = true) -> void:
	_strip_on = on
	_strip.visible = on and not _strip_rows().is_empty()


func set_strip(rows: Array) -> void:
	strip_controls = rows
	_fill_strip()
	_strip.visible = _strip_on and not _strip_rows().is_empty()


## Hides everything (the game ended); no signal.
func end() -> void:
	close_card(false)
	show_strip(false)


func strip_visible() -> bool:
	return _strip.visible


## Will this event go to the card (or open it)? Hosts with their own _input skip it when true.
func wants(event: InputEvent) -> bool:
	if not is_inside_tree() or not visible or ChatInputGuard.is_suspended():
		return false
	if not _card_open:
		return help_enabled and _strip_on and event.is_action_pressed(HELP_ACTION) and not event.is_echo()
	if event is InputEventMouseMotion:
		return false
	if event.is_action_pressed("ui_cancel"):
		return mode == Mode.HELP  # Esc closes the help card; otherwise it's the host's (leave)
	return is_press(event) and (consume or mode == Mode.HELP)


func _input(event: InputEvent) -> void:
	if not visible or ChatInputGuard.is_suspended():  # typing in the chat bar

		return
	if not _card_open:
		if help_enabled and _strip_on and event.is_action_pressed(HELP_ACTION) and not event.is_echo():
			get_viewport().set_input_as_handled()
			open_card(Mode.HELP)
		return
	if event is InputEventMouseMotion:
		return
	if event.is_action_pressed("ui_cancel") and mode != Mode.HELP:
		return
	if not is_press(event):
		return
	if consume or mode == Mode.HELP:
		get_viewport().set_input_as_handled()
	close_card()


func _process(delta: float) -> void:
	if not _card_open:
		return
	_pulse += delta
	if mode == Mode.COUNTDOWN and not hold:
		left -= delta
		if left <= 0.0:
			close_card()
			return
	_foot()
	_c_foot.modulate.a = 0.75 + 0.25 * sin(_pulse * 4.0) if mode == Mode.KEY else 1.0


func _foot() -> void:
	match mode:
		Mode.KEY:
			_c_foot.text = "PRESS ANY KEY TO %s" % verb.to_upper()
		Mode.HELP:
			_c_foot.text = "PRESS ANY KEY TO GO BACK"
		Mode.COUNTDOWN:
			var n := ceili(maxf(left, 0.0))
			if n == _shown_left:
				return
			_shown_left = n
			_c_foot.text = countdown_text(left, verb)
	var bits: PackedStringArray = []
	bits.append("%s: these instructions again" % ControlsHelp.key_of(HELP_ACTION))
	if esc_words != "":
		bits.append("Esc: %s" % esc_words)
	_c_foot2.text = "   ·   ".join(bits)


# --- Pure helpers (tested) ---------------------------------------------------------------

## A countdown is never shorter than MIN_COUNTDOWN.
static func countdown_seconds(seconds: float) -> float:
	return maxf(seconds, MIN_COUNTDOWN)


## "CLOSES IN 7 S   ·   ANY KEY TO START NOW" (whole seconds, rounded up; never below 1 while showing).
static func countdown_text(seconds_left: float, p_verb: String = "start") -> String:
	return "CLOSES IN %d S   ·   ANY KEY TO %s NOW" % [maxi(1, ceili(seconds_left)), p_verb.to_upper()]


## A press that dismisses the card: a key, a mouse button or a pad button going down (not a repeat).
static func is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	if event is InputEventJoypadButton or event is InputEventAction:  # a pad, or an action fed in (tools)
		return event.pressed
	return false


## A one-line hint ("E / click: swing   ·   Esc: leave") as [[key, words], …]. A part with no
## "key: words" shape keeps its words with an empty key.
static func parse_hint(text: String) -> Array:
	var out: Array = []
	for raw in text.split("·"):
		var part := String(raw).strip_edges()
		if part == "":
			continue
		var i := part.find(": ")
		if i > 0 and i <= 24:
			out.append([part.left(i).strip_edges(), part.substr(i + 2).strip_edges()])
			continue
		var sp := HudV2.split_prompt(part)
		if String(sp[0]) != "":
			out.append([String(sp[0]), String(sp[1])])
		else:
			out.append(["", part])
	return out


## The strip's rows: the host's, then the help key.
func _strip_rows() -> Array:
	var rows: Array = (strip_controls if not strip_controls.is_empty() else controls).duplicate()
	if rows.is_empty():
		return rows
	if help_enabled:
		rows.append([ControlsHelp.key_of(HELP_ACTION), "how to play"])
	return rows


# --- Building -----------------------------------------------------------------------------

## A key cap: the key's name in mono on a dark chip with a bright edge.
static func key_chip(key: String, size: int = 17, color: Color = DeepFieldTheme.ICE) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.15, 1.0)
	sb.border_color = Color(color, 0.85)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	l.text = key
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip


## The controls as a two-column grid of [chip, words] (the card; also embedded in menus).
static func controls_grid(rows: Array, size: int = 20, words_w: float = 560.0) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_grid(g, rows, size, words_w)
	return g


static func fill_grid(g: GridContainer, rows: Array, size: int = 20, words_w: float = 560.0) -> void:
	for c in g.get_children():
		g.remove_child(c)
		c.queue_free()
	for r in rows:
		var key := String(r[0])
		var cell := HBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_END
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if key != "":
			cell.add_child(key_chip(key, size - 2))
		g.add_child(cell)
		var w := Label.new()
		w.text = String(r[1])
		w.add_theme_font_size_override("font_size", size)
		w.add_theme_color_override("font_color", DeepFieldTheme.INK)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size = Vector2(words_w, 0)
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(w)


func _label(parent: Control, size: int, color: Color, variation: String = "") -> Label:
	var l := Label.new()
	if variation != "":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_card() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	_root.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -40  # clear of the strip
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_card.visible = false
	center.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	_c_title = _label(col, 36, accent, "DisplayLabel")
	_c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_c_tag = _label(col, 16, DeepFieldTheme.MUTED.lerp(DeepFieldTheme.INK, 0.4))
	_c_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(HSeparator.new())
	_c_rules = VBoxContainer.new()
	_c_rules.add_theme_constant_override("separation", 4)
	_c_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_c_rules)
	var kh := _label(col, 15, DeepFieldTheme.ICE, "DisplayLabel")
	kh.text = "CONTROLS"
	_c_keys = controls_grid([], 20, 600.0)
	col.add_child(_c_keys)
	col.add_child(HSeparator.new())
	_c_foot = _label(col, 26, GOLD, "DisplayLabel")
	_c_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_c_foot2 = _label(col, 15, DeepFieldTheme.MUTED.lerp(DeepFieldTheme.INK, 0.3), "MonoLabel")
	_c_foot2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _fill_card() -> void:
	if _card == null:
		return
	var sb := DeepFieldTheme.panel_style(accent)
	sb.bg_color = Color(0.012, 0.016, 0.03, 0.96)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", sb)
	_c_title.text = title.to_upper()
	_c_title.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.15))
	_c_tag.text = tag
	_c_tag.visible = tag != ""
	for c in _c_rules.get_children():
		_c_rules.remove_child(c)
		c.queue_free()
	if not rules.is_empty():
		var rh := _label(_c_rules, 15, DeepFieldTheme.ICE, "DisplayLabel")
		rh.text = "HOW TO PLAY"
	for r in rules:
		var l := _label(_c_rules, 21, DeepFieldTheme.INK)
		l.text = "•  " + r
		l.custom_minimum_size = Vector2(CARD_W - 60.0, 0)
	fill_grid(_c_keys, controls, 20, 600.0)


func _build_strip() -> void:
	_strip = PanelContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.offset_left = 16
	_strip.offset_right = -16
	_strip.offset_bottom = -10
	_strip.offset_top = -10
	_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DeepFieldTheme.BLACK, 0.88)
	sb.border_color = Color(DeepFieldTheme.ICE, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	_strip.add_theme_stylebox_override("panel", sb)
	_strip.visible = false
	_root.add_child(_strip)
	_strip_flow = HFlowContainer.new()
	_strip_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_strip_flow.add_theme_constant_override("h_separation", 22)
	_strip_flow.add_theme_constant_override("v_separation", 6)
	_strip_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_strip_flow)


func _fill_strip() -> void:
	for c in _strip_flow.get_children():
		_strip_flow.remove_child(c)
		c.queue_free()
	for r in _strip_rows():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 7)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if String(r[0]) != "":
			item.add_child(key_chip(String(r[0]), 17))
		var w := Label.new()
		w.text = String(r[1])
		w.add_theme_font_size_override("font_size", 19)
		w.add_theme_color_override("font_color", DeepFieldTheme.INK)
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(w)
		_strip_flow.add_child(item)
