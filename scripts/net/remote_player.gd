class_name RemotePlayer
extends Node3D
## Another player in this territory (Net): a HumanAvatar driven by the
## interpolated pose, a name tag, a speaking mark, chat bubbles and their
## voice played at the avatar (AudioStreamPlayer3D + AudioStreamGenerator).
## Uses HumanAvatar's public API only (set_head, set_body, update_movement,
## set_seated). Someone driving or on a ride is drawn seated (simplified).

const TAG_Y := 2.25
const BUBBLE_S := 6.0
const VOICE_RATE := 16000.0

var peer_id := -1
var wallet := ""
var display_name := ""
## Read by HumanAvatar (its parent's crouch).
var is_crouching := false

var avatar: HumanAvatar
var tag: Label3D
var speak_mark: Label3D
var bubble: Label3D
var _bubble_bg: MeshInstance3D
var _bubble_t := 0.0
var voice: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _voice_t := 0.0
var _flag_speaking := false
var _seated := false
var _head := ""


func setup(info: Dictionary) -> void:
	peer_id = int(info.get("id", -1))
	avatar = HumanAvatar.new()
	avatar.civilian = true  # ~16 meshes, like the pub's regulars
	avatar.name = "Avatar"
	add_child(avatar)
	tag = _label(28, Color(0.86, 0.93, 1.0))
	tag.position.y = TAG_Y
	speak_mark = _label(34, Color(0.45, 1.0, 0.7))
	speak_mark.position.y = TAG_Y + 0.32
	speak_mark.text = "◉ ))"
	speak_mark.visible = false
	bubble = _label(30, Color(1, 1, 1))
	bubble.position.y = TAG_Y + 0.75
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 520.0
	bubble.render_priority = 2
	bubble.outline_render_priority = 1
	bubble.visible = false
	_bubble_bg = MeshInstance3D.new()
	var q := QuadMesh.new()
	_bubble_bg.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.03, 0.05, 0.09, 0.78)
	m.no_depth_test = true
	m.render_priority = 0
	_bubble_bg.material_override = m
	_bubble_bg.visible = false
	_bubble_bg.layers = 2
	add_child(_bubble_bg)
	voice = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VOICE_RATE
	gen.buffer_length = 0.4
	voice.stream = gen
	voice.position.y = 1.6
	voice.unit_size = 8.0
	voice.max_distance = 45.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(voice)
	apply_info(info)


func _label(px: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.0042
	l.font_size = px
	l.outline_size = 10
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.render_priority = 1
	l.layers = 2
	add_child(l)
	return l


## Name, wallet and look from the server's peer record.
func apply_info(info: Dictionary) -> void:
	wallet = String(info.get("wallet", ""))
	var guest: bool = info.get("guest", true) or wallet == ""
	display_name = String(info.get("name", ""))
	var shown := display_name if display_name != "" else ("guest" if guest else NetProto.short_wallet(wallet))
	tag.text = shown + ("" if guest else "\n" + NetProto.short_wallet(wallet))
	tag.modulate = Color(0.7, 0.74, 0.8) if guest else Color(0.86, 0.93, 1.0)
	var head := String(info.get("head", "bear"))
	var acc: Array = info.get("acc", []) if info.get("acc") is Array else []
	var key := head + "|" + ",".join(acc) + "|" + String(info.get("body", "male"))
	if key != _head and avatar.is_inside_tree():
		_head = key
		avatar.set_body(String(info.get("body", "male")))
		avatar.set_head(head, acc)
	elif not avatar.is_inside_tree():
		avatar.ready.connect(func(): apply_info(info), CONNECT_ONE_SHOT)


## A pose from NetInterp.sample().
func apply_pose(s: Dictionary) -> void:
	if s.is_empty():
		return
	global_position = s["pos"]
	avatar.rotation.y = float(s["yaw"])
	var flags: int = s["flags"]
	is_crouching = flags & NetProto.F_CROUCH != 0
	_flag_speaking = flags & NetProto.F_SPEAKING != 0
	var seated := flags & NetProto.F_SEATED != 0
	var anim: String = NetProto.ANIMS[int(s["anim"])]
	if seated != _seated:
		_seated = seated
		avatar.set_seated("Driving" if seated else "")
	avatar.hold_clip = anim if not seated else ""
	if not seated:
		avatar.update_movement(s["vel"], flags & NetProto.F_ON_FLOOR != 0, flags & NetProto.F_FLYING != 0)


func say(text: String) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_t = BUBBLE_S + text.length() * 0.05
	_size_bubble.call_deferred()


func _size_bubble() -> void:
	var lines := maxi(1, ceili(bubble.text.length() / 34.0))
	var w := minf(bubble.text.length(), 34.0) * bubble.font_size * 0.55 * bubble.pixel_size + 0.3
	var h := lines * bubble.font_size * 1.25 * bubble.pixel_size + 0.2
	(_bubble_bg.mesh as QuadMesh).size = Vector2(w, h)
	_bubble_bg.position = bubble.position - Vector3(0, 0, 0.01)
	_bubble_bg.visible = true


func play_voice(pcm: PackedFloat32Array, volume: float) -> void:
	_voice_t = 0.3
	if not voice.playing:
		voice.play()
		_playback = voice.get_stream_playback()
	if _playback == null:
		return
	voice.volume_db = linear_to_db(maxf(volume, 0.001))
	var room := _playback.get_frames_available()
	var n := mini(room, pcm.size())
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		frames[i] = Vector2(pcm[i], pcm[i])
	_playback.push_buffer(frames)


func _process(delta: float) -> void:
	_voice_t = maxf(0.0, _voice_t - delta)
	speak_mark.visible = _voice_t > 0.0 or _flag_speaking
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			bubble.visible = false
			_bubble_bg.visible = false
