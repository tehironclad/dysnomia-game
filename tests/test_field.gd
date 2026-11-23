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
