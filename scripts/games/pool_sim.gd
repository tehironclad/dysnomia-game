class_name PoolSim
extends RefCounted
## Eight-ball on a 9-foot table in integer maths, so every machine replays a
## shot (a chat line: aim vector + power) to exactly the same result. Units:
## micrometres for position, micrometres per tick for velocity; a tick is
## 1/480 s. No floats touch the state.
##
## Table: x along the length [0, W], y across [0, H]; pockets at the four
## corners and the middle of each long rail. Ball 0 is the cue ball, 1–7
## solids, 8 the eight, 9–15 stripes.

const W := 2540000
const H := 1270000
const R := 28600  # ball radius
const TICK_HZ := 480
const MAX_TICKS := 480 * 25
const DECEL := 2  # µm/tick² (≈ 0.46 m/s² on the cloth)
const VMAX := 10400  # µm/tick at power 1000 (≈ 5 m/s)
const BALL_REST := 95  # % kept along the line of centres
const RAIL_REST := 75  # % kept off a cushion
const CORNER_CAPTURE := 62000
const SIDE_CAPTURE := 46000
const RACK := [[1], [9, 2], [10, 8, 3], [11, 7, 14, 4], [5, 13, 15, 6, 12]]

var px := PackedInt64Array()
var py := PackedInt64Array()
var vx := PackedInt64Array()
var vy := PackedInt64Array()
var down := PackedByteArray()  # 1 = pocketed


static func pockets() -> Array:
	return [Vector2i(0, 0), Vector2i(W / 2, 0), Vector2i(W, 0), Vector2i(0, H), Vector2i(W / 2, H), Vector2i(W, H)]


static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var r := int(sqrt(float(n)))
	while r * r > n:
		r -= 1
	while (r + 1) * (r + 1) <= n:
		r += 1
	return r


func _init() -> void:
	px.resize(16)
	py.resize(16)
	vx.resize(16)
	vy.resize(16)
	down.resize(16)
	rack()


## The opening position: cue ball on the head spot, the triangle on the foot spot.
func rack() -> void:
	for i in 16:
		vx[i] = 0
		vy[i] = 0
		down[i] = 0
	px[0] = W / 4
	py[0] = H / 2
	var step := 2 * R + 20
	var row_dx := isqrt(3 * step * step / 4)
	for k in RACK.size():
		var row: Array = RACK[k]
		for j in row.size():
			var b: int = row[j]
			px[b] = W * 3 / 4 + k * row_dx
			py[b] = H / 2 + (2 * j - k) * step / 2


func on_table(b: int) -> bool:
	return down[b] == 0


## Puts the cue ball back on the head spot (moved toward the head rail until clear).
func spot_cue() -> void:
	down[0] = 0
	vx[0] = 0
	vy[0] = 0
	var x := W / 4
	while x > R and _occupied(x, H / 2):
		x -= R
	px[0] = x
	py[0] = H / 2


func _occupied(x: int, y: int) -> bool:
	for b in range(1, 16):
		if down[b] == 0:
			var dx := px[b] - x
			var dy := py[b] - y
			if dx * dx + dy * dy < 4 * R * R:
				return true
	return false


## Strikes the cue ball along (dx, dy) with power 1–1000 and runs the table
## until everything stops. Returns {first_contact (-1 if none), pocketed:
## [ball ids in order], ticks, frames?: [PackedInt64Array of x,y per ball]
## every `frame_every` ticks when asked}.
func shoot(dx: int, dy: int, power: int, frame_every: int = 0) -> Dictionary:
	power = clampi(power, 1, 1000)
	var mag := isqrt(dx * dx + dy * dy)
	var out := {"first_contact": -1, "pocketed": [], "ticks": 0}
	var frames: Array = []
	if mag == 0 or down[0] == 1:
		return out
	var speed := VMAX * power / 1000
	vx[0] = dx * speed / mag
	vy[0] = dy * speed / mag
	var caps := [CORNER_CAPTURE, SIDE_CAPTURE, CORNER_CAPTURE, CORNER_CAPTURE, SIDE_CAPTURE, CORNER_CAPTURE]
	var pk := pockets()
	var t := 0
	while t < MAX_TICKS:
		t += 1
		var moving := false
		for i in 16:
			if down[i] == 0 and (vx[i] != 0 or vy[i] != 0):
				moving = true
				px[i] += vx[i]
				py[i] += vy[i]
		if not moving:
			break
		# Pockets first, so a ball running into the jaws drops instead of bouncing.
		for i in 16:
			if down[i] == 1 or (vx[i] == 0 and vy[i] == 0):
				continue
			for p in 6:
				var q: Vector2i = pk[p]
				var ex := px[i] - q.x
				var ey := py[i] - q.y
				var cap: int = caps[p]
				if ex * ex + ey * ey < cap * cap:
					down[i] = 1
					vx[i] = 0
					vy[i] = 0
					out["pocketed"].append(i)
					break
		# Cushions
		for i in 16:
			if down[i] == 1:
				continue
			if px[i] < R and vx[i] < 0:
				px[i] = 2 * R - px[i]
				vx[i] = -vx[i] * RAIL_REST / 100
			elif px[i] > W - R and vx[i] > 0:
				px[i] = 2 * (W - R) - px[i]
				vx[i] = -vx[i] * RAIL_REST / 100
			if py[i] < R and vy[i] < 0:
				py[i] = 2 * R - py[i]
				vy[i] = -vy[i] * RAIL_REST / 100
			elif py[i] > H - R and vy[i] > 0:
				py[i] = 2 * (H - R) - py[i]
				vy[i] = -vy[i] * RAIL_REST / 100
		# Ball on ball (equal masses: exchange along the line of centres)
		for i in 16:
			if down[i] == 1:
				continue
			for j in range(i + 1, 16):
				if down[j] == 1:
					continue
				if vx[i] == 0 and vy[i] == 0 and vx[j] == 0 and vy[j] == 0:
					continue
				var nx := px[j] - px[i]
				var ny := py[j] - py[i]
				var d2 := nx * nx + ny * ny
				if d2 >= 4 * R * R:
					continue
				if d2 == 0:
					nx = 1
					d2 = 1
				var rel := (vx[i] - vx[j]) * nx + (vy[i] - vy[j]) * ny
				if rel > 0:
					var k := rel * BALL_REST / 100
					vx[i] -= nx * k / d2
					vy[i] -= ny * k / d2
					vx[j] += nx * k / d2
					vy[j] += ny * k / d2
					if out["first_contact"] == -1 and (i == 0 or j == 0):
						out["first_contact"] = j if i == 0 else i
				var d := isqrt(d2)
				var push := (2 * R - d) / 2 + 1
				px[i] -= nx * push / maxi(d, 1)
				py[i] -= ny * push / maxi(d, 1)
				px[j] += nx * push / maxi(d, 1)
				py[j] += ny * push / maxi(d, 1)
		# Cloth
		for i in 16:
			if vx[i] == 0 and vy[i] == 0:
				continue
			var s := isqrt(vx[i] * vx[i] + vy[i] * vy[i])
			if s <= DECEL:
				vx[i] = 0
				vy[i] = 0
			else:
				vx[i] = vx[i] * (s - DECEL) / s
				vy[i] = vy[i] * (s - DECEL) / s
		if frame_every > 0 and t % frame_every == 0:
			frames.append(snapshot())
	for i in 16:  # anything still rolling at the cap stops where it is
		vx[i] = 0
		vy[i] = 0
	out["ticks"] = t
	if frame_every > 0:
		frames.append(snapshot())
		out["frames"] = frames
	return out


## x, y and pocketed for each ball: [x0, y0, down0, x1, …].
func snapshot() -> PackedInt64Array:
	var s := PackedInt64Array()
	s.resize(48)
	for i in 16:
		s[i * 3] = px[i]
		s[i * 3 + 1] = py[i]
		s[i * 3 + 2] = down[i]
	return s


func apply_snapshot(s: PackedInt64Array) -> void:
	for i in 16:
		px[i] = s[i * 3]
		py[i] = s[i * 3 + 1]
		down[i] = s[i * 3 + 2]
		vx[i] = 0
		vy[i] = 0


## A digest of the whole table (tests compare replays with it).
func digest() -> String:
	return snapshot().to_byte_array().hex_encode().sha256_text()
