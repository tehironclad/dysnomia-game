class_name GarageSite
extends Node3D
## The vehicle pad near the arrival point of every v2 territory: a round terrace
## in the terrain's own material (like the fair's), five bays in a fan, a sign at
## each bay that says whether that vehicle is OPEN, LOCKED or unknown (…/—) for
## you, and why, from your real chain state (VehicleUnlocks). The same for every
## viewer except those signs, which are about the viewer, not the territory.
##
## V gets in and out, R puts a vehicle back on its wheels; E at a locked bay rents
## that vehicle for this session for 1 Ⓐ to this QING (ArcadePay: simulated,
## signed, receipt-verified). A vehicle stays where you leave it; V at its empty
## bay brings it back.

signal driving_changed(on: bool)

const AT := Vector2(0.0, 48.0)   ## preferred spot (relative to the Core): behind you on arrival
const RADIUS := 17.0             ## the terrace
const BAY_RING := 10.5            ## bays sit on this circle, on the far side from the Core
const BAY_SPREAD := 68.0         ## degrees either side of the outward axis
const REACH := 3.6               ## how close to a vehicle you must be to get in
## [centre, clearance] relative to the Core: the Core's disc, arcade, monolith, pads, arrival
const KEEP_OUT := [[Vector2(0, 0), 30.0], [Vector2(26, 18), 9.0], [Vector2(-26, 18), 7.0],
	[Vector2(15.5, 9), 4.0], [Vector2(-15.5, 9), 4.0], [Vector2(0, 16), 2.0]]
const STATE_COLORS := [Color("#a8e6ff"), Color("#ff8fa0"), Color("#8e97a9")]  # OPEN, LOCKED, UNKNOWN

var vehicles := {}  ## kind → MoonVehicle
var driving: MoonVehicle = null
var status := {}  ## kind → {state, why}
var _qing := ""
var _hud: Node
var _player: CharacterBody3D
var _state: TerritoryState
var _height_fn: Callable  ## relative to the Core
var _world_h: Callable  ## world (x, z) → world height
var _tint := Color(0.6, 0.8, 1.0)
var _ground_mat: Material
var _bays := {}  ## kind → {at: Vector3 (local), yaw, ring: MeshInstance3D, sign: Label3D}
var _focus := ""  ## "kind" (a vehicle in reach) or "bay:kind" (an empty bay)
var _prompt := ""
var _paying := false
var _speedo: Label
var _howto: GameHowto  ## the vehicle's card at the start and its controls strip while driving
var _arm_len := 3.5
var _alighting := false  ## stepping out (a short animation; input waits)
const ALIGHT_S := 0.5
const CAM_EASE_S := 0.5  ## the chase camera eases out to the vehicle's distance and back
var _site: Dictionary = {}


## Finds the pad's spot: every sample of the round footprint on land, the flattest
## such spot near the preferred one, clear of the Core's landmarks, the skyline
## ring and `extra` keep-outs ([[Vector2 centre, clearance], …], e.g. the fair).
## Pure and deterministic. Returns {ok, at, top, low, land}.
static func find_site(height_fn: Callable, extra: Array = [], land_floor: float = -2.5) -> Dictionary:
	var best := {"ok": false, "score": INF}
	var fallback := {"ok": false, "land": -1.0}
	var keep: Array = KEEP_OUT + extra
	for gx in range(-19, 20):
		for gz in range(-19, 20):
			var c := Vector2(gx * 5.0, gz * 5.0)
			if c.length() > 96.0:
				continue
			var clear := true
			for k in keep:
				if c.distance_to(k[0]) < float(k[1]) + RADIUS:
					clear = false
					break
			if clear and _in_skyline(c):
				clear = false
			if not clear:
				continue
			var top := -INF
			var low := INF
			var on_land := 0
			var n := 0
			for ring in [0.0, 0.55, 1.0]:
				var steps := 1 if ring == 0.0 else 10
				for i in steps:
					var a := TAU * i / steps
					var p: Vector2 = c + Vector2(cos(a), sin(a)) * RADIUS * ring
					var h: float = height_fn.call(p.x, p.y)
					top = maxf(top, h)
					low = minf(low, h)
					n += 1
					if h >= land_floor:
						on_land += 1
			var land := float(on_land) / n
			if land > fallback["land"]:
				fallback = {"ok": false, "at": c, "top": top, "low": low, "land": land}
			if on_land < n:
				continue
			var score := (top - low) * 4.0 + c.distance_to(AT) * 0.08
			if score < best["score"]:
				best = {"ok": true, "at": c, "top": top, "low": low, "land": 1.0, "score": score}
	return best if best["ok"] else fallback


## The skyline's towers stand on rings 36–43 m behind the Room (BarColumns).
static func _in_skyline(c: Vector2) -> bool:
	var a := fposmod(rad_to_deg(atan2(c.y, c.x)), 360.0)
	var d := c.length()
	return d > BarColumns.RINGS[0] - RADIUS - 4.0 and d < BarColumns.RINGS[1] + RADIUS + 4.0 \
		and a > BarColumns.ARC_FROM - 12.0 and a < BarColumns.ARC_TO + 12.0


## Bay positions (local to the pad) and the yaw that faces each vehicle at the pad's
## centre; the fan opens away from the Core so you walk into the showroom.
static func bay_layout(outward: Vector2) -> Array:
	var o := outward.normalized() if outward.length() > 0.01 else Vector2(0, 1)
	var out: Array = []
	var n := VehicleSpecs.KINDS.size()
	for i in n:
		var a := deg_to_rad(lerpf(-BAY_SPREAD, BAY_SPREAD, float(i) / (n - 1)))
		var d := o.rotated(a) * BAY_RING
		var face := -d.normalized()
		out.append({"kind": VehicleSpecs.KINDS[i], "at": Vector2(d.x, d.y), "yaw": atan2(-face.x, -face.y)})
	return out


func setup(qing: String, hud: Node, player: CharacterBody3D, state: TerritoryState, height_fn: Callable,
		world_h: Callable, tint: Color, ground_mat: Material = null, extra_keep_out: Array = []) -> void:
	_qing = qing.to_lower()
	_hud = hud
	_player = player
	_state = state
	_height_fn = height_fn
	_world_h = world_h
	_tint = tint
	_ground_mat = ground_mat
	_site = find_site(height_fn, extra_keep_out)
	var at: Vector2 = _site.get("at", AT)
	position = Vector3(at.x, float(_site.get("top", 0.0)) + 0.12, at.y)
	_build_terrace(position.y - float(_site.get("low", position.y)) + 1.5)
	_build_props()
	_build_bays()
	if _state:
		_state.changed.connect(refresh_unlocks)
	Session.changed.connect(refresh_unlocks)
	refresh_unlocks()
	print("[Garage] pad at %s (%s, relief %.1f m)" % [str(at), "on land" if _site.get("ok", false) else "best effort",
		float(_site.get("top", 0.0)) - float(_site.get("low", 0.0))])
	_preview_drive.call_deferred()


# --- building ------------------------------------------------------------------------

func _build_terrace(depth: float) -> void:
	var slope := clampf(depth * 2.2, 3.0, 10.0)
	var m := CylinderMesh.new()
	m.top_radius = RADIUS
	m.bottom_radius = RADIUS + slope
	m.height = depth
	m.radial_segments = 48
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "Terrace"
	mi.mesh = m
	mi.material_override = _ground_mat if _ground_mat else VehicleModels.mat(Color(0.5, 0.5, 0.53), 0.9, 0.0)
	mi.position = Vector3(0, -depth * 0.5 - 0.02, 0)
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerraceBody"
	var cs := CollisionShape3D.new()
	cs.shape = m.create_convex_shape()
	cs.position = mi.position
	body.add_child(cs)
	add_child(body)
	# A thin ring of light at the rim, as on the fair's terrace
	var ring := TorusMesh.new()
	ring.inner_radius = RADIUS - 0.1
	ring.outer_radius = RADIUS + 0.1
	ring.rings = 72
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.material_override = VehicleModels.glow(_tint, 1.3)
	ri.scale = Vector3(1, 0.25, 1)
	ri.position.y = 0.03
	add_child(ri)


func _outward() -> Vector2:
	var o := Vector2(position.x, position.z)
	return o.normalized() if o.length() > 0.1 else Vector2(0, 1)


func _build_props() -> void:
	var o := _outward()
	var side := Vector2(-o.y, o.x)
	# Two light masts flanking the fan, lighting the bays at night
	for s in [-1.0, 1.0]:
		var p: Vector2 = o * 2.0 + side * s * 13.5
		var mast := MeshInstance3D.new()
		mast.mesh = VehicleModels._cyl(0.12, 0.18, 7.0, 10)
		mast.material_override = VehicleModels.mat(VehicleModels.STEEL, 0.4, 0.7)
		mast.position = Vector3(p.x, 3.5, p.y)
		add_child(mast)
		Solid.cylinder(self, 0.25, 7.0, Vector3(p.x, 0, p.y))
		var head := MeshInstance3D.new()
		head.mesh = VehicleModels._box(1.4, 0.2, 0.5)
		head.material_override = VehicleModels.glow(Color(1.0, 0.96, 0.88), 2.5)
		head.position = Vector3(p.x, 7.05, p.y)
		head.rotation.y = atan2(side.x * s, side.y * s)
		add_child(head)
		var l := OmniLight3D.new()
		l.position = Vector3(p.x, 6.6, p.y) - Vector3(side.x, 0, side.y) * s * 2.5
		l.light_color = Color(1.0, 0.95, 0.88).lerp(_tint, 0.2)
		l.light_energy = 3.2
		l.omni_range = 24.0
		l.omni_attenuation = 0.7
		add_child(l)
	var over := OmniLight3D.new()
	over.position = Vector3(o.x, 0, o.y) * 6.0 + Vector3(0, 7.5, 0)
	over.light_color = Color(0.92, 0.96, 1.0)
	over.light_energy = 2.0
	over.omni_range = 18.0
	add_child(over)
	# A sign at the way in, and the rental terminal beside it
	var sign := Label3D.new()
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 96
	sign.pixel_size = 0.012
	sign.text = "VEHICLE PAD"
	sign.modulate = DeepFieldTheme.INK
	sign.outline_size = 10
	sign.outline_modulate = Color(0, 0, 0, 0.85)
	sign.position = Vector3(o.x, 0, o.y) * (BAY_RING + 5.5) + Vector3(0, 7.2, 0)
	sign.rotation.y = atan2(-o.x, -o.y)
	add_child(sign)
	var term := PlaceBase.load_piece("Prop_Computer")
	term.position = Vector3(-o.x * 11.5 + side.x * 3.0, 0, -o.y * 11.5 + side.y * 3.0)
	term.rotation.y = atan2(-o.x, -o.y) + PI
	add_child(term)
	Solid.wrap(term)
	for k in 2:
		var crate := PlaceBase.load_piece("Prop_Crate3" if k == 0 else "Prop_Barrel_Large")
		var cp: Vector2 = -o * 11.0 - side * (3.0 + k * 1.8)
		crate.position = Vector3(cp.x, 0, cp.y)
		add_child(crate)
		Solid.wrap(crate)
	# Floor lamps around the rim
	for i in 6:
		var a := TAU * (i + 0.5) / 6.0
		var lamp := PlaceBase.load_piece("Prop_Light_Floor")
		lamp.position = Vector3(cos(a), 0, sin(a)) * (RADIUS - 1.0)
		add_child(lamp)


func _build_bays() -> void:
	for b in bay_layout(_outward()):
		var kind: String = b["kind"]
		var at := Vector3(b["at"].x, 0.0, b["at"].y)
		var yaw: float = b["yaw"]
		var pad := MeshInstance3D.new()
		var spec := VehicleSpecs.spec(kind)
		var r := maxf(2.4, Vector2((spec["hull"] as Vector3).x, (spec["hull"] as Vector3).z).length() * 0.5 + 0.4)
		pad.mesh = VehicleModels._cyl(r, r, 0.06, 32)
		pad.material_override = VehicleModels.mat(VehicleModels.TRIM, 0.6, 0.4)
		pad.position = at + Vector3(0, 0.03, 0)
		add_child(pad)
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = r - 0.12
		t.outer_radius = r
		t.rings = 40
		ring.mesh = t
		ring.position = at + Vector3(0, 0.07, 0)
		ring.scale = Vector3(1, 0.3, 1)
		add_child(ring)
		var sign := Label3D.new()
		sign.font = DeepFieldTheme.mono_font()
		sign.font_size = 36
		sign.pixel_size = 0.009
		sign.outline_size = 8
		sign.outline_modulate = Color(0, 0, 0, 0.85)
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.no_depth_test = false
		var back := Vector3(sin(yaw), 0, cos(yaw))  # behind the vehicle
		sign.position = at + back * (r + 0.4) + Vector3(0, 3.6 if kind != "crawler" else 4.8, 0)
		add_child(sign)
		var v := MoonVehicle.new()
		v.setup(kind, _tint, _world_h)
		add_child(v)
		var gx := global_transform * at
		v.bay = Transform3D(Basis(Vector3.UP, yaw), gx + Vector3(0, 0.1, 0))
		v.park(v.bay)
		vehicles[kind] = v
		_bays[kind] = {"at": at, "yaw": yaw, "ring": ring, "sign": sign}


# --- unlocks ---------------------------------------------------------------------------

func refresh_unlocks() -> void:
	if not is_inside_tree():
		return
	var facts := VehicleUnlocks.gather(_qing, _state)
	var lines: PackedStringArray = []
	for kind in VehicleSpecs.KINDS:
		var st := VehicleUnlocks.evaluate(kind, facts)
		status[kind] = st
		var b: Dictionary = _bays.get(kind, {})
		if b.is_empty():
			continue
		var col: Color = STATE_COLORS[st["state"]]
		if st["state"] == VehicleUnlocks.State.OPEN:
			col = _tint.lerp(DeepFieldTheme.ICE, 0.5)
		(b["ring"] as MeshInstance3D).material_override = VehicleModels.glow(col, 2.2 if st["state"] == VehicleUnlocks.State.OPEN else 1.2)
		var sign: Label3D = b["sign"]
		sign.text = "%s\n%s\n%s" % [VehicleSpecs.display_name(kind).to_upper(), VehicleUnlocks.status_word(st["state"]), VehicleUnlocks.RULES[kind]]
		sign.modulate = col.lerp(DeepFieldTheme.INK, 0.35)
		lines.append("%s — %s: %s" % [VehicleSpecs.display_name(kind), VehicleUnlocks.status_word(st["state"]), st["why"]])
	Inspector.register(self, "Vehicle pad (your unlocks)",
		"Which vehicles you may drive, from your own chain state (read by the identity and bars passes; nothing guessed):\n%s\nRent a locked one for this session: E at its bay, %s to this QING, receipt-verified." % ["\n".join(lines), ArcadePay.fee_text()])
	_prompt = ""  # re-show with the new reasons


# --- play --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _player == null or not _player.is_inside_tree() or not _player.visible:
		return
	if driving:
		_update_speedo()
		return
	var p := _player.global_position
	var focus := ""
	var best := REACH
	for kind in vehicles:
		var v: MoonVehicle = vehicles[kind]
		var hull: Vector3 = v.spec["hull"]
		var d := Vector2(p.x - v.global_position.x, p.z - v.global_position.z).length() - maxf(hull.x, hull.z) * 0.35
		if d < best and absf(p.y - v.global_position.y) < 4.0:
			best = d
			focus = kind
	if focus == "":
		for kind in _bays:
			var bay_g := global_transform * (_bays[kind]["at"] as Vector3)
			var v2: MoonVehicle = vehicles[kind]
			if Vector2(p.x - bay_g.x, p.z - bay_g.z).length() < 2.5 and v2.global_position.distance_to(v2.bay.origin) > 10.0:
				focus = "bay:" + kind
	if focus != _focus:
		_focus = focus
		_prompt = ""
	var text := _prompt_text()
	if text != _prompt:
		if text == "":
			_hud.hide_prompt()
		else:
			_hud.show_prompt(text)
		_prompt = text


func _prompt_text() -> String:
	if _focus == "":
		return ""
	if _focus.begins_with("bay:"):
		var k := _focus.substr(4)
		return "%s  bring the %s back to its bay" % [ControlsHelp.key_of("vehicle_enter"), VehicleSpecs.display_name(k)]
	var st: Dictionary = status.get(_focus, {"state": VehicleUnlocks.State.UNKNOWN, "why": "…"})
	var nm := VehicleSpecs.display_name(_focus)
	if st["state"] == VehicleUnlocks.State.OPEN:
		return "%s  drive the %s · %s" % [ControlsHelp.key_of("vehicle_enter"), nm, st["why"]]
	var rent := ("%s  rent it for this session (%s to this QING)" % [ControlsHelp.key_of("interact"), ArcadePay.fee_text()]) \
		if Session.wallet != "" else "connect a wallet to rent it"
	return "%s %s · %s\n%s" % [nm, VehicleUnlocks.status_word(st["state"]), st["why"], rent]


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _alighting:
		return
	if driving:
		if event.is_action_pressed("vehicle_enter"):
			get_viewport().set_input_as_handled()
			dismount()
		elif event.is_action_pressed("vehicle_reset"):
			get_viewport().set_input_as_handled()
			driving.reset_upright()
		elif event.is_action_pressed("flashlight"):
			get_viewport().set_input_as_handled()
			driving.toggle_lights()
		elif event.is_action_pressed("ui_cancel"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)
		return
	if _focus == "" or _player.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	if event.is_action_pressed("vehicle_enter"):
		get_viewport().set_input_as_handled()
		if _focus.begins_with("bay:"):
			var k := _focus.substr(4)
			if not vehicles[k].is_driven():
				vehicles[k].park(vehicles[k].bay)
				_hud.ticker("%s back in its bay" % VehicleSpecs.display_name(k), DeepFieldTheme.ICE, 5.0)
			return
		var st: Dictionary = status.get(_focus, {})
		if st.get("state", VehicleUnlocks.State.UNKNOWN) == VehicleUnlocks.State.OPEN:
			mount(_focus)
		else:
			_hud.ticker("%s is %s: %s" % [VehicleSpecs.display_name(_focus), VehicleUnlocks.status_word(st.get("state", 2)).to_lower(), st.get("why", "…")], Color("#ff8fa0"), 8.0)
			_show_unlock_steps(_focus)
	elif event.is_action_pressed("interact") and not _focus.begins_with("bay:"):
		var st2: Dictionary = status.get(_focus, {})
		if st2.get("state", VehicleUnlocks.State.UNKNOWN) != VehicleUnlocks.State.OPEN:
			get_viewport().set_input_as_handled()
			_rent(_focus)


func mount(kind: String) -> void:
	var v: MoonVehicle = vehicles.get(kind)
	if v == null or driving != null or v.is_driven():
		return
	if GameManager.is_flying:
		GameManager.toggle_fly_mode()
	driving = v
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	if "is_crouching" in _player:
		_player.set("is_crouching", false)
	var model := _player.get_node_or_null("PlayerModel")
	if model and model.has_method("set_seated"):
		model.set_seated("Driving")
	var arm := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	if arm:
		_arm_len = arm.spring_length
		arm.add_excluded_object(v.get_rid())
		var tw := arm.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(arm, "spring_length", float(v.spec["chase"]), CAM_EASE_S)
		tw.tween_property(arm, "position:y", float(v.spec["chase_h"]), CAM_EASE_S)
	var rig := _player.get_node_or_null("CameraRig")
	if rig and "_pitch" in rig:
		# Swing in behind the vehicle, looking down the road a little (no snap).
		var tr := rig.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tr.tween_property(rig, "_pitch", -0.3, CAM_EASE_S)
		var y0: float = rig.get("_yaw")
		var y1 := y0 + wrapf(v.rotation.y - y0, -PI, PI)
		tr.tween_property(rig, "_yaw", y1, CAM_EASE_S)
	v.mount(_player)
	_hud.hide_prompt()
	_prompt = ""
	if _howto == null:
		_howto = GameHowto.new()
		_howto.name = "HowTo"
		add_child(_howto)
	_howto.setup({"title": VehicleSpecs.display_name(kind), "tag": "Vehicle pad · this territory", "accent": DeepFieldTheme.ICE,
		"rules": [String(v.spec.get("blurb", "")), "Drive anywhere in the territory; %s gets out beside it, %s puts it back on its wheels." % [
			ControlsHelp.key_of("vehicle_enter"), ControlsHelp.key_of("vehicle_reset")]],
		"controls": controls(kind), "verb": "drive"})
	_howto.open_card(GameHowto.Mode.COUNTDOWN, 8.0, false)  # the vehicle drives meanwhile: a key closes it and drives
	_howto.show_strip(true)
	_ensure_speedo()
	_speedo.visible = true
	driving_changed.emit(true)


## A vehicle's controls as [[key, words]] (GameHowto's card and strip). Keys from the InputMap.
static func controls(kind: String) -> Array:
	var rows: Array = [["%s %s" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_back")], "drive / reverse"],
		["%s %s" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right")], "steer"]]
	if _jump_word(kind) != "—":
		rows.append([ControlsHelp.key_of("jump"), _jump_word(kind)])
	rows.append([ControlsHelp.key_of("sprint"), "boost"])
	rows.append([ControlsHelp.key_of("crouch_descend"), "descend" if kind == "hopper" else "brake / slide"])
	rows.append([ControlsHelp.key_of("flashlight"), "lights"])
	rows.append([ControlsHelp.key_of("vehicle_reset"), "upright"])
	rows.append([ControlsHelp.key_of("vehicle_enter"), "get out"])
	return rows


static func _jump_word(kind: String) -> String:
	match kind:
		"hopper":
			return "lift (hold)"
		"crawler":
			return "—"
		"skimmer":
			return "crest jump"
	return "hop"


func dismount() -> void:
	if driving == null:
		return
	var v := driving
	driving = null
	var exit := v.exit_point()
	var from := _player.global_position
	v.unmount()
	_player.global_rotation = Vector3(0, v.rotation.y, 0)
	_player.velocity = Vector3.ZERO
	var model := _player.get_node_or_null("PlayerModel") as Node3D
	if model:
		if model.has_method("set_seated"):
			model.set_seated("")
		model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		if "hold_clip" in model:  # getting up and out of the seat
			model.set("hold_clip", "Sitting_Exit")
			model.set("hold_speed", 2.0)
	# Step down beside the seat (a short swing, not a teleport), then walk on.
	_alighting = true
	var tw := _player.create_tween()
	tw.tween_method(func(e: float) -> void:
		var k := e * e * (3.0 - 2.0 * e)
		_player.global_position = from.lerp(exit, k) + Vector3.UP * sin(k * PI) * 0.25, 0.0, 1.0, ALIGHT_S)
	tw.tween_callback(func() -> void:
		_alighting = false
		if model and "hold_clip" in model:
			model.set("hold_clip", "")
		if driving == null:
			_player.set_physics_process(true)
			_player.set_process_unhandled_input(true))
	var arm := _player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	if arm:
		arm.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).tween_property(arm, "spring_length", _arm_len, CAM_EASE_S)
		arm.remove_excluded_object(v.get_rid())
	if _speedo:
		_speedo.visible = false
	if _howto:
		_howto.end()
	_focus = ""
	_prompt = ""
	driving_changed.emit(false)


## What opens this vehicle, as steps (AccessSteps): its rule, read from your chain
## state (… while unread, — if the read failed), with the rental as the other way in.
func _show_unlock_steps(kind: String) -> void:
	var st: Dictionary = status.get(kind, {"state": VehicleUnlocks.State.UNKNOWN, "why": "…"})
	var why := String(st.get("why", "…"))
	var stv := "done" if st["state"] == VehicleUnlocks.State.OPEN else ("todo" if st["state"] == VehicleUnlocks.State.LOCKED else ("checking" if why.begins_with("…") else "unknown"))
	var steps := AccessSteps.popup(self, "vehicle", {"title": "Drive the %s" % VehicleSpecs.display_name(kind), "qing": _qing,
		"subtitle": "Or rent it for this session: %s to this QING, receipt-verified." % ArcadePay.fee_text(),
		"extra": [{"id": kind, "title": String(VehicleUnlocks.RULES[kind]).capitalize(), "status": stv, "detail": why,
			"explain": "Vehicles open from your own chain state; nothing is guessed. Su here or anywhere grows your bars."}]})
	steps.add_footer_button("Rent it (%s)" % ArcadePay.fee_text(), func(): _rent(kind))


func _rent(kind: String) -> void:
	if _paying:
		return
	var nm := VehicleSpecs.display_name(kind)
	if Wallet.address == "":
		_hud.ticker("Renting the %s needs a connected wallet (%s to this QING)." % [nm, ArcadePay.fee_text()], Color("#ff8fa0"), 8.0)
		AccessSteps.popup(self, "arcade", {"title": "Rent the %s (%s)" % [nm, ArcadePay.fee_text()], "qing": _qing, "fee_wei": ArcadePay.FEE_WEI})
		return
	_paying = true
	_hud.ticker("Rental: approve %s to this QING in your wallet…" % ArcadePay.fee_text(), DeepFieldTheme.ICE, 20.0)
	var res: Dictionary = await ArcadePay.pay(_qing, "Vehicle pad · %s for this session" % nm)
	_paying = false
	if not res.get("ok", false):
		Cues.play(self, "fail")
		_hud.ticker("Not rented: %s" % res.get("message", "cancelled"), Color("#ff8fa0"), 10.0)
		if AccessSteps.goal_for_failure(res, "arcade") != "":
			AccessSteps.popup(self, "arcade", {"title": "Rent the %s (%s)" % [nm, ArcadePay.fee_text()], "qing": _qing, "fee_wei": ArcadePay.FEE_WEI})
		return
	# The payment was this rental, not an arcade play: spend the credit it recorded.
	ArcadePay.use_credit(Wallet.address, _qing)
	VehicleUnlocks.add_rental(Wallet.address, _qing, kind, String(res["hash"]), int(res["block"]))
	Cues.play(self, "confirm")
	_hud.ticker("RENTAL VERIFIED · %s for this session · block %d" % [nm, int(res["block"])], DeepFieldTheme.ICE, 10.0)
	refresh_unlocks()


func _ensure_speedo() -> void:
	if _speedo:
		return
	_speedo = Label.new()
	_speedo.theme_type_variation = "MonoLabel"
	_speedo.add_theme_font_size_override("font_size", 15)
	_speedo.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_speedo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_speedo.add_theme_constant_override("outline_size", 6)
	_speedo.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speedo.position = Vector2(-160, -96)
	_speedo.custom_minimum_size = Vector2(320, 0)
	_speedo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_speedo)


func _update_speedo() -> void:
	if _speedo == null or driving == null:
		return
	var v := driving
	var extra := ""
	if v.kind == "hopper":
		var cap := float(v.spec["fuel_s"])
		var bars := int(round(v._fuel / cap * 8.0))
		extra = " · lift " + "▮".repeat(bars) + "▯".repeat(8 - bars)
	elif v._boosting:
		extra = " · BOOST"
	_speedo.text = "%s · %d m/s%s" % [VehicleSpecs.display_name(v.kind).to_upper(), int(round(v.speed())), extra]


## Where a preview camera looks at the pad: from the Core side, over the bays.
func preview_transform() -> Transform3D:
	var o := _outward()
	var c := global_position
	var eye := c - Vector3(o.x, 0, o.y) * 12.0 + Vector3(0, 5.0, 0)
	return Transform3D(Basis.looking_at(c + Vector3(o.x, 0, o.y) * 8.0 + Vector3(0, 1.0, 0) - eye, Vector3.UP), eye)


## Screenshots only (--drive=<kind> with the player's own camera): get into that
## vehicle if your real unlocks allow it, and hold the throttle for a moment.
func _preview_drive() -> void:
	var kind := ""
	var secs := 2.5
	var steer := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drive="):
			kind = a.substr(8)
		elif a.begins_with("--drive-s="):
			secs = float(a.substr(10))
		elif a.begins_with("--steer="):
			steer = a.substr(8)
	if kind == "" or not vehicles.has(kind):
		return
	var t0 := Time.get_ticks_msec()
	while status.get(kind, {}).get("state", VehicleUnlocks.State.UNKNOWN) == VehicleUnlocks.State.UNKNOWN and Time.get_ticks_msec() - t0 < 240000:
		await get_tree().create_timer(0.5).timeout
		refresh_unlocks()
	if status[kind]["state"] != VehicleUnlocks.State.OPEN:
		print("[Garage] --drive=%s: %s (%s)" % [kind, VehicleUnlocks.status_word(status[kind]["state"]), status[kind]["why"]])
		return
	var v: MoonVehicle = vehicles[kind]
	v.park(Transform3D(Basis(Vector3.UP, v.bay.basis.get_euler().y + PI), v.bay.origin))  # face out of the fan
	mount(kind)
	print("[Garage] driving %s: %s" % [kind, status[kind]["why"]])
	if secs > 0.0:
		Input.action_press("move_forward")
		if steer != "":
			Input.action_press("move_left" if steer == "left" else "move_right")
		await get_tree().create_timer(secs).timeout
		Input.action_release("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
