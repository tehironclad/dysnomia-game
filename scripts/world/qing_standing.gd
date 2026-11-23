class_name QingStanding
extends Node
## A QING's Standing: one score from how alive the territory is, mapped to a tier that
## decides what gets built there. Busy, well-loved, well-terraformed QINGs grow from a
## Dysnomia outpost into a Grand Fair; quiet ones stay moonscape with a surveyed lot that
## shows exactly what they need. That's the keeper's incentive to make their QING the best.
##
## Every input is public and the same for every visitor, so every visitor sees the same
## tier:
##   power     — XIE.Power charge (terraforming invested in the land)        on-chain
##   bars      — the keeper's own YUE.Bar Hypobar+Epibar in their QING       on-chain
##   visitors  — unique LAU souls who have chatted in this QING              on-chain logs
##   chatter   — total chat messages in this QING                            on-chain logs
##   visits    — visit count, when the entropy API serves /api/qing-stats    off-chain, optional
##   reactions — emote/reaction count, same endpoint                         off-chain, optional
## Magnitudes from chain are huge and unbounded, so power and bars are log-scaled.

signal standing_changed(standing: Dictionary)

const TIERS := [
	{"tier": 0, "min": 0,   "title": "Outpost",    "fair": "Surveyed Lot"},
	{"tier": 1, "min": 150, "title": "Settlement", "fair": "Night Market"},
	{"tier": 2, "min": 400, "title": "Hub",        "fair": "Fairground"},
	{"tier": 3, "min": 750, "title": "Capital",    "fair": "Grand Fair"},
]

## What each tier adds to the fair (shown to keepers as the next goal)
const UNLOCKS := {
	1: "Night Market + Orbital Carousel",
	2: "Rho Wheel + Pi Drop Tower",
	3: "Upsilon Rocket + headliner nights",
}

const CAP_POWER := 250.0
const CAP_BARS := 250.0
const CAP_VISITORS := 300.0
const CAP_CHATTER := 150.0
const CAP_VISITS := 200.0
const CAP_REACTIONS := 150.0

var tier_override: int = -1   # Console: `standing <0-3>` / `standing auto`

var _qing: String = ""
var _keeper_hypo: int = 0
var _keeper_epi: int = 0
var _messages: int = 0
var _visitors: int = 0
var _api: Dictionary = {}
var _last: Dictionary = {}


func _ready() -> void:
	ChainManager.qing_activity_updated.connect(_on_activity)
	ChainManager.keeper_bars_loaded.connect(_on_keeper_bars)
	ChainManager.qing_stats_loaded.connect(_on_api_stats)
	GameManager.territory_state_changed.connect(func(_d: Dictionary) -> void: recompute())
	GameManager.territory_data_changed.connect(func(_d: Dictionary) -> void: refresh())
	refresh()


func refresh() -> void:
	## Re-read everything for the current territory.
	var q := GameManager.territory_address.to_lower()
	if q != _qing:
		_qing = q
		_keeper_hypo = 0
		_keeper_epi = 0
		_api = {}
		var a: Dictionary = ChainManager.get_qing_activity(q)
		_messages = a["messages"]
		_visitors = a["unique_visitors"]
	if HexUtils.is_valid_address(GameManager.territory_owner) and HexUtils.is_valid_address(_qing):
		ChainManager.read_keeper_bars(GameManager.territory_owner, _qing)
	if HexUtils.is_valid_address(_qing):
		ChainManager.load_qing_stats(_qing)
	recompute()


func current() -> Dictionary:
	return _last if not _last.is_empty() else compute()


func compute() -> Dictionary:
	var parts := {
		"power": _log_points(GameManager.territory_charge, CAP_POWER),
		"bars": _log_points(_keeper_hypo + _keeper_epi, CAP_BARS),
		"visitors": minf(_visitors * 20.0, CAP_VISITORS),
		"chatter": minf(_messages * 1.5, CAP_CHATTER),
		"visits": minf(float(_api.get("visits", 0)) * 0.5, CAP_VISITS),
		"reactions": minf(float(_api.get("reactions", 0)) * 2.0, CAP_REACTIONS),
	}
	var score := 0
	for v in parts.values():
		score += int(round(v))
	var t: Dictionary = tier_for_score(score)
	if tier_override >= 0:
		t = TIERS[clampi(tier_override, 0, 3)]
	var next: Dictionary = TIERS[t["tier"] + 1] if t["tier"] < 3 else {}
	return {
		"score": score,
		"tier": t["tier"],
		"title": t["title"],
		"fair": t["fair"],
		"parts": parts,
		"next_tier": next.get("tier", -1),
		"next_min": next.get("min", -1),
		"next_title": next.get("title", ""),
		"next_unlock": UNLOCKS.get(next.get("tier", -1), ""),
		"best_lever": _best_lever(parts),
		"overridden": tier_override >= 0,
		"raw": {"messages": _messages, "unique_visitors": _visitors,
			"keeper_hypobar": _keeper_hypo, "keeper_epibar": _keeper_epi, "api": _api},
	}


func recompute() -> void:
	var s := compute()
	var changed: bool = _last.is_empty() or s["tier"] != _last.get("tier", -1) or s["score"] != _last.get("score", -1)
	_last = s
	if changed:
		standing_changed.emit(s)


static func tier_for_score(score: int) -> Dictionary:
	var out: Dictionary = TIERS[0]
	for t in TIERS:
		if score >= t["min"]:
			out = t
	return out


static func unlock_hint(s: Dictionary) -> String:
	if s.get("next_tier", -1) < 0:
		return "Grand Fair — the best this QING can be."
	return "Unlocks at Standing %d · this QING: %d · %s" % [s["next_min"], s["score"], s.get("best_lever", "")]


static func _log_points(value: int, cap: float) -> float:
	## 0 → 0, 1e6 → ~cap/2, 1e12 → cap. Robust to the chain's unbounded magnitudes.
	if value <= 0:
		return 0.0
	return clampf(log(1.0 + float(value)) / log(10.0) / 12.0 * cap, 0.0, cap)


static func _best_lever(parts: Dictionary) -> String:
	## The cheapest way to climb: the input furthest from its cap.
	var room := {
		"bring visitors who chat here": CAP_VISITORS - parts["visitors"],
		"terraform to build charge": CAP_POWER - parts["power"],
		"grow your Hypobar/Epibar here": CAP_BARS - parts["bars"],
		"get the bar talking": CAP_CHATTER - parts["chatter"],
	}
	var best := ""
	var most := -1.0
	for k in room:
		if room[k] > most:
			most = room[k]
			best = k
	return "Next: " + best


func _on_activity(qing: String, messages: int, visitors: int) -> void:
	if qing.to_lower() != _qing:
		return
	_messages = messages
	_visitors = visitors
	recompute()


func _on_keeper_bars(qing: String, h: int, e: int) -> void:
	if qing.to_lower() != _qing:
		return
	_keeper_hypo = h
	_keeper_epi = e
	recompute()


func _on_api_stats(qing: String, stats: Dictionary) -> void:
	if qing.to_lower() != _qing:
		return
	_api = stats
	recompute()
