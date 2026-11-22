extends Node3D
## The v2 territory scene (WP 2.2+): ground computed from the territory's
## numbers. Picks the territory from GameManager (if a chain territory was
## loaded) or --qing=0x…, falling back to Illinois Coin QING for previews.
## --view=aerial|ground frames the preview camera.

@onready var terrain: DeepFieldTerrain = $Terrain
@onready var camera: Camera3D = $PreviewCamera

var territory: Dictionary = {}


func _ready() -> void:
	var addr := ""
	var view := "aerial"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			addr = a.substr(7)
		elif a.begins_with("--view="):
			view = a.substr(7)
	if addr == "" and GameManager.is_chain_sourced:
		addr = GameManager.territory_address
	if addr == "":
		addr = "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
	territory = Registry.get_territory(addr)
	if territory.is_empty():
		push_error("[TerritoryV2] unknown territory %s" % addr)
		return
	terrain.build(territory)
	_frame(view)


func _frame(view: String) -> void:
	var core_h := terrain.heightfield.core_height
	if view == "ground":
		camera.position = Vector3(0.0, core_h + 2.0, 40.0)
		camera.look_at(Vector3(0.0, core_h + 4.0, -120.0))
		camera.fov = 70.0
	else:
		camera.position = Vector3(0.0, 330.0, 330.0)
		camera.look_at(Vector3(0.0, 0.0, 10.0))
		camera.fov = 55.0
