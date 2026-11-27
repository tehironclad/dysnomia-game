class_name ArcadeDive
extends CanvasLayer
## Diving into a cabinet, and back out.
##
## In: the camera leaves the player and pushes into the cabinet's screen (the whole frame bends like
## CRT glass, scanlines come up), a light tunnel opens with a flash, and the game's world grows out
## of it until it fills the screen. Inside: the game's 3D world (an ArcadeWorld in its own World3D)
## or, for Folklore cartridges and in "classic" view, the cabinet's own 320×240 screen full-size in
## a CRT bezel. Out: the same in reverse, back to the player's camera, with your score.
##
## The dive is presentation only. Paying, credits, starting and recording a run stay in GamesPlace
## (ArcadePay's pipeline is untouched); the menu's buttons just emit signals.
##
## How to play: the menu is the start screen (it stays until Play or Leave) and lists every
## control as a key chip; with the menu down, GameHowto's strip keeps them along the bottom, and
## the help key brings the full card back (a run pauses while it is up).

signal pay_pressed
signal strip_pressed  ## buy a ticket strip (Prices.STRIP_PLAYS plays, one approval)
signal start_pressed
signal leave_pressed
signal view_pressed
signal daily_pressed  ## today's challenge: a free scored try (DailyRun)
signal daily_practice_pressed  ## today's challenge: free practice on another seed
signal entered
signal exited

enum Phase { IDLE, ENTERING, INSIDE, LEAVING }

const T_PUSH := 0.9
const T_WARP := 0.7
const T_SETTLE := 0.55
const T_OUT_WARP := 0.6
const T_OUT_PULL := 0.8
const FOV_END := 50.0
const SCREEN_HALF_H := 0.24  # the cabinet's screen is 0.64 × 0.48 m
const ICE := Color("#7fe9ff")
const GOLD := Color("#ffd36b")
const MAGENTA := Color("#ff4fd8")

var phase := Phase.IDLE
var cab: ArcadeCabinet
var world: ArcadeWorld  ## null for a cartridge (classic only)
var classic := false  ## showing the cabinet's own screen instead of the 3D world
var running := false
var source_text := ""  ## what the overlay says about this run (credit / demo)
var freeze_at := -1.0  ## previews: hold the entry at this fraction (0..1) of the transition

# The menu, filled in by GamesPlace.
var menu: PanelContainer
var menu_title: Label
var menu_blurb: Label
var menu_info: Label
var menu_controls: GridContainer  ## how to play: every control as a key chip
var pay_button: Button
var strip_button: Button
var start_button: Button
var view_button: Button
var leave_button: Button
var daily_row: HBoxContainer  ## shown in the cabinet that runs today's challenge
var daily_button: Button
var daily_practice_button: Button
var scores_title: Label
var scores_label: Label

var _fx: ColorRect
var _mat: ShaderMaterial
var _vp: SubViewport
var _cam: Camera3D
var _from_cam: Camera3D
var _from_xf := Transform3D()
var _from_fov := 70.0
var _to_xf := Transform3D()
var _via := Vector3.ZERO
var _player_model: Node3D
var _clock := 0.0
var _time := 0.0
var _hud: Control
var _flash_rect: ColorRect
var _hud_title: Label
var _hud_score: Label
var _hud_lives: Label
var _hud_stats: Label
var _hud_center: Label
var _hud_source: Label
var _bar_box: VBoxContainer
var _bars: Array = []  # [Label, ColorRect bg, ColorRect fill]
var _toast: Label
var _toast_t := 0.0
var howto: GameHowto
var _strip_want := false
var _rows_key := ""


func _ready() -> void:
	layer = 30
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DeepFieldTheme.get_theme()
	add_child(root)
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/arcade/dive/dive.gdshader")
	_fx.material = _mat
	_fx.visible = false
	root.add_child(_fx)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(0, 0, 0, 0)
	root.add_child(_flash_rect)
	_build_hud(root)
	_build_menu(root)
	_toast = Label.new()
	_toast.theme_type_variation = "DisplayLabel"
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", GOLD)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_toast, Control.PRESET_CENTER_TOP, Vector2(-600, 90), Vector2(1200, 80))
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.visible = false
	root.add_child(_toast)
	howto = GameHowto.new()
	howto.name = "HowTo"
	add_child(howto)
	howto.opened.connect(func(m: int) -> void:
		if m == GameHowto.Mode.HELP and running and cab and cab.game:
			cab.game.set_process(false))  # the run waits while the card is up
	howto.dismissed.connect(func(m: int) -> void:
		if m == GameHowto.Mode.HELP and cab and cab.game:
			cab.game.set_process(true))


## The controls in this view, as [[key, words]]: the 3D world's own, or the cabinet's screen
## (the move keys and fire), then the view switch and Esc.
func controls_rows() -> Array:
	var rows: Array = []
	if world != null and not classic:
		rows = world.controls_list()
	else:
		rows = [["%s%s%s%s / arrows" % [ControlsHelp.key_of("move_forward"), ControlsHelp.key_of("move_left"), ControlsHelp.key_of("move_back"), ControlsHelp.key_of("move_right")], "move"],
			[ControlsHelp.key_of("jump"), "fire"]]
	if world != null:
		rows.append([ControlsHelp.key_of("arcade_view"), "3D world" if classic else "classic screen"])
	rows.append(["Esc", "end the run" if running else "leave"])
	return rows


## The how-to card's words for this cabinet.
func howto_spec() -> Dictionary:
	var title := String(cab.entry.get("title", "")) if cab else ""
	var rules := PackedStringArray()
	if cab:
		rules.append(String(cab.entry.get("blurb", "")))
	rules.append("A run is a credit: %s paid to this QING (the receipt is checked). The demo plays itself for free." % ArcadePay.fee_text())
	return {"title": title, "tag": "Arcade cabinet · %s" % ("classic screen" if classic else "3D world"), "rules": rules,
		"controls": controls_rows(), "accent": ICE, "verb": "play", "esc": "end the run" if running else "leave"}


## Menu up: the menu lists the controls. Menu down (a run, or the demo full screen): the strip.
func _refresh_controls() -> void:
	var rows := controls_rows()
	var k := str(rows)
	if k != _rows_key:
		_rows_key = k
		if menu_controls:
			GameHowto.fill_grid(menu_controls, rows, 18, 380.0)
		howto.setup(howto_spec())
		howto.set_strip(rows)
	var want := phase == Phase.INSIDE and not menu.visible
	if want != _strip_want:
		_strip_want = want
		howto.show_strip(want)


func is_active() -> bool:
	return phase != Phase.IDLE


func is_inside() -> bool:
	return phase == Phase.INSIDE


# ── in ───────────────────────────────────────────────────────────────────────


## Dives into cabinet `c`. ctx: {qing, territory, accent, model (the player's avatar), player}.
func enter(c: ArcadeCabinet, ctx: Dictionary) -> void:
	if phase != Phase.IDLE:
		return
	cab = c
	running = false
	source_text = ""
	c.set_awake(true)
	_player_model = ctx.get("model")
	var wpath := String(c.entry.get("world", ""))
	world = null
	if c.game and wpath != "" and ResourceLoader.exists(wpath):
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.size = _world_size()
		_vp.msaa_3d = Viewport.MSAA_2X if Config.level() >= 2 else Viewport.MSAA_DISABLED
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_vp)
		world = load(wpath).new()
		_vp.add_child(world)
		world.bind(c.game, ctx)
		world.prepare_demo()
	_set_classic(world == null)
	# The dive camera starts where the player's camera is.
	_from_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.near = 0.02
	get_parent().add_child(_cam)
	if _from_cam:
		_from_xf = _from_cam.global_transform
		_from_fov = _from_cam.fov
	else:
		_from_xf = c.global_transform * Transform3D(Basis(), Vector3(0, 1.8, 3.0))
	_cam.global_transform = _from_xf
	_cam.fov = _from_fov
	_cam.make_current()
	var screen := c.screen_transform()
	var d := SCREEN_HALF_H / tan(deg_to_rad(FOV_END * 0.5)) * 0.7
	_to_xf = Transform3D(screen.basis.orthonormalized(), screen.origin + screen.basis.z.normalized() * d)
	var flat := Vector3(screen.basis.z.x, 0.0, screen.basis.z.z).normalized()
	_via = screen.origin + flat * 1.5 + Vector3.UP * 0.25
	menu.visible = false
	_hud.visible = false
	_fx.visible = true
	_clock = 0.0
	phase = Phase.ENTERING
	_enter_frame(0.0)


func _world_size() -> Vector2i:
	var s := Vector2(DisplayServer.window_get_size())
	if s.x < 64.0 or s.y < 64.0:
		s = Vector2(1280, 720)
	var k := 0.6 if Config.level() <= 0 else (0.8 if Config.level() == 1 else 1.0)
	s *= k
	if s.x > 1920.0:
		s *= 1920.0 / s.x
	return Vector2i(s)


func _set_classic(on: bool) -> void:
	classic = on
	var screen_aspect := _screen_aspect()
	_mat.set_shader_parameter("screen_aspect", screen_aspect)
	_mat.set_shader_parameter("tint", ICE)
	_mat.set_shader_parameter("tint2", MAGENTA)
	if on or world == null:
		_mat.set_shader_parameter("world_tex", cab.viewport.get_texture())
		_mat.set_shader_parameter("world_px", Vector2(cab.viewport.size))
		_mat.set_shader_parameter("world_aspect", float(cab.viewport.size.x) / cab.viewport.size.y)
		_mat.set_shader_parameter("pixelate", 1.0)
		_mat.set_shader_parameter("scan_rows", float(cab.viewport.size.y))
		if world:
			world.unbind()
			world.process_mode = Node.PROCESS_MODE_DISABLED
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_mat.set_shader_parameter("world_tex", _vp.get_texture())
		_mat.set_shader_parameter("world_px", Vector2(_vp.size))
		_mat.set_shader_parameter("world_aspect", float(_vp.size.x) / _vp.size.y)
		_mat.set_shader_parameter("pixelate", 0.0)
		world.process_mode = Node.PROCESS_MODE_INHERIT
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		world.game.input_remap = world.controls_remap()
	if phase == Phase.INSIDE:
		_settled()
	if view_button:
		view_button.visible = world != null
		view_button.text = ("3D world (%s)" if classic else "Classic screen (%s)") % ControlsHelp.key_of("arcade_view")
	_rows_key = ""


func _screen_aspect() -> float:
	var r := get_viewport().get_visible_rect().size
	return r.x / maxf(1.0, r.y)


## Swaps the 3D world and the cabinet's own screen (no-op for cartridges).
func toggle_view() -> void:
	if world == null or phase != Phase.INSIDE:
		return
	_set_classic(not classic)
	_hud.visible = not classic


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## The camera's path: a curve through _via, a point square in front of the screen, so it lines up
## with the screen before the push however the player was looking (and clears the next cabinets).
func _arc(a: Transform3D, b: Transform3D, e: float) -> Transform3D:
	var o := a.origin * (1.0 - e) * (1.0 - e) + _via * 2.0 * (1.0 - e) * e + b.origin * e * e
	var qa := a.basis.orthonormalized().get_rotation_quaternion()
	var qb := b.basis.orthonormalized().get_rotation_quaternion()
	return Transform3D(Basis(qa.slerp(qb, minf(1.0, e * 1.25))), o)


func _inside_bulge() -> float:
	return 0.08 if classic else 0.0


func _enter_frame(t: float) -> void:
	var u := clampf(t / T_PUSH, 0.0, 1.0)
	var e := _smooth(u)
	_cam.global_transform = _arc(_from_xf, _to_xf, e)
	_cam.fov = lerpf(_from_fov, FOV_END, e)
	_hide_player_near()
	var v := clampf((t - T_PUSH) / T_WARP, 0.0, 1.0)
	var w := clampf((t - T_PUSH - T_WARP) / T_SETTLE, 0.0, 1.0)
	var push_bulge := 0.55 * u * u
	_mat.set_shader_parameter("bulge", lerpf(push_bulge, _inside_bulge(), w))
	_mat.set_shader_parameter("scan", lerpf(0.6 * u, 0.12 if not classic else 0.0, w))
	_mat.set_shader_parameter("vignette", lerpf(0.4 * u, 0.25, w))
	_mat.set_shader_parameter("tunnel", _smooth(v / 0.35) * (1.0 - w))
	_mat.set_shader_parameter("world_mix", _smooth((v - 0.1) / 0.45))
	_mat.set_shader_parameter("world_zoom", lerpf(0.03, 1.0, pow(v, 2.0)))
	_mat.set_shader_parameter("flash", exp(-pow((v - 0.42) * 9.0, 2.0)) * 0.75 if v > 0.0 else 0.0)
	_mat.set_shader_parameter("rgb_split", 0.012 * sin(v * PI))
	_mat.set_shader_parameter("bezel", 1.0 if classic else 0.0)


func _hide_player_near() -> void:
	if _player_model and is_instance_valid(_player_model):
		var head := _player_model.global_position + Vector3.UP * 1.5
		_player_model.visible = _cam.global_position.distance_to(head) > 1.1


func _inside() -> void:
	phase = Phase.INSIDE
	_settled()
	# Nothing of the hall shows now: stop drawing it.
	get_viewport().disable_3d = true
	_hud.visible = world != null and not classic
	entered.emit()


func _settled() -> void:
	_mat.set_shader_parameter("bulge", _inside_bulge())
	_mat.set_shader_parameter("scan", 0.0 if classic else 0.1)
	_mat.set_shader_parameter("vignette", 0.25)
	_mat.set_shader_parameter("tunnel", 0.0)
	_mat.set_shader_parameter("world_mix", 1.0)
	_mat.set_shader_parameter("world_zoom", 1.0)
	_mat.set_shader_parameter("flash", 0.0)
	_mat.set_shader_parameter("rgb_split", 0.0015 if classic else 0.0)
	_mat.set_shader_parameter("bezel", 1.0 if classic else 0.0)


# ── out ──────────────────────────────────────────────────────────────────────


func leave() -> void:
	if phase != Phase.INSIDE and phase != Phase.ENTERING:
		return
	get_viewport().disable_3d = false
	menu.visible = false
	_hud.visible = false
	howto.end()
	_strip_want = false
	_rows_key = ""
	_flash_rect.color = Color(0, 0, 0, 0)
	if _from_cam and is_instance_valid(_from_cam):
		_from_xf = _from_cam.global_transform
	_to_xf = _cam.global_transform
	_clock = 0.0
	phase = Phase.LEAVING
	freeze_at = -1.0


func _leave_frame(t: float) -> void:
	var v := clampf(t / T_OUT_WARP, 0.0, 1.0)
	var u := clampf((t - T_OUT_WARP) / T_OUT_PULL, 0.0, 1.0)
	var e := _smooth(u)
	_mat.set_shader_parameter("world_zoom", lerpf(1.0, 0.03, pow(v, 1.5)))
	_mat.set_shader_parameter("world_mix", 1.0 - _smooth((v - 0.45) / 0.5))
	_mat.set_shader_parameter("tunnel", _smooth(v / 0.3) * (1.0 - u))
	_mat.set_shader_parameter("flash", exp(-pow((v - 0.7) * 6.0, 2.0)) * 0.7)
	_mat.set_shader_parameter("bulge", lerpf(lerpf(_inside_bulge(), 0.55, v), 0.0, e))
	_mat.set_shader_parameter("scan", 0.5 * (1.0 - e))
	_mat.set_shader_parameter("vignette", 0.4 * (1.0 - e))
	_mat.set_shader_parameter("rgb_split", 0.01 * sin(v * PI))
	_mat.set_shader_parameter("bezel", (1.0 if classic else 0.0) * (1.0 - v))
	_cam.global_transform = _arc(_to_xf, _from_xf, e)
	_cam.fov = lerpf(FOV_END, _from_fov, e)
	_hide_player_near()


func _done() -> void:
	if _from_cam and is_instance_valid(_from_cam):
		_from_cam.make_current()
	if _player_model and is_instance_valid(_player_model):
		_player_model.visible = true
	_cam.queue_free()
	_cam = null
	if world:
		world.unbind()
	if _vp:
		_vp.queue_free()
	_vp = null
	world = null
	_fx.visible = false
	cab = null
	running = false
	phase = Phase.IDLE
	exited.emit()


func _process(delta: float) -> void:
	_time += delta
	if _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if phase == Phase.IDLE:
		return
	_mat.set_shader_parameter("time_s", _time)
	match phase:
		Phase.ENTERING:
			_clock += delta
			var total := T_PUSH + T_WARP + T_SETTLE
			if freeze_at >= 0.0:
				_clock = minf(_clock, freeze_at * total)
			_enter_frame(_clock)
			if _clock >= total:
				_inside()
		Phase.LEAVING:
			_clock += delta
			_leave_frame(_clock)
			if _clock >= T_OUT_WARP + T_OUT_PULL:
				_done()
		Phase.INSIDE:
			_refresh_controls()
			_hud_frame()


# ── the overlay ──────────────────────────────────────────────────────────────


func set_running(on: bool, source: String = "") -> void:
	running = on
	_rows_key = ""
	if source != "":
		source_text = source
	menu.visible = not on and phase == Phase.INSIDE
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN if on else Input.MOUSE_MODE_VISIBLE)


func show_menu() -> void:
	menu.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func show_toast(text: String, seconds: float = 6.0) -> void:
	_toast.text = text
	_toast_t = seconds
	_toast.modulate.a = 1.0
	_toast.visible = true


func _hud_frame() -> void:
	if world == null or classic or cab == null or cab.game == null:
		_flash_rect.color = Color(0, 0, 0, 0)
		return
	var g := cab.game
	var h := world.hud()
	_hud_title.text = String(cab.entry.get("title", "")).to_upper()
	_hud_score.text = ArcadeScores.grouped(g.score)
	_hud_lives.text = "◆ ".repeat(g.lives)
	_hud_stats.text = "\n".join(h.get("stats", PackedStringArray()))
	var center := String(h.get("center", ""))
	if g.over:
		center = "GAME OVER"
	_hud_center.text = center
	_hud_center.add_theme_color_override("font_color", MAGENTA if g.over else h.get("center_color", GOLD))
	var bars: Array = h.get("bars", [])
	for i in _bars.size():
		var b: Array = _bars[i]
		var on := i < bars.size()
		b[0].visible = on
		b[1].visible = on
		if on:
			b[0].text = String(bars[i][0])
			b[2].size.x = b[1].size.x * clampf(float(bars[i][1]), 0.0, 1.0)
			b[2].color = bars[i][2]
	var ws := world.source_label
	if running or g.over:
		_hud_source.text = source_text + ("\n" + ws if ws.begins_with("PAID") else "")
	else:
		_hud_source.text = ws if ws.begins_with("DEMO") else "DEMO: the cabinet plays itself, no credit spent"
	var f := float(h.get("flash", 0.0))
	var fc: Color = h.get("flash_color", MAGENTA)
	_flash_rect.color = Color(fc, clampf(f, 0.0, 1.0) * 0.35)


## Anchors a control to a preset and puts its rect at pos/size relative to that anchor.
static func _place(c: Control, preset: int, pos: Vector2, size: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + size.x
	c.offset_bottom = pos.y + size.y


func _label(parent: Control, size: int, color: Color, variation: String = "MonoLabel") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_hud(root: Control) -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.visible = false
	root.add_child(_hud)
	var tl := VBoxContainer.new()
	tl.position = Vector2(36, 26)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(tl)
	_hud_title = _label(tl, 22, ICE, "DisplayLabel")
	_hud_score = _label(tl, 54, Color("#e9edf4"))
	_hud_lives = _label(tl, 26, ICE)
	_bar_box = VBoxContainer.new()
	_bar_box.add_theme_constant_override("separation", 4)
	tl.add_child(_bar_box)
	for i in 2:
		var l := _label(_bar_box, 14, GOLD)
		var bg := ColorRect.new()
		bg.custom_minimum_size = Vector2(300, 12)
		bg.color = Color(1, 1, 1, 0.08)
		_bar_box.add_child(bg)
		var fill := ColorRect.new()
		fill.size = Vector2(300, 12)
		bg.add_child(fill)
		_bars.append([l, bg, fill])
	var tr := VBoxContainer.new()
	_place(tr, Control.PRESET_TOP_RIGHT, Vector2(-420, 30), Vector2(380, 200))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(tr)
	_hud_stats = _label(tr, 22, GOLD)
	_hud_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_stats.custom_minimum_size = Vector2(380, 0)
	_hud_center = _label(_hud, 64, GOLD, "DisplayLabel")
	_place(_hud_center, Control.PRESET_CENTER, Vector2(-500, -200), Vector2(1000, 90))
	_hud_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_source = _label(_hud, 15, Color("#8e97a9"))
	_place(_hud_source, Control.PRESET_BOTTOM_LEFT, Vector2(36, -118), Vector2(1100, 50))
	_hud_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _button(parent: Control, text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # Space and Enter belong to the game
	b.pressed.connect(func(): sig.emit())
	parent.add_child(b)
	return b


func _build_menu(root: Control) -> void:
	menu = PanelContainer.new()
	menu.theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style(Color(ICE, 0.35))
	sb.bg_color = Color(0.01, 0.012, 0.025, 0.86)
	menu.add_theme_stylebox_override("panel", sb)
	menu.custom_minimum_size = Vector2(600, 0)
	_place(menu, Control.PRESET_CENTER_RIGHT, Vector2(-680, -340), Vector2(620, 100))
	menu.visible = false
	root.add_child(menu)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	menu.add_child(col)
	menu_title = Label.new()
	menu_title.theme_type_variation = "DisplayLabel"
	menu_title.add_theme_font_size_override("font_size", 30)
	menu_title.add_theme_color_override("font_color", ICE)
	menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_title.custom_minimum_size = Vector2(560, 0)
	col.add_child(menu_title)
	menu_blurb = Label.new()
	menu_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_blurb.custom_minimum_size = Vector2(560, 0)
	menu_blurb.add_theme_font_size_override("font_size", 19)
	col.add_child(menu_blurb)
	var ch := Label.new()
	ch.theme_type_variation = "DisplayLabel"
	ch.add_theme_font_size_override("font_size", 14)
	ch.add_theme_color_override("font_color", ICE)
	ch.text = "HOW TO PLAY  ·  %s: this card again in a run" % ControlsHelp.key_of(GameHowto.HELP_ACTION)
	col.add_child(ch)
	menu_controls = GameHowto.controls_grid([], 18, 380.0)
	col.add_child(menu_controls)
	menu_info = Label.new()
	menu_info.theme_type_variation = "MutedLabel"
	menu_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_info.custom_minimum_size = Vector2(560, 0)
	col.add_child(menu_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	pay_button = _button(row, "Pay", pay_pressed)
	strip_button = _button(row, "Strip", strip_pressed)
	start_button = _button(row, "Play", start_pressed)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	col.add_child(row2)
	view_button = _button(row2, "Classic screen", view_pressed)
	leave_button = _button(row2, "Leave the cabinet (Esc)", leave_pressed)
	daily_row = HBoxContainer.new()
	daily_row.add_theme_constant_override("separation", 10)
	daily_row.visible = false
	col.add_child(daily_row)
	daily_button = _button(daily_row, "Today's challenge", daily_pressed)
	daily_practice_button = _button(daily_row, "Practice", daily_practice_pressed)
	col.add_child(HSeparator.new())
	scores_title = Label.new()
	scores_title.theme_type_variation = "MutedLabel"
	scores_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scores_title.custom_minimum_size = Vector2(560, 0)
	scores_title.add_theme_font_size_override("font_size", 13)
	col.add_child(scores_title)
	scores_label = Label.new()
	scores_label.theme_type_variation = "MonoLabel"
	scores_label.add_theme_font_size_override("font_size", 15)
	scores_label.add_theme_color_override("font_color", GOLD)
	col.add_child(scores_label)
