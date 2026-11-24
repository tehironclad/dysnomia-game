class_name MotionMath
extends RefCounted
## Pure motion rules shared by the player controller and its tests.

const TERMINAL := 25.0      ## m/s: the fastest fall (regolith dust drag, artistic)
const FLY_EXIT_UP := 3.0    ## m/s: leaving flight while climbing keeps at most this much climb
const SOFT_LAND := 4.0      ## m/s down: from here a landing kicks up dust
const HARD_LAND := 14.0     ## m/s down: the most dust and the deepest knee bend


## One step of falling under low gravity, capped at the terminal speed.
static func fall_step(v: Vector3, gravity: float, dt: float) -> Vector3:
	return Vector3(v.x, maxf(v.y - gravity * dt, -TERMINAL), v.z)


## Flight switched off: the body keeps its way (no snap to the ground); a
## climb is trimmed so the suit doesn't fling you skywards.
static func fly_exit_velocity(v: Vector3) -> Vector3:
	return Vector3(v.x, minf(v.y, FLY_EXIT_UP), v.z)


## 0 (no dust) … 1 (hard landing) from the downward speed at touchdown.
static func land_strength(fall_speed: float) -> float:
	var down := -fall_speed
	if down < SOFT_LAND:
		return 0.0
	return clampf((down - SOFT_LAND) / (HARD_LAND - SOFT_LAND), 0.0, 1.0) * 0.85 + 0.15


## Steering toward a point on foot (auto-walk): the horizontal direction, or
## zero when within `arrive` of it.
static func walk_dir(from: Vector3, to: Vector3, arrive: float = 0.12) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return Vector3.ZERO if d.length() < arrive else d.normalized()
