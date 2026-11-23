extends ArcadeGame
## Entropy Drift: steer a probe through a scrolling field of entropy shards.
##
## Your probe's Fornax charge drains all the time (faster as the field speeds up). Gold Fornax motes
## refill it; a run of motes without a hit raises the multiplier. Fire spends charge on a pulse that
## shatters nearby shards. Every so often an Eris front (a wall of shards with one gap) crosses the
## field, with a mote in the gap. A shard hit or an empty charge costs one of three lives.

const TOP := 20.0  # playfield top (the HUD is above)
const BOTTOM := 236.0
const PROBE_R := 5.0
const PROBE_MIN_X := 18.0
const PROBE_MAX_X := 150.0
const ACCEL := 900.0
const MAX_V := 150.0
const DRAG := 5.0
const PULSE_COST := 22.0
const PULSE_R := 58.0
const PULSE_TIME := 0.32
const MOTE_CHARGE := 14.0
const DRAIN := 3.0  # charge per second, plus a share of the speed
const INVULN := 2.0
const MAX_SHARDS := 48
const MAX_SPARKS := 90
const TRAIL := 14

var probe := Vector2(60, 128)
var vel := Vector2.ZERO
var charge := 100.0
var speed := 70.0
var dist := 0.0
var bonus := 0
var streak := 0
var invuln := 0.0
var pulse_t := -1.0
var pulse_at := Vector2.ZERO
var shards: Array = []  # {p, k, vy, r, rot, spin, shape}
var motes: Array = []  # {p, ph}
var sparks: Array = []  # {p, v, life, c}
var trail := PackedVector2Array()
var spawn_shard := 0.0
var spawn_mote := 0.0
var next_front := 16.0
var fronts := 0
var grid_off := 0.0
var flash := 0.0
var epoch := 1
var _ai_fire := false


func title() -> String:
	return "Entropy Drift"


func blurb() -> String:
	return "Steer the probe, grab gold Fornax motes, dodge shards. Fire: pulse."


func multiplier() -> int:
	return 1 + int(mini(streak, 20) / 5.0)


func _reset() -> void:
	probe = Vector2(60, 128)
	vel = Vector2.ZERO
	charge = 100.0
	speed = 70.0
	dist = 0.0
	bonus = 0
	streak = 0
	invuln = 1.0
	pulse_t = -1.0
	shards.clear()
	motes.clear()
	sparks.clear()
	trail.clear()
	spawn_shard = 1.2
	spawn_mote = 0.4
	next_front = 16.0
	fronts = 0
	grid_off = 0.0
	flash = 0.0
	epoch = 1


func _tick(dt: float) -> void:
	epoch = 1 + int(t / 20.0)
	speed = minf(70.0 + t * 2.4, 260.0)
	grid_off = fmod(grid_off + speed * dt * 0.5, 40.0)
	invuln = maxf(0.0, invuln - dt)
	flash = maxf(0.0, flash - dt)

	# The probe.
	var acc := Vector2.ZERO
	if held & IN_LEFT:
		acc.x -= 1.0
	if held & IN_RIGHT:
		acc.x += 1.0
	if held & IN_UP:
		acc.y -= 1.0
	if held & IN_DOWN:
		acc.y += 1.0
	vel += acc * ACCEL * dt
	vel -= vel * minf(1.0, DRAG * dt)
	vel = vel.limit_length(MAX_V)
	probe += vel * dt
	if probe.x < PROBE_MIN_X or probe.x > PROBE_MAX_X:
		probe.x = clampf(probe.x, PROBE_MIN_X, PROBE_MAX_X)
		vel.x = 0.0
	if probe.y < TOP + PROBE_R or probe.y > BOTTOM - PROBE_R:
		probe.y = clampf(probe.y, TOP + PROBE_R, BOTTOM - PROBE_R)
		vel.y = 0.0
	for i in trail.size():
		trail[i] = trail[i] - Vector2(speed * dt, 0.0)
	trail.append(probe)
	if trail.size() > TRAIL:
		trail.remove_at(0)

	charge -= (DRAIN + speed * 0.008) * dt

	# The pulse.
	if pressed & IN_FIRE and pulse_t < 0.0 and charge >= PULSE_COST:
		charge -= PULSE_COST
		pulse_t = 0.0
		pulse_at = probe
	if pulse_t >= 0.0:
		pulse_t += dt
		var radius := PULSE_R * minf(1.0, pulse_t / PULSE_TIME)
		for i in range(shards.size() - 1, -1, -1):
			var s: Dictionary = shards[i]
			if s.p.distance_to(pulse_at) < radius + s.r:
				_shatter(i)
		if pulse_t > PULSE_TIME:
			pulse_t = -1.0

	_spawn(dt)

	# The field moves.
	for i in range(shards.size() - 1, -1, -1):
		var s: Dictionary = shards[i]
		s.p.x -= speed * s.k * dt
		s.p.y += s.vy * dt
		if s.p.y < TOP + s.r or s.p.y > BOTTOM - s.r:
			s.vy = -s.vy
			s.p.y = clampf(s.p.y, TOP + s.r, BOTTOM - s.r)
		s.rot += s.spin * dt
		if s.p.x < -24.0:
			shards.remove_at(i)
	for i in range(motes.size() - 1, -1, -1):
		var m: Dictionary = motes[i]
		m.p.x -= speed * dt
		m.ph += dt * 5.0
		if m.p.x < -10.0:
			motes.remove_at(i)
			streak = 0  # a mote let go breaks the run
	for i in range(sparks.size() - 1, -1, -1):
		var sp: Dictionary = sparks[i]
		sp.p += sp.v * dt
		sp.life -= dt
		if sp.life <= 0.0:
			sparks.remove_at(i)

	dist += speed * dt * 0.1
	score = int(dist) + bonus

	# Collisions.
	for i in range(motes.size() - 1, -1, -1):
		var m: Dictionary = motes[i]
		if m.p.distance_to(probe) < PROBE_R + 7.0:
			motes.remove_at(i)
			streak += 1
			charge = minf(100.0, charge + MOTE_CHARGE)
			bonus += 25 * multiplier()
			score = int(dist) + bonus
			_burst(m.p, GOLD, 6)
	if invuln <= 0.0:
		for s in shards:
			if s.p.distance_to(probe) < PROBE_R + s.r * 0.8:
				_hit()
				return
	if charge <= 0.0:
		_hit()


func _spawn(dt: float) -> void:
	spawn_shard -= dt
	if spawn_shard <= 0.0:
		spawn_shard = rng.randf_range(0.45, 1.0) * clampf(1.25 - t / 80.0, 0.22, 1.0)
		var big := minf(epoch * 0.6, 4.0)
		_add_shard(Vector2(340.0, rng.randf_range(TOP + 10.0, BOTTOM - 10.0)), rng.randf_range(5.0, 11.0 + big), rng.randf_range(0.8, 1.35), rng.randf_range(-40.0, 40.0) * minf(1.0, t / 60.0 + 0.2))
	spawn_mote -= dt
	if spawn_mote <= 0.0:
		spawn_mote = rng.randf_range(0.9, 1.8)
		var y := rng.randf_range(TOP + 14.0, BOTTOM - 14.0)
		if rng.randf() < 0.3:
			# A Fornax seam: a short arc of motes.
			var dy := rng.randf_range(-14.0, 14.0)
			for j in 4:
				var p := Vector2(330.0 + j * 18.0, clampf(y + dy * j, TOP + 8.0, BOTTOM - 8.0))
				motes.append({"p": p, "ph": j * 0.7})
		else:
			motes.append({"p": Vector2(330.0, y), "ph": 0.0})
	if t >= next_front:
		fronts += 1
		next_front += maxf(10.0, 18.0 - fronts)
		var gap := maxf(46.0, 86.0 - fronts * 4.0)
		var c := rng.randf_range(TOP + gap * 0.5 + 6.0, BOTTOM - gap * 0.5 - 6.0)
		var y := TOP + 6.0
		while y < BOTTOM:
			if absf(y - c) > gap * 0.5:
				_add_shard(Vector2(344.0, y), 7.0, 1.0, 0.0)
			y += 15.0
		motes.append({"p": Vector2(344.0, c), "ph": 0.0})


func _add_shard(p: Vector2, r: float, k: float, vy: float) -> void:
	if shards.size() >= MAX_SHARDS:
		return
	var n := rng.randi_range(3, 5)
	var shape := PackedVector2Array()
	for j in n:
		var a := TAU * (j + rng.randf_range(-0.25, 0.25)) / n
		shape.append(Vector2(cos(a), sin(a)) * r * rng.randf_range(0.6, 1.0))
	shards.append({"p": p, "k": k, "vy": vy, "r": r, "rot": rng.randf() * TAU, "spin": rng.randf_range(-3.0, 3.0), "shape": shape})


func _shatter(i: int) -> void:
	var s: Dictionary = shards[i]
	shards.remove_at(i)
	bonus += 10 * multiplier()
	score = int(dist) + bonus
	_burst(s.p, MAGENTA, 5)


func _burst(p: Vector2, c: Color, n: int) -> void:
	for j in n:
		if sparks.size() >= MAX_SPARKS:
			return
		var a := TAU * j / n + rng.randf() * 0.6
		sparks.append({"p": p, "v": Vector2(cos(a), sin(a)) * rng.randf_range(40.0, 110.0), "life": rng.randf_range(0.25, 0.5), "c": c})


func _hit() -> void:
	_burst(probe, MAGENTA, 12)
	_burst(probe, ICE, 6)
	streak = 0
	flash = 0.35
	if lose_life():
		return
	invuln = INVULN
	charge = maxf(charge, 60.0)
	for i in range(shards.size() - 1, -1, -1):
		if shards[i].p.distance_to(probe) < 60.0:
			shards.remove_at(i)


func _demo_input() -> int:
	var bits := 0
	var target := Vector2(64.0, 128.0)
	var best_dx := 1e9
	for m in motes:
		var dx: float = m.p.x - probe.x
		if dx > -4.0 and dx < best_dx and dx < 220.0:
			best_dx = dx
			target.y = m.p.y
	var fire := false
	for s in shards:
		var dx: float = s.p.x - probe.x
		if dx > -12.0 and dx < 70.0 and absf(s.p.y - probe.y) < s.r + 16.0:
			target.y = probe.y + (26.0 if s.p.y < probe.y else -26.0)
			if dx < 34.0 and charge > 40.0:
				fire = true
	target.y += ai_rng.randf_range(-3.0, 3.0)
	if target.y < probe.y - 4.0:
		bits |= IN_UP
	elif target.y > probe.y + 4.0:
		bits |= IN_DOWN
	if probe.x < target.x - 6.0:
		bits |= IN_RIGHT
	elif probe.x > target.x + 6.0:
		bits |= IN_LEFT
	_ai_fire = fire and not _ai_fire  # tap, don't hold
	if _ai_fire:
		bits |= IN_FIRE
	return bits


# ── drawing ──────────────────────────────────────────────────────────────────


func _draw_game() -> void:
	# The field: a faint lattice scrolling left.
	var line_c := Color(ICE, 0.06)
	var x := 40.0 - grid_off
	while x < SIZE.x:
		draw_line(Vector2(x, TOP), Vector2(x, BOTTOM), line_c, 1.0)
		x += 40.0
	var y := TOP + 18.0
	while y < BOTTOM:
		draw_line(Vector2(0, y), Vector2(SIZE.x, y), line_c, 1.0)
		y += 40.0
	draw_line(Vector2(0, TOP), Vector2(SIZE.x, TOP), Color(ICE, 0.25), 1.0)
	draw_line(Vector2(0, BOTTOM), Vector2(SIZE.x, BOTTOM), Color(ICE, 0.25), 1.0)

	for m in motes:
		var pulse := 0.5 + 0.5 * sin(m.ph)
		draw_arc(m.p, 4.5 + pulse * 1.5, 0.0, TAU, 12, Color(GOLD, 0.35 + 0.3 * pulse), 1.0, true)
		draw_circle(m.p, 2.2, GOLD)
	for s in shards:
		var pts := PackedVector2Array()
		var rot := Transform2D(s.rot, s.p)
		for q in s.shape:
			pts.append(rot * q)
		draw_colored_polygon(pts, Color(MAGENTA, 0.16))
		glow_poly(pts, MAGENTA, 1.0)
	for sp in sparks:
		draw_line(sp.p, sp.p - sp.v * 0.04, Color(sp.c, clampf(sp.life * 2.5, 0.0, 1.0)), 1.0)

	if trail.size() > 1:
		for i in range(1, trail.size()):
			var a := float(i) / trail.size()
			draw_line(trail[i - 1] - Vector2(5, 0), trail[i] - Vector2(5, 0), Color(ICE, a * 0.4), 1.0)
	if pulse_t >= 0.0:
		var r := PULSE_R * minf(1.0, pulse_t / PULSE_TIME)
		draw_arc(pulse_at, r, 0.0, TAU, 40, Color(ICE, 1.0 - pulse_t / PULSE_TIME), 1.5, true)
	if lives > 0 and (invuln <= 0.0 or int(t * 12.0) % 2 == 0):
		var p := probe
		var hull := PackedVector2Array([p + Vector2(8, 0), p + Vector2(-5, -5), p + Vector2(-2, 0), p + Vector2(-5, 5)])
		draw_colored_polygon(hull, Color(ICE, 0.2))
		glow_poly(hull, ICE, 1.2)
		if held & (IN_LEFT | IN_RIGHT | IN_UP | IN_DOWN):
			draw_line(p + Vector2(-3, 0), p + Vector2(-8 - (int(t * 30.0) % 3), 0), GOLD, 1.0)
	if flash > 0.0 and not over:
		draw_rect(Rect2(0, TOP, SIZE.x, BOTTOM - TOP), Color(MAGENTA, flash * 0.3))


func _draw_hud() -> void:
	super._draw_hud()
	# Fornax charge.
	var r := Rect2(112, 5, 96, 7)
	draw_rect(r, Color(GOLD, 0.12))
	var low := charge < 25.0 and int(t * 6.0) % 2 == 0
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(charge / 100.0, 0.0, 1.0), r.size.y)), MAGENTA if low else GOLD)
	draw_rect(r, Color(GOLD, 0.6), false, 1.0)
	text(Vector2(112, 19), "FORNAX", 7, Color(GOLD, 0.8))
	text(Vector2(80, 12), "x%d" % multiplier(), 9, GOLD if multiplier() > 1 else DIM)
	text(Vector2(214, 12), "EPOCH %d" % epoch, 8, MUTED)
