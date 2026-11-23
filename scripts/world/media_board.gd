class_name MediaBoard
extends Node3D
## A community media board standing at one wing of a QING. Shows the wing's verified
## posts from BoardFeed (rotating every ROTATE_SECONDS), or an invitation when empty.
## Local -Z is the board's front, facing visitors. Walking up to it emits board_focus.

signal board_focus(board: MediaBoard, inside: bool)

const ROTATE_SECONDS := 12.0
const SCREEN_W := 3.2
const SCREEN_H := 1.8
const BOTTOM := 1.2
const MAX_IMAGE_BYTES := 2 * 1024 * 1024

static var _image_cache: Dictionary = {}   # url -> ImageTexture (shared by all boards)

var wing: String = ""
var title: String = ""
var _feed: BoardFeed
var _posts: Array = []
var _index: int = 0
var _t: float = 0.0
var _screen_mat: StandardMaterial3D
var _caption: Label3D
var _footer: Label3D
var _idle: Label3D
var _header: Label3D
var _http: HTTPRequest
var _loading_url: String = ""


func setup(wing_id: String, wing_title: String, feed: BoardFeed) -> void:
	wing = wing_id
	title = wing_title
	_feed = feed
	_build()
	_feed.posts_changed.connect(func(w: String) -> void:
		if w == wing:
			_refresh())
	_refresh()


func current_post() -> Dictionary:
	return _posts[_index] if _index < _posts.size() else {}


func _process(delta: float) -> void:
	if _posts.size() < 2:
		return
	_t += delta
	if _t >= ROTATE_SECONDS:
		_t = 0.0
		_index = (_index + 1) % _posts.size()
		_show_current()


func _refresh() -> void:
	_posts = _feed.active_posts(wing)
	_index = clampi(_index, 0, maxi(_posts.size() - 1, 0))
	_show_current()


func _show_current() -> void:
	var p := current_post()
	if p.is_empty():
		_idle.text = "SHARE HERE\n[E] post a picture for 24 h"
		_screen_mat.albedo_texture = null
		_screen_mat.albedo_color = Color(0.05, 0.06, 0.1)
		_idle.visible = true
		_caption.text = ""
		_footer.text = "1 AFFECTION · 24 h · paid to this QING's keeper"
		return
	_idle.visible = false
	_caption.text = str(p.get("caption", ""))
	var left := maxi(0, int(p.get("expires", 0)) - int(Time.get_unix_time_from_system()))
	var state := "awaiting chain confirmation" if p.get("pending", false) else "%dh %02dm left" % [left / 3600, (left % 3600) / 60]
	_footer.text = "posted by %s · %s · %d/%d" % [p.get("poster", "?"), state, _index + 1, _posts.size()]
	var url := str(p.get("url", ""))
	var show_images: bool = Config.get("show_board_images") != false  # viewer setting, default on
	if url.is_empty() or not show_images:
		# Text-only post (or images switched off): the caption fills the screen
		_screen_mat.albedo_texture = null
		_screen_mat.albedo_color = Color(0.08, 0.06, 0.14)
		_idle.visible = true
		_idle.text = str(p.get("caption", "")) + ("" if url.is_empty() else "\n[image hidden]")
		_caption.text = ""
		return
	_screen_mat.albedo_color = Color.WHITE
	if _image_cache.has(url):
		_screen_mat.albedo_texture = _image_cache[url]
	else:
		_screen_mat.albedo_texture = null
		_screen_mat.albedo_color = Color(0.08, 0.06, 0.14)
		_load_image(url)


# ─── Image loading ──────────────────────────────────────────────────────

func _load_image(url: String) -> void:
	if _loading_url == url or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_loading_url = url
	if _http.request(url) != OK:
		_loading_url = ""


func _on_image(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var url := _loading_url
	_loading_url = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		return
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	# Sniff by magic bytes, never trust the extension
	if body.size() > 8 and body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	elif body.size() > 3 and body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	elif body.size() > 12 and body[8] == 0x57 and body[9] == 0x45 and body[10] == 0x42 and body[11] == 0x50:
		err = img.load_webp_from_buffer(body)
	if err != OK:
		return
	# Fit inside 1024 px so a huge upload can't eat VRAM
	var s := minf(1.0, 1024.0 / float(maxi(img.get_width(), img.get_height())))
	if s < 1.0:
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	_image_cache[url] = ImageTexture.create_from_image(img)
	_show_current()


# ─── Construction ───────────────────────────────────────────────────────

func _build() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.body_size_limit = MAX_IMAGE_BYTES
	_http.request_completed.connect(_on_image)
	add_child(_http)

	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.13, 0.14, 0.17)
	frame.metallic = 0.7
	frame.roughness = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.25, 0.85, 1.0)
	trim.emission_enabled = true
	trim.emission = Color(0.25, 0.85, 1.0)
	trim.emission_energy_multiplier = 1.6

	var cy := BOTTOM + SCREEN_H * 0.5
	# Two posts + footings
	for sx in [-SCREEN_W * 0.5 - 0.12, SCREEN_W * 0.5 + 0.12]:
		_box(Vector3(0.14, BOTTOM + SCREEN_H + 0.35, 0.14), Vector3(sx, (BOTTOM + SCREEN_H + 0.35) * 0.5, 0.05), frame)
		_box(Vector3(0.4, 0.12, 0.4), Vector3(sx, 0.06, 0.05), frame)
	# Backing panel + bezel + cyan edge
	_box(Vector3(SCREEN_W + 0.3, SCREEN_H + 0.3, 0.1), Vector3(0, cy, 0.08), frame)
	_box(Vector3(SCREEN_W + 0.34, 0.04, 0.12), Vector3(0, cy - SCREEN_H * 0.5 - 0.15, 0.06), trim)
	_box(Vector3(SCREEN_W + 0.34, 0.04, 0.12), Vector3(0, cy + SCREEN_H * 0.5 + 0.15, 0.06), trim)
	# Screen (faces -Z)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_mat.albedo_color = Color(0.05, 0.06, 0.1)
	var q := QuadMesh.new()
	q.size = Vector2(SCREEN_W, SCREEN_H)
	var screen := MeshInstance3D.new()
	screen.mesh = q
	screen.material_override = _screen_mat
	screen.position = Vector3(0, cy, 0.02)
	screen.rotation.y = PI  # QuadMesh faces +Z; turn it to face -Z
	add_child(screen)
	# Header plate
	_header = _label(title.to_upper() + " BOARD", 48, Color(0.55, 0.92, 1.0), Vector3(0, cy + SCREEN_H * 0.5 + 0.38, -0.02))
	_header.outline_size = 8
	_idle = _label("SHARE HERE\n[E] post a picture for 24 h", 54, Color(0.92, 0.9, 1.0), Vector3(0, cy, -0.01))
	_caption = _label("", 40, Color.WHITE, Vector3(0, BOTTOM - 0.16, -0.06))
	_caption.width = 900.0
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer = _label("", 26, Color(0.75, 0.78, 0.9), Vector3(0, BOTTOM - 0.42, -0.06))
	# Soft light on the reading area
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.85, 1.0)
	l.light_energy = 0.9
	l.omni_range = 6.0
	l.shadow_enabled = false
	l.position = Vector3(0, cy, -1.2)
	add_child(l)
	# Trigger in front of the board
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(SCREEN_W + 1.5, 3.0, 3.5)
	cs.shape = sh
	area.add_child(cs)
	area.position = Vector3(0, 1.5, -2.0)
	add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			board_focus.emit(self, true))
	area.body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			board_focus.emit(self, false))
	# Solid posts
	var body := StaticBody3D.new()
	for sx in [-SCREEN_W * 0.5 - 0.12, SCREEN_W * 0.5 + 0.12]:
		var c := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.3, 3.4, 0.3)
		c.shape = b
		c.position = Vector3(sx, 1.7, 0.05)
		body.add_child(c)
	add_child(body)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _label(text: String, size: int, color: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = pos
	l.rotation.y = PI  # Label3D faces +Z by default; boards face -Z
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l
