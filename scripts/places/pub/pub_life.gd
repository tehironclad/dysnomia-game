class_name PubLife
extends Node3D
## The people of Sunny's Pub: Sunny behind the bar and a handful of regulars
## who sit, lean and chat, all on v2's avatar (HumanAvatar: the Quaternius body
## and its UAL clip library, which has real Sitting_Idle / Sitting_Talking /
## Idle_Talking clips). They are the room's furniture of life, not players:
## nothing about them is read from, or claimed to be, the chain.
##
## Set pieces, played only after a write is verified on chain: a drink poured
## and slid down the counter (play_pour), and the room cheering a round (cheer).

const MAX_GLASSES := 6
const SEAT_LIFT_STOOL := 0.3  # the sitting clip sits at chair height; bar stools are higher
const BARTENDER_STOPS := [Vector3(-3.2, 0, -6.35), Vector3(-1.0, 0, -6.35), Vector3(1.6, 0, -6.35), Vector3(-4.6, 0, -6.6)]

var sunny: HumanAvatar
var patrons: Array[HumanAvatar] = []
var room: PubRoom

var _rng := RandomNumberGenerator.new()
var _glasses: Array[Node3D] = []
var _serve := 0
var _confetti: CPUParticles3D
var _sunny_target := Vector3.ZERO
var _sunny_pause := 5.0
var _sunny_stop := 1
var _sunny_hold := 0.0  # seconds Sunny stays put (serving, or someone at the bar)
var _walker: HumanAvatar
var _walker_pts: Array = []
var _walker_i := 0
var _walker_pause := 0.0
var _focus := Vector3.INF  # where Sunny looks when someone is at the bar


func setup(p_room: PubRoom) -> void:
	room = p_room
	name = "PubLife"
	_rng.seed = 0x50a1
	# Sunny: the sun-headed bartender, on the duckboards.
	sunny = _avatar("sunny", Color(0.92, 0.9, 0.84), Color(0.45, 0.28, 0.14), "male")
	sunny.name = "Sunny"
	var h := sunny.find_child("Head_sunny", true, false)
	if h:
		(h as Node3D).scale = Vector3.ONE * 1.35  # a big sunny head, as on the sign
	sunny.position = _deck(BARTENDER_STOPS[1])
	_sunny_target = sunny.position
	# Regulars. [head, fabric, body, at, facing (yaw toward), clip]
	var st := room.stools
	var la: Vector3 = room.lounges[0]
	var ht: Vector3 = room.hightops[0]
	var cast := [
		["bear", Color(0.22, 0.14, 0.38), "female", st[0] + Vector3(0, SEAT_LIFT_STOOL, 0.12), Vector3(0, 0, -1), "Sitting_Idle"],
		["fox", Color(0.10, 0.36, 0.40), "male", st[st.size() - 2] + Vector3(0, SEAT_LIFT_STOOL, 0.12), Vector3(0.4, 0, -1), "Sitting_Talking"],
		["frog", Color(0.85, 0.42, 0.10), "male", Vector3(3.95, 0, -4.55), Vector3(-1, 0, 0.1), "Idle_Talking"],
		["cat", Color(0.48, 0.10, 0.14), "female", la + Vector3(-0.35, 0, 0.78), Vector3(0, 0, -1), "Sitting_Talking"],
		["rat", Color(0.82, 0.83, 0.86), "male", la + Vector3(0.35, 0, -0.78), Vector3(0, 0, 1), "Sitting_Idle"],
		["robot", Color(0.30, 0.34, 0.18), "female", ht + Vector3(0.62, 0, 0.15), Vector3(-1, 0, -0.2), "Idle"],
	]
	for c in cast:
		var p := _avatar(c[0], c[1], c[1].darkened(0.35), c[2])
		p.position = c[3]
		p.rotation.y = atan2(c[4].x, c[4].z)
		p.hold_clip = c[5]
		p.hold_speed = _rng.randf_range(0.85, 1.1)
		patrons.append(p)
	# One regular walks a slow loop: the darts, the pool table, the bar end.
	_walker = _avatar("dog", Color(0.12, 0.16, 0.34), Color(0.12, 0.16, 0.34).darkened(0.35), "male")
	_walker_pts = [Vector3(7.0, 0, -3.3), Vector3(6.6, 0, 0.2), Vector3(4.2, 0, -0.4), Vector3(5.2, 0, -4.4)]
	_walker.position = _walker_pts[0]
	_walker_pause = 3.0
	patrons.append(_walker)
	# Everyone is indoors: no shadow pass for their meshes.
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_confetti()


func _avatar(head: String, fabric: Color, armour: Color, body: String) -> HumanAvatar:
	var a := HumanAvatar.new()
	a.civilian = true  # off duty: no armour or jetpack (a third of the meshes)
	a.body_kind = body
	add_child(a)
	a.set_head(head)
	a.set_suit_colors(fabric, armour)
	return a


static func _deck(p: Vector3) -> Vector3:
	return Vector3(p.x, PubRoom.PLATFORM_H, p.z)


## Someone at the counter (or nobody: Vector3.INF): Sunny comes over and faces them.
func attend(at: Vector3) -> void:
	_focus = at
	if at != Vector3.INF:
		_sunny_target = _deck(Vector3(clampf(at.x, PubRoom.COUNTER_X0 + 0.6, PubRoom.COUNTER_X1 - 0.6), 0, -6.25))


func _process(delta: float) -> void:
	_drive_sunny(delta)
	_drive_walker(delta)


func _drive_sunny(delta: float) -> void:
	if sunny == null:
		return
	_sunny_hold = maxf(0.0, _sunny_hold - delta)
	var to := _sunny_target - sunny.position
	to.y = 0.0
	if to.length() > 0.08:
		var v := to.normalized() * minf(1.5, to.length() * 3.0)
		sunny.position += v * delta
		sunny.rotation.y = lerp_angle(sunny.rotation.y, atan2(v.x, v.z), clampf(delta * 8.0, 0.0, 1.0))
		if sunny.hold_clip != "Interact":
			sunny.hold_clip = ""
		sunny.update_movement(v, true, false)
		return
	sunny.update_movement(Vector3.ZERO, true, false)
	if _sunny_hold > 0.0:
		return
	if _focus != Vector3.INF:
		var f := _focus - sunny.position
		sunny.rotation.y = lerp_angle(sunny.rotation.y, atan2(f.x, f.z), clampf(delta * 4.0, 0.0, 1.0))
		sunny.hold_clip = "Idle_Talking" if sunny.hold_clip == "Idle_Talking" else ""
		return
	# Working the bar: pause at a stop (facing the room or the shelves), then the next.
	sunny.rotation.y = lerp_angle(sunny.rotation.y, 0.0 if _sunny_stop != 3 else PI, clampf(delta * 3.0, 0.0, 1.0))
	_sunny_pause -= delta
	if _sunny_pause <= 0.0:
		_sunny_stop = (_sunny_stop + 1) % BARTENDER_STOPS.size()
		_sunny_target = _deck(BARTENDER_STOPS[_sunny_stop])
		_sunny_pause = _rng.randf_range(3.0, 7.0)


func _drive_walker(delta: float) -> void:
	if _walker == null:
		return
	if _walker_pause > 0.0:
		_walker_pause -= delta
		_walker.update_movement(Vector3.ZERO, true, false)
		return
	var target: Vector3 = _walker_pts[_walker_i]
	var to := target - _walker.position
	to.y = 0.0
	if to.length() < 0.2:
		_walker_i = (_walker_i + 1) % _walker_pts.size()
		_walker_pause = _rng.randf_range(3.0, 8.0)
		return
	var v := to.normalized() * 1.1
	_walker.position += v * delta
	_walker.rotation.y = lerp_angle(_walker.rotation.y, atan2(v.x, v.z), clampf(delta * 6.0, 0.0, 1.0))
	_walker.update_movement(v, true, false)


## Sunny says a line: Idle_Talking for a while.
func talk(seconds: float = 4.0) -> void:
	if sunny == null:
		return
	sunny.hold_clip = "Idle_Talking"
	get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(sunny) and sunny.hold_clip == "Idle_Talking":
			sunny.hold_clip = "")


# --- Set pieces (after a verified write only) --------------------------------------

## A drink, after its receipt was verified: Sunny steps to the taps, a handle is
## pulled, the glass fills and slides down the counter to the order spot.
func play_pour(look: Array, rounds: int = 1) -> void:
	_serve += 1
	_sunny_target = _deck(Vector3(-2.6, 0, -6.2))
	_sunny_hold = 3.0
	sunny.hold_clip = "Interact"
	get_tree().create_timer(2.6).timeout.connect(func():
		if is_instance_valid(sunny) and sunny.hold_clip == "Interact":
			sunny.hold_clip = "")
	if not room.tap_handles.is_empty():
		var hdl: Node3D = room.tap_handles[_serve % room.tap_handles.size()].get_parent()
		var tw := create_tween()
		tw.tween_property(hdl, "rotation_degrees:x", 28.0, 0.25).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(0.8)
		tw.tween_property(hdl, "rotation_degrees:x", 0.0, 0.3)
	if room.bar_flash:
		var l := room.bar_flash
		var base: float = room.light_base[0] if not room.light_base.is_empty() else l.light_energy
		var lt := create_tween()
		lt.tween_property(l, "light_energy", base * 1.8, 0.2)
		lt.tween_property(l, "light_energy", base, 1.2)
	if room.back_glow_mat:
		var gt := create_tween()
		gt.tween_property(room.back_glow_mat, "emission_energy_multiplier", 0.9, 0.25)
		gt.tween_property(room.back_glow_mat, "emission_energy_multiplier", 0.32, 1.4)
	var top := PubRoom.COUNTER_H
	var start := Vector3(-3.1, top, PubRoom.COUNTER_Z - 0.1)
	for r in rounds:
		var g := _make_glass(look[0], look[1])
		g.position = start + Vector3(float(r) * 0.14, 0, 0)
		g.scale = Vector3.ONE * 0.01
		add_child(g)
		_glasses.append(g)
		var liquid: Node3D = g.get_node("Liquid")
		liquid.scale = Vector3(1, 0.05, 1)
		var slot := (_serve + r) % 4
		var dest := Vector3(PubRoom.ORDER_X - 0.3 + float(slot) * 0.18, top, PubRoom.COUNTER_Z + 0.25)
		var tw := create_tween()
		tw.tween_interval(float(r) * 0.35)
		tw.tween_property(g, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(liquid, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.25)
		tw.tween_property(g, "position", dest, 1.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(g, "rotation:y", _rng.randf_range(-0.8, 0.8), 1.1)
		tw.tween_interval(40.0)
		tw.tween_property(g, "scale", Vector3.ONE * 0.01, 0.4)
		tw.tween_callback(_drop_glass.bind(g))
	while _glasses.size() > MAX_GLASSES:
		_drop_glass(_glasses[0])


func _drop_glass(g: Node3D) -> void:
	_glasses.erase(g)
	if is_instance_valid(g):
		g.queue_free()


func _make_glass(col: Color, kind: String) -> Node3D:
	var g := Node3D.new()
	g.name = "ServedGlass"
	var liquid_mat := PubKit.glass(Color(col.r, col.g, col.b, 0.85), col, 2.2)
	var dims := {"shot": [0.028, 0.024, 0.07], "rocks": [0.045, 0.042, 0.09], "pint": [0.045, 0.036, 0.16],
		"coupe": [0.05, 0.03, 0.08], "highball": [0.036, 0.034, 0.17], "fizz": [0.036, 0.034, 0.17]}
	var dd: Array = dims.get(kind, dims["rocks"])
	var rt: float = dd[0]
	var rb: float = dd[1]
	var hh: float = dd[2]
	PubKit.mesh_instance(PubKit.cyl(rt, rb, hh, 14), Vector3(0, hh * 0.5, 0), PubKit.drinkware(), g)
	var liquid := Node3D.new()
	liquid.name = "Liquid"
	g.add_child(liquid)
	var lh := hh * 0.78
	PubKit.mesh_instance(PubKit.cyl(rt * 0.9, rb * 0.88, lh, 14), Vector3(0, lh * 0.5 + 0.004, 0), liquid_mat, liquid)
	match kind:
		"pint":
			PubKit.mesh_instance(PubKit.cyl(rt * 0.95, rt * 0.9, 0.025, 14), Vector3(0, lh + 0.016, 0), PubKit.flat(Color(1.0, 0.97, 0.9), 0.8), liquid)
		"rocks":
			for k in 2:
				var ice_box := BoxMesh.new()
				ice_box.size = Vector3.ONE * 0.028
				var ice := PubKit.mesh_instance(ice_box, Vector3(-0.012 + float(k) * 0.022, lh - 0.008, 0.005 * float(k)),
					PubKit.glass(Color(0.9, 0.95, 1.0, 0.55), Color(0.8, 0.9, 1.0), 0.4), liquid)
				ice.rotation_degrees = Vector3(20.0 * float(k), 35.0, 10.0)
		"coupe":
			PubKit.mesh_instance(PubKit.cyl(0.01, 0.01, 0.012, 8), Vector3(0.03, hh + 0.004, 0), PubKit.neon(Color(0.6, 1.0, 0.2), 1.5), liquid)
		"fizz":
			for k in 5:
				PubKit.mesh_instance(PubKit.sphere(0.004, 6), Vector3(_rng.randf_range(-0.02, 0.02), 0.02 + float(k) * 0.025, _rng.randf_range(-0.02, 0.02)),
					PubKit.neon(Color(1.0, 0.85, 1.0), 3.0), liquid)
	return g


## A round for the house, after the Transfer to the QING was verified: everyone
## dances for a few seconds, the lights flare, the neon blinks, confetti drifts.
func cheer() -> void:
	for p in patrons + [sunny]:
		if not is_instance_valid(p):
			continue
		var was: String = p.hold_clip
		var sitting := was.begins_with("Sitting")
		p.hold_clip = "Sitting_Talking" if sitting else "Dance"
		var tw := create_tween()
		tw.tween_interval(4.5)
		tw.tween_callback(func():
			if is_instance_valid(p):
				p.hold_clip = was)
		if not sitting:
			var body: Node3D = p.get("body")
			if body:
				var hop := create_tween()
				for k in 2:
					hop.tween_property(p, "position:y", p.position.y + 0.18, 0.18).set_trans(Tween.TRANS_SINE)
					hop.tween_property(p, "position:y", p.position.y, 0.22).set_trans(Tween.TRANS_BOUNCE)
	for i in room.lights.size():
		var l := room.lights[i]
		var base: float = room.light_base[i] if i < room.light_base.size() else l.light_energy
		var lt := create_tween()
		lt.tween_property(l, "light_energy", base * 2.4, 0.15)
		lt.tween_property(l, "light_energy", base * 0.8, 0.25)
		lt.tween_property(l, "light_energy", base * 1.8, 0.2)
		lt.tween_property(l, "light_energy", base, 1.6).set_trans(Tween.TRANS_SINE)
	for m in room.neon_mats:
		var e := m.emission_energy_multiplier
		var nt := create_tween()
		for k in 3:
			nt.tween_property(m, "emission_energy_multiplier", e * 0.2, 0.08)
			nt.tween_property(m, "emission_energy_multiplier", e * 1.8, 0.12)
		nt.tween_property(m, "emission_energy_multiplier", e, 0.6)
	if _confetti:
		_confetti.restart()
		_confetti.emitting = true


func _build_confetti() -> void:
	_confetti = CPUParticles3D.new()
	_confetti.name = "Confetti"
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 140
	_confetti.lifetime = 4.5
	_confetti.explosiveness = 0.9
	_confetti.direction = Vector3(0, -1, 0)
	_confetti.spread = 75.0
	_confetti.initial_velocity_min = 1.5
	_confetti.initial_velocity_max = 3.5
	_confetti.gravity = Vector3(0, -1.2, 0)
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	_confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_confetti.emission_box_extents = Vector3(3.0, 0.2, 2.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.03)
	_confetti.mesh = quad
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.emission_enabled = true
	cm.emission = Color(0.4, 0.3, 0.2)
	_confetti.material_override = cm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.3, 0.5))
	grad.set_color(1, Color(0.3, 0.8, 1.0))
	grad.add_point(0.33, Color(1.0, 0.85, 0.2))
	grad.add_point(0.66, Color(0.5, 1.0, 0.4))
	_confetti.color_initial_ramp = grad
	_confetti.position = Vector3(-1.0, PubRoom.H - 0.5, -2.0)
	add_child(_confetti)
