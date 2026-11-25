class_name OnboardingPanel
extends PanelContainer
## "Enter the Void" (WP 4.4): the five identity steps, each complete only when
## the chain says so, each simulated before signing and verified after.
##   1 Forge  LAUFactory.New(name, symbol)       → a LAU contract you own
##   2 Bind   CHO.Enter(LAU)                      → CHO maps your wallet to it
##   3 Name   LAU.Username(name)  (optional)     → your 12-character name
##   4 Wake   SEI.Start(LAU, name, symbol)        → your YUE scoreboard
##   5 Play   CHOA.Play(LAU)                      → mints your first YUE (clears ZeroHoldings)

const STEPS := [
	{"key": "forge", "title": "1 · FORGE YOUR LAU", "code": "LAUFactory.New(string name, string symbol) returns (address LAU)",
		"plain": "Deploys your identity contract. Its constructor enters the Void and gives you a Soul."},
	{"key": "bind", "title": "2 · BIND IT", "code": "CHO.Enter(address LAU)",
		"plain": "Tells CHO this LAU is yours, so every contract can find it from your wallet."},
	{"key": "name", "title": "3 · NAME IT (optional)", "code": "LAU.Username(string)  // owner only, ≤ 12 characters",
		"plain": "Your display name. Names are not unique; your LAU address is what identifies you."},
	{"key": "wake", "title": "4 · WAKE YOUR YUE", "code": "SEI.Start(address LAU, string name, string symbol)",
		"plain": "Deploys your YUE: the scoreboard that holds your Hypobar and Epibar at every territory."},
	{"key": "play", "title": "5 · PLAY", "code": "CHOA.Play(address LAU)",
		"plain": "Activates you and mints your first YUE, so ZeroHoldings stops blocking you."},
]

var _rows := {}
var _name: LineEdit
var _symbol: LineEdit
var _out: Label
var _connect: Button
var _busy := false


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := Label.new()
	head.theme_type_variation = "DisplayLabel"
	head.text = "ENTER THE VOID"
	box.add_child(head)
	var sub := Label.new()
	sub.theme_type_variation = "MutedLabel"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "Each step is simulated before you sign and checked on chain after. A step is done only when the chain says so."
	box.add_child(sub)
	var form := HBoxContainer.new()
	box.add_child(form)
	_name = LineEdit.new()
	_name.placeholder_text = "name (≤ 12)"
	_name.max_length = 12
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(_name)
	_symbol = LineEdit.new()
	_symbol.placeholder_text = "SYMBOL"
	_symbol.max_length = 8
	form.add_child(_symbol)
	for s in STEPS:
		var row := VBoxContainer.new()
		box.add_child(row)
		var top := HBoxContainer.new()
		row.add_child(top)
		var t := Label.new()
		t.text = s["title"]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(t)
		var stl := Label.new()
		stl.theme_type_variation = "MonoLabel"
		top.add_child(stl)
		var btn := Button.new()
		btn.text = "Sign"
		btn.pressed.connect(_run_step.bind(s["key"]))
		top.add_child(btn)
		var code := Label.new()
		code.theme_type_variation = "MonoLabel"
		code.add_theme_color_override("font_color", DeepFieldTheme.ICE)
		code.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
		code.text = s["code"]
		row.add_child(code)
		var plain := Label.new()
		plain.theme_type_variation = "MutedLabel"
		plain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plain.text = s["plain"]
		row.add_child(plain)
		_rows[s["key"]] = {"status": stl, "button": btn}
	_out = Label.new()
	_out.theme_type_variation = "MonoLabel"
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_out)
	# Not connected: the first thing to do, right here (not only on the doors).
	_connect = Button.new()
	_connect.text = "Connect wallet"
	_connect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_connect.custom_minimum_size = Vector2(180, 38)
	_connect.pressed.connect(_on_connect)
	box.add_child(_connect)


func _ready() -> void:
	Session.changed.connect(refresh_view)
	Wallet.tx_stage.connect(func(label, stage, info):
		_out.text = "%s: %s %s" % [label, stage, String(info.get("hash", info.get("message", "")))])
	refresh_view()


## Step completion straight from chain state (Session.player / readiness).
func step_done(key: String) -> bool:
	var ps: PlayerState = Session.player
	if ps == null:
		return false
	match key:
		"forge":
			return ps.has_lau() or Session.forged_lau != ""
		"bind":
			return ps.has_lau()
		"name":
			return ps.username != ""
		"wake":
			return ps.has_yue()
		"play":
			return ps.has_yue() and Session.readiness != null and Session.readiness.state not in ["blocked", "not-started", "unknown"]
	return false


func refresh_view() -> void:
	var connected := Session.wallet != ""
	var first_open := ""
	for s in STEPS:
		var k: String = s["key"]
		var done := step_done(k)
		if not done and first_open == "" and k != "name":
			first_open = k
		var row: Dictionary = _rows[k]
		row["status"].text = "✓ done" if done else ("—" if not connected else "")
		row["status"].add_theme_color_override("font_color", Color("#64e3a8") if done else DeepFieldTheme.MUTED)
	for s in STEPS:
		var k2: String = s["key"]
		var b: Button = _rows[k2]["button"]
		b.disabled = not connected or _busy or step_done(k2) or (k2 != first_open and k2 != "name") \
			or (k2 == "name" and not step_done("bind"))
	_connect.visible = not connected
	if not connected:
		_out.text = "Connect a wallet to begin. Each step is one transaction, paid in PLS gas."


func _on_connect() -> void:
	if Wallet.connect_wallet():
		_out.text = "A wallet window opened in your browser: approve the connection there."
	else:
		_out.text = "Could not start the local wallet relay (another copy of the game running?)."


func _lau() -> String:
	var ps: PlayerState = Session.player
	return ps.lau if ps != null and ps.has_lau() else Session.forged_lau


func _run_step(key: String) -> void:
	var nm := _name.text.strip_edges()
	var sym := _symbol.text.strip_edges().to_upper()
	var to := ""
	var data := ""
	var label := ""
	match key:
		"forge":
			if nm == "" or sym == "":
				_out.text = "Enter a name and a symbol first."
				return
			to = Contracts.LAU_FACTORY
			data = Abi.encode_call("New(string,string)", [nm, sym])
			label = "Forge your LAU"
		"bind":
			to = Contracts.CHO
			data = Abi.encode_call("Enter(address)", [_lau()])
			label = "Bind your LAU"
		"name":
			if nm == "":
				_out.text = "Enter a name first."
				return
			to = _lau()
			data = Abi.encode_call("Username(string)", [nm])
			label = "Name your LAU"
		"wake":
			to = Contracts.SEI
			data = Abi.encode_call("Start(address,string,string)", [_lau(), (nm if nm != "" else "Dysnomian") + " Yue", sym if sym != "" else "YUE"])
			label = "Wake your YUE"
		"play":
			to = Contracts.CHOA
			data = Abi.encode_call("Play(address)", [_lau()])
			label = "Play"
	if to == "":
		_out.text = "No LAU yet: forge one first."
		return
	_busy = true
	refresh_view()
	var res: Dictionary = await Wallet.send(label, to, data)
	if res["ok"] and key == "forge":
		var lau := await find_forged_lau(res["receipt"], res["simulated"])
		if lau != "":
			Session.remember_forged(lau)
			_out.text = "Forged: your LAU is %s (block %d). Next: bind it." % [lau, res["block"]]
		else:
			_out.text = "Confirmed in block %d, but the new LAU could not be picked out of the logs; open the transaction %s." % [res["block"], res["hash"]]
	elif res["ok"]:
		_out.text = "%s confirmed in block %d." % [label, res["block"]]
	else:
		_out.text = "%s: %s" % [label, res["message"]]
	_busy = false
	await Session.refresh()
	refresh_view()


## Like the site's /enter: the new LAU is a log emitter whose Type() is "LAU"
## and whose owner(wallet) is true; the simulated return is the fallback.
static func find_forged_lau(receipt: Dictionary, simulated: String) -> String:
	var seen := {}
	for lg in receipt.get("logs", []):
		var a := String(lg.get("address", "")).to_lower()
		if seen.has(a):
			continue
		seen[a] = true
		var t := await Chain.rpc.call_decoded(a, "Type()", [], ["string"])
		if not t["ok"] or String(t["values"][0]) != "LAU":
			continue
		var own := await Chain.rpc.call_decoded(a, "owner(address)", [Session.wallet], ["bool"])
		if own["ok"] and own["values"][0]:
			return a
	var d := Abi.strip0x(simulated)
	if d.length() >= 64:
		return "0x" + d.substr(24, 40)
	return ""
