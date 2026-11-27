class_name AwayDiff
extends RefCounted
## "While you were away": what really changed for a wallet since its last visit
## on this computer. Pure (no network): AwayRead does the reads, AwayStore keeps
## the baseline in user://, Alerts and AwayCard show the card.
##
## The baseline (one per wallet, written at each visit; numbers as decimal strings):
##   {v, block (the chain head at that visit), at (unix s), lau, name,
##    rooms:    {qing: {seen: block read up to, last: newest line block known (-1 unknown)}},
##    qings:    {qing: {hypo: Σ YUE.Bar(QING).Hypobar, tier, lead, block}},
##    bars:     {qing: [hypobar, epibar]} (this wallet's YUE.Bar), bars_block,
##    registry: {count, cursor (NewQing logs read to this block)}}
## A read of now (AwayRead.read) has the same sections, each with an ok flag, plus
## the new room lines (room_lines: {qing: [ChatLog line]}) and the new QINGs.
##
## Rules (CLAUDE.md, LEARNINGS §10): only what really changed is listed, each with
## its block or tx; a section whose read failed shows "—" and keeps its old
## baseline (an outage is never stored); nothing changed is one calm "Quiet since
## block N" line; the first visit has no card (nothing to compare), it only stores
## the baseline. Your own lines are never news (same Aura = the same creator wallet).

const VERSION := 1
const MENTIONS_MAX := 6
const ROOMS_MAX := 8
const NEW_QINGS_SHOWN := 3


# --- Who "you" are, for lines -------------------------------------------------------

## {name, aura, soul, wallet} from a PlayerState-like object (or {}).
static func me_of(ps, wallet: String = "") -> Dictionary:
	if ps == null:
		return {"name": "", "aura": "", "soul": "", "wallet": wallet.to_lower()}
	return {"name": String(ps.username), "aura": String(ps.aura), "soul": String(ps.soul),
		"wallet": (wallet if wallet != "" else String(ps.wallet)).to_lower()}


## Whether a line is one of yours: the speaking LAU's Aura is uint160(creator) %
## Motzkin (the same for every LAU this wallet made), else the resolved tx.from, else
## (site lines carry no Aura) the same Soul.
static func is_own(l: Dictionary, me: Dictionary) -> bool:
	var aura := String(l.get("aura", ""))
	if aura != "" and String(me.get("aura", "")) != "":
		return aura == String(me["aura"])
	var w := String(l.get("wallet", "")).to_lower()
	if w != "" and String(me.get("wallet", "")) != "":
		return w == String(me["wallet"])
	var soul := String(l.get("soul", ""))
	return soul != "" and soul == String(me.get("soul", ""))


## A new line names you (not one of yours).
static func names_you(l: Dictionary, me: Dictionary) -> bool:
	var nm := String(me.get("name", ""))
	return nm != "" and not is_own(l, me) and ChatLines.mentions(String(l.get("text", "")), nm)


# --- The card ------------------------------------------------------------------------

## The card from the stored baseline `prev` and the read `now`. `names` maps a QING
## to its name (else the short address). Returns
## {first, since, at, block, entries: [{kind, title, sub, block, tx, qing, go}], fails: [text], quiet, preview}.
static func compute(prev: Dictionary, now: Dictionary, me: Dictionary, names: Dictionary = {}) -> Dictionary:
	var card := {"first": prev.is_empty(), "since": int(prev.get("block", -1)), "at": int(prev.get("at", 0)),
		"block": int(now.get("block", -1)), "entries": [], "fails": [], "quiet": false, "preview": bool(prev.get("preview", false))}
	if card["first"]:
		return card
	var entries: Array = card["entries"]
	var fails: Array = card["fails"]
	if int(now.get("block", -1)) < 0:
		fails.append("The chain could not be read: — (nothing compared)")
		return card
	_rooms(prev, now, me, names, entries, fails)
	_qings(prev, now, names, entries, fails)
	_bars(prev, now, names, entries, fails)
	_registry(prev, now, entries, fails)
	card["quiet"] = entries.is_empty() and fails.is_empty()
	return card


static func _name(q: String, names: Dictionary) -> String:
	var n := String(names.get(q, ""))
	return n if n != "" else NetProto.short_wallet(q)


static func g(d: String) -> String:
	return TokenFormat.group(d) if d != "" else "—"


## A stored decimal → BigInt; anything that is not plain digits reads as 0 (a
## damaged file must not crash the card).
static func dec(s: String) -> PackedInt64Array:
	s = s.strip_edges()
	return BigInt.from_decimal(s) if _digits(s) else BigInt.zero()


static func _digits(s: String) -> bool:
	for ch in s:
		if ch < "0" or ch > "9":
			return false
	return s != ""


static func _rooms(prev: Dictionary, now: Dictionary, me: Dictionary, names: Dictionary, entries: Array, fails: Array) -> void:
	var room_list: Array = now.get("rooms_list", [])
	if not bool(now.get("rooms_ok", false)):
		if not room_list.is_empty():
			fails.append("New lines in your %d room%s: — (%s)" % [room_list.size(), "" if room_list.size() == 1 else "s",
				String(now.get("rooms_error", "the log read failed"))])
		return
	var by_room: Dictionary = now.get("room_lines", {})
	var mentions: Array = []
	var rooms: Array = []
	for q in by_room:
		var since := room_seen(prev, q)
		var others: Array = []
		for l in by_room[q]:
			if int(l.get("block", -1)) <= since or is_own(l, me):
				continue
			others.append(l)
			if names_you(l, me):
				mentions.append([q, l])
		if others.is_empty():
			continue
		var latest: Dictionary = others[others.size() - 1]
		rooms.append({"kind": "room", "qing": q, "count": others.size(),
			"title": "%d new line%s in %s" % [others.size(), "" if others.size() == 1 else "s", _name(q, names)],
			"sub": "latest %s · block %s" % [ChatLines.compact(latest, 70), g(str(int(latest["block"])))],
			"block": int(latest["block"]), "tx": String(latest.get("tx", "")),
			"go": {"to": "line", "qing": q, "key": ChatLines.key(latest), "block": int(latest["block"])}})
	mentions.sort_custom(func(a, b): return int(a[1]["block"]) > int(b[1]["block"]))
	for m in mentions.slice(0, MENTIONS_MAX):
		var l: Dictionary = m[1]
		entries.append({"kind": "mention", "qing": m[0],
			"title": "%s named you in %s" % [ChatLines.speaker(l), _name(m[0], names)],
			"sub": "“%s” · block %s · tx %s" % [ChatLines.clean_text(String(l.get("text", "")), 70), g(str(int(l["block"]))), _short_tx(String(l.get("tx", "")))],
			"block": int(l["block"]), "tx": String(l.get("tx", "")),
			"go": {"to": "line", "qing": m[0], "key": ChatLines.key(l), "block": int(l["block"])}})
	if mentions.size() > MENTIONS_MAX:
		entries.append({"kind": "more", "title": "+%d more mention%s" % [mentions.size() - MENTIONS_MAX, "" if mentions.size() - MENTIONS_MAX == 1 else "s"],
			"sub": "in the room histories", "block": -1, "tx": "", "go": {}})
	rooms.sort_custom(func(a, b): return a["count"] > b["count"] or (a["count"] == b["count"] and a["block"] > b["block"]))
	for r in rooms.slice(0, ROOMS_MAX):
		entries.append(r)
	if rooms.size() > ROOMS_MAX:
		var n := 0
		for r in rooms.slice(ROOMS_MAX):
			n += int(r["count"])
		entries.append({"kind": "more", "title": "+%d line%s in %d more room%s" % [n, "" if n == 1 else "s", rooms.size() - ROOMS_MAX, "" if rooms.size() - ROOMS_MAX == 1 else "s"],
			"sub": "", "block": -1, "tx": "", "go": {}})


static func _short_tx(tx: String) -> String:
	return (tx.left(10) + "…") if tx.length() > 12 else (tx if tx != "" else "—")


## The block a room's lines were read up to at the last visit.
static func room_seen(prev: Dictionary, q: String) -> int:
	var r = prev.get("rooms", {}).get(q)
	if r is Dictionary and int(r.get("seen", -1)) > 0:
		return int(r["seen"])
	return int(prev.get("block", -1))


static func _qings(prev: Dictionary, now: Dictionary, names: Dictionary, entries: Array, fails: Array) -> void:
	var nq: Dictionary = now.get("qings", {})
	var pq: Dictionary = prev.get("qings", {})
	var failed: Array = now.get("qings_failed", [])
	if not bool(now.get("qings_ok", false)) and nq.is_empty():
		if not failed.is_empty():
			fails.append("Hypobar of your %d QING%s: — (%s)" % [failed.size(), "" if failed.size() == 1 else "s", String(now.get("qings_error", "the read failed"))])
		return
	if not failed.is_empty():
		fails.append("Hypobar at %s: —" % ", ".join(failed.slice(0, 3).map(func(q): return _name(q, names))) + (" and %d more" % (failed.size() - 3) if failed.size() > 3 else ""))
	var then_failed: Array = prev.get("qings_failed", []).filter(func(q): return nq.has(q))
	if not then_failed.is_empty():
		fails.append("Hypobar growth at %s: — (the board at block %s could not be read)" % [", ".join(then_failed.slice(0, 3).map(func(q): return _name(q, names))) + (" and %d more" % (then_failed.size() - 3) if then_failed.size() > 3 else ""), g(str(int(prev.get("block", -1))))])
	var leads: Array = []
	var growth: Array = []
	for q in nq:
		if not pq.has(q):
			continue  # newly followed: nothing to compare with
		var a: Dictionary = pq[q]
		var b: Dictionary = nq[q]
		var blk := int(b.get("block", now.get("block", -1)))
		var src := "Σ YUE.Bar(QING) over known players · block %s → %s" % [g(str(int(a.get("block", prev.get("block", -1))))), g(str(blk))]
		if bool(a.get("lead", false)) != bool(b.get("lead", false)):
			var lost := bool(a.get("lead", false))
			leads.append({"kind": "lead_lost" if lost else "lead_gained", "qing": q,
				"title": ("You lost the lead at %s" if lost else "You took the lead at %s") % _name(q, names),
				"sub": "YUE.Bar(QING) of every known player · block %s" % g(str(blk)), "block": blk, "tx": "", "go": {"to": "qing", "qing": q}})
		var ha := dec(String(a.get("hypo", "0")))
		var hb := dec(String(b.get("hypo", "0")))
		if BigInt.cmp(hb, ha) <= 0:
			continue
		var d := BigInt.to_decimal(BigInt.sub(hb, ha))
		var ta := int(a.get("tier", Development.tier_of(ha)))
		var tb := int(b.get("tier", Development.tier_of(hb)))
		var e := {"qing": q, "block": blk, "tx": "", "go": {"to": "qing", "qing": q}, "d": hb}
		if tb > ta:
			e["kind"] = "tier"
			e["title"] = "%s grew to %s (from %s)" % [_name(q, names), Development.tier_name(tb), Development.tier_name(ta)]
		else:
			e["kind"] = "hypo"
			e["title"] = "%s: Hypobar +%s" % [_name(q, names), g(d)]
		e["sub"] = "Hypobar %s → %s · %s" % [g(String(a.get("hypo", ""))), g(String(b.get("hypo", ""))), src]
		growth.append(e)
	growth.sort_custom(func(x, y): return (x["kind"] == "tier" and y["kind"] != "tier") or (x["kind"] == y["kind"] and BigInt.cmp(x["d"], y["d"]) > 0))
	for e in leads + growth:
		e.erase("d")
		entries.append(e)


static func _bars(prev: Dictionary, now: Dictionary, names: Dictionary, entries: Array, fails: Array) -> void:
	if not bool(now.get("bars_ok", false)):
		if String(now.get("lau", "")) != "" or not now.get("bars", {}).is_empty():
			fails.append("Your bars (YUE.Bar): — (%s)" % String(now.get("bars_error", "the read failed")))
		return
	if int(prev.get("bars_block", -1)) <= 0:
		return  # never read at the last visit: nothing to compare with
	var nb: Dictionary = now.get("bars", {})
	var pb: Dictionary = prev.get("bars", {})
	var out: Array = []
	for q in nb:
		var b: Array = nb[q]
		var a: Array = pb.get(q, ["0", "0"])
		var hb := dec(String(b[0]))
		var ha := dec(String(a[0]))
		var eb := dec(String(b[1]))
		var ea := dec(String(a[1]))
		var up_h := BigInt.cmp(hb, ha) > 0
		var up_e := BigInt.cmp(eb, ea) > 0
		if not up_h and not up_e:
			continue  # bars only grow: equal is no news (and a lower read is not news either)
		var dh := BigInt.sub(hb, ha) if up_h else BigInt.zero()
		var de := BigInt.sub(eb, ea) if up_e else BigInt.zero()
		var parts: PackedStringArray = []
		if up_h:
			parts.append("Hypobar +%s" % g(BigInt.to_decimal(dh)))
		if up_e:
			parts.append("Epibar +%s" % g(BigInt.to_decimal(de)))
		out.append({"kind": "bars", "qing": q, "d": dh,
			"title": ("Your bars at %s: %s" if pb.has(q) else "Your first bars at %s: %s") % [_name(q, names), " · ".join(parts)],
			"sub": "YUE.Bar(QING) · block %s → %s" % [g(str(int(prev.get("bars_block", -1)))), g(str(int(now.get("bars_block", -1))))],
			"block": int(now.get("bars_block", -1)), "tx": "", "go": {"to": "qing", "qing": q}})
	out.sort_custom(func(x, y): return BigInt.cmp(x["d"], y["d"]) > 0)
	for e in out:
		e.erase("d")
		entries.append(e)


static func _registry(prev: Dictionary, now: Dictionary, entries: Array, fails: Array) -> void:
	var fresh: Array = now.get("new_qings", [])
	var cursor := int(now.get("registry", {}).get("cursor", -1))
	if not bool(now.get("registry_ok", false)):
		if fresh.is_empty():
			fails.append("New QINGs (NewQing logs on MAP): — (%s)" % String(now.get("registry_error", "the log read failed")))
			return
	if fresh.is_empty():
		return
	var newest: Array = fresh.duplicate()
	newest.sort_custom(func(a, b): return int(a["block"]) > int(b["block"]))
	var shown: PackedStringArray = []
	for r in newest.slice(0, NEW_QINGS_SHOWN):
		shown.append("%s (block %s)" % [String(r.get("name", "")) if String(r.get("name", "")) != "" else NetProto.short_wallet(String(r["address"])), g(str(int(r["block"])))])
	var floor := not bool(now.get("registry_ok", false))
	entries.append({"kind": "new_qings", "qing": String(newest[0]["address"]),
		"title": "%d%s new QING%s founded" % [fresh.size(), "+" if floor else "", "" if fresh.size() == 1 else "s"],
		"sub": "newest %s · NewQing logs read to block %s%s" % [", ".join(shown), g(str(cursor)), " (the read stopped: a floor)" if floor else ""],
		"block": int(newest[0]["block"]), "tx": String(newest[0].get("tx_hash", "")), "go": {"to": "qing", "qing": String(newest[0]["address"])}})


# --- Words ----------------------------------------------------------------------------

## "since your last visit on this computer (block 28,140,001)".
static func since_text(card: Dictionary) -> String:
	var b := int(card.get("since", -1))
	if bool(card.get("preview", false)):
		return "since block %s (PREVIEW: the values at that block read from the chain, not a stored visit)" % g(str(b))
	return "since your last visit on this computer (block %s)" % g(str(b))


## The calm line when nothing changed.
static func quiet_text(card: Dictionary) -> String:
	return "Quiet since block %s: nothing new in your rooms, QINGs, bars or the registry." % g(str(int(card.get("since", -1))))


## Roughly how long ago, from the blocks (≈ 8,400 a day).
static func ago_text(card: Dictionary) -> String:
	return ChatLines.age_text(int(card.get("since", -1)), int(card.get("block", -1)))


## Plain lines (the live tool, logs).
static func lines(card: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if bool(card.get("first", false)):
		out.append("First visit on this computer: no card (nothing to compare); the baseline is stored.")
		return out
	out.append("WHILE YOU WERE AWAY · %s · ≈ %s ago · now block %s" % [since_text(card), ago_text(card), g(str(int(card.get("block", -1))))])
	if bool(card.get("quiet", false)):
		out.append("  " + quiet_text(card))
	for e in card.get("entries", []):
		out.append("  [%s] %s" % [e["kind"], e["title"]])
		if String(e.get("sub", "")) != "":
			out.append("        %s" % e["sub"])
	for f in card.get("fails", []):
		out.append("  [—] %s" % f)
	return out


# --- The next baseline -------------------------------------------------------------------

## What to store after a visit's read: `prev` with each section that read OK
## replaced by now's values. A failed section keeps its old values (never store an outage).
static func next_baseline(prev: Dictionary, now: Dictionary, at_unix: int = 0) -> Dictionary:
	var b: Dictionary = prev.duplicate(true)
	b.erase("preview")
	b.erase("qings_failed")
	b["v"] = VERSION
	var head := int(now.get("block", -1))
	if head > 0:
		b["block"] = head
	if at_unix > 0:
		b["at"] = at_unix
	if String(now.get("lau", "")) != "":
		b["lau"] = String(now["lau"])
		b["name"] = String(now.get("name", ""))
	var rooms: Dictionary = b.get("rooms", {})
	for q in now.get("rooms_list", []):
		var r: Dictionary = rooms.get(q, {"seen": int(prev.get("block", head)) if not prev.is_empty() else head, "last": -1})
		if bool(now.get("rooms_ok", false)) and int(now.get("rooms_to", -1)) > 0:
			r["seen"] = maxi(int(r.get("seen", -1)), int(now["rooms_to"]))
			for l in now.get("room_lines", {}).get(q, []):
				r["last"] = maxi(int(r.get("last", -1)), int(l.get("block", -1)))
		rooms[q] = r
	b["rooms"] = rooms
	if bool(now.get("qings_ok", false)) or not now.get("qings", {}).is_empty():
		var qs: Dictionary = b.get("qings", {})
		for q in now.get("qings", {}):
			qs[q] = (now["qings"][q] as Dictionary).duplicate()
		b["qings"] = qs
	if bool(now.get("bars_ok", false)):
		b["bars"] = (now.get("bars", {}) as Dictionary).duplicate(true)
		b["bars_block"] = int(now.get("bars_block", head))
	if bool(now.get("registry_ok", false)):
		b["registry"] = (now.get("registry", {}) as Dictionary).duplicate()
	return b


## During a visit: the rooms in `qings` were read up to `to_block`; `lines` (any
## rooms) are the new lines seen. Returns the updated baseline.
static func with_rooms_seen(base: Dictionary, qings: Array, to_block: int, lines: Array = []) -> Dictionary:
	if base.is_empty() or to_block <= 0:
		return base
	var rooms: Dictionary = base.get("rooms", {})
	for q in qings:
		var r: Dictionary = rooms.get(q, {"seen": -1, "last": -1})
		r["seen"] = maxi(int(r.get("seen", -1)), to_block)
		rooms[q] = r
	for l in lines:
		var q := String(l.get("qing", ""))
		if rooms.has(q):
			rooms[q]["last"] = maxi(int(rooms[q].get("last", -1)), int(l.get("block", -1)))
	base["rooms"] = rooms
	base["block"] = maxi(int(base.get("block", -1)), to_block)
	return base


## During a visit: this wallet's bars were read at `block` ({qing: [hypo, epi]} as decimals).
static func with_bars(base: Dictionary, bars: Dictionary, block: int) -> Dictionary:
	if base.is_empty() or block <= int(base.get("bars_block", -1)):
		return base
	base["bars"] = bars.duplicate(true)
	base["bars_block"] = block
	base["block"] = maxi(int(base.get("block", -1)), block)
	return base


## During a visit: territory totals read at their blocks (only the QINGs that read OK).
static func with_qings(base: Dictionary, qings: Dictionary) -> Dictionary:
	if base.is_empty():
		return base
	var qs: Dictionary = base.get("qings", {})
	for q in qings:
		qs[q] = (qings[q] as Dictionary).duplicate()
	base["qings"] = qs
	return base


## During a visit: the registry was read to `cursor` and holds `count` QINGs.
static func with_registry(base: Dictionary, count: int, cursor: int) -> Dictionary:
	if base.is_empty() or cursor <= int(base.get("registry", {}).get("cursor", -1)):
		return base
	base["registry"] = {"count": count, "cursor": cursor}
	return base


## Session.bars ({qing: [PackedInt64Array hypo, epi]}) → decimals for the baseline.
static func bars_dec(bars: Dictionary) -> Dictionary:
	var out := {}
	for q in bars:
		var v: Array = bars[q]
		out[String(q).to_lower()] = [BigInt.to_decimal(BigInt.coerce(v[0])), BigInt.to_decimal(BigInt.coerce(v[1]))]
	return out
