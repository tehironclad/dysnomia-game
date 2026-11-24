class_name SwapPanel
extends ExchangePanel
## The Swap Hall's counter: PLS ⇄ Dysnomia tokens on PulseX (PulseX.TOKENS plus
## this territory's own QING token and its asset).
##   - The list is PulseX.read_board(): each token's pairs on both factories and
##     their reserves, read at one block. No pair: "no pool on PulseX", no price.
##   - Quote: the router's getAmountsOut, checked against the reserves maths; price
##     impact from the reserves; slippage → the minimum out; a deadline.
##   - Approve (selling a token): approve(router, amount) through the write rule,
##     allowance re-read at the receipt block.
##   - Swap: simulated from the wallet (with the PLS value for a buy; the
##     fee-on-transfer variant if the plain one hits "PulseX: K"), signed, receipt
##     read, Transfer/WPLS logs checked, balances and the pool re-read at that block.

const SLIPPAGES := [50, 100, 300]
const MODES := ["buy", "sell", "cross"]

var qing := ""
var place := ""
var tokens: Array = []      ## [[address, label], …]
var board: Dictionary = {}
var _sel := -1
var _rows: Array[Button] = []
var _mode: OptionButton
var _target: OptionButton
var _amount: LineEdit
var _slip: OptionButton
var _approve_b: Button
var _swap_b: Button
var _quote: Dictionary = {}
var _ask := 0


## The steps to sign here when the wallet is not ready (AccessSteps).
var _access: AccessSteps

func setup(p_qing: String, p_place: String, asset: String) -> void:
	qing = p_qing.to_lower()
	place = p_place
	tokens = PulseX.TOKENS.duplicate()
	var have := {}
	for t in tokens:
		have[t[0]] = true
	if not have.has(qing):
		tokens.append([qing, ""])
	if asset != "" and not have.has(asset.to_lower()):
		tokens.append([asset.to_lower(), ""])
	set_titles("SWAP HALL · %s" % place.to_upper(),
		"PLS ⇄ Dysnomia tokens on PulseX, PulseChain's DEX. Every number is read from the chain with its block; a token with no pool says so. Each swap is your own call: quoted by the router, simulated from your wallet, signed by you, then its receipt is read and your balances re-read.")
	var r1 := row()
	_mode = OptionButton.new()
	for m in ["Buy with PLS", "Sell for PLS", "Swap for another token"]:
		_mode.add_item(m)
	_mode.item_selected.connect(func(_i): _on_change())
	r1.add_child(_mode)
	_target = OptionButton.new()
	_target.visible = false
	_target.item_selected.connect(func(_i): _on_change())
	r1.add_child(_target)
	var r2 := row()
	var al := Label.new()
	al.text = "Amount in"
	r2.add_child(al)
	_amount = LineEdit.new()
	_amount.placeholder_text = "e.g. 1000"
	_amount.custom_minimum_size = Vector2(220, 0)
	_amount.text_submitted.connect(func(_t): quote())
	r2.add_child(_amount)
	button("Max", _max, r2)
	var sl := Label.new()
	sl.text = "  slippage"
	r2.add_child(sl)
	_slip = OptionButton.new()
	for s in SLIPPAGES:
		_slip.add_item("%.1f%%" % (s / 100.0))
	_slip.select(1)
	_slip.item_selected.connect(func(_i): quote())
	r2.add_child(_slip)
	finish_layout()
	button("Quote", quote)
	_approve_b = button("Approve", _do_approve)
	_swap_b = button("Swap", _do_swap)
	button("Refresh", refresh)
	_approve_b.visible = false
	_swap_b.disabled = true


func open() -> void:
	show_panel()
	if board.is_empty():
		await refresh()


## Re-reads every pool and the wallet's balances at one block.
func refresh(block = "latest") -> void:
	say("Reading every pool on PulseX V1 and V2 at one block…")
	var b: Dictionary = await PulseX.read_board(tokens, reader())
	if not b["ok"]:
		say("The chain did not answer: %s. Nothing is shown rather than a guess." % b.get("error", ""), BAD)
		info.text = "—"
		return
	board = b
	_fill_list()
	say("Pools read at %s%s." % [blk(b["block"]), "" if b["routers_ok"] else " · ⚠ a router's factory()/WPLS() did not match: swaps are off"], OK if b["routers_ok"] else BAD)
	if _sel < 0:
		for i in board["tokens"].size():
			if board["tokens"][i]["best"] != "":
				_select(i)
				break
	else:
		_select(_sel)


func _fill_list() -> void:
	for c in list.get_children():
		c.queue_free()
	_rows.clear()
	_target.clear()
	var group := ButtonGroup.new()
	for i in board["tokens"].size():
		var t: Dictionary = board["tokens"][i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", DeepFieldTheme.mono_font())
		b.add_theme_font_size_override("font_size", 12)
		b.text = list_line(t, qing)
		b.pressed.connect(_select.bind(i))
		list.add_child(b)
		_rows.append(b)
		_target.add_item(t["name"])
		_target.set_item_disabled(i, t["best"] == "")


## One line of the token list: name, its deeper pool's mid price, or "no pool".
static func list_line(t: Dictionary, p_qing: String) -> String:
	var tag := " (this QING)" if t["address"] == p_qing else ""
	if t["decimals"] < 0:
		return "%s%s\n   decimals() did not read: —" % [t["name"], tag]
	if t["best"] == "":
		return "%s%s\n   no pool on PulseX" % [t["name"], tag]
	var p: Dictionary = t["pools"][t["best"]]
	return "%s%s\n   %s PLS · %s · %s WPLS deep" % [t["name"], tag, PulseX.fmt(PulseX.price_wei(p["wpls"], p["token"], t["decimals"]), 18, 4),
		t["best"], PulseX.fmt(p["wpls"], 18, 1)]


func _select(i: int) -> void:
	if board.is_empty() or i < 0 or i >= board["tokens"].size():
		return
	_sel = i
	_rows[i].button_pressed = true
	_on_change()


func _on_change() -> void:
	_target.visible = _mode.selected == 2
	_quote = {}
	_swap_b.disabled = true
	_approve_b.visible = false
	result.text = ""
	info.text = token_card(board, _sel, reader())
	if _amount.text.strip_edges() != "":
		quote()


## The selected token's facts: pools, reserves with their block, your balances.
static func token_card(b: Dictionary, i: int, wallet: String) -> String:
	if b.is_empty() or i < 0:
		return "—"
	var t: Dictionary = b["tokens"][i]
	var lines: Array = ["%s · %s (symbol() %s, decimals() %s)" % [t["name"], t["address"], t["symbol"], str(t["decimals"]) if t["decimals"] >= 0 else "—"]]
	if t["pools"].is_empty():
		lines.append("No pool on PulseX: getPair(WPLS, token) is 0x0 on both factories at %s. No price is shown." % blk(b["block"]))
	for v in PulseX.VERSIONS:
		if t["pools"].has(v):
			var p: Dictionary = t["pools"][v]
			lines.append("%s pool %s%s: %s WPLS / %s %s · mid %s PLS each (getReserves · %s)" % [v, short(p["pair"]), " (used)" if v == t["best"] else "",
				PulseX.fmt(p["wpls"], 18, 2), PulseX.fmt(p["token"], maxi(t["decimals"], 0), 4), t["symbol"],
				PulseX.fmt(PulseX.price_wei(p["wpls"], p["token"], maxi(t["decimals"], 0)), 18, 4), blk(b["block"])])
	if wallet == "":
		lines.append("Your balances: connect a wallet (reads need none; swaps need one to sign).")
	else:
		lines.append("Your wallet %s: %s PLS · %s %s (%s)" % [short(wallet), PulseX.fmt(b["pls"], 18, 4) if b["pls"] != null else "—",
			PulseX.fmt(t["balance"], maxi(t["decimals"], 0), 6) if t["balance"] != null else "—", t["symbol"], blk(b["block"])])
	return "\n".join(lines)


func _max() -> void:
	if board.is_empty() or _sel < 0:
		return
	var t: Dictionary = board["tokens"][_sel]
	if MODES[_mode.selected] == "buy":
		if board["pls"] == null:
			return
		# Leave 1,000 PLS for gas
		var keep := BigInt.from_decimal("1000000000000000000000")
		var v: PackedInt64Array = BigInt.sub(board["pls"], keep) if BigInt.cmp(board["pls"], keep) > 0 else BigInt.zero()
		_amount.text = TokenFormat.wei_to_tokens(v, 18, 18).replace(",", "")
	elif t["balance"] != null:
		_amount.text = _plain(t["balance"], t["decimals"])
	quote()


static func _plain(wei: PackedInt64Array, decimals: int) -> String:
	var s := BigInt.to_decimal(wei).lpad(decimals + 1, "0")
	var ip := s.substr(0, s.length() - decimals)
	var fp := s.substr(s.length() - decimals).rstrip("0")
	return ip + ("." + fp if fp != "" else "")


## Quote: route, router getAmountsOut (live), reserves maths, impact, minimum, the
## approval needed, and a simulation from the wallet when nothing blocks it.
func quote() -> void:
	if board.is_empty() or _sel < 0:
		return
	_ask += 1
	var ask := _ask
	_quote = {}
	_swap_b.disabled = true
	_approve_b.visible = false
	var t: Dictionary = board["tokens"][_sel]
	var kind: String = MODES[_mode.selected]
	var other: Dictionary = board["tokens"][_target.selected] if kind == "cross" and _target.selected >= 0 else {}
	var dec_in: int = 18 if kind == "buy" else int(t["decimals"])
	var dec_out: int = int(t["decimals"]) if kind == "buy" else (18 if kind == "sell" else int(other.get("decimals", -1)))
	if dec_in < 0 or dec_out < 0:
		result.text = "decimals() did not read: no quote (—)."
		return
	var v := "" if kind == "cross" else String(t["best"])
	if kind == "cross":
		if other.is_empty() or other["address"] == t["address"]:
			result.text = "Pick a different token to swap into."
			return
		v = PulseX.shared_router(t, other)
		if v == "":
			result.text = "No PulseX router has pools for both %s and %s: swap to PLS first, then buy." % [t["name"], other.get("name", "?")]
			return
	if v == "":
		result.text = "No pool on PulseX for %s: nothing to quote." % t["name"]
		return
	var parsed := PulseX.parse_units(_amount.text, dec_in)
	if parsed.is_empty() or BigInt.is_zero(parsed["wei"]):
		result.text = "Enter an amount (up to %d decimals)." % dec_in
		return
	var amount_in: PackedInt64Array = parsed["wei"]
	var router := PulseX.router_of(v)
	var path := PulseX.path_for(kind, t["address"], t["address"] if kind == "buy" else String(other.get("address", "")))
	var sym_in := "PLS" if kind == "buy" else String(t["symbol"])
	var sym_out: String = String(t["symbol"]) if kind == "buy" else ("PLS" if kind == "sell" else String(other["symbol"]))
	result.text = "Quoting on PulseX %s…" % v
	var q: Dictionary = await Chain.rpc.eth_call(router, PulseX.amounts_out_call(amount_in, path))
	if ask != _ask:
		return
	var amts: Array = PulseX.decode_amounts(q.get("result", "")) if q["ok"] else []
	if amts.size() != path.size():
		result.text = "The router's getAmountsOut did not answer: %s. No quote (—)." % why(q)
		return
	var out: PackedInt64Array = amts[amts.size() - 1]
	# The same from the reserves read at the board's block
	var hops: Array = []
	var impact := 0.0
	var keep := 1.0
	for h in path.size() - 1:
		var tok: Dictionary = t if (h == 0 and kind != "buy") or (kind == "buy") else other
		var p: Dictionary = tok["pools"][v]
		var into_token: bool = path[h] == Contracts.WPLS
		var rin: PackedInt64Array = p["wpls"] if into_token else p["token"]
		var rout: PackedInt64Array = p["token"] if into_token else p["wpls"]
		hops.append([rin, rout])
		var amt_h: PackedInt64Array = amts[h]
		keep *= 1.0 - PulseX.impact_bps(amt_h, rin, rout) / 10000.0
	impact = (1.0 - keep) * 100.0
	var local: Array = PulseX.amounts_out(amount_in, hops)
	var slip: int = SLIPPAGES[_slip.selected]
	var minimum := PulseX.min_out(out, slip)
	var wallet := reader()
	var lines: Array = []
	var hops_txt := " → ".join(PackedStringArray(path.map(func(a): return "WPLS" if a == Contracts.WPLS else _sym_of(a))))
	if kind == "buy":
		hops_txt = "PLS → " + hops_txt
	elif kind == "sell":
		hops_txt += " → PLS"
	lines.append("Route: %s on PulseX %s (router %s)" % [hops_txt, v, short(router)])
	lines.append("Quote: %s %s → %s %s (router getAmountsOut, latest block) · from the reserves at %s: %s" % [PulseX.fmt(amount_in, dec_in, 6), sym_in,
		PulseX.fmt(out, dec_out, 6), sym_out, blk(board["block"]), PulseX.fmt(local[local.size() - 1], dec_out, 6)])
	lines.append("Price impact %.2f%% (includes PulseX's 0.29%% fee per hop) · slippage %.1f%% → you get at least %s %s · deadline: 20 min" % [impact, slip / 100.0, PulseX.fmt(minimum, dec_out, 6), sym_out])
	if impact > 5.0:
		lines.append("⚠ This moves the pool by more than 5%: the pool is thin for this size.")
	var need_approve := false
	if wallet != "":
		var bal = board["pls"] if kind == "buy" else t["balance"]
		if bal != null and BigInt.cmp(bal, amount_in) < 0:
			lines.append("⚠ Your wallet holds %s %s (%s): less than the amount." % [PulseX.fmt(bal, dec_in, 6), sym_in, blk(board["block"])])
		if kind != "buy":
			var al = await read_allowance(t["address"], wallet, router)
			if ask != _ask:
				return
			if al == null:
				lines.append("Allowance to the router: — (the read failed)")
			else:
				need_approve = BigInt.cmp(al, amount_in) < 0
				lines.append("Allowance to the %s router: %s %s%s" % [v, PulseX.fmt(al, dec_in, 6), sym_in, " → approve first" if need_approve else " (enough)"])
	_quote = {"kind": kind, "v": v, "router": router, "path": path, "amount_in": amount_in, "min_out": minimum, "out": out,
		"token_in": "" if kind == "buy" else String(t["address"]), "token_out": String(t["address"]) if kind == "buy" else String(other.get("address", "")),
		"sym_in": sym_in, "sym_out": sym_out, "dec_in": dec_in, "dec_out": dec_out, "need_approve": need_approve}
	if wallet != "" and not need_approve:
		var sim := await _simulate(_quote, wallet)
		if ask != _ask:
			return
		lines.append("Simulated from your wallet: %s" % ("OK%s" % (" (fee-on-transfer variant)" if sim.get("fot", false) else "") if sim["ok"] else "would fail: " + String(sim["message"])))
		_quote["fot"] = sim.get("fot", false)
	result.text = "\n".join(lines)
	_approve_b.visible = need_approve
	_approve_b.text = "Approve %s %s" % [PulseX.fmt(amount_in, dec_in, 6), sym_in]
	_approve_b.disabled = Wallet.address == "" or busy
	_swap_b.disabled = Wallet.address == "" or need_approve or busy or not board["routers_ok"]
	_swap_b.text = "Swap" if Wallet.address != "" else "Swap (connect a wallet to sign)"
	if _access == null:
		_access = AccessSteps.embed(result.get_parent(), result.get_index() + 1)
	_access.update_for(ChatController._signer_blocker(), "swap", {"title": "Swap on PulseX"})


func _sym_of(a: String) -> String:
	for t in board.get("tokens", []):
		if t["address"] == a:
			return String(t["symbol"])
	return short(a)


## Simulates the swap from `wallet` at the latest block (deadline from that block's
## time). Retries with the fee-on-transfer variant when the plain one hits "PulseX: K".
## {ok, data, fot, message}
static func _simulate(q: Dictionary, wallet: String) -> Dictionary:
	var blk_r: Dictionary = await Chain.rpc.get_block("latest")
	var ts := String(blk_r.get("result", {}).get("timestamp", "0x0")).hex_to_int() if blk_r["ok"] and blk_r["result"] is Dictionary else int(Time.get_unix_time_from_system())
	var deadline := ts + PulseX.DEADLINE_S
	var value := ("0x" + BigInt.to_hex(q["amount_in"])) if q["kind"] == "buy" else ""
	var data := PulseX.swap_call(q["kind"], q["amount_in"], q["min_out"], q["path"], wallet, deadline)
	var sim: Dictionary = await Chain.rpc.eth_call(q["router"], data, wallet, "latest", value)
	if sim["ok"]:
		return {"ok": true, "data": data, "fot": false, "value": value}
	var msg := String(sim.get("revert", {}).get("message", ""))
	if PulseX.wants_fot(msg):
		var data2 := PulseX.swap_call(q["kind"], q["amount_in"], q["min_out"], q["path"], wallet, deadline, true)
		var sim2: Dictionary = await Chain.rpc.eth_call(q["router"], data2, wallet, "latest", value)
		if sim2["ok"]:
			return {"ok": true, "data": data2, "fot": true, "value": value}
	return {"ok": false, "message": why(sim)}


func _do_approve() -> void:
	if busy or _quote.is_empty():
		return
	busy = true
	_approve_b.disabled = true
	var r := await approve(_quote["token_in"], _quote["sym_in"], _quote["router"], "PulseX %s router" % _quote["v"], _quote["amount_in"], _quote["dec_in"])
	busy = false
	if r["ok"]:
		say("Approved: the router's allowance re-reads as %s %s at %s. Now Swap." % [PulseX.fmt(r["allowance"], _quote["dec_in"], 6), _quote["sym_in"], blk(r["block"])], OK)
		await quote()
	else:
		say("Not approved: %s" % r["message"], BAD)
		_approve_b.disabled = false


func _do_swap() -> void:
	if busy or _quote.is_empty() or Wallet.address == "":
		return
	busy = true
	_swap_b.disabled = true
	var q := _quote
	var wallet := Wallet.address
	var sim := await _simulate(q, wallet)
	if not sim["ok"]:
		busy = false
		say("Not sent: the simulation says it would fail: %s" % sim["message"], BAD)
		return
	var label := "Swap %s %s → ≥ %s %s on PulseX %s" % [PulseX.fmt(q["amount_in"], q["dec_in"], 6), q["sym_in"], PulseX.fmt(q["min_out"], q["dec_out"], 6), q["sym_out"], q["v"]]
	track(label)
	var res: Dictionary = await Wallet.send(label, q["router"], sim["data"], sim["value"] if sim["value"] != "" else "0x0")
	busy = false
	if not res["ok"]:
		return  # the status line already says where it stopped
	var rec: Dictionary = res["receipt"]
	var v := PulseX.verify_swap(rec, q["kind"], wallet, q["token_in"], q["token_out"])
	var lines: Array = []
	if not v["ok"]:
		lines.append("Mined in block %d, but the receipt does not show the swap: %s" % [res["block"], v["message"]])
	else:
		lines.append("Done, verified in the receipt (block %d, tx %s): paid %s %s, received %s %s%s." % [res["block"], short(res["hash"]),
			PulseX.fmt(v["sent"], q["dec_in"], 6), q["sym_in"], PulseX.fmt(v["received"], q["dec_out"], 6), q["sym_out"],
			" (WPLS Withdrawal to the router, paid out as PLS)" if q["kind"] == "sell" else " (Transfer to your wallet)"])
		if q["kind"] == "sell":
			var got = await pls_delta(wallet, res["block"], rec)
			if got != null:
				lines.append("Your PLS balance change at block %d, plus the gas you paid: +%s PLS." % [res["block"], PulseX.fmt(got, 18, 6)])
	await refresh(res["block"])
	lines.append("Re-read at %s: %s" % [blk(board.get("block", -1)), token_card(board, _sel, wallet).split("\n")[-1]])
	result.text = "\n".join(lines)
	say("Swap confirmed by its receipt; balances and the pool re-read.", OK)


## PLS received by `wallet` in `block`: balance(block) − balance(block−1) + gas paid. null if a read failed.
static func pls_delta(wallet: String, block: int, rec: Dictionary) -> Variant:
	var a: Dictionary = await Chain.rpc.request("eth_getBalance", [wallet, "0x%x" % (block - 1)])
	var b: Dictionary = await Chain.rpc.request("eth_getBalance", [wallet, "0x%x" % block])
	if not a["ok"] or not b["ok"]:
		return null
	var gas := BigInt.mul(BigInt.from_hex(String(rec.get("gasUsed", "0x0"))), BigInt.from_hex(String(rec.get("effectiveGasPrice", "0x0"))))
	var after := BigInt.add(BigInt.from_hex(String(b["result"])), gas)
	var before := BigInt.from_hex(String(a["result"]))
	return BigInt.sub(after, before) if BigInt.cmp(after, before) >= 0 else BigInt.zero()
