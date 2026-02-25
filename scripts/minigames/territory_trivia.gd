extends MinigameBase
## Territory Trivia — questions about Dysnomia lore and current territory state.

var _question_label: RichTextLabel
var _answer_buttons: Array[Button] = []
var _timer_label: Label
var _round_label: Label
var _timer: float = 15.0
var _current_question: int = 0
var _total_questions: int = 10
var _questions: Array[Dictionary] = []
var _waiting_for_answer: bool = false
var _correct_index: int = 0
var _answered_this_round: bool = false


func _ready() -> void:
	_init_ui("Territory Trivia")
	_build_game_ui()
	_generate_questions()
	start_game()
	_show_question()


func _build_game_ui() -> void:
	# Round indicator
	_round_label = Label.new()
	_round_label.text = "Question 1 / 10"
	_round_label.add_theme_font_size_override("font_size", 13)
	_round_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(_round_label)

	# Question text
	_question_label = RichTextLabel.new()
	_question_label.bbcode_enabled = true
	_question_label.fit_content = true
	_question_label.custom_minimum_size = Vector2(0, 80)
	_question_label.add_theme_font_size_override("normal_font_size", 16)
	_content_vbox.add_child(_question_label)

	# Timer
	_timer_label = Label.new()
	_timer_label.text = "15s"
	_timer_label.add_theme_font_size_override("font_size", 20)
	_timer_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(_timer_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_content_vbox.add_child(spacer)

	# 4 answer buttons
	for i in range(4):
		var btn := Button.new()
		btn.text = "Answer %d" % (i + 1)
		btn.custom_minimum_size = Vector2(0, 36)
		var idx := i
		btn.pressed.connect(func(): _on_answer(idx))
		_content_vbox.add_child(btn)
		_answer_buttons.append(btn)


func _generate_questions() -> void:
	_questions.clear()

	# Static lore questions
	_questions.append({"q": "What is the MOTZKIN_PRIME constant?",
		"answers": ["953467954114363", "999999999999989", "1000000000000003", "736281946291739"],
		"correct": 0})
	_questions.append({"q": "What blockchain does Dysnomia run on?",
		"answers": ["PulseChain", "Ethereum", "Solana", "Avalanche"], "correct": 0})
	_questions.append({"q": "What celestial body is Eris named after?",
		"answers": ["A dwarf planet", "A star", "A moon of Jupiter", "An asteroid"], "correct": 0})
	_questions.append({"q": "How many biome types exist?",
		"answers": ["4", "6", "8", "2"], "correct": 0})
	_questions.append({"q": "What creature type is fastest?",
		"answers": ["Stalker", "Crawler", "Floater", "Burrower"], "correct": 0})
	_questions.append({"q": "What does HECKE.Compliment() return?",
		"answers": ["Longitude & Latitude", "Name & Address", "Power & Energy", "Hash & Nonce"], "correct": 0})
	_questions.append({"q": "What contract handles terraform ops?",
		"answers": ["AFFECTION", "META", "VOID", "LAU"], "correct": 0})
	_questions.append({"q": "What does META.Beat() do?",
		"answers": ["State aggregation", "Mine tokens", "Transfer ownership", "Deploy contract"], "correct": 0})
	_questions.append({"q": "How many QING territories exist?",
		"answers": ["~263", "~100", "~500", "~1000"], "correct": 0})
	_questions.append({"q": "What is the player character?",
		"answers": ["Teddy bear astronaut", "Robot soldier", "Space marine", "Alien explorer"], "correct": 0})
	_questions.append({"q": "What vehicle is unlocked first?",
		"answers": ["Rover", "Hoverbike", "Tank", "Shuttle"], "correct": 0})
	_questions.append({"q": "What key opens the World Map?",
		"answers": ["M", "W", "G", "Tab"], "correct": 0})
	_questions.append({"q": "What does the tesseract represent?",
		"answers": ["Territory energy core", "Player health", "Time cycle", "Wallet balance"], "correct": 0})
	_questions.append({"q": "What gravity multiplier is used?",
		"answers": ["~0.33x Earth", "1x Earth", "0.1x Earth", "2x Earth"], "correct": 0})
	_questions.append({"q": "How many weapon types are there?",
		"answers": ["4", "2", "6", "8"], "correct": 0})

	# Shuffle and pick 10
	_questions.shuffle()
	if _questions.size() > _total_questions:
		_questions.resize(_total_questions)

	# Shuffle answers for each question (keeping track of correct)
	for q in _questions:
		var correct_answer: String = q["answers"][q["correct"]]
		q["answers"].shuffle()
		q["correct"] = q["answers"].find(correct_answer)


func _show_question() -> void:
	if _current_question >= _questions.size():
		_finish_game()
		return

	var q: Dictionary = _questions[_current_question]
	_round_label.text = "Question %d / %d" % [_current_question + 1, _total_questions]
	_question_label.clear()
	_question_label.append_text("[color=#e0e0ff][b]%s[/b][/color]" % q["q"])

	_correct_index = q["correct"]
	for i in range(4):
		_answer_buttons[i].text = q["answers"][i]
		_answer_buttons[i].disabled = false
		_answer_buttons[i].modulate = Color.WHITE

	_timer = 15.0
	_waiting_for_answer = true
	_answered_this_round = false


func _process(delta: float) -> void:
	if _waiting_for_answer:
		_timer -= delta
		_timer_label.text = "%.0fs" % maxf(0, _timer)

		if _timer <= 5.0:
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			_timer_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))

		if _timer <= 0.0:
			_waiting_for_answer = false
			_on_timeout()


func _on_answer(idx: int) -> void:
	if not _waiting_for_answer or _answered_this_round:
		return
	_answered_this_round = true
	_waiting_for_answer = false

	# Highlight correct answer
	_answer_buttons[_correct_index].modulate = Color(0.3, 1.0, 0.3)

	if idx == _correct_index:
		var bonus: int = 50 if _timer > 10.0 else 0
		_update_score(100 + bonus)
		_question_label.append_text("\n[color=#22cc55]Correct!%s[/color]" % (
			" +50 speed bonus!" if bonus > 0 else ""))
	else:
		_answer_buttons[idx].modulate = Color(1.0, 0.3, 0.3)
		_update_score(-50)
		_question_label.append_text("\n[color=#cc3333]Wrong! -50[/color]")

	# Disable all buttons
	for btn in _answer_buttons:
		btn.disabled = true

	# Next question after delay
	get_tree().create_timer(1.5).timeout.connect(_next_question)


func _on_timeout() -> void:
	_answer_buttons[_correct_index].modulate = Color(0.3, 1.0, 0.3)
	for btn in _answer_buttons:
		btn.disabled = true
	_question_label.append_text("\n[color=#cc8833]Time's up![/color]")
	get_tree().create_timer(1.5).timeout.connect(_next_question)


func _next_question() -> void:
	_current_question += 1
	_show_question()


func _finish_game() -> void:
	_question_label.clear()
	_question_label.append_text("[color=#FFD700][b]Game Over![/b][/color]\n\nFinal Score: %d" % _score)
	_timer_label.text = ""
	_round_label.text = "Complete!"
	for btn in _answer_buttons:
		btn.visible = false
	end_game()
