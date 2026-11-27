extends Control
## Today's challenge, full screen (scenes/ui/daily_play.tscn; the front door's "Today's challenge"
## card opens it). The day's arcade game on its own 320×240 screen, scaled up in a CRT frame; beside
## it the board (DailyBoard), your tries, streak and where the seed came from.
##
## Play (arcade_start) spends one of today's scored tries and runs the day's seed: on the board when
## the game server signed you in (it replays the run), on this computer otherwise. Practice
## (daily_practice) is free and unlimited on a different seed, never on a board. Every run shows
## GameHowto's card first, then its controls strip; Esc ends a run (its score counts), Esc again
## goes back to the front door. The game's attract demo plays while nothing runs.

const FRONT_DOOR := "res://scenes/ui/front_door.tscn"
const SCREEN_SCALE := 3  ## whole pixels: 960×720
const SCREEN_POS := Vector2(64, 196)
const GOLD := Color("#ffd36b")

var game_id := ""
var game: ArcadeGame
var vp: SubViewport
var board: DailyBoard
var howto: GameHowto
var run: Dictionary = {}   ## the run in play (DailyRun.begin), {} when none
var running := false
var busy := false
var last_result := ""
var _title: Label
var _status: Label
var _back: Button
var _pending_start := false


func _ready() -> void:
	theme = DeepFieldTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var bg := ColorRect.new()
	bg.color = DeepFieldTheme.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_header()
	_build_screen()
	_build_side()
	howto = GameHowto.new()
	howto.name = "HowTo"
	add_child(howto)
	howto.dismissed.connect(_on_card_dismissed)
	_load_game(DailyRun.today())
	var net := get_node_or_null("/root/Net")
	if net and net.has_method("start"):
		net.start()  # the board lives on the game server (quiet when none answers)
	_set_status("")


func _build_header() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(SCREEN_POS.x, 64)
	v.custom_minimum_size = Vector2(320 * SCREEN_SCALE, 0)
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var k := Label.new()
	k.theme_type_variation = "MutedLabel"
	k.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	k.add_theme_color_override("font_color", GOLD)
	k.text = "THE DAILY CHALLENGE  ·  ONE GAME A DAY, THE SAME RUN FOR EVERYONE"
	v.add_child(k)
	_title = Label.new()
	_title.theme_type_variation = "DisplayLabel"
	_title.add_theme_font_size_override("font_size", DeepFieldTheme.FS_DISPLAY)
	v.add_child(_title)
	_status = Label.new()
	_status.theme_type_variation = "MonoLabel"
	_status.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	_status.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320 * SCREEN_SCALE, 0)
	v.add_child(_status)


func _build_screen() -> void:
	var frame := PanelContainer.new()
	var sb := DeepFieldTheme.panel_style(DeepFieldTheme.ICE)
	sb.bg_color = Color(0, 0, 0, 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", sb)
	frame.position = SCREEN_POS - Vector2(6, 6)
	add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.stretch_shrink = SCREEN_SCALE  # the viewport stays 320×240, drawn SCREEN_SCALE× bigger
	svc.custom_minimum_size = Vector2(ArcadeGame.SIZE) * SCREEN_SCALE
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(svc)
	vp = SubViewport.new()
	vp.size = ArcadeGame.SIZE
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)


func _build_side() -> void:
	var x := SCREEN_POS.x + 320 * SCREEN_SCALE + 48
	var v := VBoxContainer.new()
	v.position = Vector2(x, 64)
	v.custom_minimum_size = Vector2(1920 - 64 - x, 0)
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	board = DailyBoard.new()
	board.custom_minimum_size = Vector2(1920 - 64 - x, 0)
	v.add_child(board)
	board.play_pressed.connect(func(): start(false))
	board.practice_pressed.connect(func(): start(true))
	_back = Button.new()
	_back.text = "←  Front door (Esc)"
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(leave)
	v.add_child(_back)


## The day's game on the screen, its attract demo running. A new UTC day loads the new game.
func _load_game(day: String) -> void:
	var id := DailyChallenge.game_for(day)
	if id == game_id and game != null:
		return
	if game != null:
		game.queue_free()
	game_id = id
	game = load(DailyChallenge.script_of(id)).new()
	vp.add_child(game)
	game.game_over.connect(_on_game_over)
	game.attract()
	_title.text = DailyChallenge.title_of(id).to_upper()
	var entry := ArcadeCatalog.find(id)
	howto.setup({"title": DailyChallenge.title_of(id), "tag": "Today's challenge", "rules": [String(entry.get("blurb", "")),
		"Free: no Ⓐ ticket. %d scored tries a day, your best counts; practice is unlimited on another seed and never on a board." % DailyChallenge.ATTEMPTS,
		"On the board, the server replays your run's inputs on the day's seed: the score is the replay's."],
		"controls": controls_rows(), "accent": GOLD, "verb": "play", "esc": "end the run"})


func controls_rows() -> Array:
	return [["%s%s%s%s / arrows" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_back"),
		ControlsHelp.key_of("move_right")], "move"], [ControlsHelp.key_of("jump"), "fire"], ["Esc", "end the run (the score counts)"]]


## Starts a scored run (practice=false) or a practice run, after the how-to card.
func start(practice: bool) -> void:
	if running or busy or _pending_start:
		return
	if DailyRun.today() != String(run.get("day", DailyRun.today())) or DailyChallenge.game_for(DailyRun.today()) != game_id:
		_load_game(DailyRun.today())
	busy = true
	_set_status("Checking the seed block…" if not practice else "Practice…")
	var r: Dictionary = await DailyRun.begin(practice)
	busy = false
	if not r.get("ok", false):
		_set_status(String(r.get("error", "—")))
		board.refresh()
		return
	run = r
	_pending_start = true
	_set_status(String(r["label"]))
	howto.open_card(GameHowto.Mode.KEY)


func _on_card_dismissed(mode: int) -> void:
	if mode == GameHowto.Mode.HELP:
		if running and game:
			game.set_process(true)
		return
	if not _pending_start:
		return
	_pending_start = false
	game.recording = not bool(run.get("practice", true))
	game.start(int(run["seed"]))
	running = true
	board.play_button.disabled = true
	board.practice_button.disabled = true
	howto.set_strip(controls_rows())
	howto.show_strip(true)


func _on_game_over(_score: int) -> void:
	if not running:
		return
	running = false
	howto.end()
	busy = true
	_set_status("Game over · %s · %s" % [ArcadeScores.grouped(game.score), "the server is replaying your run…" if run.get("board", false) else "recording…"])
	var res: Dictionary = await DailyRun.finish(run, game)
	busy = false
	last_result = String(res.get("text", ""))
	game.recording = false
	run = {}
	_set_status(last_result)
	board.refresh()
	await get_tree().create_timer(2.5).timeout
	if not running and game and not game.playing:
		game.attract()


func leave() -> void:
	if running or busy:
		return
	get_tree().change_scene_to_file(FRONT_DOOR)


func _set_status(t: String) -> void:
	var st := DailyRun.status()
	_status.text = t if t != "" else "%s · %s" % [DailyChallenge.seed_text(st["seed"]), "the demo plays itself until you start"]


func _unhandled_input(event: InputEvent) -> void:
	if howto.wants(event):
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if running and game and game.playing:
			game.end_game()  # Esc: the run ends here and its score counts
		elif not _pending_start:
			leave()
	elif event.is_action_pressed("arcade_start") and not running:
		get_viewport().set_input_as_handled()
		start(false)
	elif event.is_action_pressed("daily_practice") and not running:
		get_viewport().set_input_as_handled()
		start(true)


func _process(_delta: float) -> void:
	if howto.is_card_open() and howto.mode == GameHowto.Mode.HELP and running and game:
		game.set_process(false)  # the run waits while the help card is up


## Screenshot previews (tools/screenshot.gd --daily=play): a practice run held mid-play with a
## scripted input. Nothing is submitted.
func preview_play() -> void:
	run = {"practice": true, "seed": DailyChallenge.practice_seed(DailyRun.today(), 0), "day": DailyRun.today(), "label": "PRACTICE (preview)"}
	_set_status("PRACTICE · PREVIEW · a different seed · not on any board")
	game.scripted_input = ArcadeGame.IN_RIGHT
	game.start(int(run["seed"]))
	running = true
	howto.set_strip(controls_rows())
	howto.show_strip(true)
	for i in 240:
		game.scripted_input = ArcadeGame.IN_FIRE if i % 40 < 10 else (ArcadeGame.IN_LEFT if (i / 60) % 2 == 0 else ArcadeGame.IN_RIGHT)
		game.step(ArcadeGame.DT)
		if not game.playing:
			break
	game.scripted_input = 0
	game.set_process(false)  # hold this frame
