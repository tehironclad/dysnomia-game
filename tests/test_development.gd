extends TestCase
## Development tiers from a territory's Hypobar total; energy from its Epibar total.


func _w(s: String) -> PackedInt64Array:
	return BigInt.from_decimal(s)


func test_tiers() -> void:
	eq(Development.tier_of(PackedInt64Array()), 0, "no bars: wild")
	eq(Development.tier_of(_w("26")), 1, "any bars: outpost")
	eq(Development.tier_of(_w("2704")), 1, "Illinois (2,704 Hypobar): outpost")
	eq(Development.tier_of(_w("10000")), 2)
	eq(Development.tier_of(_w("2000000")), 3, "enter teh QING (10^6.3): town")
	eq(Development.tier_of(_w("316000000")), 4, "Zürich (10^8.5): city")
	eq(Development.tier_of(_w("1260000000")), 5, "RatKing (10^9.1): capital")
	eq(Development.tier_name(5), "Capital")


func test_thresholds_and_energy() -> void:
	eq(Development.next_threshold(0), "1")
	eq(Development.next_threshold(1), "10000")
	eq(Development.next_threshold(5), "", "nothing above Capital")
	near(Development.energy_of(PackedInt64Array()), 0.0, 1e-9)
	near(Development.energy_of(_w("100")), 0.0, 1e-6)
	near(Development.energy_of(_w("10000000000")), 1.0, 1e-6)
	check(Development.energy_of(_w("1000000")) > Development.energy_of(_w("1000")))


func test_tower_floors() -> void:
	eq(BarColumns.floors_for(PackedInt64Array()), 0)
	eq(BarColumns.floors_for(_w("1")), 1, "at least one floor once there are bars")
	check(BarColumns.floors_for(_w("1260000000")) >= 12, "RatKing-scale bars make a tall tower")
