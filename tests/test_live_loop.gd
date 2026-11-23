extends TestCase
## Phase 5 logic: chat parsing and badges, the Su delta, the Join plan, the
## interaction zones. No network.

const QING := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func _log(address: String, data: String, block: int, idx: int = 0, tx: String = "0xabc") -> Dictionary:
	return {"address": address, "data": data, "blockNumber": "0x%x" % block, "logIndex": "0x%x" % idx, "transactionHash": tx}


func test_parse_void_real_line() -> void:
	# LAU.Chat tx 0x1148be9e…7fcc, block 28,033,746: (403523022759625, 254841623954401, "<⽍> ☠")
	var data := "0x" + Abi.encode(["uint64", "uint64", "string"], ["0x" + BigInt.to_hex(BigInt.from_decimal("403523022759625")),
		"0x" + BigInt.to_hex(BigInt.from_decimal("254841623954401")), "<⽍> ☠"])
	var l := ChatLog.parse_void(_log(Contracts.FOMALHAUTE, data, 28033746))
	eq(l["soul"], "403523022759625")
	eq(l["aura"], "254841623954401")
	eq(l["name"], "⽍")
	eq(l["text"], "☠")
	eq(l["block"], 28033746)


func test_parse_void_without_name() -> void:
	var data := "0x" + Abi.encode(["uint64", "uint64", "string"], ["0x1", "0x2", "plain text"])
	var l := ChatLog.parse_void(_log(Contracts.FOMALHAUTE, data, 21000001))
	eq(l["name"], "")
	eq(l["text"], "plain text")


func test_parse_room_and_emitter_filter() -> void:
	var data := "0x" + Abi.encode(["string", "uint64", "uint64", "string"], ["alice", "0x7", "0x9", "gm room"])
	var good := _log(QING, data, 28000000, 1, "0x01")
	var forged := _log("0x000000000000000000000000000000000000dead", data, 28000001, 0, "0x02")
	var dup := good.duplicate()
	var out := ChatLog.parse_logs([forged, good, dup], QING, true)
	eq(out.size(), 1, "only the QING's own log, once")
	eq(out[0]["name"], "alice")
	eq(out[0]["soul"], "7")
	eq(out[0]["aura"], "9")
	eq(out[0]["text"], "gm room")
	eq(out[0]["qing"], QING)


func test_chain_order() -> void:
	var d := func(t): return "0x" + Abi.encode(["uint64", "uint64", "string"], ["0x1", "0x2", "<a> " + t])
	var out := ChatLog.parse_logs([_log(Contracts.FOMALHAUTE, d.call("late"), 30, 0, "0x1"),
		_log(Contracts.FOMALHAUTE, d.call("early"), 20, 5, "0x2"), _log(Contracts.FOMALHAUTE, d.call("mid"), 30, -0 + 0, "0x3")], Contracts.FOMALHAUTE, false)
	eq(out[0]["text"], "early")


func test_normalize() -> void:
	eq(ChatLog.normalize("MariaraheI"), "marlarahel")  # the site folds i and I to l
	eq(ChatLog.normalize("  Bob​  Smith "), "bob smlth")
	eq(ChatLog.normalize("аlice"), "allce")  # Cyrillic а, then I/l folding
	eq(ChatLog.normalize("o0"), "o0", "no folding under three letters")
	eq(ChatLog.normalize("vvorm"), "worm")
	eq(ChatLog.normalize("barn"), "bam")


func test_verdicts_from_claims() -> void:
	# name-claims.json: "0" is owned by Aura 256613458014241.
	eq(ChatLog.verdict("0", "256613458014241"), "og")
	eq(ChatLog.verdict("0", "1"), "imposter")
	eq(ChatLog.verdict("kek", "1"), "", "generic names get no badge")
	eq(ChatLog.verdict("surely-nobody-has-this-name-xyz", "1"), "")


func test_su_delta() -> void:
	var v := Moves.su_delta(["0x64", "0xa"], ["0x3", "0x96", "0xf"])
	eq(BigInt.to_decimal(v["d_hypo"]), "50")
	eq(BigInt.to_decimal(v["d_epi"]), "5")
	eq(BigInt.to_decimal(v["charge"]), "3")
	eq(BigInt.to_decimal(v["hypo_after"]), "150")


func test_join_plan() -> void:
	var r := RoomState.new()
	r.qing = QING
	r.asset = "0x1111111111111111111111111111111111111111"
	r.asset_symbol = "Ⓐ"
	r.lau = "0x2222222222222222222222222222222222222222"
	r.ok = true
	r.cover = BigInt.from_decimal("414000000000000000000")
	r.allowance = BigInt.from_decimal("414000000000000000000")  # exactly the cover: refused on chain
	check(r.needs_approve(), "allowance == cover still needs an approve")
	var steps := r.join_steps()
	eq(steps.size(), 2)
	eq(BigInt.to_decimal(r.approve_amount()), "414000000000000000001")
	check(String(steps[0]["data"]).begins_with(Contracts.selector("approve(address,uint256)")))
	check(String(steps[1]["data"]).begins_with(Contracts.selector("Join(address)")))
	r.allowance = BigInt.from_decimal("414000000000000000001")
	eq(r.join_steps().size(), 1)
	r.admitted = true
	eq(r.join_steps().size(), 0)
	eq(r.chat_blocker(), "")
	r.admitted = false
	check(r.chat_blocker().contains("Join first"))
	r.banned = true
	check(r.chat_blocker().contains("WITHOUT"))
	var open := RoomState.new()
	open.lau = r.lau
	open.admitted = true  # Admitted() is true when the cover is 0
	check(not open.has_cover())
	eq(open.join_steps().size(), 0)


func test_zones() -> void:
	var t: GDScript = load("res://scripts/world/territory_v2.gd")
	var mono := Vector3(-26, 0, 18)
	eq(t.zone_at(Vector3(-9, 0, 1), mono), "su")
	eq(t.zone_at(Vector3(9, 0, -1), mono), "su")
	eq(t.zone_at(Vector3(0.5, 0, 0.5), mono), "beat")
	eq(t.zone_at(Vector3(0, 0, 7), mono), "room")
	eq(t.zone_at(Vector3(-25, 0, 17), mono), "void")
	eq(t.zone_at(Vector3(0, 0, 16), mono), "", "the arrival spot is free")


func test_bar_column_height() -> void:
	near(BarColumns.height_for(PackedInt64Array()), 0.15, 0.001)
	check(BarColumns.height_for(BigInt.from_decimal("78")) > BarColumns.height_for(BigInt.from_decimal("26")) + 0.4, "small bars still differ")
	check(BarColumns.height_for(BigInt.from_decimal("1000000000")) > BarColumns.height_for(BigInt.from_decimal("1000")))
	near(BarColumns.height_for(BigInt.from_decimal("1" + "0".repeat(60))), 16.0, 0.001)


func test_chat_merge_dedups_and_orders() -> void:
	var c := ChatController.new()
	c.lines = [{"tx": "0x1", "log_index": 0, "block": 10, "name": "a", "text": "x"}]
	var fresh := c._merge([{"tx": "0x1", "log_index": 0, "block": 10, "name": "a", "text": "x"},
		{"tx": "0x2", "log_index": 3, "block": 11, "name": "b", "text": "y"}])
	eq(fresh.size(), 1, "the already-seen line is not new")
	eq(c.lines.size(), 2)
	eq(fresh[0]["text"], "y")
	c.free()


func test_echoes_pick_latest_distinct_speakers() -> void:
	var e := SpeakerEchoes.new()
	e.spots = [Transform3D(), Transform3D()]
	var key_a := SpeakerEchoes.speaker_key({"name": "a", "aura": "1"})
	var key_b := SpeakerEchoes.speaker_key({"name": "b", "aura": "2"})
	check(key_a != key_b)
	eq(SpeakerEchoes.speaker_key({"name": "a", "aura": "9"}) == key_a, false, "same name, other Aura: another speaker")
	e.free()
