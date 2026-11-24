class_name WalletTestPanel
extends PanelContainer
## Settings → "Test my wallet": runs WalletDiagnosis (read-only; an optional free
## signature) and shows ✓ / ✗ per step with the reason, so the player can find the
## step that fails. The same lines go to the console with [Pay].

var _rows: VBoxContainer
var _run_btn: Button
var _sign: CheckBox
var _summary: Label
var _busy := false


func _ready() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.97
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(640, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.text = "TEST MY WALLET"
	col.add_child(title)
	var note := Label.new()
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(600, 0)
	note.text = "Checks the payment path step by step: the local relay, the wallet window, the wallet in it, your account, the chain, your Ⓐ and PLS, and a simulated 1 Ⓐ ticket. Nothing is sent and nothing is spent. The free signature asks your wallet for a signature of a test text (not a transaction)."
	col.add_child(note)
	_sign = CheckBox.new()
	_sign.text = "Also ask for a free signature (a wallet popup; nothing is spent)"
	col.add_child(_sign)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	col.add_child(_rows)
	_summary = Label.new()
	_summary.theme_type_variation = "MonoLabel"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(600, 0)
	col.add_child(_summary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_run_btn = Button.new()
	_run_btn.text = "Run the test"
	_run_btn.pressed.connect(run)
	row.add_child(_run_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): visible = false)
	row.add_child(close_btn)


func run() -> void:
	if _busy:
		return
	_busy = true
	_run_btn.disabled = true
	for c in _rows.get_children():
		c.queue_free()
	_summary.text = "Testing… (a wallet window may open)"
	var steps: Array = await WalletDiagnosis.run({"open": true, "sign": _sign.button_pressed})
	for s in steps:
		var l := Label.new()
		l.theme_type_variation = "MonoLabel"
		l.add_theme_font_size_override("font_size", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(600, 0)
		l.text = WalletDiagnosis.lines([s])[0]
		l.add_theme_color_override("font_color", Color("#64e3a8") if s["ok"] == true else (Color("#ff8fa0") if s["ok"] == false else Color("#8e97a9")))
		_rows.add_child(l)
	var bad := WalletDiagnosis.first_failure(steps)
	_summary.text = "Every step passed: payments should reach your wallet." if bad.is_empty() else "First failing step: %s. Fix that one first, then run the test again." % bad["step"]
	if not Wallet.last_failure.is_empty():
		_summary.text += "\nLast payment failure: %s — stopped at %s: %s" % [Wallet.last_failure["label"], Wallet.stage_text(String(Wallet.last_failure["stage"])), Wallet.last_failure["message"]]
	_run_btn.disabled = false
	_busy = false
