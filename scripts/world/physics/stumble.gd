class_name Stumble
extends Node
## How a character takes being run into (KnockWorld): no punches, only bumps.
##   NUDGE    (walking into them) a lean and a sidestep, then back;
##   STUMBLE  (a jog, or another player) the Hit_Chest clip, a lean, an "oof";
##   FALL     (running, a vehicle) the UAL Death01 clip turned to fall the way
##            they were pushed, a thud, a moment on the ground, the clip back
##            the other way to get up, a brush-off line.
## It rides on a HumanAvatar (its react() and overlay hooks), so it works for
## the fair's crowd, the pub's regulars, the Steward, speaker echoes and other
## players' avatars alike. Owners that move the character check busy() and
## hold still while someone is down.
##
##   Stumble.attach(avatar)                       # an NPC
##   Stumble.attach(avatar, {"max_level": BumpMath.STUMBLE, "peer_id": id})  # another player
##   Stumble.attach(model, {"enlisted": false})   # the local player's own model (net bumps only)

signal bumped(level: int, dir: Vector3, by: Node3D)

const OOF := ["oof!", "whoa!", "hey!", "oi!", "easy!", "ow!", "steady…", "mind out!"]
const NUDGE_LINES := ["hey", "pardon", "'scuse me", "careful", "oh!"]
const UP := ["…I'm fine", "all good", "ha, watch it", "who put the ground there", "no harm done", "carry on", "ow. ok."]
const FALL_SPEED := 1.6     ## Death01 (2.4 s) plays at this speed going down
const GETUP_SPEED := 2.2    ## and backwards at this speed getting up
const LIE_S := 0.8
const STUMBLE_S := 0.9
const PLAYER_STUMBLE_S := 0.6  ## another player: a brief stagger at most
const NUDGE_S := 0.7

var avatar: Node3D
var peer_id := -1
var max_level := BumpMath.FALL
var enlisted := true
var quiet := false  ## no bubble or sound (previews)

var level := BumpMath.NONE
var t := 0.0
var _dur := 0.0
var _dir := Vector3.BACK   # the push, in the avatar's own space
var _yaw := 0.0            # the body turned so Death01 falls along the push
var _yaw_w := 0.0
var _phase := 0            # FALL: 0 going down, 1 lying, 2 getting up, 3 brushing off
var _lean := Vector2.ZERO  # spring: angle (rad), rate
var _side := Vector2.ZERO  # spring: sidestep (m), rate
var _cool_until := 0.0
var _now := 0.0
var _last_pos := Vector3.INF
var _vel := Vector3.ZERO
var _world: Node
var _bubble: Label3D
var _bubble_t := 0.0


static func attach(av: Node3D, opts: Dictionary = {}) -> Stumble:
	var s := Stumble.new()
	s.name = "Stumble"
	s.avatar = av
	s.peer_id = int(opts.get("peer_id", -1))
	s.max_level = int(opts.get("max_level", BumpMath.FALL))
	s.enlisted = bool(opts.get("enlisted", true))
	av.add_child(s)
	return s


## The Stumble riding on `av`, if any.
static func on(av: Node) -> Stumble:
	return av.get_node_or_null("Stumble") as Stumble if av else null


func _enter_tree() -> void:
	if avatar == null:
		avatar = get_parent() as Node3D
	if enlisted:
		_world = KnockWorld.of(self)
		if _world:
			_world.add_character(self)


func _exit_tree() -> void:
	if _world and is_instance_valid(_world):
		_world.remove_character(self)
	_world = null


## Someone is down or getting up: the owner should not walk them about.
func busy() -> bool:
	return level == BumpMath.FALL


func velocity() -> Vector3:
	return _vel


## Seated (a stool, a sofa, a ride, a dance on the spot) or another player: no falling.
func can_fall() -> bool:
	if max_level < BumpMath.FALL or avatar == null:
		return false
	if avatar.position.y < -0.2 or avatar.position.y > 0.2:
		return false  # AmbientNPC's sit lowers the model; a hop lifts it
	var seat = avatar.get("_seat_clip")
	if seat is String and seat != "":
		return false
	var hold = avatar.get("hold_clip")
	return not (hold is String and String(hold).begins_with("Sitting"))


func ready_for(p_level: int) -> bool:
	return _now >= _cool_until and p_level > level


## Takes a bump along `dir` (global, horizontal) at `p_level` from `by`.
func bump(dir: Vector3, p_level: int, by: Node3D = null) -> void:
	p_level = mini(p_level, max_level)
	if p_level == BumpMath.FALL and not can_fall():
		p_level = BumpMath.STUMBLE
	if p_level == BumpMath.NONE or avatar == null:
		return
	var flying = avatar.get("_flying")
	if flying is bool and flying and p_level == BumpMath.FALL:
		p_level = BumpMath.STUMBLE
	var local := avatar.global_basis.orthonormalized().inverse() * dir
	local.y = 0.0
	_dir = local.normalized() if local.length() > 1e-3 else Vector3.BACK
	level = p_level
	t = 0.0
	_cool_until = _now + BumpMath.cooldown(p_level)
	match p_level:
		BumpMath.NUDGE:
			_dur = NUDGE_S
			_lean.y += 1.6
			_side.y += 1.4
			if randf() < 0.35:
				_say(NUDGE_LINES[randi() % NUDGE_LINES.size()], 1.1)
		BumpMath.STUMBLE:
			_dur = PLAYER_STUMBLE_S if max_level < BumpMath.FALL else STUMBLE_S
			_lean.y += 4.5
			_side.y += 2.2
			_react("Hit_Chest", 1.25)
			_say(OOF[randi() % OOF.size()], 1.3)
			_sound("oof", 0.8)
		BumpMath.FALL:
			_phase = 0
			_yaw = atan2(-_dir.x, -_dir.z)  # Death01 falls backwards (-Z, the avatar faces +Z)
			_yaw_w = 0.0
			_lean.y += 2.0
			_react("Death01", FALL_SPEED)
			_say(OOF[randi() % OOF.size()], 1.6)
			_sound("oof", 1.0)
	bumped.emit(p_level, dir, by)


func _react(clip: String, speed: float, backwards: bool = false) -> void:
	if avatar.has_method("react"):
		avatar.react(clip, speed, backwards)


func _physics_process(delta: float) -> void:
	_now += delta
	if avatar == null or not avatar.is_inside_tree():
		return
	var p := avatar.global_position
	if _last_pos != Vector3.INF:
		_vel = (p - _last_pos) / maxf(delta, 1e-4)
		if _vel.length() > 40.0:
			_vel = Vector3.ZERO
	_last_pos = p


func _process(delta: float) -> void:
	if _bubble:
		_bubble_t -= delta
		_bubble.position.y += delta * 0.35
		_bubble.modulate.a = clampf(_bubble_t / 0.4, 0.0, 1.0)
		_bubble.outline_modulate.a = _bubble.modulate.a * 0.85
		if _bubble_t <= 0.0:
			_bubble.queue_free()
			_bubble = null
	if level == BumpMath.NONE and _lean.is_zero_approx() and _side.is_zero_approx():
		return
	t += delta
	match level:
		BumpMath.FALL:
			_fall_step(delta)
		BumpMath.NUDGE, BumpMath.STUMBLE:
			if t >= _dur:
				if level == BumpMath.STUMBLE:
					_react("", 1.0)
				level = BumpMath.NONE
	_lean = BumpMath.spring_step(_lean.x, _lean.y, 0.0, 70.0, 10.0, delta)
	_side = BumpMath.spring_step(_side.x, _side.y, 0.0, 22.0, 7.5, delta)
	if level == BumpMath.NONE and absf(_lean.x) < 1e-3 and absf(_lean.y) < 1e-3 and absf(_side.x) < 1e-3 and absf(_side.y) < 1e-3:
		_lean = Vector2.ZERO
		_side = Vector2.ZERO
	_apply()


func _fall_step(delta: float) -> void:
	var down_s := 2.4 / FALL_SPEED
	var up_s := 2.4 / GETUP_SPEED
	match _phase:
		0:
			_yaw_w = minf(1.0, _yaw_w + delta / 0.15)
			if t >= down_s * 0.42 and t - delta < down_s * 0.42:
				_sound("thud", 0.9)
			if t >= down_s:
				_phase = 1
				t = 0.0
		1:
			if t >= LIE_S:
				_phase = 2
				t = 0.0
				_react("Death01", GETUP_SPEED, true)
		2:
			if t >= up_s:
				_phase = 3
				t = 0.0
				_react("", 1.0)
				_say(UP[randi() % UP.size()], 1.8)
		3:
			_yaw_w = maxf(0.0, _yaw_w - delta / 0.3)
			# A little brush-off shimmy as they turn back.
			_side.x = sin(t * 18.0) * 0.02 * (1.0 - t / 0.5)
			if t >= 0.5:
				_yaw_w = 0.0
				level = BumpMath.NONE


## The overlay on the avatar's body: turned for the fall, leaning with the push, stepped aside.
func _apply() -> void:
	if not ("overlay" in avatar):
		return
	var axis := Vector3.UP.cross(_dir)
	var basis := Basis(Vector3.UP, _yaw * _yaw_w)
	if axis.length() > 1e-3 and absf(_lean.x) > 1e-4:
		basis = Basis(axis.normalized(), clampf(_lean.x, -0.5, 0.5)) * basis
	avatar.set("overlay", Transform3D(basis, _dir * clampf(_side.x, -0.5, 0.5)))


## A quick line over their head that rises and fades (not chat: nothing is posted).
func _say(text: String, seconds: float) -> void:
	if quiet or avatar == null:
		return
	if _bubble:
		_bubble.queue_free()
	var l := Label3D.new()
	l.text = text
	l.font = DeepFieldTheme.body_font()
	l.font_size = 30
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.96, 0.85)
	l.outline_size = 8
	l.outline_modulate = Color(0.05, 0.03, 0.08, 0.85)
	l.position = Vector3(0, 2.15, 0)
	avatar.add_child(l)
	_bubble = l
	_bubble_t = seconds


func _sound(id: String, strength: float) -> void:
	if not quiet and avatar:
		BumpSfx.play_at(self, avatar.global_position + Vector3(0, 1.0, 0), id, strength)
