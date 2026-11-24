extends TestCase
## The Swap Hall (PulseX) and the YUE exchange desk: calldata against an
## independent encoder (tools/golden: Node + the site's keccak), the router's
## own maths checked against live router answers, slippage, receipt checks,
## and the decoded reverts seen live on 2026-11-24 (LEARNINGS §19).

const WPLS := "0xa1077a294dde1b09bb078844df40758a5d0f9a27"
const AFF := "0x24f0154c1dce548adf15da2098fdd8b8a3b8151d"
const OWNER := "0x18f621662d6a1f23700ea32d146b32195dc33111"
const ZUR := "0x583d1c1427308f7f96bfd3e0d7a3f9674d8bf8ec"
const QZU := "0xb0ba7d36b7f0505879179ece7401f24eb653c6e1"
const YUE_A := "0x4f94f27d9655411927e72799c6e797989a86f2d4"


func test_addresses_known() -> void:
	eq(Contracts.PULSEX_V1_FACTORY, "0x1715a3e4a142d8b698131108995174f37aeba10d")
	eq(Contracts.PULSEX_V2_ROUTER, "0x165c3410fc91ef562c50559f7d2289febed552d9")
	eq(PulseX.router_of("V1"), Contracts.PULSEX_V1_ROUTER)
	eq(PulseX.factory_of("V2"), Contracts.PULSEX_V2_FACTORY)


func test_swap_calldata() -> void:
	var buy := PulseX.swap_call("buy", BigInt.zero(), BigInt.from_decimal("38056268779373012311"), [WPLS, AFF], OWNER, 1795501215)
	eq(buy, "0x7ff36ab5000000000000000000000000000000000000000000000002102306d2f7512557000000000000000000000000000000000000000000000000000000000000008000000000000000000000000018f621662d6a1f23700ea32d146b32195dc33111000000000000000000000000000000000000000000000000000000006b052c9f0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a1077a294dde1b09bb078844df40758a5d0f9a2700000000000000000000000024f0154c1dce548adf15da2098fdd8b8a3b8151d")
	var sell := PulseX.swap_call("sell", BigInt.from_decimal("100000000000000000000"), BigInt.from_int(1), [AFF, WPLS], OWNER, 1795501215)
	eq(sell, "0x18cbafe50000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a000000000000000000000000018f621662d6a1f23700ea32d146b32195dc33111000000000000000000000000000000000000000000000000000000006b052c9f000000000000000000000000000000000000000000000000000000000000000200000000000000000000000024f0154c1dce548adf15da2098fdd8b8a3b8151d000000000000000000000000a1077a294dde1b09bb078844df40758a5d0f9a27")
	eq(PulseX.amounts_out_call(BigInt.from_decimal("1000000000000000000000"), [WPLS, AFF]), "0xd06ca61f00000000000000000000000000000000000000000000003635c9adc5dea0000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a1077a294dde1b09bb078844df40758a5d0f9a2700000000000000000000000024f0154c1dce548adf15da2098fdd8b8a3b8151d")
	# The fee-on-transfer and token→token variants use their own selectors
	check(PulseX.swap_call("buy", BigInt.zero(), BigInt.from_int(1), [WPLS, AFF], OWNER, 1, true).begins_with("0xb6f9de95"))
	check(PulseX.swap_call("sell", BigInt.from_int(1), BigInt.from_int(1), [AFF, WPLS], OWNER, 1, true).begins_with("0x791ac947"))
	check(PulseX.swap_call("cross", BigInt.from_int(1), BigInt.from_int(1), [AFF, WPLS, ZUR], OWNER, 1).begins_with("0x38ed1739"))
	eq(PulseX.path_for("cross", AFF, ZUR), [AFF, WPLS, ZUR])


func test_yue_calldata() -> void:
	eq(YueExchange.hong_call(ZUR, QZU, BigInt.from_decimal("100000000000000")), "0xb3bde122000000000000000000000000583d1c1427308f7f96bfd3e0d7a3f9674d8bf8ec000000000000000000000000b0ba7d36b7f0505879179ece7401f24eb653c6e100000000000000000000000000000000000000000000000000005af3107a4000")
	check(YueExchange.hung_call(QZU, ZUR, BigInt.from_int(1)).begins_with("0x518945cd"))


func test_amount_out_matches_router() -> void:
	# Both live router answers (getAmountOut on V1 and V2, block 28,136,9xx)
	eq(BigInt.to_decimal(PulseX.amount_out(BigInt.from_int(1000000), BigInt.from_decimal("1" + "0".repeat(30)), BigInt.from_decimal("1" + "0".repeat(30)))), "997099")
	eq(BigInt.to_decimal(PulseX.amount_out(BigInt.from_decimal("12345678901234567890"), BigInt.from_decimal("50000000000000000000000"), BigInt.from_decimal("700000000000000000000"))), "172295851241121887")
	eq(BigInt.to_decimal(PulseX.amount_out(BigInt.zero(), BigInt.from_int(5), BigInt.from_int(5))), "0")
	var chain := PulseX.amounts_out(BigInt.from_int(1000000), [[BigInt.from_decimal("1" + "0".repeat(30)), BigInt.from_decimal("1" + "0".repeat(30))],
		[BigInt.from_decimal("1" + "0".repeat(30)), BigInt.from_decimal("1" + "0".repeat(30))]])
	eq(chain.size(), 3)
	eq(BigInt.to_decimal(chain[1]), "997099")
	eq(BigInt.to_decimal(chain[2]), BigInt.to_decimal(PulseX.amount_out(chain[1], BigInt.from_decimal("1" + "0".repeat(30)), BigInt.from_decimal("1" + "0".repeat(30)))))


func test_impact_and_slippage() -> void:
	var big := BigInt.from_decimal("1" + "0".repeat(30))
	eq(PulseX.impact_bps(BigInt.from_int(1000000), big, big), 29)  # the fee alone
	var r := BigInt.from_decimal("1000000000000000000000")
	check(PulseX.impact_bps(r, r, r) > 5000, "half the pool costs more than 50%")
	eq(BigInt.to_decimal(PulseX.min_out(BigInt.from_int(1000), 100)), "990")
	eq(BigInt.to_decimal(PulseX.min_out(BigInt.from_int(999), 50)), "994")
	eq(BigInt.to_decimal(PulseX.min_out(BigInt.from_int(1000), 0)), "1000")
	# 26 PLS per token from reserves, with no float on the way
	eq(BigInt.to_decimal(PulseX.price_wei(BigInt.from_decimal("26000000000000000000"), BigInt.from_decimal("1000000000000000000"), 18)), "26000000000000000000")
	eq(BigInt.to_decimal(PulseX.price_wei(BigInt.from_decimal("26000000000000000000"), BigInt.from_int(1000000), 6)), "26000000000000000000")


func test_parse_units() -> void:
	eq(BigInt.to_decimal(PulseX.parse_units("1.5")["wei"]), "1500000000000000000")
	eq(BigInt.to_decimal(PulseX.parse_units("1,000")["wei"]), "1000000000000000000000")
	eq(BigInt.to_decimal(PulseX.parse_units(".25", 6)["wei"]), "250000")
	check(PulseX.parse_units("1e5").is_empty())
	check(PulseX.parse_units("-1").is_empty())
	check(PulseX.parse_units("0.1234567", 6).is_empty())
	check(PulseX.parse_units("").is_empty())


func test_best_pool_and_shared_router() -> void:
	var a := {"pools": {"V1": {"wpls": BigInt.from_int(800), "token": BigInt.from_int(1)}, "V2": {"wpls": BigInt.from_int(9000), "token": BigInt.from_int(3)}}}
	var b := {"pools": {"V1": {"wpls": BigInt.from_int(5000), "token": BigInt.from_int(1)}}}
	eq(PulseX.best_pool(a["pools"]), "V2")
	eq(PulseX.best_pool({}), "")
	eq(PulseX.best_pool({"V1": {"wpls": BigInt.zero(), "token": BigInt.from_int(3)}}), "")
	eq(PulseX.shared_router(a, b), "V1")
	eq(PulseX.shared_router(a, {"pools": {}}), "")


func test_yue_cost() -> void:
	# Zürich QING: rate 1e24, so 0.0001 qZů costs 100 Zů (live: transferFrom 1e20)
	eq(BigInt.to_decimal(YueExchange.cost(BigInt.from_decimal("100000000000000"), BigInt.from_decimal("1000000000000000000000000"))), "100000000000000000000")
	# Illinois: 1 qILLINOIS for 0.1 ILLINOIS (tx 0x8d16d814…)
	eq(BigInt.to_decimal(YueExchange.cost(BigInt.from_decimal("1000000000000000000"), BigInt.from_decimal("100000000000000000"))), "100000000000000000")
	var l := YueExchange.legs("hung", QZU, ZUR, BigInt.from_int(10), BigInt.from_decimal("1000000000000000000000000"))
	eq(l["pay_token"], QZU)
	eq(l["get_token"], ZUR)
	eq(BigInt.to_decimal(l["get"]), "10000000")


func test_pick_desk() -> void:
	var desks := [{"yue": "0xa", "own": false, "stock_qing": BigInt.from_int(5), "stock_asset": BigInt.zero()},
		{"yue": "0xb", "own": true, "stock_qing": BigInt.from_int(5), "stock_asset": BigInt.from_int(1)},
		{"yue": "0xc", "own": false, "stock_qing": null, "stock_asset": BigInt.from_int(9)}]
	eq(YueExchange.pick_desk(desks, "hong", BigInt.from_int(3))["yue"], "0xb")  # a tie goes to your own YUE
	eq(YueExchange.pick_desk(desks, "hung", BigInt.from_int(2))["yue"], "0xc")
	check(YueExchange.pick_desk(desks, "hong", BigInt.from_int(6)).is_empty(), "nobody holds 6")


func _log(token: String, from: String, to: String, value: String) -> Dictionary:
	return {"address": token, "topics": [Contracts.TOPIC_TRANSFER, "0x" + Abi.strip0x(from).lpad(64, "0"), "0x" + Abi.strip0x(to).lpad(64, "0")],
		"data": "0x" + BigInt.to_word(BigInt.from_decimal(value))}


func test_receipt_checks() -> void:
	var pair := "0x155172653e94a7e5f0e04126803dcb6896796fbb"
	var dep := {"address": WPLS, "topics": [Contracts.TOPIC_WPLS_DEPOSIT, "0x" + Abi.strip0x(Contracts.PULSEX_V2_ROUTER).lpad(64, "0")], "data": "0x" + BigInt.to_word(BigInt.from_decimal("1000"))}
	var rec := {"status": "0x1", "logs": [dep, _log(WPLS, Contracts.PULSEX_V2_ROUTER, pair, "1000"), _log(AFF, pair, OWNER, "38")]}
	var v := PulseX.verify_swap(rec, "buy", OWNER, "", AFF)
	check(v["ok"], str(v))
	eq(BigInt.to_decimal(v["received"]), "38")
	eq(BigInt.to_decimal(v["sent"]), "1000")
	var bad := {"status": "0x1", "logs": [dep, _log(AFF, pair, "0x" + "1".repeat(40), "38")]}
	check(not PulseX.verify_swap(bad, "buy", OWNER, "", AFF)["ok"], "a transfer to someone else is not yours")
	check(not PulseX.verify_swap({"status": "0x0", "logs": []}, "buy", OWNER, "", AFF)["ok"])
	# YUE: both legs, wallet → YUE and YUE → wallet
	var l := YueExchange.legs("hong", QZU, ZUR, BigInt.from_decimal("100000000000000"), BigInt.from_decimal("1000000000000000000000000"))
	var yr := {"status": "0x1", "logs": [_log(ZUR, OWNER, YUE_A, "100000000000000000000"), _log(QZU, YUE_A, OWNER, "100000000000000")]}
	check(YueExchange.verify(yr, OWNER, YUE_A, l)["ok"])
	var short := {"status": "0x1", "logs": [_log(ZUR, OWNER, YUE_A, "100000000000000000000"), _log(QZU, YUE_A, OWNER, "99")]}
	check(not YueExchange.verify(short, OWNER, YUE_A, l)["ok"], "short payout is caught")


func test_error_decoding() -> void:
	# Revert data seen live (simulated Hong from the owner's wallet, 2026-11-24)
	var inv := Abi.decode_revert("0xd9a764d9000000000000000000000000b6be11f0a788014c1f68c92f8d6ccc1abf78f2ab000000000000000000000000d127839b83cbf537c29b7d268c135f745a0da2e8")
	eq(inv["name"], "InvalidPair")
	eq(inv["args"][0], "0xb6be11f0a788014c1f68c92f8d6ccc1abf78f2ab")
	check(String(inv["message"]).contains("asset chain"))
	var nr := Abi.decode_revert("0x464460b9000000000000000000000000174a0ad99c60c20d9b3d94c3095bc1fb9ddefd620000000000000000000000004dd0371c02631bfd17ad10ab7c0e35a047ff2d20")
	eq(nr["name"], "ExchangeRateNotFound")
	var al := Abi.decode_revert("0xfb8f41b20000000000000000000000004f94f27d9655411927e72799c6e797989a86f2d40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002386f26fc10000")
	eq(al["name"], "ERC20InsufficientAllowance")
	eq(BigInt.to_decimal(BigInt.coerce(al["args"][2])), "10000000000000000")
	# Router reverts are Error(string): explained in plain words
	check(PulseX.explain("execution reverted: PulseXRouter: EXPIRED").begins_with("the deadline passed"))
	check(PulseX.explain("PulseXRouter: INSUFFICIENT_OUTPUT_AMOUNT").contains("slippage"))
	check(PulseX.wants_fot("PulseX: K"))
	check(not PulseX.wants_fot("PulseXRouter: EXPIRED"))
	eq(PulseX.explain("something else"), "something else")


func test_yue_floor_height() -> void:
	eq(YueFloor.floor_height({}), -1.0)
	var burj := LandmarkPlan.spec(5, 9.06)
	var f := YueFloor.floor_height(burj)
	check(f >= 16.0 and f <= 96.0 and fmod(f, 4.0) == 0.0, "burj floor %s" % f)
	var inn := LandmarkPlan.spec(2, 4.0)
	check(YueFloor.floor_height(inn) >= 16.0 and YueFloor.floor_height(inn) < float(inn["roof"]), "inn floor below the roof")


func test_swap_hall_site_clear_and_on_land() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var others := [[Vector2(0, 80), FairSite.RADIUS], [Vector2(40, -50), GarageSite.RADIUS], [Vector2(64, -128), LandmarkPlan.PLAZA_R]]
	var s := SwapHall.find_site(flat, others)
	check(s["ok"], "a site on flat land")
	var at: Vector2 = s["at"]
	check(at.length() >= 70.0 + SwapHall.RADIUS, "clear of the Core and the skyline")
	for o in others:
		check(at.distance_to(o[0]) >= float(o[1]) + SwapHall.RADIUS, "clear of %s" % str(o[0]))
	eq(SwapHall.find_site(flat, others), s, "deterministic")


func test_boards_never_invent_prices() -> void:
	check(SwapHall.wall_text({}, "").contains("reading"))
	check(SwapHall.wall_text({"ok": false, "error": "x"}, "").contains("—"))
	var b := {"ok": true, "block": 5, "tokens": [{"address": "0xa", "name": "NoPool", "symbol": "N", "decimals": 18, "pools": {}, "best": ""},
		{"address": "0xb", "name": "Deep", "symbol": "D", "decimals": 18, "best": "V2",
			"pools": {"V2": {"pair": "0xp", "wpls": BigInt.from_decimal("26000000000000000000"), "token": BigInt.from_decimal("1000000000000000000")}}}]}
	var t := SwapHall.wall_text(b, "0xb")
	check(t.contains("no pool on PulseX"), t)
	check(t.contains("26"), t)
	check(SwapHall.face_text(b, 0).contains("DEEP"), "faces skip tokens with no pool")
	check(SwapPanel.list_line(b["tokens"][0], "").contains("no pool on PulseX"))
