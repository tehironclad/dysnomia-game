class_name CoreActions
extends CanvasLayer
## The live moves at a territory (WP 5.1, 5.3, 5.4, 5.5). Each one is
## preview (simulated from the wallet, pinned to a block) → sign → receipt
## verified from the chain → state re-read; success is reported from the
## re-read, never from the wallet page.
##
## - Su at the pylons (CHEON.Su): the bar delta is checked by reading
##   YUE.Bar(QING) at the receipt's block.
## - The Room and the Void are places now (scripts/places): the door leads
##   into the QING's hall, the monolith into the Void (ChatController).
## - Beat at the Heart (META.Beat(Waat)): gated by readiness, so a wallet that
##   would panic sees the diagnosis instead of a doomed transaction.

signal opened
signal closed

var territory: Dictionary = {}
var qing := ""
var state: TerritoryState
var core: TerritoryCore
var hud: HudV2
var phenomena: Phenomena
var monolith: VoidMonolith
var lattice: WorldLattice
var action: ActionPanel
var _busy := false


func setup(q: Dictionary, p_state: TerritoryState, p_core: TerritoryCore, p_hud: HudV2, p_phen: Phenomena, p_mono: VoidMonolith) -> void:
	territory = q
	qing = String(q["address"]).to_lower()
	state = p_state
	core = p_core
	hud = p_hud
	phenomena = p_phen
	monolith = p_mono
	layer = 20
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)
	action = ActionPanel.new()
	stack.add_child(action)
	action.closed.connect(_on_closed)
	Wallet.tx_stage.connect(func(_l, stage, _i):
		if stage == "failed": Cues.play(self, "fail")
		elif stage == "confirmed": Cues.play(self, "confirm"))


func is_open() -> bool:
	return action.is_open()


func _on_closed() -> void:
	if not is_open():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		closed.emit()


func _open_action(title: String) -> void:
	action.show_panel(title)
	opened.emit()


func _tname() -> String:
	return String(territory.get("name", qing))


## Can this session sign? (A --session view or a different wallet cannot.)
func _signer_blocker() -> String:
	if Wallet.address == "":
		return "View only: connect this wallet at the front door to sign."
	if Wallet.address != Session.wallet:
		return "The connected wallet differs from the session's."
	if not Wallet.is_connected_to_chain():
		return "Switch the wallet to PulseChain (369)."
	return ""


func _identity_blocker(need_yue: bool) -> String:
	if Session.wallet == "":
		return "Connect a wallet at the front door: previews are simulated from your own wallet."
	var ps: PlayerState = Session.player
	if ps == null:
		return "Reading your identity… try again in a moment."
	if ps.error != "":
		return "Couldn't read your identity from the chain: %s. Check the RPC in Settings, or try again." % ps.error
	if not ps.has_lau():
		return "No LAU yet: Enter the Void at the front door to create your identity."
	if need_yue and not ps.has_yue():
		return "No YUE yet: wake it (SEI.Start) at the front door."
	return ""


# --- Su ---------------------------------------------------------------------

func open_su() -> void:
	_open_action("SU · react with %s" % _tname())
	var omega := state.omega.display(func(v): return TokenFormat.group(BigInt.to_decimal(BigInt.coerce(v))))
	var ib := _identity_blocker(true)
	if ib != "":
		action.set_body("Ω here: %s Hypobar per Su (Fornax held here ÷ Entropy, the same for everyone).\n\n%s" % [omega, ib])
		return
	var ps: PlayerState = Session.player
	var p: Dictionary = await Moves.su_preview(Session.wallet, ps.yue, qing)
	if not action.is_open():
		return
	if not p["ok"]:
		action.set_body(p["message"] + _hint(p))
		return
	action.set_body("\n".join(p["lines"]) + "\n\nSimulated from your wallet at block %d." % p["block"])
	var sb := _signer_blocker()
	action.set_status(sb)
	action.set_primary("Sign Su", sb == "", _do_su.bind(p))


func _do_su(p: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	action.set_primary("Sign Su", false, Callable())
	var label := "Su at %s" % _tname()
	action.track(label)
	var res: Dictionary = await Wallet.send(label, p["to"], p["data"])
	_busy = false
	if not res["ok"]:
		return
	var ps: PlayerState = Session.player
	var r: Dictionary = await Chain.rpc.call_decoded(ps.yue, "Bar(address)", [qing], ["uint256", "uint256"], "", res["block"])
	if r["ok"]:
		var hb := BigInt.from_hex(r["values"][0])
		var eb := BigInt.from_hex(r["values"][1])
		var v: Dictionary = p["values"]
		var dh := BigInt.sub(hb, v["hypo_before"]) if BigInt.cmp(hb, v["hypo_before"]) >= 0 else PackedInt64Array()
		var de := BigInt.sub(eb, v["epi_before"]) if BigInt.cmp(eb, v["epi_before"]) >= 0 else PackedInt64Array()
		action.set_status("Confirmed in block %d. Your bars here, read at that block: %s Hypobar (+%s) · %s Epibar (+%s)." % [
			res["block"], TokenFormat.group(BigInt.to_decimal(hb)), TokenFormat.group(BigInt.to_decimal(dh)),
			TokenFormat.group(BigInt.to_decimal(eb)), TokenFormat.group(BigInt.to_decimal(de))], Color("#64e3a8"))
		hud.ticker("YOUR SU · +%s Hypobar · block %d" % [TokenFormat.group(BigInt.to_decimal(dh)), res["block"]], Color("#64e3a8"))
	else:
		action.set_status("Mined in block %d (status 1), but the bar re-read failed: —. It will show on the next refresh." % res["block"], Color("#ffd27a"))
	core.cascade(0.7)
	Cues.play(self, "cascade")
	state.refresh()
	Session.refresh()


func _hint(p: Dictionary) -> String:
	if p.has("revert"):
		var nm := String(p["revert"].get("name", ""))
		if Contracts.ERROR_HINTS.has(nm):
			return "\n\n" + String(Contracts.ERROR_HINTS[nm])
	return ""


# --- Beat ---------------------------------------------------------------------

func open_beat() -> void:
	_open_action("BEAT · the Heart of %s" % _tname())
	var ib := _identity_blocker(true)
	if ib != "":
		action.set_body(ib)
		return
	var rd: Readiness = Session.readiness
	if rd == null:
		action.set_body("Reading your readiness…")
		return
	if not (rd.state == "ready" or rd.state == "fragile"):
		var lines: PackedStringArray = ["Not ready to Beat: %s" % rd.reason, "", "The four holdings (all four, or Beat panics with 0x12):"]
		for k in ["fomalhaute", "fornax", "tethys", "qzu"]:
			var v: Dictionary = rd.holdings.get(k, {"verdict": "missing", "detail": "—"})
			lines.append("  %-11s %s · %s" % [k.to_upper(), v["verdict"], v["detail"]])
		lines.append("")
		lines.append("Probe: [CHEON.Su(Phobos), META.Beat(Phobos Waat)] from your wallet at block %d." % rd.block)
		action.set_body("\n".join(lines))
		action.set_status("No transaction offered: it would revert.", Color("#ffd27a"))
		return
	var p: Dictionary = await Moves.beat_preview(Session.wallet, String(territory["waat"]))
	if not action.is_open():
		return
	if not p["ok"]:
		action.set_body(p["message"] + _hint(p))
		return
	action.set_body("\n".join(p["lines"]) + "\n\nSimulated from your wallet at block %d.%s" % [p["block"],
		"\nReadiness is FRAGILE: " + rd.fragile_reason if rd.state == "fragile" else ""])
	var sb := _signer_blocker()
	action.set_status(sb)
	action.set_primary("Sign Beat", sb == "", _do_beat.bind(p))


func _do_beat(p: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	action.set_primary("Sign Beat", false, Callable())
	var label := "Beat at %s" % _tname()
	action.track(label)
	var res: Dictionary = await Wallet.send(label, p["to"], p["data"])
	_busy = false
	if not res["ok"]:
		return
	core.pulse()
	Cues.play(self, "beat")
	Acts.set_flag(Session.wallet, "beat")
	hud.ticker("YOUR BEAT · %s · block %d" % [_tname(), res["block"]], Color("#64e3a8"))
	action.set_status("The Heart beat: mined in block %d, status 1." % res["block"], Color("#64e3a8"))
	state.refresh()
	Session.refresh()


# --- WORLD (latent): the range preview --------------------------------------------

## Pure: the centre cell's exact call, as the site builds it: Code(word0, word1,
## QING) with the Compliment words as int256 (order to confirm on the first
## real Code, by simulating both).
static func code_call(q: Dictionary) -> Dictionary:
	var w0 := BigInt.word_to_signed_hex(String(q.get("lon_word", "")))
	var w1 := BigInt.word_to_signed_hex(String(q.get("lat_word", "")))
	var addr := String(q["address"]).to_lower()
	return {"word0": w0, "word1": w1, "qing": addr,
		"text": "WORLD.Code(%s, %s, %s)" % [_signed_dec(w0), _signed_dec(w1), addr],
		"data": Abi.encode_call("Code(int256,int256,address)", [w0, w1, addr])}


static func _signed_dec(h: String) -> String:
	var neg := h.begins_with("-")
	return ("-" if neg else "") + BigInt.to_decimal(BigInt.from_hex(h.trim_prefix("-")))


func open_world() -> void:
	_open_action("WORLD · range preview at %s" % _tname())
	var lines: PackedStringArray = [World.headline()]
	for e in World.evidence.slice(0, 3):
		lines.append("  " + e)
	lines.append("  Site world-watch (corroboration only): %s" % World.site.display())
	lines.append("")
	var cc := code_call(territory)
	lines.append("Centre cell (this territory's Compliment words, int256):")
	lines.append("  word0 %s" % _signed_dec(cc["word0"]))
	lines.append("  word1 %s" % _signed_dec(cc["word1"]))
	lines.append("The exact call: Code(int256,int256,address) %s…" % String(cc["data"]).left(10))
	lines.append("  (argument order to confirm on the first real Code by simulating both)")
	action.set_body("\n".join(lines) + "\n\nReading your Beat and Su here…")
	var code_why := "WORLD is not deployed: nothing to call." if not World.is_live() \
		else "WORLD is live, but Code waits for the launch kit (WP 6.3: argument order and guards checked first)."
	action.set_primary("Code (disabled)", false, Callable())
	action.set_status(code_why, Color("#ffd27a"))
	var ib := _identity_blocker(true)
	if ib != "":
		action.set_body("\n".join(lines) + "\n\n" + ib)
		return
	var ps: PlayerState = Session.player
	var bt: Dictionary = await Moves.beat_preview(Session.wallet, String(territory["waat"]))
	var su: Dictionary = await Moves.su_preview(Session.wallet, ps.yue, qing)
	if not action.is_open():
		return
	lines.append("")
	lines.append("What a Code here would do for you now (simulated from your wallet):")
	if bt["ok"]:
		for l in bt["lines"].slice(0, 4):
			lines.append("  " + l)
	else:
		lines.append("  Beat: " + String(bt["message"]) + "  → a Code would revert.")
	if su["ok"]:
		var ch: PackedInt64Array = su["values"]["charge"]
		lines.append("  Su charge here: %s%s" % [TokenFormat.group(BigInt.to_decimal(ch)),
			"  → Code runs Su first and does nothing at charge 0 (gas spent, no claim)." if BigInt.is_zero(ch)
			else "  → a claim takes a cell when this charge ≥ the cell's value; empty cells fall to 1."])
	else:
		lines.append("  Su: " + String(su["message"]))
	lines.append("Range check: |lat − qlat| ≤ Yeo and |lon − qlon| ≤ Yeo (a square).")
	action.set_body("\n".join(lines))
	if bt["ok"] and lattice != null:
		var yeo := BigInt.from_hex(bt["values"]["yeo"])
		action.set_secondary("Hide my range" if lattice.range_visible() else "Show my range on the ground", true, func():
			lattice.show_range(yeo, not lattice.range_visible())
			action.set_secondary("Hide my range" if lattice.range_visible() else "Show my range on the ground", true, action._action2))
