class_name BaseJump
extends Node
## Base jumping: from the landmark's sky deck (Landmark.jump_requested), from
## your own skyline tower (its height is your Hypobar here), or from any drop of
## JUMP_MIN_M or more. Freefall with the territory's wind, a wingsuit to glide
## and steer, a canopy to land; the camera pulls back and follows. The flight
## maths is JumpPhysics (pure, tested).
##
## What counts:
##   ticket     a sky-deck jump paid 1 Ⓐ to this QING (ArcadePay, receipt-verified): scored, kept
##   own tower  a jump from your own tower (bars you grew with Su here): free, scored, kept
##   practice   everything else: flown and shown, never recorded
## Scores are kept locally (user://basejump.cfg), keyed by QING and wallet.

const BEST := "user://basejump.cfg"
const AAD_AGL := 30.0     ## automatic canopy if still in freefall this low and fast
const AAD_SINK := 14.0

enum { IDLE, FLYING, LIFT }

var state := IDLE
var mode := JumpPhysics.Mode.FREEFALL
var source := "practice"
var ticket: Dictionary = {}
var yaw := 0.0
var path_m := 0.0
var airtime := 0.0
var flare_left := 0.0
var canopy_t := 0.0

var _player: CharacterBody3D
var _hud: Node
var _landmark: Landmark
var _columns: BarColumns
var _address := ""
var _height: Callable      ## world (x, z) → terrain height (world)
var _core: Node3D
var _tint := Color("#7fd3ff")
var _rig: Node3D
var _model: Node3D
var _gear: Node3D
var _wing: MeshInstance3D
var _wing_mesh: Mesh
var _wing_mat: Material
var _canopy: Node3D
var _streaks: CPUParticles3D
var _panel: Label
var _card: PanelContainer
var _card_label: Label
var _card_t := 0.0
var _t := 0.0
var _focus := ""
var _lift_t := 0.0
var _lift_from := Vector3.ZERO
var _lift_h := 0.0
var _lift_pad: MeshInstance3D
var _suit_light: OmniLight3D   ## the suit's own lights, so a jumper reads against the night
var _last_pos := Vector3.ZERO
var _g := 3.2              ## the player's own (low) gravity


func setup(player: CharacterBody3D, hud: Node, landmark: Landmark, columns: BarColumns, address: String,
		height_fn: Callable, core: Node3D, tint: Color) -> void:
	_player = player
	_hud = hud
	_landmark = landmark
	_columns = columns
	_address = address.to_lower()
	_height = height_fn
	_core = core
	_tint = tint
	_rig = player.get_node_or_null("CameraRig")
	_g = float(player.get("gravity")) if player.get("gravity") != null else 3.2
	_model = player.get_node_or_null("PlayerModel")
	if _landmark:
		_landmark.jump_requested.connect(launch)
	GameManager.fly_mode_changed.connect(func(f: bool) -> void:
		if f and state == FLYING:
			_end(false))
	_build_gear()
	_build_hud()


# --- Starting ---------------------------------------------------------------

## Leaves the plank (or a roof) at `at`, moving along `dir`.
func launch(at: Vector3, dir: Vector3, p_source: String, p_ticket: Dictionary) -> void:
	_player.global_position = at
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	_begin(d * 6.5 + Vector3(0, 3.5, 0), p_source, p_ticket)
	yaw = atan2(-d.x, -d.z)
	_hud.ticker("%s · %s to deploy the wingsuit · %s the canopy" % [
		{"ticket": "TICKETED JUMP · block %d" % int(p_ticket.get("block", 0)), "own tower": "YOUR TOWER", "practice": "PRACTICE JUMP · not recorded"}.get(p_source, p_source),
		ControlsHelp.key_of("wingsuit"), ControlsHelp.key_of("parachute")], Color("#ffd27a"), 8.0)


func _begin(vel: Vector3, p_source: String, p_ticket: Dictionary) -> void:
	state = FLYING
	mode = JumpPhysics.Mode.FREEFALL
	source = p_source
	ticket = p_ticket
	path_m = 0.0
	airtime = 0.0
	flare_left = JumpPhysics.FLARE_S
	canopy_t = 0.0
	_player.set_physics_process(false)
	_player.velocity = vel
	_last_pos = _player.global_position
	yaw = _player.rotation.y
	_focus = ""
	_hud.hide_prompt()
	_set_pose("freefall")
	_streaks.emitting = true
	_panel.visible = true


# --- Watching for drops and your own tower --------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _card_t > 0.0:
		_card_t -= delta
		if _card_t <= 0.0:
			_card.visible = false
	if state == LIFT:
		_lift_tick(delta)
		return
	if state == FLYING:
		_update_panel()
		_camera(delta)
		return
	if not _player.is_physics_processing() or GameManager.is_flying:
		_set_focus("", {})
		return
	# A drop of JUMP_MIN_M or more under a falling player is a base jump.
	if not _player.is_on_floor() and _player.velocity.y < -5.0 and _void_below() >= LandmarkPlan.JUMP_MIN_M:
		var src := "practice"
		var mine := _my_tower()
		if not mine.is_empty() and _near_top(mine, 8.0):
			src = "own tower"
		_begin(_player.velocity, src, {})
		return
	_tower_prompts()


func _void_below() -> float:
	var space := _player.get_world_3d().direct_space_state
	var from := _player.global_position + Vector3(0, 0.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -LandmarkPlan.JUMP_MIN_M - 1.0, 0))
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return from.y - _height.call(from.x, from.z) if _height.is_valid() else 999.0
	return from.y - (hit["position"] as Vector3).y


func _my_tower() -> Dictionary:
	if _columns == null or Session.wallet == "":
		return {}
	return _columns.tower_of(Session.wallet)


func _near_top(t: Dictionary, margin: float) -> bool:
	var root: Node3D = t["root"]
	var p := root.to_local(_player.global_position)
	return Vector2(p.x, p.z).length() < float(t["width"]) * 0.75 + margin and p.y > float(t["height"]) - 4.0


func _tower_prompts() -> void:
	var t := _my_tower()
	if t.is_empty():
		_set_focus("", {})
		return
	var root: Node3D = t["root"]
	var p := root.to_local(_player.global_position)
	var flat := Vector2(p.x, p.z).length()
	var w: float = t["width"]
	if p.y < 3.0 and flat < w * 0.5 + 3.0:
		_set_focus("tower_lift", t)
	elif p.y > float(t["height"]) - 1.0 and flat < w * 0.75 + 0.5:
		_set_focus("tower_top", t)
	else:
		_set_focus("", {})


func _set_focus(z: String, t: Dictionary) -> void:
	if z == _focus:
		return
	_focus = z
	var k := ControlsHelp.key_of("interact")
	match z:
		"":
			_hud.hide_prompt()
		"tower_lift":
			var h: float = t["height"]
			if h < LandmarkPlan.JUMP_MIN_M:
				_hud.show_prompt("YOUR TOWER · %d m (your Hypobar here) · base jumps need %d m: Su here to grow it" % [int(h), int(LandmarkPlan.JUMP_MIN_M)])
			else:
				_hud.show_prompt("%s  Lift to your tower's roof · %d m (your Hypobar here)" % [k, int(h)])
		"tower_top":
			_hud.show_prompt("%s  BASE JUMP from your tower · free: it is yours (scored)" % k)


func _unhandled_input(event: InputEvent) -> void:
	if state == FLYING:
		if event.is_action_pressed("wingsuit"):
			get_viewport().set_input_as_handled()
			if mode == JumpPhysics.Mode.FREEFALL:
				mode = JumpPhysics.Mode.WINGSUIT
				_set_pose("wingsuit")
				_hud.ticker("WINGSUIT · glide %.1f : 1 · %s/%s dive and flare, %s/%s turn" % [
					JumpPhysics.steady(mode, 0.0).x / JumpPhysics.steady(mode, 0.0).y, ControlsHelp.key_of("move_forward"),
					ControlsHelp.key_of("move_back"), ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right")], DeepFieldTheme.ICE, 5.0)
			elif mode == JumpPhysics.Mode.WINGSUIT:
				mode = JumpPhysics.Mode.FREEFALL
				_set_pose("freefall")
		elif event.is_action_pressed("parachute") and mode != JumpPhysics.Mode.CANOPY:
			get_viewport().set_input_as_handled()
			_deploy_canopy("CANOPY")
		return
	if _focus == "" or state != IDLE or not event.is_action_pressed("interact"):
		return
	var t := _my_tower()
	if t.is_empty():
		return
	get_viewport().set_input_as_handled()
	if _focus == "tower_lift" and float(t["height"]) >= LandmarkPlan.JUMP_MIN_M:
		_start_lift(t)
	elif _focus == "tower_top":
		var root: Node3D = t["root"]
		var out := (root.global_transform.basis * Vector3(0, 0, 1)).normalized()  # away from the Core
		var top := root.global_position + Vector3(0, float(t["height"]) + 0.6, 0) + out * (float(t["width"]) * 0.5 + 1.2)
		launch(top, out, "own tower", {})


func _deploy_canopy(why: String) -> void:
	mode = JumpPhysics.Mode.CANOPY
	canopy_t = 0.0
	_set_pose("canopy")
	_hud.ticker("%s · %s/%s steer · %s brakes · hold %s to flare at the ground" % [why, ControlsHelp.key_of("move_left"),
		ControlsHelp.key_of("move_right"), ControlsHelp.key_of("move_back"), ControlsHelp.key_of("jump")], DeepFieldTheme.ICE, 6.0)


# --- Your own tower's lift (a window-washer's cradle up the facade) -------------

func _start_lift(t: Dictionary) -> void:
	state = LIFT
	_lift_t = 0.0
	var root: Node3D = t["root"]
	var out := (root.global_transform.basis * Vector3(0, 0, 1)).normalized()
	_lift_from = root.global_position + out * (float(t["width"]) * 0.5 + 0.9) + Vector3(0, 0.6, 0)
	_lift_h = float(t["height"])
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_lift_pad.visible = true
	_hud.hide_prompt()
	_focus = ""


func _lift_tick(delta: float) -> void:
	_lift_t += delta
	var h := _lift_h + 0.4
	var y := LandmarkPlan.lift_travel(_lift_t, h)
	var p := _lift_from + Vector3(0, y, 0)
	_player.global_position = p
	_lift_pad.global_position = p - Vector3(0, 0.08, 0)
	if _lift_t >= LandmarkPlan.lift_duration(h):
		# Step onto the roof
		var t := _my_tower()
		var root: Node3D = t.get("root", null)
		_player.global_position = (Vector3(root.global_position.x, p.y + 0.4, root.global_position.z)) if root else p
		_lift_pad.visible = false
		state = IDLE
		_player.set_physics_process(true)


# --- Flight -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state != FLYING:
		return
	airtime += delta
	var inp := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var steer := inp.x
	var pitch := inp.y
	var air := JumpPhysics.wind(_address, _t)
	var pos := _player.global_position
	var track := Vector3.ZERO
	if mode == JumpPhysics.Mode.FREEFALL:
		# Tracking: push toward where the camera looks; the body faces the camera.
		if _rig:
			var b := _rig.global_transform.basis
			var f := Vector3(-b.z.x, 0, -b.z.z).normalized()
			var r := Vector3(b.x.x, 0, b.x.z).normalized()
			track = f * inp.y + r * inp.x
			yaw = lerp_angle(yaw, atan2(-f.x, -f.z), minf(1.0, 3.0 * delta))
	else:
		yaw = JumpPhysics.turn(mode, yaw, steer, delta)
		# The territory's edge: the wind there turns you back toward the middle
		var e := JumpPhysics.edge_push(pos - _core.global_position)
		if e.length() > 0.01:
			var home := -(pos - _core.global_position)
			yaw = lerp_angle(yaw, atan2(-home.x, -home.z), minf(1.0, e.length() * 0.2 * delta))
	if mode == JumpPhysics.Mode.CANOPY:
		canopy_t += delta
	var flare := 0.0
	if mode == JumpPhysics.Mode.CANOPY and Input.is_action_pressed("jump") and flare_left > 0.0:
		flare_left -= delta
		flare = 1.0
	var v := JumpPhysics.step(mode, _player.velocity, yaw, steer, pitch, track, Input.is_action_pressed("sprint"), flare, air, _g, delta)
	if mode == JumpPhysics.Mode.FREEFALL:
		v += JumpPhysics.edge_push(pos - _core.global_position) * delta
	elif mode == JumpPhysics.Mode.CANOPY and canopy_t < 1.4:
		# Opening shock: the canopy takes 1.4 s to fly; until then it brakes the fall
		v.y = lerpf(_player.velocity.y, v.y, minf(1.0, delta * 2.5))
	_player.velocity = v
	_player.rotation.y = yaw
	_player.move_and_slide()
	# Never through the border fields (the controller clamps on foot; we fly here)
	var lim := JuliaHeightfield.SIZE_M * 0.5 - 2.0
	_player.position.x = clampf(_player.position.x, -lim, lim)
	_player.position.z = clampf(_player.position.z, -lim, lim)
	var now := _player.global_position
	path_m += Vector2(now.x - _last_pos.x, now.z - _last_pos.z).length()
	_last_pos = now
	if _model and _model.has_method("update_movement"):
		_model.update_movement(_player.velocity, false, true)
	var agl: float = now.y - (_height.call(now.x, now.z) if _height.is_valid() else -INF)
	if mode == JumpPhysics.Mode.FREEFALL and agl < AAD_AGL and -_player.velocity.y > AAD_SINK:
		_deploy_canopy("AAD FIRED · automatic canopy")
	if _player.is_on_floor() or agl < -1.0:
		_land(v)


func _land(v: Vector3) -> void:
	var target := Vector2.INF
	if _landmark and _landmark.has_tower():
		var r := _landmark.ring_global()
		target = Vector2(r.x, r.z)
	var p := _player.global_position
	var s := JumpPhysics.score(path_m, Vector2(p.x, p.z), target if target != Vector2.INF else Vector2(p.x, p.z) + Vector2(1e6, 0), airtime, v)
	_end(true)
	_show_card(s, target != Vector2.INF)


func _end(landed: bool) -> void:
	state = IDLE
	_set_pose("")
	_streaks.emitting = false
	_panel.visible = false
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	if not landed:
		_player.velocity = Vector3.ZERO
	if _rig:
		var arm := _rig.get_node_or_null("SpringArm3D") as SpringArm3D
		if arm:
			arm.spring_length = float(_rig.get("follow_distance"))
		_rig.set("extra_fov", 0.0)
		_rig.set("shake", 0.0)


func _set_pose(p: String) -> void:
	if _model and _model.has_method("set_air_pose"):
		_model.set_air_pose(p)
	if _model and p == "" and _model.has_method("update_movement"):
		_model.update_movement(Vector3.ZERO, true, false)
	_attach_wing()  # the avatar can rebuild its body (a new look): follow it
	_wing.visible = p == "wingsuit"
	_canopy.visible = p == "canopy"
	_suit_light.visible = p != ""
	_canopy.scale = Vector3.ONE * 0.15


func _camera(delta: float) -> void:
	if _canopy.visible:
		_canopy.scale = _canopy.scale.lerp(Vector3.ONE, minf(1.0, delta * 2.2))
	if _rig == null:
		return
	var speed := _player.velocity.length()
	var arm := _rig.get_node_or_null("SpringArm3D") as SpringArm3D
	var want: float = {JumpPhysics.Mode.FREEFALL: 7.0, JumpPhysics.Mode.WINGSUIT: 9.5, JumpPhysics.Mode.CANOPY: 11.0}[mode]
	if arm:
		arm.spring_length = lerpf(arm.spring_length, want, minf(1.0, delta * 1.5))
	_rig.set("extra_fov", clampf((speed - 8.0) * 0.6, 0.0, 22.0))
	_rig.set("shake", clampf((speed - 15.0) / 30.0, 0.0, 1.0) * (1.0 if mode != JumpPhysics.Mode.CANOPY else 0.2))
	if mode != JumpPhysics.Mode.FREEFALL and _rig.has_method("chase"):
		var pitch := -0.18 if mode == JumpPhysics.Mode.WINGSUIT else -0.32
		_rig.chase(yaw, pitch, 1.6, delta)
	elif _rig.has_method("chase"):
		_rig.chase(yaw, -0.75, 0.6, delta)  # freefall: look down past your feet
	# Wind streaks rush past along the flight path
	_streaks.global_position = _player.global_position + _player.velocity * 0.45
	_streaks.direction = -_player.velocity.normalized() if speed > 1.0 else Vector3.UP
	_streaks.initial_velocity_min = speed * 0.4
	_streaks.initial_velocity_max = speed * 0.6


# --- Gear ---------------------------------------------------------------------

func _build_gear() -> void:
	_gear = Node3D.new()
	_gear.name = "JumpGear"
	add_child(_gear)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.09, 0.1, 0.13)
	cloth.emission_enabled = true
	cloth.emission = _tint
	cloth.emission_energy_multiplier = 0.35
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 0.6
	# The wingsuit's membranes, in the avatar's body space (arms spread, legs apart)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		for pt in [Vector3(0.17, 1.42, 0.02), Vector3(0.62, 1.02, 0.02), Vector3(0.14, 0.92, 0.02)]:
			st.add_vertex(Vector3(pt.x * s, pt.y, pt.z))
	for pt in [Vector3(-0.13, 0.92, 0.03), Vector3(-0.34, 0.1, 0.03), Vector3(0.34, 0.1, 0.03),
			Vector3(-0.13, 0.92, 0.03), Vector3(0.34, 0.1, 0.03), Vector3(0.13, 0.92, 0.03)]:
		st.add_vertex(pt)
	st.generate_normals()
	_wing_mesh = st.commit()
	_wing_mat = cloth
	_attach_wing()
	_wing.visible = false
	# The canopy: a ram-air wing of seven cells over the player, with its lines
	_canopy = Node3D.new()
	_canopy.name = "Canopy"
	_canopy.visible = false
	_player.add_child(_canopy)
	var cells := 7
	for i in cells:
		var f := (i - (cells - 1) * 0.5) / ((cells - 1) * 0.5)  # -1..1
		var cell := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.25, 0.5, 2.8)
		cell.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = _tint if i % 2 == 0 else Color(0.92, 0.94, 0.97)
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.25
		cell.material_override = m
		cell.position = Vector3(f * 3.9, 5.4 - f * f * 0.9, 0.2)
		cell.rotation.z = -f * 0.35
		_canopy.add_child(cell)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_LINES)
	for i in cells:
		var f := (i - (cells - 1) * 0.5) / ((cells - 1) * 0.5)
		for dz in [-1.0, 1.2]:
			lines.add_vertex(Vector3(0.22 * signf(f), 1.45, 0.0))
			lines.add_vertex(Vector3(f * 3.9, 5.15 - f * f * 0.9, dz))
	var lm := MeshInstance3D.new()
	lm.mesh = lines.commit()
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(0.85, 0.88, 0.95)
	lm.material_override = lmat
	_canopy.add_child(lm)
	_suit_light = OmniLight3D.new()
	_suit_light.name = "SuitLight"
	_suit_light.light_color = _tint.lerp(Color.WHITE, 0.5)
	_suit_light.light_energy = 1.6
	_suit_light.omni_range = 6.5
	_suit_light.position = Vector3(0, 2.6, -0.4)
	_suit_light.visible = false
	_player.add_child(_suit_light)
	# Your own tower's cradle
	_lift_pad = MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(1.8, 0.12, 1.8)
	_lift_pad.mesh = pb
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.2, 0.21, 0.24)
	pm.emission_enabled = true
	pm.emission = Color("#ffd27a")
	pm.emission_energy_multiplier = 0.8
	_lift_pad.material_override = pm
	_lift_pad.top_level = true
	_lift_pad.visible = false
	_gear.add_child(_lift_pad)
	# Wind streaks (world space)
	_streaks = CPUParticles3D.new()
	_streaks.name = "WindStreaks"
	_streaks.top_level = true
	_streaks.local_coords = false
	_streaks.emitting = false
	_streaks.amount = 90
	_streaks.lifetime = 0.7
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_streaks.emission_sphere_radius = 9.0
	_streaks.spread = 4.0
	_streaks.gravity = Vector3.ZERO
	_streaks.particle_flag_align_y = true
	var sm := BoxMesh.new()
	sm.size = Vector3(0.025, 1.6, 0.025)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.85, 0.93, 1.0, 0.28)
	sm.material = smat
	_streaks.mesh = sm
	_gear.add_child(_streaks)


func _attach_wing() -> void:
	var body: Node3D = _model.get("body") if is_instance_valid(_model) else null
	var parent: Node = body if is_instance_valid(body) else _player
	if not is_instance_valid(_wing):
		_wing = MeshInstance3D.new()
		_wing.name = "Wingsuit"
		_wing.mesh = _wing_mesh
		_wing.material_override = _wing_mat
	if _wing.get_parent() == parent:
		return
	if _wing.get_parent():
		_wing.get_parent().remove_child(_wing)
	parent.add_child(_wing)


# --- HUD ------------------------------------------------------------------------

func _build_hud() -> void:
	_panel = Label.new()
	_panel.theme = DeepFieldTheme.get_theme()
	_panel.theme_type_variation = "MonoLabel"
	_panel.add_theme_font_size_override("font_size", 18)
	_panel.add_theme_color_override("font_color", DeepFieldTheme.ICE)
	_panel.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_panel.add_theme_constant_override("outline_size", 6)
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position = Vector2(-460, -210)
	_panel.size = Vector2(920, 90)
	_panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.visible = false
	_hud.add_child(_panel)
	_card = PanelContainer.new()
	_card.theme = DeepFieldTheme.get_theme()
	_card.add_theme_stylebox_override("panel", DeepFieldTheme.panel_style())
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.position = Vector2(-300, -170)
	_card.custom_minimum_size = Vector2(600, 0)
	_card.visible = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_card)
	_card_label = Label.new()
	_card_label.theme_type_variation = "MonoLabel"
	_card_label.add_theme_font_size_override("font_size", 15)
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_card_label)


func _update_panel() -> void:
	var p := _player.global_position
	var v := _player.velocity
	var agl: float = p.y - (_height.call(p.x, p.z) if _height.is_valid() else 0.0)
	var name: String = {JumpPhysics.Mode.FREEFALL: "FREEFALL", JumpPhysics.Mode.WINGSUIT: "WINGSUIT", JumpPhysics.Mode.CANOPY: "CANOPY"}[mode]
	var fwd := Vector2(v.x, v.z).length()
	var glide := ("glide %.1f" % (fwd / maxf(0.1, -v.y))) if v.y < -0.1 else "climbing"
	var ring := ""
	if _landmark and _landmark.has_tower():
		var r := _landmark.ring_global()
		var d := Vector2(r.x - p.x, r.z - p.z)
		ring = "ring %d m %s" % [int(d.length()), FairSite._compass(d)]
	var w := JumpPhysics.wind(_address, _t)
	var hint := ""
	match mode:
		JumpPhysics.Mode.FREEFALL:
			hint = "%s wingsuit · %s canopy · %s head-down" % [ControlsHelp.key_of("wingsuit"), ControlsHelp.key_of("parachute"), ControlsHelp.key_of("sprint")]
		JumpPhysics.Mode.WINGSUIT:
			hint = "%s canopy · %s freefall" % [ControlsHelp.key_of("parachute"), ControlsHelp.key_of("wingsuit")]
		JumpPhysics.Mode.CANOPY:
			hint = "hold %s to flare (%.1f s left)" % [ControlsHelp.key_of("jump"), maxf(0.0, flare_left)]
	_panel.text = "%s   ALT %d m   %d m/s   ↓ %.1f m/s   %s\n%s   ·   wind %.1f m/s from the %s   ·   flown %d m\n%s" % [
		name, int(agl), int(v.length()), -v.y, glide, ring, w.length(), FairSite._compass(Vector2(-w.x, -w.z)), int(path_m), hint]


func _show_card(s: Dictionary, has_ring: bool) -> void:
	var lines: Array = []
	lines.append("BASE JUMP · %s" % {"ticket": "TICKETED", "own tower": "FROM YOUR TOWER", "practice": "PRACTICE"}.get(source, source.to_upper()))
	lines.append("%d points · %s" % [int(s["points"]), s["grade"]])
	lines.append("flown %d m · airtime %.1f s" % [int(s["distance"]), float(s["airtime"])])
	if has_ring:
		lines.append("%.1f m from the ring's centre · +%d" % [float(s["from_target"]), int(s["accuracy"])])
	match source:
		"ticket":
			lines.append("ticket %s… verified in block %d (1 Ⓐ to this QING)" % [String(ticket.get("hash", "")).left(12), int(ticket.get("block", 0))])
		"own tower":
			lines.append("from your own tower: its height is your Hypobar here")
		_:
			lines.append("practice: not recorded")
	if source != "practice":
		var best := _record(int(s["points"]))
		lines.append("your best here: %d" % best)
	_card_label.text = "\n".join(lines)
	_card.visible = true
	_card_t = 9.0
	_hud.ticker("LANDED · %d points · %s" % [int(s["points"]), s["grade"]], Color("#ffd27a"), 12.0)


func _record(points: int) -> int:
	var c := ConfigFile.new()
	c.load(BEST)
	var key := "%s@%s" % [Session.wallet.to_lower() if Session.wallet != "" else Wallet.address.to_lower(), _address]
	var best := maxi(int(c.get_value("best", key, 0)), points)
	c.set_value("best", key, best)
	c.save(BEST)
	return best


# --- Preview (screenshots) -------------------------------------------------------

## Poses the player mid-flight in `pose` at `at` (screenshot views only).
func preview(at: Vector3, dir: Vector3, pose: String) -> void:
	_player.global_position = at
	yaw = atan2(-dir.x, -dir.z)
	_player.rotation.y = yaw
	_player.visible = true
	_player.velocity = dir * 22.0 + Vector3(0, -7.0, 0)
	if _model:
		_model.process_mode = Node.PROCESS_MODE_ALWAYS
		if _model.has_method("update_movement"):
			_model.update_movement(_player.velocity, false, true)
	mode = JumpPhysics.Mode.WINGSUIT if pose == "wingsuit" else JumpPhysics.Mode.CANOPY
	_set_pose(pose)
	if pose == "canopy":
		_canopy.scale = Vector3.ONE
