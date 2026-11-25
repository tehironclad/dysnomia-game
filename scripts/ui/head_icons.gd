class_name HeadIcons
extends RefCounted
## Little portraits of the avatar heads (AvatarHeads) for the 2D UI: the chat
## dock's speakers and your name on the HUD. Each kind is rendered once in a
## small SubViewport and kept; until it lands (and with no renderer, headless)
## a disc in the kind's colour stands in, so a caller always gets a texture at
## once and sees it fill in. The same kind always draws the same picture.

const SIZE := 96
## The disc each kind shows before its portrait is rendered (and its ring).
const COLORS := {
	"bear": Color("#c49a6c"), "human": Color("#a8e6ff"), "rat": Color("#b9b0c4"), "alien": Color("#8fe39a"),
	"frog": Color("#7fd36a"), "dog": Color("#d8b48a"), "cat": Color("#f0b878"), "skull": Color("#e9edf4"),
	"robot": Color("#9fc4e8"), "hamster": Color("#f2c48e"), "fox": Color("#ff9a52"), "pig": Color("#ffb2c4"),
	"ape": Color("#a48266"), "bird": Color("#7fb8ff"), "sunny": Color("#ffd27a"),
}

static var _tex := {}  # kind → ImageTexture (the disc, then the portrait)
static var _queue: Array = []
static var _busy := false


static func color_of(kind: String) -> Color:
	return COLORS.get(kind, DeepFieldTheme.ICE)


## The kind's portrait (a stand-in disc until it is rendered).
static func texture(kind: String) -> Texture2D:
	if kind == "" or not AvatarHeads.KINDS.has(kind):
		kind = "bear"
	if _tex.has(kind):
		return _tex[kind]
	var t := ImageTexture.create_from_image(disc(color_of(kind), 24))
	_tex[kind] = t
	if can_render() and kind != "human":  # "human" is the helmet on a body: no head mesh to draw
		_queue.append(kind)
		_pump()
	return t


## Pure: a soft filled disc (the stand-in), `size` px square.
static func disc(c: Color, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length() / r
			var a := clampf((1.0 - d) * r, 0.0, 1.0) * 0.55
			img.set_pixel(x, y, Color(c, a))
	return img


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


static func _pump() -> void:
	if _busy:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_busy = true
	while not _queue.is_empty():
		var kind: String = _queue.pop_front()
		var img := await _render(tree, kind)
		if img != null and not img.is_empty():
			(_tex[kind] as ImageTexture).set_image(img)
	_busy = false


static func _render(tree: SceneTree, kind: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.82, 1.0)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = DeepFieldTheme.ICE
	vp.add_child(rim)
	var head := AvatarHeads.build(kind)
	head.rotation_degrees.y = -18.0
	vp.add_child(head)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(0.0, 0.3, 1.15)
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.27, 0.0))
	tree.root.add_child.call_deferred(vp)
	for i in 4:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_instance_valid(vp) and vp.is_inside_tree():
		img = vp.get_texture().get_image()
	if is_instance_valid(vp):
		vp.queue_free()
	return img
