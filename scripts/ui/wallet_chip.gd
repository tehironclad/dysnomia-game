class_name WalletChip
extends CanvasLayer
## The wallet chip (top centre, every scene; owned by the Wallet autoload):
## not connected / 0x…  · chain · wallet window linked or not. Click it to connect,
## or to raise / reopen the wallet window. Under it, the current payment's stage
## and every payment failure in plain words, with its stage (the same text is
## printed to the console with [Pay]).

const LAYER := 12
const FAIL_S := 16.0
const OK_S := 6.0

var _chip: Button
var _toast: PanelContainer
var _toast_label: Label
var _toast_until := 0.0
var _refresh_t := 0.0


func _ready() -> void:
	layer = LAYER
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DeepFieldTheme.get_theme()
	add_child(root)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_top = 6
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	root.add_child(col)
	_chip = Button.new()
	_chip.flat = false
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.add_theme_font_size_override("font_size", 11)
	_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_chip.tooltip_text = "Wallet: click to connect, or to bring back the wallet window. F2 → Test my wallet checks every step."
	_chip.pressed.connect(func(): Wallet.connect_wallet())
	col.add_child(_chip)
	_toast = PanelContainer.new()
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_toast)
	_toast_label = Label.new()
	_toast_label.theme_type_variation = "MonoLabel"
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(560, 0)
	_toast.add_child(_toast_label)
	Wallet.status_changed.connect(refresh)
	Wallet.tx_stage.connect(_on_stage)
	refresh()


func _process(delta: float) -> void:
	_refresh_t += delta
	if _refresh_t > 1.0:
		_refresh_t = 0.0
		refresh()
	if _toast.visible and _toast_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _toast_until:
		_toast.visible = false


func refresh() -> void:
	var s := chip_state(Wallet.address, Wallet.chain_id, Wallet.is_linked(), Wallet.bridge.is_server_running(),
		Wallet.bridge.page_info)
	_chip.text = s["text"]
	_chip.add_theme_color_override("font_color", s["color"])
	_chip.add_theme_color_override("font_hover_color", s["color"])


## Pure: what the chip says and its colour.
static func chip_state(address: String, chain_id: int, linked: bool, relay_running: bool, page_info: Dictionary) -> Dictionary:
	var grey := Color("#8e97a9")
	var amber := Color("#ffd27a")
	var green := Color("#64e3a8")
	if address == "":
		if linked and not bool(page_info.get("hasProvider", true)):
			return {"text": "◌ WALLET · window open, but no wallet extension in that browser (F2 → Test my wallet)", "color": amber}
		if linked:
			return {"text": "◌ WALLET · window open: approve the connection in your wallet", "color": amber}
		if relay_running:
			return {"text": "◌ WALLET · not connected · wallet window not linked (click to open)", "color": amber}
		return {"text": "◌ WALLET · not connected (click to connect)", "color": grey}
	var parts: PackedStringArray = ["● %s…%s" % [address.left(6), address.right(4)]]
	var color := green
	if chain_id == Contracts.CHAIN_ID:
		parts.append("PulseChain")
	else:
		parts.append("chain %d (paying asks to switch to 369)" % chain_id)
		color = amber
	if linked:
		parts.append("wallet window linked")
	else:
		parts.append("wallet window closed (click to reopen)")
		color = amber
	return {"text": " · ".join(parts), "color": color}


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	match stage:
		"failed":
			var st := String(info.get("stage", "?"))
			_show("✗ %s — stopped at %s: %s" % [label, Wallet.stage_text(st), info.get("message", "")], Color("#ff8fa0"), FAIL_S)
		"confirmed":
			_show("✓ %s — confirmed in block %d" % [label, int(info.get("block", 0))], Color("#64e3a8"), OK_S)
		"pending":
			_show("… %s — sent %s; waiting for the chain receipt" % [label, String(info.get("hash", "")).left(12)], Color("#a8e6ff"), 0.0)
		"sign":
			_show("… %s — approve it in your wallet (the wallet window is raised)" % label, Color("#ffd27a"), 0.0)
		"link":
			_show("… %s — opening the wallet window…" % label, Color("#ffd27a"), 0.0)
		"chain":
			_show("… %s — asking the wallet to switch to PulseChain (369)…" % label, Color("#ffd27a"), 0.0)
		"simulate":
			_show("… %s — checking it on the chain first" % label, Color("#a8e6ff"), 0.0)


func _show(text: String, color: Color, seconds: float) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style(Color(color, 0.45)))
	_toast.visible = true
	_toast_until = Time.get_ticks_msec() / 1000.0 + seconds if seconds > 0.0 else 0.0
