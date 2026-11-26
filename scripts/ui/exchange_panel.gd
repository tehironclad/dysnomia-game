class_name ExchangePanel
extends PanelContainer
## Shared frame for the Swap Hall's swap panel and the YUE Exchange's Hong/Hung
## panel (DeepFieldTheme, like ActionPanel and BarMenu): a list on the left, the
## trade on the right, a status line that follows Wallet.send's stages
## (simulate → sign → pending → confirmed / failed), and the write helpers both
## use: approve (simulated, signed, receipt read, allowance re-read) and reads.
## Nothing is shown as done before its receipt is read from the chain.

signal closed

const OK := Color("#64e3a8")
const WARN := Color("#ffd27a")
const BAD := Color("#ff8fa0")

var list: VBoxContainer
var right: VBoxContainer
var info: Label
var status: Label
var result: Label
var buttons: HBoxContainer
var busy := false
var _title: Label
var _sub: Label
var _label := ""
var _outer: ScrollContainer
var _col: VBoxContainer
const EDGE_PX := 24.0


## As tall as the panel, at most the window (then it scrolls).
func _fit() -> void:
	if _outer == null or not is_inside_tree():
		return
	var h := get_viewport_rect().size.y
	_outer.custom_minimum_size.y = minf(_col.get_combined_minimum_size().y, maxf(240.0, h - 2.0 * EDGE_PX))
	reset_size()


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(Color(0.66, 0.9, 1.0, 0.45))
	sb.bg_color.a = 1.0  # an opaque modal: the hall's glowing boards showed through 0.96
	add_theme_stylebox_override("panel", sb)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(1040, 0)
	# Scrolls when taller than the window (720p with the access steps: Swap and Close were
	# below the bottom edge; audit 2026-11-25).
	_outer = ScrollContainer.new()
	_outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer.add_child(col)
	_col = col
	col.minimum_size_changed.connect(_fit)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	col.add_child(_title)
	_sub = Label.new()
	_sub.theme_type_variation = "MutedLabel"
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(1000, 0)
	col.add_child(_sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	right = VBoxContainer.new()
	right.custom_minimum_size = Vector2(620, 0)
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	info = mono(12)
	status = Label.new()
	status.theme_type_variation = "MutedLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(1000, 0)
	result = mono(12)
	result.custom_minimum_size = Vector2(1000, 0)
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)


## Call from the subclass after it filled `right`: info, then the shared rows.
func finish_layout() -> void:
	right.add_child(info)
	var col := _col
	col.add_child(status)
	col.add_child(result)
	col.add_child(buttons)
	var close_b := Button.new()
	close_b.text = "Close (Esc)"
	close_b.pressed.connect(close)
	buttons.add_child(close_b)


func _ready() -> void:
	Wallet.tx_stage.connect(_on_stage)


func set_titles(title: String, sub: String) -> void:
	_title.text = title
	_sub.text = sub


func mono(size: int = 13) -> Label:
	var l := Label.new()
	l.theme_type_variation = "MonoLabel"
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l


func button(text: String, action: Callable, parent: Node = null) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(action)
	(parent if parent != null else buttons).add_child(b)
	return b


func row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	right.add_child(h)
	return h


func say(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	status.text = text
	if color.a > 0.0:
		status.add_theme_color_override("font_color", color)
	else:
		status.remove_theme_color_override("font_color")


func show_panel() -> void:
	visible = true
	_fit.call_deferred()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func track(label: String) -> void:
	_label = label


func _on_stage(label: String, stage: String, info_d: Dictionary) -> void:
	if not visible or label != _label:
		return
	match stage:
		"simulate": say("1/4  Simulating from your wallet…")
		"sign": say("2/4  Waiting for your signature in the browser wallet…", DeepFieldTheme.ICE)
		"pending": say("3/4  Sent %s. Waiting for the receipt from the chain…" % String(info_d.get("hash", "")), DeepFieldTheme.ICE)
		"confirmed": say("4/4  Receipt: mined in block %d, status 1. Checking its logs and re-reading…" % int(info_d.get("block", -1)), OK)
		"failed": say("Stopped at %s: %s" % [String(info_d.get("stage", "?")), String(info_d.get("message", ""))], BAD)


## The wallet the panel reads for (signer if connected, else the session's view-only one).
static func reader() -> String:
	return Wallet.address if Wallet.address != "" else Session.wallet


static func short(a: String) -> String:
	return a.left(6) + "…" + a.right(4) if a.length() > 12 else a


static func blk(b: int) -> String:
	return "block %s" % (TokenFormat.group(str(b)) if b >= 0 else "—")


## allowance(owner, spender) on `token` at `block`: BigInt or null if the read failed.
static func read_allowance(token: String, owner: String, spender: String, block = "latest") -> Variant:
	var r: Dictionary = await Chain.rpc.call_decoded(token, "allowance(address,address)", [owner, spender], ["uint256"], "", block)
	return BigInt.coerce(r["values"][0]) if r["ok"] else null


## approve(spender, amount) on `token` through the write rule, then the allowance
## re-read at the receipt's block must cover `amount`. {ok, block, allowance} or {ok:false, message}.
func approve(token: String, symbol: String, spender: String, spender_name: String, amount: PackedInt64Array, decimals: int) -> Dictionary:
	var label := "Approve %s %s for %s" % [PulseX.fmt(amount, decimals, 6), symbol, spender_name]
	track(label)
	var res: Dictionary = await Wallet.send(label, token, Abi.encode_call("approve(address,uint256)", [spender, BigInt.to_decimal(amount)]))
	if not res["ok"]:
		return {"ok": false, "message": "%s (at %s)" % [res.get("message", ""), res.get("stage", "?")]}
	var now = await read_allowance(token, Wallet.address, spender, int(res["block"]))
	if now == null:
		return {"ok": false, "message": "approve mined in block %d, but the allowance did not re-read" % res["block"]}
	if BigInt.cmp(now, amount) < 0:
		return {"ok": false, "message": "approve mined in block %d, but the allowance re-reads as %s" % [res["block"], PulseX.fmt(now, decimals, 6)]}
	return {"ok": true, "block": int(res["block"]), "allowance": now, "hash": res["hash"]}


## A revert or failure in plain words.
static func why(r: Dictionary) -> String:
	if r.get("kind") == "revert":
		return PulseX.explain(String(r["revert"].get("message", "reverted")))
	return String(r.get("error", {}).get("message", r.get("message", "the chain did not answer")))
