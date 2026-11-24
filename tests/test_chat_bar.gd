extends TestCase
## The chat bar's parts with no network: history recall, the queue and its
## batches, line formatting, the day's activity, and the input guard.

const ZURICH := "0xb0ba7d36b7f0505879179ece7401f24eb653c6e1"


func _line(tx: String, block: int, name: String, text: String, soul: String = "1") -> Dictionary:
	return {"tx": tx, "log_index": 0, "block": block, "name": name, "text": text, "soul": soul, "aura": "", "badge": "", "source": "chain"}


func test_history_recall_keeps_the_draft() -> void:
	var d := ChatDraft.new()
	d.remember("one")
	d.remember("two")
	d.remember("two")  # repeats once
	eq(d.history.size(), 2)
	eq(d.older("typing"), "two")
	eq(d.older("two"), "one")
	eq(d.older("one"), "one", "stops at the oldest")
	eq(d.newer("one"), "two")
	eq(d.newer("two"), "typing", "back to what was being typed")
	check(not d.browsing())
	eq(d.newer("typing"), "typing")
	eq(ChatDraft.new().older("x"), "x", "no history: nothing changes")


func test_length_rule_and_restore() -> void:
	eq(ChatDraft.reject_reason("  "), "empty")
	eq(ChatDraft.reject_reason("gm"), "")
	check(ChatDraft.reject_reason("x".repeat(ChatDraft.MAX_LEN + 1)).begins_with("too long"))
	eq(ChatDraft.restore("", "failed line"), "failed line", "an empty bar gets the failed line back")
	eq(ChatDraft.restore("new text", "failed line"), "new text", "typed text is never overwritten")
	eq(ChatDraft.quick(0), ChatDraft.QUICK[0])
	eq(ChatDraft.quick(9), "")


func test_queue_batches_lines_typed_while_signing() -> void:
	var o := ChatOutbox.new()
	o.add("first", ZURICH)
	var b1 := o.take_batch()
	eq(b1.size(), 1, "the first line goes at once, alone")
	eq(b1[0]["state"], "signing")
	o.add("second", ZURICH)
	o.add("third", ZURICH)
	eq(o.take_batch().size(), 0, "nothing else is signed while one transaction is open")
	o.confirm(b1, 100, "0xaa", "on chain · block 100")
	var b2 := o.take_batch()
	eq(b2.size(), 2, "lines queued meanwhile go together")
	eq(b2.map(func(e): return e["text"]), ["second", "third"])
	o.fail(b2, "declined", "declined")
	eq(o.get_entry(b2[0]["id"])["state"], "failed")
	eq(o.get_entry(b2[0]["id"])["text"], "second", "a failed line keeps its text")
	eq(ChatOutbox.status_text(o.get_entry(b1[0]["id"])), "on chain · block 100")


func test_batch_stays_in_one_room_and_caps() -> void:
	var o := ChatOutbox.new()
	for i in ChatOutbox.MAX_BATCH + 2:
		o.add("l%d" % i, ZURICH)
	o.add("elsewhere", "0xd127839b83cbf537c29b7d268c135f745a0da2e8")
	var b := o.take_batch()
	eq(b.size(), ChatOutbox.MAX_BATCH)
	o.confirm(b, 1, "0x1", "ok")
	var b2 := o.take_batch()
	eq(b2.size(), 2, "the rest of this room; the other room waits for its own transaction")


func test_batch_encoding() -> void:
	var one := ChatOutbox.encode_batch(ZURICH, ["gm"], "Zürich QING")
	eq(one["to"], Contracts.CHOA)
	check(String(one["data"]).begins_with("0xb340a780"), "CHOA.Chat(address,string)")
	var many := ChatOutbox.encode_batch(ZURICH, ["a", "b"], "Zürich QING")
	eq(many["to"], Contracts.MULTICALL3)
	check(String(many["data"]).begins_with("0x82ad56cb"), "aggregate3")
	var calls: Array = Abi.decode(["(address,bool,bytes)[]"], "0x" + String(many["data"]).substr(10))[0]
	eq(calls.size(), 2)
	eq(String(calls[0][0]).to_lower(), Contracts.CHOA)
	eq(calls[0][1], false, "allowFailure = false: all lines post or none")
	eq(String(calls[1][2]), Abi.encode_call("Chat(address,string)", [ZURICH, "b"]))


func test_failure_kinds() -> void:
	eq(ChatOutbox.classify({"stage": "simulate", "revert": {"name": "NotAdmitted"}}), "join")
	eq(ChatOutbox.classify({"stage": "simulate", "revert": {"name": "NotStarted"}}), "identity")
	eq(ChatOutbox.classify({"stage": "precondition", "message": "No wallet connected."}), "signer")
	eq(ChatOutbox.classify({"stage": "sign", "message": "User rejected the request (4001)"}), "declined")
	eq(ChatOutbox.classify({"stage": "receipt", "message": "reverted"}), "other")


func test_merge_prefers_the_chain_copy() -> void:
	var site := ChatLines.from_site({"from": "0xb644", "fromName": "PulsePunk", "soul": "430955136252741", "text": "Anyone home?",
		"txHash": "0xABC", "block": 27787862, "logIndex": 5, "qingAddr": ZURICH}, ZURICH)
	eq(site["source"], "site")
	eq(site["badge"], "", "no Aura from the site: no badge")
	check(not site.has("wallet"), "the API's 'from' is not trusted as the speaker")
	var lines: Array = [site]
	lines[0]["wallet"] = "0xb644"
	var chain := _line("0xabc", 27787862, "PulsePunk", "Anyone home?")
	chain["log_index"] = 5
	chain["aura"] = "42"
	eq(ChatLines.merge(lines, [chain]).size(), 0, "the same line is not new")
	eq(lines[0]["source"], "chain")
	eq(lines[0]["aura"], "42")
	eq(lines[0]["wallet"], "0xb644", "a resolved wallet survives")


func test_merge_orders_chain_then_say() -> void:
	var lines: Array = []
	ChatLines.merge(lines, [ChatLines.say_line("0x1", "a", "free", 5)])
	ChatLines.merge(lines, [_line("0x2", 20, "b", "late"), _line("0x1", 10, "c", "early")])
	eq(lines.map(func(l): return l["text"]), ["early", "late", "free"])


func test_clean_text() -> void:
	eq(ChatLines.clean_text("a\nb\tc"), "a b c")
	eq(ChatLines.clean_text("data:image/webp;base64," + "A".repeat(4096)), "[image · 3.0 kB]")
	eq(ChatLines.clean_text("data:audio/webm;codecs=opus;base64,AAAA"), "[audio · 3 B]")
	var long := ChatLines.clean_text("x".repeat(300), 20)
	eq(long.length(), 20)
	check(long.ends_with("…"))
	eq(ChatLines.compact({"name": "", "text": "hi", "badge": "og"}), "? ✓: hi")


func test_bbcode_escapes_and_tags() -> void:
	var l := _line("0x1", 7, "[b]x", "[url]y")
	var s := ChatLines.bbcode(l, true)
	check(s.contains("[lb]b]x") and s.contains("[lb]url]y"), "brackets escaped: %s" % s)
	check(s.contains("7"), "the block shows in the history")
	check(ChatLines.bbcode(ChatLines.say_line("0x1", "a", "t", 1)).contains("say"), "say lines are tagged")
	check(ChatLines.provenance(l).contains("block 7"))
	check(ChatLines.provenance(ChatLines.say_line("0x1", "a", "t", 1)).contains("not on chain"))


func test_day_stats_and_glow() -> void:
	var head := 100000
	var ls: Array = [_line("0x1", head - 9000, "old", "x", "9"),
		_line("0x2", head - 100, "ann", "a", "1"), _line("0x3", head - 50, "bob", "b", "2"),
		_line("0x4", head - 10, "ann", "c", "1"), ChatLines.say_line("0x9", "zed", "free", 1)]
	ls[3]["wallet"] = "0xann"
	var st := ChatLines.day_stats(ls, head)
	eq(st["count"], 3, "only chain lines inside the last day")
	eq(st["speakers"][0]["name"], "ann")
	eq(st["speakers"][0]["lines"], 2)
	eq(st["speakers"][0]["wallet"], "0xann")
	check(not st["floor"])
	var capped := ChatLines.day_stats(ls.slice(1, 4), head, true)
	check(capped["floor"], "a capped history wholly inside the day is a floor")
	eq(ChatLines.count_text(capped), "3+")
	eq(ChatLines.glow_for(0), 0.0)
	near(ChatLines.glow_for(ChatLines.FULL_GLOW_LINES), 1.0, 1e-6)
	check(ChatLines.glow_for(3) < ChatLines.glow_for(10))


func test_input_guard_lifts_gameplay_keys_only() -> void:
	check(not ChatInputGuard.is_suspended())
	var before := InputMap.action_get_events("move_forward").size()
	check(before > 0)
	ChatInputGuard.suspend()
	eq(InputMap.action_get_events("move_forward").size(), 0, "W types, it does not walk")
	eq(InputMap.action_get_events("interact").size(), 0)
	check(InputMap.action_get_events("chat_recall_prev").size() > 0, "the chat's own keys stay")
	check(InputMap.action_get_events("ui_cancel").size() > 0, "Esc still closes")
	ChatInputGuard.restore()
	eq(InputMap.action_get_events("move_forward").size(), before, "every key comes back")
	check(not ChatInputGuard.is_suspended())
	eq(ControlsHelp.key_of("interact"), "E")


func test_chat_keys_are_actions() -> void:
	for a in ["chat", "chat_history", "chat_recall_prev", "chat_recall_next", "chat_mode", "chat_quick_1", "chat_quick_4"]:
		check(InputMap.has_action(a) and ControlsHelp.key_of(a) != "—", "action %s bound" % a)
	eq(ControlsHelp.key_of("chat_recall_prev"), "Up")


func test_bar_keys_and_hint() -> void:
	var bar := ChatBar.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(bar)
	check(ChatBar.hint_text().contains("Up"), ChatBar.hint_text())
	bar.open("gm")
	check(bar.is_open())
	check(ChatInputGuard.is_suspended(), "typing lifts gameplay keys")
	eq(bar.edit.text, "gm")
	bar.close()
	check(not ChatInputGuard.is_suspended())
	bar.open()
	eq(bar.edit.text, "gm", "Esc keeps the text for next time")
	bar.close()
	bar.free()
