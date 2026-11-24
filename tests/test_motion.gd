extends TestCase
## Movement polish: the door walk's timeline (DoorWalk) and the pure motion
## rules (MotionMath: falling, leaving flight, landing dust, auto-walk).


func _run_to_end(w: DoorWalk, dt := 1.0 / 60.0) -> Array:
	var fades: Array = []
	var guard := 0
	while not w.done() and guard < 1000:
		w.step(dt)
		fades.append(w.fade())
		guard += 1
	return fades


func test_enter_walk_fades_to_black_in_time() -> void:
	for dist in [0.5, 2.0, 3.5, 6.0, 40.0]:
		var w := DoorWalk.new(DoorWalk.Kind.ENTER, dist)
		check(w.total >= DoorWalk.MIN_TOTAL and w.total <= DoorWalk.MAX_TOTAL, "total %f for %f m" % [w.total, dist])
		eq(w.fade(), 0.0, "starts clear")
		eq(w.door_open(), 0.0, "door shut at the start")
		check(w.walking(), "walks from the start")
		var fades := _run_to_end(w)
		check(w.done(), "ends")
		near(float(fades[-1]), 1.0, 1e-6, "ends black (then the scene changes)")
		near(w.door_open(), 1.0, 1e-6, "door open by the end")
		for i in range(1, fades.size()):
			check(float(fades[i]) >= float(fades[i - 1]) - 1e-9, "fade never brightens")


func test_walk_pace_stays_a_walk() -> void:
	for dist in [0.0, 1.0, 3.0, 5.5, 100.0]:
		var v := DoorWalk.walk_speed(dist)
		check(v >= DoorWalk.MIN_SPEED and v < 4.5, "%f m/s is a walk (the avatar jogs from 4.5)" % v)


func test_arrive_fades_in_and_closes_door_behind() -> void:
	var w := DoorWalk.new(DoorWalk.Kind.ARRIVE, 4.0)
	near(w.fade(), 1.0, 1e-6, "starts black (carried over from the door)")
	near(w.door_open(), 1.0, 1e-6, "door open as you come through")
	w.step(DoorWalk.FADE_IN_S + 0.01)
	near(w.fade(), 0.0, 1e-6, "clear after the fade in")
	_run_to_end(w)
	check(w.done(), "ends")
	near(w.door_open(), 0.0, 1e-6, "door shut behind you")
	check(not w.walking(), "hands control back")


func test_skip_ends_quickly() -> void:
	var a := DoorWalk.new(DoorWalk.Kind.ARRIVE, 4.0)
	a.step(0.2)
	a.skip()
	check(a.done(), "arrival skip ends at once")
	eq(a.fade(), 0.0, "and the screen is clear")
	var e := DoorWalk.new(DoorWalk.Kind.ENTER, 4.0)
	e.step(0.3)
	var before := e.fade()
	e.skip()
	check(not e.done(), "enter skip still finishes its fade")
	_run_to_end(e)
	check(e.t <= 0.3 + DoorWalk.SKIP_FADE_S + 0.02, "but within %f s" % DoorWalk.SKIP_FADE_S)
	check(e.fade() >= before and is_equal_approx(e.fade(), 1.0), "black at the end")
	e.skip()  # a second key press changes nothing
	check(e.done(), "still done")


func test_fall_step_low_gravity_and_terminal() -> void:
	# From 30 m up at rest: lands after about sqrt(2h/g) s (Euler, 120 Hz).
	var g := 3.2
	var v := Vector3(2.0, 0.0, -1.0)
	var y := 30.0
	var t := 0.0
	var dt := 1.0 / 120.0
	while y > 0.0 and t < 60.0:
		v = MotionMath.fall_step(v, g, dt)
		y += v.y * dt
		t += dt
	near(t, sqrt(2.0 * 30.0 / g), 0.05, "fall time")
	eq(v.x, 2.0, "keeps its way across the ground")
	eq(v.z, -1.0)
	var fast := MotionMath.fall_step(Vector3(0, -24.99, 0), g, 1.0)
	eq(fast.y, -MotionMath.TERMINAL, "capped at the terminal speed")


func test_fly_exit_keeps_momentum() -> void:
	var v := MotionMath.fly_exit_velocity(Vector3(18.0, -6.0, 4.0))
	eq(v, Vector3(18.0, -6.0, 4.0), "diving: the way is kept, nothing snaps")
	var up := MotionMath.fly_exit_velocity(Vector3(0.0, 30.0, 0.0))
	eq(up.y, MotionMath.FLY_EXIT_UP, "a climb is trimmed")


func test_land_strength() -> void:
	eq(MotionMath.land_strength(-1.0), 0.0, "a step down raises no dust")
	eq(MotionMath.land_strength(0.0), 0.0)
	check(MotionMath.land_strength(-6.0) > 0.0, "a jump's landing does")
	check(MotionMath.land_strength(-25.0) <= 1.0 and MotionMath.land_strength(-25.0) > MotionMath.land_strength(-8.0), "harder = more")


func test_walk_dir() -> void:
	eq(MotionMath.walk_dir(Vector3(0, 5, 0), Vector3(3, -2, 4)), Vector3(0.6, 0.0, 0.8), "horizontal, unit")
	eq(MotionMath.walk_dir(Vector3.ZERO, Vector3(0.05, 0, 0)), Vector3.ZERO, "there already")
