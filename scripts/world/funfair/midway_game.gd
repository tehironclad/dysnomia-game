class_name MidwayGame
extends RefCounted
## The Affection Fair's midway games: what each stall plays, and the pure rules
## (seeding, scoring, prizes) the overlay (MidwayOverlay) runs. No network here.
##
## A paid round is seeded by its own ticket: the AFFECTION.transfer tx hash that
## ArcadePay verified in the receipt, so the targets, numbers and wheel come from
## the chain, not from this computer. A practice round (no wallet) is seeded
## locally and says so. Scores are kept on this computer only (ArcadeScores).
## Every game is one button (Use) and skill-based; prizes are bragging rights.

const GAMES := {
	"striker": {"title": "TEST YOUR AFFECTION", "mech": "striker", "rounds": 3,
		"how": "The meter swings. Press Use at the top to ring the bell. Three swings."},
	"entropy": {"title": "ENTROPY TOSS", "mech": "toss", "rounds": 3,
		"how": "Each toss has a target band. Press Use when the power meter sits in it."},
	"regolith": {"title": "REGOLITH RING TOSS", "mech": "rings", "rounds": 3,
		"how": "Press Use to stop the sweep across, then again to stop it down. Land on a peg."},
	"crystal": {"title": "CRYSTAL SHY", "mech": "shy", "rounds": 8,
		"how": "Crystals slide past the sight. Press Use to throw. Eight throws."},
	"motzkin": {"title": "MOTZKIN PRIME SHOOTER", "mech": "primes", "rounds": 12,
		"how": "Numbers drift through the sight. Shoot only the primes (+100); a non-prime costs 50."},
	"waat": {"title": "WAAT WHEEL OF FORTUNE", "mech": "wheel", "rounds": 3,
		"how": "The wheel spins. Press Use to brake; it always slows the same way, so time it."},
	"saat": {"title": "SAAT FORTUNE TELLER", "mech": "fortune", "rounds": 1,
		"how": "The teller reads your ticket's transaction hash."},
}

const PRIZES := [
	[0.85, "GRAND PRIZE · an Upsilon toy rocket"],
	[0.6, "a crystal plush moon"],
	[0.35, "a glow-stick of Eris ice"],
	[0.0, "a paper Dysnomia pennant"],
]

const FORTUNES := [
	"A Su you skip today becomes a tower you never climb.",
	"Your Hypobar is a floor, never a ceiling.",
	"The QING remembers every Ⓐ; so should you.",
	"A neighbour across the force field is waiting for your Join.",
	"Entropy favours the one who reacts first.",
	"The Void answers those who speak in it.",
	"Your next block is closer than your last.",
	"What the chain records, no one can take away.",
	"Bars never shrink. Neither should you.",
	"Fornax rises for the patient.",
	"The Capital was a Wild lot once.",
	"Somewhere a Motzkin prime has your name on it.",
]


static func has_game(id: String) -> bool:
	return GAMES.has(id)


static func title(id: String) -> String:
	return String(GAMES.get(id, {}).get("title", id.to_upper()))


## A 31-bit seed from a tx hash ("0x…64 hex"); 0 if it isn't one.
static func seed_from_tx(tx: String) -> int:
	var h := tx.to_lower().trim_prefix("0x")
	if h.length() < 8 or not h.is_valid_hex_number():
		return 0
	return h.right(8).hex_to_int() & 0x7fffffff


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


## The best score a game allows (for the prize fraction).
static func max_score(id: String) -> int:
	match String(GAMES.get(id, {}).get("mech", "")):
		"striker": return 300
		"toss": return 300
		"rings": return 300
		"shy": return 800
		"primes": return 1200
		"wheel": return 1500
	return 0


static func prize(id: String, score: int) -> String:
	var m := max_score(id)
	if m <= 0:
		return ""
	var f := clampf(float(score) / m, 0.0, 1.0)
	for p in PRIZES:
		if f >= float(p[0]):
			return String(p[1])
	return String(PRIZES[-1][1])


# --- Per-mechanic pure rules ---------------------------------------------------

## The meter's position 0..1 at time t for round r (it speeds up each round).
static func meter(t: float, r: int) -> float:
	return 0.5 - 0.5 * cos(t * (2.4 + 0.9 * r))


## Striker: points for a swing (0..100); the bell rings at ≥ 0.96.
static func striker_points(m: float) -> int:
	return int(round(clampf(m, 0.0, 1.0) * 100.0))


## Toss: the target band centre for round r (0.3..0.9), from the seed.
static func toss_target(seed_v: int, r: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 7 + r
	return rng.randf_range(0.3, 0.9)


static func toss_points(m: float, target: float) -> int:
	var e := absf(m - target)
	if e <= 0.03:
		return 100
	if e <= 0.07:
		return 60
	if e <= 0.12:
		return 25
	return 0


## Rings: pegs on a 3×3 board at u, v ∈ {0.2, 0.5, 0.8}. Points for a landing.
static func ring_points(u: float, v: float) -> int:
	var best := 1.0
	for pu in [0.2, 0.5, 0.8]:
		for pv in [0.2, 0.5, 0.8]:
			best = minf(best, Vector2(u - pu, v - pv).length())
	if best <= 0.04:
		return 100
	if best <= 0.08:
		return 50
	return 0


## Shy: crystals per row (row, offset, speed) from the seed.
static func shy_rows(seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 13 + 1
	var rows := []
	for i in 2:
		rows.append({"offset": rng.randf(), "speed": rng.randf_range(0.18, 0.32) * (1.0 if i == 0 else -1.0), "gap": rng.randf_range(0.22, 0.3)})
	return rows


## Is a crystal under the sight (x = 0.5) on this row at time t? Crystals are
## `gap` apart, each 0.08 wide.
static func shy_hit(row: Dictionary, t: float) -> bool:
	var gap := float(row["gap"])
	var x := fposmod(0.5 - float(row["offset"]) - float(row["speed"]) * t, gap)
	return x <= 0.04 or x >= gap - 0.04


## Primes: the sequence of numbers the shooter sends (about 40% primes), from the seed.
static func prime_sequence(seed_v: int, n: int = 40) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 5
	var out := PackedInt32Array()
	for i in n:
		var k := rng.randi_range(2, 199)
		if rng.randf() < 0.4:
			while not is_prime(k):
				k += 1
		out.append(k)
	return out


## Wheel: twelve segment values from the seed (one 500 jackpot).
static func wheel_values(seed_v: int) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 17 + 3
	var base := [10, 20, 25, 40, 50, 60, 75, 100, 120, 150, 200, 500]
	for i in range(base.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = base[i]
		base[i] = base[j]
		base[j] = tmp
	return PackedInt32Array(base)


const WHEEL_SPEED := 7.0   # rad/s while spinning
const WHEEL_DECEL := 2.2   # rad/s² once braked: the same every time


## Where the wheel stops (radians), braked at angle a0.
static func wheel_stop(a0: float) -> float:
	return a0 + WHEEL_SPEED * WHEEL_SPEED / (2.0 * WHEEL_DECEL)


## The segment under the pointer (at the top) for a wheel angle.
static func wheel_segment(angle: float) -> int:
	return int(floor(fposmod(-angle, TAU) / (TAU / 12.0))) % 12


static func fortune(seed_v: int) -> String:
	return FORTUNES[absi(seed_v) % FORTUNES.size()]
