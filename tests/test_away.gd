extends TestCase
## "While you were away" and the alerts, with no network: the card's diff (what
## changed, "—" on a failed read, the first visit, a quiet stretch), the next
## baseline, the store, the alert gate (merging, pacing), the prefs, and mention
## matching folded the way the site folds names.

const Q1 := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
const Q2 := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const Q3 := "0x1299bbac80f7038c19c20843f80608bd80c14a74"
const ME := {"name": "enteh", "aura": "777", "soul": "5", "wallet": "0x18f621662d6a1f23700ea32d146b32195dc33111"}
const NAMES := {Q1: "RatKing QING", Q2: "Illinois Coin QING", Q3: "MrStu QING"}


func _line(q: String, block: int, name: String, text: String, aura: String = "1", li: int = 0) -> Dictionary:
	return {"tx": "0x%064x" % block, "log_index": li, "block": block, "name": name, "text": text, "soul": "9", "aura": aura,
		"badge": "", "qing": q, "source": "chain"}


func _prev() -> Dictionary:
	return {"v": AwayDiff.VERSION, "block": 1000, "at": 1700000000, "lau": "0xlau", "name": "enteh",
		"rooms": {Q1: {"seen": 1000, "last": 900}, Q2: {"seen": 1000, "last": -1}},
		"qings": {Q1: {"hypo": "5000", "tier": Development.tier_of(BigInt.from_int(5000)), "lead": true, "block": 1000},
			Q2: {"hypo": "26", "tier": Development.tier_of(BigInt.from_int(26)), "lead": false, "block": 1000}},
		"bars": {Q1: ["4000", "10"]}, "bars_block": 1000, "registry": {"count": 940, "cursor": 1000}}


func _now_quiet() -> Dictionary:
	return {"block": 2000, "lau": "0xlau", "name": "enteh", "aura": "777", "soul": "5",
		"bars_ok": true, "bars": {Q1: ["4000", "10"]}, "bars_block": 2000,
		"rooms_list": [Q1, Q2], "rooms_ok": true, "room_lines": {}, "rooms_to": 2000,
		"qings_ok": true, "qings": {Q1: {"hypo": "5000", "tier": 3, "lead": true, "block": 2000}, Q2: {"hypo": "26", "tier": 1, "lead": false, "block": 2000}},
		"qings_failed": [], "registry_ok": true, "registry": {"count": 940, "cursor": 2000}, "new_qings": []}


func test_first_visit_has_no_card() -> void:
	var c := AwayDiff.compute({}, _now_quiet(), ME, NAMES)
	check(c["first"], "nothing to compare")
	eq(c["entries"].size(), 0)
	eq(c["fails"].size(), 0)
	var b := AwayDiff.next_baseline({}, _now_quiet(), 1700000500)
	eq(int(b["block"]), 2000, "the baseline is the visit's block")
	eq(int(b["rooms"][Q1]["seen"]), 2000, "rooms seen up to the head")
	eq(b["bars"], {Q1: ["4000", "10"]})
	eq(int(b["at"]), 1700000500)


func test_quiet_is_one_calm_line() -> void:
	var c := AwayDiff.compute(_prev(), _now_quiet(), ME, NAMES)
	check(not c["first"])
	check(c["quiet"], "nothing changed")
	eq(c["entries"].size(), 0)
	check(AwayDiff.quiet_text(c).begins_with("Quiet since block 1,000"))
	check(AwayDiff.since_text(c).contains("since your last visit on this computer (block 1,000)"))


func test_what_changed_is_listed_with_blocks() -> void:
	var now := _now_quiet()
	now["room_lines"] = {
		Q1: [_line(Q1, 1500, "Lucy", "gm Enteh, you up?"), _line(Q1, 1600, "Bob", "anyone home"), _line(Q1, 1700, "enteh", "my own line", "777")],
		Q2: [_line(Q2, 900, "Old", "before the visit")],
	}
	now["qings"][Q1] = {"hypo": "150000", "tier": Development.tier_of(BigInt.from_int(150000)), "lead": false, "block": 2000}
	now["qings"][Q2] = {"hypo": "40", "tier": Development.tier_of(BigInt.from_int(40)), "lead": false, "block": 2000}
	now["bars"] = {Q1: ["4875", "10"], Q3: ["66", "3"]}
	now["new_qings"] = [{"address": "0xaaaa000000000000000000000000000000000001", "name": "New One QING", "block": 1800}]
	var c := AwayDiff.compute(_prev(), now, ME, NAMES)
	check(not c["quiet"])
	var kinds: Array = c["entries"].map(func(e): return e["kind"])
	eq(kinds[0], "mention", "mentions first")
	check(kinds.has("room"))
	check(kinds.has("lead_lost"), "the lead at RatKing was lost")
	check(kinds.has("tier") or kinds.has("hypo"))
	check(kinds.has("bars"))
	check(kinds.has("new_qings"))
	var room: Dictionary = c["entries"].filter(func(e): return e["kind"] == "room")[0]
	eq(int(room["count"]), 2, "two lines by others (the own line and the old one are not news)")
	check(room["title"].contains("RatKing QING"))
	eq(int(room["block"]), 1600, "the latest line's block")
	eq(room["go"]["to"], "line")
	var m: Dictionary = c["entries"][0]
	check(m["title"].begins_with("Lucy named you"))
	check(m["sub"].contains("block 1,500"))
	eq(m["go"]["key"], ChatLines.key(now["room_lines"][Q1][0]))
	for e in c["entries"]:
		check(int(e.get("block", -1)) > 0 or String(e.get("tx", "")) != "" or e["kind"] == "more", "%s carries its block or tx" % e["kind"])
	var bars: Array = c["entries"].filter(func(e): return e["kind"] == "bars")
	eq(bars.size(), 2)
	check(bars[0]["title"].contains("Hypobar +875"), "measured: 4,000 → 4,875")
	check(bars[1]["title"].begins_with("Your first bars at MrStu QING"))
	eq(c["fails"].size(), 0)


func test_a_failed_read_shows_a_dash_and_keeps_its_baseline() -> void:
	var now := _now_quiet()
	now["rooms_ok"] = false
	now["rooms_error"] = "eth_getLogs stopped at block 1500"
	now["room_lines"] = {}
	now["bars_ok"] = false
	now["bars"] = {}
	now["registry_ok"] = false
	var c := AwayDiff.compute(_prev(), now, ME, NAMES)
	check(not c["quiet"], "a failure is not quiet")
	eq(c["entries"].size(), 0)
	eq(c["fails"].size(), 3)
	for f in c["fails"]:
		check(String(f).contains("—"), "a failed read shows —: %s" % f)
	var b := AwayDiff.next_baseline(_prev(), now, 1)
	eq(int(b["rooms"][Q1]["seen"]), 1000, "rooms not read: their old point stays")
	eq(b["bars"], {Q1: ["4000", "10"]}, "bars not read: the old ones stay (an outage is never stored)")
	eq(int(b["bars_block"]), 1000)
	eq(int(b["registry"]["cursor"]), 1000)
	eq(int(b["block"]), 2000)


func test_a_board_unread_at_the_last_visit_says_so() -> void:
	var p := _prev()
	p["qings"].erase(Q2)
	p["qings_failed"] = [Q2]
	var c := AwayDiff.compute(p, _now_quiet(), ME, NAMES)
	eq(c["fails"].size(), 1)
	check(String(c["fails"][0]).begins_with("Hypobar growth at Illinois Coin QING: —"))
	check(not AwayDiff.next_baseline(p, _now_quiet()).has("qings_failed"), "not carried into the next baseline")


func test_no_head_compares_nothing() -> void:
	var c := AwayDiff.compute(_prev(), {"block": -1}, ME, NAMES)
	eq(c["entries"].size(), 0)
	eq(c["fails"].size(), 1)
	check(String(c["fails"][0]).contains("—"))
	check(not c["quiet"])


func test_own_lines_and_mentions() -> void:
	check(AwayDiff.is_own(_line(Q1, 1, "anyone", "x", "777"), ME), "same Aura = the same creator wallet")
	check(not AwayDiff.is_own(_line(Q1, 1, "enteh", "x", "1"), ME), "the same name from another creator is not you")
	var site := {"tx": "0x1", "block": 5, "name": "x", "text": "gm enteh", "soul": "5", "aura": "", "source": "site"}
	check(AwayDiff.is_own(site, ME), "no Aura (site line): the Soul decides")
	check(AwayDiff.names_you(_line(Q1, 1, "Lucy", "@ENTEH look"), ME))
	check(not AwayDiff.names_you(_line(Q1, 1, "enteh", "enteh here", "777"), ME), "your own line never names you")
	check(not AwayDiff.names_you(_line(Q1, 1, "Lucy", "gm all"), ME))
	check(not AwayDiff.names_you(_line(Q1, 1, "Lucy", "gm enteh"), {"name": "", "aura": "", "soul": ""}), "no name: no mention")


func test_mentions_fold_like_the_site() -> void:
	check(ChatLines.mentions("gm ratklng", "RatKing"), "I/l fold (names of 3+ letters)")
	check(ChatLines.mentions("@ЕNТЕН look", "enteh"), "Cyrillic lookalikes")
	check(ChatLines.mentions("hey en​teh!", "enteh"), "an invisible character inside")
	check(ChatLines.mentions("yo, PULSEPUNK…", "PulsePunk"), "punctuation around the word")
	check(ChatLines.mentions("thanks enter teh!", "enter teh"), "a two-word name")
	check(not ChatLines.mentions("enteh1 is not me", "enteh"), "a longer word is still another name")
	check(not ChatLines.mentions("entehs", "enteh"))
	check(not ChatLines.mentions("x", "x"), "one-letter names never match")
	check(ChatLines.mentions("io!", "io"), "two-letter names: case only")


func test_room_seen_falls_back_to_the_visit() -> void:
	var p := _prev()
	eq(AwayDiff.room_seen(p, Q1), 1000)
	eq(AwayDiff.room_seen(p, Q3), 1000, "a room not followed then: since the visit")
	p["rooms"][Q1]["seen"] = 1800
	var now := _now_quiet()
	now["room_lines"] = {Q1: [_line(Q1, 1500, "Lucy", "read already"), _line(Q1, 1900, "Lucy", "new")]}
	var c := AwayDiff.compute(p, now, ME, NAMES)
	eq(int(c["entries"][0]["count"]), 1, "lines up to the room's own point were seen during the visit")


func test_during_the_visit_the_baseline_moves() -> void:
	var b := _prev()
	b = AwayDiff.with_rooms_seen(b, [Q1, Q2], 2500, [_line(Q1, 2400, "x", "y")])
	eq(int(b["rooms"][Q1]["seen"]), 2500)
	eq(int(b["rooms"][Q1]["last"]), 2400)
	eq(int(b["block"]), 2500)
	b = AwayDiff.with_bars(b, {Q1: ["5000", "11"]}, 2600)
	eq(int(b["bars_block"]), 2600)
	var same := AwayDiff.with_bars(b.duplicate(true), {Q1: ["1", "1"]}, 2500)
	eq(same["bars"], {Q1: ["5000", "11"]}, "an older read never replaces a newer one")
	b = AwayDiff.with_registry(b, 941, 2700)
	eq(int(b["registry"]["count"]), 941)
	eq(AwayDiff.bars_dec({Q1: [BigInt.from_int(12), BigInt.from_int(3)]}), {Q1: ["12", "3"]})


func test_split_lines_keeps_only_the_rooms_own_logs() -> void:
	var data := Abi.encode(["string", "uint64", "uint64", "string"], ["Lucy", "9", "1", "gm enteh"])
	var logs := [
		{"address": Q1, "blockNumber": "0x%x" % 1500, "logIndex": "0x0", "transactionHash": "0xaa", "data": data},
		{"address": "0x000000000000000000000000000000000000dead", "blockNumber": "0x%x" % 1500, "logIndex": "0x1", "transactionHash": "0xab", "data": data},
		{"address": Q2, "blockNumber": "0x%x" % 900, "logIndex": "0x0", "transactionHash": "0xac", "data": data},
	]
	var by := AwayRead.split_lines(logs, [Q1, Q2], _prev())
	eq(by.keys(), [Q1], "another emitter is ignored; Q2's line is older than the visit")
	eq(String(by[Q1][0]["text"]), "gm enteh")


func test_rooms_for_orders_by_your_bars() -> void:
	var rows := [{"address": Q3, "creator": ME["wallet"]}, {"address": Q2, "creator": "0x0"}]
	var r := AwayRead.rooms_for(ME["wallet"], {Q2: ["10", "0"], Q1: ["900", "1"]}, {"rooms": {"0xbbbb000000000000000000000000000000000002": {}}}, rows)
	eq(r, [Q1, Q2, Q3, "0xbbbb000000000000000000000000000000000002"], "biggest bars, then founded, then last visit's")


func test_store_round_trip() -> void:
	var path := "user://test_away.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	eq(AwayStore.load_for(ME["wallet"], path), {}, "nothing stored: a first visit")
	check(AwayStore.save_for(ME["wallet"].to_upper().replace("0X", "0x"), _prev(), path))
	eq(int(AwayStore.load_for(ME["wallet"], path)["block"]), 1000, "keyed by the lower-cased wallet")
	var pv := _prev()
	pv["preview"] = true
	check(not AwayStore.save_for(ME["wallet"], pv, path), "a preview is never stored")
	check(not AwayStore.save_for(ME["wallet"], {"v": 1, "block": -1}, path), "no block, no baseline")
	AwayStore.forget(ME["wallet"], path)
	eq(AwayStore.load_for(ME["wallet"], path), {})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_damaged_numbers_do_not_crash() -> void:
	var p := _prev()
	p["bars"] = {Q1: ["12abc", "x"]}
	var now := _now_quiet()
	var c := AwayDiff.compute(p, now, ME, NAMES)
	eq(c["entries"].filter(func(e): return e["kind"] == "bars").size(), 1, "a damaged old value reads as 0")


# --- Alerts: merging and pacing ---------------------------------------------------------------

func _mention(q: String, who: String, text: String) -> Dictionary:
	return {"kind": "mention", "group": "mention|" + q, "who": who, "place": "Qingston", "text": text}


func test_repeats_merge_into_one_toast() -> void:
	var g := AlertGate.new()
	var a := g.push(_mention(Q1, "Lucy", "gm enteh"), 10.0)
	eq(a["action"], "new")
	eq(AlertGate.text_of(a["toast"]), "Lucy named you in Qingston: “gm enteh”")
	var b := g.push(_mention(Q1, "Bob", "enteh?"), 12.0)
	eq(b["action"], "merge")
	var c := g.push(_mention(Q1, "Ann", "@enteh hi"), 14.0)
	eq(int(c["toast"]["count"]), 3)
	eq(AlertGate.text_of(c["toast"]), "3 new mentions in Qingston · latest Ann: “@enteh hi”")
	eq(int(c["toast"]["id"]), int(a["toast"]["id"]), "one toast")
	var d := g.push(_mention(Q1, "Zed", "enteh"), 14.0 + AlertGate.MERGE_S + 1.0)
	eq(d["action"], "new", "after the merge window: a new toast")


func test_new_toasts_are_rate_limited_then_released() -> void:
	var g := AlertGate.new()
	var acts: Array = []
	for i in 6:
		acts.append(g.push({"kind": "arrive", "group": "arrive|q%d" % i, "who": "p%d" % i, "place": "Q%d" % i}, 100.0)["action"])
	eq(acts, ["new", "new", "new", "held", "held", "held"], "a burst of %d, then held" % int(AlertGate.BURST))
	var again := g.push({"kind": "arrive", "group": "arrive|q4", "who": "x", "place": "Q4"}, 100.5)
	eq(again["action"], "held", "a repeat of a held one merges into it")
	eq(int(again["toast"]["count"]), 2)
	eq(g.release(100.6).size(), 0, "no room yet")
	var out := g.release(100.0 + 1.0 / AlertGate.RATE + 0.01)
	eq(out.size(), 1, "one comes out when there is room")
	eq(String(out[0]["group"]), "arrive|q3")
	var later := g.release(100.0 + 10.0 / AlertGate.RATE)
	eq(later.size(), 2, "the rest follow")


func test_sound_and_flash_have_gaps() -> void:
	var g := AlertGate.new()
	check(g.sound_ok(1.0))
	check(not g.sound_ok(1.0 + AlertGate.SOUND_GAP_S * 0.5))
	check(g.sound_ok(1.0 + AlertGate.SOUND_GAP_S + 0.1))
	check(g.attention_ok(5.0))
	check(not g.attention_ok(6.0))
	check(g.attention_ok(5.0 + AlertGate.ATTENTION_GAP_S))


func test_toast_words_per_kind() -> void:
	eq(AlertGate.text_of({"kind": "arrive", "count": 1, "who": "PulsePunk", "place": "Zürich QING"}), "PulsePunk arrived in Zürich QING")
	eq(AlertGate.text_of({"kind": "arrive", "count": 4, "who": "Lucy", "place": "Zürich QING"}), "4 arrivals in Zürich QING · latest Lucy")
	check(AlertGate.text_of({"kind": "invite", "count": 2, "text": "Lucy asks you to join them."}).begins_with("2 invites"))
	eq(AlertGate.title_of("crown"), "CROWN")


func test_prefs_round_trip() -> void:
	var path := "user://test_alerts.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var p := AlertPrefs.new(path)
	p.load_prefs()
	for k in AlertGate.KINDS:
		check(p.on(k), "%s is on by default" % k)
		check(AlertPrefs.LABELS.has(k), "%s has a label" % k)
	check(p.sound and p.flash)
	p.set_kind("arrive", false)
	p.sound = false
	p.save_prefs()
	var q := AlertPrefs.new(path)
	q.load_prefs()
	check(not q.on("arrive"))
	check(q.on("mention"))
	check(not q.sound)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_alert_slot_is_clear_of_the_corners() -> void:
	var s := HudLayout.slots()
	var a: Rect2 = s["alerts"]
	check(a.size.y >= 300, "room for the card and a toast")
	for k in ["who", "keys", "room", "prompt", "where", "activity"]:
		check(not a.intersects(s[k]), "alerts and %s overlap" % k)
