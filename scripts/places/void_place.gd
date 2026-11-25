extends PlaceBase
## The Void: one board for everyone (Fomalhaute's LogEvent lines, written by
## LAU.Chat). You stand on a glass platform in open space with the monolith at
## its heart; the lines drift around you in slow rings, the newest closest and
## brightest, each with its block. Echoes of the latest speakers stand at the
## rim. A portal at the edge takes you back to the territory you came from.

const PLATFORM_R := 9.0
const RINGS := [[12.5, 2.0, 6], [19.0, 4.2, 8], [27.0, 7.5, 10]]  # radius, height, how many lines

var _line_nodes: Array = []  # Label3D, newest first
var _spin := 0.0
var _ring_root: Node3D
var _mono: VoidMonolith


func _ready() -> void:
	floor_y = 0.0
	if GameManager.territory_name == "" and GameManager.territory_address != "":
		GameManager.territory_name = String(Registry.get_territory(GameManager.territory_address).get("name", ""))
	_environment()
	_platform()
	_mono = VoidMonolith.new()
	_mono.name = "Monolith"
	add_child(_mono)
	_mono.build()
	_mono.position = Vector3(0, 0, -3)
	_portal()
	_ring_root = Node3D.new()
	add_child(_ring_root)
	_collisions()
	exit_at = Vector3(0, 0, PLATFORM_R - 1.2)
	setup_player(Vector3(0, 0.1, 3.5), 0.0)
	add_door("curtain", 2.9, 2.9, Vector3(0, 0.25, PLATFORM_R - 0.4), DeepFieldTheme.ICE, true, false)  # open space: no wall to stop the camera at
	exit_radius = 2.0
	setup_hud("THE VOID")
	info_label.text = "One board for everyone: Fomalhaute's lines from block %d, written by LAU.Chat. Reading…" % Contracts.VOID_CHAT_FROM_BLOCK
	setup_chat("void", {})
	var rim: Array = []
	for i in SpeakerEchoes.MAX:
		var a := deg_to_rad(lerpf(200.0, 340.0, float(i) / float(SpeakerEchoes.MAX - 1)))
		var at := Vector3(cos(a) * (PLATFORM_R - 1.6), 0.0, sin(a) * (PLATFORM_R - 1.6))
		rim.append(Transform3D(Basis.looking_at(-at, Vector3.UP, true), at))
	echoes.spots = rim
	chat_ctl.lines_changed.connect(func(ls, _f): info_label.text = "One board for everyone: %d lines read from Fomalhaute's logs. Names are not unique: ✓ OG and ⚠ imposter compare the speaker's Aura." % ls.size())


func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/void_sky.gdshader")
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.4, 0.7)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 1.1
	e.glow_bloom = 0.15
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.05, 0.16)
	e.fog_density = 0.012
	e.fog_sky_affect = 0.0
	we.environment = e
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 30, 0)
	key.light_energy = 0.4
	key.light_color = Color(0.7, 0.65, 1.0)
	add_child(key)
	Config.register_scene(e, key)
	var under := OmniLight3D.new()
	under.position = Vector3(0, -2.0, 0)
	under.omni_range = 18.0
	under.light_color = Color(0.5, 0.3, 1.0)
	under.light_energy = 2.0
	add_child(under)
	# Motes drifting up from the abyss.
	var motes := GPUParticles3D.new()
	motes.amount = Shares.particles(400)
	motes.lifetime = 14.0
	motes.preprocess = 14.0
	motes.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 2, 35)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	motes.process_material = pm
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.7, 0.6, 1.0)
	dm.emission_enabled = true
	dm.emission = Color(0.7, 0.6, 1.0)
	dm.emission_energy_multiplier = 2.0
	dot.material = dm
	motes.draw_pass_1 = dot
	motes.position = Vector3(0, -25, 0)
	add_child(motes)


func _platform() -> void:
	var disc := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = PLATFORM_R
	c.bottom_radius = PLATFORM_R * 0.92
	c.height = 0.4
	c.radial_segments = 64
	disc.mesh = c
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.04, 0.035, 0.07, 0.82)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.6
	glass.roughness = 0.08
	glass.rim_enabled = true
	glass.rim = 0.6
	disc.material_override = glass
	disc.position = Vector3(0, -0.2, 0)
	add_child(disc)
	var rim := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = PLATFORM_R - 0.06
	t.outer_radius = PLATFORM_R + 0.06
	t.rings = 96
	rim.mesh = t
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.6, 0.5, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.6, 0.5, 1.0)
	rm.emission_energy_multiplier = 2.4
	rim.material_override = rm
	add_child(rim)
	# Concentric etched rings on the glass.
	for r in [3.0, 5.5]:
		var ring := MeshInstance3D.new()
		var tt := TorusMesh.new()
		tt.inner_radius = r - 0.02
		tt.outer_radius = r + 0.02
		tt.rings = 64
		ring.mesh = tt
		var m := rm.duplicate() as StandardMaterial3D
		m.emission_energy_multiplier = 0.7
		ring.material_override = m
		ring.position.y = 0.01
		add_child(ring)


func _portal() -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.45
	t.outer_radius = 1.6
	t.rings = 64
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = DeepFieldTheme.ICE
	m.emission_enabled = true
	m.emission = DeepFieldTheme.ICE
	m.emission_energy_multiplier = 2.5
	ring.material_override = m
	ring.rotation_degrees.x = 90.0
	ring.position = Vector3(0, 1.7, PLATFORM_R - 0.4)
	add_child(ring)
	var lab := Label3D.new()
	lab.text = "BACK TO %s" % GameManager.territory_name.to_upper()
	lab.font = DeepFieldTheme.mono_font()
	lab.font_size = 36
	lab.pixel_size = 0.01
	lab.position = Vector3(0, 3.6, PLATFORM_R - 0.4)
	lab.rotation_degrees.y = 180.0
	lab.modulate = DeepFieldTheme.ICE
	add_child(lab)


func on_lines(lines: Array, _fresh: Array) -> void:
	for n in _line_nodes:
		(n as Node).queue_free()
	_line_nodes.clear()
	if not lines.is_empty():
		_mono.show_line(lines[-1])
	var newest: Array = lines.slice(maxi(0, lines.size() - 24))
	newest.reverse()
	var idx := 0
	for ring in RINGS:
		var r: float = ring[0]
		var h: float = ring[1]
		var n: int = ring[2]
		for k in n:
			if idx >= newest.size():
				return
			var l: Dictionary = newest[idx]
			var a := TAU * float(k) / float(n) + float(RINGS.find(ring)) * 0.4
			var lab := Label3D.new()
			lab.font = DeepFieldTheme.mono_font()
			lab.font_size = 30
			lab.pixel_size = 0.006 + r * 0.00035
			lab.width = 520.0
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.outline_size = 8
			lab.outline_modulate = Color(0, 0, 0, 0.7)
			var fade := 1.0 - float(idx) / 28.0
			lab.modulate = Color(0.78, 0.72, 1.0, clampf(fade, 0.25, 1.0))
			var badge := " ✓" if l.get("badge", "") == "og" else (" ⚠" if l.get("badge", "") == "imposter" else "")
			lab.text = "%s%s\n%s\nblock %d" % [l["name"] if l["name"] != "" else "?", badge, String(l["text"]).left(70), l["block"]]
			lab.position = Vector3(cos(a) * r, h + 0.4 * sin(a * 3.0), sin(a) * r)
			_ring_root.add_child(lab)
			_line_nodes.append(lab)
			idx += 1


func _process(delta: float) -> void:
	super._process(delta)
	_spin += delta * 0.025
	if _ring_root:
		_ring_root.rotation.y = _spin


func _collisions() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = PLATFORM_R
	sh.height = 0.4
	cs.shape = sh
	cs.position = Vector3(0, -0.2, 0)
	body.add_child(cs)
	# A low invisible rail so you don't walk off by accident (you can still jump).
	for i in 32:
		var a := TAU * i / 32.0
		var w := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(1.9, 1.0, 0.2)
		w.shape = b
		w.position = Vector3(cos(a) * (PLATFORM_R + 0.1), 0.5, sin(a) * (PLATFORM_R + 0.1))
		w.rotation.y = -a + PI * 0.5
		body.add_child(w)
