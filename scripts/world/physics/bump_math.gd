class_name BumpMath
extends RefCounted
## The pure maths of bumping into things (KnockWorld, Stumble, NetBump): a
## one-dimensional collision along the contact normal, how hard a bump is for a
## character, a damped spring for leans, and when a knocked prop may go home.
## No nodes, no physics server: unit-tested (tests/test_bump.gd).

## How a character takes a bump.
enum { NONE, NUDGE, STUMBLE, FALL }

## Bumper speeds (m/s, closing speed along the contact, scaled by mass) at which
## a character reacts. The player walks at 6 m/s and runs at 14 on this moon.
const NUDGE_SPEED := 1.0
const STUMBLE_SPEED := 7.0
const FALL_SPEED := 9.5
## The mass the speeds above are measured against (a person in a suit).
const PERSON_KG := 80.0

## A knocked prop waits at least this long before it may go home, and goes only
## when neither where it lies nor its spot is in view. Past RESET_MAX_S it goes
## home as soon as its spot is out of view, wherever it lies.
const RESET_MIN_S := 25.0
const RESET_MAX_S := 90.0

## The longest the player's own stagger lasts (also the net bump's cap).
const STAGGER_MAX_S := 0.6


## The impulse (N·s) on the prop when a bumper moving at `v_b` meets a prop
## moving at `v_p`, along `n` (unit, bumper → prop). Zero when they are not
## closing. `e` is the restitution (0 = they move off together, 1 = elastic).
static func contact_impulse(v_b: Vector3, v_p: Vector3, n: Vector3, m_b: float, m_p: float, e: float = 0.2) -> Vector3:
	var closing := (v_b - v_p).dot(n)
	if closing <= 0.0 or m_b <= 0.0 or m_p <= 0.0:
		return Vector3.ZERO
	var j := (1.0 + e) * closing / (1.0 / m_b + 1.0 / m_p)
	return n * j


## The impulse a bumper gives a prop: the contact impulse (restitution `e`),
## along the push (half the bumper's heading, half the contact normal, so a
## glancing blow still sends it the way you were going), never taking the prop
## past `max_speed` that way, plus a little `hop` (a share of it upwards) so
## things tip rather than skid. Pushing something already moving away at your
## speed adds nothing.
static func kick(v_b: Vector3, v_p: Vector3, n: Vector3, m_b: float, m_p: float, max_speed: float,
		e: float = 0.15, hop: float = 0.18) -> Vector3:
	var jl := contact_impulse(v_b, v_p, n, m_b, m_p, e).length()
	if jl <= 0.0:
		return Vector3.ZERO
	var flat := Vector3(v_b.x, 0.0, v_b.z)
	var dir := (flat.normalized() * 0.5 + n * 0.5) if flat.length() > 0.1 else n
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	jl = minf(jl, maxf(0.0, max_speed - v_p.dot(dir)) * m_p)
	if jl <= 1e-6:
		return Vector3.ZERO
	return dir * jl + Vector3.UP * jl * hop


## The horizontal unit normal from `from` to `to`; when they coincide,
## `fallback` flattened, or +X.
static func flat_normal(from: Vector3, to: Vector3, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length_squared() > 1e-6:
		return d.normalized()
	var f := Vector3(fallback.x, 0.0, fallback.z)
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.RIGHT


## The closing speed a character feels, scaled by the bumper's mass (a rover
## at a walking pace knocks people over; something light barely does).
static func effective_speed(closing: float, m_b: float) -> float:
	return maxf(closing, 0.0) * clampf(sqrt(maxf(m_b, 0.0) / PERSON_KG), 0.4, 3.0)


## NONE, NUDGE, STUMBLE or FALL for an effective speed. `can_fall` false (seated,
## another player) caps it at STUMBLE.
static func reaction(eff_speed: float, can_fall: bool = true) -> int:
	if eff_speed >= FALL_SPEED and can_fall:
		return FALL
	if eff_speed >= STUMBLE_SPEED:
		return STUMBLE
	if eff_speed >= NUDGE_SPEED:
		return NUDGE
	return NONE


## Seconds a character ignores further bumps after one of `level` (no knock-down spam).
static func cooldown(level: int) -> float:
	match level:
		FALL:
			return 4.0
		STUMBLE:
			return 1.5
		NUDGE:
			return 0.6
	return 0.0


## The player's own stagger (seconds, ≤ STAGGER_MAX_S) after hitting a
## character at `level`, or a prop with an impulse of `impulse` N·s.
static func stagger_seconds(level: int, impulse: float = 0.0) -> float:
	var s := 0.0
	if level == FALL:
		s = 0.45
	elif level == STUMBLE:
		s = 0.3
	if impulse > 300.0:
		s = maxf(s, clampf(impulse / 1600.0, 0.2, STAGGER_MAX_S))
	return minf(s, STAGGER_MAX_S)


## One step of a damped spring (semi-implicit Euler): (x, v) toward `target`.
## k stiffness (1/s²), c damping (1/s).
static func spring_step(x: float, v: float, target: float, k: float, c: float, dt: float) -> Vector2:
	v += (-(x - target) * k - v * c) * dt
	x += v * dt
	return Vector2(x, v)


## Smooth 0 → 1 → 0 over [0, dur]: in over `rise`, held, out over `fall` seconds.
static func pulse(t: float, dur: float, rise: float, fall: float) -> float:
	if t <= 0.0 or t >= dur:
		return 0.0
	var a := smoothstep(0.0, maxf(rise, 1e-4), t)
	var b := 1.0 - smoothstep(dur - maxf(fall, 1e-4), dur, t)
	return minf(a, b)


## May a knocked prop go home now? `age` seconds since it was knocked,
## `settled` it has stopped moving, `seen_now` it (where it lies) is in view,
## `home_seen` its spot is in view. It never pops in or out in front of you.
static func may_reset(age: float, settled: bool, seen_now: bool, home_seen: bool, min_s: float = RESET_MIN_S) -> bool:
	if home_seen:
		return false
	if age >= maxf(RESET_MAX_S, min_s):
		return true
	return age >= min_s and settled and not seen_now


## Do a bumper (an upright capsule standing at `b`, radius rb, height hb) and a
## prop (centre `c`, horizontal radius rp, half height hp) touch?
static func touches(b: Vector3, rb: float, hb: float, c: Vector3, rp: float, hp: float) -> bool:
	var dx := c.x - b.x
	var dz := c.z - b.z
	var r := rb + rp
	if dx * dx + dz * dz > r * r:
		return false
	return c.y + hp >= b.y and c.y - hp <= b.y + hb


## A yaw as one byte (NetBump's direction), and back.
static func quant_dir(yaw: float) -> int:
	return int(round(fposmod(yaw, TAU) / TAU * 256.0)) & 0xFF


static func dequant_dir(q: int) -> float:
	return float(q & 0xFF) / 256.0 * TAU


## The horizontal unit vector for a yaw (0 = -Z, the game's forward), and back.
static func dir_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
