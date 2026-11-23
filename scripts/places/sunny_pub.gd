extends GamesPlace
## Sunny's Pub, in TehSunFlowrScioety QING (q☀️🌻). You arrive on the street
## facing its front: the neon SUNNY'S PUB sign over the door, suns either
## side, sunflowers in the planters. Inside: the bar, with Sunny (the
## sun-headed goat) pouring behind it; a corner of arcade cabinets (1 Ⓐ a
## play, paid to this QING); the pool table and the card table, played in
## this QING's room lines. Talk to Sunny for what the chain says about the house.

const HX := 10.0
const BACK := -8.0
const FRONT := 8.0  # the facade
const STREET := 17.0

var sunny: Node3D
var _bubble: Label3D
var _bubble_t := 0.0
var _talk_i := 0


func _ready() -> void:
	load_territory()
	floor_y = 0.0
	_environment()
	_street()
	_interior()
	_bar()
	var entries: Array = load("res://scripts/places/arcade_place.gd")._catalog().filter(func(e): return e.get("playable", true) and e.get("kind", "game") != "cartridge")
	for i in mini(3, entries.size()):
		add_cabinet(entries[i], Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-HX + 0.7, 0, -2.6 + i * 1.3)))
	add_pool_table(Transform3D(Basis(), Vector3(4.0, 0, 1.8)))
	add_card_table(Transform3D(Basis(), Vector3(-3.6, 0, 3.2)))
	_sunny()
	exit_at = Vector3(0, 0, STREET - 0.8)
	exit_radius = 2.2
	setup_player(Vector3(0, 0.1, STREET - 3.0), 0.0)
	setup_hud("SUNNY'S PUB · %s" % String(territory.get("name", "")).to_upper())
	info_label.text = "The bar, the arcade (%s a play, to this QING), pool and Twenty-One in this room's lines (T: the chat). Talk to Sunny at the bar." % ArcadePay.fee_text()
	var spots: Array = []
	for i in SpeakerEchoes.MAX:
		var at := Vector3(-4.0 + i * 1.6, 0.0, -3.4)
		spots.append(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP, true), at))
	setup_games(spots)
	add_spot(Vector3(0, 0, BACK + 3.4), 2.0, func(): return "talk to Sunny", _talk)


func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.025, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.6, 0.45)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.1
	we.environment = e
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, -30, 0)
	moon.light_energy = 0.35
	moon.light_color = Color(0.7, 0.75, 1.0)
	add_child(moon)
	Config.register_scene(e, moon)
	for p in [Vector3(-5, 3.4, -4), Vector3(4, 3.4, -4), Vector3(-5, 3.4, 3), Vector3(4, 3.4, 3)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 1.5
		l.omni_range = 9.0
		l.position = p
		add_child(l)


func _street() -> void:
	box(self, Vector3(30, 0.2, STREET - FRONT + 2), Vector3(0, -0.1, (STREET + FRONT) * 0.5), mat(Color(0.16, 0.16, 0.18), 0.9), true)
	box(self, Vector3(30, 0.02, 3.0), Vector3(0, 0.01, FRONT + 1.6), mat(Color(0.3, 0.28, 0.26), 0.85))  # pavement
	var brick := mat(Color(0.42, 0.2, 0.13), 0.9)
	var wood := mat(Color(0.25, 0.13, 0.06), 0.5)
	# The facade with its door, two bay windows lit warm from inside.
	box(self, Vector3(HX - 1.1, 5.0, 0.4), Vector3(-(HX + 1.1) * 0.5, 2.5, FRONT), brick, true)
	box(self, Vector3(HX - 1.1, 5.0, 0.4), Vector3((HX + 1.1) * 0.5, 2.5, FRONT), brick, true)
	box(self, Vector3(2.2, 1.8, 0.4), Vector3(0, 4.1, FRONT), brick)
	box(self, Vector3(2.4, 0.15, 0.5), Vector3(0, 3.2, FRONT), wood)
	var warm := glow(Color(1.0, 0.7, 0.35), 0.9)
	for sx in [-1.0, 1.0]:
		box(self, Vector3(3.0, 1.8, 0.06), Vector3(sx * 4.2, 1.9, FRONT + 0.21), warm)
		box(self, Vector3(3.3, 0.14, 0.3), Vector3(sx * 4.2, 2.85, FRONT + 0.25), wood)
		box(self, Vector3(3.3, 0.14, 0.3), Vector3(sx * 4.2, 0.95, FRONT + 0.25), wood)
		_planter(Vector3(sx * 4.2, 0, FRONT + 0.75))
	var sign := Label3D.new()
	sign.text = "SUNNY'S PUB"
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 150
	sign.pixel_size = 0.011
	sign.outline_size = 20
	sign.outline_modulate = Color(0.2, 0.05, 0.0, 0.9)
	sign.modulate = Color(1.0, 0.8, 0.25)
	sign.position = Vector3(0, 4.35, FRONT + 0.25)
	add_child(sign)
	var tag := Label3D.new()
	tag.text = "est. on PulseChain · arcade · pool · cards"
	tag.font = DeepFieldTheme.mono_font()
	tag.font_size = 40
	tag.pixel_size = 0.009
	tag.modulate = Color(1.0, 0.9, 0.7)
	tag.position = Vector3(0, 3.55, FRONT + 0.25)
	add_child(tag)
	for sx in [-1.0, 1.0]:
		_sun(Vector3(sx * 7.6, 4.2, FRONT + 0.25), 0.55)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.35)
	lamp.light_energy = 2.5
	lamp.omni_range = 10.0
	lamp.position = Vector3(0, 4.0, FRONT + 2.0)
	add_child(lamp)
	var back := Label3D.new()
	back.text = "BACK TO %s" % String(territory.get("name", "")).to_upper()
	back.font = DeepFieldTheme.mono_font()
	back.font_size = 36
	back.pixel_size = 0.01
	back.modulate = DeepFieldTheme.ICE
	back.position = Vector3(0, 2.6, STREET)
	back.rotation_degrees.y = 180.0
	add_child(back)
	box(self, Vector3(3.0, 0.06, 0.06), Vector3(0, 0.03, STREET - 0.2), glow(DeepFieldTheme.ICE, 2.0))
	# Keep people on the street.
	for sx in [-1.0, 1.0]:
		box(self, Vector3(0.2, 2.0, STREET - FRONT + 1), Vector3(sx * 7.5, 1.0, (STREET + FRONT) * 0.5 + 0.5), mat(Color(0.1, 0.1, 0.12)), true)
	box(self, Vector3(16, 2.0, 0.2), Vector3(0, 1.0, STREET + 0.6), mat(Color(0.1, 0.1, 0.12)), true)


func _planter(at: Vector3) -> void:
	box(self, Vector3(2.6, 0.5, 0.5), at + Vector3(0, 0.25, 0), mat(Color(0.28, 0.15, 0.08), 0.8), true)
	for i in 4:
		var x := -0.9 + i * 0.6
		var stem := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.025
		cm.height = 1.1 + 0.15 * (i % 2)
		stem.mesh = cm
		stem.material_override = mat(Color(0.2, 0.45, 0.12))
		stem.position = at + Vector3(x, 0.5 + cm.height * 0.5, 0)
		add_child(stem)
		_sunflower(at + Vector3(x, 0.5 + cm.height, 0.05))


func _sunflower(at: Vector3) -> void:
	var petal := mat(Color(1.0, 0.78, 0.1), 0.7)
	for k in 12:
		var a := TAU * k / 12.0
		var p := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		p.mesh = sm
		p.material_override = petal
		p.scale = Vector3(0.45, 1.0, 0.2)
		p.position = at + Vector3(cos(a) * 0.1, sin(a) * 0.1, 0)
		p.rotation.z = a - PI * 0.5
		add_child(p)
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 0.03
	c.mesh = cm
	c.material_override = mat(Color(0.25, 0.14, 0.05))
	c.rotation_degrees.x = 90.0
	c.position = at + Vector3(0, 0, 0.01)
	add_child(c)


func _sun(at: Vector3, r: float) -> void:
	var gold := glow(Color(1.0, 0.8, 0.2), 2.6)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.05
	disc.mesh = cm
	disc.material_override = gold
	disc.rotation_degrees.x = 90.0
	disc.position = at
	add_child(disc)
	for i in 12:
		var a := TAU * i / 12.0
		box(self, Vector3(0.08, r * 0.6, 0.04), at + Vector3(cos(a) * r * 1.55, sin(a) * r * 1.55, 0), gold).rotation.z = a - PI * 0.5


func _interior() -> void:
	box(self, Vector3(HX * 2, 0.2, FRONT - BACK), Vector3(0, -0.1, (FRONT + BACK) * 0.5), mat(Color(0.3, 0.17, 0.08), 0.55), true)  # floorboards
	for i in 16:
		box(self, Vector3(HX * 2, 0.005, 0.02), Vector3(0, 0.003, BACK + 0.5 + i), mat(Color(0.2, 0.1, 0.04)))
	var wall := mat(Color(0.4, 0.22, 0.12), 0.85)
	var panel := mat(Color(0.22, 0.11, 0.05), 0.5)
	box(self, Vector3(HX * 2, 5.0, 0.3), Vector3(0, 2.5, BACK), wall, true)
	box(self, Vector3(0.3, 5.0, FRONT - BACK), Vector3(-HX, 2.5, 0), wall, true)
	box(self, Vector3(0.3, 5.0, FRONT - BACK), Vector3(HX, 2.5, 0), wall, true)
	for sx in [-1.0, 1.0]:  # wood wainscot
		box(self, Vector3(0.05, 1.1, FRONT - BACK), Vector3(sx * (HX - 0.17), 0.55, 0), panel)
	box(self, Vector3(HX * 2, 0.2, FRONT - BACK), Vector3(0, 5.1, 0), mat(Color(0.15, 0.08, 0.04)))
	for i in 4:  # beams
		box(self, Vector3(HX * 2, 0.25, 0.3), Vector3(0, 4.85, BACK + 2.0 + i * 4.0), panel)
	# Sunflowers painted on the side wall, and a big sun over the bar.
	for i in 3:
		_sunflower(Vector3(HX - 0.2, 2.6, -2.0 + i * 3.0))
	_sun(Vector3(0, 3.9, BACK + 0.2), 0.5)


func _bar() -> void:
	var wood := mat(Color(0.3, 0.15, 0.06), 0.35)
	var top := mat(Color(0.18, 0.09, 0.04), 0.2, 0.1)
	var brass := mat(Color(0.85, 0.65, 0.3), 0.25, 0.9)
	box(self, Vector3(9.0, 1.1, 0.8), Vector3(0, 0.55, BACK + 2.6), wood, true)
	box(self, Vector3(9.3, 0.08, 1.0), Vector3(0, 1.14, BACK + 2.6), top)
	box(self, Vector3(9.0, 0.05, 0.05), Vector3(0, 0.2, BACK + 3.05), brass)  # foot rail
	for i in 4:  # taps
		var tap := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 0.35
		tap.mesh = cm
		tap.material_override = brass
		tap.position = Vector3(-1.2 + i * 0.8, 1.35, BACK + 2.4)
		add_child(tap)
	# Shelves of bottles on the back wall.
	var colors := [Color(0.2, 0.5, 0.2, 0.85), Color(0.55, 0.3, 0.1, 0.85), Color(0.7, 0.7, 0.75, 0.7), Color(0.6, 0.15, 0.2, 0.85)]
	for row in 3:
		box(self, Vector3(8.0, 0.06, 0.4), Vector3(0, 1.4 + row * 0.6, BACK + 0.35), wood)
		for k in 16:
			var b := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.045
			cm.height = 0.3
			b.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = colors[(k + row) % colors.size()]
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.1
			m.metallic = 0.3
			b.material_override = m
			b.position = Vector3(-3.7 + k * 0.49, 1.58 + row * 0.6, BACK + 0.35)
			add_child(b)
	var shelf_light := OmniLight3D.new()
	shelf_light.light_color = Color(1.0, 0.8, 0.5)
	shelf_light.light_energy = 1.2
	shelf_light.omni_range = 5.0
	shelf_light.position = Vector3(0, 2.6, BACK + 1.2)
	add_child(shelf_light)
	for i in 6:  # stools
		var x := -3.5 + i * 1.4
		var seat := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.2
		cm.height = 0.08
		seat.mesh = cm
		seat.material_override = mat(Color(0.5, 0.08, 0.06), 0.6)
		seat.position = Vector3(x, 0.75, BACK + 3.6)
		add_child(seat)
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.04
		lm.bottom_radius = 0.16
		lm.height = 0.72
		leg.mesh = lm
		leg.material_override = brass
		leg.position = Vector3(x, 0.36, BACK + 3.6)
		add_child(leg)


func _sunny() -> void:
	sunny = Node3D.new()
	sunny.set_script(load("res://scripts/player/human_avatar.gd"))
	sunny.name = "Sunny"
	add_child(sunny)
	sunny.position = Vector3(0, 0.32, BACK + 1.6)  # on the duckboard behind the bar
	box(self, Vector3(8.6, 0.3, 1.2), Vector3(0, 0.15, BACK + 1.5), mat(Color(0.22, 0.11, 0.05), 0.6), true)
	sunny.set_head("sunny")
	sunny.set_suit_colors(Color(0.92, 0.9, 0.84), Color(0.45, 0.28, 0.14))
	var h := sunny.find_child("Head_sunny", true, false)
	if h:
		(h as Node3D).scale = Vector3.ONE * 1.35  # a big sunny head, as on the sign
	_bubble = Label3D.new()
	_bubble.font = DeepFieldTheme.body_font()
	_bubble.font_size = 30
	_bubble.pixel_size = 0.005
	_bubble.width = 900.0
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.outline_size = 10
	_bubble.outline_modulate = Color(0.1, 0.05, 0.0, 0.9)
	_bubble.modulate = Color(1.0, 0.93, 0.7)
	_bubble.position = Vector3(0, 3.35, BACK + 2.3)
	_bubble.text = "Welcome to Sunny's! Press %s at the bar." % ControlsHelp.key_of("interact")
	add_child(_bubble)


## Sunny says what the chain says: the house's Ⓐ, the room's games, who owes.
func _talk() -> void:
	_talk_i += 1
	_bubble_t = 10.0
	match _talk_i % 4:
		1:
			_bubble.text = "Sunny: reading the till…"
			var r := await ArcadePay.read_balance(qing)
			_bubble.text = ("Sunny: this QING holds %s right now (AFFECTION.balanceOf, latest block). Every play on those cabinets adds %s." % [ArcadePay.fmt(r["balance"]), ArcadePay.fee_text()]) if r["ok"] else "Sunny: the till won't read just now: —"
		2:
			var live := book.matches.filter(func(m): return m["status"] == "playing").size()
			var open := book.matches.filter(func(m): return m["status"] == "open").size()
			_bubble.text = "Sunny: %d game%s on, %d challenge%s waiting, all in this room's lines. Grab a cue or a seat." % [live, "" if live == 1 else "s", open, "" if open == 1 else "s"]
		3:
			var owed: Array = book.debts().filter(func(d): return d["match"]["paid"] == false)
			if owed.is_empty():
				_bubble.text = "Sunny: nobody owes anybody here, as far as the chain shows. Keep it that way."
			else:
				var d: Dictionary = owed[0]
				_bubble.text = "Sunny: %s still owes %s %s from game #%s. The chain remembers, friend." % [book.display(d["loser"]), book.display(d["winner"]), ArcadePay.fmt(d["stake"]), d["match"]["id"]]
		0:
			_bubble.text = "Sunny: what'll it be? The drinks are on the house. The games are on the chain."


func _process(delta: float) -> void:
	super._process(delta)
	if _bubble_t > 0.0:
		_bubble_t -= delta
	if sunny:
		# Sunny turns to whoever's at the bar.
		if player and player.global_position.distance_to(sunny.global_position) < 6.0:
			var to := player.global_position - sunny.global_position
			sunny.rotation.y = lerp_angle(sunny.rotation.y, atan2(to.x, to.z), delta * 3.0)
		else:
			sunny.rotation.y = lerp_angle(sunny.rotation.y, 0.0, delta * 2.0)
