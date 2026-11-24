extends TestCase
## The shipped development snapshot: real chain measurements, labelled with a block.


func test_shipped_snapshot_has_ratking_as_capital() -> void:
	var b := DevelopmentSnapshot.shipped_block()
	check(b > 0, "the shipped snapshot carries its block")
	var rk := ""
	for q in Registry.all():
		if String(q["name"]) == "RatKing QING":
			rk = String(q["address"])
	check(rk != "", "RatKing is in the registry")
	var rec := DevelopmentSnapshot.lookup(rk)
	check(not rec.is_empty(), "RatKing was measured with bars")
	var d := DevelopmentSnapshot.apply(rec)
	eq(d["tier"], 5, "RatKing is a Capital in the snapshot")
	eq(FairSite.fair_tier(d["tier"]), 3, "so it gets the Grand Fair before any live read")
	check(int(d["block"]) > 0)


func test_unmeasured_territory_is_not_invented() -> void:
	eq(DevelopmentSnapshot.lookup("0x000000000000000000000000000000000000dead"), {}, "no record, no development")


func test_snapshot_values_are_decimal_strings() -> void:
	var f := FileAccess.open(DevelopmentSnapshot.SHIPPED_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	for k in d["territories"]:
		var r: Dictionary = d["territories"][k]
		check(r["hypo"] is String and DevelopmentSnapshot._digits(r["hypo"]), "hypo is a decimal string (never a float)")
		check(r["epi"] is String and DevelopmentSnapshot._digits(r["epi"]))
		check(r["hypo"] != "0", "only territories with bars are listed")
