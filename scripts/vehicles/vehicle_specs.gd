class_name VehicleSpecs
extends RefCounted
## The moon vehicles at a territory's garage, and the pure physics helpers they
## drive with. Everything here is deterministic and free of scene state, so the
## feel (acceleration, drift, hover, glide, landing squash) is unit-tested.
##
## Units: metres, seconds, m/s. Gravity matches the player's artistic low-g
## (3.2 m/s², about a third of Earth's): long hops, soft landings.

const GRAVITY := 3.2

## Garage order (cheapest unlock first).
const KINDS := ["rover", "hoverbike", "skimmer", "hopper", "crawler"]

## mode: "wheels" (rays per wheel, suspension), "hover" (rides a spring of air
## above whatever is under it, glides when the ground falls away), "thrust"
## (VTOL: lifts on Space while its fuel lasts), "tracks" (turns in place,
## climbs steep ground).
const SPECS := {
	"rover": {
		"name": "Regolith Rover", "mode": "wheels",
		"blurb": "Six wheels on long soft springs. Space hops, Ctrl slides it round.",
		"max_speed": 20.0, "boost": 1.35, "reverse": 0.45, "accel": 9.0, "brake": 16.0, "coast": 2.2,
		"turn": 1.9, "grip": 6.5, "slide_grip": 1.1, "air_control": 0.15,
		"jump": 6.0, "gravity_scale": 1.0, "floor_deg": 48.0, "snap": 0.35,
		"susp_k": 46.0, "susp_c": 5.5, "squash": 0.055, "travel": 0.42,
		"chase": 7.5, "chase_h": 2.6, "seat": Vector3(0.0, 1.05, 0.25),
		"hull": Vector3(2.4, 0.9, 3.4), "engine": "rover", "turn_in_place": false,
	},
	"hoverbike": {
		"name": "Hoverbike", "mode": "hover",
		"blurb": "The fastest thing on the moon. Drifts; sails off the Julia coast.",
		"max_speed": 34.0, "boost": 1.4, "reverse": 0.3, "accel": 14.0, "brake": 20.0, "coast": 3.0,
		"turn": 2.5, "grip": 2.4, "slide_grip": 0.8, "air_control": 0.6,
		"jump": 6.0, "gravity_scale": 1.0, "glide": 0.22, "hover": 1.0, "hover_k": 26.0, "hover_c": 7.0,
		"floor_deg": 40.0, "snap": 0.0, "susp_k": 30.0, "susp_c": 4.0, "squash": 0.04, "travel": 0.3,
		"chase": 6.0, "chase_h": 2.2, "seat": Vector3(0.0, 0.55, 0.35),
		"hull": Vector3(1.0, 0.7, 2.6), "engine": "hoverbike", "turn_in_place": false,
	},
	"skimmer": {
		"name": "Crest Skimmer", "mode": "hover",
		"blurb": "A low jet-sled. Space jumps the plateau crests.",
		"max_speed": 28.0, "boost": 1.3, "reverse": 0.35, "accel": 12.0, "brake": 18.0, "coast": 2.4,
		"turn": 2.2, "grip": 4.0, "slide_grip": 1.2, "air_control": 0.5,
		"jump": 9.0, "gravity_scale": 1.0, "glide": 0.5, "hover": 0.7, "hover_k": 34.0, "hover_c": 8.0,
		"floor_deg": 42.0, "snap": 0.0, "susp_k": 38.0, "susp_c": 4.5, "squash": 0.05, "travel": 0.3,
		"chase": 6.5, "chase_h": 2.2, "seat": Vector3(0.0, 0.5, 0.45),
		"hull": Vector3(2.0, 0.6, 3.2), "engine": "skimmer", "turn_in_place": false,
	},
	"hopper": {
		"name": "Lander Hopper", "mode": "thrust",
		"blurb": "A small VTOL. Hold Space to lift while the tank lasts; it refills on the ground.",
		"max_speed": 18.0, "boost": 1.3, "reverse": 0.6, "accel": 7.0, "brake": 9.0, "coast": 1.2,
		"turn": 1.7, "grip": 3.0, "slide_grip": 3.0, "air_control": 1.0,
		"thrust": 7.6, "fuel_s": 4.0, "refuel": 1.2, "jump": 0.0, "gravity_scale": 1.0,
		"floor_deg": 35.0, "snap": 0.2, "susp_k": 40.0, "susp_c": 4.0, "squash": 0.07, "travel": 0.35,
		"chase": 9.0, "chase_h": 3.2, "seat": Vector3(0.0, 1.15, 0.0),
		"hull": Vector3(2.4, 1.8, 2.4), "engine": "hopper", "turn_in_place": true,
	},
	"crawler": {
		"name": "Bar Crawler", "mode": "tracks",
		"blurb": "A tracked hauler for the territory's top towers. Turns on the spot, climbs anything.",
		"max_speed": 11.0, "boost": 1.25, "reverse": 0.7, "accel": 5.0, "brake": 14.0, "coast": 4.0,
		"turn": 1.2, "grip": 12.0, "slide_grip": 12.0, "air_control": 0.0,
		"jump": 0.0, "gravity_scale": 1.0, "floor_deg": 62.0, "snap": 0.6,
		"susp_k": 60.0, "susp_c": 9.0, "squash": 0.03, "travel": 0.2,
		"chase": 11.0, "chase_h": 3.8, "seat": Vector3(0.0, 1.65, -0.3),
		"hull": Vector3(3.4, 1.7, 5.2), "engine": "crawler", "turn_in_place": true,
	},
}


static func spec(kind: String) -> Dictionary:
	return SPECS.get(kind, SPECS["rover"])


static func display_name(kind: String) -> String:
	return String(spec(kind)["name"])


## One step of the planar drive model, in the vehicle's own frame:
## v.x = forward speed, v.y = sideways (slip) speed. `throttle` in [-1, 1].
## - throttle pulls the forward speed toward throttle × max (× boost), reverse capped;
## - pushing against the motion brakes; no input coasts down;
## - the sideways slip bleeds off at `grip` per second (slide_grip on a handbrake),
##   which is what makes a hoverbike drift and a crawler not;
## - off the ground only `air_control` of that applies.
static func drive_step(v: Vector2, throttle: float, boost: bool, braking: bool, grounded: bool, s: Dictionary, dt: float) -> Vector2:
	var top: float = float(s["max_speed"]) * (float(s["boost"]) if boost else 1.0)
	var control: float = 1.0 if grounded else float(s["air_control"])
	var fwd := v.x
	if control > 0.0:
		if absf(throttle) > 0.05:
			var target := throttle * (top if throttle > 0.0 else top * float(s["reverse"]))
			var against := fwd * throttle < 0.0
			var rate: float = (float(s["brake"]) if against else float(s["accel"]) * (1.25 if boost else 1.0)) * control
			fwd = move_toward(fwd, target, rate * dt)
		else:
			fwd = move_toward(fwd, 0.0, float(s["coast"]) * control * dt)
		if braking and grounded:
			fwd = move_toward(fwd, 0.0, float(s["brake"]) * 0.35 * dt)
	var g: float = float(s["slide_grip"]) if braking else float(s["grip"])
	var slip := v.y * exp(-g * control * dt)
	# Never faster than the boosted top speed, whatever the slope gave.
	var out := Vector2(fwd, slip)
	if out.length() > top * 1.25:
		out = out.normalized() * top * 1.25
	return out


## Yaw rate (rad/s) for a steering input. Wheels and hover craft need speed to
## turn and turn less at the top end; tracks and the hopper turn on the spot.
## Reversing steers the other way, as a car does. A handbrake tightens the turn.
static func yaw_rate(steer: float, forward_speed: float, braking: bool, s: Dictionary) -> float:
	var turn: float = float(s["turn"])
	if bool(s["turn_in_place"]):
		return steer * turn
	var top: float = float(s["max_speed"])
	var grip_in := clampf(absf(forward_speed) / 3.0, 0.0, 1.0)
	var high := 1.0 / (1.0 + 0.6 * clampf(absf(forward_speed) / top, 0.0, 1.5))
	var dir := 1.0 if forward_speed >= 0.0 else -1.0
	return steer * turn * grip_in * high * dir * (1.5 if braking else 1.0)


## Vertical acceleration for a hover craft. `clearance` is the height of the hull
## above whatever is under it (< 0: nothing in range, the ground fell away).
## In range: a damped spring toward the hover height that also carries its own
## weight, so it settles exactly at `hover`. Out of range: it glides, falling
## at only `glide` × gravity.
static func hover_accel(clearance: float, vy: float, s: Dictionary) -> float:
	var g: float = GRAVITY * float(s["gravity_scale"])
	var h: float = float(s["hover"])
	if clearance < 0.0 or clearance > h * 3.0:
		# Out of the cushion's reach: full gravity on the way up, a glide on the way down.
		return -g if vy > 0.0 else -g * float(s.get("glide", 1.0))
	var a := float(s["hover_k"]) * (h - clearance) - float(s["hover_c"]) * vy
	return clampf(a, -g * 3.0, 40.0)


## A damped spring step (semi-implicit Euler): returns Vector2(x, v).
## Used for the body's suspension bob and the landing squash.
static func spring_step(x: float, v: float, target: float, k: float, c: float, dt: float) -> Vector2:
	var a := -k * (x - target) - c * v
	v += a * dt
	x += v * dt
	return Vector2(x, v)


## How hard a landing squashes the body (0..0.45), from the vertical speed at
## touchdown (negative = falling).
static func landing_squash(impact_vy: float, s: Dictionary) -> float:
	if impact_vy > -1.5:
		return 0.0
	return clampf((-impact_vy - 1.5) * float(s["squash"]), 0.0, 0.45)


## The hopper's tank: seconds of thrust left after `dt` (thrusting or refuelling
## on the ground). Returns Vector2(fuel, thrust_fraction applied this step).
static func fuel_step(fuel: float, thrusting: bool, grounded: bool, s: Dictionary, dt: float) -> Vector2:
	var cap: float = float(s.get("fuel_s", 0.0))
	if thrusting and fuel > 0.0:
		var used := minf(fuel, dt)
		return Vector2(fuel - used, used / dt if dt > 0.0 else 0.0)
	if grounded:
		return Vector2(minf(cap, fuel + float(s.get("refuel", 1.0)) * dt), 0.0)
	return Vector2(fuel, 0.0)


## Body pitch and roll (radians) from the heights under the wheels: front/rear
## and left/right averages over the wheelbase and track width.
static func body_tilt(front: float, rear: float, left: float, right: float, wheelbase: float, track: float) -> Vector2:
	var pitch := atan2(front - rear, maxf(wheelbase, 0.1))
	var roll := atan2(left - right, maxf(track, 0.1))
	return Vector2(clampf(pitch, -0.7, 0.7), clampf(roll, -0.6, 0.6))
