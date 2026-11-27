class_name DailyCard
extends PanelContainer
## "Today's challenge" on the front door, under the doors: the day's game, the top score (the game
## server's board; "—" with no server), time left until 00:00 UTC, your tries and streak, Play and
## Board. Play opens DailyPlay; Board opens the full board in the right column (DailyBoard).
## Reads the seed block and the board itself; nothing here is invented.

signal play_pressed
signal board_pressed

var top_text := "checking…"
var _t := 0.0
var _kicker: Label
var _title: Label
var _facts: Label
var play: Button
var board: Button


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(Color("#ffd36b"))
	sb.bg_color = Color(1.0, 0.83, 0.42, 0.08)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(620, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_kicker = Label.new()
	_kicker.theme_type_variation = "MutedLabel"
	_kicker.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	_kicker.add_theme_color_override("font_color", Color("#ffd36b"))
	v.add_child(_kicker)
	_title = Label.new()
	_title.add_theme_font_override("font", DeepFieldTheme.display_font())
	_title.add_theme_font_size_override("font_size", 19)
	v.add_child(_title)
	_facts = Label.new()
	_facts.theme_type_variation = "MonoLabel"
	_facts.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	_facts.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_facts.clip_text = true
	_facts.custom_minimum_size = Vector2(380, 0)
	_facts.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_facts)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", 6)
	h.add_child(bv)
	play = Button.new()
	play.text = "Play  ▸"
	play.custom_minimum_size = Vector2(120, 40)
	play.pressed.connect(func(): play_pressed.emit())
	bv.add_child(play)
	board = Button.new()
	board.text = "Board"
	board.custom_minimum_size = Vector2(120, 34)
	board.pressed.connect(func(): board_pressed.emit())
	bv.add_child(board)


func _ready() -> void:
	var net := get_node_or_null("/root/Net")
	if net and net.has_signal("status_changed"):
		net.status_changed.connect(func(_s): if is_inside_tree(): refresh())
	if net and net.get("client"):
		net.client.auth_changed.connect(func(_w): if is_inside_tree(): refresh())
	refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 10.0:  # minutes are the finest the screen shows; status() reads a small file
		_t = 0.0
		_render()


## Reads the seed block and the server's top score (when a server with the daily board answers).
func refresh() -> void:
	_render()
	var day := DailyRun.today()
	if DailySeed.peek(day)["state"] != "ok":
		await DailySeed.find(day)
		_render()
	if not DailyRun.board_online():
		top_text = "—"
		_render()
		return
	var b: Dictionary = await get_node("/root/Net").call("daily_board", day)
	if not is_inside_tree():
		return
	var rows: Array = b.get("rows", []) if b.get("ok", false) else []
	if not b.get("ok", false):
		top_text = "—"
	elif rows.is_empty():
		top_text = "no runs yet"
	else:
		var net := get_node_or_null("/root/Net")
		var nm := String(net.names.display(String(rows[0]["wallet"]))) if net and net.get("names") else NetProto.short_wallet(String(rows[0]["wallet"]))
		top_text = "%s · %s" % [ArcadeScores.grouped(int(rows[0]["score"])), nm]
	_render()


func _render() -> void:
	var st := DailyRun.status()
	_kicker.text = "TODAY'S CHALLENGE  ·  %s" % st["left_text"]
	_title.text = String(st["title"]).to_upper()
	var seed: Dictionary = st["seed"]
	var tries := "%d/%d tries" % [int(st["left"]), DailyChallenge.ATTEMPTS]
	if seed["state"] == "checking":
		tries = "seed checking…"
	elif seed["state"] != "ok":
		tries = "seed — practice only"
	var streak := int(st["streak"])
	_facts.text = "top %s · %s · streak %s" % [top_text, tries, ("%d d" % streak) if streak > 0 else "—"]
	_facts.tooltip_text = "Top score: the game server's board (replayed runs). Free: no Ⓐ ticket. %s\n%s" % [DailyChallenge.seed_text(seed), DailyChallenge.SOURCE]
