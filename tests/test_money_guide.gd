extends TestCase
## The Guide's Money page (GuidePanel.money_text): every price comes from the price table
## and every tier name from Development, and it says plainly that Ⓐ grows no territory.
## No network.


func test_prices_come_from_the_table() -> void:
	var G = load("res://scripts/ui/guide_panel.gd")
	var t: String = G.money_text()
	check(t.contains(Prices.play_text()), "a play's price")
	check(t.contains(Prices.strip_text()), "a strip's price")
	check(t.contains(Prices.text(Prices.ROCKET)), "the rocket's price")
	check(t.contains(G.drink_range()), "the drinks' range")
	eq(G.drink_range(), "1–2 Ⓐ")


func test_tiers_and_honesty() -> void:
	var G = load("res://scripts/ui/guide_panel.gd")
	var t: String = G.money_text()
	for tier in Development.TIERS:
		check(t.contains(String(tier["name"])), "tier %s named" % tier["name"])
	check(t.contains("raises no bar and no tier"), "Ⓐ grows nothing, said plainly")
	check(t.contains("Not live yet"), "WORLD and friends marked not live")
	check(t.contains(G.MONEY_URL), "points to the site's money map")
