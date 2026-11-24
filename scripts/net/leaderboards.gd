class_name Leaderboards
extends RefCounted
## The game server's leaderboards (docs/SERVER.md). Boards live in one JSON
## file under the server's user:// folder. Every row was submitted by a wallet
## that proved itself with a signature; nothing is ever made up here: an empty
## board is an empty list, and a row says how it was checked.
##
## Verification is pluggable: a verifier per board-id pattern,
##   func(board: String, entry: Dictionary, wallet: String) -> {ok, verified, check}
## (may be a coroutine). ok=false refuses the row. Boards with no verifier
## take the row as "unverified": the game reported the score itself.
##
## Board ids: lowercase [a-z0-9:_./-], ≤ 96 chars, e.g. "0x2b78…96de/fair:striker".

const KEEP := 500          # rows kept per board (one per wallet, best score)
const MAX_BOARDS := 500
const UNVERIFIED := "unverified: the game reported this score itself (no replay)"

var path := ""
var boards := {}           # id → [row] best first
var dirty := false
var _verifiers: Array = [] # [[pattern (String.match glob), Callable]]


func _init(p_path: String = "") -> void:
	path = p_path
	if path != "":
		load_file()


func add_verifier(pattern: String, verifier: Callable) -> void:
	_verifiers.append([pattern, verifier])


static func clean_board(s: String) -> String:
	s = s.strip_edges().to_lower()
	if s.is_empty() or s.length() > 96:
		return ""
	for ch in s:
		if not (ch >= "a" and ch <= "z") and not (ch >= "0" and ch <= "9") and not (ch in [":", "_", ".", "/", "-"]):
			return ""
	return s


## A score from JSON: a non-negative integer (int, integral float or digit string), else -1.
static func score_of(v) -> int:
	if v is int:
		return v if v >= 0 else -1
	if v is float:
		return int(v) if v >= 0.0 and v == floorf(v) and v < 9.0e15 else -1
	if v is String and v.length() <= 18 and v.is_valid_int() and not v.begins_with("-"):
		return v.to_int()
	return -1


## {ok, rank, row} or {ok: false, error}.
func submit(board: String, entry: Dictionary, wallet: String, name: String) -> Dictionary:
	board = clean_board(board)
	if board == "":
		return {"ok": false, "error": "bad board id"}
	if NetProto.clean_wallet(wallet) == "":
		return {"ok": false, "error": "sign in to submit a score"}
	var score := score_of(entry.get("score"))
	if score < 0:
		return {"ok": false, "error": "score must be a whole number ≥ 0"}
	if not boards.has(board) and boards.size() >= MAX_BOARDS:
		return {"ok": false, "error": "too many boards"}
	var verdict: Dictionary = {"ok": true, "verified": false, "check": UNVERIFIED}
	for v in _verifiers:
		if board.match(String(v[0])):
			verdict = await (v[1] as Callable).call(board, entry, wallet)
			break
	if not bool(verdict.get("ok", false)):
		return {"ok": false, "error": String(verdict.get("check", "refused"))}
	var row := {
		"wallet": wallet, "name": NetProto.clean_text(name, NetProto.NAME_MAX_CHARS), "score": score,
		"verified": bool(verdict.get("verified", false)), "check": String(verdict.get("check", "")),
		"at": int(Time.get_unix_time_from_system()),
	}
	for k in ["tx", "block", "game"]:
		if entry.has(k):
			row[k] = NetProto.clean_text(str(entry[k]), 80)
	return insert(board, row)


## Keeps the wallet's best row (a tie goes to a verified one). {ok, rank, row}.
func insert(board: String, row: Dictionary) -> Dictionary:
	var list: Array = boards.get(board, [])
	for i in list.size():
		var old: Dictionary = list[i]
		if old["wallet"] == row["wallet"]:
			var better: bool = int(row["score"]) > int(old["score"]) or (int(row["score"]) == int(old["score"]) and row["verified"] and not old["verified"])
			if not better:
				return {"ok": true, "rank": i + 1, "row": old, "kept": "your best stands"}
			list.remove_at(i)
			break
	var at := list.size()
	for i in list.size():
		if int(row["score"]) > int(list[i]["score"]):
			at = i
			break
	if at >= KEEP:
		return {"ok": true, "rank": 0, "row": row}
	list.insert(at, row)
	while list.size() > KEEP:
		list.pop_back()
	boards[board] = list
	dirty = true
	return {"ok": true, "rank": at + 1, "row": row}


## The best `n` rows (copies); [] for an unknown board. Never invents rows.
func top(board: String, n: int = 10) -> Array:
	board = clean_board(board)
	var list: Array = boards.get(board, [])
	return list.slice(0, clampi(n, 1, 100)).duplicate(true)


func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if j is Dictionary and j.get("boards") is Dictionary:
		for b in j["boards"]:
			if clean_board(String(b)) != "" and j["boards"][b] is Array:
				var rows: Array = []
				for r in j["boards"][b]:
					if r is Dictionary and r.has("wallet") and r.has("score"):
						r["score"] = int(r["score"])  # JSON numbers come back as floats
						rows.append(r)
				boards[String(b)] = rows


func save() -> void:
	if path == "" or not dirty:
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": 1, "boards": boards}))
	f.close()
	DirAccess.rename_absolute(tmp, path)
	dirty = false
