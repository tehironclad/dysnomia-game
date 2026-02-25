extends MinigameBase
## Entropy Dice — roll 3 dice seeded from territory entropy, score combos.

var _dice_labels: Array[Label] = []
var _roll_btn: Button
var _result_label: Label
var _rolling: bool = false
var _roll_timer: float = 0.0
var _roll_count: int = 0
var _final_values: Array[int] = [1, 1, 1]


func _ready() -> void:
	_init_ui("Entropy Dice")
	_build_game_ui()
	start_game()


func _build_game_ui() -> void:
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	_content_vbox.add_child(spacer)

	# Dice display (3 large labels in a row)
	var dice_row := HBoxContainer.new()
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_row.add_theme_constant_override("separation", 20)
	_content_vbox.add_child(dice_row)

	for i in range(3):
		var die := Label.new()
		die.text = "?"
		die.add_theme_font_size_override("font_size", 64)
		die.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		die.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		die.custom_minimum_size = Vector2(80, 90)

		# Die background
		var die_panel := PanelContainer.new()
		var die_style := StyleBoxFlat.new()
		die_style.bg_color = Color(0.12, 0.12, 0.18)
		die_style.set_corner_radius_all(8)
		die_style.border_width_left = 2
		die_style.border_width_right = 2
		die_style.border_width_top = 2
		die_style.border_width_bottom = 2
		die_style.border_color = Color(0.4, 0.3, 0.7, 0.5)
		die_panel.add_theme_stylebox_override("panel", die_style)
		die_panel.add_child(die)
		dice_row.add_child(die_panel)
		_dice_labels.append(die)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	_content_vbox.add_child(spacer2)

	# Result label
	_result_label = Label.new()
	_result_label.text = "Roll the dice!"
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(_result_label)

	# Spacer
	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 15)
	_content_vbox.add_child(spacer3)

	# Roll button
	_roll_btn = Button.new()
	_roll_btn.text = "ROLL"
	_roll_btn.custom_minimum_size = Vector2(150, 50)
	_roll_btn.pressed.connect(_on_roll)
	var btn_center := HBoxContainer.new()
	btn_center.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_center.add_child(_roll_btn)
	_content_vbox.add_child(btn_center)

	# Scoring help
	var help := Label.new()
	help.text = "\nTriples: 100pts  |  Straight: 50pts  |  Pair: 30pts"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(help)


func _process(delta: float) -> void:
	if _rolling:
		_roll_timer += delta
		# Animate dice cycling
		if _roll_timer < 1.5:
			for i in range(3):
				_dice_labels[i].text = str(randi_range(1, 6))
		else:
			# Settle
			_rolling = false
			for i in range(3):
				_dice_labels[i].text = str(_final_values[i])
			_evaluate_roll()
			_roll_btn.disabled = false


func _on_roll() -> void:
	_rolling = true
	_roll_timer = 0.0
	_roll_count += 1
	_roll_btn.disabled = true
	_result_label.text = "Rolling..."

	# Generate final values from territory entropy + roll count
	var entropy := GameManager.territory_entropy if GameManager.territory_entropy > 0 else randi()
	var seed_val := entropy + _roll_count * 7919
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	_final_values = [rng.randi_range(1, 6), rng.randi_range(1, 6), rng.randi_range(1, 6)]


func _evaluate_roll() -> void:
	var d := _final_values.duplicate()
	d.sort()

	# Check combos
	if d[0] == d[1] and d[1] == d[2]:
		_result_label.text = "TRIPLE %d's! +100" % d[0]
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_update_score(100)
	elif d[0] + 1 == d[1] and d[1] + 1 == d[2]:
		_result_label.text = "Straight! %d-%d-%d  +50" % [d[0], d[1], d[2]]
		_result_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		_update_score(50)
	elif d[0] == d[1] or d[1] == d[2]:
		_result_label.text = "Pair! +30"
		_result_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
		_update_score(30)
	else:
		_result_label.text = "Nothing... try again"
		_result_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))
