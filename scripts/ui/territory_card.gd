class_name TerritoryCard
extends PanelContainer
## A territory's face: its Deep Field picture (drawn live from its Entropy()
## and address), name, rarity and the numbers behind them, each with its
## source. Registers "How is this drawn?" with the Inspector.

var emblem: DeepFieldView
var _name: Label
var _rarity: Label
var _entropy: FactLabel
var _coords: FactLabel
var _address := ""
var _detail_rows: Array = []  # the ENTROPY and MAP rows (hidden when compact)
var compact := false


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	custom_minimum_size = Vector2(320, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	emblem = DeepFieldView.new()
	emblem.custom_minimum_size = Vector2(112, 112)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(emblem)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_name = Label.new()
	_name.theme_type_variation = "DisplayLabel"
	_name.add_theme_font_size_override("font_size", DeepFieldTheme.FS_SMALL)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_name)
	_rarity = Label.new()
	_rarity.theme_type_variation = "MonoLabel"
	col.add_child(_rarity)
	_entropy = _fact_row(col, "ENTROPY")
	_coords = _fact_row(col, "MAP")


func _fact_row(parent: Container, label: String) -> FactLabel:
	var l := Label.new()
	l.theme_type_variation = "MutedLabel"
	l.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	l.text = label
	parent.add_child(l)
	var f := FactLabel.new()
	f.theme_type_variation = "MonoLabel"
	f.add_theme_font_size_override("font_size", DeepFieldTheme.FS_CAPTION)
	f.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	parent.add_child(f)
	_detail_rows.append_array([l, f])
	return f


## The HUD's card: the picture, name and rarity only; the Entropy and map rows
## (still read, still sourced) live in the Inspector (H) and the Field.
func set_compact(c: bool) -> void:
	compact = c
	for n in _detail_rows:
		(n as Control).visible = not c
	emblem.custom_minimum_size = Vector2(88, 88) if c else Vector2(112, 112)


## Shows a territory from the Registry. Returns false if it isn't known yet.
func show_territory(address: String) -> bool:
	_address = address.to_lower()
	var q: Dictionary = Registry.get_territory(_address)
	if q.is_empty() or String(q.get("entropy", "")) == "":
		_name.text = "UNKNOWN TERRITORY"
		_rarity.text = ""
		_entropy.set_fact(Fact.unavailable("QING.Entropy()", "not in the registry yet"))
		_coords.set_fact(Fact.unavailable("HECKE.Compliment(Waat)", "not in the registry yet"))
		emblem.visible = false
		return false
	var p := DeepField.for_territory(q)
	emblem.visible = true
	var why := DeepField.describe(p, "QING.Entropy()", String(q["entropy"]), _address)
	emblem.apply_params(p, why)
	_name.text = String(q.get("name", "")).to_upper()
	_rarity.text = "%s · %s · z^%d" % [p["tier"].to_upper(), p["style"], p["power"]]
	_rarity.add_theme_color_override("font_color", DeepFieldTheme.rarity_color(p["tier"]))
	_entropy.set_fact(Fact.ok(String(q["entropy"]), "QING.Entropy() (fixed at founding; registry, founded block %d)" % int(q["block"])))
	if q.has("lat") and q.has("lon"):
		_coords.set_fact(Fact.ok([float(q["lat"]), float(q["lon"])],
			"HECKE.Compliment(Waat), projected (lon=w0 mod 360e6, lat=w1 mod 180e6); display only"),
			func(v): return "%.4f°, %.4f°" % [v[0], v[1]])
	else:
		_coords.set_fact(Fact.unavailable("HECKE.Compliment(Waat)", "not resolved yet"))
	Inspector.register(self, "Territory card · %s" % q.get("name", _address),
		"Picture: %s\nRarity from Entropy against the site's cut-offs (lib/rarity.js).\nEntropy: %s (QING.Entropy(), fixed at founding; registry, founded block %d)\nMap: %s (HECKE.Compliment(Waat), projected; display only)" % [
			why, String(q["entropy"]), int(q["block"]), _coords.text])
	return true
