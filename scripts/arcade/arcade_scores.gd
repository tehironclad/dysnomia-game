class_name ArcadeScores
extends RefCounted
## The high-score board of each cabinet, kept on THIS computer only (v2 records no arcade scores on
## chain: a score is self-reported by the game, so a room line would prove nothing). What the board can
## say honestly: every entry was a paid play, and it carries the credit's tx hash and block, the
## AFFECTION Transfer to the QING that ArcadePay verified in the receipt.
##
## Keyed by the QING (lower-cased) and the catalog id. Pure list logic (insert, rank) is static and
## needs no file, so tests run it directly.

const FILE := "user://arcade_scores.cfg"
const KEEP := 10
const LABEL := "High scores on this computer (not on chain) · every entry was a paid play"


## Inserts `e` ({score, wallet, tx, block, at}) into a list sorted best first (ties: the older
## entry stays ahead). Keeps `keep` entries. Returns the 1-based rank, or 0 if it didn't place.
## A tx already on the board is not added twice (returns its rank).
static func insert(list: Array, e: Dictionary, keep: int = KEEP) -> int:
	var tx := String(e.get("tx", ""))
	if tx != "":
		for i in list.size():
			if String(list[i].get("tx", "")) == tx:
				return i + 1
	var s := int(e.get("score", 0))
	var at := list.size()
	for i in list.size():
		if s > int(list[i].get("score", 0)):
			at = i
			break
	if at >= keep:
		return 0
	list.insert(at, e)
	while list.size() > keep:
		list.pop_back()
	return at + 1


## Where a score would land on the board (1-based; 0 = off the board). Doesn't change the list.
static func rank_of(list: Array, score: int, keep: int = KEEP) -> int:
	for i in list.size():
		if score > int(list[i].get("score", 0)):
			return i + 1 if i < keep else 0
	return list.size() + 1 if list.size() < keep else 0


## "0x12ab…cd34" for a board row.
static func short(addr: String) -> String:
	if addr.length() < 12:
		return addr
	return "%s…%s" % [addr.substr(0, 6), addr.right(4)]


## Board rows as text: "1  12,340  0x12ab…cd34  block 25,000,123".
static func lines(list: Array, n: int = 5) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mini(n, list.size()):
		var e: Dictionary = list[i]
		out.append("%d  %s  %s  block %s" % [i + 1, grouped(int(e.get("score", 0))).lpad(9), short(String(e.get("wallet", ""))), grouped(int(e.get("block", 0)))])
	return out


static func grouped(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


# --- The file --------------------------------------------------------------------

static func _key(qing: String, game_id: String) -> String:
	return "%s@%s" % [game_id, qing.to_lower()]


static func board(qing: String, game_id: String) -> Array:
	var c := ConfigFile.new()
	c.load(FILE)
	var list = c.get_value("boards", _key(qing, game_id), [])
	return list if list is Array else []


## Records a paid run. Returns its rank on this cabinet's board (0 = off the board).
static func record(qing: String, game_id: String, e: Dictionary) -> int:
	var c := ConfigFile.new()
	c.load(FILE)
	var list = c.get_value("boards", _key(qing, game_id), [])
	if not (list is Array):
		list = []
	var r := insert(list, e)
	if r > 0:
		c.set_value("boards", _key(qing, game_id), list)
		c.save(FILE)
	return r
