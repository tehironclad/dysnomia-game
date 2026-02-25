extends MinigameBase
## Card Match — 4x4 memory grid with contract-themed pairs.
## Flip two cards at a time, match all 8 pairs to win. Score by moves.

var _grid: GridContainer
var _cards: Array[Button] = []
var _card_values: Array[String] = []
var _revealed: Array[bool] = []
var _matched: Array[bool] = []
var _first_pick: int = -1
var _second_pick: int = -1
var _checking: bool = false
var _moves: int = 0
var _matches_found: int = 0
var _total_pairs: int = 8
var _moves_label: Label
var _result_label: Label

const CARD_SYMBOLS: Array[String] = [
	"QING", "LAU", "AFFECTION", "META",
	"VOID", "CHOA", "FAUNG", "HECKE"
]

const CARD_COLORS: Dictionary = {
	"QING": Color(0.3, 0.7, 0.9),
	"LAU": Color(0.9, 0.5, 0.3),
	"AFFECTION": Color(0.9, 0.3, 0.5),
	"META": Color(0.4, 0.9, 0.4),
	"VOID": Color(0.6, 0.3, 0.9),
	"CHOA": Color(0.9, 0.9, 0.3),
	"FAUNG": Color(0.3, 0.9, 0.7),
	"HECKE": Color(0.9, 0.6, 0.8),
}


func _ready() -> void:
	_init_ui("Card Match")
	_build_game_ui()
	start_game()
	_setup_board()


func _build_game_ui() -> void:
	# Moves counter
	_moves_label = Label.new()
	_moves_label.text = "Moves: 0"
	_moves_label.add_theme_font_size_override("font_size", 14)
	_moves_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(_moves_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	_content_vbox.add_child(spacer)

	# 4x4 grid
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.add_child(_grid)

	# Create 16 card buttons
	for i in range(16):
		var btn := Button.new()
		btn.text = "?"
		btn.custom_minimum_size = Vector2(80, 60)
		btn.add_theme_font_size_override("font_size", 11)
		var idx := i
		btn.pressed.connect(func(): _on_card_pressed(idx))

		# Card back style
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.25)
		style.set_corner_radius_all(6)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.5, 0.6)
		btn.add_theme_stylebox_override("normal", style)

		_grid.add_child(btn)
		_cards.append(btn)

	# Result label
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	_content_vbox.add_child(spacer2)

	_result_label = Label.new()
	_result_label.text = "Find all 8 matching pairs!"
	_result_label.add_theme_font_size_override("font_size", 13)
	_result_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(_result_label)

	# Scoring help
	var help := Label.new()
	help.text = "Score: 1000 - (moves * 30)"
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_vbox.add_child(help)


func _setup_board() -> void:
	# Create pairs of symbols
	_card_values.clear()
	_revealed.clear()
	_matched.clear()
	_first_pick = -1
	_second_pick = -1
	_checking = false
	_moves = 0
	_matches_found = 0

	for symbol in CARD_SYMBOLS:
		_card_values.append(symbol)
		_card_values.append(symbol)

	# Shuffle using territory seed for variety
	var rng := RandomNumberGenerator.new()
	rng.seed = GameManager.terrain_seed + 42
	for i in range(_card_values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := _card_values[i]
		_card_values[i] = _card_values[j]
		_card_values[j] = tmp

	# Initialize state
	for i in range(16):
		_revealed.append(false)
		_matched.append(false)
		_cards[i].text = "?"
		_cards[i].disabled = false
		_cards[i].modulate = Color.WHITE

		# Reset to back style
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.25)
		style.set_corner_radius_all(6)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.5, 0.6)
		_cards[i].add_theme_stylebox_override("normal", style)

	_moves_label.text = "Moves: 0"
	_result_label.text = "Find all 8 matching pairs!"


func _on_card_pressed(idx: int) -> void:
	if _checking:
		return
	if _matched[idx] or _revealed[idx]:
		return

	# Reveal this card
	_reveal_card(idx)

	if _first_pick < 0:
		# First card of the pair
		_first_pick = idx
	else:
		# Second card
		_second_pick = idx
		_moves += 1
		_moves_label.text = "Moves: %d" % _moves
		_checking = true

		# Check for match after brief delay
		get_tree().create_timer(0.7).timeout.connect(_check_match)


func _reveal_card(idx: int) -> void:
	_revealed[idx] = true
	var symbol: String = _card_values[idx]
	_cards[idx].text = symbol
	var card_color: Color = CARD_COLORS.get(symbol, Color(0.5, 0.5, 0.5))

	# Show revealed style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(card_color.r * 0.3, card_color.g * 0.3, card_color.b * 0.3, 0.9)
	style.set_corner_radius_all(6)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = card_color
	_cards[idx].add_theme_stylebox_override("normal", style)
	_cards[idx].add_theme_color_override("font_color", card_color)


func _hide_card(idx: int) -> void:
	_revealed[idx] = false
	_cards[idx].text = "?"

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.25)
	style.set_corner_radius_all(6)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.5, 0.6)
	_cards[idx].add_theme_stylebox_override("normal", style)
	_cards[idx].remove_theme_color_override("font_color")


func _check_match() -> void:
	if _first_pick < 0 or _second_pick < 0:
		_checking = false
		return

	if _card_values[_first_pick] == _card_values[_second_pick]:
		# Match found!
		_matched[_first_pick] = true
		_matched[_second_pick] = true
		_matches_found += 1

		# Dim matched cards
		_cards[_first_pick].modulate = Color(0.6, 0.6, 0.6, 0.7)
		_cards[_second_pick].modulate = Color(0.6, 0.6, 0.6, 0.7)
		_cards[_first_pick].disabled = true
		_cards[_second_pick].disabled = true

		_result_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		_result_label.text = "Matched: %s!" % _card_values[_first_pick]

		if _matches_found >= _total_pairs:
			_finish_game()
	else:
		# No match — hide both
		_hide_card(_first_pick)
		_hide_card(_second_pick)
		_result_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3))
		_result_label.text = "No match — try again"

	_first_pick = -1
	_second_pick = -1
	_checking = false


func _finish_game() -> void:
	# Score: 1000 - (moves * 30), minimum 100
	var final_score := maxi(100, 1000 - _moves * 30)
	_update_score(final_score)

	_result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_result_label.text = "All pairs found in %d moves! +%d points" % [_moves, final_score]

	# Disable all cards
	for btn in _cards:
		btn.disabled = true

	end_game()
