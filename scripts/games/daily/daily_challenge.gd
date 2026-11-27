class_name DailyChallenge
extends RefCounted
## The daily challenge (LEARNINGS §23): one arcade game a UTC day, the same run for everyone.
##
##   - The day is the UTC date "YYYY-MM-DD"; it resets at 00:00 UTC.
##   - The game: the original arcade games (ArcadeCatalog.GAMES, never a cartridge) in a fixed
##     rotation, GAMES[days since 1970-01-01 % 6]. Anyone can recompute it from the date.
##   - The seed: from the chain, never invented. The first PulseChain block whose timestamp is
##     ≥ 00:00 UTC that day (found by a search on block timestamps, `Search`), and
##     seed = the first 12 hex digits of SHA-256("daily:<day>:<block hash>"). Until the block is
##     read the screen says "checking…"; if it can't be read, "—" and practice only.
##   - Free: no Ⓐ ticket. ATTEMPTS scored runs a day (the server counts them for signed-in
##     players; this computer counts them for guests and offline), best counts; practice is
##     unlimited and never on the board (its seed is not the day's).
##   - The board is the game server's `daily:<day>`, scored by replaying the run's input log
##     (DailyReplay) on the day's seed. Pure: the client, the server and the tests share this.

const GAMES := ["entropy_drift", "void_lanes", "bar_raiser", "motzkin_sieve", "qing_orbit", "yue_courier"]
const ATTEMPTS := 3
const DAY_S := 86400
const BOARD_PREFIX := "daily:"
const BOARD_SHOW := 10
## A run that ends this soon after midnight still counts for the day it started on.
const GRACE_S := 600
## The longest scored run the server replays: 20 minutes at 60 steps a second.
const MAX_STEPS := 72000
## The input log's text, at most (fits NetProto.MAX_MESSAGE with the rest of the message).
const MAX_LOG_CHARS := 12000
const SOURCE := "seed = SHA-256(\"daily:<day>:<hash>\") of the first PulseChain block at or after 00:00 UTC"


# --- Days ------------------------------------------------------------------------

## "2026-11-27" for a unix second (UTC).
static func day_of(unix: int) -> String:
	return Time.get_date_string_from_unix_time(unix)


## Unix second of 00:00 UTC on `day` ("YYYY-MM-DD"); -1 if malformed.
static func day_start(day: String) -> int:
	if not valid_day(day):
		return -1
	return Time.get_unix_time_from_datetime_string(day + "T00:00:00")


## Unix second of 00:00 UTC on the day holding `unix`.
static func midnight_of(unix: int) -> int:
	return unix - posmod(unix, DAY_S)


static func valid_day(day: String) -> bool:
	if day.length() != 10 or day[4] != "-" or day[7] != "-":
		return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9]:
		if not (day[i] >= "0" and day[i] <= "9"):
			return false
	var y := day.substr(0, 4).to_int()
	var m := day.substr(5, 2).to_int()
	var d := day.substr(8, 2).to_int()
	if y < 1970 or m < 1 or m > 12 or d < 1:
		return false
	var leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
	var dim: int = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
	return d <= dim  # a real date (no 2026-02-31)


## The day before `day`.
static func prev_day(day: String) -> String:
	var t := day_start(day)
	return day_of(t - DAY_S) if t >= 0 else ""


static func next_day(day: String) -> String:
	var t := day_start(day)
	return day_of(t + DAY_S) if t >= 0 else ""


## Seconds until the next 00:00 UTC.
static func seconds_left(unix: int) -> int:
	return DAY_S - posmod(unix, DAY_S)


## "5 h 12 min left" / "12 min left" / "under a minute left".
static func left_text(unix: int) -> String:
	var s := seconds_left(unix)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%d h %02d min left" % [h, m]
	if m > 0:
		return "%d min left" % m
	return "under a minute left"


## Days since 1970-01-01 for `day` (UTC); -1 if malformed.
static func day_number(day: String) -> int:
	var t := day_start(day)
	return t / DAY_S if t >= 0 else -1


## Which day a run belongs to, given the day it says it started on and the time now: today, or
## yesterday within GRACE_S after midnight. "" when neither (a stale or a future day).
static func accept_day(claimed: String, now_unix: int) -> String:
	var today := day_of(now_unix)
	if claimed == today:
		return today
	if claimed == prev_day(today) and seconds_since_midnight(now_unix) <= GRACE_S:
		return claimed
	return ""


static func seconds_since_midnight(unix: int) -> int:
	return posmod(unix, DAY_S)


# --- The game and the seed --------------------------------------------------------

## The day's game id (one of GAMES).
static func game_for(day: String) -> String:
	var n := day_number(day)
	return GAMES[posmod(n, GAMES.size())] if n >= 0 else ""


static func title_of(game_id: String) -> String:
	for g in ArcadeCatalog.GAMES:
		if g["id"] == game_id:
			return String(g["title"])
	return game_id.replace("_", " ").capitalize()


static func script_of(game_id: String) -> String:
	for g in ArcadeCatalog.GAMES:
		if g["id"] == game_id:
			return String(g["script"])
	return ""


## The day's seed from its first block's hash ("0x" + 64 hex). -1 for a malformed hash: no seed.
static func seed_from_hash(day: String, hash_hex: String) -> int:
	var h := hash_hex.strip_edges().to_lower()
	if not valid_hash(h) or not valid_day(day):
		return -1
	return ("daily:%s:%s" % [day, h]).sha256_text().substr(0, 12).hex_to_int()


static func valid_hash(h: String) -> bool:
	return h.length() == 66 and h.begins_with("0x") and NetProto.is_hex(h.substr(2))


## A practice run's seed: not the day's (practice can't rehearse the scored run), different
## each time. From the day and a counter, so it needs no chain read.
static func practice_seed(day: String, n: int) -> int:
	return ("practice:%s:%d" % [day, n]).sha256_text().substr(0, 12).hex_to_int()


static func board_id(day: String) -> String:
	return BOARD_PREFIX + day


static func is_board(board: String) -> bool:
	return board.begins_with(BOARD_PREFIX) and valid_day(board.substr(BOARD_PREFIX.length()))


## Where the seed came from, for every screen that shows it.
static func seed_text(state: Dictionary) -> String:
	match String(state.get("state", "")):
		"ok":
			var h := String(state.get("hash", ""))
			return "seed: block #%s · %s…%s (first block ≥ 00:00 UTC)" % [ArcadeScores.grouped(int(state.get("block", 0))), h.substr(0, 8), h.right(4)]
		"failed":
			return "seed: — (the day's first block could not be read; practice only)"
	return "seed: checking… (the day's first block)"


# --- Attempts, streaks, the board -------------------------------------------------

static func attempts_left(used: int) -> int:
	return maxi(0, ATTEMPTS - used)


## A streak of days played: `last` the last day counted, `streak` its length. Playing on `today`
## keeps it (same day), adds one (the next day) or starts again at 1. Returns [last, streak].
static func streak_after(last: String, streak: int, today: String) -> Array:
	if last == today:
		return [today, maxi(1, streak)]
	if last != "" and next_day(last) == today:
		return [today, streak + 1]
	return [today, 1]


## The streak as it stands on `today`: 0 when the last day played is older than yesterday.
static func streak_now(last: String, streak: int, today: String) -> int:
	if last == today or (last != "" and next_day(last) == today):
		return streak
	return 0


## Rows best first: higher score, then the earlier time (`at`), then the wallet (a stable order).
static func sort_rows(rows: Array) -> Array:
	var out := rows.duplicate()
	out.sort_custom(func(a, b):
		var sa := int(a.get("score", 0))
		var sb := int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		var ta := int(a.get("at", 0))
		var tb := int(b.get("at", 0))
		if ta != tb:
			return ta < tb
		return String(a.get("wallet", "")) < String(b.get("wallet", "")))
	return out


## 1-based rank of `wallet` in sorted rows; 0 when it isn't there.
static func rank_of(rows: Array, wallet: String) -> int:
	for i in rows.size():
		if String(rows[i].get("wallet", "")) == wallet and wallet != "":
			return i + 1
	return 0


# --- The input log ----------------------------------------------------------------
# One byte of ArcadeGame IN_* bits per 60 Hz step (ArcadeGame records them while a run is live),
# plus the bits held when the run started. On the wire: run-length pairs [bits][varint count],
# base64, prefixed "v1:<start bits>:". About 2 bytes per change of input.

const LOG_VERSION := "v1"


static func encode_log(start_held: int, steps: PackedByteArray) -> String:
	var out := PackedByteArray()
	var i := 0
	while i < steps.size():
		var b := steps[i]
		var n := 1
		while i + n < steps.size() and steps[i + n] == b:
			n += 1
		out.append(b & 0x1F)
		var v := n
		while v >= 0x80:
			out.append((v & 0x7F) | 0x80)
			v >>= 7
		out.append(v)
		i += n
	return "%s:%d:%s" % [LOG_VERSION, start_held & 0x1F, Marshalls.raw_to_base64(out) if not out.is_empty() else ""]


## {ok, start, steps: PackedByteArray} or {ok: false, error}. Refuses anything malformed or longer
## than `max_steps` (it never allocates more than that).
static func decode_log(text: String, max_steps: int = MAX_STEPS) -> Dictionary:
	if text.length() > MAX_LOG_CHARS + 16:
		return {"ok": false, "error": "input log too long"}
	var parts := text.split(":")
	if parts.size() != 3 or parts[0] != LOG_VERSION or not parts[1].is_valid_int():
		return {"ok": false, "error": "malformed input log"}
	var start := parts[1].to_int()
	if start < 0 or start > 0x1F:
		return {"ok": false, "error": "malformed input log"}
	var raw := PackedByteArray()
	if parts[2] != "":
		for ch in parts[2]:
			if not (ch.is_valid_identifier() or (ch >= "0" and ch <= "9") or ch in ["+", "/", "="]):
				return {"ok": false, "error": "malformed input log"}
		raw = Marshalls.base64_to_raw(parts[2])
		if raw.is_empty():
			return {"ok": false, "error": "malformed input log"}
	var steps := PackedByteArray()
	var i := 0
	while i < raw.size():
		var b := raw[i]
		if b > 0x1F:
			return {"ok": false, "error": "malformed input log"}
		i += 1
		var n := 0
		var shift := 0
		while true:
			if i >= raw.size() or shift > 21:
				return {"ok": false, "error": "malformed input log"}
			var c := raw[i]
			i += 1
			n |= (c & 0x7F) << shift
			shift += 7
			if c < 0x80:
				break
		if n <= 0:
			return {"ok": false, "error": "malformed input log"}
		if steps.size() + n > max_steps:
			return {"ok": false, "error": "run longer than %d steps" % max_steps}
		var at := steps.size()
		steps.resize(at + n)
		for k in n:
			steps[at + k] = b
	return {"ok": true, "start": start, "steps": steps}


# --- The seed's block: a search on block timestamps -------------------------------

## Finds the first block with timestamp ≥ target, given the head. Pure: the caller reads the
## block `next()` asks for and `feed()`s its timestamp; tests drive it with made-up timestamps.
## Interpolation steps (blocks are ~10 s apart) alternate with halving, so a gap in block times
## can't make it crawl. Invariant: ts(lo) < target ≤ ts(hi).
class Search:
	extends RefCounted
	var target := 0
	var lo := -1          ## a block known to be before the target (-1: none yet)
	var lo_ts := 0
	var hi := -1          ## a block known to be at or after it
	var hi_ts := 0
	var reads := 0
	var done := false
	var found := -1       ## the answer once done (-1: there is no such block yet)
	var error := ""
	var _bisect := false
	const MAX_READS := 80

	func _init(p_target: int, head_number: int, head_ts: int) -> void:
		target = p_target
		if head_ts < target:
			done = true
			error = "no block at or after 00:00 UTC yet"
			return
		hi = head_number
		hi_ts = head_ts
		if head_number == 0:
			done = true
			found = 0

	## The block number to read next, or -1 when done.
	func next() -> int:
		if done:
			return -1
		if lo < 0:
			# First guess: back from the head at 10 s a block, a little past the target.
			var back := (hi_ts - target) / 10 + 2
			return clampi(hi - back, 0, hi - 1)
		if hi - lo <= 1:
			return -1
		var n: int
		if _bisect or hi_ts <= lo_ts:
			n = lo + (hi - lo) / 2
		else:
			n = lo + int(float(target - lo_ts) * float(hi - lo) / float(hi_ts - lo_ts))
		_bisect = not _bisect
		return clampi(n, lo + 1, hi - 1)

	func feed(n: int, ts: int) -> void:
		if done:
			return
		reads += 1
		if ts < target:
			if n > lo:
				lo = n
				lo_ts = ts
		else:
			if n < hi:
				hi = n
				hi_ts = ts
			if n == 0:
				lo = -1
				done = true
				found = 0
				return
		if lo < 0 and ts >= target:
			return  # still above the target: next() guesses further back from the new hi
		if lo >= 0 and hi - lo <= 1:
			done = true
			found = hi
		elif reads >= MAX_READS:
			done = true
			error = "the search did not converge"

	## A read failed: the search stops with nothing (the caller shows "—").
	func fail(why: String) -> void:
		done = true
		found = -1
		error = why
