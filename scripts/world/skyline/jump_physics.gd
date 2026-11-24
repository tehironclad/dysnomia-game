class_name JumpPhysics
extends RefCounted
## Base-jump flight, as pure maths (no scene): freefall, wingsuit, canopy,
## the territory's wind, landing grades and the score. Gravity is the game's
## own low gravity (PlayerController.gravity, 3.2 m/s²). Dysnomia's thin air is
## modelled as a velocity relaxation toward each mode's steady airspeed.

enum Mode { FREEFALL, WINGSUIT, CANOPY }

const FREEFALL_VT := 30.0   ## belly-to-earth terminal speed, m/s
const DIVE_VT := 44.0       ## head-down (sprint) terminal speed
const TRACK_A := 3.0        ## horizontal push while tracking in freefall, m/s²
const EDGE := 228.0         ## |x| or |z| past this: the territory's edge wind turns you back

## Steady airspeed (forward, sink) per mode at pitch input −1 (flare/brakes), 0, +1 (dive).
const GLIDE := {
	Mode.WINGSUIT: [Vector2(15.0, 4.2), Vector2(22.0, 6.8), Vector2(31.0, 13.5)],
	Mode.CANOPY: [Vector2(4.0, 2.1), Vector2(8.0, 3.0), Vector2(11.5, 4.6)],
}
const RELAX := {Mode.WINGSUIT: 0.75, Mode.CANOPY: 1.1}   ## 1/s
const TURN := {Mode.FREEFALL: 1.6, Mode.WINGSUIT: 1.15, Mode.CANOPY: 0.75}  ## rad/s at full steer
const FLARE := Vector2(3.0, 0.6)   ## canopy flare (jump held): forward, sink
const FLARE_S := 2.2               ## seconds of flare a canopy holds


## (forward, sink) a mode settles to at pitch input p ∈ [−1, 1].
static func steady(mode: int, p: float) -> Vector2:
	var g: Array = GLIDE[mode]
	p = clampf(p, -1.0, 1.0)
	return g[1].lerp(g[0], -p) if p < 0.0 else g[1].lerp(g[2], p)


## The body's forward (−Z) for a yaw.
static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The territory's wind: a fixed direction and strength from its address (the
## same for every viewer), with slow gusts. 1.5–4.5 m/s.
static func wind(address: String, t: float = 0.0) -> Vector3:
	var h := address.to_lower().hash()
	var a := float(h & 0xffff) / 65535.0 * TAU
	var s := 1.5 + 3.0 * float((h >> 16) & 0xff) / 255.0
	var gust := 1.0 + 0.3 * sin(t * 0.7 + a) + 0.15 * sin(t * 2.3 + 2.0 * a)
	return Vector3(cos(a), 0.0, sin(a)) * s * gust


## One step of velocity. `steer` −1..1 (left..right), `pitch` −1..1 (back..forward),
## `track` the camera-relative horizontal input (freefall only), `flare` 0..1.
## Returns the new velocity.
static func step(mode: int, vel: Vector3, yaw: float, steer: float, pitch: float, track: Vector3,
		dive: bool, flare: float, air: Vector3, g: float, dt: float) -> Vector3:
	var rel := vel - air
	if mode == Mode.FREEFALL:
		var vt := DIVE_VT if dive else FREEFALL_VT
		var k := g / (vt * vt)
		var acc := Vector3(0.0, -g, 0.0) - rel * rel.length() * k
		acc += Vector3(track.x, 0.0, track.z).limit_length(1.0) * TRACK_A
		return vel + acc * dt
	var s := steady(mode, pitch)
	if mode == Mode.CANOPY and flare > 0.0:
		s = s.lerp(FLARE, clampf(flare, 0.0, 1.0))
	var want := forward(yaw) * s.x + Vector3(0.0, -s.y, 0.0)
	var w := 1.0 - exp(-float(RELAX[mode]) * dt)
	return air + rel.lerp(want, w)


## New yaw after steering for dt.
static func turn(mode: int, yaw: float, steer: float, dt: float) -> float:
	return wrapf(yaw - clampf(steer, -1.0, 1.0) * float(TURN[mode]) * dt, -PI, PI)


## A push back toward the middle near the territory's edge (m/s²).
static func edge_push(pos: Vector3) -> Vector3:
	var p := Vector3.ZERO
	for axis in [0, 2]:
		var v: float = pos[axis]
		if absf(v) > EDGE:
			p[axis] = -signf(v) * (absf(v) - EDGE) * 0.4
	return p


## How a landing went, from the velocity at touchdown.
static func landing(vel: Vector3) -> Dictionary:
	var sink := -vel.y
	var fwd := Vector2(vel.x, vel.z).length()
	if sink <= 4.5 and fwd <= 10.0:
		return {"grade": "STAND-UP LANDING", "mult": 1.0}
	if sink <= 9.0 and fwd <= 24.0:
		return {"grade": "SKID LANDING", "mult": 0.6}
	return {"grade": "IMPACT · the suit's thrusters caught you", "mult": 0.25}


## Ring points by distance from the target's centre (radii 3 / 8 / 14 m).
static func ring_points(d: float) -> int:
	if d <= 3.0:
		return 1000
	if d <= 8.0:
		return 600
	if d <= 14.0:
		return 300
	return maxi(0, 200 - int(d))


## The score: horizontal path flown (1 point a metre) + accuracy, times the landing.
static func score(path_m: float, land_xz: Vector2, target_xz: Vector2, airtime: float, vel: Vector3) -> Dictionary:
	var d := land_xz.distance_to(target_xz)
	var l := landing(vel)
	var acc := ring_points(d)
	var pts := int(round((path_m + acc) * float(l["mult"])))
	return {"points": pts, "distance": path_m, "from_target": d, "accuracy": acc, "airtime": airtime,
		"grade": l["grade"], "mult": l["mult"]}
