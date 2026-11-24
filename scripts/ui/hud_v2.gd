class_name HudV2
extends CanvasLayer
## The v2 HUD (Deep Field). Every chain number is a FactLabel with its source.
## Layout: territory card + "here" facts (top-left), block & DysnomiaTime
## (top-right), prompt (bottom-centre), key hints (bottom-left).

var card: TerritoryCard
var prompt: Label          # the prompt's text (the key, if any, sits in prompt_key)
var prompt_key: Label
var prompt_box: PanelContainer
var tracker: ActTracker    # the acts here and your goals (ActLoop fills it)
var _banner: VBoxContainer
var clock: Label
var hint: Label
var ticker_box: VBoxContainer
var _facts := {}  # key → FactLabel
var _state: TerritoryState
var _sky: DeepFieldSky
var _root: Control


const COMPACT_HIDDEN := ["epi", "reactors", "door"]


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = DeepFieldTheme.get_theme()
	add_child(_root)
	var left := VBoxContainer.new()
	left.position = Vector2(20, 20)
	left.add_theme_constant_override("separation", 8)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(left)
	card = TerritoryCard.new()
	left.add_child(card)
	var here := PanelContainer.new()
	here.custom_minimum_size = Vector2(320, 0)
	left.add_child(here)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	here.add_child(grid)
	for row in [["omega", "HYPOBAR PER SU"], ["hypo", "HYPOBAR HERE"], ["epi", "EPIBAR HERE"],
			["reactors", "REACTORS"], ["door", "COVER CHARGE"], ["dev", "DEVELOPMENT"], ["you", "YOU HERE"]]:
		# Less clutter: Epibar, reactors and the cover live in the Inspector (H) and
		# the act tracker; the facts are still read and kept current.
		var shown: bool = not row[0] in COMPACT_HIDDEN
		var l := Label.new()
		l.visible = shown
		l.theme_type_variation = "MutedLabel"
		l.add_theme_font_size_override("font_size", 11)
		l.text = row[1]
		grid.add_child(l)
		var f := FactLabel.new()
		f.theme_type_variation = "MonoLabel"
		f.set_fact(Fact.loading("…"))
		f.visible = shown
		grid.add_child(f)
		_facts[row[0]] = f
	clock = Label.new()
	clock.theme_type_variation = "MonoLabel"
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.position = Vector2(-380, 20)
	clock.size = Vector2(360, 40)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(clock)
	# The prompt: one style everywhere: [KEY] what it does (glass, centred).
	prompt_box = PanelContainer.new()
	prompt_box.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style(Color(DeepFieldTheme.ICE, 0.35)))
	prompt_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_box.offset_left = 0.0
	prompt_box.offset_right = 0.0
	prompt_box.offset_top = -96.0
	prompt_box.offset_bottom = -96.0
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_box.visible = false
	_root.add_child(prompt_box)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 12)
	prompt_box.add_child(pr)
	prompt_key = Label.new()
	prompt_key.theme_type_variation = "MonoLabel"
	prompt_key.add_theme_font_size_override("font_size", 15)
	prompt_key.add_theme_color_override("font_color", DeepFieldTheme.BLACK)
	var ks := StyleBoxFlat.new()
	ks.bg_color = DeepFieldTheme.ICE
	ks.set_corner_radius_all(4)
	ks.content_margin_left = 8
	ks.content_margin_right = 8
	ks.content_margin_top = 1
	ks.content_margin_bottom = 1
	prompt_key.add_theme_stylebox_override("normal", ks)
	pr.add_child(prompt_key)
	prompt = Label.new()
	prompt.theme_type_variation = "MonoLabel"
	prompt.add_theme_font_size_override("font_size", 15)
	prompt.add_theme_color_override("font_color", DeepFieldTheme.INK)
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(prompt)
	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position = Vector2(0, 120)
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	ticker_box = VBoxContainer.new()
	ticker_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ticker_box.position = Vector2(-460, 80)
	ticker_box.custom_minimum_size = Vector2(440, 0)
	ticker_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	ticker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ticker_box)
	tracker = ActTracker.new()
	left.add_child(tracker)
	hint = Label.new()
	hint.theme_type_variation = "MutedLabel"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -36)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))  # readable over bright regolith
	hint.add_theme_constant_override("outline_size", 6)
	hint.text = "%s  use   ·   %s  how is this drawn   ·   %s  the field   ·   %s  controls   ·   %s  settings" % [
		ControlsHelp.key_of("interact"), ControlsHelp.key_of("inspect"), ControlsHelp.key_of("open_field"),
		ControlsHelp.key_of("controls_help"), ControlsHelp.key_of("settings")]
	_root.add_child(hint)


func bind(address: String, state: TerritoryState, sky: DeepFieldSky) -> void:
	card.show_territory(address)
	_state = state
	_sky = sky
	state.changed.connect(_on_state)
	_on_state()


func _on_state() -> void:
	var dec := func(v): return TokenFormat.group(BigInt.to_decimal(BigInt.coerce(v)))
	var tok := func(v): return TokenFormat.wei_to_tokens(BigInt.coerce(v))
	_facts["omega"].set_fact(_state.omega, dec)
	_facts["hypo"].set_fact(_state.total_hypobar, dec)
	_facts["epi"].set_fact(_state.total_epibar, dec)
	_facts["reactors"].set_fact(_state.reactors)
	_facts["door"].set_fact(_state.cover_charge, func(v): return "none — door open" if BigInt.is_zero(BigInt.coerce(v)) else tok.call(v) + " (asset)")
	_facts["you"].set_fact(you_fact(_state, Session.wallet))
	_facts["dev"].set_fact(dev_fact(_state))


## Your place on this territory's board (known players: a floor), with the
## gap to the leader or to the next one above.
static func you_fact(st: TerritoryState, wallet: String) -> Fact:
	if wallet == "":
		return Fact.ok("no wallet connected", "your rank here needs a wallet (the chip at the top)")
	if not st.total_hypobar.has_value():
		return Fact.loading("YUE.Bar(QING)")
	var rows: Array = st.board
	for i in rows.size():
		if rows[i]["wallet"] == wallet:
			var mine: PackedInt64Array = rows[i]["hypobar"]
			var txt := "#%d · %s Hypobar" % [i + 1, TokenFormat.group(BigInt.to_decimal(mine))]
			if i > 0:
				var gap := BigInt.sub(rows[i - 1]["hypobar"], mine)
				txt += " · %s behind #%d" % [TokenFormat.group(BigInt.to_decimal(gap)), i]
			else:
				txt += " · leading" + ("" if rows.size() < 2 else " by %s" % TokenFormat.group(BigInt.to_decimal(BigInt.sub(mine, rows[1]["hypobar"]))))
			return Fact.floor_of(txt, "YUE.Bar(QING) vs known players", "rank among %d known players" % Players.count(), st.block)
	return Fact.floor_of("no bars here yet", "YUE.Bar(QING)", "known players only", st.block)


## The territory's development tier, from its Hypobar total (a floor).
static func dev_fact(st: TerritoryState) -> Fact:
	if not st.total_hypobar.has_value():
		return st.total_hypobar
	var t := Development.tier_of(BigInt.coerce(st.total_hypobar.value))
	var nxt := Development.next_threshold(t)
	var su := ""
	if nxt != "" and st.omega.has_value() and not BigInt.is_zero(BigInt.coerce(st.omega.value)):
		var need := BigInt.sub(BigInt.from_decimal(nxt), BigInt.coerce(st.total_hypobar.value))
		su = " · %s Su to %s" % [BigInt.to_decimal(Opportunities.ceil_div(need, BigInt.coerce(st.omega.value))), Development.tier_name(t + 1)]
	elif nxt != "":
		su = " · Ω = 0 here: Su adds no Hypobar"
	return Fact.floor_of("%s%s" % [Development.tier_name(t), su],
		"tier of Σ YUE.Bar(QING).Hypobar", "known players only", st.block)


## A phenomenon line (each carries its block). Fades after `ttl` seconds.
func ticker(text: String, color: Color = DeepFieldTheme.ICE, ttl: float = 24.0) -> void:
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	l.text = text
	ticker_box.add_child(l)
	ticker_box.move_child(l, 0)
	while ticker_box.get_child_count() > 6:
		ticker_box.get_child(ticker_box.get_child_count() - 1).free()
	var tw := l.create_tween()
	tw.tween_interval(ttl)
	tw.tween_property(l, "modulate:a", 0.0, 2.0)
	tw.tween_callback(l.queue_free)


## Prompts from every place share one look: "<key>  what it does" puts the key
## in a chip; anything else is shown as plain text in the same glass box.
func show_prompt(text: String) -> void:
	if text == "":
		hide_prompt()
		return
	var parts := split_prompt(text)
	var same: bool = prompt_box.visible and prompt.text == parts[1] and prompt_key.text == parts[0]
	prompt_key.text = parts[0]
	prompt_key.visible = parts[0] != ""
	prompt.text = parts[1]
	prompt_box.reset_size()  # grows both ways from the centre (offsets 0, 0)
	if same and not prompt_box.get_meta("fading_out", false):
		return
	_fade_prompt(true)


func hide_prompt() -> void:
	if not prompt_box.visible or prompt_box.get_meta("fading_out", false):
		return
	_fade_prompt(false)


## Prompts ease in and out (PromptFade's timings) instead of blinking at a zone's edge.
func _fade_prompt(show: bool) -> void:
	var tw: Tween = prompt_box.get_meta("fade_tw") if prompt_box.has_meta("fade_tw") else null
	if tw != null and tw.is_valid():
		tw.kill()
	prompt_box.set_meta("fading_out", not show)
	if not prompt_box.is_inside_tree():
		prompt_box.visible = show
		prompt_box.modulate.a = 1.0 if show else 0.0
		return
	tw = prompt_box.create_tween()
	if show:
		if not prompt_box.visible:
			prompt_box.modulate.a = 0.0
		prompt_box.visible = true
		tw.tween_property(prompt_box, "modulate:a", 1.0, PromptFade.FADE_IN)
	else:
		tw.tween_interval(PromptFade.LINGER)
		tw.tween_property(prompt_box, "modulate:a", 0.0, PromptFade.FADE_OUT)
		tw.tween_callback(func() -> void:
			prompt_box.visible = false
			prompt.text = "")
	prompt_box.set_meta("fade_tw", tw)


## Pure: ["E", "Steward: …"] from "E  Steward: …"; ["", text] when no key leads.
## A key is a short token (≤ 12 chars, e.g. "E" or "E / Mouse 1") before two spaces.
static func split_prompt(text: String) -> Array:
	var i := text.find("  ")
	if i > 0 and i <= 12 and not text.left(i).contains("·") and not text.left(i).contains(":"):
		var rest := text.substr(i).strip_edges()
		return [text.left(i), rest.left(1).to_upper() + rest.substr(1)]
	return ["", text]


## A confirmed move, celebrated with its measured change (the caller passes
## numbers read back from the chain, never the wallet page's word).
func celebrate(title: String, line: String, color: Color = DeepFieldTheme.ICE) -> void:
	for c in _banner.get_children():
		c.queue_free()
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.3))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("outline_size", 8)
	_banner.add_child(t)
	var l := Label.new()
	l.text = line
	l.theme_type_variation = "MonoLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", DeepFieldTheme.INK)
	_banner.add_child(l)
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.9, 0.9)
	var tw := _banner.create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(5.0)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.2)
	ticker("%s · %s" % [title, line], color, 60.0)


var _clock_t := 0.0


func _process(delta: float) -> void:
	if _sky == null:
		return
	_clock_t -= delta
	if _clock_t > 0.0:
		return
	_clock_t = 0.25  # the clock text is rebuilt 4×/s, not every frame
	var t := _sky.now_unix()
	clock.text = (("block %d\n%s" % [Chain.head_block, DysnomiaTime.format(t)]) if t >= 0 else "block —\ntime unknown") \
		+ "\nWORLD " + {"latent": "not deployed yet", "stirring": "· deployer moved", "unverified": "· unverified code", "live": "LIVE", "unknown": "—"}.get(World.status, "—")
