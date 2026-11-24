class_name PoolAim
extends RefCounted
## Pure maths for pool in first person: the mouse's aim angle and the held
## charge become exactly the integers a shot line carries (`🎱 #id shot dx dy
## power`, PoolSim's inputs), and the aiming ghost is the real PoolSim run on a
## copy of the table, stopped shortly after the cue ball's first contact.
##
## Angles are in the sim's plane: 0 points along +x (the table's length),
## PI/2 along +y (across). The table node maps sim x → local X and sim y →
## local Z, so a sim angle is also a direction on the felt in table space.

const AIM_SCALE := 10000  # dx, dy are a unit vector × 10000 (as the 2D table panel sends them)
const MIN_POWER := 50
const MAX_POWER := 1000
const POWER_STEP := 10
const CHARGE_TIME := 1.4  # seconds from no power to full while the shot is held; then it falls back
const GHOST_EVERY := 4  # sim ticks between ghost points
const GHOST_MAX_TICKS := 1800  # 3.75 s of cue-ball travel without a contact
const GHOST_AFTER := 200  # ticks shown after the first contact


## The integer aim vector for an angle.
static func aim_vector(angle: float) -> Vector2i:
	return Vector2i(int(round(cos(angle) * AIM_SCALE)), int(round(sin(angle) * AIM_SCALE)))


## The angle of an aim vector (inverse of aim_vector up to rounding).
static func angle_of(v: Vector2i) -> float:
	return atan2(float(v.y), float(v.x))


## The angle from one sim point to another (to aim at a ball).
static func angle_to(from: Vector2i, to: Vector2i) -> float:
	return atan2(float(to.y - from.y), float(to.x - from.x))


## A unit direction on the felt (table-local X/Z) for an angle.
static func dir3(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


## Held time → charge 0..1, rising then falling back (a ping-pong meter).
static func charge_at(held: float) -> float:
	if held <= 0.0:
		return 0.0
	var u := fmod(held, CHARGE_TIME * 2.0) / CHARGE_TIME
	return u if u <= 1.0 else 2.0 - u


## Charge 0..1 → power MIN_POWER..MAX_POWER in POWER_STEP steps (the line's power field).
static func power_from_charge(c: float) -> int:
	c = clampf(c, 0.0, 1.0)
	var steps := int(round(c * float(MAX_POWER - MIN_POWER) / POWER_STEP))
	return clampi(MIN_POWER + steps * POWER_STEP, MIN_POWER, MAX_POWER)


## Power → the meter's 0..1.
static func charge_of(power: int) -> float:
	return clampf(float(power - MIN_POWER) / float(MAX_POWER - MIN_POWER), 0.0, 1.0)


## {dx, dy, power}: what the shot line carries for this aim and charge.
static func shot_params(angle: float, charge: float) -> Dictionary:
	var v := aim_vector(angle)
	return {"dx": v.x, "dy": v.y, "power": power_from_charge(charge)}


## The cue ball's starting speed for a power, in metres per second (for the HUD).
static func speed_mps(power: int) -> float:
	return float(PoolSim.VMAX * clampi(power, 1, 1000) / 1000) * PoolSim.TICK_HZ / 1e6


## Sim micrometres → table-local metres (on the cloth, at the balls' centres).
static func to_local(x: int, y: int) -> Vector3:
	return Vector3(float(x) / 1e6 - 1.27, PoolTable3D.BED + 0.0286, float(y) / 1e6 - 0.635)


## The aiming ghost, from the real PoolSim on a copy of `snap` (a snapshot).
## {cue_path: [Vector2i] up to the contact (or the whole run if none),
##  target: ball id first hit (-1 none), contact_at: Vector2i (the cue ball when it touches),
##  target_path: [Vector2i] the struck ball afterwards, cue_after: [Vector2i],
##  pocketed: [ids that dropped within the preview], first_contact: as PoolSim reports it}.
static func ghost(snap: PackedInt64Array, dx: int, dy: int, power: int) -> Dictionary:
	var out := {"cue_path": [], "target": -1, "contact_at": Vector2i(-1, -1), "target_path": [], "cue_after": [], "pocketed": []}
	if snap.size() < 48 or snap[2] != 0 or (dx == 0 and dy == 0):
		return out
	var sim := PoolSim.new()
	sim.apply_snapshot(snap)
	var r := sim.shoot(dx, dy, power, GHOST_EVERY, GHOST_MAX_TICKS, GHOST_AFTER)
	var frames: Array = r.get("frames", [])
	out["pocketed"] = r["pocketed"]
	var target: int = r["first_contact"]
	out["target"] = target
	var cue: Array = [Vector2i(snap[0], snap[1])]
	var hit_k := frames.size()
	if target >= 0:
		var t0 := Vector2i(snap[target * 3], snap[target * 3 + 1])
		for k in frames.size():
			var f: PackedInt64Array = frames[k]
			if Vector2i(f[target * 3], f[target * 3 + 1]) != t0:
				hit_k = k
				break
	for k in mini(hit_k, frames.size()):
		var f: PackedInt64Array = frames[k]
		if f[2] != 0:
			break
		cue.append(Vector2i(f[0], f[1]))
	out["cue_path"] = cue
	if target < 0 or hit_k >= frames.size():
		return out
	var hit: PackedInt64Array = frames[hit_k]
	out["contact_at"] = Vector2i(hit[0], hit[1])
	var tp: Array = [Vector2i(snap[target * 3], snap[target * 3 + 1])]
	var ca: Array = []
	for k in range(hit_k, frames.size()):
		var f: PackedInt64Array = frames[k]
		if f[target * 3 + 2] == 0:
			tp.append(Vector2i(f[target * 3], f[target * 3 + 1]))
		if f[2] == 0:
			ca.append(Vector2i(f[0], f[1]))
	out["target_path"] = tp
	out["cue_after"] = ca
	return out


## A first aim that points somewhere useful: at the object ball nearest the cue
## ball, or `fallback`.
static func default_angle(snap: PackedInt64Array, fallback: float = 0.0) -> float:
	if snap.size() < 48 or snap[2] != 0:
		return fallback
	var cue := Vector2i(snap[0], snap[1])
	var best := -1
	var best_d := 1 << 62
	for b in range(1, 16):
		if snap[b * 3 + 2] != 0:
			continue
		var ex := snap[b * 3] - cue.x
		var ey := snap[b * 3 + 1] - cue.y
		var d := ex * ex + ey * ey
		if d < best_d:
			best_d = d
			best = b
	if best < 0:
		return fallback
	return angle_to(cue, Vector2i(snap[best * 3], snap[best * 3 + 1]))


## Where the shooter's eye goes: behind the cue ball (table-local), `back`
## metres along the reverse aim and `up` above the cloth's ball centres.
static func eye_behind(cue_local: Vector3, angle: float, back: float, up: float) -> Vector3:
	return cue_local - dir3(angle) * back + Vector3.UP * up
