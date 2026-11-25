extends ArcadeWorld
## Qing Orbit, dived into: the QING hangs in the Void as a glowing world with four neon orbits round
## it, and you ride a hover disc along them, the camera close behind. Ⓐ spin on the rings in gold, the
## LAU sigil in magenta; the Void's rifts are black cores in magenta halos sliding at you. Left drops
## toward the QING, right climbs outward, Space is the Hong dash (gold streak, wide lens). The 2D game
## (qing_orbit.gd) rules every pickup and hit; this stages it: 2D ring radius → metres, angle as is.

const K := 0.13  ## metres per 2D px of radius
const POOL := 28

var _rings: Array = []
var _coins: MultiMesh
var _rifts: MultiMesh
var _halos: MultiMesh
var _laus: MultiMesh
var _trail: MultiMesh
var _rider: Node3D
var _avatar: Node3D
var _disc: MeshInstance3D
var _qing: Node3D
var _pops: Array = []
var _fov := 70.0


func controls_list() -> Array:
	return [["%s / ←" % ControlsHelp.key_of("move_left"), "drop a ring, toward the QING"],
		["%s / →" % ControlsHelp.key_of("move_right"), "climb a ring, outward"],
		["%s %s / ↑ ↓" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_back")], "throttle / brake"],
		[ControlsHelp.key_of("jump"), "Hong dash: a burst, untouchable (recharges)"]]


func controls_hint() -> String:
	return "%s/%s change rings · %s/%s throttle, brake · %s Hong dash" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right"),
		ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_back"), ControlsHelp.key_of("jump")]


## Pure: a ring point in metres (counter-clockwise seen from above; the QING on your left).
static func world_at(r_px: float, a: float, y: float = 0.0) -> Vector3:
	return Vector3(cos(a) * r_px * K, y, -sin(a) * r_px * K)


func _build() -> void:
	make_environment(Color(0.004, 0.003, 0.012), Color(0.03, 0.0, 0.05), 0.004, 1.2)
	make_camera(70.0)
	starfield(900, 260.0, 0x0EB1, 1.8)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 0.9
	add_child(key)
	# The QING: a lit world with an equatorial band and its name.
	_qing = Node3D.new()
	add_child(_qing)
	var sph := SphereMesh.new()
	sph.radius = 2.6
	sph.height = 5.2
	var core := StandardMaterial3D.new()
	core.albedo_color = accent.darkened(0.5)
	core.emission_enabled = true
	core.emission = accent
	core.emission_energy_multiplier = 0.8
	core.roughness = 0.4
	add_mesh(sph, core, _qing).position.y = 0.6
	var band := TorusMesh.new()
	band.inner_radius = 3.0
	band.outer_radius = 3.15
	band.rings = 64
	add_mesh(band, neon_mat(accent.lerp(Color.WHITE, 0.3), 2.4), _qing).position.y = 0.6
	var nm := label3d("QING · " + String(ctx.get("territory", {}).get("name", "")).to_upper(), 72, Color(accent, 0.9), false)
	nm.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nm.pixel_size = 0.003
	nm.position = Vector3(0, 3.5, 0)
	var omni := OmniLight3D.new()
	omni.light_color = accent
	omni.light_energy = 2.0
	omni.omni_range = 18.0
	omni.position.y = 0.6
	add_child(omni)
	for r in qing_rings():
		var tm := TorusMesh.new()
		tm.inner_radius = r * K - 0.04
		tm.outer_radius = r * K + 0.04
		tm.rings = 128
		tm.ring_segments = 4
		_rings.append(add_mesh(tm, neon_mat(ICE, 0.8)))
	var coin := CylinderMesh.new()
	coin.top_radius = 0.35
	coin.bottom_radius = 0.35
	coin.height = 0.08
	coin.radial_segments = 16
	_coins = pool_multimesh(coin, neon_mat(GOLD, 2.6), POOL)
	var core_m := SphereMesh.new()
	core_m.radius = 0.42
	core_m.height = 0.84
	core_m.radial_segments = 12
	core_m.rings = 6
	_rifts = pool_multimesh(core_m, mat(Color(0.0, 0.0, 0.0), 0.2, 0.0), POOL)
	var halo := QuadMesh.new()
	halo.size = Vector2(1.9, 1.9)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_texture = _dot_texture()
	hm.albedo_color = Color(MAGENTA, 1.0) * 2.0
	_halos = pool_multimesh(halo, hm, POOL)
	var oct := SphereMesh.new()
	oct.radius = 0.4
	oct.height = 0.8
	oct.radial_segments = 4
	oct.rings = 2
	_laus = pool_multimesh(oct, neon_mat(MAGENTA, 3.0), 6)
	_trail = pool_multimesh(box_mesh(Vector3(0.5, 0.05, 0.5)), neon_mat(ICE, 1.6, true, 0.6), 10)
	_rider = Node3D.new()
	add_child(_rider)
	var dm := CylinderMesh.new()
	dm.top_radius = 0.55
	dm.bottom_radius = 0.4
	dm.height = 0.12
	_disc = add_mesh(dm, neon_mat(ICE, 2.0), _rider)
	_disc.position.y = 0.06
	_avatar = make_avatar()
	if _avatar:
		remove_child(_avatar)
		_rider.add_child(_avatar)
		_avatar.position.y = 0.12
	for i in 6:
		var l := label3d("", 64, GOLD, false)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.006
		l.visible = false
		_pops.append(l)


static func qing_rings() -> Array:
	return [34.0, 56.0, 78.0, 100.0]


func _sync(delta: float) -> void:
	var g = game
	var me: int = g.hit_ring()
	for i in _rings.size():
		var m: MeshInstance3D = _rings[i]
		m.material_override.set_shader_parameter("energy", 2.2 if i == me else 0.7)
	_qing.rotation.y += delta * 0.2
	var nc := 0
	var nr := 0
	var nl := 0
	for th in g.things:
		var p := world_at(float(g.RINGS[int(th["ring"])]), float(th["a"]), 0.6)
		match int(th["kind"]):
			0:
				if nc < POOL:
					_coins.set_instance_transform(nc, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, _t * 3.0 + nc), p))
					_coins.set_instance_color(nc, Color.WHITE)
					nc += 1
			1:
				if nr < POOL:
					var pulse := 1.0 + 0.15 * sin(_t * 9.0 + nr)
					_rifts.set_instance_transform(nr, Transform3D(Basis.from_scale(Vector3.ONE * pulse), p))
					_halos.set_instance_transform(nr, Transform3D(Basis.from_scale(Vector3.ONE * pulse), p))
					_halos.set_instance_color(nr, Color.WHITE)
					nr += 1
			2:
				if nl < 6:
					_laus.set_instance_transform(nl, Transform3D(Basis(Vector3.UP, _t * 2.0), p))
					_laus.set_instance_color(nl, Color.WHITE)
					nl += 1
	_coins.visible_instance_count = nc
	_rifts.visible_instance_count = nr
	_halos.visible_instance_count = nr
	_laus.visible_instance_count = nl
	# You.
	var r: float = g.radius()
	var a: float = g.angle
	var pos := world_at(r, a)
	var fwd := Vector3(-sin(a), 0, -cos(a))
	_rider.position = pos
	_rider.rotation.y = atan2(fwd.x, fwd.z)
	var dashing: bool = g.dash > 0.0
	_disc.material_override.set_shader_parameter("color", GOLD if dashing else ICE)
	_rider.visible = g.safe <= 0.0 or int(_t * 12.0) % 2 == 0
	if _avatar:
		_avatar.update_movement(Vector3.ZERO, true, false)
	# The trail (2D trail points → metres).
	var n: int = mini(g.trail.size(), 10)
	for i in n:
		var tp: Vector2 = g.trail[i] - g.CENTER
		_trail.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * (0.4 + i * 0.07)), Vector3(tp.x * K, 0.08, tp.y * K)))
		var c: Color = GOLD if dashing else ICE
		_trail.set_instance_color(i, Color(c, i / 10.0))
	_trail.visible_instance_count = n
	for i in _pops.size():
		var l: Label3D = _pops[i]
		l.visible = i < g.popups.size()
		if l.visible:
			var pp: Dictionary = g.popups[i]
			var pv: Vector2 = (pp["p"] as Vector2) - g.CENTER
			l.text = String(pp["s"])
			l.modulate = Color(pp["c"], clampf(float(pp["life"]) / 0.4, 0.0, 1.0))
			l.position = Vector3(pv.x * K, 1.8 + (0.8 - float(pp["life"])) * 1.5, pv.y * K)
	# The chase camera: behind, above, a little outside the ring; a wider lens in a dash.
	var out := Vector3(cos(a), 0, -sin(a))
	var want_cam := pos - fwd * 4.6 + out * 1.4 + Vector3.UP * 2.3
	camera.position = camera.position.lerp(want_cam, minf(1.0, delta * 6.0)) if _t > 0.1 else want_cam
	camera.look_at(pos + fwd * 5.0 - out * 0.8 + Vector3.UP * 0.6, Vector3.UP)
	_fov = lerpf(_fov, 86.0 if dashing else 70.0, minf(1.0, delta * 5.0))
	camera.fov = _fov


func hud() -> Dictionary:
	var g = game
	var out := {"stats": PackedStringArray(["ORBIT %d" % g.level, "x%d · Ⓐ IN A ROW %d" % [g.mult, g.streak], "RING %d" % (g.ring + 1)]),
		"flash": g.flash, "flash_color": g.flash_c}
	out["bars"] = [["HONG DASH" if g.charge >= 1.0 else "RECHARGING", g.charge, GOLD if g.charge >= 1.0 else ICE]]
	return out
