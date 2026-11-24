class_name PlaySnapshot
extends RefCounted
## Builds PlayLoop's snapshot from what the game has already read (TerritoryState,
## Session, the room's feed) plus two small reads of its own (`read_extras`):
## the room's door for this wallet (RoomState) and Ω at the neighbouring QINGs
## (Fornax.balanceOf ÷ Entropy, one Multicall). Anything not read stays null, so
## PlayLoop shows "—" and never a made-up 0.


## Pure-ish: no reads. `extras` is what read_extras returned (or {}).
static func build(state: TerritoryState, wallet: String, ps: PlayerState, rd: Readiness, record: PlayerRecord,
		bars: Dictionary, bars_block: int, feed: RoomFeed, sides: Dictionary, extras: Dictionary) -> Dictionary:
	var s := {"wallet": wallet}
	if wallet == "":
		s["identity"] = "none"
	elif ps == null or ps.error != "" or not ps.ok:
		s["identity"] = "unknown"
	elif not ps.has_lau():
		s["identity"] = "no_lau"
	elif not ps.has_yue():
		s["identity"] = "no_yue"
	else:
		s["identity"] = "ok"
	if state != null:
		s["block"] = state.block
		if state.omega.has_value():
			s["omega"] = BigInt.coerce(state.omega.value)
		if state.total_hypobar.has_value():
			s["total_hypo"] = BigInt.coerce(state.total_hypobar.value)
			s["board"] = state.board
		var wells := {}
		for k in ["fornax", "eris", "tethys"]:
			var f: Fact = state.get(k)
			wells[k] = BigInt.coerce(f.value) if f.has_value() else null
		s["wells"] = wells
	if rd != null and rd.state != "unknown":
		s["readiness"] = rd.state
		s["readiness_reason"] = rd.reason
	if record != null and record.ok:
		s["streak"] = {"current": record.current, "best": record.best, "today_done": record.today_done, "seconds_left": record.seconds_left}
	if bars_block >= 0:
		s["bars_count"] = bars.size()
	if feed != null and feed.is_loaded():
		var last := -1
		for l in feed.lines:
			if String(l.get("source", "chain")) != "say":
				last = maxi(last, int(l.get("block", -1)))
		var room := {"loaded": feed.history_ok or last >= 0, "last_block": last,
			"head": maxi(feed.head_seen, Chain.head_block), "cover": null, "admitted": null}
		var door: RoomState = extras.get("door")
		if door != null and door.ok:
			room["cover"] = door.cover
			room["admitted"] = door.admitted
		s["room"] = room
	var nbs: Array = []
	var nom: Dictionary = extras.get("neighbour_omega", {})
	for side in Neighbours.SIDES:
		if not sides.has(side):
			continue
		var a := String(sides[side]["address"]).to_lower()
		var q: Dictionary = sides[side].get("q", Registry.get_territory(a))
		nbs.append({"side": side, "address": a, "name": BorderRing.qname(q),
			"omega": nom.get(a), "my_bars": (bars.has(a)) if bars_block >= 0 else null})
	s["neighbours"] = nbs
	return s


## The two reads PlayLoop needs beyond the shared ones: {door: RoomState|null,
## neighbour_omega: {address: PackedInt64Array}} (a failed read is left out).
static func read_extras(qing: String, ps: PlayerState, sides: Dictionary) -> Dictionary:
	var out := {"neighbour_omega": {}}
	if ps != null and ps.has_lau():
		out["door"] = await RoomState.read(qing, ps)
	var addrs: Array = []
	for side in Neighbours.SIDES:
		if sides.has(side):
			addrs.append(String(sides[side]["address"]).to_lower())
	if addrs.is_empty():
		return out
	var head := await Chain.refresh_head()
	if head < 0:
		return out
	var calls: Array = addrs.map(func(a): return Multicall.make_call(Contracts.FORNAX, "balanceOf(address)", [a]))
	var res: Array = await Chain.multicall.run(calls, "", head)
	for i in addrs.size():
		var v = Multicall.value(res[i], ["uint256"])
		var ent := String(Registry.get_territory(addrs[i]).get("entropy", ""))
		if v == null or ent == "" or BigInt.is_zero(BigInt.from_decimal(ent)):
			continue
		out["neighbour_omega"][addrs[i]] = BigInt.div(BigInt.from_hex(v[0]), BigInt.from_decimal(ent))
	return out
