extends Node
## Manages Cantina minigame sessions: opening/closing games, personal bests and the
## per-QING record table (MinigameRecords), and feeding results to the QuestBoard.

signal minigame_opened(game_type: String)
signal minigame_closed
signal minigame_score(game_type: String, score: int)
signal minigame_result(game_type: String, result: Dictionary, records: Dictionary)

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
	"card_match": "Contract Match",
}

const GAME_BLURBS: Dictionary = {
	"entropy_dice": "Push-your-luck dice rolled from this QING's entropy. Beat the house line.",
	"waat_slots": "Reels of contracts, crystals, teddies and rockets. Hunt the Motzkin jackpot.",
	"territory_trivia": "Ten questions from the chain: real QINGs, live charge, contracts, the bar menu.",
	"card_match": "Timed memory pairs with Dysnomia's contracts. Learn the whole stack.",
}

var _active_game: PanelContainer = null
var _active_game_type: String = ""
var _hud: CanvasLayer


func initialize(hud: CanvasLayer) -> void:
	_hud = hud


func open_game(table_index: int) -> void:
	## Open a minigame by table index (0-3 maps to game type).
	if _active_game:
		return  # Already playing
	var type_idx := clampi(table_index, 0, GAME_TYPES.size() - 1)
	open_game_by_type(GAME_TYPES[type_idx])


func open_game_by_type(game_type: String) -> void:
	if _active_game:
		_free_active()
	if not GAME_SCRIPTS.has(game_type):
		push_warning("[MinigameManager] Unknown game type: %s" % game_type)
		return
	var script = load(GAME_SCRIPTS[game_type])
	if not script:
		push_warning("[MinigameManager] Failed to load script: %s" % GAME_SCRIPTS[game_type])
		return

	_active_game_type = game_type
	_active_game = PanelContainer.new()
	_active_game.set_script(script)
	_active_game.name = "ActiveMinigame"
	_active_game.set("_game_type", game_type)
	if _hud:
		_hud.add_child(_active_game)
	else:
		add_child(_active_game)

	if _active_game.has_method("set_records"):
		_active_game.set_records(MinigameRecords.personal_best(game_type), MinigameRecords.qing_record(game_type))
	_active_game.game_result.connect(_on_game_result)
	_active_game.game_closed.connect(close_game)
	_active_game.replay_requested.connect(func(): open_game_by_type.call_deferred(_active_game_type))

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	minigame_opened.emit(game_type)


func close_game() -> void:
	_free_active()
	_active_game_type = ""
	minigame_closed.emit()


func _free_active() -> void:
	if _active_game:
		_active_game.queue_free()
		_active_game = null


func is_game_active() -> bool:
	return _active_game != null


func get_active_game_type() -> String:
	return _active_game_type


func get_active_game() -> Control:
	return _active_game


func get_high_score(game_type: String) -> int:
	return MinigameRecords.personal_best(game_type)


func get_bests() -> Dictionary:
	## Personal bests + per-QING records, ready for the community layer to broadcast.
	return MinigameRecords.get_bests()


func _on_game_result(result: Dictionary) -> void:
	var game_type := _active_game_type
	if game_type.is_empty():
		return
	var score: int = result.get("score", 0)
	var won: bool = result.get("won", false)
	var rec := MinigameRecords.submit(game_type, score, won)

	var title_names: Array = []
	var on_title := func(t: Dictionary) -> void: title_names.append(t["name"])
	QuestBoard.bus.title_unlocked.connect(on_title)
	var completed: Array = []
	completed += QuestBoard.report("minigame_played", {"game": game_type, "score": score})
	if won:
		completed += QuestBoard.report("minigame_win", {"game": game_type, "score": score})
	completed += QuestBoard.report("minigame_score", {"game": game_type, "score": score,
		"jackpot": result.get("jackpot", false), "perfect": result.get("perfect", false)})
	QuestBoard.bus.title_unlocked.disconnect(on_title)

	minigame_score.emit(game_type, score)
	minigame_result.emit(game_type, result, rec)
	if _active_game and _active_game.has_method("show_result"):
		var info := result.duplicate()
		info["personal_best"] = rec["personal_best"]
		info["qing_record"] = rec["qing_record"]
		info["rank"] = rec["rank"]
		info["quests"] = completed
		info["title"] = ", ".join(title_names)
		_active_game.set_records(MinigameRecords.personal_best(game_type), MinigameRecords.qing_record(game_type))
		_active_game.show_result(info)
