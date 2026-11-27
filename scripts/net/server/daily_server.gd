class_name DailyServer
extends RefCounted
## The game server's daily challenge (NetDaily, DailyChallenge, docs/SERVER.md §8d).
##
##   - C_DAILY_START: a signed-in wallet spends one of today's scored attempts (DailyBook). The
##     server must have read the day's seed block itself (DailySeed); if it can't, no scored
##     attempts: practice only, as on every client.
##   - C_DAILY_SUBMIT: the run's input log. Replayed here on the day's seed (DailyReplay, a slice per
##     frame so a long run never stalls the server); the replay's score is the score. A claimed
##     score the replay doesn't give is refused, and so is a log submitted sooner than it could have
##     been played. A good run goes on the board "daily:<day>" (Leaderboards: one row per wallet,
##     its best), and taking #1 sends a `daily_record` event to every signed-in player.
##   - C_DAILY_BOARD: top N, the asker's rank, attempts and streak, yesterday's winner, time left.
## Plain C_LB_SUBMIT to a daily board is refused (a verifier): only replayed runs go on it.
## The day rolls over at 00:00 UTC: a new board, new attempts; boards older than KEEP_DAYS go.

const KEEP_DAYS := 7
const PLAY_SLACK_S := 3.0  ## a run's steps/60 s may exceed the time since its start by this much

var server: Node            ## the GameServer
var book := DailyBook.new()
var path := ""
var clock := Callable()     ## () -> unix seconds; tools/net_selftest.gd moves the day with it
var _queue: Array = []      ## [{peer, wallet, day, attempt, claimed, req, replay, block}]
var _house_at := -1e9


func _init(p_server: Node, p_path: String) -> void:
	server = p_server
	path = p_path
	if path != "" and FileAccess.file_exists(path):
		book.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


func unix() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


func today() -> String:
	return DailyChallenge.day_of(unix())


## Leaderboards verifier for "daily:*": plain scores are refused.
static func refuse_plain(_board: String, _entry: Dictionary, _wallet: String) -> Dictionary:
	return {"ok": false, "check": "daily boards take only replayed runs (the daily challenge), not plain scores"}


func handle(p, msg: PackedByteArray, now: float) -> void:
	var t: int = msg[0]
	var d := NetDaily.parse(msg)
	if d.is_empty():
		server._strike(p, "bad daily message")
		return
	if not p.b_daily.take(now):
		server.stats["throttled"] += 1
		_reply(p, t, {"req": d["req"], "ok": false, "day": d["day"], "error": "slow down"})
		return
	match t:
		NetDaily.C_DAILY_START:
			_start(p, d)
		NetDaily.C_DAILY_SUBMIT:
			_submit(p, d)
		NetDaily.C_DAILY_BOARD:
			_board(p, d)


func _reply(p, t: int, body: Dictionary) -> void:
	var rt: int = {NetDaily.C_DAILY_START: NetDaily.S_DAILY_START, NetDaily.C_DAILY_SUBMIT: NetDaily.S_DAILY_RESULT,
		NetDaily.C_DAILY_BOARD: NetDaily.S_DAILY_BOARD}.get(t, NetDaily.S_DAILY_RESULT)
	server._send(p, NetProto.json_msg(rt, body))


func _start(p, d: Dictionary) -> void:
	var req: int = d["req"]
	var day: String = d["day"]
	if p.wallet == "":
		_reply(p, NetDaily.C_DAILY_START, {"req": req, "ok": false, "day": day, "error": "sign in to play for the board (guests: practice and your own best here)"})
		return
	if day != today():
		_reply(p, NetDaily.C_DAILY_START, {"req": req, "ok": false, "day": day, "error": "that is not today's challenge (today is %s, UTC)" % today()})
		return
	var seed: Dictionary = await DailySeed.find(day)
	if not server._peers.has(p.id):
		return
	if seed["state"] != "ok":
		_reply(p, NetDaily.C_DAILY_START, {"req": req, "ok": false, "day": day, "error": "the server could not read the day's seed block: — (practice only)"})
		return
	var r := book.start_attempt(day, p.wallet, unix())
	r["req"] = req
	r["day"] = day
	r["game"] = DailyChallenge.game_for(day)
	r["seed"] = {"state": "ok", "block": int(seed["block"]), "hash": String(seed["hash"])}
	if r.get("ok", false):
		server.log_line("daily %s: %s started attempt %d" % [day, p.wallet, int(r["attempt"])])
	_reply(p, NetDaily.C_DAILY_START, r)


func _submit(p, d: Dictionary) -> void:
	var req: int = d["req"]
	var fail := func(why: String) -> void:
		_reply(p, NetDaily.C_DAILY_SUBMIT, {"req": req, "ok": false, "day": d["day"], "error": why})
	if p.wallet == "":
		fail.call("sign in to submit a score")
		return
	var now := unix()
	var day := DailyChallenge.accept_day(String(d["day"]), now)
	if day == "":
		fail.call("that day's board is closed")
		return
	if int(d["score"]) < 0:
		fail.call("score must be a whole number ≥ 0")
		return
	var steps := DailyChallenge.decode_log(String(d["log"]))
	if not steps.get("ok", false):
		fail.call(String(steps.get("error", "malformed input log")))
		return
	var n_steps: int = (steps["steps"] as PackedByteArray).size()
	var why := book.can_submit(day, p.wallet, int(d["attempt"]), n_steps / 60.0 - PLAY_SLACK_S, now)
	if why != "":
		fail.call(why)
		return
	for j in _queue:
		if j["wallet"] == p.wallet:
			fail.call("your last run is still being replayed")
			return
	if _queue.size() >= NetDaily.REPLAY_QUEUE:
		fail.call("the server is busy replaying runs: try again in a moment")
		return
	var seed := DailySeed.peek(day)
	if seed["state"] != "ok":
		fail.call("the server has not read the day's seed block: —")
		return
	_queue.append({"peer": p, "wallet": p.wallet, "day": day, "attempt": int(d["attempt"]), "claimed": int(d["score"]), "req": req,
		"block": int(seed["block"]), "replay": DailyReplay.begin(DailyChallenge.game_for(day), int(seed["seed"]), String(d["log"]))})


## Every frame: a slice of the replay at the head of the queue; housekeeping once a minute.
func process(now: float) -> void:
	if not _queue.is_empty():
		var j: Dictionary = _queue[0]
		var rp: DailyReplay = j["replay"]
		if rp.run(NetDaily.REPLAY_STEPS_PER_FRAME):
			_queue.pop_front()
			_finish(j)
	if now - _house_at > 60.0:
		_house_at = now
		housekeeping()


func _finish(j: Dictionary) -> void:
	var p = j["peer"]
	var rp: DailyReplay = j["replay"]
	var alive: bool = server._peers.has(p.id)
	var body := {"req": j["req"], "day": j["day"]}
	if not rp.ok:
		server.log_line("daily %s: %s run refused (%s)" % [j["day"], j["wallet"], rp.error])
		body.merge({"ok": false, "error": "replay refused: " + rp.error})
	elif rp.score != int(j["claimed"]):
		server.log_line("daily %s: %s claimed %d, the replay scores %d: refused" % [j["day"], j["wallet"], j["claimed"], rp.score])
		body.merge({"ok": false, "score": rp.score, "error": "the replay of your input log scores %d, not %d: refused" % [rp.score, j["claimed"]]})
	else:
		book.mark_submitted(j["day"], j["wallet"], j["attempt"], rp.score)
		var check := "verified: replayed on the day's seed (block %s, %d steps)" % [ArcadeScores.grouped(int(j["block"])), rp.steps_run]
		var row := NetDaily.row(j["wallet"], rp.score, true, check, j["attempt"], unix())
		var board := DailyChallenge.board_id(j["day"])
		var res: Dictionary = server.lb.insert(board, row)
		var best: Dictionary = res.get("row", row)
		body.merge({"ok": true, "score": rp.score, "rank": int(res.get("rank", 0)), "best": int(best.get("score", rp.score)),
			"verified": true, "check": check, "kept": String(res.get("kept", ""))})
		server.log_line("daily %s: %s scored %d (attempt %d, rank %d)" % [j["day"], j["wallet"], rp.score, j["attempt"], int(res.get("rank", 0))])
		if int(res.get("rank", 0)) == 1 and not res.has("kept"):
			server._event({"k": "daily_record", "w": j["wallet"], "n": server._name_of(j["wallet"]), "board": board,
				"game": DailyChallenge.game_for(j["day"]), "score": rp.score, "verified": true}, "signed")
	if alive:
		_reply(p, NetDaily.C_DAILY_SUBMIT, body)


func _board(p, d: Dictionary) -> void:
	var day: String = d["day"]
	var board := DailyChallenge.board_id(day)
	var all: Array = server.lb.boards.get(board, [])
	var seed := DailySeed.peek(day)
	if seed["state"] == "checking" and day == today():
		DailySeed.find(day)  # the server reads it for itself; the next board says
	var me := {"signed": p.wallet != ""}
	if p.wallet != "":
		var rank := DailyChallenge.rank_of(all, p.wallet)
		me["rank"] = rank
		me["score"] = int(all[rank - 1]["score"]) if rank > 0 else -1
		me["used"] = book.used(day, p.wallet)
		var st := book.streak_of(p.wallet, today())
		me["streak"] = st["streak"]
		me["best_streak"] = st["best"]
	var yd := DailyChallenge.prev_day(day)
	var yrows: Array = server.lb.boards.get(DailyChallenge.board_id(yd), [])
	_reply(p, NetDaily.C_DAILY_BOARD, {"req": d["req"], "ok": true, "day": day, "game": DailyChallenge.game_for(day),
		"seed": {"state": seed["state"], "block": int(seed.get("block", 0)), "hash": String(seed.get("hash", ""))},
		"rows": all.slice(0, int(d["n"])).duplicate(true), "me": me,
		"yesterday": {"day": yd, "game": DailyChallenge.game_for(yd), "winner": yrows[0] if not yrows.is_empty() else null},
		"left_s": DailyChallenge.seconds_left(unix()) if day == today() else 0})


## Old days go (attempts after DailyBook.KEEP_DAYS, boards after KEEP_DAYS); the book is saved.
func housekeeping() -> void:
	var t := today()
	book.prune(t)
	var oldest := t
	for i in KEEP_DAYS:
		oldest = DailyChallenge.prev_day(oldest)
	for b in server.lb.boards.keys():
		if DailyChallenge.is_board(String(b)) and String(b).substr(DailyChallenge.BOARD_PREFIX.length()) < oldest:
			server.lb.boards.erase(b)
			server.lb.dirty = true
	save()


func save() -> void:
	if path == "" or not book.dirty:
		return
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(book.to_dict()))
	f.close()
	DirAccess.rename_absolute(tmp, path)
	book.dirty = false


func stop() -> void:
	for j in _queue:
		(j["replay"] as DailyReplay).cancel("server stopping")
	_queue.clear()
	save()
