class_name PlayLoop
extends RefCounted
## The diegetic loop (pure): a territory's live chain state, seen by one player,
## becomes a short list of things to do *here*, each one a real contract call
## at a real building, plus personal goals. Nothing here reads the chain: the
## caller (ActLoop) builds a snapshot from values it already read, and an
## unread value is null, so it shows "—" and never turns into a 0.
##
## Snapshot (every key optional; null / missing = not read):
##   wallet: String ("" = no wallet)
##   identity: "ok" | "no_lau" | "no_yue" | "unknown"
##   block: int                         TerritoryState's block
##   omega: PackedInt64Array             ⌊Fornax(QING)/Entropy⌋, the Hypobar every Su adds here
##   board: Array [{wallet, hypobar}]    YUE.Bar(QING) over known players, desc (a floor)
##   total_hypo: PackedInt64Array        Σ Hypobar here (a floor)
##   readiness: String                   Readiness.state ("" = unread)
##   readiness_reason: String
##   streak: {current, best, today_done, seconds_left}   PlayerRecord (YUE mint logs)
##   room: {loaded: bool, last_block: int (-1 = no line in the history read), head: int,
##          cover: PackedInt64Array|null, admitted: bool|null}
##   neighbours: [{side, name, address, omega: PIA|null, my_bars: bool|null}]
##   wells: {fornax: PIA|null, eris: PIA|null, tethys: PIA|null}   balanceOf(QING), wei
##   bars_count: int (-1 = unread)       territories where this wallet has bars
##
## Act: {key, kind, anchor, title, lore, detail, call, priority, doable, blocker}
##   kind: su | beat | room | border | well | crown
##   anchor: pylon | heart | room | tower | border_<side> | well_<key>  (where its beacon stands)

## One DysnomiaTime day in blocks (115,600 s ÷ ≈10.3 s per block): "quiet" means
## no room line within it.
const QUIET_BLOCKS := 11223
const REACH_MAX := 25  # Su to pass someone, beyond which it is not offered as an act
const MAX_ACTS := 6
const MAX_SU := 1 << 62  # "more than can be counted" for display


static func _pia(v) -> PackedInt64Array:
	return v if v is PackedInt64Array else PackedInt64Array()


static func _has(snap: Dictionary, key: String) -> bool:
	return snap.has(key) and snap[key] != null


static func dec(v) -> String:
	if v == null:
		return "—"
	return TokenFormat.group(BigInt.to_decimal(BigInt.coerce(v)))


# --- Goal maths (BigInt only) ------------------------------------------------------

## Su needed for `mine` to reach at least `target` at Ω (0 when already there,
## -1 when Ω = 0: Su adds no Hypobar here).
static func su_to_reach(target: PackedInt64Array, mine: PackedInt64Array, omega: PackedInt64Array) -> int:
	if BigInt.cmp(mine, target) >= 0:
		return 0
	if BigInt.is_zero(omega):
		return -1
	var n := Opportunities.ceil_div(BigInt.sub(target, mine), omega)
	return BigInt.to_int(n) if BigInt.fits_int(n) else MAX_SU


## The territory's next development tier: {tier, next, need (Hypobar), su}
## (su -1 at Ω = 0; empty dict at the top tier). The total is a floor.
static func tier_goal(total: PackedInt64Array, omega: PackedInt64Array) -> Dictionary:
	var t := Development.tier_of(total)
	var nxt := Development.next_threshold(t)
	if nxt == "":
		return {}
	var th := BigInt.from_decimal(nxt)
	var need := BigInt.sub(th, total) if BigInt.cmp(th, total) > 0 else PackedInt64Array()
	return {"tier": t, "next": t + 1, "need": need, "su": su_to_reach(th, total, omega)}


## Your tower here (BarColumns.floors_for): its floors now and how many Su until
## the next floor. Exact search over BigInt sums: floors_for(mine + k·Ω).
## {floors, su_next (-1 = Ω is 0 or the tower is at its top)}
static func tower_goal(mine: PackedInt64Array, omega: PackedInt64Array) -> Dictionary:
	var f := BarColumns.floors_for(mine)
	if BigInt.is_zero(omega) or f >= 16:
		return {"floors": f, "su_next": -1}
	if BarColumns.floors_for(BigInt.add(mine, omega)) > f:
		return {"floors": f, "su_next": 1}
	var lo := 1
	var hi := 2
	while BarColumns.floors_for(BigInt.add(mine, BigInt.mul(omega, BigInt.from_int(hi)))) <= f:
		lo = hi
		hi *= 2
		if hi > (1 << 60):
			return {"floors": f, "su_next": -1}
	while hi - lo > 1:  # floors_for(mine + lo·Ω) == f < floors_for(mine + hi·Ω)
		var mid := lo + (hi - lo) / 2
		if BarColumns.floors_for(BigInt.add(mine, BigInt.mul(omega, BigInt.from_int(mid)))) > f:
			hi = mid
		else:
			lo = mid
	return {"floors": f, "su_next": hi}


## Your row on the board: {rank (0 = none), mine, above (the next one up's Hypobar), gap_su}
static func rank_of(board: Array, wallet: String, omega: PackedInt64Array) -> Dictionary:
	for i in board.size():
		if String(board[i]["wallet"]) == wallet:
			var mine: PackedInt64Array = board[i]["hypobar"]
			var r := {"rank": i + 1, "mine": mine, "players": board.size()}
			if i > 0:
				var above: PackedInt64Array = board[i - 1]["hypobar"]
				r["above"] = above
				r["gap_su"] = _n(Opportunities.su_to_pass(above, mine, omega)) if not BigInt.is_zero(omega) else -1
			elif board.size() > 1:
				var runner: PackedInt64Array = board[1]["hypobar"]
				r["margin"] = BigInt.sub(mine, runner)
				r["margin_su"] = _n(Opportunities.su_to_pass(mine, runner, omega)) if not BigInt.is_zero(omega) else -1
			return r
	return {"rank": 0, "mine": PackedInt64Array(), "players": board.size()}


static func _n(b: PackedInt64Array) -> int:
	return BigInt.to_int(b) if BigInt.fits_int(b) else MAX_SU


static func su_text(n: int) -> String:
	if n < 0:
		return "—"
	if n >= MAX_SU:
		return "too many"
	return TokenFormat.group(str(n))


# --- Acts ---------------------------------------------------------------------------

## Pure: the acts here, most worth doing first (at most MAX_ACTS).
static func acts(snap: Dictionary) -> Array:
	var out: Array = []
	var wallet := String(snap.get("wallet", ""))
	var ident := String(snap.get("identity", "unknown"))
	var has_omega := _has(snap, "omega")
	var omega := _pia(snap.get("omega"))
	var omega_txt := dec(snap.get("omega")) if has_omega else "—"
	var board_read := _has(snap, "board")
	var me := rank_of(snap["board"], wallet, omega) if board_read and wallet != "" else {}
	var streak: Dictionary = snap["streak"] if _has(snap, "streak") else {}
	var id_block := ""
	if wallet == "":
		id_block = "connect a wallet at the front door"
	elif ident == "no_lau":
		id_block = "no LAU yet: enter the Void at the front door"
	elif ident == "no_yue":
		id_block = "no YUE yet: wake it (SEI.Start)"
	elif ident != "ok":
		id_block = "reading your identity…"

	# Su at the pylons: the primary live move.
	var su := {"key": "su", "kind": "su", "anchor": "pylon", "call": "CHEON.Su(QING)", "doable": id_block == "", "blocker": id_block}
	if not has_omega:
		su["title"] = "Su here: Ω = —"
		su["detail"] = "Ω not read yet"
		su["priority"] = 40
	elif BigInt.is_zero(omega):
		su["title"] = "Su here: Ω = 0"
		su["detail"] = "Fornax here ÷ Entropy rounds to 0: a Su adds no Hypobar, still +1 YUE and your Epibar"
		su["priority"] = 30
	else:
		su["title"] = "Su here: Ω = %s" % omega_txt
		su["priority"] = 80
		if not me.is_empty():
			var tg := tower_goal(me["mine"], omega)
			if int(tg["su_next"]) == 1:
				su["detail"] = "your tower grows: %d → %d floors" % [tg["floors"], tg["floors"] + 1]
				su["priority"] = 90
			elif int(tg["su_next"]) > 1:
				su["detail"] = "+%s Hypobar a Su; your tower's next floor in %s Su" % [omega_txt, su_text(tg["su_next"])]
			else:
				su["detail"] = "+%s Hypobar a Su" % omega_txt
		else:
			su["detail"] = "+%s Hypobar a Su, the same for everyone" % omega_txt
	if not streak.is_empty() and not bool(streak.get("today_done", true)):
		su["priority"] = int(su["priority"]) + 15
		su["detail"] = String(su.get("detail", "")) + (" · keeps your %d-day streak" % int(streak.get("current", 0)) if int(streak.get("current", 0)) > 0 else " · starts a streak today")
	su["lore"] = "React with the Rod and the Cone. The pylons carry this land's set, c and its mirror; touch them and your bars here grow."
	out.append(su)

	# Beat at the Heart.
	var rs := String(snap.get("readiness", ""))
	var beat := {"key": "beat", "kind": "beat", "anchor": "heart", "call": "META.Beat(Waat)",
		"lore": "The Heart either beats or it doesn't. Hold the four bodies in their places and it answers."}
	if id_block != "":
		beat.merge({"title": "Beat: —", "detail": id_block, "doable": false, "blocker": id_block, "priority": 10})
	elif rs == "":
		beat.merge({"title": "Beat: reading…", "detail": "readiness not read yet", "doable": false, "blocker": "readiness unread", "priority": 10})
	elif rs in ["ready", "fragile"]:
		beat.merge({"title": "Beat is ready", "detail": "the probe passes from your wallet" + (" (fragile)" if rs == "fragile" else ""),
			"doable": true, "blocker": "", "priority": 70})
	else:
		var why := String(snap.get("readiness_reason", rs))
		beat.merge({"title": "Beat: not yet", "detail": why, "doable": false, "blocker": why, "priority": 20})
	out.append(beat)

	# The room: speak when it is quiet; Join a covered room.
	if _has(snap, "room"):
		var room: Dictionary = snap["room"]
		var r := {"key": "room", "kind": "room", "anchor": "room", "call": "CHOA.Chat(QING, line)",
			"lore": "Every QING is a room. A line spoken here is written on the chain, and it is a reaction too."}
		var cover := _pia(room.get("cover"))
		if room.get("admitted") == false and room.get("cover") != null and not BigInt.is_zero(cover):
			r.merge({"title": "The door is closed to you", "detail": "Join: cover %s (asset), a day's admission" % TokenFormat.wei_to_tokens(cover),
				"call": "QING.Join(LAU)", "doable": id_block == "", "blocker": id_block, "priority": 55}, true)
			out.append(r)
		elif bool(room.get("loaded", false)):
			var last := int(room.get("last_block", -1))
			var head := int(room.get("head", -1))
			if last < 0:
				r.merge({"title": "The room is silent: speak", "detail": "no line in the history read", "priority": 60})
			elif head > 0 and head - last > QUIET_BLOCKS:
				r.merge({"title": "The room is quiet: speak", "detail": "last line at block %s" % TokenFormat.group(str(last)), "priority": 60})
			else:
				r.merge({"title": "The room is talking", "detail": "last line at block %s" % TokenFormat.group(str(last)), "priority": 25})
			r["doable"] = id_block == ""
			r["blocker"] = id_block
			out.append(r)

	# Crowns: pass the one above you, or hold your lead.
	if not me.is_empty() and has_omega and not BigInt.is_zero(omega):
		if int(me["rank"]) > 1 and int(me.get("gap_su", -1)) >= 0 and int(me["gap_su"]) <= REACH_MAX:
			out.append({"key": "crown", "kind": "crown", "anchor": "tower", "call": "CHEON.Su(QING)",
				"title": "Pass #%d in %s Su" % [int(me["rank"]) - 1, su_text(me["gap_su"])],
				"detail": "you are #%d of %d known players here (a floor)" % [me["rank"], me["players"]],
				"lore": "The skyline is the board. Each tower is one player's Hypobar here.",
				"doable": id_block == "", "blocker": id_block, "priority": 65})
		elif int(me["rank"]) == 1 and me.has("margin_su"):
			out.append({"key": "crown", "kind": "crown", "anchor": "tower", "call": "CHEON.Su(QING)",
				"title": "You hold the crown", "detail": "a rival needs %s Su to pass you" % su_text(me["margin_su"]),
				"lore": "The tallest tower carries the crown beacon. Bars never shrink, but others can grow past you.",
				"doable": id_block == "", "blocker": id_block, "priority": 35})

	# Neighbours beyond the force fields where you have no bars yet.
	if snap.get("neighbours") is Array:
		for nb in snap["neighbours"]:
			if nb.get("my_bars") != false:
				continue  # you have bars there, or that is unread
			var nom = nb.get("omega")
			var side := String(nb["side"])
			var good: bool = nom != null and not BigInt.is_zero(_pia(nom))
			out.append({"key": "border_" + side, "kind": "border", "anchor": "border_" + side,
				"call": "CHEON.Su(%s)" % String(nb.get("name", "")),
				"title": "Beyond the %s field: %s" % [Neighbours.NAMES.get(side, side), String(nb.get("name", "—"))],
				"detail": "no bars there yet · Ω there = %s" % (dec(nom) if nom != null else "—"),
				"lore": "The force fields are doors. Cross, and react with the land beyond.",
				"doable": true, "blocker": "", "priority": 45 if good else 15})

	# Wells: what this QING holds. A dry well is a fact about the land, not a call.
	if _has(snap, "wells"):
		var wells: Dictionary = snap["wells"]
		var dry := {"fornax": "Ω here is 0: no Hypobar per Su", "eris": "Charge base 0: Charge is 0 for everyone here",
			"tethys": "Dione 0: a future Code here pays no VITUS"}
		for k in ["fornax", "eris", "tethys"]:
			var v = wells.get(k)
			if v != null and BigInt.is_zero(_pia(v)):
				out.append({"key": "well_" + k, "kind": "well", "anchor": "well_" + k, "call": "%s.balanceOf(QING)" % k.capitalize(),
					"title": "The %s well is dry" % k.capitalize(), "detail": dry[k],
					"lore": "Anyone may send %s to this QING to fill it; its owner can withdraw it (GWAT = false). No call is offered here." % k.capitalize(),
					"doable": false, "blocker": "a fact, not a move", "priority": 12})

	out.sort_custom(func(a, b): return int(a["priority"]) > int(b["priority"]))
	return out.slice(0, MAX_ACTS)


# --- Goals --------------------------------------------------------------------------

## Pure: personal goals, each derived from chain reads and saying which.
## [{key, text, source}]
static func goals(snap: Dictionary) -> Array:
	var out: Array = []
	var wallet := String(snap.get("wallet", ""))
	var has_omega := _has(snap, "omega")
	var omega := _pia(snap.get("omega"))
	if _has(snap, "total_hypo"):
		var g := tier_goal(_pia(snap["total_hypo"]), omega)
		if not g.is_empty():
			var su := " (%s Su at Ω)" % su_text(g["su"]) if has_omega and int(g["su"]) >= 0 else (" (Ω = 0 here)" if has_omega else "")
			out.append({"key": "tier", "text": "Reach %s: %s Hypobar to go%s" % [Development.tier_name(g["next"]), dec(g["need"]), su],
				"source": "Σ YUE.Bar(QING) over known players (a floor)"})
		else:
			out.append({"key": "tier", "text": "This land is a Capital", "source": "Σ YUE.Bar(QING)"})
	else:
		out.append({"key": "tier", "text": "Next tier: —", "source": "Σ YUE.Bar(QING) not read"})
	if wallet != "" and _has(snap, "board"):
		var me := rank_of(snap["board"], wallet, omega)
		if int(me["rank"]) == 0:
			out.append({"key": "tower", "text": "Your tower here: not built (no bars)", "source": "YUE.Bar(QING)"})
		else:
			var tg := tower_goal(me["mine"], omega)
			var nxt := " · next floor in %s Su" % su_text(tg["su_next"]) if int(tg["su_next"]) > 0 else ""
			out.append({"key": "tower", "text": "Your tower: %d floor%s, %s Hypobar · #%d%s" % [tg["floors"], "" if tg["floors"] == 1 else "s",
				dec(me["mine"]), me["rank"], nxt], "source": "YUE.Bar(QING) vs known players (a floor)"})
	if _has(snap, "streak"):
		var s: Dictionary = snap["streak"]
		var left := int(s.get("seconds_left", -1))
		var today := "today done ✓" if bool(s.get("today_done", false)) else ("today: %dh %02dm left" % [left / 3600, (left % 3600) / 60] if left >= 0 else "today: not yet")
		out.append({"key": "streak", "text": "Streak %d day%s (best %d) · %s" % [int(s.get("current", 0)), "" if int(s.get("current", 0)) == 1 else "s",
			int(s.get("best", 0)), today], "source": "YUE mint logs (DysnomiaTime days)"})
	elif wallet != "":
		out.append({"key": "streak", "text": "Streak: —", "source": "YUE mint logs not read"})
	var bc := int(snap.get("bars_count", -1))
	if bc >= 0:
		var gear := "a spark at 3" if bc < 3 else ("an orbit ring at 10" if bc < 10 else "spark and orbit ring")
		out.append({"key": "reach", "text": "Bars at %d territor%s · %s" % [bc, "y" if bc == 1 else "ies", gear if bc >= 10 else "next: " + gear],
			"source": "YUE.Bar(QING) at every territory"})
	return out


## Pure: the measured change after a confirmed Su (from YUE.Bar re-read at the
## receipt's block): {d_hypo, floors_before, floors_after, text}.
static func su_outcome(before: PackedInt64Array, after: PackedInt64Array, d_epi: PackedInt64Array, block: int) -> Dictionary:
	var d := BigInt.sub(after, before) if BigInt.cmp(after, before) >= 0 else PackedInt64Array()
	var fb := BarColumns.floors_for(before)
	var fa := BarColumns.floors_for(after)
	var t := "+%s Hypobar · +%s Epibar" % [dec(d), dec(d_epi)]
	if fa > fb:
		t += " · your tower +%d floor%s (%d → %d)" % [fa - fb, "" if fa - fb == 1 else "s", fb, fa]
	return {"d_hypo": d, "floors_before": fb, "floors_after": fa, "text": t + " · block %d" % block}
