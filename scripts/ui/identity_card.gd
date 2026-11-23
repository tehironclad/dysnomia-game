class_name IdentityCard
extends PanelContainer
## The connected player's face (WP 4.2/4.3): their Aura drawn as a Deep Field
## picture (Aura = uint160(wallet) % MotzkinPrime, the contract's own formula),
## LAU, Username, Soul, Aura, YUE, and WORLD readiness with per-holding
## verdicts, which are also shown as the four bodies (Fomalhaute, Fornax,
## Tethys, Phobos) lighting up.

const HOLDINGS := [["fomalhaute", "FOMALHAUTE", "on your LAU"], ["fornax", "FORNAX", "on your LAU"],
	["tethys", "TETHYS", "anywhere"], ["qzu", "PHOBOS · qZů", "anywhere"]]
const VERDICT_COLOR := {"ok": Color("#64e3a8"), "thin": Color("#ffd27a"), "round": Color("#ffd27a"),
	"low": Color("#ffb070"), "wrong-place": Color("#ff8fa0"), "missing": Color("#5d6578")}

var emblem: DeepFieldView
var _name: Label
var _lines: Label
var _state: Label
var _reason: Label
var _bodies := {}
var _head_pick: OptionButton


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	custom_minimum_size = Vector2(420, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	emblem = DeepFieldView.new()
	emblem.custom_minimum_size = Vector2(96, 96)
	top.add_child(emblem)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	_name = Label.new()
	_name.theme_type_variation = "DisplayLabel"
	_name.add_theme_font_size_override("font_size", 16)
	info.add_child(_name)
	_lines = Label.new()
	_lines.theme_type_variation = "MonoLabel"
	_lines.add_theme_font_size_override("font_size", 11)
	info.add_child(_lines)
	_state = Label.new()
	_state.theme_type_variation = "MonoLabel"
	col.add_child(_state)
	_reason = Label.new()
	_reason.theme_type_variation = "MutedLabel"
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_reason)
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	for h in HOLDINGS:
		var l := Label.new()
		l.theme_type_variation = "MonoLabel"
		l.add_theme_font_size_override("font_size", 12)
		l.text = "●  " + h[1]
		grid.add_child(l)
		var d := Label.new()
		d.theme_type_variation = "MutedLabel"
		d.add_theme_font_size_override("font_size", 11)
		grid.add_child(d)
		_bodies[h[0]] = {"dot": l, "detail": d}
	var hrow := HBoxContainer.new()
	col.add_child(hrow)
	var hl := Label.new()
	hl.theme_type_variation = "MutedLabel"
	hl.text = "Avatar head"
	hrow.add_child(hl)
	_head_pick = OptionButton.new()
	_head_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head_pick.item_selected.connect(_on_head_picked)
	hrow.add_child(_head_pick)


func _ready() -> void:
	Session.changed.connect(refresh)
	refresh()


## The first entry follows the LAU's on-chain name/symbol; the rest are a local
## choice for this wallet on this machine.
func _fill_heads(w: String, ps: PlayerState) -> void:
	_head_pick.visible = true
	_head_pick.clear()
	_head_pick.add_item("from my LAU: %s (%s %s)" % [ps.head_kind(), ps.lau_name, ps.lau_symbol])
	for k in AvatarHeads.KINDS:
		_head_pick.add_item("%s (my choice, this machine)" % k)
	var pick := AvatarHeads.local_choice(w)
	_head_pick.select(0 if pick == "" else 1 + AvatarHeads.KINDS.find(pick))


func _on_head_picked(i: int) -> void:
	if Session.wallet == "":
		return
	AvatarHeads.set_local_choice(Session.wallet, "" if i == 0 else String(AvatarHeads.KINDS[i - 1]))
	Session.changed.emit()


func refresh() -> void:
	var w := Session.wallet
	if w == "":
		_name.text = "NOT CONNECTED"
		_lines.text = "Connect a browser wallet to see your identity."
		_state.text = ""
		_reason.text = ""
		emblem.visible = false
		for k in _bodies:
			_bodies[k]["detail"].text = "—"
		_head_pick.visible = false
		return
	emblem.visible = true
	var p := DeepField.for_identity(w)
	emblem.apply_params(p, "Your Aura, %s = uint160(%s) % 953,467,954,114,363 (the contract's formula), drawn as a Julia set." % [DeepField.aura(w), w])
	var ps: PlayerState = Session.player
	if ps == null:
		_name.text = "READING…"
		_lines.text = w
		_state.text = ""
		return
	_name.text = (ps.username if ps.username != "" else "(no username)").to_upper()
	_fill_heads(w, ps)
	_lines.text = "wallet %s\nLAU    %s\nYUE    %s\nSoul %s · Aura %s\nblock %d" % [
		w, ps.lau if ps.has_lau() else "— (none registered)", ps.yue if ps.has_yue() else "— (not started)",
		ps.soul if ps.soul != "" else "—", ps.aura if ps.aura != "" else DeepField.aura(w), ps.block]
	var rd: Readiness = Session.readiness
	if rd != null:
		var label: String = {"no-account": "NO ACCOUNT", "not-started": "NOT STARTED", "blocked": "BLOCKED",
			"not-ready": "NOT READY FOR WORLD", "fragile": "READY · FRAGILE", "ready": "READY FOR WORLD"}.get(rd.state, rd.state.to_upper())
		_state.text = "%s%s%s" % [label, "  ·  crow (≥ 25 CROWS: universal bouncer)" if ps.is_bouncer() else "",
			"  ·  WITHOUT held (banned from rooms)" if ps.is_banned() else ""]
		_state.add_theme_color_override("font_color", Color("#64e3a8") if rd.state.begins_with("ready") or rd.state == "fragile" else Color("#ffd27a"))
		_reason.text = rd.reason + (("\n" + rd.fragile_reason) if rd.fragile_reason != "" else "")
		for h in HOLDINGS:
			var v: Dictionary = rd.holdings.get(h[0], {"verdict": "missing", "detail": "—"})
			var b: Dictionary = _bodies[h[0]]
			b["dot"].add_theme_color_override("font_color", VERDICT_COLOR.get(v["verdict"], DeepFieldTheme.MUTED))
			b["detail"].text = "%s · %s" % [v["verdict"], v["detail"]]
