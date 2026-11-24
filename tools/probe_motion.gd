extends SceneTree
## Movement polish, end to end (read-only; nothing is signed):
##   godot --headless --path . -s res://tools/probe_motion.gd [-- --only=room,void,arcade,pub,fly,vehicle,skip]
## Walks into and out of the Room, the Void, the arcade and Sunny's Pub through
## their doors (DoorSequence), checks where the player ends up each time,
## skips an arrival with a key press, toggles flight off mid-air (no snap: the
## body falls and lands), and steps in and out of a vehicle.
## With a display (xvfb + lavapipe) and --shots=<abs dir>, it also saves frames
## mid-transition: enter_<door>.png, inside_<door>.png, out_<door>.png.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const SUNFLOWER := "0x2b78b345880807ac9be28c1309ab55d6fa8796de"

var _fails := 0
var _only: PackedStringArray = []
var _shots := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).split(",")
		elif a.begins_with("--shots="):
			_shots = a.substr(8)
	_run.call_deferred()


func _want(what: String) -> bool:
	return _only.is_empty() or _only.has(what)


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await process_frame


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


func _scene_is(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path


func _wait_scene(path: String, timeout_s: float = 60.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not _scene_is(path) and Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		await process_frame
	await _frames(2)
	return _scene_is(path)


func _seq() -> Node:
	return current_scene.get_node_or_null("DoorSequence") if current_scene else null


func _wait_seq_end(timeout_s: float = 6.0) -> float:
	var t0 := Time.get_ticks_msec()
	while _seq() != null and Time.get_ticks_msec() - t0 < int(timeout_s * 1000.0):
		await process_frame
	return (Time.get_ticks_msec() - t0) / 1000.0


func _player() -> CharacterBody3D:
	return current_scene.get_node_or_null("Player") as CharacterBody3D if current_scene else null


## Plays on for `t` s; with --shots, instead holds the walk's timeline at `t`
## (the player still walks) and saves a frame.
func _hold_shot(name: String, t: float) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		await _seconds(t)
		return
	var s := _seq()
	if s:
		s.freeze_at = t
	await _frames(6)
	await _shot(name)
	if s and is_instance_valid(s):
		s.freeze_at = -1.0


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("     saved %s.png" % name)


func _run() -> void:
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	for door in ["room", "void", "arcade"]:
		if _want(door):
			await _door_round(ILLINOIS, door)
	if _want("pub"):
		await _door_round(SUNFLOWER, "arcade")
	if _want("skip"):
		await _skip_round()
	if _want("fly"):
		await _fly_round()
	if _want("vehicle"):
		await _vehicle_round()
	print("\n%s (%d failed)" % ["ALL OK" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


func _to_territory(addr: String) -> Node:
	load("res://scripts/core/travel.gd").go(self, addr)
	await _wait_scene("res://scenes/territory/territory_v2.tscn")
	await _frames(10)
	return current_scene


## In through the territory door, check the arrival inside, out again, check
## the player stands outside that same door facing out.
func _door_round(addr: String, door: String) -> void:
	var travel = load("res://scripts/core/travel.gd")
	var terr := await _to_territory(addr)
	var p := _player()
	var spot: Dictionary = terr._door_spot(door)
	if spot["owns"] and spot["door"]:
		(spot["door"] as Node).queue_free()  # only the lookup: the pass makes its own
	var label := "%s (%s)" % [door, String(terr.territory.get("name", ""))]
	# Stand a few metres out from the door, as a player walking up would.
	var start: Vector3 = spot["at"] + spot["out"] * 2.6
	start.y = terr.terrain.get_height_at(start.x, start.z) + 0.3
	p.global_position = start
	p.velocity = Vector3.ZERO
	await _frames(12)
	_check(terr._near == door, "%s: the door's prompt is offered (near=%s)" % [label, terr._near])
	await _press("interact")
	_check(_seq() != null, "%s: Use starts the walk in" % label)
	await _hold_shot("enter_" + label.get_slice(" ", 0) + ("_pub" if addr == SUNFLOWER else ""), 0.7)
	var place: String = travel.place_scene(door, addr)
	var t0 := Time.get_ticks_msec()
	var arrived: bool = await _wait_scene(place, 30.0)
	_check(arrived, "%s: changed to %s" % [label, place.get_file()])
	if not arrived:
		return
	var walk_in_s := (Time.get_ticks_msec() - t0) / 1000.0
	await _frames(2)
	_check(_seq() != null, "%s: arrives walking in through the entrance" % label)
	await _hold_shot("inside_" + place.get_file().get_basename(), 0.45)
	var dur := await _wait_seq_end()
	p = _player()
	var spawn: Vector3 = current_scene._spawn
	var d := Vector2(p.global_position.x - spawn.x, p.global_position.z - spawn.z).length()
	_check(d < 0.9, "%s: walked in to %s (%.2f m off) in %.1f s; door shut=%s" % [label, spawn, d, dur + 0.45,
		current_scene.door == null or current_scene.door.open < 0.05])
	_check(p.is_physics_processing() and not p.auto_walking, "%s: control handed back" % label)
	print("     scene load %.1f s" % walk_in_s)
	# Out again: stand at the exit, Use.
	p.global_position = current_scene.exit_at + Vector3(0, 0.1, -0.3)
	p.velocity = Vector3.ZERO
	await _frames(8)
	_check(current_scene._near_exit, "%s: exit prompt offered" % label)
	await _press("interact")
	_check(_seq() != null, "%s: Use at the exit starts the walk out" % label)
	await _hold_shot("exit_" + place.get_file().get_basename(), 0.6)
	var back: bool = await _wait_scene("res://scenes/territory/territory_v2.tscn", 60.0)
	_check(back, "%s: back in the territory" % label)
	if not back:
		return
	terr = current_scene
	p = _player()
	_check(_seq() != null, "%s: comes out walking from the door" % label)
	await _hold_shot("out_" + label.get_slice(" ", 0) + ("_pub" if addr == SUNFLOWER else ""), 0.5)
	await _wait_seq_end()
	await _frames(5)
	spot = terr._door_spot(door)
	if spot["owns"] and spot["door"]:
		(spot["door"] as Node).queue_free()
	var want: Vector3 = spot["at"] + spot["out"] * 4.0
	var off := Vector2(p.global_position.x - want.x, p.global_position.z - want.z).length()
	var fwd := -p.global_transform.basis.z
	var facing := Vector2(fwd.x, fwd.z).normalized().dot(Vector2(spot["out"].x, spot["out"].z))
	_check(off < 1.2, "%s: out of the same door (%.2f m from %s)" % [label, off, want])
	_check(facing > 0.8, "%s: facing out (dot %.2f)" % [label, facing])
	var ground: float = terr.terrain.get_height_at(p.global_position.x, p.global_position.z)
	_check(absf(p.global_position.y - ground) < 1.5, "%s: on the ground (%.2f above)" % [label, p.global_position.y - ground])
	_check(root.get_node("ScreenFade").alpha() < 0.01, "%s: screen clear" % label)


## A key press ends an arrival at once and puts the player at its end.
func _skip_round() -> void:
	var terr := await _to_territory(ILLINOIS)
	var p := _player()
	var spot: Dictionary = terr._door_spot("room")
	if spot["owns"] and spot["door"]:
		(spot["door"] as Node).queue_free()
	terr._arrive_from("room")
	await _frames(3)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(1)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(3)
	_check(_seq() == null, "skip: a key press ends the arrival")
	_check(not p.auto_walking and p.is_physics_processing(), "skip: control is back")
	var want: Vector3 = spot["at"] + spot["out"] * 4.0
	_check(Vector2(p.global_position.x - want.x, p.global_position.z - want.z).length() < 0.3, "skip: at the arrival's end")
	await _frames(40)
	_check(root.get_node("ScreenFade").alpha() < 0.01, "skip: screen clear")


## Flight off in mid-air: no snap to the ground; the body keeps going, falls, lands.
func _fly_round() -> void:
	var terr := await _to_territory(ILLINOIS)
	var p := _player()
	var gm := root.get_node("GameManager")
	var at := Vector3(30.0, 0.0, 60.0)
	at.y = terr.terrain.get_height_at(at.x, at.z) + 25.0
	p.global_position = at
	gm.toggle_fly_mode()
	_check(p.is_flying, "fly: flying")
	await _frames(5)
	p.global_position = at
	p.velocity = Vector3(8.0, 0.0, 0.0)
	await _frames(1)
	var y0 := p.global_position.y
	gm.toggle_fly_mode()
	await physics_frame
	await physics_frame
	_check(not p.is_flying, "fly: off")
	_check(absf(p.global_position.y - y0) < 0.5, "fly: no snap to the ground (moved %.2f m)" % (p.global_position.y - y0))
	_check(p.velocity.x > 4.0, "fly: momentum kept (vx %.1f)" % p.velocity.x)
	var t0 := Time.get_ticks_msec()
	var model = p.get_node("PlayerModel")
	var clips := {}
	while not p.is_on_floor() and Time.get_ticks_msec() - t0 < 15000:
		await physics_frame
		clips[model._clip] = true
	var fall_s := (Time.get_ticks_msec() - t0) / 1000.0
	_check(p.is_on_floor(), "fly: landed after %.1f s" % fall_s)
	_check(fall_s > 2.0, "fly: fell under low gravity (not instantly)")
	_check(clips.has("Jump"), "fly: the fall loop played (%s)" % ", ".join(clips.keys()))
	_check(absf(p.global_position.x - at.x) > 3.0, "fly: carried on across the ground (%.1f m)" % (p.global_position.x - at.x))
	await _frames(3)
	_check(model._clip == "Jump_Land", "fly: soft landing animation (%s)" % model._clip)


## V in: a short hop onto the seat; V out: a step down beside it (no teleports).
func _vehicle_round() -> void:
	var terr := await _to_territory(ILLINOIS)
	var p := _player()
	var garage = terr.garage
	var kind: String = garage.vehicles.keys()[0]
	var v = garage.vehicles[kind]
	var stand: Vector3 = v.exit_point()
	p.global_position = stand
	p.velocity = Vector3.ZERO
	await _frames(10)
	var before := p.global_position
	garage.mount(kind)
	await physics_frame
	await physics_frame
	var moved := p.global_position.distance_to(before)
	var seat: Vector3 = v.body.global_transform.orthonormalized() * Vector3(v.spec["seat"])
	_check(moved < before.distance_to(seat) * 0.6, "vehicle: steps in (not a jump to the seat: %.2f of %.2f m in 2 frames)" % [moved, before.distance_to(seat)])
	await _seconds(0.8)
	seat = v.body.global_transform.orthonormalized() * Vector3(v.spec["seat"])
	_check(p.global_position.distance_to(seat) < 0.2, "vehicle: seated")
	garage.dismount()
	await physics_frame
	var exit_at: Vector3 = v.exit_point()
	_check(p.global_position.distance_to(exit_at) > 0.3, "vehicle: steps out (not teleported)")
	_check(not p.is_physics_processing(), "vehicle: input waits while stepping out")
	await _seconds(0.9)
	_check(p.is_physics_processing(), "vehicle: on foot again")
	_check(p.global_position.distance_to(exit_at) < 1.0, "vehicle: beside the vehicle (%.2f m)" % p.global_position.distance_to(exit_at))
	_check(String(p.get_node("PlayerModel").hold_clip) == "", "vehicle: back to normal animation")
