class_name Development
extends RefCounted
## How built-up a territory is, from its chain state (shared by every viewer):
##
## - Tier, from the Hypobar total at the QING (Σ YUE.Bar(QING).Hypobar over
##   known players). Hypobar is the territory's accumulated, Ω-weighted
##   activity (every Su or CHOA.Chat adds Ω = ⌊Fornax(QING)/Entropy⌋), and
##   bars only ever grow, so a territory can build up but never decay.
## - Energy, from the Epibar total: the reacting players' own Fornax stake
##   (⌊Fornax(LAU)/entropy⌋ per reaction). It lights the windows, the city
##   lights and the aurora.
## - Each player's own Hypobar there is the height of their tower (Skyline).
##
## The totals are floors (known players only), so a tier can be understated,
## never overstated. Measured 2026-11-23 over all 942 territories: 889 wild;
## 11 outposts; 9 settlements; 4 towns; 4 cities; 1 capital (RatKing).

const TIERS := [
	{"name": "Wild", "min_log": -INF, "what": "no bars yet: bare regolith"},
	{"name": "Outpost", "min_log": 0.0, "what": "a beacon on the Room"},
	{"name": "Settlement", "min_log": 4.0, "what": "landing pads, lights, supplies"},
	{"name": "Town", "min_log": 6.0, "what": "city lights along the Julia coast"},
	{"name": "City", "min_log": 8.0, "what": "an aurora; brighter streets"},
	{"name": "Capital", "min_log": 9.0, "what": "a light spire from the Heart into the sky"},
]


## Pure: tier index (0..5) for a Hypobar total.
static func tier_of(hypobar_total: PackedInt64Array) -> int:
	if BigInt.is_zero(hypobar_total):
		return 0
	var lg := BigInt.log10(hypobar_total)
	var t := 1
	for i in range(1, TIERS.size()):
		if lg >= float(TIERS[i]["min_log"]):
			t = i
	return t


static func tier_name(t: int) -> String:
	return String(TIERS[clampi(t, 0, TIERS.size() - 1)]["name"])


## The Hypobar total the next tier needs ("" at the top).
static func next_threshold(t: int) -> String:
	if t + 1 >= TIERS.size():
		return ""
	var lg: float = TIERS[t + 1]["min_log"]
	return "1" if lg <= 0.0 else "1" + "0".repeat(int(lg))


## Pure: 0..1 energy from the Epibar total (log scale, 10^2 → 0, 10^10 → 1).
static func energy_of(epibar_total: PackedInt64Array) -> float:
	if BigInt.is_zero(epibar_total):
		return 0.0
	return clampf((BigInt.log10(epibar_total) - 2.0) / 8.0, 0.0, 1.0)


static func describe(t: int) -> String:
	var nxt := next_threshold(t)
	return "%s: %s%s" % [tier_name(t), TIERS[t]["what"], ("; next tier at %s Hypobar" % TokenFormat.group(nxt)) if nxt != "" else ""]
