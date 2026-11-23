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

var _rider: CharacterBody3D
var _t: float = 0.0
var _idle_t: float = 0.0
var _riding: bool = false
var _booth_area: Area3D


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
	if _riding or player == null:
		return
	_rider = player
	_riding = true
	_t = 0.0
	_rider.set_physics_process(false)
	_rider.velocity = Vector3.ZERO
	_on_ride_start()
	ride_started.emit(self)


func end_ride() -> void:
	if not _riding:
		return
	_riding = false
	_on_ride_end()
	if is_instance_valid(_rider):
		_rider.global_position = to_global(exit_local_position) + Vector3.UP * 0.6
		_rider.velocity = Vector3.ZERO
		_rider.set_physics_process(true)
	_rider = null
	ride_caption.emit("")
	ride_finished.emit(self)


func _process(delta: float) -> void:
	_idle_t += delta
	if _riding:
		_t += delta
		_ride_tick(_t, delta)
		if is_instance_valid(_rider):
			var seat := get_seat_transform(_t)
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
