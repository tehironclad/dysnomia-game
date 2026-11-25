extends ArcadeGame
## Motzkin Sieve: numbers rain down on the QING; shoot the composites, let the primes through.
##
## Left/right slide the sieve along the floor; fire shoots a bolt straight up. A composite hit by a
## bolt shatters into its prime factors (91 → 7 × 13): gold shards that fall fast, worth their value
## times the combo if the sieve catches them. A prime is never shot: hitting one costs a life. Let a
## prime reach the floor and it banks (its value, the combo grows); catch it on the sieve for double.
## A composite that reaches the floor (or lands on the sieve) costs a life and the combo. The Motzkin
## primes (2, 127, 15511, the primes among 1, 1, 2, 4, 9, 21, 51, 127, …) fall gold: catch one for a
## big bonus. Every 12 numbers sieved the level rises: bigger numbers, faster rain.
## Everything is integer arithmetic on small ints; the rng (seeded by the play) picks the numbers.

const FLOOR_Y := 222.0
const SIEVE_W := 34.0
const SIEVE_SPEED := 170.0
const BOLT_SPEED := 360.0
const BOLT_COOLDOWN := 0.16
const MAX_BOLTS := 3
const BLOCK_H := 14.0
const SHARD_FALL := 120.0
const MOTZKIN_PRIMES := [2, 127, 15511]
const MOTZKIN_BONUS := 500
const PER_LEVEL := 12

var sieve_x := 160.0
var blocks: Array = []  # {x, y, n, prime: bool, motzkin: bool, w}
var shards: Array = []  # {x, y, n, vx}
var bolts: Array = []  # Vector2
var popups: Array = []  # {p: Vector2, s: String, c: Color, life}
var combo := 0
var level := 1
var sieved := 0  ## numbers resolved this level (shot, banked, caught or leaked)
var spawn_t := 0.8
var cooldown := 0.0
var flash := 0.0
var flash_c := MAGENTA
var last_event := ""  ## the last thing that happened ("SHATTER 91 = 7 × 13", "BANK 37", "LEAK 51"…)
var _ai_target := 160.0
var _gen := 0  ## bumped by every reset: a lost life that restarts the demo ends this step


func title() -> String:
	return "Motzkin Sieve"


func blurb() -> String:
	return "Shoot composites into prime shards; let primes through. Fire: bolt."


## Pure: is n prime (n < 2^31; trial division, small n only here).
static func is_prime(n: int) -> bool:
	if n < 2:
		return false
	if n < 4:
		return true
	if n % 2 == 0 or n % 3 == 0:
		return false
	var d := 5
	while d * d <= n:
		if n % d == 0 or n % (d + 2) == 0:
			return false
		d += 6
	return true


## Pure: the prime factors of n with multiplicity, smallest first (n ≥ 2). 91 → [7, 13]; 12 → [2, 2, 3].
static func factors(n: int) -> Array:
	var out: Array = []
	var m := n
	var d := 2
	while d * d <= m:
		while m % d == 0:
			out.append(d)
			m /= d
		d += 1 if d == 2 else 2
	if m > 1:
		out.append(m)
	return out


## Pure: the first `count` Motzkin numbers (M0 = M1 = 1; (n+2)·M(n) = (2n+1)·M(n−1) + 3(n−1)·M(n−2)).
static func motzkin(count: int) -> Array:
	var out: Array = [1, 1]
	for n in range(2, count):
		out.append(((2 * n + 1) * int(out[n - 1]) + 3 * (n - 1) * int(out[n - 2])) / (n + 2))
	return out.slice(0, count)


static func multiplier_of(c: int) -> int:
	return mini(9, 1 + c / 4)


func multiplier() -> int:
	return multiplier_of(combo)


## The largest number this level rains (grows with the level).
func max_n() -> int:
	return mini(30 + (level - 1) * 40, 999)


func fall_speed() -> float:
	return minf(26.0 + (level - 1) * 6.0, 92.0)


func spawn_every() -> float:
	return maxf(0.5, 1.6 - (level - 1) * 0.12)


func _reset() -> void:
	_gen += 1
	sieve_x = 160.0
	blocks.clear()
	shards.clear()
	bolts.clear()
	popups.clear()
	combo = 0
	level = 1
	sieved = 0
	spawn_t = 0.8
	cooldown = 0.0
	flash = 0.0
	last_event = ""
	_ai_target = 160.0


## A number for the rain: about half primes, the rest composites, a Motzkin prime now and then.
func _pick_number() -> Dictionary:
	var hi := max_n()
	var n := 0
	var roll := rng.randi_range(0, 99)
	if roll < 4:
		var choices := [2] if level < 3 else ([2, 127] if level < 6 else MOTZKIN_PRIMES)
		n = int(choices[rng.randi_range(0, choices.size() - 1)])
	elif roll < 50:
		n = rng.randi_range(2, hi)
		while not is_prime(n):
			n += 1
	else:
		n = rng.randi_range(4, hi)
		while is_prime(n):
			n += 1
	return {"n": n, "prime": is_prime(n), "motzkin": MOTZKIN_PRIMES.has(n)}


func _spawn() -> void:
	var pick := _pick_number()
	var w := 12.0 + str(pick["n"]).length() * 7.0
	var x := rng.randf_range(16.0 + w * 0.5, 304.0 - w * 0.5)
	pick["x"] = x
	pick["y"] = 16.0
	pick["w"] = w
	blocks.append(pick)


func _tick(dt: float) -> void:
	var gen := _gen
	cooldown = maxf(0.0, cooldown - dt)
	flash = maxf(0.0, flash - dt)
	var dir := 0.0
	if held & IN_LEFT:
		dir -= 1.0
	if held & IN_RIGHT:
		dir += 1.0
	sieve_x = clampf(sieve_x + dir * SIEVE_SPEED * dt, 18.0, 302.0)
	if pressed & IN_FIRE or (held & IN_FIRE and cooldown <= 0.0):
		if cooldown <= 0.0 and bolts.size() < MAX_BOLTS:
			bolts.append(Vector2(sieve_x, FLOOR_Y - 8.0))
			cooldown = BOLT_COOLDOWN
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = spawn_every()
		_spawn()
	# Bolts fly up and break what they meet.
	for i in range(bolts.size() - 1, -1, -1):
		var b: Vector2 = bolts[i]
		b.y -= BOLT_SPEED * dt
		bolts[i] = b
		if b.y < 10.0:
			bolts.remove_at(i)
			continue
		for j in range(blocks.size() - 1, -1, -1):
			var bl: Dictionary = blocks[j]
			if absf(b.x - float(bl["x"])) <= float(bl["w"]) * 0.5 and absf(b.y - float(bl["y"])) <= BLOCK_H * 0.5 + 3.0:
				bolts.remove_at(i)
				_shot(j)
				break
		if gen != _gen or not (playing or attract_mode):
			return
	# The rain.
	var fall := fall_speed()
	for j in range(blocks.size() - 1, -1, -1):
		var bl: Dictionary = blocks[j]
		bl["y"] = float(bl["y"]) + fall * dt
		if float(bl["y"]) >= FLOOR_Y - BLOCK_H * 0.5:
			blocks.remove_at(j)
			_landed(bl)
			if gen != _gen or not (playing or attract_mode):
				return
	for j in range(shards.size() - 1, -1, -1):
		var s: Dictionary = shards[j]
		s["y"] = float(s["y"]) + SHARD_FALL * dt
		s["x"] = clampf(float(s["x"]) + float(s["vx"]) * dt, 8.0, 312.0)
		if float(s["y"]) >= FLOOR_Y - 4.0:
			shards.remove_at(j)
			if absf(float(s["x"]) - sieve_x) <= SIEVE_W * 0.5 + 4.0:
				var gain := int(s["n"]) * multiplier()
				score += gain
				combo += 1
				_popup(Vector2(float(s["x"]), FLOOR_Y - 14.0), "+%d" % gain, GOLD)
	for j in range(popups.size() - 1, -1, -1):
		var p: Dictionary = popups[j]
		p["life"] = float(p["life"]) - dt
		p["p"] = (p["p"] as Vector2) + Vector2(0, -18.0 * dt)
		if float(p["life"]) <= 0.0:
			popups.remove_at(j)


## A bolt hit block j: a composite shatters into its factors; a prime costs a life.
func _shot(j: int) -> void:
	var bl: Dictionary = blocks[j]
	blocks.remove_at(j)
	var n := int(bl["n"])
	if bool(bl["prime"]):
		combo = 0
		last_event = "PRIME SHOT %d" % n
		flash = 0.4
		flash_c = MAGENTA
		_popup(Vector2(float(bl["x"]), float(bl["y"])), "%d IS PRIME" % n, MAGENTA)
		_resolved()
		lose_life()
		return
	var fs := factors(n)
	var parts := PackedStringArray()
	for f in fs:
		parts.append(str(f))
	last_event = "%d = %s" % [n, " × ".join(parts)]
	score += n / 2 * multiplier()
	_popup(Vector2(float(bl["x"]), float(bl["y"])), last_event, ICE)
	var k := 0
	for f in fs:
		if k >= 5:
			break
		shards.append({"x": float(bl["x"]), "y": float(bl["y"]), "n": int(f), "vx": (k - (fs.size() - 1) * 0.5) * 26.0})
		k += 1
	_resolved()


## A number reached the floor: on the sieve it is caught, else it passes.
func _landed(bl: Dictionary) -> void:
	var n := int(bl["n"])
	var on_sieve := absf(float(bl["x"]) - sieve_x) <= (SIEVE_W + float(bl["w"])) * 0.5
	if bool(bl["prime"]):
		var gain := n * (2 if on_sieve else 1)
		if bool(bl["motzkin"]) and on_sieve:
			gain += MOTZKIN_BONUS
			flash = 0.5
			flash_c = GOLD
		gain *= multiplier()
		score += gain
		combo += 1
		last_event = ("MOTZKIN %d" if bool(bl["motzkin"]) and on_sieve else ("CAUGHT %d" if on_sieve else "BANKED %d")) % n
		_popup(Vector2(float(bl["x"]), FLOOR_Y - 14.0), "+%d" % gain, GOLD if bool(bl["motzkin"]) else ICE)
		_resolved()
		return
	combo = 0
	last_event = ("CRUSHED BY %d" if on_sieve else "LEAK %d") % n
	flash = 0.4
	flash_c = MAGENTA
	_popup(Vector2(float(bl["x"]), FLOOR_Y - 14.0), "%d LEAKS" % n, MAGENTA)
	_resolved()
	lose_life()


func _resolved() -> void:
	sieved += 1
	if sieved >= PER_LEVEL:
		sieved = 0
		level += 1


func _popup(p: Vector2, s: String, c: Color) -> void:
	if popups.size() >= 8:
		popups.pop_front()
	popups.append({"p": p, "s": s, "c": c, "life": 0.9})


## The demo: go under the lowest composite and shoot it; stand clear of composites about to land.
func _demo_input() -> int:
	var target := -1.0
	var lowest := -1.0
	for bl in blocks:
		if not bool(bl["prime"]) and float(bl["y"]) > lowest:
			lowest = float(bl["y"])
			target = float(bl["x"])
	if target < 0.0:
		for s in shards:
			target = float(s["x"])
	if target >= 0.0:
		_ai_target = target + ai_rng.randf_range(-3.0, 3.0)
	var bits := 0
	if sieve_x < _ai_target - 3.0:
		bits |= IN_RIGHT
	elif sieve_x > _ai_target + 3.0:
		bits |= IN_LEFT
	if lowest >= 0.0 and absf(sieve_x - target) < 8.0 and int(t * 10.0) % 3 == 0:
		bits |= IN_FIRE
	return bits


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw_game() -> void:
	# The sieve's mesh in the background: faint columns.
	for i in 9:
		var x := 32.0 * (i + 1)
		draw_line(Vector2(x, 18), Vector2(x, FLOOR_Y), Color(ICE, 0.05), 1.0)
	glow_line(Vector2(8, FLOOR_Y + 2.0), Vector2(312, FLOOR_Y + 2.0), Color(ICE, 0.6), 1.0)
	text_centered(FLOOR_Y + 14.0, "QING", 7, DIM)
	var font := ThemeDB.fallback_font
	for bl in blocks:
		var c: Color = GOLD if bool(bl["motzkin"]) else (ICE if bool(bl["prime"]) else MAGENTA)
		var r := Rect2(float(bl["x"]) - float(bl["w"]) * 0.5, float(bl["y"]) - BLOCK_H * 0.5, float(bl["w"]), BLOCK_H)
		draw_rect(r, Color(c, 0.14))
		draw_rect(r, c, false, 1.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 11.0), str(bl["n"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, INK)
	for s in shards:
		var p := Vector2(float(s["x"]), float(s["y"]))
		_diamond(p, 5.0, Color(GOLD, 0.8))
		draw_string(font, p + Vector2(7, 3), str(s["n"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, GOLD)
	for b in bolts:
		glow_line(b, b + Vector2(0, 9), ICE, 1.5)
	# The sieve: a comb with the gun in the middle.
	var sx := sieve_x
	glow_poly(PackedVector2Array([Vector2(sx - SIEVE_W * 0.5, FLOOR_Y), Vector2(sx + SIEVE_W * 0.5, FLOOR_Y),
		Vector2(sx + 6.0, FLOOR_Y - 7.0), Vector2(sx - 6.0, FLOOR_Y - 7.0)]), ICE, 1.0)
	draw_line(Vector2(sx, FLOOR_Y - 7.0), Vector2(sx, FLOOR_Y - 12.0), ICE, 2.0)
	for p in popups:
		var a := clampf(float(p["life"]) / 0.4, 0.0, 1.0)
		draw_string(font, (p["p"] as Vector2) - Vector2(40, 0), String(p["s"]), HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color(p["c"], a))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color(flash_c, flash * 0.25))


func _draw_hud() -> void:
	super._draw_hud()
	text(Vector2(250, 30), "LEVEL %d" % level, 8, ICE)
	if multiplier() > 1:
		text(Vector2(250, 42), "x%d" % multiplier(), 9, GOLD)
