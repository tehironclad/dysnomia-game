extends MinigameBase
## Territory Trivia — ten questions generated from real Dysnomia data (see TriviaBank):
## real QING names, this QING's live charge and bars, contract roles, the Motzkin prime,
## chain id 369, the fair's rides and the bar's AFFECTION drinks.
## Difficulty ramps 1 → 3, the clock tightens, a streak multiplies your points and you get
## one 50/50 per game. 6/10 passes; 10/10 is a perfect round.

const TIME_BY_DIFF := {1: 15.0, 2: 13.0, 3: 11.0}
const PASS_MARK := 6

var _question_label: RichTextLabel
var _fact_label: Label
var _answer_buttons: Array[Button] = []
var _timer_bar: ProgressBar
var _round_label: Label
var _streak_label: Label
var _fifty_btn: Button
var _timer: float = 15.0
var _time_max: float = 15.0
var _current: int = 0
var _questions: Array = []
var _waiting: bool = false
var _correct_index: int = 0
var _correct_count: int = 0
var _streak: int = 0
var _best_streak: int = 0
var _fifty_used: bool = false
var _tick_second: int = -1


func _ready() -> void:
	_init_ui("Territory Trivia", "%s · questions from the chain itself" % DysnomiaLore.qing_label(), Vector2(500, 560))
	_build_game_ui()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_questions = TriviaBank.build_game(TriviaBank.live_context(), rng)
	start_game()
	_show_question()


func _build_game_ui() -> void:
	var top := HBoxContainer.new()
	_content_vbox.add_child(top)
	_round_label = _label("", 13, DysnomiaLore.DIM)
	_round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_round_label)
	_streak_label = _label("", 13, PINK)
	top.add_child(_streak_label)

	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 8)
	_timer_bar.max_value = 1.0
	_timer_bar.step = 0.001
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.12, 0.22)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = PULSE
	fg.set_corner_radius_all(4)
	_timer_bar.add_theme_stylebox_override("background", bg)
	_timer_bar.add_theme_stylebox_override("fill", fg)
	_content_vbox.add_child(_timer_bar)

	_question_label = RichTextLabel.new()
	_question_label.bbcode_enabled = true
	_question_label.fit_content = true
	_question_label.scroll_active = false
	_question_label.custom_minimum_size = Vector2(0, 74)
	_question_label.add_theme_font_size_override("normal_font_size", 19)
	_question_label.add_theme_font_size_override("bold_font_size", 19)
	_content_vbox.add_child(_question_label)

	for i in 4:
		var btn := _button("…", Color(0.4, 0.35, 0.6), Vector2(0, 46))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_answer.bind(i))
		_content_vbox.add_child(btn)
		_answer_buttons.append(btn)

	_fact_label = _center_label(" ", 12, Color(0.75, 0.75, 0.88))
	_fact_label.custom_minimum_size = Vector2(0, 36)
	_content_vbox.add_child(_fact_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_content_vbox.add_child(row)
	_fifty_btn = _button("50/50", PINK, Vector2(110, 34))
	_fifty_btn.pressed.connect(_on_fifty)
	row.add_child(_fifty_btn)


func _show_question() -> void:
	if _current >= _questions.size():
		_finish_trivia()
		return
	var q: Dictionary = _questions[_current]
	var diff: int = q["difficulty"]
	_round_label.text = "Question %d / %d   ·   %s" % [_current + 1, _questions.size(), ["", "warm-up", "regular", "deep lore"][diff]]
	_question_label.clear()
	_question_label.append_text("[b]%s[/b]" % q["q"])
	_correct_index = q["correct"]
	for i in 4:
		var b := _answer_buttons[i]
		b.text = "  %s   %s" % [["A", "B", "C", "D"][i], q["answers"][i]]
		b.disabled = false
		b.visible = true
		b.modulate = Color.WHITE
	_fact_label.text = " "
	_time_max = TIME_BY_DIFF[diff]
	_timer = _time_max
	_tick_second = -1
	_waiting = true
	_fifty_btn.disabled = _fifty_used
	_update_streak()
	_question_label.modulate.a = 0.0
	_question_label.create_tween().tween_property(_question_label, "modulate:a", 1.0, 0.25)


func _process(delta: float) -> void:
	_base_process(delta)
	if not _waiting:
		return
	_timer -= delta
	var frac := maxf(0.0, _timer / _time_max)
	_timer_bar.value = frac
	var fill: StyleBoxFlat = _timer_bar.get_theme_stylebox("fill")
	fill.bg_color = PULSE.lerp(DysnomiaLore.BAD, clampf(1.0 - frac * 2.5, 0.0, 1.0))
	if _timer <= 4.0 and int(_timer) != _tick_second and _timer > 0.0:
		_tick_second = int(_timer)
		_sfx("tick", 1.0 + (4.0 - _timer) * 0.1)
	if _timer <= 0.0:
		_waiting = false
		_on_timeout()


func _on_answer(idx: int) -> void:
	if not _waiting:
		return
	_waiting = false
	var q: Dictionary = _questions[_current]
	var diff: int = q["difficulty"]
	_answer_buttons[_correct_index].modulate = Color(0.5, 1.4, 0.6)
	for b in _answer_buttons:
		b.disabled = true
	if idx == _correct_index:
		_correct_count += 1
		_streak += 1
		_best_streak = maxi(_best_streak, _streak)
		var speed := int(50.0 * diff * clampf(_timer / _time_max, 0.0, 1.0))
		var mult := minf(1.0 + 0.25 * (_streak - 1), 2.0)
		var pts := int(round((100 * diff + speed) * mult))
		_update_score(pts)
		_float_text("+%d" % pts, DysnomiaLore.OK, _answer_buttons[idx])
		_punch(_answer_buttons[idx], 0.06)
		_sfx("win" if _streak < 3 else "big")
		_fact_label.add_theme_color_override("font_color", DysnomiaLore.OK)
		_fact_label.text = ("Correct! " if mult <= 1.0 else "Correct! Streak ×%.2f. " % mult) + q["fact"]
	else:
		_answer_buttons[idx].modulate = Color(1.5, 0.5, 0.5)
		_streak = 0
		_shake(5.0, 0.25)
		_sfx("miss")
		_fact_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
		_fact_label.text = "Not quite. " + q["fact"]
	_update_streak()
	get_tree().create_timer(2.2).timeout.connect(_next_question)


func _on_timeout() -> void:
	var q: Dictionary = _questions[_current]
	_answer_buttons[_correct_index].modulate = Color(0.5, 1.4, 0.6)
	for b in _answer_buttons:
		b.disabled = true
	_streak = 0
	_sfx("miss")
	_fact_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	_fact_label.text = "Time! " + q["fact"]
	_update_streak()
	get_tree().create_timer(2.2).timeout.connect(_next_question)


func _on_fifty() -> void:
	if _fifty_used or not _waiting:
		return
	_fifty_used = true
	_fifty_btn.disabled = true
	var wrong: Array = []
	for i in 4:
		if i != _correct_index:
			wrong.append(i)
	wrong.shuffle()
	for i in wrong.slice(0, 2):
		_answer_buttons[i].disabled = true
		_answer_buttons[i].modulate = Color(1, 1, 1, 0.25)
	_sfx("nudge")


func _update_streak() -> void:
	_streak_label.text = ("Streak %d" % _streak) if _streak >= 2 else ("%d correct" % _correct_count)


func _next_question() -> void:
	if not is_inside_tree():
		return
	_current += 1
	_show_question()


func _finish_trivia() -> void:
	_waiting = false
	for b in _answer_buttons:
		b.visible = false
	_fifty_btn.visible = false
	_question_label.clear()
	_question_label.append_text("[center][b]%d / %d[/b][/center]" % [_correct_count, _questions.size()])
	var perfect := _correct_count == _questions.size() and _questions.size() >= 10
	var won := _correct_count >= PASS_MARK
	var head := "SAGE OF ERIS" if perfect else ("YOU KNOW YOUR QING" if won else "BACK TO THE ARCHIVES")
	var lines: Array = ["%d / %d correct · best streak %d" % [_correct_count, _questions.size(), _best_streak]]
	if not won and _correct_count == PASS_MARK - 1:
		lines.append("One answer short of a pass.")
	finish(won, {"headline": head, "lines": lines, "perfect": perfect})
