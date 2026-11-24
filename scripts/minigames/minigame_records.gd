class_name MinigameRecords
## Personal bests and a per-QING local leaderboard for every Cantina game.
## Local save in user:// shaped so a community server can sync it later (see get_bests()).
## Bragging rights only — nothing here touches the chain or any token.
##
##   var r := MinigameRecords.submit("entropy_dice", 640, true)
##   r.personal_best / r.qing_record / r.rank
##   MinigameRecords.qing_record("waat_slots")  → {player, score, at} or {}
##   MinigameRecords.get_bests()                → broadcastable summary

class Bus extends RefCounted:
	signal records_changed(game_type: String)

const VERSION := 1
const BOARD_SIZE := 5
const LEGACY_PATH := "user://minigame_scores.json"

static var save_path: String = "user://minigame_records.json"
static var bus: Bus = Bus.new()
static var _data: Dictionary = {}
static var _loaded: bool = false


static func submit(game_type: String, score: int, won: bool = false, qing_key: String = "",
		qing_name: String = "", player: String = "", now: int = -1) -> Dictionary:
	_ensure()
	if qing_key.is_empty():
		qing_key = DysnomiaLore.qing_key()
		qing_name = DysnomiaLore.qing_label()
	if player.is_empty():
		player = DysnomiaLore.player_label()
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var personal: Dictionary = _data["personal"]
	var p: Dictionary = personal.get(game_type, {"best": 0, "plays": 0, "wins": 0, "last": 0})
	var prev_best: int = int(p.get("best", 0))
	p["plays"] = int(p.get("plays", 0)) + 1
	p["wins"] = int(p.get("wins", 0)) + (1 if won else 0)
	p["last"] = score
	var is_pb := score > prev_best
	if is_pb:
		p["best"] = score
		p["best_at"] = now
		p["best_qing"] = qing_key
	personal[game_type] = p

	var qings: Dictionary = _data["qing"]
	var q: Dictionary = qings.get(qing_key, {"name": qing_name, "boards": {}})
	if not qing_name.is_empty():
		q["name"] = qing_name
	var boards: Dictionary = q["boards"]
	var board: Array = boards.get(game_type, [])
	var prev_record: int = int(board[0]["score"]) if board.size() > 0 else 0
	var rank := -1
	if score > 0:
		var entry := {"player": player, "score": score, "at": now}
		rank = board.size()
		for i in board.size():
			if score > int(board[i]["score"]):
				rank = i
				break
		if rank < BOARD_SIZE:
			board.insert(rank, entry)
			if board.size() > BOARD_SIZE:
				board.resize(BOARD_SIZE)
		else:
			rank = -1
	boards[game_type] = board
	qings[qing_key] = q
	_save()
	bus.records_changed.emit(game_type)
	return {
		"score": score,
		"personal_best": is_pb,
		"prev_best": prev_best,
		"qing_record": rank == 0 and score > prev_record,
		"prev_record": prev_record,
		"rank": rank,
		"qing": qing_key,
	}


static func personal_best(game_type: String) -> int:
	_ensure()
	return int(_data["personal"].get(game_type, {}).get("best", 0))


static func personal_stats(game_type: String) -> Dictionary:
	_ensure()
	return _data["personal"].get(game_type, {"best": 0, "plays": 0, "wins": 0, "last": 0})


static func leaderboard(game_type: String, qing_key: String = "") -> Array:
	_ensure()
	if qing_key.is_empty():
		qing_key = DysnomiaLore.qing_key()
	return _data["qing"].get(qing_key, {}).get("boards", {}).get(game_type, [])


static func qing_record(game_type: String, qing_key: String = "") -> Dictionary:
	var b := leaderboard(game_type, qing_key)
	return b[0] if b.size() > 0 else {}


static func record_line(game_type: String, qing_key: String = "") -> String:
	var r := qing_record(game_type, qing_key)
	if r.is_empty():
		return "QING record: unclaimed"
	return "QING record %d · %s" % [int(r["score"]), str(r["player"])]


static func get_bests() -> Dictionary:
	## Everything the community layer needs to broadcast records. Plain JSON types only.
	_ensure()
	var games := {}
	for g in _data["personal"]:
		var p: Dictionary = _data["personal"][g]
		games[g] = {"personal_best": int(p.get("best", 0)), "plays": int(p.get("plays", 0)),
			"wins": int(p.get("wins", 0)), "best_at": int(p.get("best_at", 0)),
			"best_qing": str(p.get("best_qing", ""))}
	var records := {}
	for qk in _data["qing"]:
		var q: Dictionary = _data["qing"][qk]
		var per := {}
		for g in q.get("boards", {}):
			var b: Array = q["boards"][g]
			if b.size() > 0:
				per[g] = b[0].duplicate()
		if not per.is_empty():
			records[qk] = {"name": q.get("name", ""), "records": per}
	return {"version": VERSION, "player": DysnomiaLore.player_label(),
		"wallet": GameManager.lau_wallet, "games": games, "qing_records": records}


static func reset(path: String = "") -> void:
	## Tests: start from an empty store, optionally at another path.
	if not path.is_empty():
		save_path = path
	_data = {"version": VERSION, "personal": {}, "qing": {}}
	_loaded = true


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {"version": VERSION, "personal": {}, "qing": {}}
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for k in ["personal", "qing"]:
					if d.get(k) is Dictionary:
						_data[k] = d[k]
	elif FileAccess.file_exists(LEGACY_PATH):
		# Carry over the old single high-score table as personal bests
		var f := FileAccess.open(LEGACY_PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for g in d:
					_data["personal"][g] = {"best": int(d[g]), "plays": 0, "wins": 0, "last": 0}


static func _save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "\t"))
