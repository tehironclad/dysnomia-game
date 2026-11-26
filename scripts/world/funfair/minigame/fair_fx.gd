class_name FairFx
extends Node3D
## The midway's game feel, shared by every stage: impact bursts and sparks, confetti, rising
## score pop-ups, a flash of light at the hit, squash-and-stretch, and a frame of chase bulbs
## round the stall's back wall (idle: a slow chase · win: a fast two-colour chase · grand: all
## gold, blinking). Everything is pooled and built once; nothing here reads the chain or the
## sim (MidwayPlay decides what happened and calls these).

const POP_T := 1.15

var _bursts: Array = []       ## CPUParticles3D (sphere bits)
var _sparks: Array = []       ## CPUParticles3D (streaks aligned to their velocity)
var _confetti: CPUParticles3D
var _pops: Array = []         ## [Label3D, age, base_pos, base_scale]
var _flash: OmniLight3D
var _flash_e := 0.0
var _bulbs: Array = []        ## bulb positions (stage space); drawn by _bulb_mm, one instance each
var _bulb_mm: MultiMesh       ## the chase bulbs: one draw for the frame (was ~120 meshes)
## Instance colours: rgb = colour, a = emission energy / 16 (fair_chase.gdshader).
const BULB_OFF := Color(0.35, 0.28, 0.2, 0.0)
const BULB_A := Color(1.0, 0.82, 0.45, 7.0 / 16.0)
const BULB_B := Color(1.0, 0.35, 0.7, 7.0 / 16.0)
const BULB_GOLD := Color(1.0, 0.9, 0.35, 12.0 / 16.0)
var _mode := "idle"
var _clock := 0.0
var _step := -1
var _ib := 0
var _is := 0
var _ip := 0


func _ready() -> void:
	for i in 3:
		_bursts.append(_particles(_bit_mesh(), 40, 0.7, false))
		_sparks.append(_particles(_spark_mesh(), 28, 0.45, true))
	_confetti = _confetti_emitter()
	for i in 6:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 3
		l.outline_render_priority = 2
		l.font_size = 96
		l.outline_size = 22
		l.pixel_size = 0.0019
		l.outline_modulate = Color(0.06, 0.02, 0.1, 0.95)
		l.font = DeepFieldTheme.display_font()
		l.visible = false
		add_child(l)
		_pops.append([l, 99.0, Vector3.ZERO, 1.0])
	_flash = OmniLight3D.new()
	_flash.omni_range = 5.0
	_flash.light_energy = 0.0
	_flash.visible = false
	_flash.shadow_enabled = false
	add_child(_flash)


func _bit_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.022
	m.height = 0.044
	m.radial_segments = 6
	m.rings = 3
	m.material = _vc_mat(false)
	return m


func _spark_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.012, 0.13, 0.012)
	m.material = _vc_mat(false)
	return m


static func _vc_mat(billboard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.6, 1.6, 1.6)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return mat


func _particles(mesh: Mesh, amount: int, life: float, align: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = Shares.particles(amount)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.particle_flag_align_y = align
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(0.7, 0.8))
	sc.add_point(Vector2(1, 0))
	p.scale_amount_curve = sc
	_idle_hidden(p)
	add_child(p)
	return p


## An idle emitter is hidden: CPUParticles3D still draws its whole (zero-scaled) batch when
## it isn't emitting, one object and one draw call each, ~7 per stall (perf, 2026-11-24).
## It shows on a trigger and hides again once its one shot is done.
static func _idle_hidden(p: CPUParticles3D) -> void:
	p.visible = false
	p.finished.connect(func() -> void: p.visible = false)


static func _fire(p: CPUParticles3D) -> void:
	p.visible = true
	p.restart()
	p.emitting = true


func _confetti_emitter() -> CPUParticles3D:
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.035)
	var mat := _vc_mat(true)
	mat.albedo_color = Color(1.2, 1.2, 1.2)
	q.material = mat
	var p := CPUParticles3D.new()
	p.mesh = q
	p.amount = Shares.particles(220)
	p.lifetime = 3.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.6, 0.1, 0.4)
	p.direction = Vector3.UP
	p.spread = 55.0
	p.gravity = Vector3(0, -2.2, 0)
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.5
	p.damping_min = 1.2
	p.damping_max = 2.4
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	g.colors = PackedColorArray([Color(1.0, 0.3, 0.45), Color(1.0, 0.85, 0.3), Color(0.35, 0.9, 1.0), Color(0.6, 1.0, 0.45), Color(0.8, 0.5, 1.0)])
	p.color_initial_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_idle_hidden(p)
	add_child(p)
	return p


# --- Effects ------------------------------------------------------------------------------

## A burst of glowing bits at `pos` (stage space). power ~0.5 (small) .. 2 (huge).
func burst(pos: Vector3, c: Color, power: float = 1.0) -> void:
	var p: CPUParticles3D = _bursts[_ib % _bursts.size()]
	_ib += 1
	p.position = pos
	p.color = c
	p.amount = Shares.particles(int(clampf(18.0 * power, 8.0, 40.0)))
	p.initial_velocity_max = 2.0 + 2.2 * power
	_fire(p)
	flash(pos, c, 1.0 + power * 2.0)


## Streaks flying off a hard hit (metal, the bell, glass).
func sparks(pos: Vector3, c: Color = Color(1.0, 0.8, 0.4), power: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	var p: CPUParticles3D = _sparks[_is % _sparks.size()]
	_is += 1
	p.position = pos
	p.color = c
	p.direction = dir
	p.spread = 70.0
	p.amount = Shares.particles(int(clampf(14.0 * power, 6.0, 28.0)))
	p.initial_velocity_min = 2.0 * power
	p.initial_velocity_max = 5.0 + 2.0 * power
	_fire(p)


## Confetti from `pos` (a box ~3 m wide).
func confetti(pos: Vector3) -> void:
	_confetti.position = pos
	_fire(_confetti)


## A rising score pop-up.
func popup(pos: Vector3, text: String, c: Color, size: float = 1.0) -> void:
	var e: Array = _pops[_ip % _pops.size()]
	_ip += 1
	var l: Label3D = e[0]
	l.text = text
	l.modulate = c
	l.visible = true
	e[1] = 0.0
	e[2] = pos
	e[3] = size
	set_process(true)


## A light flash at a hit.
func flash(pos: Vector3, c: Color, energy: float = 3.0) -> void:
	_flash.position = pos + Vector3(0, 0.15, 0.3)
	_flash.light_color = c
	_flash_e = energy
	_flash.light_energy = energy
	_flash.visible = true
	set_process(true)


## Squash-and-stretch: the node squashes along `axis` and springs back (elastic).
static func squash(n: Node3D, amount: float = 0.35, axis: Vector3 = Vector3.UP, base: Vector3 = Vector3.ONE) -> void:
	if n == null or not n.is_inside_tree():
		return
	var side := Vector3.ONE - axis.abs()
	var squashed := base * (Vector3.ONE - axis.abs() * amount + side * amount * 0.6)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", squashed, 0.05)
	tw.tween_property(n, "scale", base, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Stretch along the direction of travel (call each frame for a flying thing; 0 = round).
static func stretch(n: Node3D, amount: float, base: float = 1.0) -> void:
	n.scale = Vector3(base * (1.0 - amount * 0.4), base * (1.0 + amount), base * (1.0 - amount * 0.4))


# --- Chase bulbs --------------------------------------------------------------------------

## A rectangle of bulbs (stage space), centred at `c` in the XY plane facing +Z.
func bulb_frame(c: Vector3, w: float, h: float, spacing: float = 0.2) -> void:
	var nx := int(w / spacing)
	var ny := int(h / spacing)
	var pts: Array = []
	for i in nx:
		pts.append(c + Vector3(-w * 0.5 + i * w / nx, h * 0.5, 0))
	for i in ny:
		pts.append(c + Vector3(w * 0.5, h * 0.5 - i * h / ny, 0))
	for i in nx:
		pts.append(c + Vector3(w * 0.5 - i * w / nx, -h * 0.5, 0))
	for i in ny:
		pts.append(c + Vector3(-w * 0.5, -h * 0.5 + i * h / ny, 0))
	# Two MultiMeshes (bulbs, brass sockets): two draws for the whole frame.
	_bulbs = pts
	_bulb_mm = MultiMesh.new()
	_bulb_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bulb_mm.use_colors = true
	_bulb_mm.mesh = FairKit.bulb_mesh()  # 0.032 m, with LODs
	_bulb_mm.instance_count = pts.size()
	var sockets := MultiMesh.new()
	sockets.transform_format = MultiMesh.TRANSFORM_3D
	sockets.mesh = FairKit.cached_mesh("socket_lod", func() -> Mesh: return FairKit.with_lods(FairKit.cyl_mesh(0.02, 0.024, 0.03, 8)))
	sockets.instance_count = pts.size()
	var up := Basis(Vector3.RIGHT, PI * 0.5)
	for i in pts.size():
		_bulb_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i] + Vector3(0, 0, 0.03)))
		_bulb_mm.set_instance_color(i, BULB_OFF)
		sockets.set_instance_transform(i, Transform3D(up, pts[i]))
	for e in [[_bulb_mm, FairKit.shader_mat("fair_chase"), "Bulbs"], [sockets, FairKit.paint(Color(0.75, 0.6, 0.3), 0.3, 0.9), "Sockets"]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = e[2]
		mmi.multimesh = e[0]
		mmi.material_override = e[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	set_mode("still")


## still (a fixed pattern, no processing: the stall at rest) | idle (a slow chase while playing)
## | win | grand | off
func set_mode(m: String) -> void:
	_mode = m
	_step = -1
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	var busy := false
	for e in _pops:
		if float(e[1]) >= POP_T:
			continue
		busy = true
		e[1] = float(e[1]) + delta
		var t: float = e[1]
		var l: Label3D = e[0]
		var pop := 1.35 if t < 0.08 else lerpf(1.35, 1.0, clampf((t - 0.08) / 0.15, 0.0, 1.0))
		l.scale = Vector3.ONE * float(e[3]) * pop * minf(1.0, t / 0.06 + 0.2)
		l.position = e[2] + Vector3.UP * (0.55 * (1.0 - pow(1.0 - minf(t / POP_T, 1.0), 2.0)))
		l.modulate.a = clampf((POP_T - t) / 0.3, 0.0, 1.0)
		if t >= POP_T:
			l.visible = false
	if _flash.visible:
		busy = true
		_flash_e = maxf(0.0, _flash_e - delta * 14.0)
		_flash.light_energy = _flash_e
		_flash.visible = _flash_e > 0.01
	if not _bulbs.is_empty() and _mode in ["still", "off"]:
		if _step != -2:
			_step = -2
			for i in _bulbs.size():
				_bulb_mm.set_instance_color(i, BULB_A if _mode == "still" and i % 2 == 0 else BULB_OFF)
	elif not _bulbs.is_empty():
		busy = true
		var rate := 5.0 if _mode == "idle" else (16.0 if _mode == "win" else 6.0)
		var s := int(_clock * rate)
		if s != _step:
			_step = s
			var n := _bulbs.size()
			for i in n:
				var m := BULB_OFF
				match _mode:
					"idle": m = BULB_A if (i + s) % 4 == 0 else BULB_OFF
					"win": m = (BULB_A if (i / 3) % 2 == 0 else BULB_B) if (i + s) % 3 != 0 else BULB_OFF
					"grand": m = BULB_GOLD if s % 2 == 0 or i % 2 == 0 else BULB_B
				_bulb_mm.set_instance_color(i, m)
	if not busy:
		set_process(false)
