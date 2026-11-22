extends TestCase
## UI components built in a headless tree.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_territory_card_shows_real_numbers() -> void:
	var card := TerritoryCard.new()
	_root().add_child(card)
	check(card.show_territory(ILLINOIS), "Illinois should be in the registry")
	var q: Dictionary = Registry.get_territory(ILLINOIS)
	eq(card._name.text, "ILLINOIS COIN QING")
	eq(card._rarity.text, "EPIC · duo · z^2")
	eq(card._entropy.text, String(q["entropy"]))
	check(card._entropy.tooltip_text.begins_with("QING.Entropy()"), card._entropy.tooltip_text)
	eq(card._coords.text, "%.4f°, %.4f°" % [float(q["lat"]), float(q["lon"])])
	var titles: Array = Inspector.visible_entries().map(func(e): return e["title"])
	check(titles.has("Deep Field picture"), "emblem registered: %s" % str(titles))
	check(titles.has("Territory card · Illinois Coin QING"), "card registered: %s" % str(titles))
	var n_before := Inspector.visible_entries().size()
	card.free()
	eq(Inspector.visible_entries().size(), n_before - 2, "entries leave with their nodes")


func test_unknown_territory_is_unavailable_not_zero() -> void:
	var card := TerritoryCard.new()
	_root().add_child(card)
	check(not card.show_territory("0x000000000000000000000000000000000000dead"))
	eq(card._entropy.text, "—")
	card.free()
