extends TestCase


func test_dysnomia_time() -> void:
	eq(DysnomiaTime.DAY_SECONDS, 115600)
	var t := DysnomiaTime.from_unix(115600 * 3 + 3400 * 2 + 34 * 5 + 7)
	eq([t["day"], t["hour"], t["minute"], t["second"]], [3, 2, 5, 7])
	near(DysnomiaTime.from_unix(57800)["fraction"], 0.5, 1e-12)
	eq(DysnomiaTime.format(0), "day 0 · 00:00:00 DT")
