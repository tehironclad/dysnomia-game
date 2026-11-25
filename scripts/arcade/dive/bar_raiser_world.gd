extends ArcadeWorld
## Bar Raiser, dived into: you climb a Hypobar column out of the QING's plaza. Holding fire pours a
## glowing magenta segment under your feet and lifts you with it; the gold Epibar ring hangs above.
## Let go on the ring and the segment locks (gilded if PERFECT) and you stand higher; over or short,
## the pour spills, the top segment breaks off and you drop. The camera climbs with you.
## The 2D game (bar_raiser.gd) judges every pour; this stages its state (2D px → 0.05 m).

const S := 0.05  ## metres per 2D px
const COL := 3.0  ## the column's width (60 px)
const POOL := 64

const GLASS_SHADER := """shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
instance uniform vec3 size_m = vec3(3.0, 1.0, 3.0);
instance uniform vec4 tint : source_color = vec4(0.5, 0.9, 1.0, 1.0);
instance uniform float glow = 1.0;
varying vec3 pm;
void vertex() {
	pm = VERTEX * size_m;
}
void fragment() {
	vec3 e = size_m * 0.5 - abs(pm);
	float m1 = min(e.x, min(e.y, e.z));
	float m3 = max(e.x, max(e.y, e.z));
	float m2 = e.x + e.y + e.z - m1 - m3;
	float edge = smoothstep(0.09, 0.02, m2);
	float band = smoothstep(0.025, 0.0, abs(fract(pm.y / 0.5 + 0.5) - 0.5) * 0.5) * 0.25;
	ALBEDO = tint.rgb * (0.22 + band + edge * 2.6) * glow;
	ALPHA = clamp(0.38 + edge * 0.62, 0.0, 1.0);
}
"""

var _glass: ShaderMaterial
var _segs: Array = []
var _pour: MeshInstance3D
var _debris: Array = []
var _ring: MeshInstance3D
var _band_good: MeshInstance3D
var _band_perfect: MeshInstance3D
var _ring_label: Label3D
var _msg: Label3D
var _avatar: Node3D
var _av_y := 0.0
var _av_vy := 0.0
var _ticks: MultiMesh
var _nums: Array = []
var _focus := 2.0


func controls_list() -> Array:
	return [["hold %s" % ControlsHelp.key_of("jump"), "pour and rise"], ["let go", "on the gold ring"]]


func controls_hint() -> String:
	return "hold %s to pour and rise · let go on the gold ring" % ControlsHelp.key_of("jump")


func _build() -> void:
	make_environment(Color(0.008, 0.008, 0.02), Color(0.03, 0.02, 0.06), 0.006, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.01, 0.01, 0.035)
	sm.sky_horizon_color = Color(0.09, 0.04, 0.16)
	sm.ground_bottom_color = Color(0.0, 0.0, 0.0)
	sm.ground_horizon_color = Color(0.06, 0.03, 0.1)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	make_camera(55.0)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 0.6
	add_child(key)
	starfield(500, 200.0, 0xBA2, 1.5)
	var sh := Shader.new()
	sh.code = GLASS_SHADER
	_glass = ShaderMaterial.new()
	_glass.shader = sh
	_glass.render_priority = 0
	_build_plaza()
	_build_pylons()
	for i in POOL:
		var m := add_mesh(BoxMesh.new(), _glass)
		m.visible = false
		_segs.append(m)
	_pour = add_mesh(BoxMesh.new(), _glass)
	_pour.set_instance_shader_parameter("tint", MAGENTA)
	_pour.set_instance_shader_parameter("glow", 1.5)
	for i in 24:
		var d := add_mesh(BoxMesh.new(), _glass)
		d.visible = false
		_debris.append(d)
	var tm := TorusMesh.new()
	tm.inner_radius = COL * 0.5 + 0.5
	tm.outer_radius = COL * 0.5 + 0.75
	tm.rings = 64
	_ring = add_mesh(tm, neon_mat(GOLD, 3.2))
	var band := CylinderMesh.new()
	band.top_radius = COL * 0.5 + 0.62
	band.bottom_radius = COL * 0.5 + 0.62
	band.height = 1.0
	band.cap_top = false
	band.cap_bottom = false
	_band_good = add_mesh(band, neon_mat(GOLD, 0.6, true, 0.35))
	_band_perfect = add_mesh(band, neon_mat(GOLD, 1.4, true, 0.6))
	_ring_label = label3d("EPIBAR", 48, GOLD)
	_ring_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_msg = label3d("", 120, GOLD, false)
	_msg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_msg.pixel_size = 0.0065
	_ticks = pool_multimesh(box_mesh(Vector3(0.3, 0.03, 0.03)), neon_mat(ICE, 1.6), 60)
	for i in 10:
		var l := label3d("", 44, Color(ICE, 0.6))
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_nums.append(l)
	_avatar = make_avatar()


func _build_plaza() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 16.0
	disc.bottom_radius = 16.0
	disc.height = 0.3
	disc.radial_segments = 64
	var floor_mat := mat(Color(0.03, 0.03, 0.05), 0.35, 0.6)
	var f := add_mesh(disc, floor_mat)
	f.position.y = -0.15
	var tm := TorusMesh.new()
	tm.inner_radius = 15.7
	tm.outer_radius = 16.0
	tm.rings = 96
	tm.ring_segments = 4
	add_mesh(tm, neon_mat(accent, 2.4))
	for r in [4.0, 8.0, 12.0]:
		var t2 := TorusMesh.new()
		t2.inner_radius = r - 0.03
		t2.outer_radius = r
		t2.rings = 64
		t2.ring_segments = 3
		var ring := add_mesh(t2, neon_mat(accent, 0.9))
		ring.position.y = 0.01
	for i in 12:
		var spoke := add_mesh(box_mesh(Vector3(0.05, 0.02, 13.0)), neon_mat(accent, 0.6))
		spoke.rotation.y = TAU * i / 12.0
		spoke.position = Vector3(sin(spoke.rotation.y), 0, cos(spoke.rotation.y)) * 9.0
		spoke.position.y = 0.01
	var base := add_mesh(box_mesh(Vector3(COL + 0.6, 0.2, COL + 0.6)), neon_mat(ICE, 1.2))
	base.position.y = 0.1
	var q := label3d("QING", 160, Color(accent, 0.7), false)
	q.rotation_degrees.x = -90.0
	q.position = Vector3(0, 0.03, 5.0)
	var name_l := label3d(String(ctx.get("territory", {}).get("name", "")).to_upper(), 64, Color(accent, 0.5))
	name_l.rotation_degrees.x = -90.0
	name_l.position = Vector3(0, 0.03, 6.6)


## Far, faint light pillars around the plaza (decoration).
func _build_pylons() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 0x9170
	for i in 28:
		var h := r.randf_range(14.0, 60.0)
		var a := TAU * i / 28.0 + r.randf_range(-0.05, 0.05)
		var p := add_mesh(box_mesh(Vector3(0.25, h, 0.25)), neon_mat(ICE if i % 3 else MAGENTA, 0.9))
		p.position = Vector3(sin(a) * 55.0, h * 0.5, cos(a) * 55.0)


func _sync(delta: float) -> void:
	var g = game
	# The column.
	var base := 0.0
	var i := 0
	for s in g.segments:
		var h: float = s.h * S
		if i >= _segs.size():
			_segs.append(add_mesh(BoxMesh.new(), _glass))
		var m: MeshInstance3D = _segs[i]
		m.visible = true
		m.scale = Vector3(COL, h, COL)
		m.position = Vector3(0, base + h * 0.5, 0)
		m.set_instance_shader_parameter("size_m", Vector3(COL, h, COL))
		m.set_instance_shader_parameter("tint", GOLD if s.perfect else ICE)
		m.set_instance_shader_parameter("glow", 1.0)
		base += h
		i += 1
	for j in range(i, _segs.size()):
		_segs[j].visible = false
	var top: float = g.height * S
	# The pour.
	var pouring: bool = g.state == 1 or (g.state == 0 and g.grow > 0.0)
	_pour.visible = pouring and g.grow > 0.0
	var grow: float = g.grow * S if pouring else 0.0
	if _pour.visible:
		_pour.scale = Vector3(COL - 0.2, grow, COL - 0.2)
		_pour.position = Vector3(0, top + grow * 0.5, 0)
		_pour.set_instance_shader_parameter("size_m", Vector3(COL - 0.2, grow, COL - 0.2))
	# The Epibar ring and its bands.
	var aiming: bool = g.state != 2
	_ring.visible = aiming
	_band_good.visible = aiming
	_band_perfect.visible = aiming
	_ring_label.visible = aiming
	var mark: float = (g.height + g.target()) * S
	if aiming:
		_ring.position = Vector3(0, mark, 0)
		_ring.rotation.y += delta * 0.8
		var c := GOLD
		if g.state == 0:
			var left := clampf(1.0 - g.state_t / g.deadline, 0.0, 1.0)
			c = MAGENTA.lerp(GOLD, smoothstep(0.0, 0.6, left))
		_ring.material_override.set_shader_parameter("color", c)
		_band_good.position = Vector3(0, mark, 0)
		_band_good.scale = Vector3(1, maxf(0.01, g.good_tol * 2.0 * S), 1)
		_band_perfect.position = Vector3(0, mark, 0)
		_band_perfect.scale = Vector3(1, maxf(0.01, g.perfect_tol * 2.0 * S), 1)
		_ring_label.position = Vector3(COL * 0.5 + 1.6, mark + 0.35, 0.6)
	_msg.visible = g.state == 2 and g.msg != ""
	if _msg.visible:
		_msg.text = g.msg
		_msg.modulate = g.msg_c
		_msg.position = Vector3(0, top + 2.6 + g.state_t * 0.8, 0)
	# Debris: 2D screen rectangles back into metres.
	for j in _debris.size():
		var dm: MeshInstance3D = _debris[j]
		if j >= g.debris.size():
			dm.visible = false
			continue
		var d: Dictionary = g.debris[j]
		var w: float = d.w * S
		var hh: float = maxf(0.05, d.h * S)
		dm.visible = true
		dm.scale = Vector3(w, hh, COL * 0.5)
		dm.position = Vector3((d.p.x + d.w * 0.5 - g.COL_X) * S, (g.GROUND_Y + g.cam - d.p.y - d.h * 0.5) * S, ((j % 4) - 1.5) * 0.35)
		dm.rotation = Vector3(d.life * 1.7 + j, 0, (1.2 - d.life) * (2.0 if j % 2 else -2.0))
		dm.set_instance_shader_parameter("size_m", Vector3(w, hh, COL * 0.5))
		dm.set_instance_shader_parameter("tint", Color(d.c, 1.0))
		dm.set_instance_shader_parameter("glow", clampf(d.life, 0.0, 1.0))
	# You, on top of whatever is under your feet.
	var floor_y := top + grow
	if _avatar:
		if _av_y > floor_y + 0.02:
			_av_vy -= 22.0 * delta
			_av_y = maxf(floor_y, _av_y + _av_vy * delta)
		else:
			_av_y = floor_y
			_av_vy = 0.0
		var on_floor := _av_y <= floor_y + 0.02
		_avatar.position = Vector3(0.4, _av_y, 0.5)
		_avatar.rotation.y = 0.5
		_avatar.update_movement(Vector3(0, _av_vy, 0), on_floor, false)
	# The ruler: a tick every 10 px, a number every 50.
	var lo := floorf((_focus / S - 120.0) / 10.0) * 10.0
	var n := 0
	var k := 0
	for t in 60:
		var hpx := lo + t * 10.0
		if hpx < 0.0:
			continue
		var major := int(hpx) % 50 == 0
		_ticks.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(2.0 if major else 1.0, 1, 1)), Vector3(-COL * 0.5 - 0.6, hpx * S, -COL * 0.5 - 0.2)))
		_ticks.set_instance_color(n, Color(1, 1, 1, 1.0 if major else 0.45))
		n += 1
		if major and k < _nums.size():
			_nums[k].visible = true
			_nums[k].text = str(int(hpx))
			_nums[k].position = Vector3(-COL * 0.5 - 1.3, hpx * S, -COL * 0.5 - 0.2)
			k += 1
	_ticks.visible_instance_count = n
	for j in range(k, _nums.size()):
		_nums[j].visible = false
	# The camera climbs with you, circling slowly.
	var want := maxf(2.0, (top + (mark - top) * 0.5) if aiming else top + 1.0)
	_focus = lerpf(_focus, want, minf(1.0, delta * 2.5))
	var a := 0.55 + 0.25 * sin(_t * 0.17)
	camera.position = Vector3(sin(a) * 11.0, _focus + 1.6, cos(a) * 11.0)
	camera.look_at(Vector3(0, _focus + 0.2, 0), Vector3.UP)


func hud() -> Dictionary:
	var g = game
	var out := {
		"stats": PackedStringArray(["HEIGHT %d" % int(g.height), "ROUND %d" % g.round_n] + (["STREAK %d" % g.streak] if g.streak > 1 else [])),
	}
	if g.state == 0 and (g.playing or g.attract_mode):
		var left := clampf(1.0 - g.state_t / g.deadline, 0.0, 1.0)
		out["bars"] = [["START POUR", left, MAGENTA if left < 0.35 else ICE]]
	return out
