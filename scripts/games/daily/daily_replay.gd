class_name DailyReplay
extends RefCounted
## Scores a daily-challenge run by replaying it: the day's game, started from the day's seed,
## fed the run's input log one 60 Hz step at a time (ArcadeGame records it while the run is live).
## The score is what the game says at its game over, or when the log ends (the player quit: a
## run that ends early keeps the score it had). Nothing is taken from the client but the log.
##
## Refused: an unknown game, a malformed log, a log that runs on past the game's end (the game
## couldn't have taken it), more than DailyChallenge.MAX_STEPS steps.
##
## The server replays in slices (`run(n)` per frame) so a long run never stalls it; tests and
## the client call `replay()` in one go. The games are Node2D scripts: the replay keeps one out
## of the tree and frees it when done.

var game_id := ""
var score := -1
var steps_run := 0
var done := false
var ok := false
var error := ""
var _g: ArcadeGame
var _steps := PackedByteArray()


## Starts a replay. `log_text` is DailyChallenge.encode_log's text.
static func begin(p_game: String, seed: int, log_text: String) -> DailyReplay:
	var r := DailyReplay.new()
	r.game_id = p_game
	var path := DailyChallenge.script_of(p_game)
	if path == "" or not DailyChallenge.GAMES.has(p_game):
		r._fail("unknown game '%s'" % p_game)
		return r
	var dec := DailyChallenge.decode_log(log_text)
	if not dec.get("ok", false):
		r._fail(String(dec.get("error", "malformed input log")))
		return r
	var script = load(path)
	if script == null:
		r._fail("game script missing")
		return r
	r._g = script.new()
	r._g.scripted_input = int(dec["start"])
	r._g.start(seed)
	r._steps = dec["steps"]
	return r


## Runs up to `n` more steps. Returns true when the replay has finished (see ok / score / error).
func run(n: int = 1 << 30) -> bool:
	if done:
		return true
	var end := mini(_steps.size(), steps_run + n)
	while steps_run < end:
		if not _g.playing:
			_fail("the input log runs on after the game ended (step %d of %d)" % [steps_run, _steps.size()])
			return true
		_g.scripted_input = _steps[steps_run]
		_g.step(ArcadeGame.DT)
		steps_run += 1
	if steps_run < _steps.size():
		return false
	if _g.playing:
		_g.end_game()  # the player quit here: the score so far stands
	score = _g.score
	ok = true
	_finish()
	return true


## Stops early (the server gave up on it) and frees the game.
func cancel(why: String = "cancelled") -> void:
	if not done:
		_fail(why)


func _fail(why: String) -> void:
	error = why
	ok = false
	score = -1
	_finish()


func _finish() -> void:
	done = true
	if _g != null:
		_g.free()
		_g = null
	_steps = PackedByteArray()


## One go: {ok, score, steps} or {ok: false, error}.
static func replay(p_game: String, seed: int, log_text: String) -> Dictionary:
	var r := begin(p_game, seed, log_text)
	r.run()
	if r.ok:
		return {"ok": true, "score": r.score, "steps": r.steps_run}
	return {"ok": false, "error": r.error}
