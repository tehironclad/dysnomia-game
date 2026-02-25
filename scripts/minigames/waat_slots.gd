extends MinigameBase
## Waat Slots — 3 spinning columns with territory-themed symbols.

const SYMBOLS: Array[String] = ["*", "@", "#", "+", "~", "^"]
const SYMBOL_NAMES: Array[String] = ["Planet", "Moon", "Star", "Crystal", "Tesseract", "Creature"]

var _column_labels: Array[Label] = []
var _spin_btn: Button
var _result_label: Label
var _spinning: Array[bool] = [false, false, false]
var _spin_timers: Array[float] = [0.0, 0.0, 0.0]
var _stop_times: Array[float] = [0.8, 1.3, 1.8]  # Columns stop sequentially
var _final_symbols: Array[int] = [0, 0, 0]
var _spin_count: int = 0


func _ready() -> void:
	_init_ui("Waat Slots")
	_build_game_ui()
	start_game()


func _build_game_ui() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	_content_vbox.add_child(spacer)

	# Slot columns (3 large symbol displays)
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 12)
	_content_vbox.add_child(slot_row)

	for i in range(3):
		var col := Label.new()
		col.text = SYMBOLS[0]
		col.add_theme_font_size_override("font_size", 72)
		col.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
		col.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.custom_minimum_size = Vector2(90, 100)

		var col_panel := PanelContainer.new()
		var col_style := StyleBoxFlat.new()
		col_style.bg_color = Color(0.1, 0.08, 0.14)
		col_style.set_corner_radius_all(6)
		col_style.border_width_left = 2
		col_style.border_width_right = 2
		col_style.border_width_top = 2
		col_style.border_width_bottom = 2
		col_style.border_color = Color(0.6, 0.4, 0.2, 0.6)
		col_panel.add_theme_stylebox_override("panel", col_style)
		col_panel.add_child(col)
		slot_row.add_child(col_panel)
		_column_labels.append(col)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	_content_vbox.add_child(spacer2)

	# Result
	_result_label = Label.new()
	_result_label.text = "Pull the lever!"
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(_result_label)

	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 15)
	_content_vbox.add_child(spacer3)

	# Spin button
	_spin_btn = Button.new()
	_spin_btn.text = "SPIN"
	_spin_btn.custom_minimum_size = Vector2(150, 50)
	_spin_btn.pressed.connect(_on_spin)
	var btn_center := HBoxContainer.new()
	btn_center.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_center.add_child(_spin_btn)
	_content_vbox.add_child(btn_center)

	# Payout info
	var help := Label.new()
	help.text = "\n3 Match: 500pts  |  2 Match: 50pts"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(help)


func _process(delta: float) -> void:
	var all_stopped := true
	for i in range(3):
		if _spinning[i]:
			_spin_timers[i] += delta
			if _spin_timers[i] >= _stop_times[i]:
				_spinning[i] = false
				_column_labels[i].text = SYMBOLS[_final_symbols[i]]
			else:
				# Animate cycling
				_column_labels[i].text = SYMBOLS[randi() % SYMBOLS.size()]
				all_stopped = false
		elif _spin_timers[i] > 0:
			pass  # Already stopped
		else:
			pass

	if not all_stopped:
		return

	# Check if all just finished
	if _spin_timers[0] > 0 and not _spinning[0] and not _spinning[1] and not _spinning[2]:
		var all_done := _spin_timers[0] >= _stop_times[0] and _spin_timers[1] >= _stop_times[1] and _spin_timers[2] >= _stop_times[2]
		if all_done and _spin_btn.disabled:
			_evaluate_spin()
			_spin_btn.disabled = false


func _on_spin() -> void:
	_spin_count += 1
	_spin_btn.disabled = true
	_result_label.text = "Spinning..."

	# Generate results from waat + spin count
	var waat := GameManager.territory_waat_hex.hash() if not GameManager.territory_waat_hex.is_empty() else randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = waat + _spin_count * 3571

	_final_symbols = [rng.randi() % SYMBOLS.size(), rng.randi() % SYMBOLS.size(), rng.randi() % SYMBOLS.size()]
	_spinning = [true, true, true]
	_spin_timers = [0.0, 0.0, 0.0]


func _evaluate_spin() -> void:
	var a := _final_symbols[0]
	var b := _final_symbols[1]
	var c := _final_symbols[2]

	if a == b and b == c:
		_result_label.text = "JACKPOT! Triple %s! +500" % SYMBOL_NAMES[a]
		_result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_update_score(500)
	elif a == b or b == c or a == c:
		var match_sym := a if (a == b or a == c) else b
		_result_label.text = "Double %s! +50" % SYMBOL_NAMES[match_sym]
		_result_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		_update_score(50)
	else:
		_result_label.text = "No match. Try again!"
		_result_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))
		# Reset spin timers for next check
	_spin_timers = [0.0, 0.0, 0.0]
