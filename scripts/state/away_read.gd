class_name AwayRead
extends RefCounted
## The reads behind "while you were away" (AwayDiff turns them into the card).
## Read-only, no wallet needed. Budget: one Multicall3 pass for your bars (or
## Session's, when it already read them), one for your QINGs' boards, ONE
## eth_getLogs for the room lines of every room you belong to (the address list
## form, windowed by LogScanner), and the registry's own NewQing catch-up.
##
## "Your rooms" = the QINGs where your YUE has bars (every Su or room line you made
## left one; the biggest first), any QING your wallet founded, and the rooms of the
## last visit; at most ROOMS_MAX. Their boards (the Hypobar total, tier and whether you
## lead, over known players) for the first QINGS_MAX.

const ROOMS_MAX := 24
const QINGS_MAX := 12


## Pure: your rooms, in order (your biggest bars first, then founded, then last visit's).
static func rooms_for(wallet: String, bars: Dictionary, prev: Dictionary, rows: Array) -> Array:
	wallet = wallet.to_lower()
	var with_bars: Array = bars.keys()
	with_bars.sort_custom(func(a, b): return BigInt.cmp(AwayDiff.dec(String(bars[a][0])), AwayDiff.dec(String(bars[b][0]))) > 0)
	var out: Array = []
	var seen := {}
	var add := func(q: String) -> void:
		q = q.to_lower()
		if q != "" and not seen.has(q) and out.size() < ROOMS_MAX:
			seen[q] = true
			out.append(q)
	for q in with_bars:
		add.call(String(q))
	if wallet != "":
		for r in rows:
			if String(r.get("creator", "")).to_lower() == wallet:
				add.call(String(r["address"]))
	for q in prev.get("rooms", {}):
		add.call(String(q))
	return out


## What is true now, for AwayDiff.compute(prev, now, …). opts (all optional):
##   player: a PlayerState already read for this wallet; bars + bars_block: Session.bars
##   at that block (PackedInt64Array pairs) so they are not read twice; block: pin the head.
static func read(wallet: String, prev: Dictionary, opts: Dictionary = {}) -> Dictionary:
	wallet = wallet.to_lower()
	var now := {"block": -1, "wallet": wallet, "lau": "", "name": "", "aura": "", "soul": "",
		"bars_ok": false, "bars": {}, "bars_block": -1, "rooms_list": [], "rooms_ok": false, "room_lines": {}, "rooms_to": -1,
		"qings_ok": false, "qings": {}, "qings_failed": [], "registry_ok": false, "registry": {}, "new_qings": []}
	var head := int(opts.get("block", -1))
	if head <= 0:
		head = await Chain.refresh_head()
	if head < 0:
		now["error"] = "chain head unavailable"
		return now
	now["block"] = head
	var ps = opts.get("player")
	if ps == null or String(ps.wallet) != wallet:
		ps = await PlayerState.read(wallet)
	var reg := _registry_node()
	if ps != null and ps.ok:
		now["lau"] = ps.lau
		now["name"] = ps.username
		now["aura"] = ps.aura
		now["soul"] = ps.soul
		if not ps.has_yue():
			now["bars_ok"] = true  # no YUE: no bars anywhere (a fact, not a failure)
			now["bars_block"] = head
		elif opts.has("bars") and int(opts.get("bars_block", -1)) > 0:
			now["bars"] = AwayDiff.bars_dec(opts["bars"])
			now["bars_block"] = int(opts["bars_block"])
			now["bars_ok"] = true
		else:
			var qs: Array = reg.all().map(func(q): return String(q["address"]))
			var r := await bars_at(ps.yue, qs, head)
			now["bars_ok"] = r["ok"]
			now["bars"] = r["map"]
			now["bars_block"] = head
			if not r["ok"]:
				now["bars_error"] = "the Multicall3 read failed"
	else:
		now["bars_error"] = String(ps.error) if ps != null and String(ps.error) != "" else "your identity could not be read"
	var bars_for_rooms: Dictionary = now["bars"] if now["bars_ok"] else prev.get("bars", {})
	var rooms := rooms_for(wallet, bars_for_rooms, prev, reg.all())
	now["rooms_list"] = rooms
	await totals(now, rooms.slice(0, QINGS_MAX), head, wallet, ps.yue if ps != null and ps.ok else "")
	if prev.is_empty() or rooms.is_empty():
		now["rooms_ok"] = true  # nothing to compare (first visit) or no rooms: no log read
		now["rooms_to"] = head
	else:
		await room_lines(now, prev, rooms, head)
	await registry(now, prev)
	return now


static func _registry_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Registry")


static func _players_node() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Players")


## A YUE.Bar result: [hypo, epi] decimals; [0, 0] when the YUE had no code at that
## block (it did not exist yet: no bars, a fact); null when the read failed.
static func _bar_pair(res: Dictionary) -> Variant:
	var v = Multicall.value(res, ["uint256", "uint256"])
	if v != null:
		return [BigInt.to_decimal(BigInt.from_hex(v[0])), BigInt.to_decimal(BigInt.from_hex(v[1]))]
	if res.get("ok", false) and Abi.strip0x(String(res.get("data", ""))) == "":
		return ["0", "0"]
	return null


## `yue`'s YUE.Bar at each of `qings` at `block`: {ok, map: {qing: [hypo, epi]} (non-zero only)}.
static func bars_at(yue: String, qings: Array, block: int) -> Dictionary:
	var calls: Array = []
	for q in qings:
		calls.append(Multicall.make_call(yue, "Bar(address)", [q]))
	var res: Array = await Chain.multicall.run(calls, "", block)
	var out := {}
	var failed := 0
	for i in qings.size():
		var p = _bar_pair(res[i])
		if p == null:
			failed += 1
			continue
		if p[0] != "0" or p[1] != "0":
			out[String(qings[i]).to_lower()] = p
	return {"ok": failed == 0, "map": out, "failed": failed}


## The boards of `qings` at `block`: Σ YUE.Bar(QING).Hypobar over known players (a
## floor), the tier, and whether `wallet` leads. A QING with any failed read is left
## out (qings_failed) rather than shown low.
static func totals(now: Dictionary, qings: Array, block: int, wallet: String, my_yue: String) -> void:
	if qings.is_empty():
		now["qings_ok"] = true
		return
	var players: Array = _players_node().all().duplicate()
	var has_me := false
	for p in players:
		if String(p["wallet"]) == wallet:
			has_me = true
	if not has_me and my_yue != "":
		players.append({"wallet": wallet, "yue": my_yue})
	var calls: Array = []
	for q in qings:
		for p in players:
			calls.append(Multicall.make_call(String(p["yue"]), "Bar(address)", [q]))
	var res: Array = await Chain.multicall.run(calls, "", block)
	var failed: Array = []
	for qi in qings.size():
		var total := BigInt.zero()
		var mine := BigInt.zero()
		var best_other := BigInt.zero()
		var reactors := 0
		var bad := false
		for pi in players.size():
			var pair = _bar_pair(res[qi * players.size() + pi])
			if pair == null:
				bad = true
				break
			var h := BigInt.from_decimal(String(pair[0]))
			total = BigInt.add(total, h)
			if pair[0] != "0" or pair[1] != "0":
				reactors += 1
			if String(players[pi]["wallet"]) == wallet:
				mine = h
			elif BigInt.cmp(h, best_other) > 0:
				best_other = h
		if bad:
			failed.append(qings[qi])
			continue
		now["qings"][qings[qi]] = {"hypo": BigInt.to_decimal(total), "tier": Development.tier_of(total),
			"lead": not BigInt.is_zero(mine) and BigInt.cmp(mine, best_other) >= 0, "reactors": reactors, "block": block}
	now["qings_failed"] = failed
	now["qings_ok"] = failed.is_empty()
	if not failed.is_empty():
		now["qings_error"] = "the Multicall3 read failed"


## New room lines since each room's last-visit block, from ONE windowed eth_getLogs
## over every room's address. Only logs whose emitter is one of the rooms count.
static func room_lines(now: Dictionary, prev: Dictionary, rooms: Array, head: int) -> void:
	var from := head
	for q in rooms:
		from = mini(from, AwayDiff.room_seen(prev, q))
	from = maxi(from, Contracts.MAP_FIRST_BLOCK)
	if from >= head:
		now["rooms_ok"] = true
		now["rooms_to"] = head
		return
	var r: Dictionary = await Chain.logs.scan(rooms, [Contracts.TOPIC_ROOM_CHAT], from + 1, head)
	now["room_lines"] = split_lines(r["logs"], rooms, prev)
	now["rooms_ok"] = r["ok"]
	now["rooms_to"] = head if r["ok"] else int(r.get("scanned_to", -1))
	if not r["ok"]:
		now["rooms_error"] = "eth_getLogs stopped at block %d" % int(r.get("scanned_to", -1))


## Pure: raw logs → {qing: [line]} for the rooms in `rooms`, newer than each room's
## last-visit block (ChatLog parses; the emitter must be the room itself).
static func split_lines(logs: Array, rooms: Array, prev: Dictionary) -> Dictionary:
	var by := {}
	for l in logs:
		var a := String(l.get("address", "")).to_lower()
		if rooms.has(a):
			if not by.has(a):
				by[a] = []
			by[a].append(l)
	var out := {}
	for q in by:
		var since := AwayDiff.room_seen(prev, q)
		var lines: Array = ChatLog.parse_logs(by[q], q, true).filter(func(x): return int(x["block"]) > since)
		for x in lines:
			x["source"] = "chain"
		if not lines.is_empty():
			out[q] = lines
	return out


## The registry caught up (NewQing logs on MAP), and the QINGs founded since the last visit.
static func registry(now: Dictionary, prev: Dictionary) -> void:
	var reg := _registry_node()
	var ok: bool = await reg.catch_up()
	now["registry_ok"] = ok
	now["registry"] = {"count": reg.count(), "cursor": reg.cursor_block}
	if not ok:
		now["registry_error"] = String(reg.last_error) if String(reg.last_error) != "" else "the log read failed"
	var since := int(prev.get("registry", {}).get("cursor", prev.get("block", -1)))
	if since <= 0:
		return
	var fresh: Array = []
	for q in reg.all():
		var b := int(q.get("block", 0))
		if b > since and b <= reg.cursor_block:
			fresh.append({"address": String(q["address"]), "name": String(q.get("name", "")), "block": b, "tx_hash": String(q.get("tx_hash", ""))})
	now["new_qings"] = fresh


## A baseline read from the chain AT an earlier block (archive state), for previews and
## the live tool: what a visit at `block` would have stored. Marked "preview" (never saved).
## {} when the block is not in the past or the identity can't be read.
static func at_block(wallet: String, block: int, opts: Dictionary = {}) -> Dictionary:
	wallet = wallet.to_lower()
	var head := await Chain.refresh_head()
	if head < 0 or block <= 0 or block >= head:
		return {}
	var ps = opts.get("player")
	if ps == null or String(ps.wallet) != wallet:
		ps = await PlayerState.read(wallet)
	if ps == null or not ps.ok:
		return {}
	var reg := _registry_node()
	await reg.catch_up()
	var base := {"v": AwayDiff.VERSION, "block": block, "at": 0, "lau": ps.lau, "name": ps.username, "preview": true,
		"rooms": {}, "qings": {}, "bars": {}, "bars_block": -1, "registry": {}}
	var bars_now := {}
	if ps.has_yue():
		if opts.has("bars") and int(opts.get("bars_block", -1)) > 0:
			bars_now = AwayDiff.bars_dec(opts["bars"])
		else:
			var r := await bars_at(ps.yue, reg.all().map(func(q): return String(q["address"])), head)
			bars_now = r["map"]
		# Bars only grow: every QING with bars then has bars now, so these are all.
		var then := await bars_at(ps.yue, bars_now.keys(), block)
		if then["ok"]:
			base["bars"] = then["map"]
			base["bars_block"] = block
	var rooms := rooms_for(wallet, bars_now, {}, reg.all())
	for q in rooms:
		base["rooms"][q] = {"seen": block, "last": -1}
	var tmp := {"qings": {}, "qings_failed": []}
	await totals(tmp, rooms.slice(0, QINGS_MAX), block, wallet, ps.yue if ps.has_yue() else "")
	base["qings"] = tmp["qings"]
	if not tmp["qings_failed"].is_empty():
		base["qings_failed"] = tmp["qings_failed"]  # the card says "—" for these (nothing to compare with)
	var n := 0
	for q in reg.all():
		if int(q.get("block", 0)) <= block:
			n += 1
	base["registry"] = {"count": n, "cursor": block}
	return base
