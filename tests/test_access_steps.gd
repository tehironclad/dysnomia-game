extends TestCase
## AccessGates: a snapshot of facts → the numbered steps (✓ / → / ○ / checking… / —).

const W := "0x18f6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3111"
const ONE := "1000000000000000000"


func _ready_signer() -> Dictionary:
	return {"wallet": W, "signer": W, "relay": true, "chain_id": 369, "identity": "ok", "lau": true, "yue": true,
		"lau_addr": "0x1111111111111111111111111111111111111111", "yue_addr": "0x2222222222222222222222222222222222222222"}


func _ids(r: Dictionary) -> Array:
	return r["steps"].map(func(s): return s["id"])


func _marks(r: Dictionary) -> String:
	return "".join(PackedStringArray(r["steps"].map(func(s): return s["mark"])))


func test_room_post_with_no_wallet() -> void:
	var r := AccessGates.resolve("room_post", {"wallet": "", "relay": false, "room": {"state": "ok", "cover": false}})
	eq(_ids(r), ["wallet", "window", "chain", "lau", "room"], "unbanned is hidden until a ban is read")
	eq(r["current"], 0)
	eq(_marks(r), "→○——✓", "connect is current; chain/LAU unknown; an open door is done")
	eq(r["steps"][0]["action"], "connect")
	check(not r["ready"])
	check(String(r["summary"]).begins_with("Step 1 of 5: Connect a wallet"), r["summary"])


func test_view_only_session_needs_the_window() -> void:
	# --session: a wallet is set but the window is not linked; nothing can be signed.
	var f := {"wallet": W, "relay": false, "identity": "ok", "lau": true, "yue": true}
	var r := AccessGates.resolve("su", f)
	eq(_marks(r), "✓→—✓✓")
	eq(r["steps"][1]["action"], "connect", "a closed relay: connect restarts it")
	f["relay"] = true
	r = AccessGates.resolve("su", f)
	eq(r["steps"][1]["action"], "reopen", "relay up but nothing linked: reopen the window")
	f["signer"] = "0x9999999999999999999999999999999999999999"
	r = AccessGates.resolve("su", f)
	check(String(r["steps"][1]["detail"]).contains("not"), "another account linked")
	eq(r["steps"][1]["status"], "todo")


func test_wrong_chain_is_current() -> void:
	var f := _ready_signer()
	f["chain_id"] = 1
	var r := AccessGates.resolve("sign", f)
	eq(_marks(r), "✓✓→")
	eq(r["steps"][2]["action"], "chain")
	check(String(r["steps"][2]["detail"]).contains("chain 1"))
	f["chain_id"] = 369
	check(AccessGates.resolve("sign", f)["ready"], "all done")


func test_identity_states() -> void:
	var f := _ready_signer()
	f["identity"] = "reading"
	var r := AccessGates.resolve("su", f)
	eq(r["steps"][3]["status"], "checking")
	eq(r["steps"][3]["mark"], "→", "the first not-done step is current even while checking")
	check(String(r["steps"][3]["detail"]).contains("Reading"))
	f["identity"] = "failed"
	f["identity_error"] = "timeout"
	r = AccessGates.resolve("su", f)
	eq(r["steps"][3]["status"], "unknown")
	check(String(r["steps"][3]["detail"]).begins_with("—"), "a failed read shows —, never 'no LAU'")
	f["identity"] = "ok"
	f["lau"] = false
	f["yue"] = false
	r = AccessGates.resolve("su", f)
	eq(_marks(r), "✓✓✓→○")
	eq(r["steps"][3]["action"], "void")
	eq(r["steps"][4]["action"], "", "YUE comes after the LAU: no button yet")


func test_ban_shows_only_when_read() -> void:
	var f := _ready_signer()
	f["banned"] = true
	f["room"] = {"state": "ok", "cover": false}
	var r := AccessGates.resolve("room_post", f)
	check(_ids(r).has("unbanned"))
	eq(r["steps"][r["current"]]["id"], "unbanned")
	eq(r["steps"][r["current"]]["action"], "", "nothing in the game lifts a ban")


func test_room_cover_join() -> void:
	var f := _ready_signer()
	f["room"] = {"state": "ok", "cover": true, "admitted": false, "afford": true, "cover_text": "414 Ⓐ", "block": 28140000, "name": "AFFECTION"}
	var r := AccessGates.resolve("room_post", f)
	var s: Dictionary = r["steps"][r["current"]]
	eq(s["id"], "room")
	eq(s["action"], "join")
	check(String(s["title"]).contains("AFFECTION"))
	check(String(s["detail"]).contains("414 Ⓐ") and String(s["detail"]).contains("28140000"))
	f["room"]["afford"] = false
	f["room"]["balance_text"] = "3 Ⓐ"
	s = AccessGates.resolve("room_post", f)["steps"][4]
	check(String(s["detail"]).contains("you hold 3 Ⓐ"), s["detail"])
	f["room"]["admitted"] = true
	check(AccessGates.resolve("room_post", f)["ready"])
	f["room"] = {"state": "failed"}
	eq(AccessGates.resolve("room_post", f)["steps"][4]["status"], "unknown")


func test_fair_ticket_affection() -> void:
	var f := _ready_signer()
	f["aff"] = {"state": "reading"}
	var r := AccessGates.resolve("fair_ticket", f)
	eq(r["steps"][3]["status"], "checking")
	f["aff"] = {"state": "ok", "wallet": "0", "lau": "5" + ONE.substr(1), "fee": ONE.left(18) + "2"}
	r = AccessGates.resolve("fair_ticket", f)
	eq(r["steps"][3]["action"], "move_lau", "the LAU holds enough: move it")
	check(String(r["steps"][3]["detail"]).contains("LAU"))
	f["aff"] = {"state": "ok", "wallet": "0", "lau": "0", "fee": ONE}
	r = AccessGates.resolve("fair_ticket", f)
	eq(r["steps"][3]["action"], "get_affection", "nothing anywhere: buy some")
	f["aff"] = {"state": "ok", "wallet": "2" + ONE.substr(1), "lau": "", "fee": ONE}
	check(AccessGates.resolve("fair_ticket", f)["ready"])
	f["aff"] = {"state": "failed"}
	eq(AccessGates.resolve("fair_ticket", f)["steps"][3]["mark"], "→")
	eq(AccessGates.resolve("fair_ticket", f)["steps"][3]["status"], "unknown")


func test_rocket_needs_seven() -> void:
	var f := _ready_signer()
	f["aff"] = {"state": "ok", "wallet": ONE, "fee": ONE}
	f["fair"] = {"state": "ok", "have": 5, "need": 7, "missing": ["Waat Wheel", "Saat Fortune Teller"], "block": 28141000}
	var r := AccessGates.resolve("rocket", f)
	var s: Dictionary = r["steps"][r["current"]]
	eq(s["id"], "fair")
	check(String(s["detail"]).contains("5/7") and String(s["detail"]).contains("Waat Wheel"), s["detail"])
	f["fair"] = {"state": "ok", "have": 7, "need": 7}
	check(AccessGates.resolve("rocket", f)["ready"])


func test_beat_readiness() -> void:
	var f := _ready_signer()
	f["ready"] = {"state": "ok", "verdict": "not-ready", "reason": "Fornax is on your wallet, not your LAU.", "block": 7}
	var r := AccessGates.resolve("beat", f)
	eq(r["steps"][5]["mark"], "→")
	check(String(r["steps"][5]["detail"]).contains("Fornax"))
	f["ready"]["verdict"] = "fragile"
	check(AccessGates.resolve("beat", f)["ready"])


func test_building_tier() -> void:
	var r := AccessGates.resolve("building", {"tier": {"state": "ok", "have": 1, "need": 2, "have_name": "Outpost", "need_name": "Settlement", "total": "3,960", "block": 28136594, "what": "the night market"}})
	eq(r["steps"].size(), 1)
	eq(r["steps"][0]["action"], "su")
	check(String(r["steps"][0]["title"]).contains("Settlement"))
	check(String(r["steps"][0]["detail"]).contains("3,960"))
	eq(AccessGates.resolve("building", {})["steps"][0]["status"], "checking", "unread tier: checking…")


func test_extra_and_providers() -> void:
	var f := _ready_signer()
	f["extra"] = [{"id": "hoverbike", "title": "A Hypobar anywhere", "status": "todo", "detail": "No bars yet."}]
	f["provider_steps"] = [{"id": "diag", "title": "Wallet extension found", "status": "done"}]
	f["override"] = {"window": {"status": "todo", "detail": "Diagnosis: the window lost its link 40 s ago."}}
	var r := AccessGates.resolve("vehicle", f)
	eq(_ids(r), ["hoverbike"], "vehicle goal: the host's own gates only")
	r = AccessGates.resolve("sign", f)
	eq(_ids(r), ["wallet", "window", "chain", "diag", "hoverbike"], "provider steps follow the chain step")
	eq(r["steps"][1]["mark"], "→", "an override replaces a gate's verdict")
	check(String(r["steps"][1]["detail"]).begins_with("Diagnosis"))


func test_wallet_diagnosis_refines_wallet_steps() -> void:
	var rows := [
		{"id": "relay", "step": "Local wallet relay", "ok": true, "why": "listening"},
		{"id": "window", "step": "Wallet window linked", "ok": true, "why": "opened as chrome"},
		{"id": "provider", "step": "Browser wallet in that window", "ok": false, "why": "that browser has no wallet extension"},
		{"id": "account", "step": "Account connected", "ok": null, "why": "skipped"},
		{"id": "chain", "step": "Wallet on PulseChain (369)", "ok": false, "why": "the wallet is on chain 1"},
		{"id": "gas", "step": "PLS for gas", "ok": false, "why": "0 PLS; a ticket's gas ≈ 0.5 PLS"},
	]
	var d := AccessGates.from_diagnosis(rows, "fair_ticket")
	check(d["override"].has("chain") and not d["override"].has("window"), "only failed checks override")
	eq(d["provider_steps"].map(func(x): return x["id"]), ["provider", "gas"])
	var f := _ready_signer()
	f.merge(d)
	f["aff"] = {"state": "ok", "wallet": ONE, "fee": ONE}
	var r := AccessGates.resolve("fair_ticket", f)
	eq(_ids(r), ["wallet", "window", "chain", "provider", "gas", "affection"])
	eq(r["steps"][r["current"]]["id"], "chain", "the diagnosis's chain verdict wins over the cached chain id")
	check(String(r["steps"][2]["detail"]).contains("chain 1"))
	eq(AccessGates.from_diagnosis(rows, "building"), {"override": {"chain": {"status": "todo", "detail": "the wallet is on chain 1"}}, "provider_steps": [AccessGates.from_diagnosis(rows, "building")["provider_steps"][0]]}, "no gas step for a goal that signs nothing")
