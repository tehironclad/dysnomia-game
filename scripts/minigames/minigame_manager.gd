extends Node
## Manages pub minigame sessions: opening/closing games, score persistence,
## and mapping game table indices to game types.

signal minigame_opened(game_type: String)
signal minigame_closed
signal minigame_score(game_type: String, score: int)

const GAME_TYPES: Array[String] = ["entropy_dice", "waat_slots", "territory_trivia", "card_match"]

const GAME_SCRIPTS: Dictionary = {
	"entropy_dice": "res://scripts/minigames/entropy_dice.gd",
	"waat_slots": "res://scripts/minigames/waat_slots.gd",
	"territory_trivia": "res://scripts/minigames/territory_trivia.gd",
	"card_match": "res://scripts/minigames/card_match.gd",
}

const GAME_NAMES: Dictionary = {
	"entropy_dice": "Entropy Dice",
	"waat_slots": "WAAT Slots",
	"territory_trivia": "Territory Trivia",
	"card_match": "Card Match",
}

var _active_game: PanelContainer = null
var _active_game_type: String = ""
var _high_scores: Dictionary = {}  # game_type → int
var _hud: CanvasLayer
var _save_path: String = "user://minigame_scores.json"


func initialize(hud: CanvasLayer) -> void:
	_hud = hud
	_load_scores()


func open_game(table_index: int) -> void:
	## Open a minigame by table index (0-3 maps to game type).
	if _active_game:
		return  # Already playing

	var type_idx := clampi(table_index, 0, GAME_TYPES.size() - 1)
	var game_type: String = GAME_TYPES[type_idx]
	open_game_by_type(game_type)


func open_game_by_type(game_type: String) -> void:
	## Open a specific minigame by type name.
	if _active_game:
		close_game()

	if not GAME_SCRIPTS.has(game_type):
		print("[MinigameManager] Unknown game type: %s" % game_type)
		return

	var script_path: String = GAME_SCRIPTS[game_type]
	var script = load(script_path)
	if not script:
		print("[MinigameManager] Failed to load script: %s" % script_path)
		return

	_active_game_type = game_type

	# Create the game panel
	_active_game = PanelContainer.new()
	_active_game.set_script(script)
	_active_game.name = "ActiveMinigame"

	if _hud:
		_hud.add_child(_active_game)

	# Set high score before it renders
	var hs: int = _high_scores.get(game_type, 0)
	if _active_game.has_method("_set_high_score"):
		_active_game._set_high_score(hs)

	# Connect signals
	_active_game.game_ended.connect(_on_game_ended)
	_active_game.game_closed.connect(close_game)

	# Show mouse for minigame interaction
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	minigame_opened.emit(game_type)
	print("[MinigameManager] Opened: %s" % GAME_NAMES.get(game_type, game_type))


func close_game() -> void:
	## Close the currently active minigame.
	if _active_game:
		_active_game.queue_free()
		_active_game = null

	_active_game_type = ""
	minigame_closed.emit()


func is_game_active() -> bool:
	return _active_game != null


func get_active_game_type() -> String:
	return _active_game_type


func get_high_score(game_type: String) -> int:
	return _high_scores.get(game_type, 0)


func _on_game_ended(score: int) -> void:
	## Called when a minigame round finishes.
	var game_type := _active_game_type
	if game_type.is_empty():
		return

	# Update high score
	var current_hs: int = _high_scores.get(game_type, 0)
	if score > current_hs:
		_high_scores[game_type] = score
		_save_scores()
		print("[MinigameManager] New high score for %s: %d" % [game_type, score])

	minigame_score.emit(game_type, score)


func _load_scores() -> void:
	## Load high scores from user://minigame_scores.json.
	if not FileAccess.file_exists(_save_path):
		return

	var file := FileAccess.open(_save_path, FileAccess.READ)
	if not file:
		return

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		print("[MinigameManager] Failed to parse scores file")
		return

	var data = json.data
	if data is Dictionary:
		_high_scores = data
		print("[MinigameManager] Loaded scores: %s" % str(_high_scores))


func _save_scores() -> void:
	## Save high scores to user://minigame_scores.json.
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	if not file:
		print("[MinigameManager] Failed to save scores")
		return

	file.store_string(JSON.stringify(_high_scores, "\t"))
	file.close()
