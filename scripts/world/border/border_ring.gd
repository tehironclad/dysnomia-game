class_name BorderRing
extends Node3D
## A territory's four borders (WP: neighbours). On each side stands a
## translucent force field; beyond it lies the neighbouring QING's own ground
## (its Deep Field heightfield at 129², drawn in its own colours) under its
## real name, or nothing at all where no QING lies that way (the edge of the map).
## Which QING is next door comes from Neighbours (HECKE coordinates, checked
## against MAP.GetMapQing). Everything drawn depends only on territory state.
##
## Crossing is a QING door: walk up to the field and press interact. The panel
## reads the neighbour's door for your LAU (RoomState: cover, Admitted) and, if
## you are not admitted, runs its Join (approve cover + 1 wei, QING.Join(LAU))
## through Wallet.send (simulate → sign → receipt verified), then re-reads
## Admitted. Only an Admitted(LAU) read from the chain opens the way; crossing
## then loads the neighbour with you at its matching edge.

const SAMPLES := 129  ## the neighbour's ground: 4 m spacing
const WALL_H := 90.0
const REACH_M := 7.0  ## how close to the field its prompt appears
const CROSS_M := 1.6  ## walking this close to an open field crosses it
const SHADER := preload("res://assets/shaders/border_field.gdshader")

var territory: Dictionary = {}
var sides := {}  ## side → Neighbours.find() entry (+ "q": the Registry record)
var map_check := {"block": -1, "ok": {}}
var player: Node3D
var hud: Node
var main_terrain: DeepFieldTerrain
var action: ActionPanel
var _layer: CanvasLayer
var _ground := {}  ## side → DeepFieldTerrain, once built
var _pending: Array = []  ## records still to compute (worker thread)
var _results := {}
var _lock := Mutex.new()
var _thread: Thread
var _near := ""
var _prompting := false
var _open_side := ""
var _admitted := {}  ## side → block at which Admitted(LAU) read true (this session's wallet)
var _room: RoomState
var _busy := false
var _crossing := false


## Builds the walls and starts the neighbours' ground. `player`/`hud` may be
## null (previews): then there is no prompt or crossing. `check_map` = false
## skips the live MAP.GetMapQing read (unit tests run offline).
func setup(q: Dictionary, p_terrain: DeepFieldTerrain, p_player: Node3D, p_hud: Node, check_map: bool = true) -> void:
	territory = q
	main_terrain = p_terrain
	player = p_player
	hud = p_hud
	var found := Neighbours.find(q, Registry.all())
	for side in Neighbours.SIDES:
		if found.has(side):
			var e: Dictionary = found[side]
			e["q"] = Registry.get_territory(e["address"])
			sides[side] = e
		_build_wall(side)
		_build_label(side)
		if sides.has(side):
			_pending.append([side, sides[side]["q"]])
	if not _pending.is_empty():
		_thread = Thread.new()
		_thread.start(_compute_grounds.bind(_pending.duplicate()))
	_register()
	if check_map:
		_verify()
	if player and p_hud:
		_build_panel()


## Puts the player at the matching edge if they just crossed into this territory.
func place_arrival() -> bool:
	var arr: Dictionary = GameManager.arrival
	GameManager.arrival = {}
	if player == null or arr.is_empty() or String(arr.get("address", "")) != String(territory["address"]).to_lower():
		return false
	var side := String(arr["side"])
	var at := Neighbours.arrival(side, float(arr.get("along", 0.0)))
	player.position = Vector3(at.x, main_terrain.get_height_at(at.x, at.y) + 1.0, at.y)
	var inward := -Neighbours.outward(Neighbours.OPPOSITE[side])
	player.rotation.y = atan2(-inward.x, -inward.y)
	if hud and hud.has_method("ticker"):
		hud.ticker("CROSSED the %s border from %s" % [Neighbours.NAMES[Neighbours.OPPOSITE[side]],
			String(Registry.get_territory(String(arr.get("from", ""))).get("name", "—"))], DeepFieldTheme.ICE, 12.0)
	return true


static func qname(q: Dictionary) -> String:
	var n := String(q.get("name", "")).strip_edges()
	if n == "":
		return String(q.get("address", "—"))
	return n if n.to_upper().ends_with("QING") else n + " QING"


# --- Building ----------------------------------------------------------------------

func _wall_transform(side: String) -> Transform3D:
	var half := JuliaHeightfield.SIZE_M * 0.5
	var o := Neighbours.outward(side) * half
	var basis := Basis.IDENTITY if side == "n" or side == "s" else Basis(Vector3.UP, PI * 0.5)
	return Transform3D(basis, Vector3(o.x, WALL_H * 0.5 - 8.0, o.y))


func _build_wall(side: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Field_" + side
	var quad := QuadMesh.new()
	quad.size = Vector2(JuliaHeightfield.SIZE_M, WALL_H)
	mi.mesh = quad
	mi.transform = _wall_transform(side)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var has := sides.has(side)
	var col := DeepField.to_color(DeepField.for_territory(sides[side]["q"])["color"]) if has else Color(0.45, 0.5, 0.62)
	m.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("strength", 1.0 if has else 0.35)
	m.set_shader_parameter("along_x", side == "n" or side == "s")
	m.set_shader_parameter("base_y", 0.0)
	mi.material_override = m
	add_child(mi)
	# Solid: nobody walks through a field (crossing loads the next territory instead).
	var body := StaticBody3D.new()
	body.name = "FieldBody_" + side
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var along := side == "n" or side == "s"
	box.size = Vector3(JuliaHeightfield.SIZE_M + 4.0 if along else 2.0, 400.0, 2.0 if along else JuliaHeightfield.SIZE_M + 4.0)
	cs.shape = box
	body.add_child(cs)
	var o := Neighbours.outward(side) * (JuliaHeightfield.SIZE_M * 0.5 + 1.0)
	body.position = Vector3(o.x, 150.0, o.y)
	add_child(body)


func _build_label(side: String) -> void:
	var o := Neighbours.outward(side)
	var half := JuliaHeightfield.SIZE_M * 0.5
	var big := Label3D.new()
	big.name = "Name_" + side
	big.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	big.shaded = false
	big.double_sided = true
	big.font = DeepFieldTheme.get_theme().default_font
	big.outline_size = 12
	big.outline_modulate = Color(0, 0, 0, 0.7)
	add_child(big)
	if sides.has(side):
		var q: Dictionary = sides[side]["q"]
		var col := DeepField.to_color(DeepField.for_territory(q)["color"]).lightened(0.25)
		big.text = qname(q).to_upper()
		big.modulate = col
		big.font_size = 160
		big.pixel_size = 0.09
		big.position = Vector3(o.x * (half + 70.0), 46.0, o.y * (half + 70.0))
		var sub := Label3D.new()
		sub.name = "Sub_" + side
		sub.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sub.shaded = false
		sub.font = big.font
		sub.font_size = 72
		sub.pixel_size = 0.07
		sub.modulate = col.darkened(0.15)
		sub.outline_size = 8
		sub.outline_modulate = Color(0, 0, 0, 0.7)
		sub.text = "%s · NEXT QING %s · JOIN TO CROSS" % [String(q.get("symbol", "")), Neighbours.NAMES[side].to_upper()]
		sub.position = big.position + Vector3(0.0, -11.0, 0.0)
		add_child(sub)
	else:
		big.text = "EDGE OF THE MAP · NO QING LIES %s" % Neighbours.NAMES[side].to_upper()
		big.modulate = Color(0.55, 0.6, 0.72, 0.8)
		big.font_size = 72
		big.pixel_size = 0.05
		big.position = Vector3(o.x * (half + 8.0), 14.0, o.y * (half + 8.0))


## Worker thread: the neighbours' heightfields (cached on disk after the first).
func _compute_grounds(items: Array) -> void:
	for it in items:
		var hf := JuliaHeightfield.for_territory(it[1], SAMPLES)
		_lock.lock()
		_results[it[0]] = hf
		_lock.unlock()


func _process(_delta: float) -> void:
	_attach_grounds()
	if player == null or hud == null or _crossing:
		return
	_update_prompt()


func _attach_grounds() -> void:
	if _results.is_empty():
		return
	_lock.lock()
	var ready := _results.duplicate()
	_results.clear()
	_lock.unlock()
	for side in ready:
		var g := DeepFieldTerrain.new()
		g.name = "Neighbour_" + side
		var at := Neighbours.offset(side)
		g.position = at
		add_child(g)
		g.build_distant(sides[side]["q"], ready[side], global_position + at)
		if main_terrain and main_terrain.material:
			g.material.set_shader_parameter("ground_lift", main_terrain.material.get_shader_parameter("ground_lift"))
		_ground[side] = g
	if _thread and _ground.size() == _pending.size():
		_thread.wait_to_finish()
		_thread = null


## True once a side's neighbour ground is drawn (tests, previews).
func ground_ready(side: String) -> bool:
	return _ground.has(side)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# --- Facts -------------------------------------------------------------------------

func _register() -> void:
	var lines: PackedStringArray = []
	for side in Neighbours.SIDES:
		if sides.has(side):
			var e: Dictionary = sides[side]
			var v = map_check["ok"].get(side, null)
			lines.append("%s: %s (%s) · Δlat %s, Δlon %s raw units · MAP.GetMapQing: %s" % [Neighbours.NAMES[side], qname(e["q"]), e["address"],
				Neighbours.short(e["dlat"]), Neighbours.short(e["dlon"]),
				("confirms at block %d" % map_check["block"]) if v == true else ("a different QING at block %d" % map_check["block"] if v == false else "—")])
		else:
			lines.append("%s: no QING in that quarter of the map (nothing drawn)" % Neighbours.NAMES[side])
	Inspector.register(self, "Borders",
		"Next door on each side: the nearest QING in that quarter of HECKE's raw (lat, lon) plane, by WORLD's square distance (int256 words, no floats).\n" + "\n".join(lines) +
		"\nThe force field is a QING's door: Join (QING.Admitted(your LAU) read from the chain) to cross.")


func _verify() -> void:
	var by_side := {}
	for side in sides:
		by_side[side] = sides[side]["q"]
	if by_side.is_empty():
		return
	map_check = await Neighbours.verify_on_map(by_side)
	if is_inside_tree():
		_register()


# --- Prompt, panel, Join, crossing ----------------------------------------------------

func _local_player() -> Vector2:
	var p := player.global_position - global_position
	return Vector2(p.x, p.z)


func _update_prompt() -> void:
	if action and action.is_open():
		return
	var lp := _local_player()
	var b := Neighbours.nearest_border(lp.x, lp.y)
	var side := String(b["side"]) if float(b["inside_m"]) < REACH_M else ""
	if side != _near:
		_near = side
		if side == "":
			if _prompting:
				hud.hide_prompt()
				_prompting = false
		else:
			_prompting = true
			if sides.has(side):
				var q: Dictionary = sides[side]["q"]
				var verb := "cross into" if _admitted.has(side) else "Join to cross"
				hud.show_prompt("%s  %s — %s" % [ControlsHelp.key_of("interact"), qname(q), verb])
			else:
				hud.show_prompt("The edge of the map: no QING lies %s" % Neighbours.NAMES[side])
	# An open field: walking into it crosses.
	if side != "" and _admitted.has(side) and float(b["inside_m"]) < CROSS_M:
		_cross(side, float(b["along"]))


func _unhandled_input(event: InputEvent) -> void:
	if player == null or action == null or action.is_open() or _near == "" or not sides.has(_near):
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		open_border(_near)


func _build_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)
	action = ActionPanel.new()
	center.add_child(action)
	action.closed.connect(func():
		_open_side = ""
		player.process_mode = Node.PROCESS_MODE_INHERIT
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_near = "")


## The crossing panel for one side (also used by previews).
func open_border(side: String) -> void:
	if action == null or not sides.has(side):
		return
	_open_side = side
	var q: Dictionary = sides[side]["q"]
	if hud:
		hud.hide_prompt()
	_prompting = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	action.show_panel("%s · the %s border" % [qname(q), Neighbours.NAMES[side]], _facts(side) + "\n\nReading its door for your LAU…")
	await _refresh_door()


func _facts(side: String) -> String:
	var e: Dictionary = sides[side]
	var v = map_check["ok"].get(side, null)
	return "%s (%s)\nThe nearest QING %s of here: Δlat %s, Δlon %s raw HECKE units.\nMAP.GetMapQing at its cell: %s" % [
		qname(e["q"]), e["address"], Neighbours.NAMES[side], Neighbours.short(e["dlat"]), Neighbours.short(e["dlon"]),
		("this QING · block %d" % map_check["block"]) if v == true else ("a different QING · block %d" % map_check["block"] if v == false else "—")]


func _signer_blocker() -> String:
	if Wallet.address == "":
		return "View only: connect this wallet at the front door to sign."
	if Wallet.address != Session.wallet:
		return "The connected wallet differs from the session's."
	if not Wallet.is_connected_to_chain():
		return "Switch the wallet to PulseChain (369)."
	return ""


func _refresh_door() -> void:
	var side := _open_side
	if side == "":
		return
	var q: Dictionary = sides[side]["q"]
	var ps: PlayerState = Session.player if Session.wallet != "" else null
	_room = await RoomState.read(String(q["address"]), ps)
	if _open_side != side or not action.is_open():
		return
	action.set_body(_facts(side) + "\n\n" + _room.describe())
	if not _room.ok:
		action.set_status("Its door could not be read: —. Crossing stays closed.")
		action.set_primary("Cross", false, Callable())
		return
	if ps == null or not ps.has_lau():
		action.set_status("Crossing needs a LAU that this QING admits. Connect a wallet at the front door (looking is free: the Field warps anywhere).")
		action.set_primary("Join to cross", false, Callable())
		return
	if _room.admitted:
		_admitted[side] = _room.block
		var how := "no cover: every LAU is admitted" if not _room.has_cover() else "your Join holds"
		action.set_status("QING.Admitted(your LAU) is true at block %d (%s). The field is open to you." % [_room.block, how], Color("#64e3a8"))
		action.set_primary("Cross into %s" % qname(q), true, func(): _cross(side, _along(side)))
		return
	if _room.banned:
		action.set_status("Your wallet holds WITHOUT (a ban): QING.Join reverts for it.")
		action.set_primary("Join to cross", false, Callable())
		return
	var steps := _room.join_steps()
	var blocker := _signer_blocker()
	if blocker == "" and not _room.can_afford():
		blocker = "You hold %s; the cover is %s." % [_room.fmt(_room.balance), _room.fmt(_room.cover)]
	action.set_status(blocker if blocker != "" else "Join: %d step%s, each simulated from your wallet first." % [steps.size(), "s" if steps.size() > 1 else ""])
	if steps.is_empty():
		action.set_primary("Join to cross", false, Callable())
		return
	action.set_primary("%s  (%d step%s)" % [steps[0]["label"], steps.size(), "s" if steps.size() > 1 else ""], blocker == "", _join)


func _join() -> void:
	if _busy or _room == null:
		return
	_busy = true
	action.set_primary("Joining…", false, Callable())
	for step in _room.join_steps():
		action.track(step["label"])
		var res: Dictionary = await Wallet.send(step["label"], step["to"], step["data"])
		if not res["ok"]:
			_busy = false
			return  # the panel shows where it stopped; nothing is claimed
	_busy = false
	await _refresh_door()  # success is the re-read Admitted(LAU), not the wallet page
	if _room and not _room.admitted:
		action.set_status("Join was mined, but Admitted(LAU) still reads false at block %d." % _room.block, Color("#ff8fa0"))


func _along(side: String) -> float:
	var lp := _local_player()
	return lp.x if side == "n" or side == "s" else lp.y


func _cross(side: String, along: float) -> void:
	if _crossing or not sides.has(side) or not _admitted.has(side):
		return
	_crossing = true
	if action and action.is_open():
		action.close()
	var to := String(sides[side]["address"])
	GameManager.arrival = {"address": to, "side": side, "along": along, "from": String(territory["address"]).to_lower()}
	if hud:
		hud.hide_prompt()
	Warp.to(get_tree(), to)


# --- Previews -------------------------------------------------------------------------

## A fixed camera on the ground near `side`, looking across its field.
func frame_camera(cam: Camera3D, side: String) -> void:
	var half := JuliaHeightfield.SIZE_M * 0.5
	var o := Neighbours.outward(side)
	var perp := Vector2(-o.y, o.x)
	var at := o * (half - 34.0) + perp * 30.0
	var h := main_terrain.get_height_at(at.x, at.y) if main_terrain else 0.0
	cam.position = global_position + Vector3(at.x, h + 7.0, at.y)
	var look := o * (half + 150.0) - perp * 20.0
	cam.look_at(global_position + Vector3(look.x, h + 10.0, look.y))
	cam.fov = 70.0
