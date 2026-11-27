class_name DailyRun
extends RefCounted
## Starting and finishing a daily-challenge run on this machine (the front door's Daily scene and
## the arcade cabinet that runs today's game share it). Reaches the Net and Session autoloads by
## path, so the pure parts stay usable without them.
##
## A run is one of:
##   - practice: unlimited, free, a seed that is not the day's (DailyChallenge.practice_seed), never
##     on any board; its best is kept on this computer.
##   - scored, on the board: a wallet the game server signed in, on a server that lists "daily".
##     The server spends the attempt (C_DAILY_START) and, at game over, replays the input log and
##     answers with the score it found (C_DAILY_SUBMIT).
##   - scored, this computer only: a guest, a wallet not signed in, or no server. The attempt is
##     counted here (DailyLocal); the AccessSteps say how to put the next one on the board.
## A scored run needs the day's seed block read from the chain (DailySeed): without it, practice only.


static func _node(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(n) if tree else null


static func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


static func today() -> String:
	return DailyChallenge.day_of(now_unix())


## The wallet the game server proved ("" when not signed in or offline).
static func signed_wallet() -> String:
	var net := _node("Net")
	return String(net.call("signed_wallet")) if net and net.has_method("signed_wallet") else ""


static func board_online() -> bool:
	var net := _node("Net")
	return net != null and net.has_method("has_daily") and bool(net.call("has_daily"))


## Who this computer counts attempts for: the signed-in wallet, else the connected one, else "guest".
static func who() -> String:
	var w := signed_wallet()
	if w != "":
		return w
	var s := _node("Session")
	var sw := String(s.get("wallet")) if s else ""
	return sw if sw != "" else "guest"


## What the card and the board show without asking anyone: {day, game, title, seed (DailySeed.peek),
## used, left, best (this computer, scored), practice_best, streak, best_streak, left_text, board_online, signed}.
static func status() -> Dictionary:
	var day := today()
	var w := who()
	var used := DailyLocal.used(day, w)
	var st := DailyLocal.streak(day)
	return {"day": day, "game": DailyChallenge.game_for(day), "title": DailyChallenge.title_of(DailyChallenge.game_for(day)),
		"seed": DailySeed.peek(day), "used": used, "left": DailyChallenge.attempts_left(used), "who": w,
		"best": DailyLocal.best(day, w, false), "practice_best": DailyLocal.best(day, w, true),
		"streak": int(st["streak"]), "best_streak": int(st["best"]), "left_text": DailyChallenge.left_text(now_unix()),
		"board_online": board_online(), "signed": signed_wallet() != ""}


## Begins a run: {ok, practice, board, day, game, seed, attempt, left, label} | {ok: false, error}.
static func begin(practice: bool) -> Dictionary:
	var day := today()
	var game := DailyChallenge.game_for(day)
	if practice:
		var n := DailyLocal.next_practice(day)
		return {"ok": true, "practice": true, "board": false, "day": day, "game": game, "seed": DailyChallenge.practice_seed(day, n),
			"attempt": 0, "label": "PRACTICE · a different seed each time · not on any board"}
	var sd: Dictionary = await DailySeed.find(day)
	if sd["state"] != "ok":
		return {"ok": false, "error": "The day's seed block could not be read: — (practice only)."}
	var w := signed_wallet()
	if w != "" and board_online():
		var r: Dictionary = await _node("Net").call("daily_start", day)
		if not r.get("ok", false):
			return {"ok": false, "error": "The server didn't start a scored run: %s" % NetProto.clean_text(NetProto.str_of(r.get("error", "—")), 160)}
		var att := NetProto.int_of(r.get("attempt", 0))
		DailyLocal.set_used(day, w, att)
		return {"ok": true, "practice": false, "board": true, "day": day, "game": game, "seed": int(sd["seed"]), "attempt": att,
			"left": NetProto.int_of(r.get("left", 0)), "block": int(sd["block"]),
			"label": "SCORED · attempt %d of %d · seed block #%s · for the board (the server replays it)" % [att, DailyChallenge.ATTEMPTS, ArcadeScores.grouped(int(sd["block"]))]}
	var lw := who()
	var lr := DailyLocal.start_attempt(day, lw)
	if not lr.get("ok", false):
		return {"ok": false, "error": String(lr.get("error", "—"))}
	return {"ok": true, "practice": false, "board": false, "day": day, "game": game, "seed": int(sd["seed"]), "attempt": int(lr["attempt"]),
		"left": int(lr["left"]), "block": int(sd["block"]),
		"label": "SCORED · attempt %d of %d · seed block #%s · this computer only (sign in to the game server for the board)" % [int(lr["attempt"]), DailyChallenge.ATTEMPTS, ArcadeScores.grouped(int(sd["block"]))]}


## Ends a run (after the game's game_over): records it here and, for a board run, sends the log
## for the server to replay. {score, local_best, submitted, ok, rank, check, error, text}.
static func finish(run: Dictionary, game: ArcadeGame) -> Dictionary:
	var score := game.score
	var day := String(run.get("day", today()))
	var practice := bool(run.get("practice", true))
	var w := who()
	var out := {"score": score, "submitted": false, "ok": true, "rank": 0, "check": "", "error": ""}
	out["local_best"] = DailyLocal.record(day, w, {"score": score, "practice": practice, "at": now_unix(), "attempt": int(run.get("attempt", 0)),
		"block": int(run.get("block", 0))})
	if practice:
		out["text"] = "PRACTICE · %s%s · not on any board" % [ArcadeScores.grouped(score), " · your best practice today" if out["local_best"] else ""]
		return out
	if not bool(run.get("board", false)):
		out["text"] = "SCORED %s · attempt %d · this computer only%s" % [ArcadeScores.grouped(score), int(run.get("attempt", 0)), " · your best today" if out["local_best"] else ""]
		return out
	var log_text := DailyChallenge.encode_log(game.rec_start, game.rec_steps)
	if log_text.length() > DailyChallenge.MAX_LOG_CHARS:
		out["ok"] = false
		out["error"] = "this run's input log is too long for the server to replay"
		out["text"] = "SCORED %s · not sent: %s" % [ArcadeScores.grouped(score), out["error"]]
		return out
	var r: Dictionary = await _node("Net").call("daily_submit", day, int(run.get("attempt", 0)), score, log_text)
	out["submitted"] = true
	out["ok"] = bool(r.get("ok", false))
	if out["ok"]:
		out["rank"] = NetProto.int_of(r.get("rank", 0))
		out["check"] = NetProto.clean_text(NetProto.str_of(r.get("check", "")), 140)
		var kept := NetProto.str_of(r.get("kept", "")) != ""
		out["text"] = "SCORED %s ✓ replayed by the server · %s" % [ArcadeScores.grouped(score),
			("your best stands (#%d)" % out["rank"]) if kept else ("#%d today" % out["rank"]) if out["rank"] > 0 else "on the board"]
	else:
		out["error"] = NetProto.clean_text(NetProto.str_of(r.get("error", "—")), 160)
		out["text"] = "SCORED %s · the board refused it: %s" % [ArcadeScores.grouped(score), out["error"]]
	return out


## The extra AccessSteps toward the board: reach the game server, sign in to it.
static func access_extra() -> Array:
	var net := _node("Net")
	var online: bool = net != null and bool(net.call("is_online"))
	var daily := board_online()
	var signed := signed_wallet() != ""
	var out: Array = []
	out.append({"id": "net", "title": "Reach the game server", "explain": "The daily board lives on the game server (online play). Without one, scored runs count on this computer only.",
		"status": "done" if daily else ("todo" if online else "unknown"),
		"detail": "Online, with the daily board." if daily else ("This server has no daily board (an older version)." if online else "— (no game server answered: single-player)"),
		"action": "" if online else "net_retry", "action_label": "" if online else "Try again"})
	out.append({"id": "signin", "title": "Sign in to the game server (free)", "explain": "One free signature proves your wallet to the server; nothing is sent on chain. The board shows your LAU's name from the chain.",
		"status": "done" if signed else ("todo" if online else "unknown"),
		"detail": ("Signed in as %s." % NetProto.short_wallet(signed_wallet())) if signed else ("Not signed in." if online else "— (needs the server)"),
		"action": "" if signed or not online else "net_sign_in", "action_label": "Sign in"})
	return out


## Handlers for access_extra's actions.
static func access_handlers() -> Dictionary:
	var net := _node("Net")
	if net == null:
		return {}
	return {"net_sign_in": func(): net.call("sign_in"), "net_retry": func(): net.call("restart")}
