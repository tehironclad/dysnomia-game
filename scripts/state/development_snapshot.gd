class_name DevelopmentSnapshot
extends RefCounted
## A territory's last measured development, read from the chain earlier, so the
## world can be built before (or without) this session's own live read.
##
## Sources (the higher block wins; bars never shrink, so a later measurement is
## never lower):
## 1. res://assets/data/development.json: shipped, measured by
##    tools/live_development.gd -- --snapshot=<abs path> (Σ YUE.Bar(QING) over the
##    known players, one Multicall pass pinned to one block);
## 2. user://development.json: the last live read this machine made of each territory.
##
## A record: {hypo, epi (decimal strings), reactors, block, source}. Only
## territories with bars are listed: a missing entry means "not measured with
## bars", and the world stays Wild until the live read says otherwise.
## The block is always shown with it; this is chain data, just older.

const SHIPPED_PATH := "res://assets/data/development.json"
const CACHE_PATH := "user://development.json"

static var _shipped := {}
static var _shipped_block := 0
static var _cache := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var d = _read_json(SHIPPED_PATH)
	if d is Dictionary:
		_shipped_block = int(d.get("block", 0))
		var t = d.get("territories", {})
		if t is Dictionary:
			for k in t:
				var r = t[k]
				if r is Dictionary and _valid(r):
					_shipped[String(k).to_lower()] = {"hypo": String(r["hypo"]), "epi": String(r.get("epi", "0")),
						"reactors": int(r.get("reactors", 0)), "block": _shipped_block, "source": "shipped"}
	var c = _read_json(CACHE_PATH)
	if c is Dictionary:
		var t2 = c.get("territories", {})
		if t2 is Dictionary:
			for k in t2:
				var r = t2[k]
				if r is Dictionary and _valid(r) and int(r.get("block", 0)) > 0:
					_cache[String(k).to_lower()] = {"hypo": String(r["hypo"]), "epi": String(r.get("epi", "0")),
						"reactors": int(r.get("reactors", 0)), "block": int(r["block"]), "source": "cache"}


static func _valid(r: Dictionary) -> bool:
	return _digits(String(r.get("hypo", ""))) and _digits(String(r.get("epi", "0")))


## Decimal strings can exceed int64; is_valid_int() is false for those.
static func _digits(s: String) -> bool:
	if s.is_empty():
		return false
	for ch in s:
		if ch < "0" or ch > "9":
			return false
	return true


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


## The best earlier measurement of this territory, or {} if none has bars.
static func lookup(address: String) -> Dictionary:
	_load()
	var a := address.to_lower()
	var s: Dictionary = _shipped.get(a, {})
	var c: Dictionary = _cache.get(a, {})
	if c.is_empty():
		return s
	if s.is_empty() or int(c["block"]) >= int(s["block"]):
		return c
	return s


static func shipped_block() -> int:
	_load()
	return _shipped_block


## Pure: tier and energy for a record from lookup().
static func apply(rec: Dictionary) -> Dictionary:
	var h := BigInt.from_decimal(String(rec.get("hypo", "0")))
	var e := BigInt.from_decimal(String(rec.get("epi", "0")))
	return {"tier": Development.tier_of(h), "energy": Development.energy_of(e), "hypo": h, "block": int(rec.get("block", 0))}


## Remember a live read so the next launch starts from it (only with bars; never
## replaces a later block).
static func remember(address: String, hypo_dec: String, epi_dec: String, reactors: int, block: int) -> void:
	_load()
	if block <= 0 or not _digits(hypo_dec) or hypo_dec.lstrip("0") == "":
		return
	var a := address.to_lower()
	var cur: Dictionary = _cache.get(a, {})
	if not cur.is_empty() and int(cur["block"]) >= block:
		return
	_cache[a] = {"hypo": hypo_dec, "epi": epi_dec if _digits(epi_dec) else "0", "reactors": reactors, "block": block, "source": "cache"}
	var out := {}
	for k in _cache:
		var r: Dictionary = _cache[k]
		out[k] = {"hypo": r["hypo"], "epi": r["epi"], "reactors": r["reactors"], "block": r["block"]}
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"territories": out}))
