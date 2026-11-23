extends Node
## Autoload "Registry": every territory (QING) on chain.
##
## Sources, merged so the result is never worse than the shipped snapshot:
## 1. res://assets/data/territories.json: shipped snapshot (tools/update_snapshot.gd);
## 2. user://territories.json: what this machine caught up to last time;
## 3. live catch-up: MAP NewQing logs after the cursor, then one Multicall pass
##    for each new territory's fields and HECKE.Compliment words.
##
## A record: {address, asset, waat (decimal), block, name, symbol, entropy
## (decimal), gwat, cover_charge, bouncer_divisor, creator, lat, lon,
## lon_word, lat_word}. NewQing's "Integrative" field is the asset token
## (it equals QING.Asset()). Raw words are 64-char hex (no 0x); lat/lon are
## display degrees only.

## New territories found by a catch-up (NewQing logs), each with its block.
signal founded(records: Array)
signal updated(count: int)
signal catch_up_finished(ok: bool, added: int)

const SNAPSHOT_PATH := "res://assets/data/territories.json"
const CACHE_PATH := "user://territories.json"

var cursor_block := 0  ## every NewQing up to this block is included
var _by_address := {}
var _list: Array = []  ## in founding order
var catching_up := false
var last_error := ""


func _ready() -> void:
	load_local()


func count() -> int:
	return _list.size()


func all() -> Array:
	return _list


func get_territory(address: String) -> Dictionary:
	return _by_address.get(address.to_lower(), {})


func has_territory(address: String) -> bool:
	return _by_address.has(address.to_lower())


## Case-insensitive search by name, symbol or address prefix.
func search(text: String, limit: int = 50) -> Array:
	text = text.strip_edges().to_lower()
	var out: Array = []
	for q in _list:
		if text.is_empty() or String(q["name"]).to_lower().contains(text) \
				or String(q["symbol"]).to_lower().contains(text) or String(q["address"]).begins_with(text):
			out.append(q)
			if out.size() >= limit:
				break
	return out


# --- Local data -------------------------------------------------------------------

func load_local() -> void:
	_by_address.clear()
	_list.clear()
	cursor_block = 0
	_merge_file(SNAPSHOT_PATH)
	_merge_file(CACHE_PATH)
	updated.emit(_list.size())


func _merge_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not data.has("territories"):
		push_warning("[Registry] unreadable %s" % path)
		return
	for q in data["territories"]:
		_upsert(q)
	cursor_block = maxi(cursor_block, int(data.get("snapshot_block", 0)))
	_sort()


func _upsert(q: Dictionary) -> void:
	var a := String(q.get("address", "")).to_lower()
	if a.length() != 42:
		return
	q["address"] = a
	if _by_address.has(a):
		# Keep known fields; fill gaps (e.g. raw words) from the newer record.
		var cur: Dictionary = _by_address[a]
		for k in q:
			if not cur.has(k) or str(cur[k]) == "":
				cur[k] = q[k]
	else:
		_by_address[a] = q
		_list.append(q)


func _sort() -> void:
	_list.sort_custom(func(x, y): return int(x["block"]) < int(y["block"]) \
		or (int(x["block"]) == int(y["block"]) and String(x["address"]) < String(y["address"])))


func save_cache(path: String = CACHE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[Registry] cannot write %s" % path)
		return
	f.store_string(JSON.stringify({
		"source": "chain (MAP NewQing logs + Multicall reads)",
		"snapshot_block": cursor_block,
		"count": _list.size(),
		"territories": _list,
	}))


# --- Live catch-up ------------------------------------------------------------------

## Reads NewQing logs after the cursor, fills fields for new territories and
## raw Compliment words for any record missing them. Safe to call repeatedly.
func catch_up() -> bool:
	if catching_up:
		await catch_up_finished
		return last_error.is_empty()
	catching_up = true
	last_error = ""
	var added := 0
	var head := await Chain.refresh_head()
	if head < 0:
		return _finish(false, 0, "chain head unavailable")
	if head > cursor_block:
		var scan: Dictionary = await Chain.logs.scan(Contracts.MAP, [Contracts.TOPIC_NEW_QING], cursor_block + 1, head)
		var fresh: Array = []
		for log in scan["logs"]:
			var rec := parse_new_qing(log)
			if not rec.is_empty() and not has_territory(rec["address"]):
				fresh.append(rec)
		if not fresh.is_empty():
			await _read_fields(fresh)
			for rec in fresh:
				_upsert(rec)
			added = fresh.size()
			founded.emit(fresh)
		cursor_block = scan["scanned_to"]
		if not scan["ok"]:
			_sort()
			save_cache()
			return _finish(false, added, "log scan stopped at block %d" % cursor_block)
	await _resolve_missing_words()
	_sort()
	save_cache()
	return _finish(true, added, "")


func _finish(ok: bool, added: int, err: String) -> bool:
	catching_up = false
	last_error = err
	updated.emit(_list.size())
	catch_up_finished.emit(ok, added)
	return ok


## NewQing(address QING, address Integrative, uint256 Waat): all in data.
static func parse_new_qing(log: Dictionary) -> Dictionary:
	var data := Abi.strip0x(String(log.get("data", "")))
	if data.length() < 192:
		return {}
	var v := Abi.decode(["address", "address", "uint256"], data)
	return {
		"address": v[0], "asset": v[1],
		"waat": BigInt.to_decimal(BigInt.from_hex(v[2])),
		"block": String(log.get("blockNumber", "0x0")).hex_to_int(),
		"tx_hash": String(log.get("transactionHash", "")),
	}


func _read_fields(recs: Array) -> void:
	var calls: Array = []
	for r in recs:
		var a: String = r["address"]
		calls.append(Multicall.make_call(a, "name()"))
		calls.append(Multicall.make_call(a, "symbol()"))
		calls.append(Multicall.make_call(a, "Entropy()"))
		calls.append(Multicall.make_call(a, "Asset()"))
		calls.append(Multicall.make_call(a, "GWAT()"))
		calls.append(Multicall.make_call(a, "CoverCharge()"))
		calls.append(Multicall.make_call(a, "BouncerDivisor()"))
	var res: Array = await Chain.multicall.run(calls)
	for i in recs.size():
		var r: Dictionary = recs[i]
		var o := i * 7
		r["name"] = _first(Multicall.value(res[o], ["string"]), "")
		r["symbol"] = _first(Multicall.value(res[o + 1], ["string"]), "")
		r["entropy"] = _dec(Multicall.value(res[o + 2], ["uint256"]))
		r["asset"] = _first(Multicall.value(res[o + 3], ["address"]), r.get("asset", ""))
		r["gwat"] = _first(Multicall.value(res[o + 4], ["bool"]), false)
		r["cover_charge"] = _dec(Multicall.value(res[o + 5], ["uint256"]))
		r["bouncer_divisor"] = _dec(Multicall.value(res[o + 6], ["uint256"]))
		r["creator"] = ""  # the founding tx sender needs a tx lookup; not needed yet


static func _first(v, fallback):
	return v[0] if v != null else fallback


## "" (unknown) when the read failed; never a fake 0.
static func _dec(v) -> String:
	return BigInt.to_decimal(BigInt.from_hex(v[0])) if v != null else ""


func _resolve_missing_words() -> void:
	var need: Array = []
	for q in _list:
		if String(q.get("lon_word", "")).is_empty() and String(q.get("waat", "")) != "":
			need.append(q)
	if need.is_empty():
		return
	var calls: Array = []
	for q in need:
		calls.append(Multicall.make_call(Contracts.HECKE, "Compliment(uint256)", [q["waat"]]))
	var res: Array = await Chain.multicall.run(calls)
	for i in need.size():
		var r: Dictionary = res[i]
		if not r["ok"] or Abi.strip0x(r["data"]).length() < 128:
			continue
		var d := Abi.strip0x(r["data"])
		var q: Dictionary = need[i]
		q["lon_word"] = d.substr(0, 64)
		q["lat_word"] = d.substr(64, 64)
		var p := Coords.project(q["lon_word"], q["lat_word"])
		q["lat"] = p[0]
		q["lon"] = p[1]
