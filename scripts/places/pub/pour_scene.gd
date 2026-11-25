class_name PourScene
extends Node3D
## Watching your drink poured at Sunny's bar (the owner, 2026-11-25: "the menu stays up the whole
## time so you can't see him pour the drink and the player drink it"). Played only after the
## drink's receipt was verified (BarMenu.poured / round_bought): the menu is out of the way and a
## camera watches Sunny pour and slide the glass down the counter, hand it over, and the player
## pick it up and drink; then the camera goes back to the player and the menu returns with what
## the chain measured. Any key skips to the end.
##
## Presentation only: nothing here reads or writes the chain. The timeline is pure (shot_at,
## drink_weight) and tested.

signal finished

## [from second, shot]: the camera cuts at these times.
const SHOTS := [[0.0, "pour"], [1.45, "slide"], [2.75, "handover"], [4.1, "drink"], [7.7, "cheers"]]
const T_PICK := 3.9     ## the glass leaves the counter for the player's hand
const T_SIP := [4.3, 7.3]  ## the drink pose rises from the first and is down by the second
const T_RAMP := 0.6
const T_END := 9.2
const PLAYER_Z := -4.6  ## where the player stands to drink (pub space; the counter's face is at -5.0)

var hold_at := -1.0     ## previews: hold the timeline at this second
var _t := 0.0
var _running := false
var _pub: Node3D
var _life: PubLife
var _player: Node3D
var _model: Node3D
var _cam: Camera3D
var _prev_cam: Camera3D
var _glass: Node3D
var _px := PubRoom.ORDER_X
var _shot := ""
var _say: Callable      ## (line id, detail): Sunny speaks (VoiceLines through the pub)
var _cues := {}         ## line cues already said
var _detail := ""
var _rounds := 1
var _model_mode := Node.PROCESS_MODE_INHERIT
var _from := Vector3.ZERO


## Pure: the shot at second t.
static func shot_at(t: float) -> String:
	var s := String(SHOTS[0][1])
	for e in SHOTS:
		if t >= float(e[0]):
			s = String(e[1])
	return s


## Pure: how far the drink pose is raised at second t (0..1).
static func drink_weight(t: float) -> float:
	var a: float = T_SIP[0]
	var b: float = T_SIP[1]
	if t <= a or t >= b:
		return 0.0
	return clampf(minf((t - a) / T_RAMP, (b - t) / T_RAMP), 0.0, 1.0)


## Pure: where the camera is for a shot, [eye, look at], in pub space; `px` is the player's x.
static func camera_for(shot: String, px: float) -> Array:
	var p := Vector3(px, 0.0, PLAYER_Z)
	match shot:
		"pour":
			return [Vector3(-1.45, 1.75, -3.95), Vector3(-2.9, 1.3, -6.0)]
		"slide":
			return [Vector3(px + 1.9, 1.6, -3.7), Vector3(px - 1.2, 1.15, -5.5)]
		"handover":
			return [p + Vector3(0.7, 1.85, 1.45), Vector3(px - 0.2, 1.35, -6.1)]
		"drink":
			return [p + Vector3(1.25, 1.62, -0.5), p + Vector3(0.0, 1.5, 0.0)]
		"cheers":
			return [p + Vector3(2.2, 1.9, 1.6), p + Vector3(-0.6, 1.35, -0.9)]
	return [p + Vector3(0, 1.8, 2.0), p + Vector3(0, 1.4, -1.0)]


func is_running() -> bool:
	return _running


## Starts the scene. `look`: the drink's [colour, glass kind]; `rounds` glasses; `say` speaks a line.
func play(pub: Node3D, life: PubLife, player: Node3D, look: Array, rounds: int, detail: String, say: Callable) -> void:
	_pub = pub
	_life = life
	_player = player
	_model = player.get_node_or_null("PlayerModel") if player else null
	_say = say
	_detail = detail
	_rounds = rounds
	_cues = {}
	_t = 0.0
	_running = true
	# Stand at the counter, facing the bar (the camera is on Sunny while you step up).
	_px = clampf(player.global_position.x if player else PubRoom.ORDER_X, PubRoom.COUNTER_X0 + 0.8, PubRoom.COUNTER_X1 - 0.8)
	if player:
		_from = player.global_position
	if _model:
		_model_mode = _model.process_mode
		_model.process_mode = Node.PROCESS_MODE_ALWAYS  # the player is paused at the bar; the body still moves
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 52.0
	_cam.near = 0.03
	add_child(_cam)
	_cam.make_current()
	life.play_pour(look, rounds)
	var g := life.served(rounds)
	_glass = g[0] if not g.is_empty() else null
	_frame(0.0)


## Previews: jump to second t and hold there.
func preview_at(t: float) -> void:
	_t = t
	hold_at = t
	if _player:
		_player.global_position = _pub.to_global(Vector3(_px, _from.y, PLAYER_Z))
		_player.rotation.y = 0.0
		_from = _player.global_position
	_frame(0.0)


## Jumps to the end (any key).
func skip() -> void:
	if _running:
		_finish()


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	if hold_at >= 0.0:
		_t = minf(_t, hold_at)
	_frame(delta)
	if _t >= T_END:
		_finish()


func _frame(delta: float) -> void:
	var shot := shot_at(_t)
	var cam: Array = camera_for(shot, _px)
	var eye: Vector3 = _pub.to_global(cam[0])
	var at: Vector3 = _pub.to_global(cam[1])
	if shot != _shot or delta <= 0.0:
		_shot = shot
		_cam.global_position = eye  # a cut
	else:
		_cam.global_position = _cam.global_position.lerp(eye + (eye - at).normalized() * 0.002 * _t, minf(1.0, delta * 3.0))  # a slow push
	_cam.look_at(at)
	# The player steps up to the counter while the camera is on Sunny.
	if _player and _t < 1.4:
		var to := _pub.to_global(Vector3(_px, _from.y, PLAYER_Z))
		_player.global_position = _from.lerp(to, smoothstep(0.0, 1.0, _t / 1.4))
		_player.rotation.y = lerp_angle(_player.rotation.y, 0.0, minf(1.0, delta * 6.0))
	if _model and _model.has_method("update_movement"):
		_model.update_movement(Vector3.ZERO, true, false)
	# Sunny's lines and moves, once each.
	_cue(0.05, "pour" if _rounds == 1 else "round_cheers", "")
	if _t >= 2.6 and not _cues.has("attend"):
		_cues["attend"] = true
		_life.attend(_pub.to_global(Vector3(_px, 0, PLAYER_Z)))
	_cue(2.8, "here_you_go", _detail)
	_cue(7.75, "cheers", "")
	# The glass: off the counter into the hand, then drunk.
	if _glass and is_instance_valid(_glass):
		if _t >= T_PICK and not _cues.has("pick"):
			_cues["pick"] = true
			_take_glass()
		var held := _glass.get_parent() != null and _glass.get_parent().name == "GlassHold"
		if held and _model:
			# Upright in the hand, tipped toward the mouth as it's drunk.
			var ax := _model.global_basis.x.normalized()
			_glass.global_basis = Basis(ax, -1.1 * drink_weight(_t)) * Basis.from_scale(_glass.global_basis.get_scale())
		var liquid: Node3D = _glass.get_node_or_null("Liquid")
		if liquid and _t > T_SIP[0] + T_RAMP:
			liquid.scale.y = lerpf(1.0, 0.3, clampf((_t - T_SIP[0] - T_RAMP) / (T_SIP[1] - T_SIP[0] - 2.0 * T_RAMP), 0.0, 1.0))
	if _model and "drink" in _model:
		_model.set("drink", drink_weight(_t))


func _cue(at: float, id: String, detail: String) -> void:
	if _t >= at and not _cues.has(id):
		_cues[id] = true
		if _say.is_valid():
			_say.call(id, detail)


## The glass into the right hand (a short lift, not a jump).
func _take_glass() -> void:
	var hand: Node3D = _model.call("right_hand") if _model and _model.has_method("right_hand") else null
	if hand == null:
		return
	var holder := Node3D.new()
	holder.name = "GlassHold"
	hand.add_child(holder)
	holder.scale = Vector3(1.0 / 0.85, 1.0 / 0.65, 1.0)  # undo the hand point's squash (as the fair's snacks)
	_life.take(_glass)
	var liquid: Node3D = _glass.get_node_or_null("Liquid")
	if liquid:
		liquid.scale = Vector3.ONE  # (a preview may jump here before the fill finished)
	_glass.reparent(holder, true)
	var tw := _glass.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_glass, "position", Vector3(0.0, -0.06, 0.02), 0.4)
	tw.tween_property(_glass, "scale", Vector3.ONE, 0.4)


func _finish() -> void:
	_running = false
	if _model and "drink" in _model:
		_model.set("drink", 0.0)
	if _model:
		_model.process_mode = _model_mode
	if _player:
		_player.global_position = _pub.to_global(Vector3(_px, _from.y, PLAYER_Z))
		_player.rotation.y = 0.0
	# The glass goes back on the counter in front of you (the pub clears it later).
	if _glass and is_instance_valid(_glass):
		var liquid: Node3D = _glass.get_node_or_null("Liquid")
		if liquid:
			liquid.scale.y = 0.3
		var holder := _glass.get_parent()
		_glass.reparent(_life, false)
		_glass.position = Vector3(_px - 0.25, PubRoom.COUNTER_H, PubRoom.COUNTER_Z + 0.3)
		_glass.rotation = Vector3.ZERO
		_glass.scale = Vector3.ONE
		if holder and holder.name == "GlassHold":
			holder.queue_free()
		_life.retire(_glass)
	_life.attend(Vector3.INF)
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if _cam:
		_cam.queue_free()
		_cam = null
	finished.emit()
