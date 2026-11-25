extends GamesPlace
## The territory's arcade, off the plaza: a blacklight party (RaveHall, 2026-11-25). UV paint on dark
## walls, a dance floor that changes on every beat, lasers and spot cones through the haze, a DJ on
## the decks and a crowd dancing to a synthesised track (RaveMusic), all in this QING's colours and
## tempo (RaveStyle: from the territory, never the viewer). Every game in the catalog stands in a
## cabinet along the side walls (1 Ⓐ a play, paid to this QING); the pool table and the card table by
## the door (games in this QING's room lines), the room's chat on T, and the door back out.

const HX := 12.0
const HZ := 10.0

var rave: RaveHall


func _ready() -> void:
	load_territory()
	floor_y = 0.0
	_environment()
	var entries: Array = _catalog()
	var left := entries.slice(0, (entries.size() + 1) / 2)
	var right := entries.slice((entries.size() + 1) / 2)
	for i in left.size():
		add_cabinet(left[i], Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-HX + 0.7, 0, -6.6 + i * 1.25)))
	for i in right.size():
		add_cabinet(right[i], Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(HX - 0.7, 0, -6.6 + i * 1.25)))
	rave = RaveHall.new()
	add_child(rave)
	rave.build(self, territory, HX, HZ)
	_fixtures()
	add_pool_table(Transform3D(Basis(), Vector3(-5.6, 0, 5.4)), Color(0.12, 0.1, 0.45))
	add_card_table(Transform3D(Basis(), Vector3(5.8, 0, 5.4)))
	exit_at = Vector3(0, 0, HZ - 0.6)
	exit_radius = 1.8
	setup_player(Vector3(0, 0.1, HZ - 2.6), 0.0)
	add_door("slide", 2.4, 3.2, Vector3(0, 0, HZ))
	setup_hud("THE ARCADE · %s" % String(territory.get("name", "")).to_upper())
	info_label.text = "Cabinets: %s (one approval), paid to this QING and checked on chain before the run. Pool and Twenty-One are played in this room's lines (T opens the chat). DJ set: %d BPM, synthesised here." % [Prices.menu_line(), int(rave.style["bpm"])]
	var spots: Array = []
	for i in SpeakerEchoes.MAX:
		# Two rows of three either side of the entrance lane: you walk in between them, not into them.
		var k := i % 3
		var at := Vector3((2.2 + k * 1.4) * (-1.0 if i < 3 else 1.0), 0.0, HZ - 1.5)
		spots.append(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP, true), at))
	setup_games(spots)
	# Nothing in here casts a sun shadow but the player (a dark club: the lights are the point).
	for gi in find_children("*", "GeometryInstance3D", true, false):
		if not player.is_ancestor_of(gi):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_view()


# --- Fixed views for tools/screenshot.gd (--view=rave|dj|dancers|cabinets|cabinets_far|tables) ---

const VIEWS := {
	"rave": [Vector3(0.0, 3.4, 9.2), Vector3(0.0, 1.4, -6.0)],
	"dj": [Vector3(1.0, 2.1, -4.4), Vector3(0.0, 1.5, -8.4)],
	"dancers": [Vector3(-5.5, 1.7, 2.6), Vector3(1.0, 1.0, -4.0)],
	"cabinets": [Vector3(1.0, 1.7, -0.5), Vector3(-11.3, 1.9, -2.5)],
	"cabinets_far": [Vector3(10.0, 1.7, 2.0), Vector3(-11.3, 1.9, -2.0)],
	"tables": [Vector3(0.0, 3.0, 9.0), Vector3(0.0, 0.6, 4.0)],
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
	e.background_color = Color(0.004, 0.002, 0.01)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = RaveStyle.BLACKLIGHT  # blacklight: everything lit faintly violet
	e.ambient_light_energy = 0.32
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 1.0
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.9
	# Haze: the lasers and the cones read through it.
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.05, 0.22)
	e.fog_light_energy = 0.6
	e.fog_density = 0.018
	e.fog_sky_affect = 0.0
	we.environment = e
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-70, 20, 0)
	key.light_energy = 0.08
	key.light_color = RaveStyle.BLACKLIGHT
	add_child(key)
	Config.register_scene(e, key)


## The credits counter by the door and the signs (the QING's name on the way out).
func _fixtures() -> void:
	var c0: Color = rave.uv(0)
	box(self, Vector3(3.0, 1.05, 0.7), Vector3(-8.2, 0.525, HZ - 1.4), mat(Color(0.03, 0.025, 0.05), 0.4, 0.4), true)
	box(self, Vector3(3.0, 0.05, 0.75), Vector3(-8.2, 1.07, HZ - 1.4), glow(accent, 1.6))
	box(self, Vector3(3.0, 0.04, 0.02), Vector3(-8.2, 0.12, HZ - 1.04), glow(c0, 2.2))
	var sign := Label3D.new()
	sign.text = "Ⓐ CREDITS\n%s a play · goes to this QING\nstrip of %d: %s" % [ArcadePay.fee_text(), Prices.STRIP_PLAYS, Prices.strip_text()]
	sign.font = DeepFieldTheme.display_font()
	sign.font_size = 56
	sign.pixel_size = 0.008
	sign.modulate = c0.lerp(Color.WHITE, 0.35)
	sign.outline_size = 10
	sign.outline_modulate = Color(0, 0, 0, 0.8)
	sign.position = Vector3(-8.2, 3.0, HZ - 0.2)
	sign.rotation_degrees.y = 180.0
	add_child(sign)
	box(self, Vector3(2.6, 0.08, 0.1), Vector3(0, 3.2, HZ - 0.2), glow(DeepFieldTheme.ICE, 2.5))
	var out := Label3D.new()
	out.text = "OUT TO %s" % String(territory.get("name", "")).to_upper()
	out.font = DeepFieldTheme.mono_font()
	out.font_size = 32
	out.pixel_size = 0.008
	out.modulate = DeepFieldTheme.ICE
	out.position = Vector3(0, 3.45, HZ - 0.2)
	out.rotation_degrees.y = 180.0
	add_child(out)

