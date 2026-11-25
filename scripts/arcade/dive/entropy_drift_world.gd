extends ArcadeWorld
## Entropy Drift, dived into: a drift racer. Your probe skims a neon road through the dark; entropy
## shards spin toward you, gold Fornax motes hang over the road, Eris fronts wall it off with one gap.
## The road bends and climbs, and its floor shows its own 32 bytes, from DriftTrack: SHA-256 of the
## QING's Entropy() and a block hash read from the chain (your credit's block on a paid run, which
## also seeds the field; the latest block in the demo). Nothing is invented: no hash, a flat road.
##
## The 2D game (entropy_drift.gd) is the source of truth. Its field scrolls right-to-left; here that
## is depth (2D x → z, the probe's home x = 60 sits at z = 0) and its vertical axis is the road's
## width (2D y → x). So the keys are remapped: left/right steer (2D up/down), forward/back push the
## probe ahead or let it fall back (2D right/left).

const KZ := 0.16  ## metres per 2D px of depth
const KX := 0.075  ## metres per 2D px across the road
const HALF_W := 8.4
const POSTS := 18
const POST_GAP := 5.0
const RINGS := 4
const RING_GAP := 42.0

var track: DriftTrack
var _road_mat: ShaderMaterial
var _shards: Array = []  # MultiMesh per vertex count 3, 4, 5
var _motes: MultiMesh
var _sparks: MultiMesh
var _posts: MultiMesh
var _rings: Array = []
var _ship: Node3D
var _flame: MeshInstance3D
var _trail: ImmediateMesh
var _pulse: MeshInstance3D
var _sun: MeshInstance3D
var _curv := 0.0
var _hill := 0.0
var _scroll := 0.0
var _hue_c := ICE
var _hue_c2 := MAGENTA


func controls_remap() -> Dictionary:
	return {
		ArcadeGame.IN_LEFT: ArcadeGame.IN_UP, ArcadeGame.IN_RIGHT: ArcadeGame.IN_DOWN,
		ArcadeGame.IN_UP: ArcadeGame.IN_RIGHT, ArcadeGame.IN_DOWN: ArcadeGame.IN_LEFT,
	}


func controls_list() -> Array:
	return [["%s %s" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right")], "steer"],
		["%s %s" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_back")], "surge / brake"],
		[ControlsHelp.key_of("jump"), "pulse (costs Fornax)"]]


func controls_hint() -> String:
	return "%s / %s steer · %s / %s surge and brake · %s pulse (costs Fornax)" % [ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_right"), ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_back"), ControlsHelp.key_of("jump")]


static func zf(x: float) -> float:
	return -(x - 60.0) * KZ


static func xf(y: float) -> float:
	return (y - 128.0) * KX


## The road's bend at depth z (z < 0 is ahead).
func bend(z: float) -> Vector3:
	return Vector3(_curv * z * z, _hill * z * z, 0.0)


func at(px: Vector2, h: float) -> Vector3:
	var z := zf(px.x)
	return Vector3(xf(px.y), h, z) + bend(z)


func _build() -> void:
	make_environment(Color(0.004, 0.006, 0.014), Color(0.01, 0.015, 0.03), 0.02, 1.1)
	make_camera(66.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 0.8
	sun.light_color = Color(0.75, 0.8, 1.0)
	add_child(sun)
	starfield(600, 240.0, 0xD21F7, 1.4)
	_sun = add_mesh(_quad(Vector2(120, 120)), _soft(GOLD, 0.7))
	_sun.position = Vector3(0, 18, -250)
	_build_road()
	_build_posts()
	_build_rings()
	for n in [3, 4, 5]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.05, 0.3)
		m.vertex_color_use_as_albedo = true
		m.metallic = 0.6
		m.roughness = 0.25
		m.emission_enabled = true
		m.emission = MAGENTA
		m.emission_energy_multiplier = 0.9
		_shards.append(pool_multimesh(_crystal(n), m, 48))
	var sm := SphereMesh.new()
	sm.radius = 0.26
	sm.height = 0.52
	sm.radial_segments = 10
	sm.rings = 5
	_motes = pool_multimesh(sm, neon_mat(GOLD, 3.2), 40)
	_sparks = pool_multimesh(box_mesh(Vector3(0.06, 0.06, 0.45)), neon_mat(Color.WHITE, 3.0, true), 90)
	_build_ship()
	var pm := SphereMesh.new()
	pm.radius = 1.0
	pm.height = 2.0
	_pulse = add_mesh(pm, neon_mat(ICE, 1.2, true, 0.5))
	_pulse.visible = false
	_apply_track(DriftTrack.make("", ""))


func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


func _soft(c: Color, a: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c, a)
	m.albedo_texture = _dot_texture()
	m.disable_fog = true
	return m


## An n-sided bipyramid: a crystal shard, radius 1 across, ±1 long.
func _crystal(n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array = []
	for j in n:
		var a := TAU * j / n
		ring.append(Vector3(cos(a), sin(a), 0.0) * (0.75 + 0.25 * float((j * 7) % 3) / 2.0))
	var front := Vector3(0, 0, -1)
	var back := Vector3(0, 0, 1)
	for j in n:
		var a: Vector3 = ring[j]
		var b: Vector3 = ring[(j + 1) % n]
		for tri in [[front, b, a], [back, a, b]]:
			for v in tri:
				st.set_color(Color.WHITE)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


const ROAD_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float curv = 0.0;
uniform float hill = 0.0;
uniform float scroll = 0.0;
uniform float half_w = 8.4;
uniform vec4 rail_c : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform vec4 alt_c : source_color = vec4(1.0, 0.3, 0.85, 1.0);
uniform float bytes[32];
varying vec3 lp;
void vertex() {
	float wz = VERTEX.z + MODEL_MATRIX[3].z;
	VERTEX.x += curv * wz * wz;
	VERTEX.y += hill * wz * wz;
	lp = vec3(VERTEX.x - curv * wz * wz, 0.0, wz);
}
void fragment() {
	float x = lp.x;
	float z = lp.z - scroll;
	float ax = abs(x);
	float rail = smoothstep(half_w - 0.5, half_w - 0.15, ax) * smoothstep(half_w + 0.1, half_w - 0.1, ax);
	float dash = step(0.5, fract(z / 4.0)) * smoothstep(0.09, 0.0, ax);
	// The track's 32 bytes as a field of cells: brighter cell = bigger byte.
	vec2 cell = vec2(floor((x + half_w) / 2.1), floor(z / 2.1));
	int k = int(mod(cell.x * 7.0 + cell.y * 3.0, 32.0));
	float b = bytes[k];
	vec2 f = fract(vec2((x + half_w) / 2.1, z / 2.1));
	float outline = 1.0 - smoothstep(0.0, 0.06, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	float inside_road = step(ax, half_w - 0.4);
	vec3 base = vec3(0.0015, 0.002, 0.005);
	vec3 c = base + alt_c.rgb * outline * b * 0.45 * inside_road + rail_c.rgb * b * b * 0.012 * inside_road;
	c += rail_c.rgb * rail * 3.0 + vec3(1.0) * dash * 0.7;
	float off = step(half_w + 0.15, ax);
	c = mix(c, vec3(0.0008, 0.0008, 0.002) + rail_c.rgb * 0.003, off);
	ALBEDO = c;
}
"""


func _build_road() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_W * 2.0 + 10.0, 80.0)
	pm.subdivide_depth = 60
	pm.subdivide_width = 6
	var sh := Shader.new()
	sh.code = ROAD_SHADER
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = sh
	_road_mat.set_shader_parameter("half_w", HALF_W)
	var road := add_mesh(pm, _road_mat)
	road.position = Vector3(0, 0, -30)
	road.extra_cull_margin = 40.0


func _build_posts() -> void:
	_posts = pool_multimesh(box_mesh(Vector3(0.14, 1.3, 0.14)), neon_mat(Color.WHITE, 2.6), POSTS * 2)
	_posts.visible_instance_count = POSTS * 2


func _build_rings() -> void:
	for i in RINGS:
		var tm := TorusMesh.new()
		tm.inner_radius = HALF_W + 0.6
		tm.outer_radius = HALF_W + 1.0
		tm.rings = 48
		tm.ring_segments = 6
		var r := add_mesh(tm, neon_mat(Color.WHITE, 2.2))
		r.rotation_degrees.x = 90.0
		_rings.append(r)


func _build_ship() -> void:
	_ship = Node3D.new()
	add_child(_ship)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := Vector3(0, 0, -1.1)
	var lw := Vector3(-0.75, -0.02, 0.5)
	var rw := Vector3(0.75, -0.02, 0.5)
	var top := Vector3(0, 0.26, 0.2)
	var bot := Vector3(0, -0.14, 0.25)
	var tail := Vector3(0, 0.04, 0.55)
	for tri in [[nose, lw, top], [nose, top, rw], [lw, tail, top], [top, tail, rw], [nose, bot, lw], [nose, rw, bot], [lw, bot, tail], [bot, rw, tail]]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.3, 0.34, 0.45)
	hull.metallic = 0.85
	hull.roughness = 0.28
	hull.emission_enabled = true
	hull.emission = ICE
	hull.emission_energy_multiplier = 0.08
	hull.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_mesh(st.commit(), hull, _ship)
	var trim := neon_mat(ICE, 3.5)
	for sx in [-1.0, 1.0]:
		var edge := add_mesh(box_mesh(Vector3(0.04, 0.04, 1.75)), trim, _ship)
		edge.position = Vector3(sx * 0.38, 0.0, -0.3)
		edge.rotation.y = -sx * 0.42
	var eng := SphereMesh.new()
	eng.radius = 0.09
	eng.height = 0.18
	var e := add_mesh(eng, neon_mat(ICE, 2.2), _ship)
	e.position = Vector3(0, 0.04, 0.58)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 0.0
	cone.height = 1.0
	_flame = add_mesh(cone, neon_mat(GOLD, 1.4, true, 0.5), _ship)
	_flame.rotation_degrees.x = 90.0
	_flame.position = Vector3(0, 0.04, 1.05)
	_trail = ImmediateMesh.new()
	var tmi := add_mesh(_trail, neon_mat(ICE, 2.0, true, 0.6))
	tmi.extra_cull_margin = 50.0


func _apply_track(t: DriftTrack) -> void:
	track = t
	var arr := PackedFloat32Array()
	for i in 32:
		arr.append(float(t.bytes[i]) / 255.0 if t.ok else 0.0)
	_road_mat.set_shader_parameter("bytes", arr)
	_hue_c = Color.from_hsv(t.hue(), 0.6, 1.0)
	_hue_c2 = Color.from_hsv(fmod(t.hue() + 0.42, 1.0), 0.75, 1.0)
	_road_mat.set_shader_parameter("rail_c", _hue_c)
	_road_mat.set_shader_parameter("alt_c", _hue_c2)
	for i in POSTS * 2:
		_posts.set_instance_color(i, _hue_c if i % 2 == 0 else _hue_c2)
	for i in _rings.size():
		_rings[i].material_override.set_shader_parameter("color", _hue_c2 if i % 2 == 0 else _hue_c)
	_sun.material_override.albedo_color = Color(_hue_c.lerp(GOLD, 0.5), 0.75)


func _entropy() -> String:
	var q: Dictionary = ctx.get("territory", {})
	return String(q.get("entropy", ""))


func prepare_demo() -> void:
	var r: Dictionary = await Chain.rpc.get_block("latest")
	if not is_inside_tree():
		return
	if r.get("ok", false) and r["result"] is Dictionary:
		_apply_track(DriftTrack.make(_entropy(), String(r["result"].get("hash", "")), String(r["result"].get("number", "0x0")).hex_to_int(), "latest block"))
	else:
		_apply_track(DriftTrack.make(_entropy(), "", -1, "latest block"))
	source_label = "DEMO, no credit spent · " + track.source


func prepare_run(credit: Dictionary) -> int:
	var block := int(credit.get("block", -1))
	var h := ""
	if block >= 0:
		h = await TableBook.block_hash(block)
	if h != "":
		# A strip's plays share a block: each play's road mixes in its number (TicketCode.seed_tx)
		var idx := int(credit.get("index", -1))
		_apply_track(DriftTrack.make(_entropy(), TicketCode.seed_tx(h, idx), block, "your credit's block" if idx < 0 else "your strip's block, play %d" % idx))
	else:
		_apply_track(DriftTrack.make(_entropy(), ArcadePay.seed_tx(credit), -1, "your credit's tx"))
	if track.ok:
		source_label = "PAID RUN · %s · the field is seeded from the same bytes" % track.source
		return track.seed()
	source_label = "PAID RUN · %s · field seeded from the credit tx" % track.source
	return seed_from_tx(ArcadePay.seed_tx(credit))


func _sync(delta: float) -> void:
	var g = game
	var d: float = g.dist * 10.0
	_curv = lerpf(_curv, track.curve_at(d), minf(1.0, delta * 2.0))
	_hill = lerpf(_hill, track.hill_at(d), minf(1.0, delta * 2.0))
	var speed: float = g.speed
	if g.playing or g.attract_mode:
		_scroll += speed * KZ * delta
	_road_mat.set_shader_parameter("curv", _curv)
	_road_mat.set_shader_parameter("hill", _hill)
	_road_mat.set_shader_parameter("scroll", -_scroll)
	for i in POSTS:
		var z := fmod(i * POST_GAP + _scroll, POSTS * POST_GAP) - (POSTS - 2) * POST_GAP
		for side in 2:
			var p := Vector3((HALF_W + 0.5) * (1.0 if side == 1 else -1.0), 0.65, z) + bend(z)
			_posts.set_instance_transform(i * 2 + side, Transform3D(Basis(), p))
	for i in _rings.size():
		var z := fmod(i * RING_GAP + _scroll * 0.999, RINGS * RING_GAP) - (RINGS - 1) * RING_GAP - 12.0
		var r: MeshInstance3D = _rings[i]
		r.position = Vector3(0, 0.0, z) + bend(z)
		r.rotation = Vector3(PI * 0.5, 0, 0)

	# Shards, by vertex count.
	var counts := [0, 0, 0]
	for s in g.shards:
		var k: int = clampi(s.shape.size() - 3, 0, 2)
		var mm: MultiMesh = _shards[k]
		var r: float = s.r
		var basis := Basis(Vector3(0, 0, 1), s.rot) * Basis.from_scale(Vector3(r * KX * 1.1, r * KX * 1.1, r * KZ * 0.9))
		basis = Basis(Vector3(1, 0, 0), s.rot * 0.3) * basis
		mm.set_instance_transform(counts[k], Transform3D(basis, at(s.p, 0.75 + sin(s.rot) * 0.12)))
		mm.set_instance_color(counts[k], Color(1, 0.5 + 0.5 * absf(sin(s.rot * 0.5)), 1))
		counts[k] += 1
	for k in 3:
		(_shards[k] as MultiMesh).visible_instance_count = counts[k]
	var n := 0
	for m in g.motes:
		if n >= 40:
			break
		var pulse := 0.85 + 0.25 * sin(m.ph)
		_motes.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * pulse), at(m.p, 0.75)))
		_motes.set_instance_color(n, Color.WHITE)
		n += 1
	_motes.visible_instance_count = n
	n = 0
	for sp in g.sparks:
		if n >= 90:
			break
		var v: Vector2 = sp.v
		var dir := Vector3(v.y * KX, 0.0, -v.x * KZ)
		var b := Basis.looking_at(dir.normalized(), Vector3.UP) if dir.length() > 0.05 else Basis()
		var xf3 := Transform3D(b.scaled(Vector3.ONE * clampf(sp.life * 3.0, 0.2, 1.0)), at(sp.p, 0.75))
		_sparks.set_instance_transform(n, xf3)
		_sparks.set_instance_color(n, Color(sp.c, clampf(sp.life * 2.5, 0.0, 1.0)))
		n += 1
	_sparks.visible_instance_count = n

	# The probe drifts: it yaws into its sideways speed and banks.
	var p := at(g.probe, 0.75)
	_ship.position = p
	var lat: float = g.vel.y
	_ship.rotation = Vector3(-g.vel.x * 0.0006, -lat * 0.0028, -lat * 0.0042)
	_ship.visible = g.lives > 0 and (g.invuln <= 0.0 or int(g.t * 12.0) % 2 == 0)
	var thrust: bool = (g.held & (ArcadeGame.IN_LEFT | ArcadeGame.IN_RIGHT | ArcadeGame.IN_UP | ArcadeGame.IN_DOWN)) != 0
	_flame.scale = Vector3.ONE * (1.0 + (0.6 if thrust else 0.0) + 0.15 * sin(_t * 50.0))
	_trail.clear_surfaces()
	var tr: PackedVector2Array = g.trail
	if tr.size() > 1:
		_trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in tr.size():
			var a := float(i) / tr.size()
			var c := at(tr[i] - Vector2(5, 0), 0.75)
			_trail.surface_set_color(Color(1, 1, 1, a * 0.8))
			_trail.surface_add_vertex(c + Vector3(-0.12 * a, 0, 0))
			_trail.surface_set_color(Color(1, 1, 1, a * 0.8))
			_trail.surface_add_vertex(c + Vector3(0.12 * a, 0, 0))
		_trail.surface_end()

	_pulse.visible = g.pulse_t >= 0.0
	if _pulse.visible:
		var rr: float = g.PULSE_R * minf(1.0, g.pulse_t / g.PULSE_TIME)
		_pulse.position = at(g.pulse_at, 0.75)
		_pulse.scale = Vector3(rr * KX, rr * KX * 0.35, rr * KZ)
		_pulse.material_override.set_shader_parameter("alpha", 0.6 * (1.0 - g.pulse_t / g.PULSE_TIME))

	# The chase camera: behind and above, leaning into the bend and the drift.
	var cz := p.z + 7.2
	var shake := Vector3.ZERO
	if g.flash > 0.0:
		shake = Vector3(sin(_t * 83.0), cos(_t * 71.0), 0) * g.flash * 0.4
	camera.position = Vector3(p.x * 0.6, 2.5 + bend(cz).y, cz) + shake
	var ahead := p.z - 20.0
	camera.look_at(Vector3(p.x * 0.8, 0.5, ahead) + bend(ahead) * 0.6, Vector3.UP)
	camera.rotate_object_local(Vector3(0, 0, 1), clampf(-_curv * 120.0 + lat * 0.0012, -0.32, 0.32))
	camera.fov = 64.0 + clampf((speed - 70.0) / 190.0, 0.0, 1.0) * 20.0


func hud() -> Dictionary:
	var g = game
	var low: bool = g.charge < 25.0
	return {
		"stats": PackedStringArray(["x%d MULTIPLIER" % g.multiplier(), "EPOCH %d" % g.epoch, "%d m/s" % int(g.speed * KZ)]),
		"bars": [["FORNAX", clampf(g.charge / 100.0, 0.0, 1.0), MAGENTA if low else GOLD]],
		"flash": g.flash, "flash_color": MAGENTA,
	}
