class_name DeepFieldView
extends ColorRect
## A rect that draws a Deep Field picture on the GPU. Feed it params from
## DeepField.params()/for_territory()/for_identity(). It registers an
## explanation with the "How is this drawn?" inspector.

const SHADER := preload("res://assets/shaders/deep_field.gdshader")
const STYLE_INDEX := {"glow": 0, "duo": 1, "bands": 2, "ember": 3, "gilded": 4, "prism": 5}

@export var animate_bands := true
@export var max_iter := 160

var params: Dictionary = {}
var explanation := ""
var _mat: ShaderMaterial
var _t := 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	color = Color.BLACK
	resized.connect(_update_aspect)
	_update_aspect()
	if not params.is_empty():
		apply_params(params, explanation)


## Applies chain-derived params. `why` is a plain-words line for the inspector.
func apply_params(p: Dictionary, why: String = "") -> void:
	params = p
	explanation = why
	if _mat == null:
		return
	var c: Array = p["c"]
	_mat.set_shader_parameter("c", Vector2(c[0], c[1]))
	_mat.set_shader_parameter("power", int(p["power"]))
	_mat.set_shader_parameter("color", Vector3(p["color"][0], p["color"][1], p["color"][2]))
	_mat.set_shader_parameter("color2", Vector3(p["color2"][0], p["color2"][1], p["color2"][2]))
	_mat.set_shader_parameter("hue", float(p["hue"]))
	_mat.set_shader_parameter("style", STYLE_INDEX.get(String(p["style"]), 0))
	_mat.set_shader_parameter("max_iter", max_iter)
	set_view(Vector2.ZERO, float(p["extent"]), float(p["rotation"]))
	if why != "":
		Inspector.register(self, "Deep Field picture", why)


## Frame the picture: center (complex plane), scale (half-height in complex units), angle.
func set_view(center: Vector2, scale: float, angle: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("view_scale", scale)
	_mat.set_shader_parameter("view_angle", angle)


func set_mirror(on: bool) -> void:
	if _mat:
		_mat.set_shader_parameter("mirror", on)


func set_intensity(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("intensity", v)


func _update_aspect() -> void:
	if _mat and size.y > 0.0:
		_mat.set_shader_parameter("aspect", size.x / size.y)


## Renders a SubViewport holding a Deep Field picture at `hz` instead of every
## frame (WP 7.5): the picture only drifts slowly, so 4 Hz looks the same and
## costs a fraction of the GPU time.
static func throttle(vp: SubViewport, hz: float = 4.0) -> void:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var t := Timer.new()
	t.wait_time = 1.0 / hz
	t.autostart = true
	t.timeout.connect(func(): vp.render_target_update_mode = SubViewport.UPDATE_ONCE)
	vp.add_child(t)


func _process(delta: float) -> void:
	if animate_bands and _mat and not params.is_empty():
		_t += delta
		_mat.set_shader_parameter("phase", -_t * 0.6)
