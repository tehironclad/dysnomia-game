class_name MidwaySim
extends RefCounted
## The Affection Fair's mini games as pure, deterministic simulations.
##
## A round is a state stepped at fixed ticks (HZ = 60) with integers only (mm, ticks,
## 1/12000 of a turn, an integer sine), its randomness from an xorshift32 seeded by the
## ticket's seed (MidwayGame.seed_from_tx). The only input is a log of presses:
## [tick, ax, ay], the aim quantised to integers in [-AIM, AIM]. So
##   replay(game, seed, log) == the score the player saw,
## on any machine, which is what lets a room line be checked (FairBoard): the line carries
## the ticket and the compact log, every reader replays it.
##
## Live play: press(ax, ay) queues a press (only when the game accepts one), and the next
## step() applies it at that tick and appends it to `events`. The 3D stage (MidwayStage)
## only reads this state. Nothing here knows about nodes, time or the network.

const VERSION := 1
const HZ := 60
const AIM := 640            ## aim values are integers in [-AIM, AIM]; +AIM fits two base-36 digits
const READY_LIMIT := 900    ## 15 s to throw; then the round is a miss (the wheel brakes itself)
const MAX_TICKS := 12000    ## replay hard stop (no round runs this long)
const SHOW_T := 50          ## ticks a round's result stays up

## rounds: throws (Motzkin: shots), axes: how many aim values a press carries, max: best score.
const SPEC := {
	"striker": {"rounds": 3, "axes": 0, "max": 300},
	"entropy": {"rounds": 3, "axes": 1, "max": 300},
	"regolith": {"rounds": 5, "axes": 2, "max": 500},
	"crystal": {"rounds": 8, "axes": 2, "max": 800},
	"motzkin": {"rounds": 15, "axes": 2, "max": 1500},
	"waat": {"rounds": 3, "axes": 0, "max": 1500},
	"saat": {"rounds": 3, "axes": 0, "max": 0},
}

# Striker (Test Your Affection): the bell is BELL mm up the pole.
const BELL := 6800
const STRIKER_G := 7          ## mm/tick² on the puck
const STRIKER_PERIODS := [96, 80, 64]
const SWING_T := 16
# Entropy Toss: the puck leaves the hand at z = TOSS_Z0 (mm, stall space, +z toward you).
const TOSS_Z0 := 700
const TOSS_BACK := -1100      ## the board's far edge
const TOSS_RINGS := [60, 130, 220]
const TOSS_POINTS := [100, 60, 25]
const TOSS_FLY := 48
const TOSS_PERIOD := 84
# Regolith Ring Toss: pegs on the board (u across, v up the board, mm).
const PEGS_U := [-600, 0, 600]
const PEGS_V := [200, 500, 800]
const RING_FLY := 36
const SWAY := 90
# Crystal Shy: two rails of five crystals, period RAIL_L mm.
const RAIL_L := 4000
const RAIL_N := 5
const SHY_FLY := [22, 26]
const SHY_HIT := 110
# Motzkin Prime Shooter: 4 × 2 pop-up slots on the back wall.
const SLOTS_X := [-1350, -450, 450, 1350]
const SLOTS_Y := [1450, 2200]
const PRIME_RUN := 1800       ## 30 s of targets
const PRIME_HIT := 230
const PRIME_COOL := 10
const PRIMES := [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97]
const DECOYS := [9, 15, 21, 25, 27, 33, 35, 39, 45, 49, 51, 55, 57, 63, 65, 69, 75, 77, 81, 85, 87, 91, 93, 95, 99, 1, 4, 51, 57, 91]
# Waat Wheel: 12 segments, 12000 units a turn; braking takes WHEEL_DECEL a tick.
const TURN := 12000
const WHEEL_DECEL := 2
const WHEEL_BASE := [10, 20, 25, 40, 50, 60, 75, 100, 120, 150, 200, 500]

var game := ""
var seed_v := 0
var tick := 0
var score := 0
var round_i := 0          ## throws used (Motzkin: shots fired)
var phase := "ready"      ## ready | swing | fly | show | run | brake | done
var phase_t := 0
var done := false
var events: Array = []    ## the input log: [[tick, ax, ay], …]
var last_points := 0
var last_text := ""
var last_tick := -1       ## the tick of the last result (for the stage's flashes)

# Per-game state (all ints; read by the 3D stage)
var meter := 0            ## striker / entropy power meter 0..1000
var power := 0
var puck_y := 0           ## striker: mm up the pole
var puck_v := 0
var peak := 0
var rang := false
var target := Vector2i()  ## entropy: rings centre (x, z) mm; motzkin: crosshair of the last shot
var wind := 0             ## entropy: lateral drift, mm per metre travelled
var shot_from := Vector2i()
var shot_to := Vector2i() ## where the current throw lands (entropy x,z · regolith u,v · crystal x,row)
var shot_t := 0           ## ticks the current throw takes
var sway_a := 0           ## regolith sway phases (deci-degrees)
var sway_b := 0
var rails: Array = []     ## crystal: [[offset, speed], [offset, speed]]
var knocked := [0, 0]     ## crystal: bitmask of knocked crystals per rail
var hit_index := -1       ## crystal: the crystal this throw knocks (-1: a miss)
var schedule: Array = []  ## motzkin: [[slot, start, end, n], …]
var shot_down: Array = [] ## motzkin: per schedule entry, the tick it was shot (-1: not)
var cooldown := 0
var wheel: Array = []     ## waat: 12 segment values
var angle := 0            ## waat: 0..TURN-1
var speed := 0

var _rng := 1
var _queued: Array = []


func _init(p_game: String = "striker", p_seed: int = 1) -> void:
	game = p_game if SPEC.has(p_game) else "striker"
	seed_v = p_seed & 0x7fffffff
	_rng = (seed_v ^ 0x9e3779b9 ^ (code(game) * 0x45d9f3b)) & 0xffffffff
	if _rng == 0:
		_rng = 0x1234567
	for i in 4:
		_rand()
	match game:
		"crystal":
			for r in 2:
				var sp := _range(7, 13) * (1 if r == 0 else -1)
				rails.append([_range(0, RAIL_L - 1), sp])
		"motzkin":
			_plan_targets()
			phase = "run"
		"waat":
			wheel = WHEEL_BASE.duplicate()
			for i in range(wheel.size() - 1, 0, -1):
				var j := _range(0, i)
				var t = wheel[i]
				wheel[i] = wheel[j]
				wheel[j] = t
			angle = _range(0, TURN - 1)
	_new_round()


## The stall's code (1..7): the last wei of its ticket (FairProgress) and the RNG's salt.
static func code(id: String) -> int:
	return ["striker", "entropy", "regolith", "crystal", "motzkin", "waat", "saat"].find(id) + 1


static func max_score(id: String) -> int:
	return int(SPEC.get(id, {}).get("max", 0))


static func rounds(id: String) -> int:
	return int(SPEC.get(id, {}).get("rounds", 0))


static func axes(id: String) -> int:
	return int(SPEC.get(id, {}).get("axes", 0))


# --- Integer helpers ----------------------------------------------------------------

func _rand() -> int:
	var x := _rng
	x ^= (x << 13) & 0xffffffff
	x ^= x >> 17
	x ^= (x << 5) & 0xffffffff
	_rng = x & 0xffffffff
	return _rng


func _range(lo: int, hi: int) -> int:
	return lo + _rand() % (hi - lo + 1)


## sin(θ) × 1000 for θ in deci-degrees (any int), Bhaskara I's approximation: integers only.
static func isin(deci: int) -> int:
	var t := posmod(deci, 3600)
	var neg := t >= 1800
	if neg:
		t -= 1800
	var p := t * (1800 - t)
	var v := (4 * p * 1000) / (4050000 - p)
	return -v if neg else v


static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


## A triangle wave 0..1000..0 over `period` ticks.
static func tri(t: int, period: int) -> int:
	var x := posmod(t, period) * 2000 / period
	return 2000 - x if x > 1000 else x


# --- Input -----------------------------------------------------------------------------

## Does the game take a press now?
func accepts() -> bool:
	if done or not _queued.is_empty():
		return false
	if game == "motzkin":
		return phase == "run" and cooldown == 0 and round_i < rounds(game) and tick < PRIME_RUN
	return phase == "ready"


## Queues a press; the next step() applies it at that tick. false if the game takes none now.
func press(ax: int = 0, ay: int = 0) -> bool:
	if not accepts():
		return false
	var n := axes(game)
	_queued = [clampi(ax, -AIM, AIM) if n >= 1 else 0, clampi(ay, -AIM, AIM) if n >= 2 else 0]
	return true


func step() -> void:
	if done:
		return
	if not _queued.is_empty():
		var q: Array = _queued
		_queued = []
		events.append([tick, q[0], q[1]])
		_on_press(int(q[0]), int(q[1]))
	_advance()
	tick += 1
	phase_t += 1
	if tick >= MAX_TICKS and not done:
		_finish()


func _set_phase(p: String) -> void:
	phase = p
	phase_t = -1  # step() adds one after _advance


func _finish() -> void:
	done = true
	phase = "done"


func _result(points: int, text: String) -> void:
	score = maxi(0, score + points)
	last_points = points
	last_text = text
	last_tick = tick
	round_i += 1
	_set_phase("show")


func _new_round() -> void:
	match game:
		"entropy":
			target = Vector2i(_range(-900, 900), _range(-800, -100))
			wind = _range(-150, 150)
		"regolith":
			sway_a = _range(0, 3599)
			sway_b = _range(0, 3599)
		"waat":
			speed = _range(110, 170)


# --- Per-game rules --------------------------------------------------------------------

func _on_press(ax: int, ay: int) -> void:
	match game:
		"striker":
			power = meter
			_set_phase("swing")
		"entropy":
			power = meter
			var d := 400 + power * 1600 / 1000
			var ex := (d * ax * 500 / AIM) / 1000 + wind * d / 1000
			shot_from = Vector2i(0, TOSS_Z0)
			shot_to = Vector2i(ex, TOSS_Z0 - d)
			shot_t = TOSS_FLY
			_set_phase("fly")
		"regolith":
			var s := sway()
			shot_from = Vector2i(0, -400)
			shot_to = Vector2i(ax * 900 / AIM + s.x, 500 + ay * 500 / AIM + s.y)
			shot_t = RING_FLY
			_set_phase("fly")
		"crystal":
			var row := 1 if ay > 0 else 0
			shot_to = Vector2i(ax * 1700 / AIM, row)
			shot_t = SHY_FLY[row]
			hit_index = -1
			var arrive := tick + shot_t
			var best := SHY_HIT + 1
			for i in RAIL_N:
				if knocked[row] & (1 << i):
					continue
				var dx := absi(crystal_x(row, i, arrive) - shot_to.x)
				if dx < best:
					best = dx
					hit_index = i
			_set_phase("fly")
		"motzkin":
			round_i += 1
			cooldown = PRIME_COOL
			target = Vector2i(ax * 1800 / AIM, 1825 + ay * 700 / AIM)
			last_tick = tick
			var hit := -1
			for i in schedule.size():
				var e: Array = schedule[i]
				if int(shot_down[i]) >= 0 or tick < int(e[1]) or tick >= int(e[2]):
					continue
				var dx := int(SLOTS_X[int(e[0]) % 4]) - target.x
				var dy := int(SLOTS_Y[int(e[0]) / 4]) - target.y
				if dx * dx + dy * dy <= PRIME_HIT * PRIME_HIT:
					hit = i
					break
			if hit < 0:
				last_points = 0
				last_text = "miss"
			else:
				shot_down[hit] = tick
				var n := int(schedule[hit][3])
				if is_prime(n):
					last_points = 100
					last_text = "%d PRIME +100" % n
				else:
					last_points = -50
					last_text = "%d not prime −50" % n
				score = maxi(0, score + last_points)
		"waat":
			_set_phase("brake")
		"saat":
			round_i += 1
			last_tick = tick
			if round_i >= rounds(game):
				_set_phase("show")


func _advance() -> void:
	match game:
		"striker": _adv_striker()
		"entropy": _adv_entropy()
		"regolith": _adv_throw()
		"crystal": _adv_throw()
		"motzkin": _adv_motzkin()
		"waat": _adv_waat()
		"saat":
			if phase == "show" and phase_t >= SHOW_T:
				_finish()


func _ready_timeout() -> bool:
	if phase == "ready" and phase_t >= READY_LIMIT:
		_result(0, "too slow")
		return true
	return false


func _after_show() -> void:
	if phase == "show" and phase_t >= SHOW_T:
		if round_i >= rounds(game):
			_finish()
		else:
			_new_round()
			_set_phase("ready")


func _adv_striker() -> void:
	match phase:
		"ready":
			meter = tri(phase_t, STRIKER_PERIODS[mini(round_i, 2)])
			_ready_timeout()
		"swing":
			if phase_t >= SWING_T:
				var h := power * power * 7400 / 1000000
				puck_v = isqrt(2 * STRIKER_G * h)
				puck_y = 0
				peak = 0
				rang = false
				_set_phase("fly")
		"fly":
			puck_v -= STRIKER_G
			puck_y += puck_v
			if puck_y >= BELL:
				puck_y = BELL
				if not rang:
					rang = true
					peak = BELL
				puck_v = -absi(puck_v) / 3
			peak = maxi(peak, puck_y)
			if puck_y <= 0 and puck_v < 0:
				puck_y = 0
				var pts := 100 if rang else mini(99, peak * 100 / BELL)
				_result(pts, "DING! +100" if rang else "+%d" % pts)
		"show":
			_after_show()


func _adv_entropy() -> void:
	match phase:
		"ready":
			meter = tri(phase_t, TOSS_PERIOD)
			_ready_timeout()
		"fly":
			if phase_t >= shot_t:
				if shot_to.y < TOSS_BACK or absi(shot_to.x) > 1500:
					_result(0, "off the board")
					return
				var dx := shot_to.x - target.x
				var dz := shot_to.y - target.y
				var r := isqrt(dx * dx + dz * dz)
				var pts := 0
				for i in TOSS_RINGS.size():
					if r <= int(TOSS_RINGS[i]):
						pts = int(TOSS_POINTS[i])
						break
				_result(pts, ("BULL +100" if pts == 100 else "+%d" % pts) if pts > 0 else "missed the rings")
		"show":
			_after_show()


func _adv_throw() -> void:
	match phase:
		"ready":
			_ready_timeout()
		"fly":
			if phase_t >= shot_t:
				if game == "regolith":
					var best := 1 << 30
					for u in PEGS_U:
						for v in PEGS_V:
							var du := shot_to.x - int(u)
							var dv := shot_to.y - int(v)
							best = mini(best, du * du + dv * dv)
					var pts := 100 if best <= 40 * 40 else (50 if best <= 90 * 90 else 0)
					_result(pts, "RINGER +100" if pts == 100 else ("leaner +50" if pts > 0 else "bounced off"))
				else:
					if hit_index >= 0:
						knocked[shot_to.y] = int(knocked[shot_to.y]) | (1 << hit_index)
						_result(100, "HIT +100")
					else:
						_result(0, "miss")
		"show":
			_after_show()


func _adv_motzkin() -> void:
	if cooldown > 0:
		cooldown -= 1
	if tick >= PRIME_RUN or (round_i >= rounds(game) and cooldown == 0):
		_finish()


func _adv_waat() -> void:
	match phase:
		"ready":
			angle = posmod(angle + speed, TURN)
			if phase_t >= READY_LIMIT:
				_set_phase("brake")
		"brake":
			speed -= WHEEL_DECEL
			if speed <= 0:
				speed = 0
				var v := int(wheel[segment()])
				_result(v, "JACKPOT +500" if v == 500 else "+%d" % v)
			else:
				angle = posmod(angle + speed, TURN)
		"show":
			_after_show()


# --- Read by the stage -------------------------------------------------------------------

## Regolith: the hand's sway now (mm on the board).
func sway() -> Vector2i:
	return Vector2i(isin(sway_a + phase_t * 31) * SWAY / 1000, isin(sway_b + phase_t * 23) * SWAY / 1000)


## Crystal Shy: crystal i of rail `row` at tick t, x in mm (−RAIL_L/2 .. RAIL_L/2).
func crystal_x(row: int, i: int, t: int) -> int:
	var r: Array = rails[row]
	return posmod(int(r[0]) + i * (RAIL_L / RAIL_N) + int(r[1]) * t, RAIL_L) - RAIL_L / 2


## Waat: the segment under the pointer (top) at the current angle.
func segment() -> int:
	return (posmod(TURN - angle, TURN) * 12 / TURN) % 12


## Motzkin: is schedule entry i up at tick t?
func target_up(i: int, t: int) -> bool:
	var e: Array = schedule[i]
	return t >= int(e[1]) and t < int(e[2]) and (int(shot_down[i]) < 0 or t < int(shot_down[i]))


func ammo_left() -> int:
	return rounds(game) - round_i


static func is_prime(n: int) -> bool:
	if n < 2:
		return false
	if n % 2 == 0:
		return n == 2
	var i := 3
	while i * i <= n:
		if n % i == 0:
			return false
		i += 2
	return true


func _plan_targets() -> void:
	var t := 30
	var busy := [0, 0, 0, 0, 0, 0, 0, 0]  # tick each slot frees
	while t < PRIME_RUN - 40:
		var slot := _range(0, 7)
		if int(busy[slot]) <= t:
			var up := _range(70, 120)
			var n := int(PRIMES[_range(0, PRIMES.size() - 1)]) if _range(0, 99) < 45 else int(DECOYS[_range(0, DECOYS.size() - 1)])
			schedule.append([slot, t, mini(t + up, PRIME_RUN), n])
			shot_down.append(-1)
			busy[slot] = t + up + 12
		t += _range(26, 44)


# --- The log ---------------------------------------------------------------------------------

const B36 := "0123456789abcdefghijklmnopqrstuvwxyz"


static func _b36(n: int) -> String:
	if n <= 0:
		return "0"
	var s := ""
	while n > 0:
		s = B36[n % 36] + s
		n /= 36
	return s


static func _from36(s: String) -> int:
	var n := 0
	for ch in s:
		var d := B36.find(ch)
		if d < 0:
			return -1
		n = n * 36 + d
	return n


## The compact log: per press, the tick delta in base 36, then each aim value + AIM as two
## base-36 digits; presses joined by ".". e.g. "1k.2bxz3".
static func encode_log(id: String, log: Array) -> String:
	var n := axes(id)
	var parts := PackedStringArray()
	var prev := 0
	for e in log:
		var s := _b36(int(e[0]) - prev)
		prev = int(e[0])
		if n >= 1:
			s += _b36(int(e[1]) + AIM).lpad(2, "0")
		if n >= 2:
			s += _b36(int(e[2]) + AIM).lpad(2, "0")
		parts.append(s)
	return ".".join(parts)


## {ok, log} — ok false for anything malformed.
static func decode_log(id: String, text: String) -> Dictionary:
	var n := axes(id)
	var out: Array = []
	if text == "":
		return {"ok": true, "log": out}
	var prev := 0
	for part in text.split("."):
		if part.length() <= 2 * n or part.length() > 2 * n + 4:
			return {"ok": false, "log": []}
		var dt := _from36(part.left(part.length() - 2 * n))
		if dt < 0:
			return {"ok": false, "log": []}
		var a := [0, 0]
		for k in n:
			var v := _from36(part.substr(part.length() - 2 * n + 2 * k, 2))
			if v < 0 or v > 2 * AIM:
				return {"ok": false, "log": []}
			a[k] = v - AIM
		prev += dt
		out.append([prev, a[0], a[1]])
	return {"ok": true, "log": out}


## Replays a log from the seed: the score, or -1 when the log isn't one this game could
## have taken (a press it wouldn't accept, out of order, left over, or never finished).
static func replay(id: String, p_seed: int, log: Array) -> int:
	if not SPEC.has(id):
		return -1
	var s := MidwaySim.new(id, p_seed)
	var i := 0
	while not s.done and s.tick < MAX_TICKS:
		if i < log.size():
			var e: Array = log[i]
			if int(e[0]) < s.tick:
				return -1
			if int(e[0]) == s.tick:
				if not s.press(int(e[1]), int(e[2])):
					return -1
				i += 1
		s.step()
	if i < log.size() or not s.done:
		return -1
	return s.score
