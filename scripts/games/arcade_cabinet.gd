class_name ArcadeCabinet
extends Node3D
## An upright arcade cabinet running one ArcadeCatalog entry. Its screen is a
## 320×240 SubViewport: the game's attract loop while a player is near (and
## frozen otherwise, to spare low-end PCs); a paid credit starts a real run.
## Using a cabinet dives into it (ArcadeDive): the camera pushes into this
## screen and you land in the game's 3D world, or this screen full-size.

const NEAR := 9.0
## The Use reach, from the play spot: the HUD prompt, this floating title and Use all start here
## (Use from further than the controls walks you up first). One prompt, never a dead one.
const REACH := 3.4
const TITLE_NEAR := REACH
const MARQUEE := Vector2(1.16, 0.66)  # the backlit marquee topper (m), wider than the body
const MARQUEE_TEXT := Vector2(1.08, 0.56)  # the area its letters may fill
const MARQUEE_Y := 2.1

var entry: Dictionary = {}
var game: Node  # ArcadeGame
var viewport: SubViewport
var _screen_mat: StandardMaterial3D
var _awake := true
var marquee_label: Label3D
var near_title: Label3D
var near_sub: Label3D
var _near := 0.0
var _near_on := false


func setup(p_entry: Dictionary, accent: Color) -> void:
	entry = p_entry
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.06, 0.06, 0.08)
	body_mat.metallic = 0.3
	body_mat.roughness = 0.4
	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_color = accent.darkened(0.35)
	side_mat.roughness = 0.5
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = accent
	glow.emission_enabled = true
	glow.emission = accent
	glow.emission_energy_multiplier = 2.0
	# Cabinet body (faces +Z), side panels in the accent colour, a lit marquee.
	_box(Vector3(0.8, 1.9, 0.75), Vector3(0, 0.95, -0.05), body_mat)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.04, 1.95, 0.8), Vector3(sx * 0.42, 0.975, -0.05), side_mat)
		_box(Vector3(0.02, 1.7, 0.02), Vector3(sx * 0.445, 1.0, 0.34), glow)
	_build_marquee(accent)
	_box(Vector3(0.82, 0.1, 0.36), Vector3(0, 1.0, 0.42), body_mat)  # control deck
	var stick := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	stick.mesh = sm
	stick.material_override = glow
	stick.position = Vector3(-0.15, 1.1, 0.45)
	add_child(stick)
	for i in 3:
		var btn := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 0.02
		btn.mesh = cm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = [Color(1, 0.2, 0.3), Color(1, 0.85, 0.2), Color(0.2, 0.8, 1)][i]
		bmat.emission_enabled = true
		bmat.emission = bmat.albedo_color
		bmat.emission_energy_multiplier = 0.6
		btn.material_override = bmat
		btn.position = Vector3(0.05 + i * 0.09, 1.06, 0.45)
		add_child(btn)
	# The screen
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(320, 240)
	viewport.add_child(bg)
	game = _make_game()
	if game:
		viewport.add_child(game)
		game.attract()
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.64, 0.48)
	screen.mesh = q
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.albedo_texture = viewport.get_texture()
	screen.material_override = _screen_mat
	screen.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0, 1.42, 0.33))
	add_child(screen)
	_build_bezel(screen.transform, accent)
	_build_near_label(accent)
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.86, 1.9, 0.85)
	cs.shape = sh
	cs.position = Vector3(0, 0.95, 0)
	body.add_child(cs)


## Lays a title out on a marquee: one line, or two when splitting at a space
## gives bigger letters. Never wider than max_w nor taller than max_h (metres).
## {text, pixel_size, lines, width_m, height_m}.
static func marquee_fit(title: String, font: Font, size: int, max_w: float, max_h: float) -> Dictionary:
	var t := title.strip_edges().to_upper()
	var options: Array = [[t]]
	var words := t.split(" ", false)
	if words.size() >= 2:
		var best := []
		var best_w := INF
		for k in range(1, words.size()):
			var a := " ".join(words.slice(0, k))
			var b := " ".join(words.slice(k))
			var w := maxf(font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, font.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
			if w < best_w:
				best_w = w
				best = [a, b]
		options.append(best)
	var line_h := font.get_height(size)
	var out := {}
	for lines in options:
		var w := 0.0
		for l in lines:
			w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		var h: float = line_h * (lines as Array).size()
		var px := minf(max_w / maxf(w, 1.0), max_h / maxf(h, 1.0))
		if out.is_empty() or px > float(out["pixel_size"]) * 1.08:  # two lines only when clearly bigger
			out = {"text": "\n".join(lines), "pixel_size": px, "lines": lines.size(), "width_m": w * px, "height_m": h * px}
	return out


func _build_marquee(accent: Color) -> void:
	# A backlit marquee box that rises above the cabinet: a dark frame, a lit panel, big dark letters.
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.03, 0.03, 0.04)
	frame.metallic = 0.5
	frame.roughness = 0.35
	_box(Vector3(MARQUEE.x + 0.04, MARQUEE.y + 0.04, 0.22), Vector3(0, MARQUEE_Y, 0.25), frame)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var panel := accent.lerp(Color(1.0, 0.98, 0.92), 0.7) * 0.92  # bright but under the glow threshold
	lit.albedo_color = panel
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = MARQUEE
	mi.mesh = q
	mi.material_override = lit
	mi.position = Vector3(0, MARQUEE_Y, 0.362)
	add_child(mi)
	# Neon edges top and bottom in the accent colour.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = accent
	glow.emission_enabled = true
	glow.emission = accent
	glow.emission_energy_multiplier = 2.5
	for sy in [-1.0, 1.0]:
		_box(Vector3(MARQUEE.x + 0.04, 0.018, 0.02), Vector3(0, MARQUEE_Y + sy * (MARQUEE.y * 0.5 + 0.02), 0.37), glow)
	var font := DeepFieldTheme.display_font()
	var fit := marquee_fit(String(entry.get("title", "?")), font, 96, MARQUEE_TEXT.x, MARQUEE_TEXT.y)
	marquee_label = Label3D.new()
	marquee_label.name = "Marquee"
	marquee_label.text = fit["text"]
	marquee_label.font = font
	marquee_label.font_size = 96
	marquee_label.pixel_size = fit["pixel_size"]
	marquee_label.modulate = Color(0.03, 0.02, 0.06)
	marquee_label.outline_size = 10  # the same ink: heavier letters that hold up at a distance
	marquee_label.outline_modulate = Color(0.03, 0.02, 0.06)
	marquee_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	marquee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marquee_label.position = Vector3(0, MARQUEE_Y, 0.366)
	add_child(marquee_label)


func _build_bezel(screen_xf: Transform3D, accent: Color) -> void:
	# A frame round the screen; the bottom strip carries the game's name.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.025)
	m.roughness = 0.5
	var parts := [[Vector3(0.74, 0.04, 0.012), Vector3(0, 0.26, 0.004)], [Vector3(0.74, 0.11, 0.012), Vector3(0, -0.295, 0.004)],
		[Vector3(0.05, 0.6, 0.012), Vector3(-0.345, -0.015, 0.004)], [Vector3(0.05, 0.6, 0.012), Vector3(0.345, -0.015, 0.004)]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.material_override = m
		mi.transform = screen_xf * Transform3D(Basis(), p[1])
		add_child(mi)
	var font := DeepFieldTheme.display_font()
	var l := Label3D.new()
	l.name = "BezelTitle"
	l.text = String(entry.get("title", "?")).to_upper()
	l.font = font
	l.font_size = 64
	l.pixel_size = minf(0.62 / maxf(1.0, font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x), 0.07 / font.get_height(64))
	l.modulate = accent.lerp(Color.WHITE, 0.45)
	l.outline_size = 0
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.transform = screen_xf * Transform3D(Basis(), Vector3(0, -0.293, 0.0115))
	add_child(l)


func _build_near_label(accent: Color) -> void:
	near_title = Label3D.new()
	near_title.name = "NearTitle"
	near_title.text = String(entry.get("title", "?")).to_upper()
	near_title.font = DeepFieldTheme.display_font()
	near_title.font_size = 72
	near_title.pixel_size = 0.0042
	near_title.modulate = accent.lerp(Color.WHITE, 0.55)
	near_title.outline_size = 14
	near_title.outline_modulate = Color(0, 0, 0, 0.9)
	near_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	near_title.no_depth_test = true
	near_title.position = Vector3(0, 3.0, 0.3)
	near_title.visible = false
	add_child(near_title)
	near_sub = Label3D.new()
	near_sub.name = "NearSub"
	near_sub.text = near_text()
	near_sub.font = DeepFieldTheme.mono_font()
	near_sub.font_size = 40
	near_sub.pixel_size = 0.004
	near_sub.modulate = Color(1.0, 0.86, 0.45)
	near_sub.outline_size = 10
	near_sub.outline_modulate = Color(0, 0, 0, 0.9)
	near_sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	near_sub.no_depth_test = true
	near_sub.position = Vector3(0, 2.72, 0.3)
	near_sub.visible = false
	add_child(near_sub)


## The line under the floating title: the price (the key is the HUD prompt's, shown with it).
func near_text() -> String:
	if not playable():
		return "free to watch"
	return Prices.menu_line()


## Shows the floating title (fades in/out). GamesPlace calls it for the nearest cabinet.
func set_near(on: bool) -> void:
	_near_on = on
	if on and near_title and not near_title.visible:
		near_sub.text = near_text()
		near_title.visible = true
		near_sub.visible = true
	set_process(true)


func _process(delta: float) -> void:
	if near_title == null:
		set_process(false)
		return
	_near = move_toward(_near, 1.0 if _near_on else 0.0, delta * 4.0)
	near_title.modulate.a = _near
	near_sub.modulate.a = _near
	near_title.outline_modulate.a = _near * 0.9
	near_sub.outline_modulate.a = _near * 0.9
	if _near <= 0.0 and not _near_on:
		near_title.visible = false
		near_sub.visible = false
		set_process(false)


func _make_game() -> Node:
	var path := String(entry.get("script", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var g: Node = load(path).new()
	if entry.get("kind", "") == "cartridge" and g.has_method("load_cart"):
		g.load_cart(String(entry.get("cart", "")))
	return g


## Only the real games take credits: Maria's cartridges read no input (they
## animate on their own), so they run free as attract screens.
func playable() -> bool:
	return game != null and bool(entry.get("playable", true)) and entry.get("kind", "game") != "cartridge"


## Wakes the screen when the player is near; freezes it when far.
func set_awake(on: bool) -> void:
	if on == _awake:
		return
	_awake = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if game:
		game.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## The screen quad's global transform (its +Z faces the player; 0.64 × 0.48 m).
func screen_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0, 1.42, 0.33))


## Where the player stands to play (in front of the controls).
func play_spot() -> Vector3:
	return to_global(Vector3(0, 0, 1.1))


func start_run(seed: int) -> void:
	set_awake(true)
	if game:
		game.start(seed)


func back_to_attract() -> void:
	if game:
		game.attract()


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	add_child(mi)
