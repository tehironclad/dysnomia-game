class_name NetDaily
extends RefCounted
## The daily challenge over the game server (DailyChallenge, docs/SERVER.md §8d). Kept apart from
## NetProto's core types like NetBump and NetEvents: its own message numbers (C 55–59, S 115–119).
## Pure: the server, the client and the tests share it.
##
##   C_DAILY_START  [55] json {req, day}                          spend a scored attempt (signed in)
##   C_DAILY_SUBMIT [56] json {req, day, attempt, score, log}     the run: its input log, replayed
##   C_DAILY_BOARD  [57] json {req, day, n}                       the day's board (guests may ask)
##   S_DAILY_START  [115] json {req, ok, day, game, attempt, left, error}
##   S_DAILY_RESULT [116] json {req, ok, day, score, rank, verified, check, error}
##   S_DAILY_BOARD  [117] json {req, ok, day, game, seed {state, block, hash}, rows, me, yesterday, left_s, error}
##   (58, 59, 118, 119 are kept for this feature.)
##
## The server never takes the client's score: it replays the log on the day's seed, which it reads
## from the chain itself (DailySeed). A claimed score that the replay doesn't give is refused. Rows
## carry the wallet the sign-in proved; clients show the chain's name for it (NetNames), never a
## name from the server. The board's id is "daily:<day>" (C_LB_TOP reads it too).

const C_DAILY_START := 55
const C_DAILY_SUBMIT := 56
const C_DAILY_BOARD := 57
const S_DAILY_START := 115
const S_DAILY_RESULT := 116
const S_DAILY_BOARD := 117
const REPLIES := [S_DAILY_START, S_DAILY_RESULT, S_DAILY_BOARD]
## Listed in S_WELCOME "features"; a client sends C_DAILY_* only to such a server.
const FEATURES := ["daily"]
const SIZES := {C_DAILY_START: 96, C_DAILY_SUBMIT: DailyChallenge.MAX_LOG_CHARS + 400, C_DAILY_BOARD: 96}

# Server limits.
const SENDER_RATE := 0.5   ## C_DAILY_* from one connection: one every 2 s…
const SENDER_BURST := 5.0  ## …after a burst of 5
const REPLAY_STEPS_PER_FRAME := 1500  ## ≤ ~20 ms a frame (Entropy Drift, the slowest, ~13 µs a step)
const REPLAY_QUEUE := 16   ## replays waiting at once (more: "busy, try again")


static func size_ok(msg: PackedByteArray) -> bool:
	return not msg.is_empty() and SIZES.has(int(msg[0])) and msg.size() >= 2 and msg.size() <= int(SIZES[int(msg[0])])


static func start_msg(req: int, day: String) -> PackedByteArray:
	return NetProto.json_msg(C_DAILY_START, {"req": req, "day": day})


static func submit_msg(req: int, day: String, attempt: int, score: int, log_text: String) -> PackedByteArray:
	return NetProto.json_msg(C_DAILY_SUBMIT, {"req": req, "day": day, "attempt": attempt, "score": score, "log": log_text})


static func board_msg(req: int, day: String, n: int = DailyChallenge.BOARD_SHOW) -> PackedByteArray:
	return NetProto.json_msg(C_DAILY_BOARD, {"req": req, "day": day, "n": n})


## The server's read of a client message: {req, day, attempt, score, log, n} (typed) or {} if the
## day is malformed.
static func parse(msg: PackedByteArray) -> Dictionary:
	var b := NetProto.json_body(msg)
	var day := NetProto.str_of(b.get("day", ""))
	if not DailyChallenge.valid_day(day):
		return {}
	return {"req": NetProto.int_of(b.get("req", 0)), "day": day, "attempt": NetProto.int_of(b.get("attempt", 0)),
		"score": Leaderboards.score_of(b.get("score")), "log": NetProto.str_of(b.get("log", "")).left(DailyChallenge.MAX_LOG_CHARS + 16),
		"n": clampi(NetProto.int_of(b.get("n", DailyChallenge.BOARD_SHOW)), 1, 50)}


## A board row as the server keeps it (Leaderboards row shape plus the attempt).
static func row(wallet: String, score: int, verified: bool, check: String, attempt: int, at: int) -> Dictionary:
	return {"wallet": wallet, "name": "", "score": score, "verified": verified, "check": check, "attempt": attempt, "at": at}


## Client side: a row from the server, cleaned (the server is somebody's laptop). {} if unusable.
static func clean_row(r) -> Dictionary:
	if not (r is Dictionary):
		return {}
	var w := NetProto.clean_wallet(NetProto.str_of(r.get("wallet", "")))
	var s := Leaderboards.score_of(r.get("score"))
	if w == "" or s < 0:
		return {}
	return {"wallet": w, "score": s, "verified": NetProto.flag_of(r.get("verified", false)),
		"check": NetProto.clean_text(NetProto.str_of(r.get("check", "")), 140), "attempt": clampi(NetProto.int_of(r.get("attempt", 0)), 0, 99),
		"at": maxi(0, NetProto.int_of(r.get("at", 0)))}


## Client side: an S_DAILY_BOARD body, cleaned. Rows are re-sorted here (never trust an order).
static func clean_board(b: Dictionary) -> Dictionary:
	var out := {"ok": NetProto.flag_of(b.get("ok", false)), "error": NetProto.clean_text(NetProto.str_of(b.get("error", "")), 160)}
	var day := NetProto.str_of(b.get("day", ""))
	out["day"] = day if DailyChallenge.valid_day(day) else ""
	var g := NetProto.str_of(b.get("game", ""))
	out["game"] = g if DailyChallenge.GAMES.has(g) else ""
	var rows: Array = []
	for r in (b.get("rows", []) if b.get("rows") is Array else []).slice(0, 50):
		var c := clean_row(r)
		if not c.is_empty():
			rows.append(c)
	out["rows"] = DailyChallenge.sort_rows(rows)
	var sd = b.get("seed", {})
	if sd is Dictionary:
		var st := NetProto.str_of(sd.get("state", ""))
		var h := NetProto.str_of(sd.get("hash", "")).to_lower()
		out["seed"] = {"state": st if st in ["ok", "checking", "failed"] else "", "block": maxi(0, NetProto.int_of(sd.get("block", 0))),
			"hash": h if DailyChallenge.valid_hash(h) else ""}
	var me = b.get("me", {})
	if me is Dictionary:
		out["me"] = {"rank": maxi(0, NetProto.int_of(me.get("rank", 0))), "score": NetProto.int_of(me.get("score", -1), -1),
			"used": clampi(NetProto.int_of(me.get("used", 0)), 0, DailyChallenge.ATTEMPTS), "streak": maxi(0, NetProto.int_of(me.get("streak", 0))),
			"best_streak": maxi(0, NetProto.int_of(me.get("best_streak", 0))), "signed": NetProto.flag_of(me.get("signed", false))}
	var y = b.get("yesterday", {})
	if y is Dictionary:
		var yd := NetProto.str_of(y.get("day", ""))
		out["yesterday"] = {"day": yd if DailyChallenge.valid_day(yd) else "", "game": NetProto.str_of(y.get("game", "")) if DailyChallenge.GAMES.has(NetProto.str_of(y.get("game", ""))) else "",
			"winner": clean_row(y.get("winner"))}
	out["left_s"] = clampi(NetProto.int_of(b.get("left_s", -1), -1), -1, DailyChallenge.DAY_S)
	return out
