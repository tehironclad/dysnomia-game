extends GamesPlace
## The territory's arcade, a neon hall off the plaza: every game in the
## catalog in a cabinet along the walls (1 Ⓐ a play, paid to this QING), the
## pool table and the card table in the middle (games in this QING's room
## lines), the room's chat on T, and the door back out.

const HX := 12.0
const HZ := 8.0


func _ready() -> void:
	load_territory()
	floor_y = 0.0
	_environment()
	_shell()
	var entries: Array = _catalog()
	var left := entries.slice(0, (entries.size() + 1) / 2)
	var right := entries.slice((entries.size() + 1) / 2)
	for i in left.size():
		add_cabinet(left[i], Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-HX + 0.7, 0, -5.6 + i * 1.25)))
	for i in right.size():
		add_cabinet(right[i], Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(HX - 0.7, 0, -5.6 + i * 1.25)))
	add_pool_table(Transform3D(Basis(), Vector3(-1.5, 0, -3.6)), Color(0.12, 0.1, 0.45))
	add_card_table(Transform3D(Basis(), Vector3(4.2, 0, 2.0)))
	exit_at = Vector3(0, 0, HZ - 0.6)
	exit_radius = 1.8
	setup_player(Vector3(0, 0.1, HZ - 2.6), 0.0)
	add_door("slide", 2.4, 3.2, Vector3(0, 0, HZ))
	setup_hud("THE ARCADE · %s" % String(territory.get("name", "")).to_upper())
	info_label.text = "Cabinets: %s (one approval), paid to this QING and checked on chain before the run. Pool and Twenty-One are played in this room's lines (T opens the chat)." % Prices.menu_line()
	var spots: Array = []
	for i in SpeakerEchoes.MAX:
		# Two rows of three either side of the entrance lane: you walk in between them, not into them.
		var k := i % 3
		var at := Vector3((2.8 + k * 2.4) * (-1.0 if i < 3 else 1.0), 0.0, 4.9)
		spots.append(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP, true), at))
	setup_games(spots)
	_apply_view()


# --- Fixed views for tools/screenshot.gd (--view=cabinets|cabinets_right|tables) ---

const VIEWS := {
	"cabinets": [Vector3(1.0, 1.7, 0.5), Vector3(-11.3, 1.9, -1.5)],
	"cabinets_far": [Vector3(10.0, 1.7, 0.5), Vector3(-11.3, 1.9, -1.0)],
	"tables": [Vector3(0.0, 3.0, 6.5), Vector3(0.5, 0.6, -2.0)],
}


func _apply_view() -> void:
	var view := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.substr(7)
	if not VIEWS.has(view):
		return
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.look_at_from_position(VIEWS[view][0], VIEWS[view][1])
	cam.current = true


static func _catalog() -> Array:
	var path := "res://scripts/arcade/arcade_catalog.gd"
	if not ResourceLoader.exists(path):
		return []
	return load(path).games()


func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.005, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.4, 0.65)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.1
	we.environment = e
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-70, 20, 0)
	key.light_energy = 0.25
	add_child(key)
	Config.register_scene(e, key)
	var cols := [Color(1.0, 0.25, 0.7), Color(0.3, 0.8, 1.0), accent, Color(0.7, 0.4, 1.0)]
	for i in 4:
		var l := OmniLight3D.new()
		l.light_color = cols[i]
		l.light_energy = 1.6
		l.omni_range = 11.0
		l.position = Vector3(-8.0 + i * 5.3, 3.6, -1.0 + (i % 2) * 3.0)
		add_child(l)


func _shell() -> void:
	var floor_mat := mat(Color(0.05, 0.03, 0.08), 0.85)
	box(self, Vector3(HX * 2, 0.2, HZ * 2), Vector3(0, -0.1, 0), floor_mat, true)
	# Neon inlay on the carpet: a grid of thin glowing lines.
	var line := glow(Color(0.5, 0.25, 1.0), 1.2)
	for i in 7:
		box(self, Vector3(HX * 2 - 1.0, 0.01, 0.04), Vector3(0, 0.005, -HZ + 1.6 + i * 2.2), line)
	var wall := mat(Color(0.07, 0.06, 0.1), 0.6, 0.2)
	box(self, Vector3(HX * 2, 4.5, 0.3), Vector3(0, 2.25, -HZ), wall, true)
	box(self, Vector3(0.3, 4.5, HZ * 2), Vector3(-HX, 2.25, 0), wall, true)
	box(self, Vector3(0.3, 4.5, HZ * 2), Vector3(HX, 2.25, 0), wall, true)
	# Front wall with the door gap, the way you came in.
	box(self, Vector3(HX - 1.2, 4.5, 0.3), Vector3(-(HX + 1.2) * 0.5, 2.25, HZ), wall, true)
	box(self, Vector3(HX - 1.2, 4.5, 0.3), Vector3((HX + 1.2) * 0.5, 2.25, HZ), wall, true)
	box(self, Vector3(2.4, 1.3, 0.3), Vector3(0, 3.85, HZ), wall)
	box(self, Vector3(2.6, 0.08, 0.1), Vector3(0, 3.2, HZ - 0.2), glow(DeepFieldTheme.ICE, 2.5))
	box(self, Vector3(HX * 2, 0.2, HZ * 2), Vector3(0, 4.6, 0), mat(Color(0.03, 0.03, 0.05)))
	# Ceiling light strips and a wall-wash band in pink and cyan.
	for i in 3:
		box(self, Vector3(HX * 2 - 2.0, 0.06, 0.18), Vector3(0, 4.45, -5.0 + i * 5.0), glow(Color(1.0, 0.3, 0.75) if i % 2 == 0 else Color(0.3, 0.85, 1.0), 2.2))
	for sx in [-1.0, 1.0]:
		box(self, Vector3(0.05, 0.08, HZ * 2 - 1.0), Vector3(sx * (HX - 0.18), 2.4, 0), glow(Color(1.0, 0.3, 0.75), 2.0))
	# The credits counter by the door.
	box(self, Vector3(3.0, 1.05, 0.7), Vector3(-7.5, 0.525, HZ - 1.6), mat(Color(0.12, 0.1, 0.16), 0.4, 0.4), true)
	box(self, Vector3(3.0, 0.05, 0.75), Vector3(-7.5, 1.07, HZ - 1.6), glow(accent, 1.4))
	var sign := Label3D.new()
	sign.text = "Ⓐ CREDITS\n%s a play · goes to this QING\nstrip of %d: %s" % [ArcadePay.fee_text(), Prices.STRIP_PLAYS, Prices.strip_text()]
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 56
	sign.pixel_size = 0.008
	sign.modulate = Color(1.0, 0.6, 0.85)
	sign.position = Vector3(-7.5, 3.0, HZ - 0.2)
	sign.rotation_degrees.y = 180.0
	add_child(sign)
	var back := Label3D.new()
	back.text = "ARCADE"
	back.font = DeepFieldTheme.display_font()
	back.font_size = 160
	back.pixel_size = 0.012
	back.modulate = accent.lerp(Color(1.0, 0.3, 0.8), 0.5)
	back.outline_size = 16
	back.outline_modulate = Color(0, 0, 0, 0.8)
	back.position = Vector3(0, 3.3, -HZ + 0.2)
	add_child(back)
	var out := Label3D.new()
	out.text = "OUT TO %s" % String(territory.get("name", "")).to_upper()
	out.font = DeepFieldTheme.mono_font()
	out.font_size = 32
	out.pixel_size = 0.008
	out.modulate = DeepFieldTheme.ICE
	out.position = Vector3(0, 3.45, HZ - 0.2)
	out.rotation_degrees.y = 180.0
	add_child(out)
