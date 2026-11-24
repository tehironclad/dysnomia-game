class_name DoorSequence
extends Node
## Walking through a door, played on the real player (DoorWalk is the
## timeline): ENTER walks the player to the door as it opens, the camera
## swinging in behind, and fades to black, then calls `done` (the scene
## change). ARRIVE starts the player on the threshold, fades in while they
## walk in, and shuts the door behind them.
##
## Never traps input: any key press skips, it ends on its own timeline even
## if the walk is blocked, and the player is always handed back (also if this
## node leaves the tree). Mouse look stays free.

signal finished

var walk: DoorWalk
var player: CharacterBody3D
var door: PassDoor
var owns_door := false   ## a curtain shown only for this pass: faded and freed at the end
var target := Vector3.ZERO
var face_yaw := 0.0
var done_cb := Callable()
var _rig: Node
var _fade: ScreenFade
var _ended := false
var _was_held := false
## Screenshots: hold the timeline at this many seconds (-1 = play).
var freeze_at := -1.0


static func active_in(host: Node) -> bool:
	for c in host.get_children():
		if c is DoorSequence and not (c as DoorSequence)._ended:
			return true
	return false


## Walk `p` from where it stands to `to` (through `p_door`), fade, then `p_done`.
static func enter(host: Node, p: CharacterBody3D, to: Vector3, p_door: PassDoor, p_done: Callable, p_owns := false) -> DoorSequence:
	var s := DoorSequence.new()
	s.walk = DoorWalk.new(DoorWalk.Kind.ENTER, Vector2(to.x - p.global_position.x, to.z - p.global_position.z).length())
	s.player = p
	s.target = to
	s.door = p_door
	s.owns_door = p_owns
	s.done_cb = p_done
	s.face_yaw = atan2(-(to.x - p.global_position.x), -(to.z - p.global_position.z))
	s.name = "DoorSequence"
	host.add_child(s)
	return s


## Put `p` at `from` facing along from→to and walk it in to `to`.
## `cam_yaw_offset` starts the camera that far round from behind (it swings
## in behind during the walk); 0 = behind from the start.
static func arrive(host: Node, p: CharacterBody3D, from: Vector3, to: Vector3, p_door: PassDoor, p_owns := false, cam_yaw_offset := 0.0) -> DoorSequence:
	var s := DoorSequence.new()
	s.walk = DoorWalk.new(DoorWalk.Kind.ARRIVE, Vector2(to.x - from.x, to.z - from.z).length())
	s.player = p
	s.target = to
	s.door = p_door
	s.owns_door = p_owns
	s.face_yaw = atan2(-(to.x - from.x), -(to.z - from.z))
	s.name = "DoorSequence"
	p.global_position = from
	p.velocity = Vector3.ZERO
	p.rotation.y = s.face_yaw
	var rig := p.get_node_or_null("CameraRig")
	if rig and "_yaw" in rig:
		rig.set("_yaw", s.face_yaw + cam_yaw_offset)
		rig.set("_yaw_ready", true)
		rig.set("_pitch", -0.18)
	host.add_child(s)
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ScreenFade.of(get_tree())
	_rig = player.get_node_or_null("CameraRig")
	if door:
		_was_held = door.held
		door.held = true
	if GameManager.is_flying:
		GameManager.toggle_fly_mode()  # on foot through a door (the body keeps its way and lands)
	if player.has_method("auto_walk_to"):
		player.auto_walk_to(target, walk.speed)
	_apply(0.0)


func _input(event: InputEvent) -> void:
	if _ended:
		return
	var key: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed)
	if key:
		get_viewport().set_input_as_handled()
		walk.skip()
		if walk.kind == DoorWalk.Kind.ARRIVE and is_instance_valid(player):
			player.global_position = Vector3(target.x, player.global_position.y, target.z)
			player.rotation.y = face_yaw
		_apply(0.0)


func _process(delta: float) -> void:
	if _ended:
		return
	if not is_instance_valid(player):
		_end()
		return
	if freeze_at >= 0.0:
		walk.t = minf(freeze_at, walk.total)
		delta = 0.0
	walk.step(delta)
	_apply(delta)
	if walk.done() and freeze_at < 0.0:
		_end()


func _apply(delta: float) -> void:
	_fade.set_alpha(walk.fade())
	if door and is_instance_valid(door):
		door.open = walk.door_open()
		if owns_door:
			# Shown only for this pass: lights up as you reach it, dims once you are through.
			door.set_strength(clampf(walk.t / 0.25, 0.0, 1.0) if walk.kind == DoorWalk.Kind.ENTER
				else clampf((walk.total - walk.t) / 0.4, 0.0, 1.0))
	if not walk.walking() and is_instance_valid(player) and player.has_method("auto_walk_stop"):
		player.auto_walk_stop()
	# The camera swings in behind the walk (the mouse can still look around).
	if _rig and _rig.has_method("chase") and delta > 0.0:
		_rig.chase(face_yaw, -0.2, 3.0, delta)


func _end() -> void:
	if _ended:
		return
	_ended = true
	_release()
	if walk.kind == DoorWalk.Kind.ARRIVE:
		_fade.set_alpha(0.0)
	finished.emit()
	if done_cb.is_valid():
		done_cb.call()
	queue_free()


func _release() -> void:
	if is_instance_valid(player) and player.has_method("auto_walk_stop"):
		player.auto_walk_stop()
	if door and is_instance_valid(door):
		if owns_door:
			door.queue_free()
		else:
			door.held = _was_held
			if walk.kind == DoorWalk.Kind.ARRIVE:
				door.open = 0.0


func _exit_tree() -> void:
	if not _ended:
		_ended = true
		_release()
