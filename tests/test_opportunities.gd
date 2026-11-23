extends TestCase
## Opportunities and the record: exact arithmetic on chain reads. No network.


func _w(s: String) -> PackedInt64Array:
	return BigInt.from_decimal(s)


func test_ceil_div_and_su_to_pass() -> void:
	eq(BigInt.to_decimal(Opportunities.ceil_div(_w("10"), _w("5"))), "2")
	eq(BigInt.to_decimal(Opportunities.ceil_div(_w("11"), _w("5"))), "3")
	eq(BigInt.to_decimal(Opportunities.ceil_div(PackedInt64Array(), _w("5"))), "0")
	# To pass 100 from 40 at Ω 26: need 61 more → 3 Su (78).
	eq(BigInt.to_decimal(Opportunities.su_to_pass(_w("100"), _w("40"), _w("26"))), "3")
	# A tie is not a pass: 100 vs 100 needs 1 Su.
	eq(BigInt.to_decimal(Opportunities.su_to_pass(_w("100"), _w("100"), _w("26"))), "1")
	eq(BigInt.to_decimal(Opportunities.su_to_pass(_w("100"), _w("101"), _w("26"))), "0", "already ahead")


func test_sections() -> void:
	var me := "0xme"
	var rows := [
		{"address": "0xa", "name": "A", "omega": _w("26"), "board": [
			{"wallet": "0xr", "hypobar": _w("104")}, {"wallet": me, "hypobar": _w("78")}]},
		{"address": "0xb", "name": "B", "omega": _w("1000"), "board": [
			{"wallet": me, "hypobar": _w("5000")}, {"wallet": "0xr", "hypobar": _w("3500")}]},
		{"address": "0xc", "name": "C", "omega": _w("0"), "board": []},
		{"address": "0xd", "name": "D", "omega": _w("50"), "board": []},
	]
	var s := Opportunities.compute(rows, me)
	eq(s["hot"].size(), 3, "Ω = 0 territories are left out")
	eq(s["hot"][0]["name"], "B", "highest Ω first")
	eq(s["reach"].size(), 2)
	eq(s["reach"][0]["name"], "D", "an empty board: 1 Su takes #1")
	eq(s["reach"][1]["su_top"], 2, "A: (104 − 78 + 1) / 26 → 2 Su")
	eq(s["crowns"].size(), 1)
	eq(s["crowns"][0]["margin_su"], 2, "B: the rival needs (5000 − 3500 + 1) / 1000 → 2 Su")
	var b: Array = s["build"].filter(func(e): return e["name"] == "B")
	eq(b[0]["tier"], 1, "8,500 total: outpost")
	eq(b[0]["su"], 2, "to 10,000 at Ω 1000: 2 Su")


func test_streaks() -> void:
	var st := PlayerRecord.streaks([10, 11, 12, 14, 15], 15)
	eq(st["current"], 2)
	eq(st["best"], 3)
	check(st["today_done"])
	st = PlayerRecord.streaks([10, 11, 12], 13)
	eq(st["current"], 3, "today not done yet: the streak is still alive")
	check(not st["today_done"])
	st = PlayerRecord.streaks([10, 11], 13)
	eq(st["current"], 0, "missed yesterday: streak over")
	eq(PlayerRecord.streaks([], 5)["best"], 0)


func test_topic_padding() -> void:
	eq(PlayerRecord.topic_of("0x18f621662d6a1f23700ea32d146b32195dc33111"), "0x00000000000000000000000018f621662d6a1f23700ea32d146b32195dc33111")
