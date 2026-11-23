class_name Travel
extends RefCounted
## Going to a territory: every world is a real QING from the Registry.

const TERRITORY_SCENE := "res://scenes/territory/territory_v2.tscn"
const FIELD_SCENE := "res://scenes/field/field.tscn"
const HALL_SCENE := "res://scenes/places/qing_hall.tscn"
const VOID_SCENE := "res://scenes/places/void_place.tscn"


## Sets the destination and changes scene. Returns false (and changes nothing)
## if the address is not a known territory.
static func go(tree: SceneTree, address: String) -> bool:
	var reg: Node = tree.root.get_node("Registry")
	var q: Dictionary = reg.get_territory(address)
	if q.is_empty():
		return false
	var gm: Node = tree.root.get_node("GameManager")
	gm.territory_address = String(q["address"])
	gm.territory_name = String(q.get("name", ""))
	gm.is_chain_sourced = true
	tree.change_scene_to_file(TERRITORY_SCENE)
	return true


## A territory by name/symbol search, or by its founding index ("#12").
static func resolve(tree: SceneTree, text: String) -> String:
	var reg: Node = tree.root.get_node("Registry")
	text = text.strip_edges()
	if text.begins_with("0x") and text.length() == 42:
		return text.to_lower() if reg.has_territory(text) else ""
	if text.begins_with("#") and text.substr(1).is_valid_int():
		var i := int(text.substr(1)) - 1
		return reg.all()[i]["address"] if i >= 0 and i < reg.count() else ""
	var hits: Array = reg.search(text, 1)
	return hits[0]["address"] if not hits.is_empty() else ""


static func random_address(tree: SceneTree) -> String:
	var all: Array = tree.root.get_node("Registry").all()
	return all[randi() % all.size()]["address"] if not all.is_empty() else ""


## The Field: the globe of every territory.
static func field(tree: SceneTree) -> void:
	tree.change_scene_to_file(FIELD_SCENE)


## Inside the current territory's QING: its chat hall (back out through the door).
static func hall(tree: SceneTree) -> void:
	tree.change_scene_to_file(HALL_SCENE)


## The Void (back out through the portal to the current territory).
static func void_place(tree: SceneTree) -> void:
	tree.change_scene_to_file(VOID_SCENE)
