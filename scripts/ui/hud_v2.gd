class_name HudV2
extends CanvasLayer
## The v2 HUD (Deep Field). Every chain number is a FactLabel with its source.
## Layout: territory card + "here" facts (top-left), block & DysnomiaTime
## (top-right), prompt (bottom-centre), key hints (bottom-left).

var card: TerritoryCard
var prompt: Label
var clock: Label
var hint: Label
var ticker_box: VBoxContainer
var _facts := {}  # key → FactLabel
var _state: TerritoryState
var _sky: DeepFieldSky
var _root: Control


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
			["reactors", "REACTORS"], ["door", "COVER CHARGE"], ["you", "YOU HERE"]]:
		var l := Label.new()
		l.theme_type_variation = "MutedLabel"
		l.add_theme_font_size_override("font_size", 11)
		l.text = row[1]
		grid.add_child(l)
		var f := FactLabel.new()
		f.theme_type_variation = "MonoLabel"
		f.set_fact(Fact.loading("…"))
		grid.add_child(f)
		_facts[row[0]] = f
	clock = Label.new()
	clock.theme_type_variation = "MonoLabel"
	clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock.position = Vector2(-380, 20)
	clock.size = Vector2(360, 40)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(clock)
	prompt = Label.new()
	prompt.theme_type_variation = "MonoLabel"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-400, -110)
	prompt.size = Vector2(800, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(prompt)
	ticker_box = VBoxContainer.new()
	ticker_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ticker_box.position = Vector2(-460, 80)
	ticker_box.custom_minimum_size = Vector2(440, 0)
	ticker_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	ticker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ticker_box)
	hint = Label.new()
	hint.theme_type_variation = "MutedLabel"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -36)
	hint.text = "E  use (pylon: Su · door: Room · centre: Beat · monolith: Void)   ·   H  how is this drawn   ·   M  the field   ·   Esc  mouse"
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


## Your place on this territory's board (known players: a floor), with the
## gap to the leader or to the next one above.
static func you_fact(st: TerritoryState, wallet: String) -> Fact:
	if wallet == "":
		return Fact.empty("no wallet: connect at the front door")
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


func show_prompt(text: String) -> void:
	prompt.text = text


func hide_prompt() -> void:
	prompt.text = ""


func _process(_delta: float) -> void:
	if _sky == null:
		return
	var t := _sky.now_unix()
	clock.text = ("block %d\n%s" % [Chain.head_block, DysnomiaTime.format(t)]) if t >= 0 else "block —\ntime unknown"
