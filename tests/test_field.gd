extends TestCase
## The Field scene builds headless with every territory and selects one.


func test_field_builds_and_selects() -> void:
	var scn: Node = load("res://scenes/field/field.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(scn)
	eq(scn.territories.size(), Registry.count())
	eq(scn.points.multimesh.instance_count, Registry.count())
	scn._select(0, false)
	check(scn._card.visible and scn._warp_btn.visible, "dossier + warp shown")
	check(String(scn._warp_btn.text).begins_with("WARP TO"), scn._warp_btn.text)
	scn._on_filter("Mythic")
	var shown := 0
	for b in scn.visible_mask:
		shown += b
	check(shown > 0 and shown < Registry.count(), "mythic filter: %d" % shown)
	scn.free()


func _rows() -> Array:
	var ts := [
		{"address": "0xa1", "name": "RatKing QING", "symbol": "qRAT", "block": 10, "entropy": "1", "cover_charge": "0", "creator": "0xme"},
		{"address": "0xa2", "name": "Zürich QING", "symbol": "qZů", "block": 11, "entropy": "1", "cover_charge": "414"},
		{"address": "0xa3", "name": "Rat Trap QING", "symbol": "qTRAP", "block": 12, "entropy": "1", "cover_charge": "0"},
		{"address": "0xa4", "name": "Late QING", "symbol": "qLATE", "block": 99, "entropy": "1", "cover_charge": "0"},
	]
	var dev := {"0xa1": {"hypo": "5000000000", "epi": "5", "reactors": 10, "block": 50}, "0xa2": {"hypo": "20000", "epi": "5", "reactors": 30, "block": 50}}
	return FieldIndex.build(ts, func(a): return dev.get(a, {}), 50)


func test_field_index_development_and_unknowns() -> void:
	var rows := _rows()
	eq(FieldIndex.tier_text(rows[0]), "Capital")
	eq(FieldIndex.tier_text(rows[1]), "Settlement")
	eq(FieldIndex.tier_text(rows[2]), "Wild", "founded before the snapshot and not listed: measured Wild")
	eq(FieldIndex.tier_text(rows[3]), "—", "founded after the snapshot: never measured")
	eq(FieldIndex.reactors_text(rows[3]), "—")
	eq(FieldIndex.has_fair(rows[3]), null)
	check(rows[1]["cover"] and not rows[0]["cover"])


func test_field_index_search_and_filters() -> void:
	var rows := _rows()
	var names := func(rs): return rs.map(func(r): return r["name"])
	eq(names.call(FieldIndex.query(rows, "rat")), ["RatKing QING", "Rat Trap QING"], "prefix matches, most developed first")
	eq(names.call(FieldIndex.query(rows, "trap")), ["Rat Trap QING"], "a word inside the name")
	eq(names.call(FieldIndex.query(rows, "#2")), ["Zürich QING"])
	eq(names.call(FieldIndex.query(rows, "0xa3")), ["Rat Trap QING"])
	eq(names.call(FieldIndex.query(rows, "", {"min_tier": 2})), ["RatKing QING", "Zürich QING"], "unmeasured rows fail a tier filter")
	eq(names.call(FieldIndex.query(rows, "", {"fair": true})), ["RatKing QING", "Zürich QING"])
	eq(names.call(FieldIndex.query(rows, "", {"mine": {"0xa1": true}})), ["RatKing QING"])
	eq(names.call(FieldIndex.query(rows, "", {"yue": {}})), [], "an unread/empty set lists nothing, never everything")
	eq(FieldIndex.query(rows, "", {}, 2).size(), 2, "limit")
