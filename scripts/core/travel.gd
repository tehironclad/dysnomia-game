class_name Travel
extends RefCounted
## Going to a territory: every world is a real QING from the Registry.

const TERRITORY_SCENE := "res://scenes/territory/territory_v2.tscn"
const FIELD_SCENE := "res://scenes/field/field.tscn"
const HALL_SCENE := "res://scenes/places/qing_hall.tscn"
const VOID_SCENE := "res://scenes/places/void_place.tscn"
const ARCADE_SCENE := "res://scenes/places/arcade_place.tscn"
const PUB_SCENE := "res://scenes/places/sunny_pub.tscn"

## A walk through a door in progress (DoorSequence): which territory door
## ("room" | "void" | "arcade") and which way. Read once on arrival.
static var door := ""
static var door_inbound := false
static var _door_pending := false


## Sets the destination and changes scene. Returns false (and changes nothing)
## if the address is not a known territory.
static func go(tree: SceneTree, address: String) -> bool:
	_door_pending = false
	return _go(tree, address)


static func _go(tree: SceneTree, address: String) -> bool:
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


## The current territory's arcade (cabinets, pool and cards).
static func arcade(tree: SceneTree) -> void:
	tree.change_scene_to_file(ARCADE_SCENE)


## Sunny's Pub, in TehSunFlowrScioety QING.
static func pub(tree: SceneTree) -> void:
	tree.change_scene_to_file(PUB_SCENE)


# --- Doors (DoorSequence plays the walk; these change the scene) -------------

## The place behind a territory door ("room" | "void" | "arcade").
static func place_scene(kind: String, address: String) -> String:
	match kind:
		"room": return HALL_SCENE
		"void": return VOID_SCENE
		"arcade": return PUB_SCENE if ArcadeFront.pub_for(address) else ARCADE_SCENE
	return ""


## The territory door a place's exit comes out of.
static func door_of_scene(path: String) -> String:
	match path:
		HALL_SCENE: return "room"
		VOID_SCENE: return "void"
		ARCADE_SCENE, PUB_SCENE: return "arcade"
	return ""


## In through a territory door: the place arrives walking in from its entrance.
static func through_door(tree: SceneTree, kind: String) -> void:
	var scene := place_scene(kind, String(tree.root.get_node("GameManager").territory_address))
	if scene == "":
		return
	door = kind
	door_inbound = true
	_door_pending = true
	tree.change_scene_to_file(scene)


## Out of a place: back to the territory, out of the same building's door.
static func out_door(tree: SceneTree, kind: String) -> bool:
	door = kind
	door_inbound = false
	_door_pending = kind != ""
	var ok := _go(tree, String(tree.root.get_node("GameManager").territory_address))
	if not ok:
		_door_pending = false
	return ok


## The door this scene was reached through, read once ("" = none).
static func take_door(inbound: bool) -> String:
	if not _door_pending or door_inbound != inbound:
		return ""
	_door_pending = false
	return door
