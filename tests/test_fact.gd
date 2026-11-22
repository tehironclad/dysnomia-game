extends TestCase


func test_states_display_distinctly() -> void:
	eq(Fact.loading("X()").display(), "…")
	eq(Fact.unavailable("X()", "timeout").display(), "—")
	eq(Fact.empty("X()").display(), "none")
	eq(Fact.ok(0, "X()", 5).display(), "0")
	eq(Fact.floor_of(55, "players", "snapshot list").display(), "≥ 55")
	check(not Fact.unavailable("X()").has_value())
	check(Fact.ok(0, "X()").has_value(), "zero is a value")


func test_provenance() -> void:
	eq(Fact.ok("1", "QING.Entropy()", 28124253).provenance(), "QING.Entropy() · block 28124253")
	eq(Fact.unavailable("YUE.Bar()", "timeout").provenance(), "YUE.Bar() · unavailable: timeout")
	eq(Fact.ok(1234567, "x").display(func(v): return "%d!" % v), "1234567!")


func test_parse_new_qing() -> void:
	var data := "0x" + "000000000000000000000000a3ec12ef8b48835f5da2046b897ca2cd3681ac57" \
		+ "00000000000000000000000095feb253a2e7b262bc604bb5dfd7d6775c15fd9f" + "0".repeat(62) + "2a"
	var rec: Dictionary = load("res://scripts/data/territory_registry.gd").parse_new_qing({"data": data, "blockNumber": "0x1ad0bca"})
	eq(rec["address"], "0xa3ec12ef8b48835f5da2046b897ca2cd3681ac57")
	eq(rec["asset"], "0x95feb253a2e7b262bc604bb5dfd7d6775c15fd9f")
	eq(rec["waat"], "42")
	eq(rec["block"], 28117962)
