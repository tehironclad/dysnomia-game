extends SceneTree
## Bumping into things, end to end (read-only; nothing is signed or posted):
##   godot --headless --path . -s res://tools/probe_bump.gd [-- --only=pub,fair --shots=<abs dir>]
## Sunny's Pub: runs the player along the bar stools at a sprint (they topple),
## into a high-top (its glass and candle go with it), into a standing regular
## (they fall, lie a moment and get up), walks gently into another (a nudge),
## then looks away and checks everything went home. The fair: runs into a bin
## and a crate (they topple) and into a visitor (they fall and get up).
## With a display (xvfb + lavapipe) and --shots=<abs dir> it saves frames:
## pub_stools.png, pub_table.png, pub_npc_fall.png, fair_bin.png, fair_npc_fall.png.
## In -s tools, classes that use autoloads are reached by path (see CLAUDE.md).

const SUNFLOWER := "0x2b78b345880807ac9be28c1309ab55d6fa8796de"
const RATKING := "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b"
const RUN := 13.0
const WALK := 4.0

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


## Game seconds, counted in physics frames: under lavapipe a frame takes seconds and
## Godot slows game time to match (at most 8 physics steps a frame), so wall time lies.
func _seconds(s: float) -> void:
	for i in int(ceil(s * Engine.physics_ticks_per_second)):
		await physics_frame


## Waits until `cond` holds or `limit` game seconds pass.
func _until(cond: Callable, limit: float) -> void:
	var n := int(ceil(limit * Engine.physics_ticks_per_second))
	while not cond.call() and n > 0:
		n -= 1
		await physics_frame


func _shooting() -> bool:
	return _shots != "" and DisplayServer.get_name() != "headless"


## A frame from a fixed camera at `from` looking at `at` (with a display only).
func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if not _shooting():
		return
	var cam := Camera3D.new()
	cam.fov = 60.0
	current_scene.add_child(cam)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.current = true
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))
	print("     saved %s.png" % name)
	cam.queue_free()
	var pc := _player().get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if pc:
		pc.current = true


func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D


func _kw() -> Node:
	return current_scene.get_meta("knock_world") if current_scene and current_scene.has_meta("knock_world") else null


func _run() -> void:
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	if _want("pub"):
		await _pub_round()
	if _want("fair"):
		await _fair_round()
	print("\n%s (%d failed)" % ["ALL OK" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


## Moves the player in a straight line from `from` to `to` at `speed` (m/s), one
## physics frame at a time, at floor height `y`. The controller still runs
## (gravity, collisions); KnockWorld reads the motion. Returns at `to`, or after
## `hold` more seconds of whatever callable `during` does (shots mid-run).
func _run_line(from: Vector3, to: Vector3, speed: float, y: float) -> void:
	var p := _player()
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	var dist := d.length()
	d = d.normalized()
	p.global_position = Vector3(from.x, y, from.z)
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-d.x, -d.z)
	await physics_frame
	await physics_frame
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var s := 0.0
	while s < dist:
		s = minf(dist, s + speed * dt)
		var at := from + d * s
		p.global_position = Vector3(at.x, y, at.z)
		p.velocity = d * speed
		await physics_frame


func _tilt(k) -> float:
	return rad_to_deg(acos(clampf(k.get_xf().basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))


func _moved(k) -> float:
	return k.get_xf().origin.distance_to(k.home.origin)


# --- Sunny's Pub --------------------------------------------------------------------

func _pub_round() -> void:
	root.get_node("GameManager").territory_address = SUNFLOWER
	change_scene_to_file("res://scenes/places/sunny_pub.tscn")
	var t0 := Time.get_ticks_msec()
	while (current_scene == null or not current_scene.scene_file_path.ends_with("sunny_pub.tscn") or _player() == null) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	await _frames(40)
	var kw := _kw()
	_check(kw != null, "pub: a KnockWorld for the scene")
	if kw == null:
		return
	kw.debug = OS.get_cmdline_user_args().has("--debug")
	print("     %d knockable props in the pub" % kw.prop_count())
	_check(kw.prop_count() >= 20, "pub: stools, glasses, tables, drinks and the cue stand are knockable (%d)" % kw.prop_count())
	var room = current_scene.room
	var life = current_scene.find_child("PubLife", true, false)
	_check(kw.active_count() == 0, "pub: nothing has a body while nobody moves (%d)" % kw.active_count())
	# The stools along the bar, at a sprint.
	var stools: Array = room.stool_knocks.filter(func(k): return is_instance_valid(k) and k.is_inside_tree())
	_check(stools.size() >= 6, "pub: the free stools are knockable (%d; two hold regulars)" % stools.size())
	var row_z: float = room.stools[0].z
	var knocks0: int = kw.knocks
	if OS.get_cmdline_user_args().has("--debug"):
		for k in stools:
			print("     stool home %s centre %s r %.2f hh %.2f cell %s" % [k.home.origin, k.centre_g, k.radius, k.half_h, k.cell])
		print("     run z %.2f from x %.2f to %.2f; player at %s" % [row_z, room.stools[1].x - 1.5, room.stools[4].x + 0.6, _player().global_position])
	await _run_line(Vector3(room.stools[1].x - 1.5, 0, row_z), Vector3(room.stools[4].x + 0.6, 0, row_z), RUN, 0.0)
	_check(kw.knocks > knocks0, "pub: running along the bar knocks stools (%d knocks)" % (kw.knocks - knocks0))
	_check(_player().is_staggering() or kw.knocks - knocks0 > 0, "pub: the player feels it")
	await _seconds(3.4)
	var mid := Vector3.ZERO
	var n_down := 0
	for k in stools:
		if k.lying or k.body:
			mid += k.get_xf().origin
			n_down += 1
	mid = mid / maxf(n_down, 1) if n_down > 0 else Vector3(room.stools[3].x, 0, row_z)
	await _shot("pub_stools", mid + Vector3(-1.2, 2.2, 3.4), mid + Vector3(0, 0.2, 0))
	var toppled := 0
	for k in stools:
		if k.lying or k.body:
			if _tilt(k) > 45.0 or _moved(k) > 0.3:
				toppled += 1
	_check(toppled >= 2, "pub: stools went over (%d)" % toppled)
	await _until(func(): return kw.active_count() <= 3, kw.ACTIVE_MAX_S)
	_check(kw.active_count() <= 3, "pub: once still, the bodies go (%d moving)" % kw.active_count())
	# A high-top: it goes with its glass and candle.
	var ht: Vector3 = room.hightops[1]
	var before: int = kw.knocks
	await _run_line(ht + Vector3(-3.0, 0, 0.0), ht + Vector3(1.5, 0, 0.0), RUN, 0.0)
	await _seconds(0.6)
	_check(kw.knocks - before >= 1, "pub: the high-top goes over (%d knocks)" % (kw.knocks - before))
	await _shot("pub_table", ht + Vector3(-1.5, 1.7, 2.6), ht + Vector3(0.6, 0.3, 0))
	await _seconds(2.0)
	var drinks := 0
	for k in kw._props:
		if is_instance_valid(k) and k.target and k.sound == "glass" and k.home.origin.distance_to(ht) < 1.4 and (k.lying or k.body):
			drinks += 1
	_check(drinks >= 1, "pub: what stood on it fell with it (%d)" % drinks)
	# A standing regular (the frog by the bar end), at a run: down and up again.
	var frog: Node3D = life.patrons[2]
	var st = frog.get_node_or_null("Stumble")
	_check(st != null, "pub: regulars can be bumped")
	if st:
		var levels: Array = []
		st.bumped.connect(func(l, _d, _b): levels.append(l))
		var fp := frog.global_position
		await _run_line(fp + Vector3(-3.0, 0, 0.05), fp + Vector3(0.8, 0, 0.05), RUN, 0.0)
		_check(levels.has(3), "pub: running into a regular knocks them over (levels %s)" % [levels])
		_check(st.busy(), "pub: they are down")
		_check(_player().is_staggering(), "pub: the player staggers a little")
		_check(st._bubble != null and st._bubble.text != "", "pub: they say so (%s)" % (st._bubble.text if st._bubble else "—"))
		await _seconds(0.45)
		await _shot("pub_npc_fall", fp + Vector3(2.4, 1.7, 3.4), fp + Vector3(0, 1.0, 0))
		await _until(func(): return not st.busy() and st.level == 0, 8.0)
		_check(not st.busy() and st.level == 0, "pub: they got up and carried on (level %d, phase %d, t %.2f)" % [st.level, st._phase, st.t])
	# Walking gently into the robot regular: a nudge, nobody falls.
	var robot: Node3D = life.patrons[5]
	var rs = robot.get_node_or_null("Stumble")
	if rs:
		var lv: Array = []
		rs.bumped.connect(func(l, _d, _b): lv.append(l))
		var rp := robot.global_position
		await _run_line(rp + Vector3(0.0, 0, 2.5), rp + Vector3(0.0, 0, 0.1), WALK, 0.0)
		await _seconds(0.2)
		_check(lv.size() > 0 and lv.max() == 1, "pub: walking into someone only nudges them (levels %s)" % [lv])
	# Everything goes home once it's out of view (the wait shortened for the probe).
	kw.reset_min_s = 1.0
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.global_position = Vector3(0, 3.0, 0)
	cam.look_at(Vector3(0, 10, 0.01), Vector3.FORWARD)
	cam.current = true
	_player().global_position = Vector3(0, 0, 5.0)
	await _seconds(kw.ACTIVE_MAX_S + 2.0)  # anything still rolling stops by then
	if kw.debug:
		for k in kw._active:
			print("     still moving: %s home %s at %s v %s w %s since %.1f now %.1f" % [k.get_parent().name, k.home.origin, k.body.global_position, k.body.linear_velocity, k.body.angular_velocity, k.moving_since, kw._now])
	_check(kw.lying_count() == 0 and kw.active_count() == 0, "pub: out of view, everything went home (%d lying, %d moving, %d resets)" % [kw.lying_count(), kw.active_count(), kw.resets])
	var off := 0.0
	for k in stools:
		off = maxf(off, _moved(k))
	_check(off < 0.001, "pub: the stools are back on their spots (worst %.4f m)" % off)
	cam.queue_free()


# --- The fair --------------------------------------------------------------------

func _fair_round() -> void:
	load("res://scripts/core/travel.gd").go(self, RATKING)
	var t0 := Time.get_ticks_msec()
	var fair = null
	while Time.get_ticks_msec() - t0 < 90000:
		fair = root.find_child("AffectionFair", true, false)
		if fair and fair._fair != null and fair._tier >= 2:
			break
		await process_frame
	await _frames(30)
	_check(fair != null and fair._fair != null, "fair: the fair is open")
	var kw := _kw()
	_check(kw != null, "fair: a KnockWorld for the territory")
	if kw == null or fair == null or fair._fair == null:
		return
	var f: Node3D = fair._fair
	kw.debug = OS.get_cmdline_user_args().has("--debug")
	var bins: Array = []
	var crates: Array = []
	var barrels := 0
	for k in kw._props:
		if not is_instance_valid(k) or not f.is_ancestor_of(k):
			continue
		var nm: String = k.target.name if k.target else k.mm_owner.name
		if nm.contains("trash"):
			bins.append(k)
		elif nm.contains("crate"):
			crates.append(k)
		elif nm.contains("Barrel"):
			barrels += 1
	print("     fair knockables: %d bins, %d crates, %d barrels, %d in all" % [bins.size(), crates.size(), barrels, kw.prop_count()])
	_check(bins.size() >= 1 and crates.size() >= 1 and barrels >= 2, "fair: bins, crates and barrels are knockable")
	if not bins.is_empty():
		var b = bins[0]
		var c: Vector3 = b.home.origin
		var y := c.y - 0.072
		await _run_line(c + Vector3(-3.0, 0, 0.1), c + Vector3(1.5, 0, 0.1), RUN, y)
		_check(b.body != null or b.lying, "fair: running into a bin knocks it")
		if kw.debug:
			for i in 12:
				await _seconds(0.25)
				print("     bin at %s %s" % [b.get_xf().origin, ("v %s" % b.body.linear_velocity) if b.body else "lying"])
		await _seconds(3.0)
		var lie: Vector3 = b.get_xf().origin
		await _shot("fair_bin", lie + Vector3(-1.2, 1.2, 1.7), lie + Vector3(0, 0.2, 0))
		_check(_tilt(b) > 45.0 or _moved(b) > 0.4, "fair: the bin went over (tilt %.0f°, %.2f m)" % [_tilt(b), _moved(b)])
	if not crates.is_empty():
		var cr = crates[crates.size() - 1]
		var cc: Vector3 = cr.home.origin
		await _run_line(cc + Vector3(0.1, 0, -3.0), cc + Vector3(0.1, 0, 1.5), RUN, cc.y)
		await _seconds(2.5)
		_check(cr.lying or cr.body != null, "fair: running into a crate knocks it (tilt %.0f°, %.2f m)" % [_tilt(cr), _moved(cr)])
	# A visitor on foot, at a run.
	var npc: Node3D = null
	for n in f.get_children():
		if n is AmbientNPC and n.bumpable and n._stumble and n._stumble.can_fall() and n.visible \
				and String(n.name).begins_with("Visitor"):
			npc = n
			break
	_check(npc != null, "fair: a visitor on foot to bump into")
	if npc:
		var st = npc._stumble
		var levels: Array = []
		st.bumped.connect(func(l, _d, _b): levels.append(l))
		npc.set_process(false)  # hold them still for the run-up (the probe's aim, not the game)
		var np := npc.global_position
		var dir := Vector3(1, 0, 0)
		if kw.debug:
			print("     visitor %s at %s" % [npc.name, np])
		await _run_line(np - dir * 3.0, np + dir * 0.8, RUN, np.y)
		_check(levels.has(3), "fair: running into a visitor knocks them over (levels %s)" % [levels])
		var at := npc.global_position
		await _seconds(0.1)
		_check(npc.global_position.distance_to(at) < 0.05, "fair: while down they don't walk on")
		await _seconds(0.35)
		await _shot("fair_npc_fall", np + Vector3(0.8, 1.7, 3.6), np + Vector3(0, 1.0, 0))
		await _until(func(): return not st.busy(), 8.0)
		_check(not st.busy(), "fair: the visitor got up (level %d, phase %d, t %.2f)" % [st.level, st._phase, st.t])
