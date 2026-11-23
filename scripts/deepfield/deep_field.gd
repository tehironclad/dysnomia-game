class_name DeepField
extends RefCounted
## The fractal behind every territory and identity: an exact port of the
## Entropy site's lib/deep-field.js (tehironclad/entropy-ai-pulse), checked
## against vectors produced by the real JS (tests/golden/deepfield.json).
##
## "Every image is a real number": a territory's picture is the Julia set of
## z ↦ z^D + c, where c, D, style, rotation and colour come only from its
## Entropy() and its address. An identity uses its Aura (uint160(addr) % P)
## and its wallet address. Same numbers → same picture, here and on the site.
##
## All values are 64-bit floats in Arrays (Vector2/Color would truncate to
## float32): c = [x, y], color = [r, g, b].

const P := Contracts.MOTZKIN_PRIME
const SPREAD := 369  ## PulseChain's chain id
const STYLES := ["glow", "duo", "bands", "ember"]
const CUT_MYTHIC := 416911265256012
const CUT_LEGENDARY := 394373502855546
const CUT_EPIC := 321073793475702
const CUT_RARE := 206402677688564
const BULB2 := [-1.0, 0.0, 0.25]
const BULB3 := [-0.1225611668766536, 0.7448617666197442, 0.0945]
const M32 := 0xFFFFFFFF


# --- Hashing (bit-exact with the JS) ------------------------------------------------

## (a * b) mod 2^32 for a, b < 2^32, without overflowing int64.
static func imul32(a: int, b: int) -> int:
	var lo := (a * (b & 0xFFFF)) & M32
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & M32


## FNV-1a over the BigInt's lower-case hex string, then a murmur finalizer.
static func mix(b: PackedInt64Array, salt: int) -> int:
	var h := (2166136261 ^ salt) & M32
	for ch in BigInt.to_hex(b):
		h ^= ch.unicode_at(0)
		h = imul32(h, 16777619)
	h ^= h >> 15
	h = imul32(h, 2246822507)
	h ^= h >> 13
	h = imul32(h, 3266489909)
	h ^= h >> 16
	return h & M32


static func unit(b: PackedInt64Array, salt: int) -> float:
	return float(mix(b, salt)) / 4294967296.0


# --- Inputs -----------------------------------------------------------------------

static func tier_of(n: PackedInt64Array) -> String:
	if not BigInt.fits_int(n):
		return "Mythic"
	var x := BigInt.to_int(n)
	if x >= CUT_MYTHIC:
		return "Mythic"
	if x >= CUT_LEGENDARY:
		return "Legendary"
	if x >= CUT_EPIC:
		return "Epic"
	if x >= CUT_RARE:
		return "Rare"
	return "Common"


## The contract's own Aura: uint160(address) % MotzkinPrime, as a decimal string.
static func aura(address: String) -> String:
	return str(BigInt.mod_int(BigInt.from_hex(address), P))


static func color_of(t: float) -> Array:
	return [0.55 + 0.45 * cos(TAU * (t + 0.00)), 0.55 + 0.45 * cos(TAU * (t + 0.33)), 0.55 + 0.45 * cos(TAU * (t + 0.67))]


static func to_color(rgb: Array, alpha: float = 1.0) -> Color:
	return Color(rgb[0], rgb[1], rgb[2], alpha)


static func _gcd(x: int, y: int) -> int:
	while y != 0:
		var t := y
		y = x % y
		x = t
	return x


static func _coprimes(q: int) -> Array:
	var ps: Array = []
	for k in range(1, q):
		if _gcd(k, q) == 1:
			ps.append(k)
	return ps


static func _cpow(x: float, y: float, d: int) -> Array:
	var rx := 1.0
	var ry := 0.0
	for k in d:
		var t := rx * x - ry * y
		ry = rx * y + ry * x
		rx = t
	return [rx, ry]


## c on the boundary of the degree-d Multibrot main body at multiplier ρ·e^{iφ}.
static func _multibrot_c(d: int, phi: float, rho: float) -> Array:
	var lr := rho * cos(phi) / d
	var li := rho * sin(phi) / d
	var md := pow(sqrt(lr * lr + li * li), 1.0 / (d - 1))
	var ang := atan2(li, lr) / (d - 1)
	var z := [md * cos(ang), md * sin(ang)]
	var zd := _cpow(z[0], z[1], d)
	return [z[0] - zd[0], z[1] - zd[1]]


static func _escape_radius(c: Array) -> float:
	return (1.0 + sqrt(1.0 + 4.0 * sqrt(c[0] * c[0] + c[1] * c[1]))) / 2.0


# --- params ---------------------------------------------------------------------------

## number: entropy (territory) or Aura (identity), as a decimal string, int or
## BigInt; address: the territory's or wallet's address. Returns everything
## needed to draw it (same keys as the JS).
static func params(number, address: String) -> Dictionary:
	var n := BigInt.coerce(number)
	var a := BigInt.from_hex(address)
	var u := float(BigInt.mod_int(BigInt.mul_small(n, SPREAD), P)) / float(P)
	var pick := mix(a, 1) % 10
	var depth := unit(BigInt.xor(n, a), 2)
	var c: Array
	var family := ""
	var arms := 0
	var turn := 0
	if pick < 6:
		family = "spiral"
		arms = 2 + (mix(n, 5) % 8)
		var ps := _coprimes(arms)
		turn = ps[mix(a, 6) % ps.size()]
		var theta := TAU * (float(turn) / arms + (u - 0.5) * 0.8 / (arms * arms))
		var shrink := 1.0 - (0.008 + 0.11 * depth * depth) / arms
		c = [(0.5 * cos(theta) - 0.25 * cos(2.0 * theta)) * shrink,
			(0.5 * sin(theta) - 0.25 * sin(2.0 * theta)) * shrink]
	else:
		var b: Array = BULB2 if pick < 8 else BULB3
		family = "period-2" if pick < 8 else "period-3"
		var flip := 1.0 if (pick < 8 or (mix(a, 7) & 1) != 0) else -1.0
		var rr: float = b[2] * (0.25 + 0.65 * depth)
		var th := TAU * u
		c = [b[0] + rr * cos(th), flip * b[1] + rr * sin(th)]
	var rotation := TAU * unit(a, 3)
	var hue := unit(BigInt.xor(n, BigInt.shr(a, 7)), 4)
	var frame := 0.8 + 0.4 * unit(BigInt.add(n, a), 11)
	var tier := tier_of(n)
	var power := 2
	var style: String = STYLES[mix(a, 12) % STYLES.size()]
	var roll := unit(BigInt.xor(a, n), 13)
	if tier == "Epic" and roll < 0.5:
		power = 3
	if tier == "Legendary":
		power = 3 if roll < 0.5 else 4
		style = "gilded"
	if tier == "Mythic":
		power = 4 + (mix(n, 14) % 3)
		style = "prism"
	if power > 2:
		family = "star"
		arms = 2 + (mix(n, 15) % 6)
		var ps2 := _coprimes(arms)
		turn = ps2[mix(a, 16) % ps2.size()]
		var phi := TAU * (float(turn) / arms + (u - 0.5) * 0.6 / (arms * arms))
		c = _multibrot_c(power, phi, 0.993 - 0.05 * depth * depth)
	return {
		"c": c, "family": family, "arms": arms, "turn": turn, "depth": depth, "power": power,
		"tier": tier, "style": style, "rotation": rotation, "hue": hue, "color": color_of(hue),
		"color2": color_of(hue + 0.21 + 0.5 * unit(a, 17)),
		"extent": (1.18 if power > 2 else _escape_radius(c) * 0.92) * frame, "frame": frame,
	}


## Params for a Registry territory record.
static func for_territory(q: Dictionary) -> Dictionary:
	return params(String(q["entropy"]), String(q["address"]))


## Params for an identity: Aura in place of entropy, wallet in place of address.
static func for_identity(wallet: String) -> Dictionary:
	return params(aura(wallet), wallet)


# --- Endless dive -------------------------------------------------------------------------

static func _csqrt(x: float, y: float) -> Array:
	var r := sqrt(x * x + y * y)
	var u := sqrt((r + x) / 2.0)
	var v := sqrt(maxf(0.0, (r - x) / 2.0))
	return [u, -v if y < 0.0 else v]


## A repelling periodic point of the Julia set and its multiplier, for a dive
## that loops seamlessly (zoom by mag, turn by arg). null for power > 2.
static func dive_point(p: Dictionary, address: String):
	if int(p.get("power", 2)) != 2:
		return null
	var a := BigInt.from_hex(address)
	var c: Array = p["c"]
	var best = null
	for period in range(2, 6):
		var bits := mix(a, 10 + period)
		var z := [0.3, 0.1]
		for it in 120:
			for j in range(period - 1, -1, -1):
				var s := _csqrt(z[0] - c[0], z[1] - c[1])
				z = [-s[0], -s[1]] if ((bits >> j) & 1) != 0 else s
		var w := [z[0], z[1]]
		var lr := 1.0
		var li := 0.0
		for m in period:
			var dr: float = 2.0 * w[0]
			var di: float = 2.0 * w[1]
			var nr := lr * dr - li * di
			li = lr * di + li * dr
			lr = nr
			w = [w[0] * w[0] - w[1] * w[1] + c[0], 2.0 * w[0] * w[1] + c[1]]
		var ok := sqrt(pow(w[0] - z[0], 2) + pow(w[1] - z[1], 2)) <= 1e-6
		var mag := sqrt(lr * lr + li * li)
		if not ok or not (mag > 1.6):
			continue
		var score := absf(log(mag) - log(6.0)) - 0.4 * absf(sin(atan2(li, lr)))
		if best == null or score < best["score"]:
			best = {"z": z, "mag": mag, "arg": atan2(li, lr), "period": period, "score": score}
	if best == null:
		var s1 := _csqrt(1.0 - 4.0 * c[0], -4.0 * c[1])
		var bz := [(1.0 + s1[0]) / 2.0, s1[1] / 2.0]
		best = {"z": bz, "mag": maxf(1.6, sqrt(4.0 * bz[0] * bz[0] + 4.0 * bz[1] * bz[1])), "arg": atan2(bz[1], bz[0]), "period": 1}
	return best


# --- Plain-words explanation (for the "How is this drawn?" inspector) ------------------

static func describe(p: Dictionary, number_label: String, number: String, address: String) -> String:
	var c: Array = p["c"]
	return "Julia set of z ↦ z^%d + c, c = %.6f %+.6fi\n%s %s × 369 mod 953,467,954,114,363 and address %s\nfamily %s · style %s · rarity %s · rotation %.1f°" % [
		p["power"], c[0], c[1], number_label, number, address, p["family"], p["style"], p["tier"], rad_to_deg(p["rotation"])]


## A point on the Julia set's boundary along `angle` from the origin (by
## bisection on escape). Used as the dive target where dive_point() has none
## (power > 2). Returns [x, y].
static func boundary_point(p: Dictionary, angle: float) -> Array:
	var lo := 0.0
	var hi := float(p["extent"]) * 1.2
	var d := Vector2(cos(angle), sin(angle))
	if JuliaHeightfield.probe(p, d.x * hi, d.y * hi, 96)[0]:
		return [d.x * hi, d.y * hi]
	for i in 40:
		var mid := (lo + hi) * 0.5
		if JuliaHeightfield.probe(p, d.x * mid, d.y * mid, 96)[0]:
			lo = mid
		else:
			hi = mid
	return [d.x * hi, d.y * hi]
