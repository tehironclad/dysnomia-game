class_name PubLife
extends Node3D
## The people and the moments: a bartender working the back bar, 4–6 patrons
## (AmbientNPC teddy-astronauts) and the two set pieces the AttractionDirector triggers —
## a drink poured and slid down the counter, and the room cheering a round.

const MAX_GLASSES := 6

# drink_id -> [liquid colour, glass kind]
const DRINK_LOOKS := {
	"pi_shot": [Color(1.0, 0.72, 0.18), "shot"],
	"rho_rocks": [Color(0.95, 0.45, 0.1), "rocks"],
	"generator_lager": [Color(1.0, 0.68, 0.12), "pint"],
	"alpha_sour": [Color(0.55, 1.0, 0.3), "coupe"],
	"beta_blocker": [Color(0.25, 0.55, 1.0), "highball"],
	"upsilon_fizz": [Color(1.0, 0.3, 0.85), "fizz"],
	"house_round": [Color(1.0, 0.68, 0.12), "pint"],
}

var bartender: Node3D
var patrons: Array[Node3D] = []

var _L: PubLayout
var _interior: PubInterior
var _rng := RandomNumberGenerator.new()
var _bartender_loop: Array = []
var _glasses: Array[Node3D] = []
var _serve_count := 0
var _confetti: CPUParticles3D
var _neon_mats: Array[StandardMaterial3D] = []
var _neon_base: Array[float] = []


func setup(layout: PubLayout, interior: PubInterior, shell_neon: Array[MeshInstance3D], seed_value: int) -> void:
	_L = layout
	_interior = interior
	_rng.seed = seed_value
	name = "PubLife"
	var fy := PubLayout.FY
	for n in shell_neon + interior.neon_nodes:
		var m := n.material_override as StandardMaterial3D
		if m and not (m in _neon_mats):
			_neon_mats.append(m)
			_neon_base.append(m.emission_energy_multiplier)

	# Bartender works a loop behind the counter: taps → register → shelves
	var wz := _L.walkway_z
	_bartender_loop = [Vector3(_L.tap_x, fy, wz), Vector3(_L.bar_x1 - 1.1, fy, wz),
		Vector3(_L.bar_cx - 0.2, fy, wz - 0.15), Vector3(_L.bar_x0 + 1.3, fy, wz)]
	bartender = _spawn(_rng.randi(), _bartender_loop, Vector3.ZERO)
	bartender.name = "Bartender"
	bartender.set("pause_range", Vector2(2.5, 7.0))

	var count: int = _L.p["patron_count"]
	# 1. A regular doing the rounds: bar → high-top → game tables → jukebox → back
	var g_front: Vector3 = _L.game_tables[mini(2, _L.game_tables.size() - 1)] + Vector3(0, 0, 1.0)
	var h0: Vector3 = _L.hightops[0]
	var h1: Vector3 = _L.hightops[1]
	var loop := [Vector3(_L.order_x, fy, _L.counter_front + 0.65), h0 + Vector3(0.75, 0, 0.55),
		g_front, _L.jukebox_pos + Vector3(-0.2, 0, -1.25), h1 + Vector3(-0.8, 0, 0.0)]
	_add_patron(_spawn(_rng.randi(), loop, Vector3.ZERO))
	# 2–3. Two friends talking over the first high-top
	_add_patron(_spawn(_rng.randi(), [], Vector3(1, 0, 0), h0 + Vector3(-0.62, 0, 0.05)))
	_add_patron(_spawn(_rng.randi(), [], Vector3(-1, 0, 0.15), h0 + Vector3(0.62, 0, -0.05)))
	# 4. Leaning on the bar
	if _L.occupied_stools.size() > 0:
		_add_patron(_spawn(_rng.randi(), [], Vector3(0.15, 0, -1), _L.stools[_L.occupied_stools[0]]))
	else:
		_add_patron(_spawn(_rng.randi(), [], Vector3(0, 0, -1), Vector3(_L.order_x - 1.6, fy, _L.counter_front + 0.4)))
	# 5. Darts
	if count >= 5:
		_add_patron(_spawn(_rng.randi(), [], Vector3(-1, 0, 0), _L.dart_throw + Vector3(0.1, 0, 0.1)))
	# 6. Second at the bar, half-turned to the room
	if count >= 6 and _L.occupied_stools.size() > 1:
		_add_patron(_spawn(_rng.randi(), [], Vector3(0.6, 0, -0.8), _L.stools[_L.occupied_stools[1]]))

	# Everyone is indoors under the roof: their ~90 meshes each needn't hit the sun's shadow pass
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Confetti cannon in the rafters for rounds on the house (low-g: it drifts)
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
	_confetti.emission_box_extents = Vector3(2.5, 0.2, 1.5)
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
	_confetti.position = Vector3(_L.order_x - 1.0, _L.eave - 0.4, _L.counter_front + 2.0)
	add_child(_confetti)


func _spawn(npc_seed: int, points: Array, facing: Vector3, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := AmbientNPC.new()
	add_child(n)
	if points.is_empty():
		n.position = pos
	n.setup(npc_seed, points, Vector3.ZERO)
	if points.is_empty() and facing.length() > 0.01:
		# AmbientNPC steers with -Z forward: point -Z along `facing`
		n.rotation.y = atan2(-facing.x, -facing.z)
	return n


func _add_patron(n: Node3D) -> void:
	patrons.append(n)


func set_active(on: bool) -> void:
	## Hide + pause everyone when the player is far away (60 meshes per NPC).
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


# ─── Drink service ─────────────────────────────────────────────────────────

func play_drink_served(drink_id: String) -> void:
	var look: Array = DRINK_LOOKS.get(drink_id, [Color(1.0, 0.6, 0.2), "rocks"])
	_serve_count += 1
	var fy := PubLayout.FY
	var top := fy + PubLayout.COUNTER_H
	var start := Vector3(_L.tap_x + 0.1, top, _L.counter_z - 0.1)
	var rounds := 3 if drink_id == "house_round" else 1

	# Bartender steps to the taps for the pour, then goes back to the loop
	_send_bartender(Vector3(_L.tap_x, fy, _L.walkway_z), 6.0)

	# Tap handle pull + back-bar light pulse
	if not _interior.tap_handles.is_empty():
		var h: MeshInstance3D = _interior.tap_handles[_serve_count % _interior.tap_handles.size()]
		var tw := create_tween()
		tw.tween_property(h, "rotation_degrees:x", 28.0, 0.25).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(0.7)
		tw.tween_property(h, "rotation_degrees:x", 0.0, 0.3)
	if _interior.bar_flash:
		var base := _interior.bar_flash.light_energy
		var lt := create_tween()
		lt.tween_property(_interior.bar_flash, "light_energy", base * 2.5, 0.2)
		lt.tween_property(_interior.bar_flash, "light_energy", base, 1.2)

	for r in rounds:
		var g := _make_glass(look[0], look[1])
		g.position = start + Vector3(float(r) * 0.14, 0, 0)
		g.scale = Vector3.ONE * 0.01
		add_child(g)
		_glasses.append(g)
		var liquid: Node3D = g.get_node("Liquid")
		liquid.scale = Vector3(1, 0.05, 1)
		# Successive orders land side by side instead of stacking in one spot
		var slot := (_serve_count + r) % 4
		var dest := Vector3(_L.order_x - 0.35 + float(slot) * 0.18, top, _L.counter_front - 0.14)
		var tw := create_tween()
		tw.tween_interval(float(r) * 0.35)
		tw.tween_property(g, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(liquid, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.25)
		# The slide: fast off the hand, easing to a stop right at the customer
		tw.tween_property(g, "position", dest, 1.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(g, "rotation:y", _rng.randf_range(-0.8, 0.8), 1.1)
		tw.tween_property(g, "rotation:z", 0.06, 0.08)
		tw.tween_property(g, "rotation:z", 0.0, 0.15).set_trans(Tween.TRANS_ELASTIC)
		# Left on the bar for a while, then cleared away
		tw.tween_interval(35.0)
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
	var glass := PubKit.glass(Color(0.9, 0.95, 1.0, 0.22))
	var liquid_mat := PubKit.glass(Color(col.r, col.g, col.b, 0.85), col, 2.2)
	var dims := {"shot": [0.028, 0.024, 0.07], "rocks": [0.045, 0.042, 0.09], "pint": [0.045, 0.036, 0.16],
		"coupe": [0.05, 0.03, 0.08], "highball": [0.036, 0.034, 0.17], "fizz": [0.036, 0.034, 0.17]}
	var dd: Array = dims.get(kind, dims["rocks"])
	var rt: float = dd[0]
	var rb: float = dd[1]
	var hh: float = dd[2]
	PubKit.mesh_instance(PubKit.cyl(rt, rb, hh, 14), Vector3(0, hh * 0.5, 0), glass, g)
	var liquid := Node3D.new()
	liquid.name = "Liquid"
	g.add_child(liquid)
	var lh := hh * 0.78
	PubKit.mesh_instance(PubKit.cyl(rt * 0.9, rb * 0.88, lh, 14), Vector3(0, lh * 0.5 + 0.004, 0), liquid_mat, liquid)
	match kind:
		"pint":
			PubKit.mesh_instance(PubKit.cyl(rt * 0.95, rt * 0.9, 0.025, 14), Vector3(0, lh + 0.016, 0),
				PubKit.flat(Color(1.0, 0.97, 0.9), 0.8), liquid)
		"rocks":
			for k in 2:
				var ice := PubKit.mesh_instance(_cube(0.028), Vector3(-0.012 + float(k) * 0.022, lh - 0.008, 0.005 * float(k)),
					PubKit.glass(Color(0.9, 0.95, 1.0, 0.55), Color(0.8, 0.9, 1.0), 0.4), liquid)
				ice.rotation_degrees = Vector3(20.0 * float(k), 35.0, 10.0)
		"coupe":
			PubKit.mesh_instance(PubKit.cyl(0.01, 0.01, 0.012, 8), Vector3(0.03, hh + 0.004, 0), PubKit.neon(Color(0.6, 1.0, 0.2), 1.5), liquid)
		"fizz":
			for k in 5:
				PubKit.mesh_instance(_bubble(), Vector3(_rng.randf_range(-0.02, 0.02), 0.02 + float(k) * 0.025, _rng.randf_range(-0.02, 0.02)),
					PubKit.neon(Color(1.0, 0.85, 1.0), 3.0), liquid)
	return g


func _send_bartender(spot: Vector3, hold: float) -> void:
	if not is_instance_valid(bartender):
		return
	# AmbientNPC walks between its points; park it at the taps for the pour.
	bartender.set("_points", [spot, spot + Vector3(0.3, 0, 0)])
	bartender.set("_target_idx", 0)
	bartender.set("_pause", 0.0)
	var t := get_tree().create_timer(hold)
	t.timeout.connect(func():
		if is_instance_valid(bartender):
			bartender.set("_points", _bartender_loop.duplicate())
			bartender.set("_target_idx", 1))


# ─── Round for the house ───────────────────────────────────────────────────

func play_house_cheer(lights: Array[OmniLight3D], light_base: Array[float]) -> void:
	# Patrons hop and turn toward the bar
	var bar_focus := Vector3(_L.order_x, PubLayout.FY, _L.counter_z)
	for i in patrons.size():
		var n := patrons[i]
		if not is_instance_valid(n):
			continue
		var model: Node3D = n.get_node_or_null("Model")
		if model == null:
			continue
		var tw := create_tween()
		tw.tween_interval(float(i) * 0.08)
		for k in 3:
			tw.tween_property(model, "position:y", 0.28, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(model, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		if n.get("_points") is Array and (n.get("_points") as Array).size() < 2:
			var to := bar_focus - n.position
			var want := atan2(-to.x, -to.z)
			var rt := create_tween()
			rt.tween_property(n, "rotation:y", want, 0.5)
			rt.tween_interval(4.0)
			rt.tween_property(n, "rotation:y", n.rotation.y, 0.8)
	# Bartender hops too
	if is_instance_valid(bartender):
		var bm: Node3D = bartender.get_node_or_null("Model")
		if bm:
			var bt := create_tween()
			bt.tween_property(bm, "position:y", 0.22, 0.2)
			bt.tween_property(bm, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE)
	# Lights flare warm then settle
	for i in lights.size():
		var l := lights[i]
		var base: float = light_base[i] if i < light_base.size() else l.light_energy
		var lt := create_tween()
		lt.tween_property(l, "light_energy", base * 2.6, 0.15)
		lt.tween_property(l, "light_energy", base * 0.8, 0.25)
		lt.tween_property(l, "light_energy", base * 2.0, 0.2)
		lt.tween_property(l, "light_energy", base, 1.6).set_trans(Tween.TRANS_SINE)
	# Neon blinks
	for j in _neon_mats.size():
		var m := _neon_mats[j]
		var e := _neon_base[j]
		var nt := create_tween()
		for k in 3:
			nt.tween_property(m, "emission_energy_multiplier", e * 0.2, 0.08)
			nt.tween_property(m, "emission_energy_multiplier", e * 1.8, 0.12)
		nt.tween_property(m, "emission_energy_multiplier", e, 0.6)
	if _confetti:
		_confetti.restart()
		_confetti.emitting = true


func _cube(s: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE * s
	return b


func _bubble() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.004
	s.height = 0.008
	s.radial_segments = 6
	s.rings = 3
	return s
