class_name DailyBoard
extends PanelContainer
## Today's challenge board (the front door's right column, and beside the game in DailyPlay):
## the game, where its seed came from, time left, your tries and streak, the server's top 10 with
## your rank, and yesterday's winner. Names are the chain's for each wallet (Net.names: LauNames),
## never a name from the server. Every number says where it is from; a board nobody could read is
## "—", one being read "checking…", an empty one says so. Not signed in: a line saying so and a
## button to the steps there (AccessSteps "daily_board": a wallet, the server, its free sign-in),
## never a bare refusal.

signal play_pressed
signal practice_pressed

var show_buttons := true      ## the front door's panel has Play / Practice; DailyPlay has its own
var board: Dictionary = {}    ## the last S_DAILY_BOARD (cleaned), {} while none
var board_state := "checking" ## checking | ok | offline | error
var _t := 0.0
var _req := 0
var _kicker: Label
var _title: Label
var _seed: Label
var _facts: Label
var _rows_head: Label
var _rows: GridContainer
var _me: Label
var _yesterday: Label
var _steps_line: Label
var _steps_btn: Button
var _buttons: HBoxContainer
var play_button: Button
var practice_button: Button


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	_kicker = _label("", "MutedLabel", DeepFieldTheme.FS_CAPTION)
	_kicker.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	v.add_child(_kicker)
	_title = _label("", "DisplayLabel", 26)
	v.add_child(_title)
	_seed = _label("", "MonoLabel", DeepFieldTheme.FS_CAPTION)
	_seed.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	_seed.mouse_filter = Control.MOUSE_FILTER_PASS
	_seed.tooltip_text = DailyChallenge.SOURCE
	v.add_child(_seed)
	_facts = _label("", "MonoLabel", DeepFieldTheme.FS_SMALL)
	v.add_child(_facts)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	v.add_child(_buttons)
	play_button = Button.new()
	play_button.pressed.connect(func(): play_pressed.emit())
	_buttons.add_child(play_button)
	practice_button = Button.new()
	practice_button.text = "Practice (free, unlimited)"
	practice_button.pressed.connect(func(): practice_pressed.emit())
	_buttons.add_child(practice_button)
	v.add_child(HSeparator.new())
	_rows_head = _label("", "MutedLabel", DeepFieldTheme.FS_CAPTION)
	v.add_child(_rows_head)
	_rows = GridContainer.new()
	_rows.columns = 4
	_rows.add_theme_constant_override("h_separation", 14)
	_rows.add_theme_constant_override("v_separation", 1)
	v.add_child(_rows)
	_me = _label("", "MonoLabel", DeepFieldTheme.FS_SMALL)
	_me.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	v.add_child(_me)
	_yesterday = _label("", "MonoLabel", DeepFieldTheme.FS_CAPTION)
	_yesterday.add_theme_color_override("font_color", DeepFieldTheme.MUTED)
	v.add_child(_yesterday)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 10)
	v.add_child(sr)
	_steps_line = _label("", "MutedLabel", DeepFieldTheme.FS_CAPTION)
	_steps_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(_steps_line)
	_steps_btn = Button.new()
	_steps_btn.text = "Steps to the board →"
	_steps_btn.pressed.connect(open_steps)
	sr.add_child(_steps_btn)


## The steps onto the board, over whatever scene this board is in (AccessSteps.popup).
func open_steps() -> void:
	AccessSteps.popup(get_tree().current_scene, "daily_board", {"extra": DailyRun.access_extra(),
		"subtitle": "Guests play and keep their best on this computer; the board needs a wallet signed in to the game server (free)."},
		DailyRun.access_handlers())


func _label(text: String, variation: String, size: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(size, DeepFieldTheme.FS_MIN))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _ready() -> void:
	var net := get_node_or_null("/root/Net")
	if net and net.get("names") and net.names.has_signal("resolved"):
		net.names.resolved.connect(func(_w): _render())
	if net and net.has_signal("status_changed"):
		net.status_changed.connect(func(_s): if is_inside_tree(): refresh())
	if net and net.get("client"):
		net.client.auth_changed.connect(func(_w): if is_inside_tree(): refresh())
	refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if _t >= 10.0:  # minutes are the finest the screen shows; status() reads a small file
		_t = 0.0
		var st := DailyRun.status()
		if String(board.get("day", st["day"])) != String(st["day"]):
			refresh()  # midnight UTC: a new day, a new board
		else:
			_render()


## Reads the seed block (if not yet) and the server's board; redraws as each lands.
func refresh() -> void:
	_render()
	var day := DailyRun.today()
	_req += 1
	var my := _req
	if DailySeed.peek(day)["state"] != "ok":
		_find_seed(day, my)
	if not DailyRun.board_online():
		var net := get_node_or_null("/root/Net")
		board_state = "offline" if net == null or not bool(net.call("is_online")) else "error"
		board = {}
		_render()
		return
	board_state = "checking"
	_render()
	var b: Dictionary = await get_node("/root/Net").call("daily_board", day)
	if my != _req or not is_inside_tree():
		return
	if b.get("ok", false):
		board = b
		board_state = "ok"
	else:
		board = {}
		board_state = "error"
	_render()


func _find_seed(day: String, my: int) -> void:
	await DailySeed.find(day)
	if my == _req and is_inside_tree():
		_render()


func _node_session_wallet() -> String:
	var s := get_node_or_null("/root/Session")
	return String(s.get("wallet")) if s else ""


func _name(w: String) -> String:
	var net := get_node_or_null("/root/Net")
	if net and net.get("names"):
		return String(net.names.display(w))
	return NetProto.short_wallet(w)


func _render() -> void:
	var st := DailyRun.status()
	var seed: Dictionary = st["seed"]
	_kicker.text = "TODAY'S CHALLENGE  ·  %s UTC  ·  %s" % [st["day"], st["left_text"]]
	_title.text = String(st["title"]).to_upper()
	_seed.text = DailyChallenge.seed_text(seed)
	var me: Dictionary = board.get("me", {})
	var used := int(me.get("used", st["used"])) if bool(me.get("signed", false)) else int(st["used"])
	var streak := int(me.get("streak", st["streak"])) if bool(me.get("signed", false)) else int(st["streak"])
	var tries := "%d of %d scored tries left" % [DailyChallenge.attempts_left(used), DailyChallenge.ATTEMPTS]
	var best: Dictionary = st["best"]
	_facts.text = "%s · streak %s · free, no Ⓐ ticket%s" % [tries, ("%d day%s" % [streak, "" if streak == 1 else "s"]) if streak > 0 else "—",
		("\nyour best today on this computer: %s" % ArcadeScores.grouped(int(best["score"]))) if not best.is_empty() else ""]
	var seed_ok: bool = seed["state"] == "ok"
	_buttons.visible = show_buttons
	play_button.disabled = not seed_ok or DailyChallenge.attempts_left(used) <= 0
	play_button.text = ("Play · scored · %s" % ControlsHelp.key_of("arcade_start")) if seed_ok and DailyChallenge.attempts_left(used) > 0 \
		else ("Play · %s" % ("checking the seed…" if seed["state"] == "checking" else "seed — (practice only)" if not seed_ok else "no tries left today"))
	practice_button.text = "Practice · %s (free, unlimited)" % ControlsHelp.key_of("daily_practice")
	# The board
	for c in _rows.get_children():
		c.queue_free()
	var rows: Array = board.get("rows", [])
	match board_state:
		"offline":
			_rows_head.text = "BOARD  ·  — (no game server answered: single-player). Your runs count on this computer."
		"error":
			_rows_head.text = "BOARD  ·  — (the game server has no daily board, or didn't answer)"
		"checking":
			_rows_head.text = "BOARD  ·  checking…"
		_:
			_rows_head.text = ("BOARD  ·  daily:%s  ·  top %d · every run replayed by the server ✓" % [st["day"], DailyChallenge.BOARD_SHOW]) if not rows.is_empty() \
				else "BOARD  ·  daily:%s  ·  no runs yet today: be the first" % st["day"]
	for i in mini(rows.size(), DailyChallenge.BOARD_SHOW):
		var r: Dictionary = rows[i]
		var mine := String(r["wallet"]) == DailyRun.signed_wallet()
		var col := DeepFieldTheme.ICE if mine else (Color("#ffd36b") if i == 0 else DeepFieldTheme.INK)
		for cell in [["#%d" % (i + 1), HORIZONTAL_ALIGNMENT_RIGHT], [_name(String(r["wallet"])), HORIZONTAL_ALIGNMENT_LEFT],
				[ArcadeScores.grouped(int(r["score"])), HORIZONTAL_ALIGNMENT_RIGHT], ["✓" if r["verified"] else "unverified", HORIZONTAL_ALIGNMENT_LEFT]]:
			var l := Label.new()
			l.theme_type_variation = "MonoLabel"
			l.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
			l.add_theme_color_override("font_color", col)
			l.text = cell[0]
			l.horizontal_alignment = cell[1]
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			l.tooltip_text = "%s · %s · attempt %d" % [String(r["wallet"]), String(r["check"]), int(r["attempt"])]
			if cell[1] == HORIZONTAL_ALIGNMENT_LEFT and cell[0] != "✓":
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				l.clip_text = true
				l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_rows.add_child(l)
	# You, and yesterday
	if bool(me.get("signed", false)):
		var rank := int(me.get("rank", 0))
		_me.text = ("You: #%d · %s on the board" % [rank, ArcadeScores.grouped(int(me.get("score", 0)))]) if rank > 0 else "You: not on today's board yet"
	else:
		_me.text = ""  # the line under it says how to get on the board
	_me.visible = _me.text != ""
	var y: Dictionary = board.get("yesterday", {})
	var win: Dictionary = y.get("winner", {})
	if board_state == "ok":
		_yesterday.text = ("Yesterday (%s, %s): %s won with %s%s" % [DailyChallenge.title_of(String(y.get("game", ""))), String(y.get("day", "")),
			_name(String(win["wallet"])), ArcadeScores.grouped(int(win["score"])), " ✓" if win.get("verified", false) else ""]) if not win.is_empty() \
			else "Yesterday (%s): nobody played for the board" % DailyChallenge.title_of(DailyChallenge.game_for(DailyChallenge.prev_day(String(st["day"]))))
	else:
		_yesterday.text = "Yesterday's winner: —"
	# Not on the board yet: the steps there (a wallet, then the server's free sign-in)
	var signed := bool(me.get("signed", false)) or DailyRun.signed_wallet() != ""
	_steps_line.get_parent().visible = not signed
	if not signed:
		var s := _node_session_wallet()
		_steps_line.text = "Not on the board yet: %s" % ("connect a wallet, then sign in to the game server (free)." if s == "" else
			"sign in to the game server (free) as %s." % NetProto.short_wallet(s) if board_state == "ok" else "the board needs the game server (none answered).")
