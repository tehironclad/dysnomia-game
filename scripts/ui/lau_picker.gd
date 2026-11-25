class_name LauPicker
extends PanelContainer
## Your LAUs: every one this wallet owns (LauFinder: OwnershipUpdate logs, each
## proven by Saat(2)), the current one marked, and "Use this LAU" on the others
## (CHO.Enter, one approval, re-read after the receipt).

signal switched(lau: String)

var _list: VBoxContainer
var _status: Label
var _busy := false
var _laus: Array = []
var _block := 0


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	add_theme_stylebox_override("panel", DeepFieldTheme.panel_style())
	custom_minimum_size = Vector2(600, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var t := Label.new()
	t.theme_type_variation = "DisplayLabel"
	t.text = "YOUR LAUs"
	col.add_child(t)
	var sub := Label.new()
	sub.theme_type_variation = "MutedLabel"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "Every LAU this wallet owns, found from the chain's OwnershipUpdate logs and proven by Saat(2) = wallet mod the Motzkin prime. The game plays as the one CHO knows you by; switching is CHO.Enter (one approval)."
	col.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_status = Label.new()
	_status.theme_type_variation = "MonoLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	col.add_child(_status)


func refresh() -> void:
	if _busy:
		return
	var w := Session.wallet
	if w == "":
		_fill([], "Connect a wallet to see its LAUs.")
		return
	_busy = true
	_fill([], "Reading your LAUs from the chain…")
	var r: Dictionary = await LauFinder.find(w)
	_busy = false
	if not r.get("ok", false):
		_fill([], "— %s. Try again in a moment." % String(r.get("error", "read failed")))
		return
	_laus = r["laus"]
	_block = int(r.get("block", 0))
	_fill(_laus, ("%d LAU%s · read at block %s%s" % [_laus.size(), "" if _laus.size() == 1 else "s", ArcadeScores.grouped(_block),
		"\nTo switch, connect this wallet (the chip at the top): switching is signed." if Wallet.address == "" and _laus.size() > 1 else ""])
		if not _laus.is_empty() else "This wallet owns no LAU yet: Enter the Void to make one.")


func _fill(laus: Array, status: String) -> void:
	for c in _list.get_children():
		c.queue_free()
	_status.text = status
	# The current one first, then named ones, then the rest
	var rows := laus.duplicate()
	rows.sort_custom(func(a, b):
		if a["current"] != b["current"]:
			return a["current"]
		return (String(a["username"]) != "") and String(b["username"]) == "")
	for l in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list.add_child(row)
		var name := Label.new()
		name.text = LauFinder.label(l)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		if l["current"]:
			name.add_theme_color_override("font_color", DeepFieldTheme.ICE)
		row.add_child(name)
		var addr := Label.new()
		addr.theme_type_variation = "MonoLabel"
		addr.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
		addr.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
		addr.text = ArcadeScores.short(String(l["address"]))
		row.add_child(addr)
		if l["current"]:
			var cur := Label.new()
			cur.text = "● current"
			cur.add_theme_color_override("font_color", DeepFieldTheme.ICE)
			row.add_child(cur)
		else:
			var b := Button.new()
			b.text = "Use this LAU"
			b.disabled = _busy or Wallet.address == ""
			b.tooltip_text = "CHO.Enter(%s): simulated first, then one approval in your wallet" % String(l["address"])
			b.pressed.connect(_use.bind(l))
			row.add_child(b)


func _use(l: Dictionary) -> void:
	if _busy:
		return
	if Wallet.address == "" or Wallet.address.to_lower() != Session.wallet.to_lower():
		_status.text = "Connect this wallet (the chip at the top) to switch LAUs."
		return
	_busy = true
	var title := LauFinder.label(l)
	_status.text = "Switching to %s · approve CHO.Enter in your wallet window…" % title
	var r: Dictionary = await LauFinder.switch_to(String(l["address"]), title)
	_busy = false
	if not r.get("ok", false):
		_status.text = "Not switched (%s): %s" % [String(r.get("stage", "?")), String(r.get("message", "cancelled"))]
		print("[Pay] LAU switch failed (%s): %s" % [r.get("stage", "?"), r.get("message", "")])
		return
	_status.text = "Now playing as %s · CHO re-read at block %s" % [title, ArcadeScores.grouped(int(r["block"]))]
	switched.emit(String(l["address"]))
	for x in _laus:
		x["current"] = x["address"] == String(l["address"]).to_lower()
	_fill(_laus, _status.text)
