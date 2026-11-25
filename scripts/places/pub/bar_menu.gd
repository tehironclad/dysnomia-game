class_name BarMenu
extends PanelContainer
## Sunny's bar menu, opened at the counter. Each drink is the visitor's own
## real call (BarTab): picking one simulates it from the wallet at the head
## block and quotes gas; "Pour" signs it through Wallet.send (simulate → sign →
## receipt read from the chain) and then shows what was measured: the mint logs
## in the receipt and your bars here re-read at the blocks either side. A round
## for the house is Prices.ROUND Ⓐ to this QING (ArcadePay.transfer_to_qing, verified). Each drink
## has its price (Prices.DRINKS, 1–2 Ⓐ): paid to this QING first (its code in the last wei), then
## poured; a drink paid but not poured pours again without paying while the menu is open.
## Nothing is shown as done before its receipt is read; a failed read is "—".
##
## The pub moves the menu out of the way while an order is out (order_started): it hides it,
## shows the wallet's progress small (status_changed), plays the pour once the receipt is read
## (poured / round_bought) and brings the menu back with the result (reveal). The write pipeline
## is untouched; only where its words are shown changed.

signal closed
signal poured(drink: Dictionary, result: Dictionary)
signal round_bought(result: Dictionary)
signal order_started(drink: Dictionary)          ## Pour / Buy pressed: the wallet takes over
signal order_failed(drink: Dictionary, result: Dictionary)  ## not poured (any stage): nothing happened
signal status_changed(text: String, color: Color)  ## every status line, shown or not

const OK := Color("#64e3a8")
const WARN := Color("#ffd27a")

var qing := ""
var place := ""
var _list: VBoxContainer
var _buttons: Array[Button] = []
var _name: Label
var _call: Label
var _blurb: Label
var _seed_row: HBoxContainer
var _seed: SpinBox
var _phi: CheckBox
var _preview: Label
var _status: Label
var _result: Label
var _pour: Button
var actions: HBoxContainer  # the bottom row: the place may add its own buttons
var _sel: Dictionary = {}
var _busy := false
var _ask := 0  # preview generation: a stale preview never overwrites a newer one
var _label := ""
var _paid_tab := {}  ## drink id → its verified payment, poured not yet (a failed pour pours again free)
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(Color(1.0, 0.78, 0.4, 0.5))
	sb.bg_color.a = 0.96
	add_theme_stylebox_override("panel", sb)
	visible = false
	custom_minimum_size = Vector2(940, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	title.text = "AFFECTION ON TAP · SUNNY'S"
	col.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = "MutedLabel"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(900, 0)
	sub.text = "Every drink is your own real contract call, signed in your wallet: simulated from your wallet first, then the receipt is read from the chain and your bars here are re-read. Each drink's price goes to this QING first (one transfer), then the drink's call; the round is %s." % Prices.text(Prices.ROUND)
	col.add_child(sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.add_theme_constant_override("separation", 4)
	body.add_child(_list)
	var group := ButtonGroup.new()
	for d in BarTab.DRINKS + [BarTab.ROUND]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   ·   %s" % [d["name"], price_text(d)]
		b.pressed.connect(_select.bind(d))
		_list.add_child(b)
		_buttons.append(b)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(580, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_name = Label.new()
	_name.theme_type_variation = "DisplayLabel"
	_name.add_theme_font_size_override("font_size", 17)
	right.add_child(_name)
	_call = Label.new()
	_call.theme_type_variation = "MonoLabel"
	_call.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	right.add_child(_call)
	_blurb = _wrap(right, "MutedLabel")
	_seed_row = HBoxContainer.new()
	_seed_row.add_theme_constant_override("separation", 8)
	right.add_child(_seed_row)
	var sl := Label.new()
	sl.text = "Your lucky number (seed)"
	_seed_row.add_child(sl)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = BarTab.SEED_MAX
	_seed.step = 1
	_seed.custom_minimum_size = Vector2(150, 0)
	_seed.value_changed.connect(func(_v): _refresh_preview())
	_seed_row.add_child(_seed)
	var shake := Button.new()
	shake.text = "Shake"
	shake.pressed.connect(func(): _seed.value = _rng.randi_range(1, BarTab.SEED_MAX))
	_seed_row.add_child(shake)
	_phi = CheckBox.new()
	_phi.text = "a twist of phi"
	_phi.toggled.connect(func(_on): _refresh_preview())
	_seed_row.add_child(_phi)
	_preview = _wrap(right, "MonoLabel")
	_status = _wrap(right, "")
	_result = _wrap(right, "MonoLabel")
	_result.add_theme_color_override("font_color", OK)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	col.add_child(actions)
	_pour = Button.new()
	_pour.pressed.connect(_on_pour)
	actions.add_child(_pour)
	var close_b := Button.new()
	close_b.text = "Leave the bar (Esc)"
	close_b.pressed.connect(close)
	actions.add_child(close_b)
	_rng.randomize()


func _wrap(parent: Control, variation: String) -> Label:
	var l := Label.new()
	if variation != "":
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(570, 0)
	parent.add_child(l)
	return l


static func price_text(d: Dictionary) -> String:
	var w := Prices.drink(String(d["id"]))
	return Prices.text(w) if d["id"] == BarTab.ROUND["id"] or w <= 0 else "%s + the call" % Prices.text(w)


## The board's lines: [name, price].
static func board_lines() -> Array:
	var out: Array = []
	for d in BarTab.DRINKS + [BarTab.ROUND]:
		out.append([d["name"], price_text(d)])
	return out


func setup(p_qing: String, p_place: String) -> void:
	qing = p_qing.to_lower()
	place = p_place
	Wallet.tx_stage.connect(_on_stage)


func is_open() -> bool:
	return visible


func open(preselect: String = "") -> void:
	visible = true
	_result.text = ""
	_seed.set_value_no_signal(_rng.randi_range(1, BarTab.SEED_MAX))
	var idx := 0
	var all := BarTab.DRINKS + [BarTab.ROUND]
	for i in all.size():
		if all[i]["id"] == preselect:
			idx = i
	_buttons[idx].button_pressed = true
	_buttons[idx].grab_focus()
	_select(all[idx])


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Shows the menu again as it was (the status and the measured result kept), after the pour.
func reveal() -> void:
	visible = true
	if _sel.is_empty():
		return
	for b in _buttons:
		if b.button_pressed:
			b.grab_focus()


## An order is out (between Pour and its receipt).
func is_busy() -> bool:
	return _busy


func _select(d: Dictionary) -> void:
	_sel = d
	_name.text = String(d["name"]).to_upper()
	_blurb.text = d["blurb"] + ("\n" + BarTab.OP_NOTE if d.get("kind") == BarTab.KIND_OP else "")
	_seed_row.visible = BarTab.takes_seed(d)
	_phi.visible = BarTab.takes_phi(d)
	_result.text = ""
	_refresh_preview()


func _seed_value() -> int:
	return int(_seed.value)


var _access: AccessSteps


func _blocker() -> String:
	var b := ChatController._signer_blocker()
	if b != "":
		return b
	if _sel.get("kind") == BarTab.KIND_SU:
		var ps: PlayerState = Session.player
		if ps == null:
			return "Reading your identity… try again in a moment."
		if not ps.has_yue():
			return "No YUE yet: wake it (SEI.Start) at the front door; Su needs one."
	return ""


func _refresh_preview() -> void:
	if _sel.is_empty():
		return
	_ask += 1
	var ask := _ask
	var is_round: bool = _sel["id"] == BarTab.ROUND["id"]
	var cost := Prices.drink(String(_sel["id"]))
	_call.text = ("AFFECTION.transfer(this QING, %s)" % Prices.text(cost)) if is_round else BarTab.call_text(_sel, qing, _seed_value(), _phi.button_pressed)
	_pour.text = ("Buy the round · sign %s" % Prices.text(cost)) if is_round else ("Pour · already paid" if _paid_tab.has(String(_sel["id"])) else "Pay %s, then pour" % Prices.text(cost) if cost > 0 else "Pour · sign in your wallet")
	var blocker := _blocker()
	_pour.disabled = _busy or blocker != ""
	_status.text = blocker
	if _access == null:
		_access = AccessSteps.embed(_status.get_parent(), _status.get_index() + 1)
	_access.update_for(blocker, "drink" if is_round else ("su" if _sel.get("kind") == BarTab.KIND_SU else "sign"), {"qing": qing, "fee_wei": Prices.drink_wei(String(_sel["id"])),
		"title": "Buy the round" if is_round else "Order %s (a Su at this bar)" % String(_sel.get("name", "a drink"))})
	_status.add_theme_color_override("font_color", WARN)
	if is_round:
		_preview.text = "Paid to %s's QING contract (its own balance). Wallet.send simulates the transfer from your wallet before you sign; the receipt must show AFFECTION's Transfer(you → this QING, ≥ %s)." % [place, Prices.text(Prices.ROUND)]
		return
	if Session.wallet == "":
		_preview.text = "Simulation: — (it runs from your wallet; connect one at the front door)."
		return
	_preview.text = "Simulating from your wallet…"
	var p: Dictionary = await BarTab.preview(_sel, Session.wallet, qing, _seed_value(), _phi.button_pressed)
	if ask != _ask or not visible:
		return
	if p["ok"]:
		_preview.text = "\n".join(p["lines"])
	else:
		var hint := ""
		if p.has("revert"):
			hint = String(Contracts.ERROR_HINTS.get(String(p["revert"].get("name", "")), ""))
		_preview.text = String(p["message"]) + ("\n" + hint if hint != "" else "")


func _on_pour() -> void:
	if _busy or _sel.is_empty() or _blocker() != "":
		return
	_busy = true
	_pour.disabled = true
	_result.text = ""
	var d := _sel
	order_started.emit(d)
	if d["id"] == BarTab.ROUND["id"]:
		_label = "Round for the house at Sunny's (%s)" % Prices.text(Prices.ROUND)
		var r: Dictionary = await ArcadePay.transfer_to_qing(qing, _label, Prices.drink_wei(String(d["id"])))
		_busy = false
		if r["ok"]:
			var bal: Variant = r.get("qing_balance", null)
			_result.text = "Verified: AFFECTION Transfer(you → this QING, %s) in block %d.\nThe QING now holds %s (AFFECTION.balanceOf, read at block %d)." % [
				ArcadePay.fmt(r["value"]), r["block"], ArcadePay.fmt(bal) if bal != null else "—", r["block"]]
			_set_status("The round is on you. Cheers!", OK)
			round_bought.emit(r)
			Session.refresh()
		else:
			_set_status("Not bought (%s): %s" % [r.get("stage", "?"), r.get("message", "")], WARN)
			order_failed.emit(d, r)
		_pour.disabled = _blocker() != ""
		return
	# The drink's price first (Prices.DRINKS): AFFECTION.transfer to this QING, its code in the last wei
	var cost := Prices.drink(String(d["id"]))
	if cost > 0 and not _paid_tab.has(String(d["id"])):
		_set_status("Paying %s for the %s…" % [Prices.text(cost), d["name"]], WARN)
		var paid: Dictionary = await ArcadePay.transfer_to_qing(qing, "%s at Sunny's (%s)" % [d["name"], Prices.text(cost)], Prices.drink_wei(String(d["id"])))
		if not paid["ok"]:
			_busy = false
			_pour.disabled = _blocker() != ""
			_set_status("Not paid (%s): %s" % [paid.get("stage", "?"), paid.get("message", "")], WARN)
			return
		_paid_tab[String(d["id"])] = paid
		_set_status("Paid %s in block %d (verified). Now the drink's own call…" % [Prices.text(cost), int(paid["block"])], OK)
	_label = "%s at Sunny's · %s" % [d["name"], BarTab.call_text(d, qing, _seed_value(), _phi.button_pressed)]
	var yue := ""
	if Session.player != null and Session.player.has_yue():
		yue = Session.player.yue
	var res: Dictionary = await BarTab.pour(d, _label, qing, yue, _seed_value(), _phi.button_pressed)
	_busy = false
	_pour.disabled = _blocker() != ""
	if not res["ok"]:
		_set_status("Not poured (%s): %s%s" % [res.get("stage", "?"), res.get("message", ""),
			" · it's paid: pour again without paying" if _paid_tab.has(String(d["id"])) else ""], WARN)
		_refresh_preview()
		order_failed.emit(d, res)
		return
	var paid_for: Dictionary = _paid_tab.get(String(d["id"]), {})
	_paid_tab.erase(String(d["id"]))
	_set_status("Poured. Here's what the chain shows:" + ((" (paid %s in block %d)" % [ArcadePay.fmt(paid_for["value"]), int(paid_for["block"])]) if not paid_for.is_empty() else ""), OK)
	_result.text = BarTab.report(d, res) + ("" if yue != "" else "\n(No YUE on this wallet, so there are no bars to read: —.)")
	poured.emit(d, res)
	Session.refresh()


func _set_status(t: String, c: Color) -> void:
	_status.text = t
	_status.add_theme_color_override("font_color", c)
	status_changed.emit(t, c)


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if label != _label or not _busy:  # the menu may be hidden while the order is out: still follow it
		return
	match stage:
		"simulate": _set_status("Simulating from your wallet…", DeepFieldTheme.ICE)
		"sign": _set_status("Waiting for your signature in the browser wallet…", DeepFieldTheme.ICE)
		"pending": _set_status("Sent %s · waiting for the receipt…" % String(info.get("hash", "")), DeepFieldTheme.ICE)
		"confirmed": _set_status("Mined in block %d (status 1). Reading the chain…" % int(info.get("block", -1)), DeepFieldTheme.ICE)
