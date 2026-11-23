class_name OpportunitiesPanel
extends PanelContainer
## What's worth doing now (Opportunities), read from the chain at one block:
## the hot spots by Ω, leads within reach (Su to pass, with gas), your crowns
## (how many Su a rival needs), territories close to their next development
## tier, and your record (streak, reactions, atlas). Every row warps there.

var _body: VBoxContainer
var _status: Label
var _opp: Opportunities
var _loading := false


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.95
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(620, 0)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 18)
	title.text = "OPPORTUNITIES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var again := Button.new()
	again.text = "Re-read"
	again.pressed.connect(refresh)
	top.add_child(again)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): toggle())
	top.add_child(close)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(600, 0)
	col.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)


func toggle() -> void:
	visible = not visible
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if _opp == null:
			refresh()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if _loading:
		return
	_loading = true
	_status.text = "Reading Ω at every territory and the boards where it pays…"
	_opp = await Opportunities.read(Session.wallet)
	_loading = false
	_render()


func _section(title: String, note: String) -> void:
	var l := Label.new()
	l.theme_type_variation = "DisplayLabel"
	l.add_theme_font_size_override("font_size", 14)
	l.text = title
	_body.add_child(l)
	if note != "":
		var n := Label.new()
		n.theme_type_variation = "MutedLabel"
		n.add_theme_font_size_override("font_size", 11)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(580, 0)
		n.text = note
		_body.add_child(n)


func _row(text: String, address: String) -> void:
	var r := HBoxContainer.new()
	_body.add_child(r)
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = text
	r.add_child(l)
	if address != "":
		var b := Button.new()
		b.text = "Warp"
		b.pressed.connect(func(): Warp.to(get_tree(), address))
		r.add_child(b)


static func _g(b: PackedInt64Array) -> String:
	return TokenFormat.group(BigInt.to_decimal(b))


func _render() -> void:
	for c in _body.get_children():
		c.queue_free()
	if _opp == null or not _opp.ok:
		_status.text = "Could not read the chain: —"
		return
	var me := Session.wallet
	_status.text = "Read at block %d. Ω = ⌊Fornax(QING) ÷ Entropy⌋ is the Hypobar every Su adds there, the same for everyone; boards are known players (a floor). Su counts are a snapshot: rivals can react too.%s" % [
		_opp.block, (" Gas ≈ %s units per Su." % TokenFormat.group(str(_opp.gas_per_su))) if _opp.gas_per_su > 0 else ""]
	var rec: PlayerRecord = Session.record
	if me != "":
		_section("YOUR RECORD", "From your YUE mint logs: each Su mints you 1 YUE.")
		_row(rec.describe() if rec != null else "Reading your record…", "")
		var tiers := {}
		for a in Session.bars:
			var t := String(DeepField.for_territory(Registry.get_territory(a)).get("tier", "?"))
			tiers[t] = tiers.get(t, 0) + 1
		_row("Atlas: bars at %d of %d territories %s · crowns: %d" % [Session.bars.size(), Registry.count(),
			str(tiers) if not tiers.is_empty() else "", _opp.crowns.size()], "")
	_section("HOT SPOTS · Hypobar per Su", "Only these %d territories hold Fornax: a Su anywhere else adds no Hypobar (still Epibar and +1 YUE)." % _opp.hot.size())
	for e in _opp.hot.slice(0, 10):
		var you := ""
		if me != "":
			you = "  · you: #%d" % e["rank"] if e["rank"] > 0 else "  · you: no bars"
		_row("Ω %-12s %s%s" % [_g(e["omega"]), String(e["name"]).left(30), you], e["address"])
	if me != "":
		_section("WITHIN REACH", "Leads you can take in ≤ %d Su (to #1), with the Su to pass the next player." % Opportunities.REACH_MAX)
		if _opp.reach.is_empty():
			_row("Nothing within %d Su right now." % Opportunities.REACH_MAX, "")
		for e in _opp.reach.slice(0, 10):
			_row("%s · %d Su to #1 (%s) · %d Su to #%d" % [String(e["name"]).left(28), e["su_top"], _opp.cost_of(e["su_top"]),
				e["su_next"], e["next_rank"]], e["address"])
		_section("YOUR CROWNS", "Territories you lead; how many Su the runner-up needs to pass you.")
		if _opp.crowns.is_empty():
			_row("You lead none of the territories where Su pays Hypobar.", "")
		for e in _opp.crowns:
			_row("%s · rival needs %d Su%s" % [String(e["name"]).left(30), e["margin_su"], "  ⚠ close" if e["margin_su"] <= 3 else ""], e["address"])
	_section("BUILD TOGETHER", "Su needed (by anyone) to raise a territory to its next development tier.")
	for e in _opp.build.slice(0, 8):
		_row("%s · %s → %s in %d Su (%s)" % [String(e["name"]).left(28), Development.tier_name(e["tier"]), Development.tier_name(e["next_tier"]),
			e["su"], _opp.cost_of(e["su"])], e["address"])
