class_name RideBase
extends Node3D
## Base for every paid attraction. Subclasses build geometry in _build() and animate in
## _ride_tick(); the base owns the ticket booth trigger, seating the player, the ride
## clock, and putting the player back down safely.
##
## Flow: player walks into the booth trigger → booth_focus(self, true) → AttractionDirector
## shows the price → on a granted purchase the director calls start_ride(player).
##
## While riding, the player's physics is frozen and each frame we place them at
## get_seat_transform(t). Their CameraRig is a child of the player, so the normal
## third-person / orbit camera rides along and mouse-look keeps working.
##
## No teleports: boarding is a short walk-and-step from where the player stood to the seat
## (the ride's clock already running, so the seat may be moving; the camera rides along, so it
## blends), and getting off steps down from the seat to the exit point the same way, at the
## door walk-throughs' pace (DoorWalk.walk_speed). ride_finished fires once the rider is down.
## A rider farther than STEP_MAX_M from the exit (back from the Rocket's voyage) is set down
## directly. RideBase.paused (RocketVoyage flying the rider) still skips ticking and seating.

signal booth_focus(ride: RideBase, inside: bool)
signal ride_started(ride: RideBase)
signal ride_finished(ride: RideBase)
signal ride_caption(text: String)   # Short live captions ("T-3", "APOGEE 412 m")

@export var ride_id: String = ""
var item: Dictionary = {}
var seed_value: int = 0

var booth_local_position: Vector3 = Vector3(0, 0, 8)   # Where the ticket booth trigger sits
var exit_local_position: Vector3 = Vector3(2.5, 0.5, 8) # Where the rider is set down
var booth_radius: float = 3.5
var reach_radius: float = 9.0    # Use works anywhere this close to the ride's centre too (FairSite)

var _rider: CharacterBody3D
var _t: float = 0.0
var _idle_t: float = 0.0
var _riding: bool = false
var paused := false   # true while something else flies the rider (RocketVoyage): no ticking, no seating
var _booth_area: Area3D
var _board_from := Vector3.ZERO
var _board_s := 0.0          ## the boarding step's length (s); 0 = seated
var _alighting := false

const STEP_MIN_S := 0.6
const STEP_MAX_S := 1.5
const STEP_MAX_M := 30.0
const HOP_M := 0.35


func setup(seed_val: int) -> void:
	## Call after adding to the tree.
	seed_value = seed_val
	item = AttractionCatalog.ride(ride_id)
	_build()
	_build_booth_trigger()


func is_riding() -> bool:
	return _riding


func ride_duration() -> float:
	return float(item.get("duration", 30.0))


func start_ride(player: CharacterBody3D) -> void:
	if _riding or _alighting or player == null:
		return
	_rider = player
	_riding = true
	_t = 0.0
	_rider.set_physics_process(false)
	_rider.velocity = Vector3.ZERO
	_on_ride_start()
	_board_from = _rider.global_position
	_board_s = step_seconds(_board_from.distance_to(get_seat_transform(0.0).origin))
	_hold_walk(true)
	ride_started.emit(self)


## How long a step of `dist` metres takes: the door walk's pace, kept short.
static func step_seconds(dist: float) -> float:
	return clampf(dist / DoorWalk.walk_speed(dist) + 0.2, STEP_MIN_S, STEP_MAX_S)


## A walk/step from a to b at u (0..1): eased, with a little hop at the end (onto / off the seat).
static func step_point(a: Vector3, b: Vector3, u: float) -> Vector3:
	var k := u * u * (3.0 - 2.0 * u)
	var hop := HOP_M * sin(clampf((u - 0.55) / 0.45, 0.0, 1.0) * PI)
	return a.lerp(b, k) + Vector3.UP * hop


func is_boarding() -> bool:
	return _riding and _board_s > 0.0 and _t < _board_s


func is_alighting() -> bool:
	return _alighting


func _hold_walk(on: bool) -> void:
	if not is_instance_valid(_rider):
		return
	var model := _rider.get_node_or_null("PlayerModel")
	if model and "hold_clip" in model:
		model.set("hold_clip", "Walk" if on else "")


func _face(dir: Vector3, w: float) -> void:
	dir.y = 0.0
	if dir.length() > 0.05 and is_instance_valid(_rider):
		_rider.rotation.y = lerp_angle(_rider.rotation.y, atan2(-dir.x, -dir.z), w)


func end_ride() -> void:
	if not _riding:
		return
	_riding = false
	_board_s = 0.0
	_on_ride_end()
	ride_caption.emit("")
	if not is_instance_valid(_rider):
		_rider = null
		ride_finished.emit(self)
		return
	var exit := to_global(exit_local_position) + Vector3.UP * 0.1
	var from := _rider.global_position
	if from.distance_to(exit) > STEP_MAX_M:
		_set_down(exit)
		return
	# Step off: a short walk down from the seat to the exit, then the player walks on
	_alighting = true
	_hold_walk(true)
	var dur := step_seconds(from.distance_to(exit))
	var tw := create_tween()
	tw.tween_method(func(u: float) -> void:
		if is_instance_valid(_rider):
			_rider.global_position = step_point(from, exit, u)
			_face(exit - from, 0.2), 0.0, 1.0, dur)
	tw.tween_callback(func() -> void: _set_down(exit))


func _set_down(at: Vector3) -> void:
	_alighting = false
	if is_instance_valid(_rider):
		_hold_walk(false)
		_rider.global_position = at
		_rider.velocity = Vector3.ZERO
		_rider.set_physics_process(true)
	_rider = null
	ride_finished.emit(self)


func _process(delta: float) -> void:
	_idle_t += delta
	if paused:
		return
	if _riding:
		_t += delta
		_ride_tick(_t, delta)
		if is_instance_valid(_rider):
			var seat := get_seat_transform(_t)
			if _board_s > 0.0 and _t < _board_s:
				# Boarding: walk and step from where they stood onto the (maybe moving) seat
				_rider.global_position = step_point(_board_from, seat.origin, _t / _board_s)
				_face(seat.origin - _board_from, clampf(delta * 8.0, 0.0, 1.0))
			else:
				if _board_s > 0.0:
					_board_s = 0.0
					_hold_walk(false)
				_rider.global_position = seat.origin
		if _t >= ride_duration():
			end_ride()
	else:
		_idle_tick(_idle_t, delta)


# ─── Overridables ───────────────────────────────────────────────────────

func _build() -> void:
	pass


func _ride_tick(_time: float, _delta: float) -> void:
	## Animate the ride while someone is on it.
	pass


func _idle_tick(_time: float, _delta: float) -> void:
	## Ambient motion when nobody is riding (attract mode).
	pass


func get_seat_transform(_time: float) -> Transform3D:
	## Global transform where the rider's feet go at ride time t.
	return global_transform


func _on_ride_start() -> void:
	pass


func _on_ride_end() -> void:
	pass


# ─── Booth trigger ──────────────────────────────────────────────────────

func _build_booth_trigger() -> void:
	_booth_area = Area3D.new()
	_booth_area.name = "BoothTrigger"
	var coll := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = booth_radius
	shape.height = 4.0
	coll.shape = shape
	_booth_area.add_child(coll)
	_booth_area.position = booth_local_position + Vector3(0, 1.5, 0)
	add_child(_booth_area)
	_booth_area.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player") and not _riding:
			booth_focus.emit(self, true))
	_booth_area.body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			booth_focus.emit(self, false))
