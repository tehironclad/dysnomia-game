extends SceneTree
## Headless tests for the Cantina games and the daily quest loop:
##   godot --headless --path . -s tools/test_minigames.gd
## Covers quest determinism, UTC reset + streak logic, titles, trivia generation (no
## repeats, answers correct), dice/slots/card payout math, records, and smoke-runs every
## minigame UI plus the to-do panel. Saves go to user://test_* files, never the real ones.
## Cases live in tools/test_minigames_cases.gd, loaded at runtime (autoloads must exist first).


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var cases = load("res://tools/test_minigames_cases.gd").new()
	var fails: int = await cases.run(self)
	quit(1 if fails > 0 else 0)
