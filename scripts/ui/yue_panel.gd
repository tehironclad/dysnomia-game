class_name YuePanel
extends ExchangePanel
## The YUE Exchange desk: Hong (buy a QING's token with its asset) and Hung (sell
## it back), at the QING's fixed market rate, against any YUE that holds the stock.
##   - The list: this territory first, then every territory with a rate
##     (YueExchange.rated_scan(), one block).
##   - The pair: QING.Asset(), GetMarketRate / GetAssetRate / IsValidAsset, every
##     known YUE's stock and your balances (YueExchange.read_desk(), one block).
##   - The desk: the YUE holding the most of what you receive (yours on a tie);
##     "Next desk" walks the others that can pay.
##   - Approve the pay token to that YUE (simulated, signed, receipt, allowance
##     re-read), then Hong/Hung (simulated, signed, receipt: both Transfer legs
##     checked), then the desk re-read at the receipt block.

const KINDS := ["hong", "hung"]

var qing := ""
var place := ""
var asset := ""
var _items: Array = []       ## [{qing, name, asset, rate}]
var _sel := -1
var _desk: Dictionary = {}   ## read_desk() for the selected pair
var _desk_i := -1
var _rows: Array[Button] = []
var _kind: OptionButton
var _amount: LineEdit
var _approve_b: Button
var _go_b: Button
var _next_b: Button
var _plan: Dictionary = {}
var _ask := 0


func setup(p_qing: String, p_place: String, p_asset: String, where: String) -> void:
	qing = p_qing.to_lower()
	place = p_place
	asset = p_asset.to_lower()
	set_titles("YUE EXCHANGE · %s" % where.to_upper(),
		"Every YUE is a public desk for QING tokens at the territory's fixed rate (QING.GetMarketRate, set by its owners; rates only rise). Hong buys a territory's token with its asset, Hung sells it back. The desk pays only from its own stock, and what you pay stays in that YUE. Approve the desk first, then trade; every step is simulated, signed by you and checked in its receipt.")
	var r1 := row()
	_kind = OptionButton.new()
	_kind.add_item("Hong: buy the territory's token, pay its asset")
	_kind.add_item("Hung: sell the territory's token, get its asset")
	_kind.item_selected.connect(func(_i): _plan_trade())
	r1.add_child(_kind)
	var r2 := row()
	var al := Label.new()
	al.text = "Tokens (the QING's)"
	r2.add_child(al)
	_amount = LineEdit.new()
	_amount.placeholder_text = "e.g. 0.001"
	_amount.custom_minimum_size = Vector2(200, 0)
	_amount.text_submitted.connect(func(_t): _plan_trade())
	r2.add_child(_amount)
	button("Check", _plan_trade, r2)
	_next_b = button("Next desk", _next_desk, r2)
	finish_layout()
	_approve_b = button("Approve", _do_approve)
	_go_b = button("Exchange", _do_trade)
	button("Refresh", func(): _load_pair(_sel))
	_approve_b.visible = false
	_go_b.disabled = true


func open() -> void:
	show_panel()
	if _items.is_empty():
		await refresh()


func refresh() -> void:
	say("Scanning every territory for a market rate…")
	var rated = await YueExchange.rated_scan()
	_items = [{"qing": qing, "name": place, "asset": asset, "rate": null, "here": true}]
	if rated == null:
		say("The rate scan did not answer; this territory's pair only.", WARN)
	else:
		for r in rated:
			if r["qing"] == qing:
				_items[0]["rate"] = r["rate"]
				continue
			_items.append(r)
	for c in list.get_children():
		c.queue_free()
	_rows.clear()
	var group := ButtonGroup.new()
	for i in _items.size():
		var it: Dictionary = _items[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", DeepFieldTheme.mono_font())
		b.add_theme_font_size_override("font_size", 12)
		b.text = item_line(it, rated != null, YueExchange.rated_block())
		b.pressed.connect(_load_pair.bind(i))
		list.add_child(b)
		_rows.append(b)
	await _load_pair(0)


static func item_line(it: Dictionary, scanned: bool, block: int) -> String:
	var name := String(it.get("name", "")).left(30)
	if it.get("here", false):
		name = "HERE · " + name
	if it.get("rate") == null:
		return "%s\n   %s" % [name, ("no rate set (%s)" % blk(block)) if scanned else "rate —"]
	return "%s\n   %s asset per token (%s)" % [name, PulseX.fmt(it["rate"], 18, 6), blk(block)]


func _load_pair(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	_sel = i
	_rows[i].button_pressed = true
	_ask += 1
	var ask := _ask
	var it: Dictionary = _items[i]
	info.text = "Reading %s's pair and every known YUE's stock…" % it["name"]
	var own := ""
	if Session.player != null and Session.player.has_yue():
		own = Session.player.yue
	var d: Dictionary = await YueExchange.read_desk(it["qing"], String(it.get("asset", "")), reader(), own)
	if ask != _ask:
		return
	_desk = d
	_desk_i = -1
	info.text = desk_card(d, String(it["name"]))
	_plan_trade()


## The pair's facts: rate (with its block), validity, desks with stock, your balances.
static func desk_card(d: Dictionary, name: String) -> String:
	if not d.get("ok", false):
		return "%s: %s. Nothing is shown rather than a guess (—)." % [name, d.get("error", "the chain did not answer")]
	var p: Dictionary = d["pairs"][0]
	var lines: Array = ["%s · token %s (%s) · asset %s (%s, QING.Asset())" % [name, d["qing_symbol"], short(d["qing"]), p["symbol"], short(d["asset"])]]
	var rate = p["rate"]
	if rate == null:
		lines.append("Rate: — (YUE.GetAssetRate did not read)")
	elif BigInt.is_zero(rate):
		lines.append("Rate: 0. This territory has set no market rate for its asset (QING.GetMarketRate = %s), so every YUE refuses: ExchangeRateNotFound. %s" % [
			BigInt.to_decimal(p["market_rate"]) if p["market_rate"] != null else "—", blk(d["block"])])
	else:
		lines.append("Rate: 1 %s = %s %s (YUE.GetAssetRate %s · IsValidAsset %s · %s)" % [d["qing_symbol"], PulseX.fmt(rate, 18, 8), p["symbol"],
			BigInt.to_decimal(rate), str(p["valid"]) if p["valid"] != null else "—", blk(d["block"])])
	for k in range(1, d["pairs"].size()):
		var up: Dictionary = d["pairs"][k]
		lines.append("Up the hierarchy: %s · rate %s · IsValidAsset %s" % [up["symbol"], BigInt.to_decimal(up["rate"]) if up["rate"] != null else "—", str(up["valid"])])
	var with_stock := 0
	var shown := 0
	for desk in d["desks"]:
		var sq = desk["stock_qing"]
		var sa = desk["stock_asset"]
		var has: bool = (sq != null and not BigInt.is_zero(sq)) or (sa != null and not BigInt.is_zero(sa))
		if has:
			with_stock += 1
		if (has or desk["own"]) and shown < 6:
			shown += 1
			lines.append("  desk YUE %s%s: %s %s · %s %s" % [short(desk["yue"]), " (yours)" if desk["own"] else "",
				PulseX.fmt(sq, 18, 6) if sq != null else "—", d["qing_symbol"], PulseX.fmt(sa, 18, 6) if sa != null else "—", p["symbol"]])
	lines.append("%d of %d known YUEs hold stock (balanceOf · %s)" % [with_stock, d["desks"].size(), blk(d["block"])])
	var w: Dictionary = d["wallet"]
	if w["qing"] != null or w["asset"] != null:
		lines.append("Your wallet: %s %s · %s %s" % [PulseX.fmt(w["qing"], 18, 6) if w["qing"] != null else "—", d["qing_symbol"],
			PulseX.fmt(w["asset"], 18, 6) if w["asset"] != null else "—", p["symbol"]])
	return "\n".join(lines)


func _rate() -> Variant:
	if _desk.is_empty() or not _desk.get("ok", false):
		return null
	return _desk["pairs"][0]["rate"]


## The desks that can pay `need` of what this trade gives, best first.
func _payers(kind: String, need: PackedInt64Array) -> Array:
	var key := "stock_qing" if kind == "hong" else "stock_asset"
	var out: Array = []
	for d in _desk.get("desks", []):
		if d[key] != null and BigInt.cmp(d[key], need) >= 0 and not BigInt.is_zero(d[key]):
			out.append(d)
	var best := YueExchange.pick_desk(out, kind, need)
	if not best.is_empty():
		out.erase(best)
		out.push_front(best)
	return out


func _next_desk() -> void:
	_desk_i += 1
	_plan_trade(true)


func _plan_trade(keep_desk: bool = false) -> void:
	_plan = {}
	_approve_b.visible = false
	_go_b.disabled = true
	var rate = _rate()
	if rate == null or BigInt.is_zero(rate):
		result.text = "No trade: %s." % ("the rate did not read (—)" if rate == null else "this territory has no market rate for its asset")
		return
	var parsed := PulseX.parse_units(_amount.text, 18)
	if parsed.is_empty() or BigInt.is_zero(parsed["wei"]):
		result.text = "Enter how many of the territory's tokens (up to 18 decimals)."
		return
	var kind: String = KINDS[_kind.selected]
	var l := YueExchange.legs(kind, _desk["qing"], _desk["asset"], parsed["wei"], rate)
	if BigInt.is_zero(l["pay"]) or BigInt.is_zero(l["get"]):
		result.text = "At this rate that amount rounds to nothing on one side; try more."
		return
	var payers := _payers(kind, l["get"])
	if payers.is_empty():
		result.text = "No known YUE holds %s %s to pay you. A desk pays only from its own stock." % [PulseX.fmt(l["get"], 18, 6), _sym(l["get_token"])]
		return
	if not keep_desk:
		_desk_i = 0
	var desk: Dictionary = payers[_desk_i % payers.size()]
	_plan = {"kind": kind, "legs": l, "desk": desk, "amount": parsed["wei"]}
	var lines: Array = ["%s at desk YUE %s%s (%d of %d desks can pay): you pay %s %s, you get %s %s" % [kind.to_upper(), short(desk["yue"]), " (yours)" if desk["own"] else "",
		(_desk_i % payers.size()) + 1, payers.size(), PulseX.fmt(l["pay"], 18, 8), _sym(l["pay_token"]), PulseX.fmt(l["get"], 18, 8), _sym(l["get_token"])]]
	lines.append("Cost = amount × rate ÷ 10^18, rounded down (the YUE's own formula).")
	var w: Dictionary = _desk["wallet"]
	var have = w["asset"] if kind == "hong" else w["qing"]
	if have != null and BigInt.cmp(have, l["pay"]) < 0:
		lines.append("⚠ Your wallet holds %s %s: less than you would pay." % [PulseX.fmt(have, 18, 8), _sym(l["pay_token"])])
	result.text = "\n".join(lines)
	_check_allowance(_ask)


func _check_allowance(ask: int) -> void:
	var wallet := reader()
	if wallet == "" or _plan.is_empty():
		_go_b.text = "Exchange (connect a wallet to sign)"
		return
	var l: Dictionary = _plan["legs"]
	var al = await read_allowance(l["pay_token"], wallet, _plan["desk"]["yue"])
	if ask != _ask or _plan.is_empty():
		return
	var need: bool = al == null or BigInt.cmp(al, l["pay"]) < 0
	_plan["need_approve"] = need
	result.text += "\nAllowance to this YUE: %s%s" % [PulseX.fmt(al, 18, 8) + " " + _sym(l["pay_token"]) if al != null else "— (the read failed)", " → approve first" if need else " (enough)"]
	if not need:
		var sim := await Wallet.simulate(_plan["desk"]["yue"], _call(), wallet)
		if ask != _ask:
			return
		result.text += "\nSimulated from your wallet: %s" % ("OK" if sim["ok"] else "would fail: " + why(sim))
	_approve_b.visible = need
	_approve_b.text = "Approve %s %s to the desk" % [PulseX.fmt(l["pay"], 18, 8), _sym(l["pay_token"])]
	_approve_b.disabled = Wallet.address == "" or busy
	_go_b.disabled = Wallet.address == "" or need or busy
	_go_b.text = "Exchange" if Wallet.address != "" else "Exchange (connect a wallet to sign)"


func _call() -> String:
	var l: Dictionary = _plan["legs"]
	if _plan["kind"] == "hong":
		return YueExchange.hong_call(_desk["asset"], _desk["qing"], _plan["amount"])
	return YueExchange.hung_call(_desk["qing"], _desk["asset"], _plan["amount"])


func _sym(token: String) -> String:
	if _desk.is_empty():
		return "?"
	if token == _desk["qing"]:
		return String(_desk["qing_symbol"])
	return String(_desk["pairs"][0]["symbol"])


func _do_approve() -> void:
	if busy or _plan.is_empty():
		return
	busy = true
	_approve_b.disabled = true
	var l: Dictionary = _plan["legs"]
	var r := await approve(l["pay_token"], _sym(l["pay_token"]), _plan["desk"]["yue"], "YUE %s" % short(_plan["desk"]["yue"]), l["pay"], 18)
	busy = false
	if r["ok"]:
		say("Approved: the desk's allowance re-reads as %s %s at %s. Now Exchange." % [PulseX.fmt(r["allowance"], 18, 8), _sym(l["pay_token"]), blk(r["block"])], OK)
		_plan_trade(true)
	else:
		say("Not approved: %s" % r["message"], BAD)
		_approve_b.disabled = false


func _do_trade() -> void:
	if busy or _plan.is_empty() or Wallet.address == "":
		return
	busy = true
	_go_b.disabled = true
	var plan := _plan
	var l: Dictionary = plan["legs"]
	var label := "%s %s %s at YUE %s" % ["Hong: buy" if plan["kind"] == "hong" else "Hung: sell", PulseX.fmt(plan["amount"], 18, 8), _desk["qing_symbol"], short(plan["desk"]["yue"])]
	track(label)
	var res: Dictionary = await Wallet.send(label, plan["desk"]["yue"], _call())
	busy = false
	if not res["ok"]:
		if res.has("revert"):
			result.text = "The contract's reason: %s" % res["revert"].get("message", "")
		return
	var v := YueExchange.verify(res["receipt"], Wallet.address, plan["desk"]["yue"], l)
	var head := ("Done, verified in the receipt (block %d, tx %s): paid %s %s into the YUE, received %s %s from it." % [res["block"], short(res["hash"]),
		PulseX.fmt(v["paid"], 18, 8), _sym(l["pay_token"]), PulseX.fmt(v["got"], 18, 8), _sym(l["get_token"])]) if v["ok"] else \
		"Mined in block %d, but the receipt does not show both legs: %s" % [res["block"], v["message"]]
	await _load_pair(_sel)
	result.text = head + "\nRe-read at %s:\n%s" % [blk(_desk.get("block", -1)), info.text.split("\n")[-1]]
	say("Exchange confirmed by its receipt; the desk and your balances re-read.", OK)
