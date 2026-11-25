extends ArcadeWorld
## YUE Courier, dived into: a plaza adrift in the Void, five QING pads on light pillars round a
## swirling rift. You run it on foot, the camera high behind you; the YUE parcel floats over its
## pad (a gold beam marks it), rides over your head once picked up, and the destination pad's
## pillar flares gold with the clock ring shrinking round it. Wisps are dark orbs in magenta halos
## that drift after you; the Hong pulse throws a ring of light. The 2D game (yue_courier.gd) rules it
## all; this stages it: 2D px → metres (y down the screen → +z, toward the camera).

const K := 0.11
const PILLAR_H := 7.0

var _pads: Array = []  # [base ring MeshInstance3D, pillar MeshInstance3D, label]
var _parcel: MeshInstance3D
var _parcel_beam: MeshInstance3D
var _clock_ring: MeshInstance3D
var _wisps: MultiMesh
var _wisp_halos: MultiMesh
var _pulse: MeshInstance3D
var _rift: Array = []
var _avatar: Node3D
var _pops: Array = []
var _last := Vector3.ZERO
var _yaw := 0.0


func controls_list() -> Array:
	return [["%s%s%s%s / arrows" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_back"), ControlsHelp.key_of("move_right")], "run (eight ways)"],
		[ControlsHelp.key_of("jump"), "Hong pulse: stun and throw back the wisps near you"]]


func controls_hint() -> String:
	return "%s%s%s%s or arrows run · %s Hong pulse" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_left"),
		ControlsHelp.key_of("move_back"), ControlsHelp.key_of("move_right"), ControlsHelp.key_of("jump")]


static func wf(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3((p.x - 160.0) * K, y, (p.y - 130.0) * K)


func _build() -> void:
	make_environment(Color(0.005, 0.003, 0.014), Color(0.04, 0.0, 0.07), 0.01, 1.15)
	make_camera(60.0)
	starfield(700, 220.0, 0x7E5C, 1.5)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 25, 0)
	key.light_energy = 0.8
	add_child(key)
	# The plaza: a dark disc ringed in the QING's colour, a faint grid.
	var disc := CylinderMesh.new()
	disc.top_radius = 19.0
	disc.bottom_radius = 19.0
	disc.height = 0.3
	disc.radial_segments = 64
	add_mesh(disc, mat(Color(0.025, 0.02, 0.045), 0.35, 0.5)).position.y = -0.15
	var edge := TorusMesh.new()
	edge.inner_radius = 18.7
	edge.outer_radius = 19.0
	edge.rings = 96
	edge.ring_segments = 4
	add_mesh(edge, neon_mat(accent, 2.2))
	var grid := pool_multimesh(box_mesh(Vector3(1, 1, 1)), neon_mat(accent, 0.35), 30)
	for i in 15:
		var o := -16.8 + i * 2.4
		grid.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.03, 0.01, 34.0)), Vector3(o, 0.01, 0)))
		grid.set_instance_transform(15 + i, Transform3D(Basis.from_scale(Vector3(34.0, 0.01, 0.03)), Vector3(0, 0.01, o)))
		grid.set_instance_color(i, Color.WHITE)
		grid.set_instance_color(15 + i, Color.WHITE)
	grid.visible_instance_count = 30
	# The rift: three tilted magenta rings turning over a black well.
	var well := CylinderMesh.new()
	well.top_radius = 1.4
	well.bottom_radius = 1.4
	well.height = 0.05
	add_mesh(well, mat(Color(0, 0, 0), 0.1)).position = wf(Vector2(160, 130), 0.03)
	for k in 3:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.8 + k * 0.45
		tm.outer_radius = 0.86 + k * 0.45
		tm.rings = 48
		tm.ring_segments = 4
		var m := add_mesh(tm, neon_mat(MAGENTA, 2.2 - k * 0.5))
		m.position = wf(Vector2(160, 130), 0.5 + k * 0.3)
		_rift.append(m)
	# The pads.
	var g = game
	var pads: Array = g.pads if not g.pads.is_empty() else g.pad_positions()
	for i in pads.size():
		var base := CylinderMesh.new()
		base.top_radius = 13.0 * K
		base.bottom_radius = 13.0 * K
		base.height = 0.12
		var b := add_mesh(base, neon_mat(ICE, 0.9))
		b.position = wf(pads[i], 0.06)
		var pil := CylinderMesh.new()
		pil.top_radius = 0.14
		pil.bottom_radius = 0.3
		pil.height = PILLAR_H
		pil.cap_top = false
		pil.cap_bottom = false
		var p := add_mesh(pil, neon_mat(ICE, 0.6, true, 0.55))
		p.position = wf(pads[i], PILLAR_H * 0.5)
		var l := label3d("Q%d" % (i + 1), 120, Color(ICE, 0.8), false)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = wf(pads[i], 2.4)
		_pads.append([b, p, l])
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 0.5, 0.5)
	_parcel = add_mesh(pm, neon_mat(GOLD, 2.8))
	var beam := CylinderMesh.new()
	beam.top_radius = 0.1
	beam.bottom_radius = 0.25
	beam.height = 12.0
	beam.cap_top = false
	beam.cap_bottom = false
	_parcel_beam = add_mesh(beam, neon_mat(GOLD, 0.9, true, 0.5))
	var cr := TorusMesh.new()
	cr.inner_radius = 17.0 * K
	cr.outer_radius = 17.0 * K + 0.08
	cr.rings = 48
	cr.ring_segments = 3
	_clock_ring = add_mesh(cr, neon_mat(GOLD, 2.0))
	var orb := SphereMesh.new()
	orb.radius = 0.36
	orb.height = 0.72
	orb.radial_segments = 12
	orb.rings = 6
	_wisps = pool_multimesh(orb, neon_mat(Color(0.25, 0.05, 0.3), 1.0), 8)
	var halo := QuadMesh.new()
	halo.size = Vector2(1.6, 1.6)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.vertex_color_use_as_albedo = true
	hm.albedo_texture = _dot_texture()
	_wisp_halos = pool_multimesh(halo, hm, 8)
	var pt := TorusMesh.new()
	pt.inner_radius = 0.95
	pt.outer_radius = 1.0
	pt.rings = 48
	pt.ring_segments = 3
	_pulse = add_mesh(pt, neon_mat(ICE, 3.0))
	_pulse.visible = false
	_avatar = make_avatar()
	for i in 6:
		var l := label3d("", 64, GOLD, false)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.006
		l.visible = false
		_pops.append(l)


func _sync(delta: float) -> void:
	var g = game
	if g.pads.is_empty():
		return
	for k in _rift.size():
		(_rift[k] as MeshInstance3D).rotation = Vector3(0.5 + k * 0.3, _t * (1.2 + k * 0.7), 0.2 * k)
	# Pads: the destination flares gold once you carry the parcel.
	for i in _pads.size():
		var hot: bool = g.carrying and i == g.dest
		var src: bool = not g.carrying and i == g.source
		var c := GOLD if hot else (ICE.lerp(GOLD, 0.35) if src else ICE)
		(_pads[i][0] as MeshInstance3D).material_override.set_shader_parameter("color", c)
		(_pads[i][0] as MeshInstance3D).material_override.set_shader_parameter("energy", 2.4 if hot else 0.9)
		(_pads[i][1] as MeshInstance3D).material_override.set_shader_parameter("color", c)
		(_pads[i][1] as MeshInstance3D).material_override.set_shader_parameter("energy", 1.6 if hot else 0.5)
		(_pads[i][2] as Label3D).modulate = Color(c, 0.9)
	# You.
	var p := wf(g.pos)
	var v := (p - _last) / maxf(delta, 0.001)
	_last = p
	if _avatar:
		_avatar.position = p
		if Vector2(v.x, v.z).length() > 0.3:
			_yaw = lerp_angle(_yaw, atan2(v.x, v.z), minf(1.0, delta * 12.0))
		_avatar.rotation.y = _yaw
		_avatar.update_movement(Vector3(v.x, 0, v.z), true, false)
		_avatar.visible = g.safe <= 0.0 or int(_t * 12.0) % 2 == 0
	# The parcel: on its pad, or over your head.
	var pp: Vector3 = p + Vector3(0, 2.4, 0) if g.carrying else wf(g.pads[g.source], 1.0 + 0.15 * sin(_t * 3.0))
	_parcel.position = pp
	_parcel.rotation = Vector3(_t * 1.5, _t * 2.0, 0)
	_parcel_beam.visible = not g.carrying
	_parcel_beam.position = wf(g.pads[g.source], 6.0)
	var goal := wf(g.goal(), 0.12)
	var left := clampf(g.clock / g.clock_full, 0.0, 1.0)
	_clock_ring.position = goal
	_clock_ring.scale = Vector3(0.6 + left * 0.8, 1.0, 0.6 + left * 0.8)
	_clock_ring.material_override.set_shader_parameter("color", MAGENTA if left < 0.3 else GOLD)
	# Wisps.
	var n: int = mini(g.wisps.size(), 8)
	for i in n:
		var w: Dictionary = g.wisps[i]
		var wp := wf(w["p"], 1.0 + 0.2 * sin(_t * 4.0 + i))
		var stun := float(w["stun"]) > 0.0
		_wisps.set_instance_transform(i, Transform3D(Basis(), wp))
		_wisps.set_instance_color(i, Color(0.4, 0.4, 0.5) if stun else Color.WHITE)
		_wisp_halos.set_instance_transform(i, Transform3D(Basis(), wp))
		_wisp_halos.set_instance_color(i, Color(ICE, 0.5) if stun else Color(MAGENTA, 0.9))
	_wisps.visible_instance_count = n
	_wisp_halos.visible_instance_count = n
	_pulse.visible = g.pulse_t >= 0.0
	if _pulse.visible:
		var r: float = g.PULSE_R * K * clampf(g.pulse_t / 0.25, 0.05, 1.0)
		_pulse.position = p + Vector3(0, 0.3, 0)
		_pulse.scale = Vector3(r, 1.0, r)
		_pulse.material_override.set_shader_parameter("energy", 3.0 * (1.0 - g.pulse_t / 0.45))
	for i in _pops.size():
		var l: Label3D = _pops[i]
		l.visible = i < g.popups.size()
		if l.visible:
			var pd: Dictionary = g.popups[i]
			l.text = String(pd["s"])
			l.modulate = Color(pd["c"], clampf(float(pd["life"]) / 0.4, 0.0, 1.0))
			l.position = wf(pd["p"], 2.6 + (0.8 - float(pd["life"])) * 1.5)
	# The camera: high behind you, leaning toward the goal.
	var focus := p.lerp(goal, 0.2)
	var want := focus + Vector3(0, 8.5, 8.0)
	camera.position = camera.position.lerp(want, minf(1.0, delta * 4.0)) if _t > 0.1 else want
	camera.look_at(focus + Vector3(0, 0.5, -1.0), Vector3.UP)


func hud() -> Dictionary:
	var g = game
	var left := clampf(g.clock / g.clock_full, 0.0, 1.0)
	return {"stats": PackedStringArray(["LEVEL %d" % g.level, "CHAIN x%d" % clampi(g.chain, 1, 8), "DELIVERED %d" % g.delivered,
			"%s → Q%d" % ["CARRYING YUE" if g.carrying else "PICK UP AT Q%d" % (g.source + 1), g.dest + 1]]),
		"bars": [["TIME %.1f s" % maxf(0.0, g.clock), left, MAGENTA if left < 0.3 else GOLD],
			["HONG PULSE" if g.charge >= 1.0 else "RECHARGING", g.charge, GOLD if g.charge >= 1.0 else ICE]],
		"flash": g.flash, "flash_color": g.flash_c}
