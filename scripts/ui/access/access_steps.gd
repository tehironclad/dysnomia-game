class_name AccessSteps
extends PanelContainer
## The path forward, on screen: a numbered checklist of what stands between the
## player and the thing they tried (✓ done, → the current step, ✗ still to do,
## "checking…" while a fact is being read, "—" when it could not be read). Each
## step says plainly what it is, and its button does it (or opens what does).
##
## The steps come from AccessGates.resolve (pure, unit-tested); this node only
## gathers the facts: Session (identity, readiness), Wallet (the window, the
## chain), and the reads a goal needs (AFFECTION balances, a room's door, the
## fair's ticket logs). Nothing is assumed: a fact not read yet is "checking…".
##
## Use it embedded (add it to a panel, call show_goal) or as an overlay:
##   AccessSteps.popup(self, "fair_ticket", {"qing": q, "fee_wei": fee}, {"join": _join})
##
## Hooks:
## - add_provider(callable): callable(goal: String, facts: Dictionary) -> Dictionary is
##   called on every refresh; its keys are merged into the facts. "override":
##   {gate id: {status, detail, action, …}} replaces a gate's verdict (a better
##   diagnosis, e.g. the payment agent's wallet check), "provider_steps": [...] adds
##   steps after the chain step, any other key replaces that fact.
## - set_handler(action, callable): what a step's button does. Built in: connect,
##   reopen, chain, void, yue, front_door, move_lau. Hosts add join, join_border,
##   su, get_affection… A step whose action has no handler shows no button.

signal cleared
signal action_taken(action: String)
signal closed

const DONE := Color("#64e3a8")
const TODO := Color("#ff8fa0")
const FRONT_DOOR := "res://scenes/ui/front_door.tscn"

static var _providers: Array = []
## What the front door should open when it next loads ("void" | "identity" | ""):
## set by the void / yue / front_door actions from anywhere in the game.
static var front_door_open := ""
static var _popup_ref: WeakRef = null

var goal := ""
var ctx := {}
var handlers := {}
var result := {}
var popup_mode := false
var compact := false
var _reads := {}       ## async facts this panel read itself: aff, room, border, fair
var _reading := {}
var _title: Label
var _sub: Label
var _rows: VBoxContainer
var _summary: Label
var _status: Label
var _again: Button
var _close: Button
var _foot: HBoxContainer
var _extra_btns: Array = []
var _busy := false
var _was_ready := false
var _poll: Timer
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _render_key := ""
var _diag_at := -100000


static func add_provider(c: Callable) -> void:
	if c.is_valid() and not _providers.has(c):
		_providers.append(c)


static func remove_provider(c: Callable) -> void:
	_providers.erase(c)


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(DeepFieldTheme.ICE.darkened(0.35))
	sb.bg_color.a = 0.94
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(560, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var kicker := Label.new()
	kicker.theme_type_variation = "MutedLabel"
	kicker.text = "HOW TO GET ACCESS"
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	col.add_child(kicker)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.add_theme_font_size_override("font_size", 18)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_sub = Label.new()
	_sub.theme_type_variation = "MutedLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.visible = false
	col.add_child(_sub)
	var line := ColorRect.new()
	line.color = DeepFieldTheme.HAIRLINE_STRONG
	line.custom_minimum_size = Vector2(0, 1)
	col.add_child(line)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	col.add_child(_rows)
	_summary = Label.new()
	_summary.theme_type_variation = "MonoLabel"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_summary)
	_status = Label.new()
	_status.theme_type_variation = "MutedLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	col.add_child(_status)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	_foot = foot
	_again = Button.new()
	_again.text = "Check again"
	_again.tooltip_text = "Read the wallet, your identity and this place's door again from the chain."
	_again.pressed.connect(reread)
	foot.add_child(_again)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_close = Button.new()
	_close.text = "Close (Esc)"
	_close.visible = false
	_close.pressed.connect(close)
	foot.add_child(_close)


func _ready() -> void:
	Session.changed.connect(_on_world_changed)
	Wallet.connected.connect(func(_a): _on_world_changed())
	Wallet.disconnected.connect(_on_world_changed)
	if Wallet.has_signal("status_changed"):
		Wallet.status_changed.connect(func():
			if not _reading.has("diag") and Time.get_ticks_msec() - _diag_at > 3000:
				_diag_at = Time.get_ticks_msec()
				_reads.erase("diag")
			refresh())
	_poll = Timer.new()
	_poll.wait_time = 1.5
	_poll.timeout.connect(func(): if is_visible_in_tree() and goal != "": refresh())
	add_child(_poll)
	_poll.start()


## Shows the steps toward `p_goal` (an AccessGates.GOALS key). ctx: qing, room (a
## RoomState), room_name, border_qing, border_name, border (RoomState), fee_wei,
## fair ({codes, state, block}), tier ({have, need, …}), extra ([steps]), title, subtitle.
func show_goal(p_goal: String, p_ctx: Dictionary = {}, p_handlers: Dictionary = {}) -> void:
	if p_goal != goal or String(p_ctx.get("qing", "")) != String(ctx.get("qing", "")):
		_reads.clear()
	goal = p_goal
	ctx = p_ctx.duplicate()
	for k in p_handlers:
		handlers[k] = p_handlers[k]
	_was_ready = false
	_status.visible = false
	_sub.text = String(ctx.get("subtitle", ""))
	_sub.visible = _sub.text != ""
	visible = true
	refresh()


## A footer button beside "Check again" (e.g. "Fly a free practice flight").
func add_footer_button(text: String, c: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		c.call()
		if popup_mode:
			close())
	_foot.add_child(b)
	_foot.move_child(b, 1)
	_extra_btns.append(b)
	return b


## An embedded, compact instance (hidden until update_for shows it).
static func embed(parent: Node, index: int = -1) -> AccessSteps:
	var a := AccessSteps.new()
	a.compact = true
	a.visible = false
	a.custom_minimum_size = Vector2(520, 0)
	parent.add_child(a)
	if index >= 0:
		parent.move_child(a, index)
	return a


## Shows the steps toward `p_goal` when there is a blocker ("" hides the panel).
func update_for(blocker: String, p_goal: String, p_ctx: Dictionary = {}, p_handlers: Dictionary = {}) -> void:
	if blocker == "":
		visible = false
		return
	if not visible or p_goal != goal:
		show_goal(p_goal, p_ctx, p_handlers)
	else:
		for k in p_ctx:
			ctx[k] = p_ctx[k]
		for k in p_handlers:
			handlers[k] = p_handlers[k]
		refresh()


## The goal a failed write points to: Wallet.send's precondition/sign stages are the
## wallet's; ArcadePay's "funds" is the Ⓐ step. "" = not an access problem.
static func goal_for_failure(res: Dictionary, goal_if_access: String) -> String:
	var st := String(res.get("stage", ""))
	if st.begins_with("precondition") or st.begins_with("funds") or st == "sign" and String(res.get("message", "")).contains("not linked"):
		return goal_if_access
	return ""


func set_handler(action: String, c: Callable) -> void:
	handlers[action] = c
	refresh()


## Replace one context value (e.g. a fresh RoomState after Join) and redraw.
func set_context(key: String, value) -> void:
	ctx[key] = value
	refresh()


func is_ready() -> bool:
	return bool(result.get("ready", false))


## Forget the reads this panel made and ask again (and Session, if it is idle).
func reread() -> void:
	_reads.clear()  # the wallet diagnosis, balances and doors are read again
	for k in ["room", "border", "fair", "aff"]:
		if ctx.get(k) is Object:
			ctx.erase(k)  # a host's RoomState is a snapshot: read it again
	if Session.wallet != "" and not Session.refreshing:
		Session.refresh()
	_set_status("Checking again…")
	refresh()


func refresh() -> void:
	if goal == "":
		return
	var f := gather()
	result = AccessGates.resolve(goal, f)
	_render()
	_start_reads()
	if result["ready"] and not _was_ready:
		_was_ready = true
		cleared.emit()
	elif not result["ready"]:
		_was_ready = false


# --- Facts ------------------------------------------------------------------------

func _needs(gate_id: String) -> bool:
	var g: Dictionary = AccessGates.GOALS.get(goal, {})
	return gate_id in g.get("gates", [])


func gather() -> Dictionary:
	var f := {}
	f["title"] = String(ctx.get("title", AccessGates.GOALS.get(goal, {}).get("title", goal)))
	f["wallet"] = Session.wallet
	f["signer"] = Wallet.address
	f["relay"] = Wallet.bridge != null and Wallet.bridge.is_server_running()
	f["linked"] = Wallet.is_linked()
	f["chain_id"] = Wallet.chain_id
	var ps: PlayerState = Session.player
	if Session.wallet == "":
		f["identity"] = "none"
	elif ps == null:
		f["identity"] = "reading"
	elif ps.error != "":
		f["identity"] = "failed"
		f["identity_error"] = ps.error
	else:
		f["identity"] = "ok"
		f["lau"] = ps.has_lau()
		f["yue"] = ps.has_yue()
		f["banned"] = ps.is_banned()
		f["lau_addr"] = ps.lau
		f["yue_addr"] = ps.yue
	var rd: Readiness = Session.readiness
	if rd != null:
		f["ready"] = {"state": "ok", "verdict": rd.state, "reason": rd.reason, "block": rd.block}
	elif ps != null and ps.ok:
		f["ready"] = {"state": "reading"} if Session.refreshing else {"state": "failed"}
	if _needs("affection"):
		f["aff"] = _reads.get("aff", {"state": "reading"})
	if _needs("room"):
		f["room"] = _door_facts(ctx.get("room"), _reads.get("room"), String(ctx.get("room_name", "")))
	if _needs("border"):
		f["border"] = _door_facts(ctx.get("border"), _reads.get("border"), String(ctx.get("border_name", "")))
	if _needs("fair"):
		f["fair"] = _fair_facts(ctx.get("fair", _reads.get("fair", {})))
	if ctx.has("tier"):
		f["tier"] = ctx["tier"]
	if ctx.has("extra"):
		f["extra"] = ctx["extra"]
	# The payment layer's own diagnosis (WalletDiagnosis, read-only) refines the wallet steps.
	if _reads.has("diag"):
		var d := AccessGates.from_diagnosis(_reads["diag"], goal)
		f["override"] = d.get("override", {})
		f["provider_steps"] = d.get("provider_steps", [])
	for p in _providers:
		if not p.is_valid():
			continue
		var r = p.call(goal, f)
		if r is Dictionary:
			for k in r:
				if k == "provider_steps":
					f["provider_steps"] = f.get("provider_steps", []) + Array(r[k])
				elif k == "override":
					var o: Dictionary = f.get("override", {})
					o.merge(r[k], true)
					f["override"] = o
				else:
					f[k] = r[k]
	return f


## A RoomState (the host's, or one read here) → the facts AccessGates wants.
static func room_facts(rs: RoomState, name: String = "") -> Dictionary:
	if rs == null:
		return {"state": "reading", "name": name}
	if not rs.ok:
		return {"state": "failed", "name": name}
	return {"state": "ok", "cover": rs.has_cover(), "admitted": rs.admitted, "afford": rs.can_afford(),
		"cover_text": rs.fmt(rs.cover), "balance_text": rs.fmt(rs.balance), "block": rs.block, "name": name}


func _door_facts(host_rs, read_rs, name: String) -> Dictionary:
	if host_rs is RoomState:
		return room_facts(host_rs, name)
	if host_rs is Dictionary:
		return host_rs
	return room_facts(read_rs if read_rs is RoomState else null, name)


static func fair_facts(p: Dictionary) -> Dictionary:
	var st := String(p.get("state", "reading"))
	if st != "ok":
		return {"state": st}
	var codes: Array = p.get("codes", [])
	var missing: Array = []
	for i in FairProgress.ORDER.size():
		if not codes.has(i + 1):
			missing.append(MidwayGame.title(FairProgress.ORDER[i]).capitalize())
	return {"state": "ok", "have": FairProgress.ORDER.size() - missing.size(), "need": FairProgress.ORDER.size(),
		"missing": missing, "block": int(p.get("block", -1))}


func _fair_facts(p) -> Dictionary:
	if Session.wallet == "":
		return {"state": "nowallet"}
	return fair_facts(p if p is Dictionary else {})


func _needs_wallet() -> bool:
	return _needs("window")


func _start_reads() -> void:
	var w := Session.wallet
	if _needs_wallet() and not _reads.has("diag") and not _reading.has("diag") and Wallet.bridge != null and Wallet.bridge.is_server_running():
		_read_diag()
	if w == "":
		return
	if _needs("affection") and not _reads.has("aff") and not _reading.has("aff"):
		_read_aff(w)
	var q := String(ctx.get("qing", ""))
	if _needs("room") and q != "" and not (ctx.get("room") is RoomState or ctx.get("room") is Dictionary) \
			and not _reads.has("room") and not _reading.has("room") and Session.player != null:
		_read_door("room", q)
	var bq := String(ctx.get("border_qing", ""))
	if _needs("border") and bq != "" and not (ctx.get("border") is RoomState) and not _reads.has("border") \
			and not _reading.has("border") and Session.player != null:
		_read_door("border", bq)
	if _needs("fair") and q != "" and not ctx.has("fair") and not _reads.has("fair") and not _reading.has("fair"):
		_read_fair(w, q)


## WalletDiagnosis.run() without opening anything (no window, no signature): its
## failed checks become the wallet steps' verdicts (AccessGates.from_diagnosis).
func _read_diag() -> void:
	_reading["diag"] = true
	var rows: Array = await WalletDiagnosis.run({"open": false, "sign": false, "qing": String(ctx.get("qing", ""))})
	_reading.erase("diag")
	if not is_inside_tree():
		return
	_reads["diag"] = rows
	refresh()


func _read_aff(w: String) -> void:
	_reading["aff"] = true
	var fee := String(ctx.get("fee_wei", ArcadePay.FEE_WEI))
	var wb: Dictionary = await ArcadePay.read_balance(w)
	var ps: PlayerState = Session.player
	var lb := {}
	if ps != null and ps.has_lau():
		lb = await ArcadePay.read_balance(ps.lau)
	_reading.erase("aff")
	if w != Session.wallet or not is_inside_tree():
		return
	if not wb.get("ok", false):
		_reads["aff"] = {"state": "failed"}
	else:
		_reads["aff"] = {"state": "ok", "wallet": BigInt.to_decimal(wb["balance"]), "fee": fee,
			"lau": BigInt.to_decimal(lb["balance"]) if lb.get("ok", false) else ""}
	refresh()


func _read_door(key: String, q: String) -> void:
	_reading[key] = true
	var rs: RoomState = await RoomState.read(q, Session.player)
	_reading.erase(key)
	if not is_inside_tree():
		return
	_reads[key] = rs
	refresh()


func _read_fair(w: String, q: String) -> void:
	_reading["fair"] = true
	var c := FairProgress.cached(w, q)
	if int(c["block"]) > 0:
		_reads["fair"] = {"state": "ok", "codes": c["codes"], "block": c["block"]}
	var r: Dictionary = await FairProgress.refresh(w, q)
	_reading.erase("fair")
	if not is_inside_tree():
		return
	_reads["fair"] = {"state": "ok" if r["ok"] else "failed", "codes": r["codes"], "block": int(r["block"])}
	refresh()


# --- Drawing ----------------------------------------------------------------------

func _render() -> void:
	_title.text = ("TO " + String(result.get("title", ""))).to_upper()
	var key := JSON.stringify(result.get("steps", [])) + str(handlers.keys())
	if key != _render_key:
		_render_key = key
		_rebuild_rows()
	_summary.text = String(result.get("summary", ""))
	_summary.add_theme_color_override("font_color", DONE if result.get("ready", false) else DeepFieldTheme.ICE)


func _mark_color(s: Dictionary) -> Color:
	if s["status"] == "done":
		return DONE
	if s["current"]:
		return DeepFieldTheme.ICE
	match String(s["status"]):
		"todo": return TODO
		"checking": return DeepFieldTheme.MUTED
	return DeepFieldTheme.DIM


func _rebuild_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var focus_btn: Button = null
	for s in result.get("steps", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rows.add_child(row)
		var num := Label.new()
		num.theme_type_variation = "MonoLabel"
		num.text = "%d" % int(s["n"])
		num.custom_minimum_size = Vector2(18, 0)
		num.add_theme_color_override("font_color", DeepFieldTheme.DIM)
		row.add_child(num)
		var mark := Label.new()
		mark.text = String(s["mark"])
		mark.custom_minimum_size = Vector2(22, 0)
		mark.add_theme_font_size_override("font_size", 18)
		mark.add_theme_color_override("font_color", _mark_color(s))
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(mark)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 2)
		row.add_child(text)
		var t := Label.new()
		t.text = String(s["title"])
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.add_theme_color_override("font_color", DeepFieldTheme.INK if s["status"] != "done" else DeepFieldTheme.MUTED)
		if s["current"]:
			t.add_theme_color_override("font_color", DeepFieldTheme.ICE)
		text.add_child(t)
		var d := Label.new()
		d.theme_type_variation = "MonoLabel"
		d.add_theme_font_size_override("font_size", 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.text = String(s["detail"])
		d.visible = d.text != ""
		d.add_theme_color_override("font_color", DONE.darkened(0.15) if s["status"] == "done" else DeepFieldTheme.MUTED)
		text.add_child(d)
		if s["status"] != "done" and String(s["explain"]) != "" and (s["current"] or not compact):
			var e := Label.new()
			e.theme_type_variation = "MutedLabel"
			e.add_theme_font_size_override("font_size", 12)
			e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			e.text = String(s["explain"])
			e.visible = s["current"] or not compact
			text.add_child(e)
		var act := String(s.get("action", ""))
		if s["status"] != "done" and act != "" and _has_handler(act):
			var b := Button.new()
			b.text = String(s.get("action_label", act)) if String(s.get("action_label", "")) != "" else act
			b.disabled = not s["current"] or _busy
			b.custom_minimum_size = Vector2(150, 34)
			b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			b.pressed.connect(_run.bind(act))
			row.add_child(b)
			if s["current"] and focus_btn == null:
				focus_btn = b
	if popup_mode and focus_btn != null:
		focus_btn.grab_focus.call_deferred()


func _set_status(t: String, c: Color = Color(0, 0, 0, 0)) -> void:
	_status.text = t
	_status.visible = t != ""
	if c.a > 0.0:
		_status.add_theme_color_override("font_color", c)
	else:
		_status.remove_theme_color_override("font_color")


# --- Actions ----------------------------------------------------------------------

const BUILT_IN := ["connect", "reopen", "chain", "void", "yue", "front_door", "move_lau"]


func _has_handler(act: String) -> bool:
	if handlers.has(act):
		return (handlers[act] as Callable).is_valid()
	return act in BUILT_IN


func _run(act: String) -> void:
	if _busy:
		return
	action_taken.emit(act)
	if handlers.has(act) and (handlers[act] as Callable).is_valid():
		_busy = true
		_render_key = ""
		await (handlers[act] as Callable).call()
		_busy = false
		reread()
		return
	match act:
		"connect", "reopen":
			if Wallet.connect_wallet():
				_set_status("The wallet window is opening in your browser: approve the connection there.", DeepFieldTheme.ICE)
			else:
				_set_status("Could not start the local wallet relay (ports %d+ busy?). Close other copies of the game and try again." % Config.wallet_bridge_port, TODO)
		"chain":
			_busy = true
			await _switch_chain()
			_busy = false
		"void", "yue", "front_door":
			_to_front_door("void" if act != "front_door" else "identity")
		"move_lau":
			_busy = true
			_render_key = ""
			_render()
			_set_status("Moving Ⓐ from your LAU: approve LAU.Withdraw in your wallet window (simulated first, the receipt is checked)…", DeepFieldTheme.ICE)
			var r: Dictionary = await ArcadePay.ensure_funds(String(ctx.get("fee_wei", ArcadePay.FEE_WEI)))
			_busy = false
			if r.get("ok", false):
				_set_status(("Moved %s to your wallet (block %d)." % [ArcadePay.fmt(r["moved"]), int(r["block"])]) if r.has("moved") else "Your wallet already holds enough.", DONE)
			else:
				_set_status("Not moved (%s): %s" % [r.get("stage", "?"), r.get("message", "cancelled")], TODO)
			_reads.erase("aff")
			refresh()
	refresh()


## Asks the wallet window to switch to PulseChain (the bridge's switch_chain; the
## wallet's own answer comes back as chain_changed, which Wallet keeps).
func _switch_chain() -> void:
	var b: Node = Wallet.bridge
	if b == null or not Wallet.is_linked() or not b.request_switch_chain():
		_run("reopen")
		return
	b.focus_wallet_page()
	_set_status("Approve the switch to PulseChain (369) in your wallet window…", DeepFieldTheme.ICE)
	for i in 120:
		await get_tree().create_timer(0.5).timeout
		if Wallet.chain_id == AccessGates.CHAIN_ID:
			_set_status("The wallet reports PulseChain (369).", DONE)
			_reads.erase("diag")
			return
	_set_status("The wallet did not report PulseChain within a minute: switch it in the wallet, then Check again.", TODO)


func _to_front_door(panel: String) -> void:
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur.has_method("open_panel"):
		cur.open_panel(panel)
		close()
		return
	front_door_open = panel
	close()
	tree.change_scene_to_file(FRONT_DOOR)


# --- As an overlay ----------------------------------------------------------------

## Opens the steps over everything (one at a time), mouse visible; Esc or Close
## shuts it and restores the mouse. Returns the panel (connect `cleared` to retry).
static func popup(host: Node, p_goal: String, p_ctx: Dictionary = {}, p_handlers: Dictionary = {}) -> AccessSteps:
	close_popup()
	var layer := CanvasLayer.new()
	layer.layer = 95
	layer.name = "AccessStepsLayer"
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var p := AccessSteps.new()
	p.popup_mode = true
	p.custom_minimum_size = Vector2(640, 0)
	p._close.visible = true
	p._prev_mouse = Input.mouse_mode
	center.add_child(p)
	host.add_child(layer)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	p.closed.connect(func():
		Input.set_mouse_mode(p._prev_mouse)
		layer.queue_free())
	p.show_goal(p_goal, p_ctx, p_handlers)
	_popup_ref = weakref(p)
	return p


static func close_popup() -> void:
	if _popup_ref != null:
		var p = _popup_ref.get_ref()
		if p != null and is_instance_valid(p):
			p.close()
	_popup_ref = null


static func popup_open() -> bool:
	return _popup_ref != null and _popup_ref.get_ref() != null and is_instance_valid(_popup_ref.get_ref())


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if popup_mode and visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_world_changed() -> void:
	_reads.erase("aff")
	_reads.erase("fair")
	if not Session.refreshing:
		_reads.erase("room")
		_reads.erase("border")
	refresh()
