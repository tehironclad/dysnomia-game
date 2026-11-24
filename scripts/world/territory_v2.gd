extends Node3D
## The v2 territory scene (WP 2.2+): ground computed from the territory's
## numbers. Picks the territory from GameManager (if a chain territory was
## loaded) or --qing=0x…, falling back to Illinois Coin QING for previews.
## --view=aerial|ground frames the preview camera.

@onready var terrain: DeepFieldTerrain = $Terrain
@onready var camera: Camera3D = $PreviewCamera
@onready var sky: DeepFieldSky = $Sky
@onready var core: TerritoryCore = $Core
@onready var player: CharacterBody3D = $Player
@onready var hud: HudV2 = $Hud

var territory: Dictionary = {}
var state: TerritoryState
var columns: BarColumns
var development: DevelopmentSite
var dev_tier := 0
var dev_snapshot := {}   # the earlier measurement in use until the live read lands
var dev_source := "—"
var monolith: VoidMonolith
var arcade: ArcadeFront
var fair: FairSite
var garage: GarageSite
var landmark: Landmark      # skyline landmark + base jumping (scripts/world/skyline/)
var base_jump: BaseJump
var phenomena: Phenomena
var actions: CoreActions
var lattice: WorldLattice
var help: ControlsHelp
var guide: GuidePanel
var opportunities: OpportunitiesPanel
var score: TerritoryScore
var border: BorderRing
var roads: TerritoryRoads  # the Core's ring road and roads to every place (scripts/world/roads/)
var chat_life: ChatLife  # room chat in the world: bubbles, echoes, glow, tower markers
var _settings: PanelContainer
var _monitor: Control
var _near := ""
var view_mode := ""  # su | room | beat | void | ""

const MONOLITH_AT := Vector2(-26.0, 18.0)
const PROMPTS := {
	"su": "Su: react with this territory (your bars grow, +1 YUE)",
	"room": "enter the hall: this QING's room",
	"beat": "Beat at the Heart",
	"void": "step into the Void: one board for everyone",
	"world": "WORLD: your range here (latent until deployed)",
	"arcade": "go into the arcade: cabinets, pool and cards",
	"pub": "go into Sunny's Pub: the bar, the arcade, pool and cards",
}


func _ready() -> void:
	var addr := ""
	var view := ""
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
	Config.register_scene($WorldEnvironment.environment, $Sun)
	terrain.build(territory)
	Config.register_terrain(terrain.material)
	sky.setup(terrain.params, String(territory["address"]))
	Config.register_sky(sky.material)
	Config.auto_changed.connect(func(t): hud.ticker(t, DeepFieldTheme.ICE, 14.0))
	core.build(terrain.params, territory, terrain.heightfield.core_height)
	state = TerritoryState.new()
	state.name = "State"
	add_child(state)
	state.changed.connect(_on_state_changed)
	state.setup(territory)
	hud.bind(String(territory["address"]), state, sky)
	columns = BarColumns.new()
	columns.name = "BarColumns"
	var core_y := terrain.heightfield.core_height
	columns.setup(DeepField.to_color(terrain.params["color"]), func(x, z): return terrain.get_height_at(x, z) - core_y)
	core.add_child(columns)
	development = DevelopmentSite.new()
	development.name = "Development"
	development.setup(DeepField.to_color(terrain.params["color"]))
	core.add_child(development)
	monolith = VoidMonolith.new()
	monolith.name = "VoidMonolith"
	add_child(monolith)
	monolith.build()
	monolith.position = Vector3(MONOLITH_AT.x, terrain.get_height_at(MONOLITH_AT.x, MONOLITH_AT.y) - 0.2, MONOLITH_AT.y)
	monolith.look_at(Vector3(0.0, monolith.position.y, 0.0), Vector3.UP, true)
	phenomena = Phenomena.new()
	phenomena.name = "Phenomena"
	add_child(phenomena)
	phenomena.setup(String(territory["address"]), core, hud, monolith, state, terrain.heightfield.core_height)
	actions = CoreActions.new()
	actions.name = "Actions"
	add_child(actions)
	actions.setup(territory, state, core, hud, phenomena, monolith)
	arcade = ArcadeFront.new()
	arcade.name = "Arcade"
	core.add_child(arcade)
	arcade.build(String(territory["address"]), DeepField.to_color(terrain.params["color"]))
	arcade.position = Vector3(ArcadeFront.AT.x, terrain.get_height_at(core.global_position.x + ArcadeFront.AT.x, core.global_position.z + ArcadeFront.AT.y) - core_y - 0.3, ArcadeFront.AT.y)
	arcade.look_at(core.global_position + Vector3(0.0, arcade.global_position.y - core.global_position.y, 0.0), Vector3.UP, true)
	# The Affection Fair: rides paid in Ⓐ to this QING, sized by Development
	fair = FairSite.new()
	fair.name = "AffectionFair"
	core.add_child(fair)
	fair.setup(String(territory["address"]), hud, player,
		func(x, z): return terrain.get_height_at(core.global_position.x + x, core.global_position.z + z) - core_y,
		DeepField.to_color(terrain.params["color"]), terrain.material)
	fair.set_dev_tier(0)
	# The vehicle pad near arrival (unlocks from the viewer's own chain state)
	garage = GarageSite.new()
	garage.name = "Garage"
	core.add_child(garage)
	garage.setup(String(territory["address"]), hud, player, state,
		func(x, z): return terrain.get_height_at(core.global_position.x + x, core.global_position.z + z) - core_y,
		func(x, z): return terrain.get_height_at(x, z), DeepField.to_color(terrain.params["color"]), terrain.material,
		[[Vector2(fair.position.x, fair.position.z), FairSite.RADIUS + 10.0]])
	_add_landmark(core_y)
	chat_life = ChatLife.new()
	chat_life.name = "ChatLife"
	core.add_child(chat_life)
	chat_life.setup(core, columns, state, player, DeepField.to_color(terrain.params["color"]))
	_apply_development_snapshot()
	lattice = WorldLattice.new()
	lattice.name = "WorldLattice"
	core.add_child(lattice)
	lattice.build(DeepField.to_color(terrain.params["color"]))
	actions.lattice = lattice
	if Config.last_note != "":
		hud.ticker(Config.last_note, DeepFieldTheme.ICE, 14.0)
		Config.last_note = ""
	World.launched.connect(func(_a): hud.ticker("WORLD DEPLOYED · verified on-chain · block %d" % World.block, Color("#ffd27a"), 120.0))
	World.start()
	score = TerritoryScore.new()
	score.name = "Score"
	add_child(score)
	if view == "" or OS.get_cmdline_user_args().has("--score"):
		score.play_for(String(territory["address"]), terrain.params, String(territory.get("entropy", "1")))
	help = ControlsHelp.new()
	help.position = Vector2(20, 240)
	hud.add_child(help)
	opportunities = OpportunitiesPanel.new()
	opportunities.set_anchors_preset(Control.PRESET_CENTER)
	opportunities.position = Vector2(-310, -320)
	hud.add_child(opportunities)
	Session.lead_changed.connect(func(lost, gained, block):
		for a in lost:
			hud.ticker("LEAD LOST · %s · someone passed you · block %d" % [String(Registry.get_territory(a).get("name", a)), block], Color("#ff8fa0"), 60.0)
		for a in gained:
			hud.ticker("LEAD TAKEN · %s · block %d" % [String(Registry.get_territory(a).get("name", a)), block], Color("#ffd27a"), 60.0))
	guide = GuidePanel.new()
	guide.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	guide.position = Vector2(-560, 130)
	hud.add_child(guide)
	if view == "":
		Acts.set_flag("", "arrived")
	actions.opened.connect(func(): player.process_mode = Node.PROCESS_MODE_DISABLED)
	actions.closed.connect(func(): if view_mode == "": player.process_mode = Node.PROCESS_MODE_INHERIT)
	Session.changed.connect(_on_state_changed)
	GameManager.territory_address = String(territory["address"])
	GameManager.territory_name = String(territory.get("name", ""))
	# The player arrives in front of the Room's door.
	var core_h := terrain.heightfield.core_height
	player.position = Vector3(0.0, core_h + 1.0, 16.0)
	player.rotation.y = 0.0
	if player.has_method("set_terrain_generator"):
		player.set_terrain_generator(terrain)
	# --- Borders (BorderRing): neighbouring QINGs beyond force fields; a border crossing lands here.
	border = BorderRing.new()
	border.name = "Borders"
	add_child(border)
	border.setup(territory, terrain, player if view == "" else null, hud if view == "" else null)
	if view == "":
		border.place_arrival()
	# --- end Borders
	roads = TerritoryRoads.new()
	roads.name = "Roads"
	add_child(roads)
	_build_roads()
	# --- Online (Net): other players here, free chat and voice; nothing when offline.
	if view == "":
		var presence := NetPresence.new()
		presence.name = "NetPresence"
		add_child(presence)
		presence.setup(String(territory["address"]), player, hud)
	# --- end Online
	view_mode = view
	if view == "":
		# Play: the player's camera. (With no current camera, Godot would pick
		# the first in tree order: the preview camera, under the ground.)
		camera.queue_free()
		var pc: Camera3D = player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
		if pc:
			pc.current = true
	else:
		_frame(view)  # screenshot/preview: fixed camera, no player
		camera.current = true
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.visible = false
		hud.visible = view == "hud"


func _frame(view: String) -> void:
	var core_h := terrain.heightfield.core_height
	if view == "hud":
		camera.position = Vector3(0.0, core_h + 2.5, 34.0)
		camera.look_at(Vector3(0.0, core_h + 6.0, 0.0))
		camera.fov = 65.0
	elif view == "ground":
		camera.position = Vector3(0.0, core_h + 2.0, 40.0)
		camera.look_at(Vector3(0.0, core_h + 40.0, -170.0))
		camera.fov = 70.0
	elif view == "core":
		camera.position = Vector3(6.0, core_h + 4.0, 34.0)
		camera.look_at(Vector3(0.0, core_h + 8.0, 0.0))
		camera.fov = 60.0
	elif view == "fair" and fair:
		# Looking at the Affection Fair from its arrival side
		var f := fair.global_position
		camera.position = f + Vector3(0.0, 28.0, -95.0)
		camera.look_at(f + Vector3(0.0, 8.0, 0.0))
		camera.fov = 60.0
	elif view == "garage" and garage:
		camera.global_transform = garage.preview_transform()
		camera.fov = 62.0
	elif view.begins_with("border") and border:  # --view=border_n|e|s|w: across a force field
		border.frame_camera(camera, view.substr(7) if view.length() > 7 else "n")
	elif view == "chat" and chat_life:  # the Room's front: echoes, bubbles, glow
		chat_life.frame(camera)
	elif view == "relief":  # from the highest ground, back over the terraces
		terrain.frame_relief(camera)
	elif view in ["tower", "deck", "jump"] and landmark:
		_frame_landmark(view)
	elif view == "sky":
		camera.position = Vector3(0.0, core_h + 2.0, 0.0)
		camera.look_at(camera.position + Vector3(-0.55, 0.62, 0.55))
		camera.fov = 80.0
	else:
		var d := 330.0 * TerritoryLayout.SCALE  # the whole territory in frame
		camera.position = Vector3(0.0, d, d)
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
	if state.total_hypobar.has_value():
		columns.update_board(state.board, state.block, Session.wallet)
		# Development: tier from the Hypobar total, energy from the Epibar total.
		var hypo := BigInt.coerce(state.total_hypobar.value)
		var epi := BigInt.coerce(state.total_epibar.value) if state.total_epibar.has_value() else PackedInt64Array()
		var energy := Development.energy_of(epi)
		# Bars never shrink: a live total below the earlier measurement means some
		# reads came back short, so the earlier (higher) block-labelled total stands.
		if not dev_snapshot.is_empty() and BigInt.cmp(hypo, dev_snapshot["hypo"]) < 0:
			print("[Development] live total at block %d is below the snapshot at block %d; keeping the snapshot" % [state.block, dev_snapshot["block"]])
		else:
			dev_snapshot = {}
			dev_source = "live · block %d" % state.block
			if state.block > 0 and not BigInt.is_zero(hypo):
				DevelopmentSnapshot.remember(String(territory["address"]), BigInt.to_decimal(hypo), BigInt.to_decimal(epi),
					int(state.reactors.value) if state.reactors.has_value() else 0, state.block)
			_set_development(Development.tier_of(hypo), hypo, energy, state.board, state.block)
	var model := player.get_node_or_null("PlayerModel")
	if model and model.has_method("set_territory_power"):
		model.set_territory_power(clampf(state.lit_bands() / 10.0, 0.0, 1.0))
	Inspector.register(state, "Territory state (block %d)" % state.block,
		"Development: %s (from the Hypobar total, a floor over known players; bars never shrink, so neither does the city).\nΩ, Hypobar per Su here: %s\nHypobar total %s · Epibar total %s\nReactors: %s\nLit bands on the ground: %d (one per power of ten of the Hypobar total).\nWells: Fornax %s · Eris %s · Tethys %s" % [
			Development.describe(dev_tier) + " (" + dev_source + ")", state.omega.display(), state.total_hypobar.display(_dec), state.total_epibar.display(_dec), state.reactors.display(),
			int(state.lit_bands()), state.fornax.display(_tok), state.eris.display(_tok), state.tethys.display(_tok)])


## Build the world at this territory's last measured development right away
## (shipped snapshot or this machine's last live read, labelled with its block);
## the live read replaces it when it lands. Same for every viewer, wallet or not.
func _apply_development_snapshot() -> void:
	var rec := DevelopmentSnapshot.lookup(String(territory["address"]))
	if rec.is_empty():
		return
	var d := DevelopmentSnapshot.apply(rec)
	dev_snapshot = d
	dev_source = "measured at block %d, live read pending" % d["block"]
	print("[Development] %s · tier %d (%s) from block %d (%s)" % [territory.get("name", ""), d["tier"],
		Development.tier_name(d["tier"]), d["block"], rec.get("source", "")])
	_set_development(d["tier"], d["hypo"], d["energy"], [], d["block"])


func _set_development(tier: int, hypo: PackedInt64Array, energy: float, board: Array, block: int) -> void:
	dev_tier = tier
	columns.set_energy(energy)
	development.set_tier(dev_tier, energy)
	if fair:
		fair.set_dev_tier(dev_tier)
	if landmark:
		landmark.set_development(dev_tier, hypo, energy, board, block)
	terrain.set_development(dev_tier, energy)
	sky.set_aurora(energy if dev_tier >= 4 else 0.0)
	if roads:
		_build_roads()


static func _dec(v) -> String:
	return TokenFormat.group(BigInt.to_decimal(BigInt.coerce(v)))


static func _tok(v) -> String:
	return TokenFormat.wei_to_tokens(BigInt.coerce(v))


# --- Roads (scripts/world/roads/) ------------------------------------------------

## The places a road reaches (Core-relative = world x, z: the Core stands at the
## origin). A new building adds itself here: {name, at, r[, from]}.
func _road_places() -> Array:
	var out: Array = [
		{"name": "vehicle pad", "at": Vector2(garage.position.x, garage.position.z), "r": GarageSite.RADIUS},
		{"name": "Affection Fair", "at": Vector2(fair.position.x, fair.position.z), "r": FairSite.RADIUS},
	]
	if landmark and not LandmarkPlan.spec(dev_tier, 0.0).is_empty():  # the landmark stands from Settlement up
		var t := Vector2(landmark.position.x, landmark.position.z)
		var r := landmark.ring_local()
		out.append({"name": "skyline landmark", "at": t, "r": LandmarkPlan.PLAZA_R})
		out.append({"name": "landing ring", "at": Vector2(r.x, r.z), "r": LandmarkPlan.RING_R, "from": t})
	return out


func _build_roads() -> void:
	var gates: Array = []
	for side in Neighbours.SIDES:
		if border and border.sides.has(side):  # a road to every border with a QING beyond it
			gates.append(Neighbours.outward(side) * (JuliaHeightfield.SIZE_M * 0.5))
	roads.build(func(x, z): return terrain.get_height_at(x, z), terrain.material, _road_places(), gates,
		dev_tier, DeepField.to_color(terrain.params["color"]))


# --- Skyline landmark + base jumping (scripts/world/skyline/) ------------------

func _add_landmark(core_y: float) -> void:
	var tint := DeepField.to_color(terrain.params["color"])
	landmark = Landmark.new()
	landmark.name = "Landmark"
	core.add_child(landmark)
	landmark.setup(String(territory["address"]), String(territory.get("name", "")), hud, player,
		func(x, z): return terrain.get_height_at(core.global_position.x + x, core.global_position.z + z) - core_y,
		tint, terrain.material, [[Vector2(fair.position.x, fair.position.z), FairSite.RADIUS],
			[Vector2(garage.position.x, garage.position.z), GarageSite.RADIUS]])
	base_jump = BaseJump.new()
	base_jump.name = "BaseJump"
	add_child(base_jump)
	base_jump.setup(player, hud, landmark, columns, String(territory["address"]),
		func(x, z): return terrain.get_height_at(x, z), core, tint)


## --view=tower|deck|jump: framed once the tower is built (it needs the chain read).
func _frame_landmark(view: String) -> void:
	camera.position = Vector3(0.0, 330.0, 330.0)
	camera.look_at(Vector3(0.0, 0.0, 10.0))
	landmark.built.connect(func() -> void:
		landmark.frame(view, camera)
		if view == "jump":
			var d := landmark.plank_dir()
			var p := landmark.jump_preview_at()
			player.process_mode = Node.PROCESS_MODE_ALWAYS
			player.set_physics_process(false)
			base_jump.preview(p, d, "wingsuit"), CONNECT_DEFERRED)


## Which live move is in reach of the player (positions relative to the Core).
static func zone_at(local: Vector3, monolith_local: Vector3) -> String:
	var xz := Vector2(local.x, local.z)
	if xz.distance_to(Vector2(-TerritoryCore.PYLON_GAP, 0.0)) < 4.0 or xz.distance_to(Vector2(TerritoryCore.PYLON_GAP, 0.0)) < 4.0:
		return "su"
	if xz.length() < 3.0:
		return "beat"
	if xz.distance_to(Vector2(0.0, TerritoryCore.ROOM_RADIUS)) < 3.0:
		return "room"
	if xz.distance_to(Vector2(monolith_local.x, monolith_local.z)) < 4.5:
		return "void"
	if xz.distance_to(Vector2(WorldLattice.PLINTH_AT.x, WorldLattice.PLINTH_AT.z)) < 2.5:
		return "world"
	if xz.distance_to(arcade_door()) < ArcadeFront.DOOR_REACH:
		return "arcade"
	return ""


## The arcade's door (relative to the Core): its front faces the Core.
static func arcade_door() -> Vector2:
	return ArcadeFront.AT - ArcadeFront.AT.normalized() * 4.2


func _process(_delta: float) -> void:
	if view_mode != "" or actions == null or actions.is_open():
		return
	var z := zone_at(player.global_position - core.global_position, monolith.global_position - core.global_position)
	if z != _near:
		_near = z
		if z == "":
			hud.hide_prompt()
		else:
			var key := "pub" if z == "arcade" and arcade and arcade.is_pub else z
			hud.show_prompt("%s  %s" % [ControlsHelp.key_of("interact"), PROMPTS[key]])


func _unhandled_input(event: InputEvent) -> void:
	if actions != null and actions.is_open():
		return
	if event.is_action_pressed("interact") and _near != "":
		get_viewport().set_input_as_handled()
		hud.hide_prompt()
		match _near:
			"su": actions.open_su()
			"room": Travel.hall(get_tree())
			"beat": actions.open_beat()
			"void": Travel.void_place(get_tree())
			"world": actions.open_world()
			"arcade": Travel.pub(get_tree()) if arcade and arcade.is_pub else Travel.arcade(get_tree())
		_near = ""
		return
	if event.is_action_pressed("open_field"):
		get_viewport().set_input_as_handled()
		Travel.field(get_tree())
	elif event.is_action_pressed("controls_help"):
		help.toggle()
	elif event.is_action_pressed("guide"):
		guide.toggle()
	elif event.is_action_pressed("opportunities"):
		opportunities.toggle()
		player.process_mode = Node.PROCESS_MODE_DISABLED if opportunities.is_open() else Node.PROCESS_MODE_INHERIT
		if not opportunities.is_open():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("settings"):
		_toggle_settings()
	elif event.is_action_pressed("toggle_debug"):
		_toggle_monitor()


func _toggle_settings() -> void:
	if _settings == null:
		_settings = PanelContainer.new()
		_settings.set_script(load("res://scripts/ui/settings_menu.gd"))
		_settings.visible = false
		hud.add_child(_settings)
		_settings.settings_closed.connect(func():
			_settings.hide_menu()
			player.process_mode = Node.PROCESS_MODE_INHERIT
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED))
	if _settings.visible:
		_settings.hide_menu()
		player.process_mode = Node.PROCESS_MODE_INHERIT
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		_settings.show_menu()
		player.process_mode = Node.PROCESS_MODE_DISABLED


## F3: the performance overlay (FPS, process time, draw calls, memory…).
func _toggle_monitor() -> void:
	if _monitor == null:
		_monitor = VBoxContainer.new()
		_monitor.set_script(load("res://scripts/debug/monitor_overlay.gd"))
		_monitor.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_monitor.position = Vector2(-300, -420)
		hud.add_child(_monitor)
		return
	_monitor.visible = not _monitor.visible
