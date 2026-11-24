class_name TableSeat
extends CanvasLayer
## Sitting down at a table, and standing back up: the camera leaves the
## player, glides into the seat (a soft arc, a slight lift) and from then on
## follows whatever view the table's controller (PoolSeat, CardSeat) asks for.
## Esc reverses the move back to the player's own camera.
##
## The overlay is the arcade dive's style (ArcadeDive): title and headline top
## left, numbers top right, a big centre call, where the numbers come from at
## the bottom left and the controls at the bottom. It is presentation only:
## every move still goes through TableBook (a room line: simulate, sign, the
## receipt, read back) in the controller.

signal entered
signal exited

enum Phase { IDLE, ENTERING, INSIDE, LEAVING }

const T_IN := 1.05
const T_OUT := 0.85
const ICE := Color("#7fe9ff")
const GOLD := Color("#ffd36b")
const MAGENTA := Color("#ff4fd8")
const INK := Color("#e9edf4")
const DIM := Color("#8e97a9")
const LIVE := Color("#7dffa8")
const PRACTICE := Color("#ffb86b")

var phase := Phase.IDLE
var cam: Camera3D
var target := Transform3D()  ## where the controller wants the camera (global)
var target_fov := 62.0
var follow_rate := 5.0  ## 1/s: how fast the camera eases toward `target` while seated
var freeze_at := -1.0  ## previews: hold the sit-down at this fraction (0..1)

var _from_cam: Camera3D
var _start_xf := Transform3D()
var _start_fov := 70.0
var _clock := 0.0
var _model: Node3D
var _hidden: Array = []  # CanvasLayers hidden while seated

var _hud: Control
var title: Label
var headline: Label
var badge: Label
var stats: Label
var center: Label
var status: Label
var source: Label
var hint: Label
var _meter: VBoxContainer
var _meter_label: Label
var _meter_bg: ColorRect
var _meter_fill: ColorRect
var _toast: Label
var _toast_t := 0.0
var _center_t := 0.0


func _ready() -> void:
	layer = 24
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DeepFieldTheme.get_theme()
	add_child(root)
	_build_hud(root)


func is_active() -> bool:
	return phase != Phase.IDLE


func is_inside() -> bool:
	return phase == Phase.INSIDE


## Sits down: the camera moves from the player's view to `to` (global).
## `hide_layers`: CanvasLayers (the place's HUD) to hide while seated.
func enter(to: Transform3D, fov: float, model: Node3D, hide_layers: Array = []) -> void:
	if phase != Phase.IDLE:
		return
	_model = model
	_from_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.near = 0.02
	get_parent().add_child(cam)
	_start_xf = _from_cam.global_transform if _from_cam else to
	_start_fov = _from_cam.fov if _from_cam else fov
	cam.global_transform = _start_xf
	cam.fov = _start_fov
	cam.make_current()
	target = to
	target_fov = fov
	_hidden = []
	for l in hide_layers:
		if l and l.visible:
			l.visible = false
			_hidden.append(l)
	_hud.visible = false
	center.text = ""
	status.text = ""
	_clock = 0.0
	phase = Phase.ENTERING
	_frame_in(0.0)


## Stands up: back to the player's own camera.
func leave() -> void:
	if phase != Phase.INSIDE and phase != Phase.ENTERING:
		return
	_hud.visible = false
	_start_xf = cam.global_transform
	_start_fov = cam.fov
	_clock = 0.0
	freeze_at = -1.0
	phase = Phase.LEAVING
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## A glide with a little lift in the middle (you step up to the table and lean in).
static func glide(a: Transform3D, b: Transform3D, e: float, lift: float = 0.25) -> Transform3D:
	var o := a.origin.lerp(b.origin, e) + Vector3.UP * sin(e * PI) * lift
	var qa := a.basis.orthonormalized().get_rotation_quaternion()
	var qb := b.basis.orthonormalized().get_rotation_quaternion()
	return Transform3D(Basis(qa.slerp(qb, e)), o)


func _frame_in(t: float) -> void:
	var e := _smooth(t / T_IN)
	cam.global_transform = glide(_start_xf, target, e)
	cam.fov = lerpf(_start_fov, target_fov, e)
	if _model and is_instance_valid(_model):
		_model.visible = e < 0.35


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if _center_t > 0.0:
		_center_t -= delta
		center.modulate.a = clampf(_center_t * 2.0, 0.0, 1.0)
		if _center_t <= 0.0:
			center.text = ""
	match phase:
		Phase.ENTERING:
			_clock += delta
			if freeze_at >= 0.0:
				_clock = minf(_clock, freeze_at * T_IN)
			_frame_in(_clock)
			if _clock >= T_IN:
				phase = Phase.INSIDE
				_hud.visible = true
				entered.emit()
		Phase.INSIDE:
			var w := 1.0 - exp(-follow_rate * delta)
			cam.global_transform = cam.global_transform.interpolate_with(target, w)
			cam.fov = lerpf(cam.fov, target_fov, w)
		Phase.LEAVING:
			_clock += delta
			var e := _smooth(_clock / T_OUT)
			var back := _from_cam.global_transform if _from_cam and is_instance_valid(_from_cam) else _start_xf
			var back_fov := _from_cam.fov if _from_cam and is_instance_valid(_from_cam) else _start_fov
			cam.global_transform = glide(_start_xf, back, e, 0.15)
			cam.fov = lerpf(_start_fov, back_fov, e)
			if _model and is_instance_valid(_model):
				_model.visible = e > 0.6
			if _clock >= T_OUT:
				_done()


## Jumps the camera to the target now (a cut, e.g. to the overhead view).
func snap() -> void:
	if cam and phase == Phase.INSIDE:
		cam.global_transform = target
		cam.fov = target_fov


func _done() -> void:
	if _from_cam and is_instance_valid(_from_cam):
		_from_cam.make_current()
	if _model and is_instance_valid(_model):
		_model.visible = true
	for l in _hidden:
		if is_instance_valid(l):
			l.visible = true
	_hidden = []
	cam.queue_free()
	cam = null
	phase = Phase.IDLE
	exited.emit()


# --- The overlay ---------------------------------------------------------------

## A big call in the centre that fades after `seconds` (0: stays).
func call_out(text: String, color: Color = GOLD, seconds: float = 2.2) -> void:
	center.text = text
	center.add_theme_color_override("font_color", color)
	center.modulate.a = 1.0
	_center_t = seconds if seconds > 0.0 else 0.0


func show_toast(text: String, seconds: float = 5.0) -> void:
	_toast.text = text
	_toast_t = seconds
	_toast.modulate.a = 1.0
	_toast.visible = true


## The mode badge: live (a room line) or practice (local only).
func set_badge(text: String, live: bool) -> void:
	badge.text = text
	badge.add_theme_color_override("font_color", LIVE if live else PRACTICE)


## The power meter (hidden when `v` < 0).
func set_meter(v: float, text: String = "") -> void:
	_meter.visible = v >= 0.0
	if v < 0.0:
		return
	_meter_label.text = text
	_meter_fill.size = Vector2(_meter_bg.custom_minimum_size.x * clampf(v, 0.0, 1.0), _meter_bg.custom_minimum_size.y)
	_meter_fill.color = Color(0.3, 1.0, 0.6).lerp(Color(1.0, 0.3, 0.45), clampf(v, 0.0, 1.0))


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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
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
	title = _label(tl, 22, ICE, "DisplayLabel")
	headline = _label(tl, 40, INK, "DisplayLabel")
	badge = _label(tl, 15, PRACTICE)
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.custom_minimum_size = Vector2(620, 0)
	status = _label(tl, 17, GOLD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(620, 0)
	var tr := VBoxContainer.new()
	_place(tr, Control.PRESET_TOP_RIGHT, Vector2(-440, 30), Vector2(400, 220))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(tr)
	stats = _label(tr, 19, GOLD)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats.custom_minimum_size = Vector2(400, 0)
	center = _label(_hud, 58, GOLD, "DisplayLabel")
	_place(center, Control.PRESET_CENTER, Vector2(-520, -190), Vector2(1040, 90))
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter = VBoxContainer.new()
	_place(_meter, Control.PRESET_CENTER_BOTTOM, Vector2(-230, -150), Vector2(460, 50))
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.add_theme_constant_override("separation", 4)
	_hud.add_child(_meter)
	_meter_label = _label(_meter, 15, INK)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_bg = ColorRect.new()
	_meter_bg.custom_minimum_size = Vector2(460, 14)
	_meter_bg.color = Color(1, 1, 1, 0.1)
	_meter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.add_child(_meter_bg)
	_meter_fill = ColorRect.new()
	_meter_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_bg.add_child(_meter_fill)
	_meter.visible = false
	source = _label(_hud, 14, DIM)
	_place(source, Control.PRESET_BOTTOM_LEFT, Vector2(36, -96), Vector2(1100, 50))
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = _label(_hud, 16, ICE)
	_place(hint, Control.PRESET_CENTER_BOTTOM, Vector2(-820, -42), Vector2(1640, 30))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast = Label.new()
	_toast.theme_type_variation = "DisplayLabel"
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", GOLD)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place(_toast, Control.PRESET_CENTER_TOP, Vector2(-600, 90), Vector2(1200, 80))
	_toast.visible = false
	root.add_child(_toast)
