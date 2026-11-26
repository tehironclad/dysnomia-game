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


## Settings: sliders show what they hold (mouse sensitivity 0.003 used to read "0%").
func test_settings_slider_text() -> void:
	var sm = load("res://scripts/ui/settings_menu.gd")
	eq(sm.slider_text(0.003, 0.01, 0.0005), "0.0030")
	eq(sm.slider_text(0.8, 1.0, 0.05), "80%")
	eq(sm.slider_text(1300.0, 2000.0, 50.0), "1300")
	eq(sm.slider_text(70.0, 110.0, 1.0), "70")


## Settings fit a 720p window: the panel scrolls instead of running off the bottom.
func test_settings_panel_fits_a_short_window() -> void:
	var p := PanelContainer.new()
	p.set_script(load("res://scripts/ui/settings_menu.gd"))
	_root().add_child(p)
	p._fit()
	check(p.size.y <= p.get_viewport_rect().size.y, "panel %s taller than the window %s" % [p.size, p.get_viewport_rect().size])
	p.free()
