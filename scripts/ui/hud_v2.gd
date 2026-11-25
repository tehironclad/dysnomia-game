class_name HudV2
extends CanvasLayer
## The v2 HUD (Deep Field). Every chain number is a FactLabel with its source.
## Layout (HudLayout): WHERE YOU ARE top-left (the territory card in the
## QING's colours, its few facts), WHO YOU ARE top-right (your face and name,
## the notification slot, the block clock) with WHAT TO DO HERE under it (the
## act tracker), the room's chat dock bottom-left (ChatHud), the keys
## bottom-right, the ticker top-centre, the prompt bottom-centre.

var card: TerritoryCard
var prompt: Label          # the prompt's text (the key, if any, sits in prompt_key)
var prompt_key: Label
var prompt_box: PanelContainer
var tracker: ActTracker    # the acts here and your goals (ActLoop fills it)
var activity: ActivityFeed  # online players' actions (Net.activity), under the territory card
var you_name: Label
var you_sub: Label
var you_face: HeadBadge
var notify_slot: HBoxContainer  # empty: for a notification bell/badge (the top-right corner)
var _banner: VBoxContainer
var clock: Label
var hint: HBoxContainer
var ticker_box: VBoxContainer
var where_box: PanelContainer
var _facts := {}  # key → FactLabel
var _state: TerritoryState
var _sky: DeepFieldSky
var _root: Control
var _tint := DeepFieldTheme.ICE


const COMPACT_HIDDEN := ["epi", "reactors", "door"]


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = DeepFieldTheme.get_theme()
	add_child(_root)
	_build_where()
	activity = ActivityFeed.new()  # online players' actions, under the territory card (HudLayout "activity")
	_root.add_child(activity)
	activity.follow(where_box)
	_build_who()
	_build_middle()
	_build_keys()


## Top-left: the territory card and its facts, one panel in the QING's colour.
func _build_where() -> void:
	where_box = PanelContainer.new()
	where_box.name = "Where"
	where_box.position = Vector2(HudLayout.MARGIN, HudLayout.MARGIN)
	where_box.custom_minimum_size = Vector2(HudLayout.COL_W, 0)
	where_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	where_box.add_theme_stylebox_override("panel", DeepFieldTheme.accent_style(_tint, 0.72))
	_root.add_child(where_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", DeepFieldTheme.SPACE)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	where_box.add_child(col)
	card = TerritoryCard.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.custom_minimum_size = Vector2(0, 0)
	card.set_compact(true)
	col.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	for row in [["omega", "Ω PER SU"], ["hypo", "HYPOBAR"], ["epi", "EPIBAR HERE"],
			["reactors", "REACTORS"], ["door", "COVER CHARGE"], ["dev", "TIER"], ["you", "YOU HERE"]]:
		# Less clutter: Epibar, reactors and the cover live in the Inspector (H) and
		# the act tracker; the facts are still read and kept current.
		var shown: bool = not row[0] in COMPACT_HIDDEN
		var l := Label.new()
		l.visible = shown
		l.theme_type_variation = "MutedLabel"
		l.text = row[1]
		l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.add_child(l)
		var f := FactLabel.new()
		f.theme_type_variation = "MonoLabel"
		f.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size = Vector2(HudLayout.COL_W - 150, 0)  # the rest of the panel: values wrap less
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.set_fact(Fact.loading("…"))
		f.visible = shown
		grid.add_child(f)
		_facts[row[0]] = f


## Top-right: who you are (face, name, the notification slot), the clock, and
## what to do here (the act tracker).
func _build_who() -> void:
	var col := VBoxContainer.new()
	col.name = "Who"
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.offset_left = -HudLayout.MARGIN - HudLayout.COL_W
	col.offset_right = -HudLayout.MARGIN
	col.offset_top = HudLayout.MARGIN
	col.add_theme_constant_override("separation", HudLayout.GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	var strip := PanelContainer.new()
	strip.name = "You"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := DeepFieldTheme.panel_style()
	ss.content_margin_top = 8
	ss.content_margin_bottom = 8
	strip.add_theme_stylebox_override("panel", ss)
	col.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(names)
	you_name = Label.new()
	you_name.theme_type_variation = "DisplayLabel"
	you_name.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	you_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	you_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	you_name.clip_text = true
	names.add_child(you_name)
	you_sub = Label.new()
	you_sub.theme_type_variation = "MutedLabel"
	you_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	you_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	you_sub.clip_text = true
	names.add_child(you_sub)
	you_face = HeadBadge.new("human", DeepFieldTheme.ICE, 52.0)
	row.add_child(you_face)
	notify_slot = HBoxContainer.new()
	notify_slot.name = HudLayout.NOTIFY_SLOT  # a notification bell/badge goes here (the corner itself)
	notify_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notify_slot.add_theme_constant_override("separation", 6)
	row.add_child(notify_slot)
	clock = Label.new()
	clock.theme_type_variation = "MonoLabel"
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	clock.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	clock.add_theme_constant_override("outline_size", 5)
	col.add_child(clock)
	tracker = ActTracker.new()
	col.add_child(tracker)
	Session.changed.connect(_refresh_you)
	_refresh_you()


## The middle: the ticker under the wallet chip, the celebration banner, the prompt.
func _build_middle() -> void:
	# The prompt: one style everywhere: [KEY] what it does (glass, centred).
	prompt_box = PanelContainer.new()
	prompt_box.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style(Color(DeepFieldTheme.ICE, 0.35)))
	prompt_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_box.offset_left = 0.0
	prompt_box.offset_right = 0.0
	prompt_box.offset_top = -HudLayout.PROMPT_BOTTOM
	prompt_box.offset_bottom = -HudLayout.PROMPT_BOTTOM
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_box.visible = false
	_root.add_child(prompt_box)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 12)
	prompt_box.add_child(pr)
	prompt_key = DeepFieldTheme.key_chip("", DeepFieldTheme.FS_LEAD)
	pr.add_child(prompt_key)
	prompt = Label.new()
	prompt.theme_type_variation = "MonoLabel"
	prompt.add_theme_font_size_override("font_size", DeepFieldTheme.FS_LEAD)
	prompt.add_theme_color_override("font_color", DeepFieldTheme.INK)
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pr.add_child(prompt)
	_banner = VBoxContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position = Vector2(0, HudLayout.BANNER_TOP)
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner)
	ticker_box = VBoxContainer.new()
	ticker_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ticker_box.offset_left = -HudLayout.TICKER_W * 0.5
	ticker_box.offset_right = HudLayout.TICKER_W * 0.5
	ticker_box.offset_top = HudLayout.TICKER_TOP
	ticker_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	ticker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker_box.add_theme_constant_override("separation", 2)
	_root.add_child(ticker_box)


## Bottom-right: the main keys, each as a chip.
func _build_keys() -> void:
	hint = HBoxContainer.new()
	hint.name = "Keys"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -HudLayout.MARGIN
	hint.offset_bottom = -HudLayout.MARGIN
	hint.offset_left = -HudLayout.MARGIN
	hint.offset_top = -HudLayout.MARGIN
	hint.alignment = BoxContainer.ALIGNMENT_END
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_constant_override("separation", 6)
	_root.add_child(hint)
	var hints := key_hints()
	for i in hints.size():
		hint.add_child(DeepFieldTheme.key_chip(String(hints[i][0])))
		var l := Label.new()
		l.text = String(hints[i][1]) + ("" if i == hints.size() - 1 else "   ")
		l.theme_type_variation = "MutedLabel"
		l.add_theme_color_override("font_color", DeepFieldTheme.INK.lerp(DeepFieldTheme.MUTED, 0.4))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))  # readable over bright regolith
		l.add_theme_constant_override("outline_size", 6)
		hint.add_child(l)
	var notes := NotificationPanel.new()  # invites, stakes, wagers (its own layer: scripts/ui/notify/)
	notes.dock_bell(notify_slot)  # the bell sits in the top-right corner
	add_child(notes)


## [[key, words]] of the HUD's key row (bound keys, read from the InputMap).
static func key_hints() -> Array:
	return [[ControlsHelp.key_of("interact"), "use"], [ControlsHelp.key_of("inspect"), "how is this drawn"],
		[ControlsHelp.key_of("open_field"), "the Field"], [ControlsHelp.key_of("controls_help"), "controls"],
		[ControlsHelp.key_of("settings"), "settings"]]


## Who you are, as the chain says (a visitor until a wallet is connected).
func _refresh_you() -> void:
	var t := you_text(Session.wallet, Session.player)
	you_name.text = t["name"]
	you_sub.text = t["sub"]
	var ps: PlayerState = Session.player
	var kind := "human"
	if Session.wallet != "" and ps != null and ps.ok and ps.has_lau():
		var pick := AvatarHeads.local_choice(Session.wallet)
		kind = pick if pick != "" else ps.head_kind()
	you_face.set_face(kind, _tint if kind == "human" else HeadIcons.color_of(kind))


## Pure: the identity strip's two lines.
static func you_text(wallet: String, ps: PlayerState) -> Dictionary:
	if wallet == "":
		return {"name": "VISITOR", "sub": "looking is free · a wallet to play"}
	var short := "%s…%s" % [wallet.left(6), wallet.right(4)]
	if ps == null or not ps.ok:
		return {"name": short, "sub": "reading your identity…"}
	if not ps.has_lau():
		return {"name": short, "sub": "no LAU yet: the Void, at the front door"}
	var nm := ps.username if ps.username != "" else ps.lau_name
	return {"name": nm.to_upper() if nm != "" else short,
		"sub": "%s%s" % [(ps.lau_symbol + " · ") if ps.lau_symbol != "" else "", short]}


func bind(address: String, state: TerritoryState, sky: DeepFieldSky) -> void:
	card.show_territory(address)
	_tint = ChatFeedPanel.room_tint(Registry.get_territory(address))
	var ws := where_box.get_theme_stylebox("panel") as StyleBoxFlat
	if ws:
		ws.border_color = Color(_tint, 0.55)
	_refresh_you()
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
	if _state.block > 0 and _state.block != _read_block:
		_read_block = _state.block
		_pulse_where()


var _read_block := -1


## The territory panel's edge brightens and settles when a new read of the
## territory lands (a real block), like a heartbeat of the land.
func _pulse_where() -> void:
	var ws := where_box.get_theme_stylebox("panel") as StyleBoxFlat
	if ws == null or not where_box.is_inside_tree():
		return
	var tw := where_box.create_tween()
	ws.border_color = Color(_tint, 1.0)
	ws.shadow_color = Color(_tint, 0.3)
	ws.shadow_size = 8
	tw.tween_property(ws, "border_color", Color(_tint, 0.55), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ws, "shadow_color", Color(_tint, 0.0), 1.4)


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


## A phenomenon line (each carries its block), top-centre under the wallet
## chip. Fades after `ttl` seconds; the newest TICKER_ROWS stay.
func ticker(text: String, color: Color = DeepFieldTheme.ICE, ttl: float = 24.0) -> void:
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(HudLayout.TICKER_W, 0)
	l.text = text
	ticker_box.add_child(l)
	ticker_box.move_child(l, 0)
	while ticker_box.get_child_count() > HudLayout.TICKER_ROWS:
		ticker_box.get_child(ticker_box.get_child_count() - 1).free()
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.4)
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
	t.theme_type_variation = "DisplayLabel"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", DeepFieldTheme.FS_DISPLAY)
	t.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.3))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("outline_size", 8)
	_banner.add_child(t)
	var l := Label.new()
	l.text = line
	l.theme_type_variation = "MonoLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	l.add_theme_color_override("font_color", DeepFieldTheme.INK)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
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
	clock.text = (("block %s · %s" % [TokenFormat.group(str(Chain.head_block)), DysnomiaTime.format(t)]) if t >= 0 else "block — · time unknown") \
		+ "\nWORLD " + {"latent": "not deployed yet", "stirring": "· deployer moved", "unverified": "· unverified code", "live": "LIVE", "unknown": "—"}.get(World.status, "—")
