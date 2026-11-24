class_name Neighbours
extends RefCounted
## Which QINGs border a territory, from the chain's own coordinates.
##
## HECKE.Compliment(Waat) places every QING at a raw (lat, lon) cell of ~240-bit
## int256 words (LEARNINGS §6). The *degree* projection is a modular hash, but the
## raw words are a geometric function of the Waat, and they are the space MAP keys
## territories by (GetMapQing(lat, lon)) and WORLD.Code measures range in: a
## square, |Δlat| ≤ Yeo and |Δlon| ≤ Yeo. So the neighbour on each side is the
## nearest QING in that side's quarter of the raw plane, by that same square
## (Chebyshev) distance:
##   north: Δlat > 0 and |Δlat| ≥ |Δlon|      south: Δlat < 0 and |Δlat| ≥ |Δlon|
##   east:  Δlon > 0 and |Δlon| > |Δlat|      west:  Δlon < 0 and |Δlon| > |Δlat|
## Ties go to the smaller perpendicular offset, then the lower address. A side
## with no QING in its quarter is empty (the edge of the map): nothing is drawn.
## All arithmetic is BigInt on the raw words; nothing passes through a float.
##
## World axes: north is −Z, east is +X; each territory is 512 m square.

const SIDES := ["n", "e", "s", "w"]
const OPPOSITE := {"n": "s", "e": "w", "s": "n", "w": "e"}
const NAMES := {"n": "north", "e": "east", "s": "south", "w": "west"}

## Parsed raw coordinates, keyed by address: [lat_neg, lat_mag, lon_neg, lon_mag].
static var _coords := {}


## The world offset (metres) of the neighbour's centre on `side`.
static func offset(side: String) -> Vector3:
	var s := JuliaHeightfield.SIZE_M
	match side:
		"n": return Vector3(0.0, 0.0, -s)
		"s": return Vector3(0.0, 0.0, s)
		"e": return Vector3(s, 0.0, 0.0)
		"w": return Vector3(-s, 0.0, 0.0)
	return Vector3.ZERO


## Outward unit direction of `side` on the ground (x, z).
static func outward(side: String) -> Vector2:
	match side:
		"n": return Vector2(0, -1)
		"s": return Vector2(0, 1)
		"e": return Vector2(1, 0)
		"w": return Vector2(-1, 0)
	return Vector2.ZERO


## Which border a ground position (metres from the centre) is nearest to, and
## how far inside it is: {side, inside_m, along} (along = the coordinate along that border).
static func nearest_border(x: float, z: float) -> Dictionary:
	var half := JuliaHeightfield.SIZE_M * 0.5
	var best := {"side": "n", "inside_m": half + z, "along": x}
	if half - z < float(best["inside_m"]):
		best = {"side": "s", "inside_m": half - z, "along": x}
	if half - x < float(best["inside_m"]):
		best = {"side": "e", "inside_m": half - x, "along": z}
	if half + x < float(best["inside_m"]):
		best = {"side": "w", "inside_m": half + x, "along": z}
	return best


## Where a player crossing out through `side` (at `along` metres along it)
## arrives in the neighbour: just inside its opposite border, same `along`.
static func arrival(side: String, along: float, inset: float = 6.0) -> Vector2:
	var half := JuliaHeightfield.SIZE_M * 0.5
	var a := clampf(along, -half + inset, half - inset)
	match OPPOSITE[side]:
		"n": return Vector2(a, -half + inset)
		"s": return Vector2(a, half - inset)
		"e": return Vector2(half - inset, a)
		"w": return Vector2(-half + inset, a)
	return Vector2.ZERO


## [lat_neg, lat_mag, lon_neg, lon_mag] from a Registry record's raw words, or
## [] when the words are unknown (never guessed).
static func coords(q: Dictionary) -> Array:
	var a := String(q.get("address", "")).to_lower()
	if _coords.has(a):
		return _coords[a]
	var lat_w := String(q.get("lat_word", ""))
	var lon_w := String(q.get("lon_word", ""))
	var out: Array = []
	if lat_w.length() == 64 and lon_w.length() == 64:
		var la := BigInt.from_signed(BigInt.word_to_signed_hex(lat_w))
		var lo := BigInt.from_signed(BigInt.word_to_signed_hex(lon_w))
		out = [la[0], la[1], lo[0], lo[1]]
	_coords[a] = out
	return out


## b − a for signed values held as [neg, magnitude]: returns [neg, magnitude].
static func signed_sub(a_neg: bool, a: PackedInt64Array, b_neg: bool, b: PackedInt64Array) -> Array:
	if a_neg != b_neg:
		# b − a = b + (−a): same sign as b, magnitudes add
		return [b_neg, BigInt.add(a, b)]
	var c := BigInt.cmp(b, a)
	if c == 0:
		return [false, BigInt.zero()]
	if c > 0:
		return [b_neg, BigInt.sub(b, a)]
	return [not b_neg, BigInt.sub(a, b)]


## Which quarter `to` lies in seen from `from`, with the distances that rank it:
## {side, along (|Δ| on the side's axis), perp, dlat, dlon} or {} if either
## record has no coordinates or they share a cell.
static func relate(from: Dictionary, to: Dictionary) -> Dictionary:
	var f := coords(from)
	var t := coords(to)
	if f.is_empty() or t.is_empty():
		return {}
	var dlat := signed_sub(f[0], f[1], t[0], t[1])
	var dlon := signed_sub(f[2], f[3], t[2], t[3])
	var c := BigInt.cmp(dlat[1], dlon[1])
	if BigInt.is_zero(dlat[1]) and BigInt.is_zero(dlon[1]):
		return {}
	var side := ""
	if c >= 0:
		side = "s" if dlat[0] else "n"
		return {"side": side, "along": dlat[1], "perp": dlon[1], "dlat": dlat, "dlon": dlon}
	side = "w" if dlon[0] else "e"
	return {"side": side, "along": dlon[1], "perp": dlat[1], "dlat": dlat, "dlon": dlon}


## The neighbour on each side: {n|e|s|w: {address, along, perp, dlat, dlon}},
## a side missing from the result has no QING in its quarter.
static func find(q: Dictionary, all: Array) -> Dictionary:
	var me := String(q.get("address", "")).to_lower()
	var best := {}
	if coords(q).is_empty():
		return best
	for other in all:
		var a := String(other.get("address", "")).to_lower()
		if a == me:
			continue
		var r := relate(q, other)
		if r.is_empty():
			continue
		var side: String = r["side"]
		if best.has(side) and not _better(r, a, best[side]):
			continue
		r["address"] = a
		best[side] = r
	return best


static func _better(r: Dictionary, addr: String, cur: Dictionary) -> bool:
	var c := BigInt.cmp(r["along"], cur["along"])
	if c != 0:
		return c < 0
	c = BigInt.cmp(r["perp"], cur["perp"])
	if c != 0:
		return c < 0
	return addr < String(cur["address"])


## A signed BigInt [neg, mag] as a short decimal with an exponent, for display only.
static func short(v: Array) -> String:
	var mag: PackedInt64Array = v[1]
	if BigInt.is_zero(mag):
		return "0"
	var dec := BigInt.to_decimal(mag)
	var s := ("−" if v[0] else "+")
	if dec.length() <= 4:
		return s + dec
	return "%s%s.%se%d" % [s, dec.substr(0, 1), dec.substr(1, 2), dec.length() - 1]


## Checks each neighbour against MAP.GetMapQing at its own Compliment cell, in one
## Multicall at one block. Returns {block, ok: {side: true|false|null}} where null
## means the read failed (unknown, not "no").
static func verify_on_map(q_by_side: Dictionary) -> Dictionary:
	var sides: Array = []
	var calls: Array = []
	for side in q_by_side:
		var r: Dictionary = q_by_side[side]
		calls.append(Multicall.make_call(Contracts.MAP, "GetMapQing(int256,int256)", [
			BigInt.word_to_signed_hex(String(r.get("lat_word", ""))),
			BigInt.word_to_signed_hex(String(r.get("lon_word", "")))]))
		sides.append(side)
	var out := {"block": -1, "ok": {}}
	if calls.is_empty():
		return out
	var head := await Chain.refresh_head()
	if head < 0:
		for s in sides:
			out["ok"][s] = null
		return out
	out["block"] = head
	var res: Array = await Chain.multicall.run(calls, "", head)
	for i in sides.size():
		var v = Multicall.value(res[i], ["address"])
		var want := String(q_by_side[sides[i]].get("address", "")).to_lower()
		out["ok"][sides[i]] = null if v == null else String(v[0]).to_lower() == want
	return out
