class_name GuidePanel
extends PanelContainer
## The Guide (WP 7.1), two pages:
## - "acts": the acts, ticked only by chain predicates (or a local flag set after a
##   chain-verified event). The current level is expanded with its codex entry: the
##   call it is about, then plain words, then where to do it.
## - "money": how money works here, for newcomers (the site's /money in the game's
##   words). Prices come from `Prices`, tier names from `Development`: no literals.
## In a territory G cycles: the acts → Money → closed (`cycle`). The front door shows
## both as tabs (`set_page`).

const PAGES := ["acts", "money"]
const MONEY_URL := "enterdysnomia.com/money"

var page := "acts"
var _title: Label
var _tabs: Dictionary = {}
var _list: RichTextLabel


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.94
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(520, 0)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	for p in PAGES:
		var b := Button.new()
		b.text = "The acts" if p == "acts" else "Money"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
		b.pressed.connect(set_page.bind(p))
		head.add_child(b)
		_tabs[p] = b
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.fit_content = true
	_list.scroll_active = false
	_list.custom_minimum_size = Vector2(500, 0)
	_list.add_theme_font_override("normal_font", DeepFieldTheme.body_font())
	_list.add_theme_font_override("bold_font", DeepFieldTheme._font(DeepFieldTheme.FONT_BODY_PATH, 650))
	_list.add_theme_font_override("mono_font", DeepFieldTheme.mono_font())
	_list.add_theme_font_size_override("normal_font_size", DeepFieldTheme.FS_CAPTION)
	_list.add_theme_font_size_override("bold_font_size", DeepFieldTheme.FS_CAPTION)
	_list.add_theme_font_size_override("mono_font_size", DeepFieldTheme.FS_CAPTION)
	col.add_child(_list)


func _ready() -> void:
	Session.changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


## The territory's G: closed → the acts → Money → closed.
func cycle() -> void:
	if not visible:
		page = "acts"
		visible = true
	elif page == "acts":
		page = "money"
	else:
		visible = false
		return
	refresh()


func set_page(p: String) -> void:
	page = p if p in PAGES else "acts"
	refresh()


func refresh() -> void:
	for p in _tabs:
		_tabs[p].set_pressed_no_signal(p == page)
	if not visible:
		return
	if page == "money":
		_title.text = "GUIDE · money"
		_list.text = money_text()
		return
	_title.text = "GUIDE · the acts"
	var flags := Acts.flags_for(Session.wallet)
	var done := Acts.evaluate(Session.player, Session.readiness, Session.bars, flags, Session.forged_lau != "")
	var cur := Acts.current(done)
	var act := ""
	var t := ""
	if Session.wallet == "":
		t += "[color=#ffd27a]No wallet connected: only the Prologue can be checked.[/color]\n"
	for l in Acts.LEVELS:
		if l["act"] != act:
			act = l["act"]
			t += "\n[color=#8e97a9]%s[/color]\n" % act.to_upper()
		var ok: bool = done.get(l["key"], false)
		var mark := "[color=#64e3a8]✓[/color]" if ok else ("[color=#a8e6ff]▸[/color]" if l["key"] == cur else "[color=#5d6578]○[/color]")
		t += "%s  %s\n" % [mark, l["title"] if l["key"] != cur else "[b]%s[/b]" % l["title"]]
		if l["key"] == cur:
			if l["code"] != "—":
				t += "    [code]%s[/code]\n" % l["code"]
			t += "    %s\n    [color=#8e97a9]%s[/color]\n" % [l["plain"], l["how"]]
	t += "\n[color=#8e97a9]G again: Money[/color]"
	_list.text = t


## "1–2 Ⓐ": the cheapest and dearest drink in the price table.
static func drink_range() -> String:
	var lo := 1 << 30
	var hi := 0
	for id in Prices.DRINKS:
		lo = mini(lo, int(Prices.DRINKS[id]))
		hi = maxi(hi, int(Prices.DRINKS[id]))
	if hi == 0:
		return "—"
	return Prices.text(lo) if lo == hi else "%d–%s" % [lo, Prices.text(hi)]


## "Wild → Outpost → … → Capital"
static func tier_ladder() -> String:
	var names: Array[String] = []
	for t in Development.TIERS:
		names.append(String(t["name"]))
	return " → ".join(names)


## The Money page (pure: prices from Prices, tiers from Development).
static func money_text() -> String:
	const PLS := "#ffd59a"
	const AFF := "#ff8fd0"
	const GROW := "#64e3a8"
	const YUE := "#c7a6ff"
	const DIM := "#8e97a9"
	var a := Prices.SYMBOL
	var pts: Array[String] = [
		"[color=%s][b]PLS pays gas.[/b][/color] Every move you sign, a Su, a room line or a payment, costs a little PLS. Swap %s for PLS at the Swap Hall." % [PLS, a],
		"[color=%s][b]%s AFFECTION is the everyday money:[/b][/color] what you spend here, gift to friends and trade." % [AFF, a],
		"[color=%s][b]Prices here:[/b][/color] a play, ride, vehicle or jump %s · %d plays for %s (one approval, gas once) · drinks %s · the rocket %s. You pay [b]this QING[/b] (its own balance); a play counts once its receipt is read." % [AFF, Prices.play_text(), Prices.STRIP_PLAYS, Prices.strip_text(), drink_range(), Prices.text(Prices.ROCKET)],
		"[color=%s][b]What grows this territory:[/b][/color] a Su, or a line in the Room, adds this QING's Ω to your bar here. Bars only grow. The tier, %s, comes from them, and the world builds from it." % [GROW, tier_ladder()],
		"[color=%s][b]Plainly:[/b][/color] holding %s, or paying it here, raises no bar and no tier. Moves grow territories; %s pays for fun." % [GROW, a, a],
		"[color=%s][b]Ω[/b][/color] = the Fornax this QING holds ÷ its Entropy, the same for everyone. Anyone who sends it Fornax raises Ω for all." % GROW,
		"[color=%s][b]YUE:[/b][/color] +1 per Su, your score here. At the YUE Exchange it is also a desk: Hong buys a QING's token, Hung sells it." % YUE,
		"[color=%s][b]Four holdings[/b][/color] (Fomalhaute and Fornax on your LAU, Tethys, qZů) make Beat work. [color=%s]Not live yet: WORLD · WAR · GWAT · VITUS · H2O.[/color]" % [YUE, DIM],
	]
	var t := ""
	for i in pts.size():
		t += "[color=%s]%d[/color]  %s\n" % [DIM, i + 1, pts[i]]
	t += "\n[color=%s]More, with live figures: [/color][color=#a8e6ff]%s[/color]\n[color=%s]G again: close[/color]" % [DIM, MONEY_URL, DIM]
	return t
