class_name ArcadeCabinet
extends Node3D
## An upright arcade cabinet running one ArcadeCatalog entry. Its screen is a
## 320×240 SubViewport: the game's attract loop while a player is near (and
## frozen otherwise, to spare low-end PCs); a paid credit starts a real run,
## which the place shows full screen.

const NEAR := 9.0

var entry: Dictionary = {}
var game: Node  # ArcadeGame
var viewport: SubViewport
var _screen_mat: StandardMaterial3D
var _awake := true


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
	_box(Vector3(0.8, 0.28, 0.2), Vector3(0, 1.82, 0.28), glow)
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
	var title := Label3D.new()
	title.text = String(entry.get("title", "?")).to_upper()
	title.font = DeepFieldTheme.display_font()
	title.font_size = 64
	title.pixel_size = 0.0035
	title.modulate = Color(0.02, 0.02, 0.04)
	title.position = Vector3(0, 1.82, 0.385)
	title.width = 210.0
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
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
	screen.position = Vector3(0, 1.42, 0.33)
	screen.rotation_degrees.x = -12.0
	add_child(screen)
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.86, 1.9, 0.85)
	cs.shape = sh
	cs.position = Vector3(0, 0.95, 0)
	body.add_child(cs)


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
