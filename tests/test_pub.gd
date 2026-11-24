extends TestCase
## Sunny's Pub bar: the menu is the visitor's own real calls (BarTab), the
## calldata is exact, and what's reported after a pour comes from the receipt
## and the re-read bars, with "—" where a read failed. No network.

const WALLET := "0x6d936484072482335a7a479f92a6d3cd7979829e"
const QING := "0x2b78b345880807ac9be28c1309ab55d6fa8796de"
const ZERO_TOPIC := "0x0000000000000000000000000000000000000000000000000000000000000000"


static func _topic(addr: String) -> String:
	return "0x" + Abi.strip0x(addr).to_lower().lpad(64, "0")


func test_menu_is_real_calls_only() -> void:
	var ops: Array = []
	for d in BarTab.DRINKS:
		check(Contracts.SELECTORS.has(d["sig"]), "%s: a known selector" % d["sig"])
		if d["kind"] == BarTab.KIND_OP:
			ops.append(d["sig"])
			eq(BarTab.target(d), Contracts.AFFECTION)
	ops.sort()
	# LEARNINGS §1/§3: exactly the six permissionless AFFECTION ops.
	eq(ops, ["Alpha(uint64)", "Beta(uint64)", "Generate()", "Pi()", "Rho()", "Upsilon(uint64,bool)"])
	eq(BarTab.target(BarTab.drink("house_su")), Contracts.CHEON)
	eq(BarMenu.board_lines().size(), BarTab.DRINKS.size() + 1)
	eq(BarMenu.board_lines()[-1], ["Round for the House", ArcadePay.fee_text()])


func test_calldata() -> void:
	eq(BarTab.calldata(BarTab.drink("pi_shot"), QING, 0, false), "0x5c13dbf0")
	eq(BarTab.calldata(BarTab.drink("generator_lager"), QING, 0, false), "0xd805b650")
	eq(BarTab.calldata(BarTab.drink("alpha_sour"), QING, 42, false), "0xe95b237f" + "2a".lpad(64, "0"))
	eq(BarTab.calldata(BarTab.drink("beta_blocker"), QING, 7, false), "0x7ab0960d" + "7".lpad(64, "0"))
	eq(BarTab.calldata(BarTab.drink("upsilon_fizz"), QING, 255, true), "0xdf4c7406" + "ff".lpad(64, "0") + "1".lpad(64, "0"))
	eq(BarTab.calldata(BarTab.drink("house_su"), QING, 0, false), "0x753a0c09" + Abi.strip0x(QING).lpad(64, "0"))
	eq(BarTab.call_text(BarTab.drink("upsilon_fizz"), QING, 9, false), "AFFECTION.Upsilon(9, false)")
	check(BarTab.takes_seed(BarTab.drink("alpha_sour")) and not BarTab.takes_seed(BarTab.drink("rho_rocks")))
	check(BarTab.takes_phi(BarTab.drink("upsilon_fizz")) and not BarTab.takes_phi(BarTab.drink("beta_blocker")))


func test_minted_in_receipt() -> void:
	var one := "0x" + BigInt.to_word(BigInt.from_decimal("1000000000000000000"))
	var receipt := {"logs": [
		{"address": Contracts.AFFECTION, "topics": [Contracts.TOPIC_TRANSFER, ZERO_TOPIC, _topic(Contracts.AFFECTION)], "data": one},
		{"address": Contracts.AFFECTION, "topics": [Contracts.TOPIC_TRANSFER, ZERO_TOPIC, _topic(Contracts.AFFECTION)], "data": one},
		{"address": Contracts.AFFECTION, "topics": [Contracts.TOPIC_TRANSFER, _topic(WALLET), _topic(QING)], "data": one},  # not a mint
		{"address": Contracts.CHEON, "topics": [Contracts.TOPIC_TRANSFER, ZERO_TOPIC, _topic(WALLET)], "data": one},  # another token
	]}
	var m := BarTab.minted_in_receipt(receipt)
	eq(m["count"], 2)
	eq(BigInt.to_decimal(m["total"]), "2000000000000000000")
	eq(m["to"], [Contracts.AFFECTION])
	eq(BarTab.minted_in_receipt({"logs": []})["count"], 0)


func test_bars_text_never_invents() -> void:
	var b := {"ok": true, "hypo": BigInt.from_int(1204), "epi": BigInt.from_int(88)}
	var a := {"ok": true, "hypo": BigInt.from_int(1215), "epi": BigInt.from_int(88)}
	eq(BarTab.bars_change_text(b, a), "Hypobar 1,204 → 1,215 (+11) · Epibar 88 → 88 (+0)")
	check(BarTab.bars_change_text(b, {"ok": false}).contains("—"), "a failed re-read is —")
	check(BarTab.bars_change_text({"ok": false}, a).contains("change: —"), "an unknown before: the change is —")
	var r := {"block": 100, "before": b, "after": b, "minted": {"count": 1, "total": BigInt.from_decimal("1000000000000000000"), "to": [Contracts.AFFECTION]}}
	var text := BarTab.report(BarTab.drink("pi_shot"), r)
	check(text.contains("block 100") and text.contains("Read at blocks 99 → 100"), text)
	check(text.contains("its own reserve") and text.contains(BarTab.OP_NOTE), text)
	check(not BarTab.report(BarTab.drink("house_su"), r).contains(BarTab.OP_NOTE), "Su does move bars")


func test_pub_clips_exist() -> void:
	# The regulars' clips come from the Quaternius library; a missing name would silently fall back to Idle.
	var lib := HumanAvatar.library()
	for c in ["Sitting_Idle", "Sitting_Talking", "Idle_Talking", "Interact", "Dance", "Walk"]:
		check(lib.has_animation(c), "clip %s in the library" % c)
	check(InputMap.has_action("bar_menu"), "the bar menu has an input action")
