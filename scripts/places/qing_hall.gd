extends PlaceBase
## Inside a QING: its chat hall. Built from the Modular Sci-Fi MegaKit
## (Quaternius, CC0) on its 4 m grid: a 5×5-cell chamber with rounded
## corners, columns, wall lights and the door you came through. The back wall
## is the board: the room's own LogEvent lines (this QING's logs only), live.
## The territory's Julia set is inlaid in the floor; echoes of the latest
## speakers stand before the board.

const CELL := 4.0
const HALF := 10.0  # walls at ±10 m

var territory: Dictionary = {}
var _board_text: RichTextLabel
var _board_vp: SubViewport


func _ready() -> void:
	var addr := GameManager.territory_address
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			addr = a.substr(7)
	territory = Registry.get_territory(addr)
	if territory.is_empty():
		territory = Registry.all()[0] if Registry.count() > 0 else {}
	GameManager.territory_address = String(territory.get("address", ""))
	GameManager.territory_name = String(territory.get("name", ""))
	_environment()
	_build_shell()
	_build_board()
	_build_emblem()
	_collisions()
	exit_at = Vector3(0, 0, HALF - 0.8)
	setup_player(Vector3(0, 0.1, HALF - 4.5), 0.0)
	add_door("slide", 3.6, 3.4, Vector3(0, 0, HALF - 0.05))
	exit_radius = 2.0
	setup_hud("THE ROOM · %s" % String(territory.get("name", "")).to_upper())
	info_label.text = "Lines on the board are this QING's own LogEvent logs, read from the chain. Reading the door…"
	setup_chat("room", territory)
	var arc: Array = []
	for i in SpeakerEchoes.MAX:
		var a := deg_to_rad(lerpf(205.0, 335.0, float(i) / float(SpeakerEchoes.MAX - 1)))
		var at := Vector3(cos(a) * 5.4, 0.0, sin(a) * 5.4 + 0.5)
		var xf := Transform3D(Basis.looking_at(Vector3(0, 0, 3) - at, Vector3.UP, true), at)
		arc.append(xf)
	echoes.spots = arc
	var t := Timer.new()
	t.wait_time = 3.0
	t.timeout.connect(func():
		if chat_ctl.room and chat_ctl.room.ok:
			info_label.text = chat_ctl.room.describe().replace("\n", " · "))
	add_child(t)
	t.start()


func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.7)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.08
	e.ssao_enabled = true
	we.environment = e
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-60, 20, 0)
	key.light_energy = 0.35
	key.light_color = Color(0.75, 0.82, 1.0)
	add_child(key)
	Config.register_scene(e, key)
	var tint := DeepField.to_color(DeepField.for_territory(territory)["color"]) if not territory.is_empty() else DeepFieldTheme.ICE
	for p in [Vector3(-6, 4.2, -6), Vector3(6, 4.2, -6), Vector3(-6, 4.2, 6), Vector3(6, 4.2, 6), Vector3(0, 4.5, 0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.omni_range = 13.0
		l.light_energy = 1.3
		l.light_color = Color(0.85, 0.9, 1.0).lerp(tint, 0.35)
		l.shadow_enabled = p.x == 0.0
		add_child(l)


func _put(piece: String, at: Vector3, yaw_deg: float) -> Node3D:
	var n := load_piece(piece)
	n.position = at
	n.rotation_degrees.y = yaw_deg
	add_child(n)
	return n


func _build_shell() -> void:
	# Floor: metal plates, darker plates on the ring, the centre left for the emblem.
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			var at := Vector3(ix * CELL, 0, iz * CELL)
			_put("Platform_Metal" if absi(ix) == 2 or absi(iz) == 2 else "Platform_DarkPlates", at, 0.0)
	# Walls: W (yaw 0), N (-90), E (180), S (90); the middle of S is the door.
	var sides := [[Vector3(-8, 0, 0), Vector3(0, 0, 1), 0.0], [Vector3(0, 0, -8), Vector3(1, 0, 0), -90.0],
		[Vector3(8, 0, 0), Vector3(0, 0, 1), 180.0], [Vector3(0, 0, 8), Vector3(1, 0, 0), 90.0]]
	for si in sides.size():
		var s: Array = sides[si]
		for k in [-1, 0, 1]:
			var at: Vector3 = s[0] + s[1] * (k * CELL)
			if si == 3 and k == 0:
				continue
			var piece := "WallAstra_Straight_Window" if (si == 0 or si == 2) and k == 0 else "WallAstra_Straight"
			_put(piece, at, s[2])
			_put("TopAstra_Straight", at, s[2])
	for c in [[Vector3(-6, 0, -6), 0.0], [Vector3(6, 0, -6), -90.0], [Vector3(6, 0, 6), 180.0], [Vector3(-6, 0, 6), 90.0]]:
		_put("WallAstra_Corner_Round_Inner", c[0], c[1])
		_put("TopAstra_Corner_Round_Inner", c[0], c[1])
	# The door you came through (S wall), lit.
	_put("Door_Frame_Square", Vector3(0, 0, HALF), 0.0)
	var exit_glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.8, 3.6)
	exit_glow.mesh = q
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.albedo_color = Color(0.4, 0.8, 1.0, 0.18)
	em.emission_enabled = true
	em.emission = Color(0.4, 0.8, 1.0)
	em.emission_energy_multiplier = 0.6
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	exit_glow.material_override = em
	exit_glow.position = Vector3(0, 1.8, HALF + 0.05)
	add_child(exit_glow)
	var exit_lab := Label3D.new()
	exit_lab.text = "EXIT · %s" % String(territory.get("name", "")).to_upper()
	exit_lab.font = DeepFieldTheme.mono_font()
	exit_lab.font_size = 40
	exit_lab.pixel_size = 0.01
	exit_lab.position = Vector3(0, 4.0, HALF - 0.3)
	exit_lab.rotation_degrees.y = 180.0
	exit_lab.modulate = DeepFieldTheme.ICE
	add_child(exit_lab)
	# Columns and wall lights.
	for p in [Vector3(-HALF + 0.6, 0, -4), Vector3(-HALF + 0.6, 0, 4), Vector3(HALF - 0.6, 0, -4), Vector3(HALF - 0.6, 0, 4)]:
		_put("Column_Astra", p, 0.0 if p.x < 0 else 180.0)
	for p in [[Vector3(-HALF + 0.7, 2.6, 0), 90.0], [Vector3(HALF - 0.7, 2.6, 0), -90.0]]:
		_put("Prop_Light_Wide", p[0] + Vector3(0, 0, 0.66 if p[1] > 0 else -0.66), p[1])
	# Consoles by the door, vents above the board.
	_put("Prop_Computer", Vector3(-3.2, 0, HALF - 1.4), 180.0)
	_put("Prop_Computer", Vector3(3.2, 0, HALF - 1.4), 180.0)
	_put("Prop_Vent_Big", Vector3(-6, 3.4, -HALF + 0.6), 0.0)
	_put("Prop_Vent_Big", Vector3(6, 3.4, -HALF + 0.6), 0.0)


## The board: the room's latest lines on the back wall.
func _build_board() -> void:
	_board_vp = SubViewport.new()
	_board_vp.size = Vector2i(1600, 560)
	_board_vp.transparent_bg = false
	add_child(_board_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.035)
	bg.size = Vector2(1600, 560)
	_board_vp.add_child(bg)
	_board_text = RichTextLabel.new()
	_board_text.bbcode_enabled = true
	_board_text.position = Vector2(36, 24)
	_board_text.size = Vector2(1528, 512)
	_board_text.scroll_active = false
	_board_text.add_theme_font_override("normal_font", DeepFieldTheme.mono_font())
	_board_text.add_theme_font_size_override("normal_font_size", 42)  # legible from the door (≈ 14 m)
	_board_vp.add_child(_board_text)
	_board_text.text = "[color=#5d6578]Reading this room's lines from its own logs…[/color]"
	DeepFieldView.throttle(_board_vp, 2.0)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(13.6, 4.76)
	screen.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _board_vp.get_texture()
	m.emission_enabled = true
	m.emission_texture = _board_vp.get_texture()
	m.emission_energy_multiplier = 1.25
	screen.material_override = m
	screen.position = Vector3(0, 2.6, -HALF + 0.75)
	add_child(screen)
	var head := Label3D.new()
	head.text = "%s · THE ROOM" % String(territory.get("name", "")).to_upper()
	head.font = DeepFieldTheme.display_font()
	head.font_size = 64
	head.pixel_size = 0.01
	head.position = Vector3(0, 5.25, -HALF + 0.8)
	head.modulate = ChatFeedPanel.room_tint(territory).lerp(Color.WHITE, 0.35)
	add_child(head)
	var sub := Label3D.new()
	sub.text = "EVERY LINE HERE IS WRITTEN ON THE CHAIN · %s TO SPEAK" % ControlsHelp.key_of("chat")
	sub.font = DeepFieldTheme.mono_font()
	sub.font_size = 28
	sub.pixel_size = 0.01
	sub.position = Vector3(0, 4.72, -HALF + 0.8)
	sub.modulate = DeepFieldTheme.MUTED
	add_child(sub)


func on_lines(lines: Array, _fresh: Array) -> void:
	var f: RoomFeed = chat_ctl.feed if chat_ctl else null
	var head := maxi(f.head_seen if f else -1, Chain.head_block)
	_board_text.text = board_bbcode(lines, f != null and f.is_loaded(), f == null or f.history_ok, head,
		Session.player.username if Session.player != null else "")


## Pure: the board's text: the newest lines, each speaker in their colour (the
## same as in the HUD's dock), the line, then how long ago and its block; a
## line naming you in gold. Loading, unavailable and empty each say so.
static func board_bbcode(lines: Array, loaded: bool, history_ok: bool, head: int, me: String = "") -> String:
	if lines.is_empty():
		if not loaded:
			return "[color=#5d6578]Reading this room's lines from its own logs…[/color]"
		if not history_ok:
			return "[color=#5d6578]This room's history could not be read: —[/color]"
		return "[color=#8e97a9]No lines in this room yet. Every QING is a room: say the first word (%s).[/color]" % ControlsHelp.key_of("chat")
	var t := ""
	for l in lines.slice(maxi(0, lines.size() - 7)):
		var badge := ""
		if l.get("badge", "") == "og":
			badge = " [color=#64e3a8]✓[/color]"
		elif l.get("badge", "") == "imposter":
			badge = " [color=#ff8fa0]⚠[/color]"
		var col := ChatLines.speaker_color(l).to_html(false)
		var text := ChatPanel._esc(ChatLines.clean_text(String(l.get("text", "")), 64))
		if me != "" and ChatLines.mentions(String(l.get("text", "")), me):
			text = "[color=#ffd27a]%s[/color]" % text
		var when := "say" if String(l.get("source", "")) == "say" else "%s · %s" % [ChatLines.age_text(int(l.get("block", -1)), head), TokenFormat.group(str(int(l.get("block", -1))))]
		t += "[color=#%s]%s[/color]%s  %s  [color=#5d6578][font_size=28]%s[/font_size][/color]\n" % [
			col, ChatPanel._esc(ChatLines.speaker(l)), badge, text, when]
	return t


## The territory's own Julia set, inlaid at the centre of the floor.
func _build_emblem() -> void:
	if territory.is_empty():
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	add_child(vp)
	var view := DeepFieldView.new()
	view.size = Vector2(512, 512)
	vp.add_child(view)
	view.apply_params(DeepField.for_territory(territory))
	DeepFieldView.throttle(vp, 4.0)
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.6, 7.6)
	disc.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = vp.get_texture()
	m.emission_enabled = true
	m.emission_texture = vp.get_texture()
	m.emission_energy_multiplier = 0.7
	m.roughness = 0.15
	m.metallic = 0.4
	disc.material_override = m
	disc.position = Vector3(0, 0.03, 0)
	add_child(disc)


func _collisions() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var boxes := [[Vector3(0, -0.5, 0), Vector3(26, 1, 26)], [Vector3(-HALF - 0.3, 3, 0), Vector3(0.6, 6, 22)],
		[Vector3(HALF + 0.3, 3, 0), Vector3(0.6, 6, 22)], [Vector3(0, 3, -HALF - 0.3), Vector3(22, 6, 0.6)],
		[Vector3(0, 3, HALF + 0.3), Vector3(22, 6, 0.6)], [Vector3(0, 3, -HALF + 0.9), Vector3(14, 6, 0.4)]]
	for b in boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[1]
		cs.shape = sh
		cs.position = b[0]
		body.add_child(cs)
