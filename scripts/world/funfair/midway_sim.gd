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
## v2 (2026-11-24, "make it fun"): every game shares an arcade layer, all integer and in the sim:
##   - a STREAK of good results multiplies the points (×1, ×2, ×3 … up to the game's cap); any
##     other result ends it and scores ×1;
##   - escalation: each throw is harder than the last (faster meters, stronger drift, sliding
##     rings, more sway, faster rails, shorter pop-ups, faster wheels);
##   - BONUS targets (a perfect swing, the bullseye, a gold peg, gold crystals, Mersenne primes,
##     the jackpot);
##   - the FRENZY: the last throw(s) (Motzkin: the last 8 s) score double;
##   - a near miss is flagged ("SO CLOSE!") for the stage; it scores nothing extra.
## Saat (the fortune teller) is now Higher or Lower with her cards; the fortune is still read.
##
## Live play: press(ax, ay) queues a press (only when the game accepts one), and the next
## step() applies it at that tick and appends it to `events`. The 3D stage (MidwayStage)
## only reads this state. Nothing here knows about nodes, time or the network.

const VERSION := 2
const HZ := 60
const AIM := 640            ## aim values are integers in [-AIM, AIM]; +AIM fits two base-36 digits
const READY_LIMIT := 900    ## 15 s to throw; then the round is a miss (the wheel brakes itself)
const MAX_TICKS := 12000    ## replay hard stop (no round runs this long)
const SHOW_T := 32          ## ticks a round's result stays up (snappy: about half a second)

## rounds: throws (Motzkin: shots), axes: aim values a press carries, base: the best single
## result before multipliers, cap: the streak multiplier's cap, frenzy: final throws at ×2
## (Motzkin: any shot can fall in its frenzy seconds), par: the score of the grand prize.
const SPEC := {
	"striker": {"rounds": 5, "axes": 0, "base": 150, "cap": 3, "frenzy": 1, "par": 1100},
	"entropy": {"rounds": 5, "axes": 1, "base": 150, "cap": 3, "frenzy": 1, "par": 900},
	"regolith": {"rounds": 6, "axes": 2, "base": 200, "cap": 3, "frenzy": 1, "par": 1400},
	"crystal": {"rounds": 8, "axes": 2, "base": 250, "cap": 3, "frenzy": 2, "par": 2000},
	"motzkin": {"rounds": 20, "axes": 2, "base": 250, "cap": 4, "frenzy": 20, "par": 3000},
	"waat": {"rounds": 5, "axes": 0, "base": 500, "cap": 3, "frenzy": 1, "par": 1600},
	"saat": {"rounds": 7, "axes": 1, "base": 50, "cap": 5, "frenzy": 1, "par": 700},
}

# Striker (Test Your Affection): the bell is BELL mm up the pole.
const BELL := 6800
const STRIKER_G := 7          ## mm/tick² on the puck
const STRIKER_PERIODS := [90, 78, 66, 56, 46]
const STRIKER_PERFECT := 988  ## meter ≥ this: a PERFECT swing (150)
const SWING_T := 12
# Entropy Toss: the puck leaves the hand at z = TOSS_Z0 (mm, stall space, +z toward you).
const TOSS_Z0 := 700
const TOSS_BACK := -1100      ## the board's far edge
const TOSS_RINGS := [45, 130, 220]
const TOSS_POINTS := [150, 60, 25]
const TOSS_FLY := 40
const TOSS_PERIOD := 80
const TOSS_SLIDE := [0, 0, 260, 420, 560]  ## the rings slide side to side from the third puck
# Regolith Ring Toss: pegs on the board (u across, v up the board, mm).
const PEGS_U := [-600, 0, 600]
const PEGS_V := [200, 500, 800]
const RING_FLY := 30
const SWAY := 60              ## + SWAY_UP per ring
const SWAY_UP := 22
# Crystal Shy: two rails of five crystals, period RAIL_L mm.
const RAIL_L := 4000
const RAIL_N := 5
const SHY_FLY := [20, 24]
const SHY_HIT := 110
# Motzkin Prime Shooter: 4 × 2 pop-up slots on the back wall.
const SLOTS_X := [-1350, -450, 450, 1350]
const SLOTS_Y := [1450, 2200]
const PRIME_RUN := 1800       ## 30 s of targets
const PRIME_FRENZY := 1320    ## the last 8 s: faster pop-ups, double points
const PRIME_HIT := 230
const PRIME_COOL := 10
const PRIMES := [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97]
const MERSENNE := [3, 7, 31]  ## 2^p − 1: the gold targets (250)
const DECOYS := [9, 15, 21, 25, 27, 33, 35, 39, 45, 49, 51, 55, 57, 63, 65, 69, 75, 77, 81, 85, 87, 91, 93, 95, 99, 1, 4, 51, 57, 91]
# Waat Wheel: 12 segments, 12000 units a turn; braking takes WHEEL_DECEL a tick.
const TURN := 12000
const WHEEL_DECEL := 2
const WHEEL_BASE := [10, 20, 25, 40, 50, 60, 75, 100, 120, 150, 200, 500]
const WHEEL_GOOD := 100
# Saat (Higher or Lower): ranks 1..13, the next card turns in FLIP_T ticks.
const FLIP_T := 20

var game := ""
var seed_v := 0
var tick := 0
var score := 0
var round_i := 0          ## throws used (Motzkin: shots fired)
var phase := "ready"      ## ready | swing | fly | show | run | brake | done
var phase_t := 0
var done := false
var events: Array = []    ## the input log: [[tick, ax, ay], …]
var last_points := 0      ## what the last result added (after multipliers)
var last_text := ""
var last_tick := -1       ## the tick of the last result (for the stage's flashes)
var last_mult := 1        ## the multiplier the last result scored at (streak × frenzy)
var last_good := false    ## the last result kept the streak going
var last_bonus := false   ## a bonus target / perfect / jackpot
var last_near := false    ## a near miss ("SO CLOSE!")
var streak := 0           ## good results in a row
var best_streak := 0

# Per-game state (all ints; read by the 3D stage)
var meter := 0            ## striker / entropy power meter 0..1000
var power := 0
var puck_y := 0           ## striker: mm up the pole
var puck_v := 0
var peak := 0
var rang := false
var target := Vector2i()  ## entropy: rings centre (x, z) mm, now; motzkin: crosshair of the last shot
var target_base := 0      ## entropy: the x the rings slide about
var slide_ph := 0         ## entropy: the slide's phase (deci-degrees)
var wind := 0             ## entropy: lateral drift, mm per metre travelled
var shot_from := Vector2i()
var shot_to := Vector2i() ## where the current throw lands (entropy x,z · regolith u,v · crystal x,row)
var shot_t := 0           ## ticks the current throw takes
var sway_a := 0           ## regolith sway phases (deci-degrees)
var sway_b := 0
var gold_peg := 4         ## regolith: the gold peg this ring (u + 3 v)
var hit_peg := -1         ## regolith: the peg the last ring landed on (-1: none)
var rails: Array = []     ## crystal: [[offset, speed], [offset, speed]] (offset moves every tick)
var knocked := [0, 0]     ## crystal: bitmask of knocked crystals per rail
var gold := [0, 0]        ## crystal: the gold crystal's index per rail
var hit_index := -1       ## crystal: the crystal this throw knocks (-1: a miss)
var near_dx := 0          ## crystal: how far the closest crystal was at arrival
var schedule: Array = []  ## motzkin: [[slot, start, end, n], …]
var shot_down: Array = [] ## motzkin: per schedule entry, the tick it was shot (-1: not)
var cooldown := 0
var wheel: Array = []     ## waat: 12 segment values
var angle := 0            ## waat: 0..TURN-1
var speed := 0
var cards: Array = []     ## saat: ranks 1..13; cards[round_i] is face up, the next is guessed
var guess := 0            ## saat: −1 lower, +1 higher, 0 none (too slow)

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
				var sp := _range(8, 12) * (1 if r == 0 else -1)
				rails.append([_range(0, RAIL_L - 1), sp])
				gold[r] = _range(0, RAIL_N - 1)
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
		"saat":
			for i in rounds(game) + 1:
				var c := _range(1, 13)
				if i > 0 and c == int(cards[i - 1]):  # never a tie to guess
					c = c % 13 + 1
				cards.append(c)
	_new_round()


## The stall's code (1..7): the last wei of its ticket (FairProgress) and the RNG's salt.
static func code(id: String) -> int:
	return ["striker", "entropy", "regolith", "crystal", "motzkin", "waat", "saat"].find(id) + 1


## The highest score the rules allow: every throw the best result at full streak and frenzy.
static func max_score(id: String) -> int:
	if not SPEC.has(id):
		return 0
	var sp: Dictionary = SPEC[id]
	var n := int(sp["rounds"])
	var total := 0
	for i in n:
		total += int(sp["base"]) * mini(i + 1, int(sp["cap"])) * (2 if i >= n - int(sp["frenzy"]) else 1)
	return total


## The grand prize's score (MidwayGame's prize tiers are fractions of it).
static func par(id: String) -> int:
	return int(SPEC.get(id, {}).get("par", 0))


static func rounds(id: String) -> int:
	return int(SPEC.get(id, {}).get("rounds", 0))


static func axes(id: String) -> int:
	return int(SPEC.get(id, {}).get("axes", 0))


## Is throw `i` (0-based) in the frenzy? (Motzkin: by the clock.)
func frenzy_round(i: int) -> bool:
	if game == "motzkin":
		return tick >= PRIME_FRENZY
	return i >= rounds(game) - int(SPEC[game]["frenzy"])


func frenzy_now() -> bool:
	return frenzy_round(round_i)


## The multiplier the next good result would score at.
func next_mult() -> int:
	return mini(streak + 1, int(SPEC[game]["cap"])) * (2 if frenzy_now() else 1)


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


## A throw's result: `base` points before multipliers; `good` keeps (or starts) the streak.
## Good results score base × the streak's multiplier, others base × 1; both ×2 in the frenzy.
func _score(base: int, good: bool, text: String, bonus: bool = false, near: bool = false) -> void:
	var fr := 2 if frenzy_now() else 1
	if good:
		streak += 1
		best_streak = maxi(best_streak, streak)
	else:
		streak = 0
	var m := (mini(streak, int(SPEC[game]["cap"])) if good else 1) * fr
	var pts := base * m
	score = maxi(0, score + pts)
	last_points = pts
	last_mult = m
	last_good = good
	last_bonus = bonus
	last_near = near
	last_text = text
	if base != 0:
		last_text = "%s %s%d" % [text, "+" if pts > 0 else "", pts]
		if m > 1 and pts > 0:
			last_text += " ×%d" % m
	last_tick = tick


func _result(base: int, good: bool, text: String, bonus: bool = false, near: bool = false) -> void:
	_score(base, good, text, bonus, near)
	round_i += 1
	_set_phase("show")


func _new_round() -> void:
	match game:
		"entropy":
			target_base = _range(-800, 800)
			target = Vector2i(target_base, _range(-800, -150))
			wind = _range(-60 - 30 * round_i, 60 + 30 * round_i)
			slide_ph = _range(0, 3599)
		"regolith":
			sway_a = _range(0, 3599)
			sway_b = _range(0, 3599)
			gold_peg = _range(0, 8)
		"waat":
			speed = _range(110, 150) + 28 * round_i


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
			var best := 1 << 30
			for i in RAIL_N:
				if knocked[row] & (1 << i):
					continue
				var dx := absi(crystal_x(row, i, tick + shot_t) - shot_to.x)
				if dx < best:
					best = dx
					hit_index = i if dx <= SHY_HIT else -1
			near_dx = best
			_set_phase("fly")
		"motzkin":
			_shoot(ax, ay)
		"waat":
			_set_phase("brake")
		"saat":
			guess = -1 if ax < 0 else 1
			_set_phase("fly")


func _shoot(ax: int, ay: int) -> void:
	round_i += 1
	cooldown = PRIME_COOL
	target = Vector2i(ax * 1800 / AIM, 1825 + ay * 700 / AIM)
	var hit := -1
	var closest := 1 << 30
	for i in schedule.size():
		if not target_up(i, tick):
			continue
		var dx := int(SLOTS_X[int(schedule[i][0]) % 4]) - target.x
		var dy := int(SLOTS_Y[int(schedule[i][0]) / 4]) - target.y
		var d2 := dx * dx + dy * dy
		if d2 <= PRIME_HIT * PRIME_HIT:
			hit = i
			break
		closest = mini(closest, d2)
	if hit < 0:
		var near := closest <= 4 * PRIME_HIT * PRIME_HIT
		_score(0, false, "SO CLOSE!" if near else "miss", false, near)
		return
	shot_down[hit] = tick
	var n := int(schedule[hit][3])
	if not is_prime(n):
		_score(-50, false, "%d isn't prime" % n)
	elif n in MERSENNE:
		_score(250, true, "%d MERSENNE!" % n, true)
	else:
		_score(100, true, "%d PRIME" % n)


func _advance() -> void:
	match game:
		"striker": _adv_striker()
		"entropy": _adv_entropy()
		"regolith": _adv_throw()
		"crystal":
			for r in 2:
				rails[r][0] = posmod(int(rails[r][0]) + int(rails[r][1]), RAIL_L)
			_adv_throw()
		"motzkin": _adv_motzkin()
		"waat": _adv_waat()
		"saat": _adv_saat()


func _ready_timeout() -> bool:
	if phase == "ready" and phase_t >= READY_LIMIT:
		_result(0, false, "too slow")
		return true
	return false


func _after_show() -> void:
	if phase == "show" and phase_t >= SHOW_T:
		if round_i >= rounds(game):
			_finish()
		else:
			meter = 0  # a fresh meter: never a stale reading from the last throw
			_new_round()
			_set_phase("ready")


func _adv_striker() -> void:
	match phase:
		"ready":
			meter = tri(phase_t, STRIKER_PERIODS[mini(round_i, STRIKER_PERIODS.size() - 1)])
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
				if rang and power >= STRIKER_PERFECT:
					_result(150, true, "PERFECT!", true)
				elif rang:
					_result(100, true, "DING!")
				else:
					var pts := peak * 100 / BELL
					_result(pts, false, "SO CLOSE!" if pts >= 88 else "%d%%" % pts, false, pts >= 88)
		"show":
			_after_show()


## Entropy: the rings' centre x at tick t (they slide side to side from the third puck).
func target_x(t: int) -> int:
	var amp := int(TOSS_SLIDE[mini(round_i, TOSS_SLIDE.size() - 1)])
	return target_base + isin(slide_ph + t * (14 + 3 * round_i)) * amp / 1000


func _adv_entropy() -> void:
	target.x = target_x(tick)
	match phase:
		"ready":
			meter = tri(phase_t, TOSS_PERIOD - 6 * round_i)
			_ready_timeout()
		"fly":
			if phase_t >= shot_t:
				if shot_to.y < TOSS_BACK or absi(shot_to.x) > 1500:
					_result(0, false, "off the board")
					return
				var dx := shot_to.x - target.x
				var dz := shot_to.y - target.y
				var r := isqrt(dx * dx + dz * dz)
				if r <= int(TOSS_RINGS[0]):
					_result(150, true, "BULLSEYE!", true)
				elif r <= int(TOSS_RINGS[1]):
					_result(60, true, "INNER RING")
				elif r <= int(TOSS_RINGS[2]):
					_result(25, false, "outer ring")
				else:
					var near := r <= int(TOSS_RINGS[2]) + 90
					_result(0, false, "SO CLOSE!" if near else "missed the rings", false, near)
		"show":
			_after_show()


func _adv_throw() -> void:
	match phase:
		"ready":
			_ready_timeout()
		"fly":
			if phase_t >= shot_t:
				if game == "regolith":
					_land_ring()
				elif hit_index >= 0:
					var row := shot_to.y
					knocked[row] = int(knocked[row]) | (1 << hit_index)
					var g := hit_index == int(gold[row])
					_result(250 if g else 100, true, "GOLD CRYSTAL!" if g else "SMASH!", g)
					for r in 2:  # the rails speed up with every crystal down
						rails[r][1] = int(rails[r][1]) + (2 if int(rails[r][1]) > 0 else -2)
				else:
					var near := near_dx <= SHY_HIT + 110
					_result(0, false, "SO CLOSE!" if near else "miss", false, near)
		"show":
			_after_show()


func _land_ring() -> void:
	var best := 1 << 30
	var peg := -1
	for v in 3:
		for u in 3:
			var du := shot_to.x - int(PEGS_U[u])
			var dv := shot_to.y - int(PEGS_V[v])
			if du * du + dv * dv < best:
				best = du * du + dv * dv
				peg = u + 3 * v
	var g := peg == gold_peg
	hit_peg = peg if best <= 90 * 90 else -1
	if best <= 40 * 40:
		_result(200 if g else 100, true, "GOLD RINGER!" if g else "RINGER!", g)
	elif best <= 90 * 90:
		_result(100 if g else 50, true, "gold leaner" if g else "leaner", g)
	else:
		var near := best <= 150 * 150
		_result(0, false, "SO CLOSE!" if near else "bounced off", false, near)


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
				var seg := segment()
				var v := int(wheel[seg])
				if v == 500:
					_result(v, true, "JACKPOT!", true)
				elif v >= WHEEL_GOOD:
					_result(v, true, "BIG WIN")
				else:
					var near := int(wheel[(seg + 1) % 12]) == 500 or int(wheel[(seg + 11) % 12]) == 500
					_result(v, false, "SO CLOSE!" if near else "", false, near)
			else:
				angle = posmod(angle + speed, TURN)
		"show":
			_after_show()


func _adv_saat() -> void:
	match phase:
		"ready":
			if phase_t >= READY_LIMIT:
				guess = 0
				_set_phase("fly")
		"fly":
			if phase_t >= FLIP_T:
				var a := int(cards[round_i])
				var b := int(cards[round_i + 1])
				if (b > a and guess > 0) or (b < a and guess < 0):
					_result(50, true, "RIGHT!", absi(b - a) <= 2)
				else:
					var near := absi(b - a) <= 1 and guess != 0
					_result(0, false, ("SO CLOSE!" if near else "wrong") if guess != 0 else "too slow", false, near)
		"show":
			_after_show()


# --- Read by the stage -------------------------------------------------------------------

## Regolith: the hand's sway now (mm on the board); it grows with every ring.
func sway() -> Vector2i:
	var a := SWAY + SWAY_UP * round_i
	return Vector2i(isin(sway_a + phase_t * 31) * a / 1000, isin(sway_b + phase_t * 23) * a / 1000)


## Crystal Shy: crystal i of rail `row` at tick t (≥ now), x in mm (−RAIL_L/2 .. RAIL_L/2).
func crystal_x(row: int, i: int, t: int) -> int:
	var r: Array = rails[row]
	return posmod(int(r[0]) + i * (RAIL_L / RAIL_N) + int(r[1]) * (t - tick), RAIL_L) - RAIL_L / 2


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


## Pop-ups come faster and stay up shorter as the 30 s run on; the frenzy's are quickest.
func _plan_targets() -> void:
	var t := 24
	var busy := [0, 0, 0, 0, 0, 0, 0, 0]  # tick each slot frees
	while t < PRIME_RUN - 40:
		var slot := _range(0, 7)
		if int(busy[slot]) <= t:
			var fr := t >= PRIME_FRENZY
			var up := _range(70, 115) - t / 40 - (10 if fr else 0)
			var roll := _range(0, 99)
			var n := 0
			if roll < 10:
				n = int(MERSENNE[_range(0, MERSENNE.size() - 1)])
			elif roll < 50:
				n = int(PRIMES[_range(0, PRIMES.size() - 1)])
			else:
				n = int(DECOYS[_range(0, DECOYS.size() - 1)])
			schedule.append([slot, t, mini(t + up, PRIME_RUN), n])
			shot_down.append(-1)
			busy[slot] = t + up + 10
		t += _range(14, 24) if fr_at(t) else _range(24, 40) - t / 120


static func fr_at(t: int) -> bool:
	return t >= PRIME_FRENZY


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
