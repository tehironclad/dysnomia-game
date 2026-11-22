extends Node3D
## The v2 territory scene (WP 2.2+): ground computed from the territory's
## numbers. Picks the territory from GameManager (if a chain territory was
## loaded) or --qing=0x…, falling back to Illinois Coin QING for previews.
## --view=aerial|ground frames the preview camera.

@onready var terrain: DeepFieldTerrain = $Terrain
@onready var camera: Camera3D = $PreviewCamera
@onready var sky: DeepFieldSky = $Sky
@onready var core: TerritoryCore = $Core

var territory: Dictionary = {}
var state: TerritoryState


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
	sky.setup(terrain.params, String(territory["address"]))
	core.build(terrain.params, territory, terrain.heightfield.core_height)
	state = TerritoryState.new()
	state.name = "State"
	add_child(state)
	state.changed.connect(_on_state_changed)
	state.setup(territory)
	_frame(view)


func _frame(view: String) -> void:
	var core_h := terrain.heightfield.core_height
	if view == "ground":
		camera.position = Vector3(0.0, core_h + 2.0, 40.0)
		camera.look_at(Vector3(0.0, core_h + 40.0, -120.0))
		camera.fov = 70.0
	elif view == "core":
		camera.position = Vector3(6.0, core_h + 4.0, 34.0)
		camera.look_at(Vector3(0.0, core_h + 8.0, 0.0))
		camera.fov = 60.0
	elif view == "sky":
		camera.position = Vector3(0.0, core_h + 2.0, 0.0)
		camera.look_at(camera.position + Vector3(-0.55, 0.62, 0.55))
		camera.fov = 80.0
	else:
		camera.position = Vector3(0.0, 330.0, 330.0)
		camera.look_at(Vector3(0.0, 0.0, 10.0))
		camera.fov = 55.0


## Shared territory state → the world (same for every viewer).
func _on_state_changed() -> void:
	core.set_well("fornax", state.fornax)
	core.set_well("eris", state.eris)
	core.set_well("tethys", state.tethys)
	if state.cover_charge.has_value():
		core.set_door_closed(not BigInt.is_zero(BigInt.coerce(state.cover_charge.value)))
	var reactors: int = int(state.reactors.value) if state.reactors.has_value() else 0
	terrain.set_activity(0.85 + 0.15 * minf(1.0, reactors / 8.0), state.lit_bands())
	Inspector.register(state, "Territory state (block %d)" % state.block,
		"Ω, Hypobar per Su here: %s\nHypobar total %s · Epibar total %s\nReactors: %s\nLit bands on the ground: %d (one per power of ten of the Hypobar total).\nWells: Fornax %s · Eris %s · Tethys %s" % [
			state.omega.display(), state.total_hypobar.display(_dec), state.total_epibar.display(_dec), state.reactors.display(),
			int(state.lit_bands()), state.fornax.display(_tok), state.eris.display(_tok), state.tethys.display(_tok)])


static func _dec(v) -> String:
	return TokenFormat.group(BigInt.to_decimal(BigInt.coerce(v)))


static func _tok(v) -> String:
	return TokenFormat.wei_to_tokens(BigInt.coerce(v))
