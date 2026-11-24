class_name FairCrowd
extends Node3D
## Fair-goers who wander over while you play a midway game, gather behind and beside the counter,
## and cheer (the Dance clip, a hop) when the round goes well; a groan when it's a near miss.
## Built on AmbientNPC (the players' own avatar). Stage space: +Z is toward the player at the
## counter. Purely visual: they know nothing of the chain; MidwayPlay tells them what happened.

const SPOTS := [Vector3(-1.5, 0, 3.4), Vector3(1.5, 0, 3.5), Vector3(-0.6, 0, 4.2), Vector3(0.7, 0, 4.4),
	Vector3(-2.3, 0, 2.8), Vector3(2.4, 0, 2.9), Vector3(-1.6, 0, 4.9), Vector3(1.8, 0, 5.0)]
const MAX := 8
const SPEED := 1.9

var spots: Array = SPOTS     ## where they stand (a stage may set its own)
var _folk: Array = []       ## [npc, spot, cheer_t, delay, hop_phase]
var _seed := 1
var focus := Vector3(0, 1.4, 0)


func gather(n: int, seed_v: int) -> void:
	_seed = seed_v
	while _folk.size() < mini(n, MAX):
		_add()


func add_one() -> void:
	if _folk.size() < MAX:
		_add()


func count() -> int:
	return _folk.size()


func _add() -> void:
	var i := _folk.size()
	var spot: Vector3 = spots[i % spots.size()]
	var npc := AmbientNPC.new()
	npc.name = "Onlooker%d" % i
	# They come from further out along the line from the stall through their spot
	var from := spot + Vector3(spot.x * 1.6, 0, 5.5 + i * 0.7)
	npc.position = from
	add_child(npc)
	npc.setup(_seed * 31 + i * 977, [], -Vector3(spot.x, 0, spot.z).normalized())
	npc.set_process(false)  # we walk them
	_folk.append([npc, spot, 0.0, 0.0, randf() * TAU])
	set_process(true)


## Everyone cheers for `seconds` (each starts a moment apart).
func cheer(seconds: float = 4.0) -> void:
	for f in _folk:
		f[2] = seconds
		f[3] = randf_range(0.0, 0.35)
	set_process(true)


## A quick reaction (a good throw mid-round): the nearest few hop.
func hop() -> void:
	for f in _folk:
		if float(f[2]) <= 0.0:
			f[2] = 0.9
			f[3] = randf_range(0.0, 0.2)
	set_process(true)


## Everyone at their spot now (previews).
func settle() -> void:
	for f in _folk:
		f[0].position = f[1]


func disperse() -> void:
	for f in _folk:
		if is_instance_valid(f[0]):
			f[0].queue_free()
	_folk.clear()
	set_process(false)


func _process(delta: float) -> void:
	var busy := false
	for f in _folk:
		var npc: AmbientNPC = f[0]
		if not is_instance_valid(npc):
			continue
		var model: Node3D = npc.get("_model")
		var spot: Vector3 = f[1]
		var to := spot - npc.position
		to.y = 0.0
		if to.length() > 0.08:
			busy = true
			var dir := to.normalized()
			npc.position += dir * minf(SPEED * delta, to.length())
			npc.rotation.y = lerp_angle(npc.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 8.0, 0.0, 1.0))
			if model:
				model.update_movement(dir * SPEED, true, false)
			continue
		var look := focus - npc.position
		npc.rotation.y = lerp_angle(npc.rotation.y, atan2(-look.x, -look.z), clampf(delta * 5.0, 0.0, 1.0))
		if float(f[3]) > 0.0:
			f[3] = float(f[3]) - delta
			busy = true
			if model:
				model.update_movement(Vector3.ZERO, true, false)
			continue
		if float(f[2]) > 0.0:
			busy = true
			f[2] = float(f[2]) - delta
			f[4] = float(f[4]) + delta * 9.0
			if model:
				model.set_seated("Dance")
				model.position.y = absf(sin(float(f[4]))) * 0.12
			if float(f[2]) <= 0.0 and model:
				model.set_seated("")
				model.position.y = 0.0
		elif model:
			model.update_movement(Vector3.ZERO, true, false)
	if not busy:
		set_process(false)
