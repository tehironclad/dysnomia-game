class_name TableRecordSigns
extends Node
## Floating "QING RECORD" signs over the Cantina game tables. Reads MinigameRecords and
## refreshes whenever a record changes. Attach once after the pub is built:
##   TableRecordSigns.attach(pub_building)

const GAME_TYPES := ["entropy_dice", "waat_slots", "territory_trivia", "card_match"]
const NAMES := ["Entropy Dice", "WAAT Slots", "Territory Trivia", "Contract Match"]

var _labels: Array = []   # [Label3D, game_type]


static func attach(pub_building: Node) -> TableRecordSigns:
	if pub_building == null:
		return null
	var interior = pub_building.get("_interior")
	if interior == null:
		return null
	var tables: Array = interior.get("game_table_nodes") if interior.get("game_table_nodes") != null else []
	var n := TableRecordSigns.new()
	n.name = "TableRecordSigns"
	pub_building.add_child(n)
	for i in mini(tables.size(), GAME_TYPES.size()):
		var t: Node3D = tables[i]
		if not is_instance_valid(t):
			continue
		var l := Label3D.new()
		l.name = "RecordSign"
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.pixel_size = 0.0035
		l.font_size = 30
		l.outline_size = 8
		l.outline_modulate = Color(0.02, 0.01, 0.05, 0.9)
		l.modulate = DysnomiaLore.AFFECTION_PINK.lightened(0.25)
		l.position = Vector3(0, 1.85, 0)
		l.no_depth_test = false
		t.add_child(l)
		n._labels.append([l, GAME_TYPES[i]])
	n._refresh("")
	MinigameRecords.bus.records_changed.connect(n._refresh)
	GameManager.territory_data_changed.connect(func(_d: Dictionary) -> void:
		if is_instance_valid(n):
			n._refresh(""))
	return n


func _refresh(_game_type: String) -> void:
	for e in _labels:
		var l: Label3D = e[0]
		if not is_instance_valid(l):
			continue
		var r := MinigameRecords.qing_record(e[1])
		if r.is_empty():
			l.text = "QING RECORD\nunclaimed — be the first"
		else:
			l.text = "QING RECORD\n%d · %s" % [int(r["score"]), str(r["player"]).left(16)]


func _exit_tree() -> void:
	if MinigameRecords.bus.records_changed.is_connected(_refresh):
		MinigameRecords.bus.records_changed.disconnect(_refresh)
