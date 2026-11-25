class_name RaveHall
extends Node3D
## The arcade as a blacklight party (every territory): UV paint on dark walls (rave_uv), a dance floor
## of tiles that change on every beat (rave_floor), lasers fanning from the DJ booth and spot cones
## through the haze (rave_beam), a mirror ball, speaker stacks that pump on the kick, a DJ on the decks
## and a crowd that dances, drifts round the floor and wanders over to watch the cabinets. The music is
## RaveMusic (synthesised, from the booth); its beat clock drives everything here.
##
## The palette, the patterns, the tempo, the DJ's head and the crowd's looks are RaveStyle: from the
## territory's state only, the same for every visitor. Cheap by design: one mesh for the floor, one
## material per wall pattern, MultiMeshes for the lasers, cones, knobs and glows, no shadow casters,
## and the crowd is a handful of avatars (fewer on low graphics).

const CROWD_HIGH := 10
const CROWD_LOW := 6
const CROWD_POTATO := 4
const DANCE_SPEED := 1.25
const AVOID_R := 0.95

var style: Dictionary = {}
var music: RaveMusic
var host: Node  ## the GamesPlace (its player, dive and cabinets)
var hx := 12.0
var hz := 10.0
var dance := Rect2()  ## the dance floor (x, z)
var stage_z := 0.0  ## the stage's front edge
var dj: HumanAvatar
var dancers: Array = []  # {a: HumanAvatar, mode, target: Vector3, bars: int, watch: Vector3, roamer: bool}
var _uv: Array[ShaderMaterial] = []
var _floor_mat: ShaderMaterial
var _led_mat: ShaderMaterial
var _lasers: MultiMesh
var _cones: MultiMesh
var _knobs: MultiMesh
var _glows: MultiMesh
var _glow_spots: Array = []  # Vector3 under each cabinet
var _decks: Array = []
var _cabinet_watch: Array = []  # [stand at, face toward]
var _speakers: Array = []
var _lights: Array = []
var _ball: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _dance_speed := 1.0
var _dj_bar := -1


## Where things stand in a hall hx × hz (half sizes, metres): the dance floor and the stage.
static func layout(p_hx: float, p_hz: float) -> Dictionary:
	return {"dance": Rect2(-6.0, -p_hz + 3.6, 12.0, 8.0), "stage_z": -p_hz + 3.0, "booth": Vector3(0, 0.45, -p_hz + 2.55),
		"dj": Vector3(0, 0.45, -p_hz + 1.8)}


## Builds the party into `p_host` (a GamesPlace). Call after its cabinets are placed.
func build(p_host: Node, territory: Dictionary, p_hx: float, p_hz: float) -> void:
	host = p_host
	hx = p_hx
	hz = p_hz
	name = "RaveHall"
	style = RaveStyle.for_territory(territory)
	_rng.seed = int(style["crowd_seed"])
	var lay := layout(hx, hz)
	dance = lay["dance"]
	stage_z = lay["stage_z"]
	_build_shell(territory)
	_build_stage(territory, lay)
	_build_lights()
	_build_cabinet_glows()
	_build_crowd(lay)
	music = RaveMusic.new()
	add_child(music)
	music.position = Vector3(0, 2.2, -hz + 1.2)
	var start_bar := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rave-bar="):
			start_bar = int(arg.substr(11))  # previews: start the set in the drop
	music.setup(style, start_bar)
	music.bar_started.connect(_on_bar)
	_dance_speed = dance_clip_speed(float(style["bpm"]))
	for gi in find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func uv(i: int) -> Color:
	return style["uv"][i % 3]


## The Dance clip's speed so one loop spans a whole number of beats at `bpm` (the crowd dances on it).
static func dance_clip_speed(bpm: float) -> float:
	var lib := HumanAvatar.library()
	if not lib.has_animation("Dance"):
		return 1.0
	var length := lib.get_animation("Dance").length
	var beat := 60.0 / bpm
	var n := maxf(1.0, round(length / beat))
	return length / (n * beat)


# ── building ────────────────────────────────────────────────────────────────


func _paint(pattern: String, glow: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/rave_uv.gdshader")
	m.set_shader_parameter("c1", uv(0))
	m.set_shader_parameter("c2", uv(1))
	m.set_shader_parameter("c3", uv(2))
	m.set_shader_parameter("pattern", RaveStyle.WALL_PATTERNS.find(pattern))
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("ball", Vector3(0, 4.3, dance.get_center().y))
	_uv.append(m)
	return m


func _build_shell(territory: Dictionary) -> void:
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = load("res://assets/shaders/rave_floor.gdshader")
	for i in 3:
		_floor_mat.set_shader_parameter("c%d" % (i + 1), uv(i))
	_floor_mat.set_shader_parameter("dance", Vector4(dance.position.x, dance.position.y, dance.end.x, dance.end.y))
	_floor_mat.set_shader_parameter("dj", Vector2(0, -hz + 1.8))
	_floor_mat.set_shader_parameter("pattern", RaveStyle.FLOOR_PATTERNS.find(String(style["floor"])))
	GamesPlace.box(self, Vector3(hx * 2, 0.2, hz * 2), Vector3(0, -0.1, 0), _floor_mat, true)
	var wall := _paint(String(style["wall"]))
	GamesPlace.box(self, Vector3(hx * 2, 5.0, 0.3), Vector3(0, 2.5, -hz), wall, true)
	GamesPlace.box(self, Vector3(0.3, 5.0, hz * 2), Vector3(-hx, 2.5, 0), wall, true)
	GamesPlace.box(self, Vector3(0.3, 5.0, hz * 2), Vector3(hx, 2.5, 0), wall, true)
	GamesPlace.box(self, Vector3(hx - 1.2, 5.0, 0.3), Vector3(-(hx + 1.2) * 0.5, 2.5, hz), wall, true)
	GamesPlace.box(self, Vector3(hx - 1.2, 5.0, 0.3), Vector3((hx + 1.2) * 0.5, 2.5, hz), wall, true)
	GamesPlace.box(self, Vector3(2.4, 1.8, 0.3), Vector3(0, 4.1, hz), wall)
	var ceiling := _paint("circuit", 0.35)
	GamesPlace.box(self, Vector3(hx * 2, 0.2, hz * 2), Vector3(0, 5.1, 0), ceiling)
	# Fluorescent trims: a skirting line and a wall-wash band round the room, in the paints.
	for sx in [-1.0, 1.0]:
		GamesPlace.box(self, Vector3(0.04, 0.06, hz * 2 - 0.6), Vector3(sx * (hx - 0.17), 0.08, 0), GamesPlace.glow(uv(0), 2.4))
		GamesPlace.box(self, Vector3(0.04, 0.05, hz * 2 - 0.6), Vector3(sx * (hx - 0.17), 3.2, 0), GamesPlace.glow(uv(1), 2.2))
	GamesPlace.box(self, Vector3(hx * 2 - 0.6, 0.06, 0.04), Vector3(0, 0.08, -hz + 0.17), GamesPlace.glow(uv(0), 2.4))
	# Ceiling truss: two bars over the floor, where the spot cones hang.
	var truss := GamesPlace.mat(Color(0.05, 0.05, 0.07), 0.4, 0.8)
	for z in [dance.position.y + 1.5, dance.end.y - 1.5]:
		GamesPlace.box(self, Vector3(dance.size.x + 1.0, 0.18, 0.18), Vector3(0, 4.75, z), truss)
	var ms := SphereMesh.new()
	ms.radius = 0.38
	ms.height = 0.76
	ms.radial_segments = 16
	ms.rings = 8
	_ball = MeshInstance3D.new()
	_ball.mesh = ms
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.8, 0.82, 0.9)
	bm.metallic = 1.0
	bm.roughness = 0.12
	bm.emission_enabled = true
	bm.emission = Color(0.5, 0.45, 0.7)
	bm.emission_energy_multiplier = 0.6
	_ball.material_override = bm
	_ball.position = Vector3(0, 4.3, dance.get_center().y)
	add_child(_ball)


func _build_stage(territory: Dictionary, lay: Dictionary) -> void:
	var dark := GamesPlace.mat(Color(0.03, 0.025, 0.05), 0.5, 0.4)
	# The stage, its lit edge, and the booth.
	GamesPlace.box(self, Vector3(9.0, 0.45, stage_z + hz), Vector3(0, 0.225, (-hz + stage_z) * 0.5), dark, true)
	GamesPlace.box(self, Vector3(9.0, 0.05, 0.06), Vector3(0, 0.45, stage_z), GamesPlace.glow(uv(1), 2.6))
	var booth: Vector3 = lay["booth"]
	_led_mat = _paint("hypobar", 1.6)
	GamesPlace.box(self, Vector3(3.4, 1.05, 0.7), booth + Vector3(0, 0.525, 0), dark, true)
	var front := GamesPlace.box(self, Vector3(3.3, 0.9, 0.02), booth + Vector3(0, 0.52, 0.36), _led_mat)
	front.name = "BoothFront"
	GamesPlace.box(self, Vector3(3.5, 0.04, 0.8), booth + Vector3(0, 1.07, 0), GamesPlace.glow(uv(0), 2.0))
	# Two decks and a mixer.
	var deck_mat := GamesPlace.mat(Color(0.05, 0.05, 0.06), 0.3, 0.6)
	for sx in [-1.0, 1.0]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.24
		cm.bottom_radius = 0.24
		cm.height = 0.03
		var d := MeshInstance3D.new()
		d.mesh = cm
		d.material_override = deck_mat
		d.position = booth + Vector3(sx * 1.0, 1.1, 0)
		add_child(d)
		var lab := GamesPlace.box(d, Vector3(0.1, 0.012, 0.02), Vector3(0.12, 0.02, 0), GamesPlace.glow(uv(2), 2.0))
		lab.name = "Mark"
		_decks.append(d)
	_knobs = _multimesh(_knob_mesh(), GamesPlace.glow(Color.WHITE, 2.0), 12, true)
	for i in 12:
		_knobs.set_instance_transform(i, Transform3D(Basis(), booth + Vector3(-0.42 + (i % 4) * 0.28, 1.1, -0.18 + (i / 4) * 0.18)))
		_knobs.set_instance_color(i, uv(i))
	# The LED wall behind the DJ: an equaliser in the paints, the place's name over it.
	var led := GamesPlace.box(self, Vector3(9.0, 3.2, 0.05), Vector3(0, 2.6, -hz + 0.2), _led_mat)
	led.name = "LedWall"
	var sign := Label3D.new()
	sign.text = "ARCADE · %s" % String(territory.get("name", "")).to_upper()
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 120
	sign.pixel_size = 0.01
	sign.modulate = uv(0).lerp(Color.WHITE, 0.3)
	sign.outline_size = 18
	sign.outline_modulate = Color(0, 0, 0, 0.85)
	sign.position = Vector3(0, 4.55, -hz + 0.3)
	add_child(sign)
	# Speaker stacks either side, pumping on the kick.
	var cab := GamesPlace.mat(Color(0.02, 0.02, 0.03), 0.6, 0.2)
	var cone_m := GamesPlace.mat(Color(0.06, 0.06, 0.08), 0.4, 0.5)
	for sx in [-1.0, 1.0]:
		var stack := Node3D.new()
		stack.position = Vector3(sx * 4.0, 0.45, -hz + 1.4)
		add_child(stack)
		GamesPlace.box(stack, Vector3(1.1, 2.4, 0.9), Vector3(0, 1.2, 0), cab, true)
		for k in 2:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.36
			cm.bottom_radius = 0.36
			cm.height = 0.06
			var c := MeshInstance3D.new()
			c.mesh = cm
			c.material_override = cone_m
			c.rotation.x = PI * 0.5
			c.position = Vector3(0, 0.65 + k * 1.05, 0.46)
			stack.add_child(c)
			_speakers.append(c)
			GamesPlace.box(stack, Vector3(0.82, 0.03, 0.02), Vector3(0, 0.65 + k * 1.05 + 0.42, 0.46), GamesPlace.glow(uv(k + 1), 2.2))
	# The lasers and the spot cones.
	var beam := ShaderMaterial.new()
	beam.shader = load("res://assets/shaders/rave_beam.gdshader")
	beam.set_shader_parameter("strength", 2.2)
	beam.set_shader_parameter("fade_start", 0.25)
	_lasers = _multimesh(box_mesh(Vector3(1, 1, 1)), beam, int(style["lasers"]))
	var conem := CylinderMesh.new()
	conem.top_radius = 0.06
	conem.bottom_radius = 1.0
	conem.height = 1.0
	conem.radial_segments = 16
	conem.cap_top = false
	conem.cap_bottom = false
	var cone_mat := ShaderMaterial.new()
	cone_mat.shader = load("res://assets/shaders/rave_beam.gdshader")
	cone_mat.set_shader_parameter("cone", 1.0)
	cone_mat.set_shader_parameter("strength", 0.55)
	_cones = _multimesh(conem, cone_mat, 6)
	# The DJ: a creature head from this territory, on the decks.
	dj = _avatar(String(style["dj_head"]), Outfits.for_npc(int(style["crowd_seed"]) + 77), "male")
	dj.name = "DJ"
	dj.position = lay["dj"]
	dj.hold_clip = "Dance"
	dj.apply_appearance({"accent_color": uv(0)})


static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _knob_mesh() -> CylinderMesh:
	var k := CylinderMesh.new()
	k.top_radius = 0.035
	k.bottom_radius = 0.035
	k.height = 0.04
	k.radial_segments = 8
	return k


func _multimesh(mesh: Mesh, material: Material, n: int, colors: bool = true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _build_lights() -> void:
	var at := [Vector3(-7.0, 3.8, dance.position.y + 1.0), Vector3(7.0, 3.8, dance.position.y + 1.0),
		Vector3(-4.0, 3.6, dance.end.y), Vector3(4.0, 3.6, dance.end.y), Vector3(0, 3.4, -hz + 3.2)]
	for i in at.size():
		var l := OmniLight3D.new()
		l.light_color = uv(i) if i < 4 else RaveStyle.BLACKLIGHT
		l.omni_range = 11.0
		l.light_energy = 1.2
		l.shadow_enabled = false
		l.position = at[i]
		add_child(l)
		_lights.append(l)


func _build_cabinet_glows() -> void:
	var cabs: Array = host.cabinets if host and "cabinets" in host else []
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.6)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = ArcadeWorld._dot_texture()
	m.disable_fog = true
	_glows = _multimesh(q, m, maxi(1, cabs.size()))
	for i in cabs.size():
		var c: Node3D = cabs[i]
		var at: Vector3 = c.to_global(Vector3(0, 0.02, 0.35))
		_glow_spots.append(at)
		_glows.set_instance_transform(i, Transform3D(Basis(Vector3.UP, c.global_rotation.y), at))
		_glows.set_instance_color(i, uv(i))
		# Where a crowd member stands to watch this cabinet.
		_cabinet_watch.append([c.to_global(Vector3(0.35, 0, 1.5)), c.to_global(Vector3(0, 1.4, 0))])
	_glows.visible_instance_count = cabs.size()


# ── the crowd ───────────────────────────────────────────────────────────────


func _avatar(head: String, outfit: Dictionary, body: String) -> HumanAvatar:
	var a := HumanAvatar.new()
	a.civilian = true
	a.body_kind = body
	a.outfit_kind = String(outfit["kind"])
	a.outfit_seed = int(outfit["seed"])
	add_child(a)
	a.set_head(head)
	return a


func _build_crowd(lay: Dictionary) -> void:
	var n := CROWD_HIGH if Config.level() >= 2 else (CROWD_LOW if Config.level() == 1 else CROWD_POTATO)
	var people := RaveStyle.crowd(style, n)
	for i in n:
		var who: Dictionary = people[i]
		var a := _avatar(String(who["head"]), who["outfit"], String(who["body"]))
		a.name = "Dancer%d" % i
		a.apply_appearance({"accent_color": uv(i)})
		var spot := _floor_spot()
		a.position = spot
		a.hold_clip = "Dance"
		a.hold_speed = 1.0
		dancers.append({"a": a, "mode": "dance", "target": spot, "bars": 2 + _rng.randi_range(0, 4),
			"face": Vector3.ZERO, "roamer": i % 4 == 3, "phase": float(who["phase"])})


func _floor_spot() -> Vector3:
	var r := dance.grow(-0.8)
	return Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y + 1.0, r.end.y))


## Every bar: dancers whose turn is up drift to a new spot on the floor; roamers sometimes go and
## watch a cabinet for a while; the DJ swaps between dancing and working the decks.
func _on_bar(n: int) -> void:
	for d in dancers:
		d["bars"] = int(d["bars"]) - 1
		if int(d["bars"]) > 0:
			continue
		if d["mode"] == "dance" and bool(d["roamer"]) and not _cabinet_watch.is_empty() and _rng.randf() < 0.5:
			var w: Array = _cabinet_watch[_rng.randi_range(0, _cabinet_watch.size() - 1)]
			d["target"] = w[0]
			d["face"] = w[1]
			d["next"] = "watch"
		else:
			var a: HumanAvatar = d["a"]
			var to := _floor_spot()
			if d["mode"] == "dance":
				to = a.position.lerp(to, 0.45)  # a drift, not a march
			d["target"] = to
			d["face"] = Vector3.ZERO
			d["next"] = "dance"
		d["mode"] = "walk"
		d["bars"] = 3 + _rng.randi_range(0, 5)
	if dj:
		var sec := RaveTrack.section(n)
		dj.hold_clip = "Idle_Talking" if sec == "break" or (n % 8 == 6) else "Dance"


# ── every frame ─────────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	if music == null:
		return
	var beats := music.beats()
	var ph := fposmod(beats, 1.0)
	var kick := exp(-ph * 5.0)
	var sec := music.section()
	var energy := {"intro": 0.7, "drop": 1.0, "break": 0.35, "build": 0.8}.get(sec, 1.0) as float
	var bar := music.bar()
	_floor_mat.set_shader_parameter("beats", beats)
	_floor_mat.set_shader_parameter("energy", energy)
	_floor_mat.set_shader_parameter("pattern", (RaveStyle.FLOOR_PATTERNS.find(String(style["floor"])) + bar / 8) % 4)
	var turn := beats * 0.18
	for m in _uv:
		m.set_shader_parameter("beats", beats)
		m.set_shader_parameter("energy", energy)
		m.set_shader_parameter("ball_turn", turn)
	_ball.rotation.y = turn
	# Lights pump on the kick.
	for i in _lights.size():
		(_lights[i] as OmniLight3D).light_energy = (0.35 + 1.0 * kick * energy) if i < 4 else 1.1
	for s in _speakers:
		(s as Node3D).scale = Vector3.ONE * (1.0 + 0.12 * kick)
	for i in _decks.size():
		(_decks[i] as Node3D).rotation.y = beats * PI * (0.5 if i == 0 else -0.5)
	for i in 12:
		var on := fposmod(beats * 2.0 + i * 0.37, 1.0) < 0.5
		_knobs.set_instance_color(i, uv(i) * (2.2 if on else 0.6))
	_update_lasers(beats, energy, sec)
	_update_cones(beats, energy)
	for i in _glow_spots.size():
		_glows.set_instance_color(i, Color(uv(i + bar), 0.35 + 0.5 * kick * energy))
	# The room goes quiet inside a cabinet.
	var diving: bool = host != null and host.get("dive") != null and host.dive.is_active()
	music.set_ducked(diving)
	_update_people(delta, beats, ph)


func _update_lasers(beats: float, energy: float, sec: String) -> void:
	var n := _lasers.instance_count
	var on := sec == "drop" or sec == "build"
	_lasers.visible_instance_count = n if on else 0
	if not on:
		return
	var origin := Vector3(0, 3.3, -hz + 1.0)
	var bar := int(floor(beats / 4.0))
	for i in n:
		var u := (float(i) / maxf(1.0, n - 1)) - 0.5
		var yaw := u * 1.9 + sin(beats * PI * 0.25 + i * 0.6) * 0.35 * (1.0 if bar % 2 == 0 else -1.0)
		var pitch := -0.08 - 0.12 * (0.5 + 0.5 * sin(beats * PI * 0.5 + i))
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
		var length := 26.0
		var b := Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(0.035, 0.035, length))
		_lasers.set_instance_transform(i, Transform3D(b, origin + dir * length * 0.5))
		var flick := 1.0 if fposmod(beats * 2.0 + i * 0.25, 1.0) < 0.7 else 0.25
		_lasers.set_instance_color(i, Color(uv(i + bar), energy * flick))


func _update_cones(beats: float, energy: float) -> void:
	var n := _cones.instance_count
	for i in n:
		var x := lerpf(dance.position.x + 1.0, dance.end.x - 1.0, float(i % 3) / 2.0)
		var z := dance.position.y + 1.5 if i < 3 else dance.end.y - 1.5
		var src := Vector3(x, 4.7, z)
		var sway := sin(beats * PI * 0.25 + i * 1.7) * 0.5
		var dir := Vector3(sway, -1.0, cos(beats * PI * 0.125 + i) * 0.35).normalized()
		var length := 4.9
		var y := -dir
		var xa := y.cross(Vector3.FORWARD).normalized()
		var za := xa.cross(y).normalized()
		var b := Basis(xa * 1.2, y * length, za * 1.2)
		_cones.set_instance_transform(i, Transform3D(b, src + dir * length * 0.5))
		_cones.set_instance_color(i, Color(uv(i), 0.6 + 0.4 * energy))


func _update_people(delta: float, beats: float, ph: float) -> void:
	var player: Node3D = host.player if host and "player" in host else null
	var me := player.global_position if player else Vector3.INF
	var dj_at := dj.global_position if dj else Vector3(0, 0, -hz)
	var dip := -0.035 * exp(-ph * 6.0)  # knees on the kick
	for d in dancers:
		var a: HumanAvatar = d["a"]
		var pos := a.position
		pos.y = 0.0
		# Make way for the player.
		if me != Vector3.INF:
			var away := Vector3(pos.x - me.x, 0, pos.z - me.z)
			if away.length() < AVOID_R:
				var dirv := away.normalized() if away.length() > 0.05 else Vector3.RIGHT
				var t := pos + dirv * 1.3
				d["target"] = Vector3(clampf(t.x, -hx + 1.2, hx - 1.2), 0, clampf(t.z, stage_z + 0.4, hz - 1.0))
				if d["mode"] != "walk":
					d["next"] = d["mode"]
					d["mode"] = "walk"
		match String(d["mode"]):
			"walk":
				var to: Vector3 = d["target"]
				var step := Vector3(to.x - pos.x, 0, to.z - pos.z)
				if step.length() < 0.12:
					d["mode"] = String(d.get("next", "dance"))
					a.hold_clip = "Dance" if d["mode"] == "dance" else "Idle_Talking"
					a.hold_speed = _dance_speed if d["mode"] == "dance" else 1.0
				else:
					var v := step.normalized() * minf(DANCE_SPEED, step.length() * 3.0)
					pos += v * delta
					a.hold_clip = ""
					a.rotation.y = lerp_angle(a.rotation.y, atan2(v.x, v.z), minf(1.0, delta * 8.0))
					a.update_movement(v, true, false)
					a.position = pos
					continue
			"dance":
				var f := dj_at - pos
				a.rotation.y = lerp_angle(a.rotation.y, atan2(f.x, f.z) + sin(beats * 0.5 + float(d["phase"]) * TAU) * 0.6, minf(1.0, delta * 3.0))
			"watch":
				var f2: Vector3 = (d["face"] as Vector3) - pos
				a.rotation.y = lerp_angle(a.rotation.y, atan2(f2.x, f2.z), minf(1.0, delta * 4.0))
		a.update_movement(Vector3.ZERO, true, false)
		a.position = Vector3(pos.x, dip if d["mode"] == "dance" else 0.0, pos.z)
	if dj:
		dj.hold_speed = _dance_speed if dj.hold_clip == "Dance" else 1.0
		dj.update_movement(Vector3.ZERO, true, false)
		var lay := layout(hx, hz)
		dj.position = (lay["dj"] as Vector3) + Vector3(sin(beats * PI * 0.25) * 0.5, dip, 0)
		dj.rotation.y = sin(beats * PI * 0.5) * 0.25
