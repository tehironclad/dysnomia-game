extends Node
## Autoload "Players": the known Dysnomia players (wallet + YUE), used to read
## who has bars at a territory. Source: res://assets/data/players.json (the
## site's snapshot, built from YUEs that received CHEON/CHOA/CHAN transfers),
## refreshed from the site accelerator when reachable, plus anyone this client
## learns about (e.g. the connected wallet).
##
## Any count or board built from this list is a FLOOR: players outside the list
## are not seen. Say so (Fact.floor_of).
##
## The site is an accelerator, not an authority: it can add players, never change the
## YUE of one already known (the bundled snapshot or this session's own CHAN read), and
## nothing here is trusted as a contract to pay: the YUE exchange keeps a desk only when
## CHAN.Yan(wallet) on chain confirms it (YueExchange.verified_yues).

signal updated(count: int)

const SNAPSHOT_PATH := "res://assets/data/players.json"

var snapshot_block := 0
var _by_wallet := {}  # wallet → {wallet, yue}


func _ready() -> void:
	_load(SNAPSHOT_PATH)


func _load(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if data is Dictionary and data.has("players"):
		snapshot_block = maxi(snapshot_block, int(data.get("block", 0)))
		for p in data["players"]:
			add_player(String(p.get("wallet", "")), String(p.get("yue", "")))
	updated.emit(count())


func add_player(wallet: String, yue: String, overwrite: bool = true) -> void:
	wallet = NetProto.clean_wallet(wallet)
	yue = NetProto.clean_wallet(yue)
	if wallet != "" and yue != "" and (overwrite or not _by_wallet.has(wallet)):
		_by_wallet[wallet] = {"wallet": wallet, "yue": yue}


func all() -> Array:
	return _by_wallet.values()


func count() -> int:
	return _by_wallet.size()


func yue_of(wallet: String) -> String:
	return _by_wallet.get(wallet.to_lower(), {}).get("yue", "")


## Merges the site's current players.json (optional accelerator).
func refresh_from_site() -> bool:
	var r: Dictionary = await Chain.site.players_snapshot()
	if not r.get("ok", false) or not (r["data"] is Dictionary) or not r["data"].has("players"):
		return false
	var before := count()
	snapshot_block = maxi(snapshot_block, int(r["data"].get("block", 0)))
	for p in r["data"]["players"]:
		if p is Dictionary:
			add_player(String(p.get("wallet", "")), String(p.get("yue", "")), false)
	if count() != before:
		updated.emit(count())
	return true
