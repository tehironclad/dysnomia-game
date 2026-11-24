class_name FieldIndex
extends RefCounted
## The Field's finding aid: one row per QING (Registry record + its last measured
## development from DevelopmentSnapshot), then search-as-you-type and filters.
## Pure apart from reading the snapshot file; no network.
##
## Development per row: the snapshot measured every QING it knew at its block
## (Σ YUE.Bar over known players; only QINGs with bars are listed). So a QING
## founded at or before that block and not listed was measured Wild (tier 0,
## 0 reactors, a floor); one founded later was never measured: tier -1, shown "—".

const UNKNOWN := -1


## Registry records (in founding order) → rows. `dev_lookup(address) -> Dictionary`
## and `dev_block` default to DevelopmentSnapshot (tests pass their own).
static func build(territories: Array, dev_lookup: Callable = Callable(), dev_block: int = -1) -> Array:
	if not dev_lookup.is_valid():
		dev_lookup = DevelopmentSnapshot.lookup
	if dev_block < 0:
		dev_block = DevelopmentSnapshot.shipped_block()
	var rows: Array = []
	for i in territories.size():
		var q: Dictionary = territories[i]
		var a := String(q.get("address", "")).to_lower()
		var rec: Dictionary = dev_lookup.call(a)
		var tier := UNKNOWN
		var reactors := UNKNOWN
		var energy := 0.0
		var hypo := ""
		var blk := -1
		if not rec.is_empty():
			var ap := DevelopmentSnapshot.apply(rec)
			tier = int(ap["tier"])
			energy = float(ap["energy"])
			reactors = int(rec.get("reactors", 0))
			hypo = String(rec.get("hypo", ""))
			blk = int(rec.get("block", dev_block))
		elif dev_block > 0 and int(q.get("block", 0)) <= dev_block:
			tier = 0
			reactors = 0
			hypo = "0"
			blk = dev_block
		var e := String(q.get("entropy", ""))
		rows.append({
			"i": i, "n": i + 1, "address": a, "name": String(q.get("name", "")), "symbol": String(q.get("symbol", "")),
			"name_l": String(q.get("name", "")).to_lower(), "symbol_l": String(q.get("symbol", "")).to_lower(),
			"tier": tier, "reactors": reactors, "energy": energy, "hypo": hypo, "dev_block": blk,
			"cover": String(q.get("cover_charge", "0")) not in ["0", ""],
			"creator": String(q.get("creator", "")).to_lower(),
			"rarity": DeepField.tier_of(BigInt.from_decimal(e)) if e != "" else "",
			"block": int(q.get("block", 0)),
		})
	return rows


static func tier_text(row: Dictionary) -> String:
	var t := int(row.get("tier", UNKNOWN))
	return "—" if t < 0 else Development.tier_name(t)


static func reactors_text(row: Dictionary) -> String:
	var r := int(row.get("reactors", UNKNOWN))
	return "—" if r < 0 else str(r)


## Has the fair built rides (Settlement and up; FairSite.fair_tier)? null when unmeasured.
static func has_fair(row: Dictionary):
	var t := int(row.get("tier", UNKNOWN))
	return null if t < 0 else FairSite.fair_tier(t) >= 1


## How well a row matches typed text: 0 = no match; higher is better.
static func match_score(row: Dictionary, text: String) -> int:
	var t := text.strip_edges().to_lower()
	if t == "":
		return 1
	if t.begins_with("#") and t.substr(1).is_valid_int():
		return 100 if int(t.substr(1)) == int(row["n"]) else 0
	if t.begins_with("0x"):
		return 90 if String(row["address"]).begins_with(t) else 0
	var nm: String = row["name_l"]
	var sy: String = row["symbol_l"]
	var bare := nm.trim_suffix(" qing")
	if nm == t or sy == t or bare == t or sy.trim_prefix("q") == t:
		return 80
	if nm.begins_with(t) or sy.begins_with(t) or sy.trim_prefix("q").begins_with(t):
		return 60
	for w in nm.split(" ", false):
		if w.begins_with(t):
			return 45
	if nm.contains(t) or sy.contains(t):
		return 30
	return 0


## Filters (all optional; every one given must pass):
##   mine: {address: true}   joined: {address: true}   yue: {address: true}
##   neighbours: {address: side}   min_tier: int (rows with an unmeasured tier fail)
##   fair: true (rides built: Settlement+)
## Returns matching rows: best text match first, then the most developed, the most
## reactors, then founding order. `limit` <= 0: all.
static func query(rows: Array, text: String, filters: Dictionary = {}, limit: int = 0) -> Array:
	var hits: Array = []
	var min_tier := int(filters.get("min_tier", 0))
	for r in rows:
		var sc := match_score(r, text)
		if sc <= 0:
			continue
		var a: String = r["address"]
		if filters.has("mine") and not filters["mine"].has(a):
			continue
		if filters.has("joined") and not filters["joined"].has(a):
			continue
		if filters.has("yue") and not filters["yue"].has(a):
			continue
		if filters.has("neighbours") and not filters["neighbours"].has(a):
			continue
		if min_tier > 0 and int(r["tier"]) < min_tier:
			continue
		if filters.get("fair", false) and has_fair(r) != true:
			continue
		hits.append([sc, r])
	hits.sort_custom(func(x, y):
		if x[0] != y[0]:
			return x[0] > y[0]
		if int(x[1]["tier"]) != int(y[1]["tier"]):
			return int(x[1]["tier"]) > int(y[1]["tier"])
		if int(x[1]["reactors"]) != int(y[1]["reactors"]):
			return int(x[1]["reactors"]) > int(y[1]["reactors"])
		return int(x[1]["i"]) < int(y[1]["i"]))
	var out: Array = []
	for h in hits:
		out.append(h[1])
		if limit > 0 and out.size() >= limit:
			break
	return out


## Developed rows (tier ≥ 1), most developed first: the front door's news line.
static func developed(rows: Array) -> Array:
	return query(rows, "", {"min_tier": 1})
