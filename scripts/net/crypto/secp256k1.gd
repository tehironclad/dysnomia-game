class_name Secp256k1
extends RefCounted
## secp256k1 in pure GDScript: enough for Ethereum's ecrecover (the game server
## checks a wallet's personal_sign) and for RFC 6979 signing (scripted test
## wallets). Not constant-time: signing is for throwaway test keys only; a real
## player's key never comes near this code (their browser wallet signs).
##
## Numbers are 10 limbs of 26 bits (PackedInt64Array, little-endian), value
## < 2^260, not necessarily fully reduced. A product (19 limbs of < 2^56) is
## folded with 2^260 ≡ K (mod m): for p, K = 2^36 + 0x3D10; for the group
## order n, K = 16·(2^256 − n). Canonical form (< m) only where compared.
## Big integers never become floats.
##
## Points are Jacobian [X, Y, Z]; [] is the point at infinity.

const MASK := (1 << 26) - 1
const P_HEX := "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
const N_HEX := "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
const GX_HEX := "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
const GY_HEX := "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
const KP_HEX := "1000003d10"  # 2^260 mod p
const KN_HEX := "14551231950b75fc4402da1732fc9bebf0"  # 2^260 mod n

static var P: PackedInt64Array
static var N: PackedInt64Array
static var KP: PackedInt64Array
static var KN: PackedInt64Array
static var P32: PackedInt64Array  # 32·p: added before a subtraction so limbs stay a non-negative total
static var N32: PackedInt64Array
static var G: Array
static var _p_minus_2: PackedByteArray
static var _n_minus_2: PackedByteArray
static var _p_sqrt: PackedByteArray  # (p + 1) / 4
static var _half_n: PackedInt64Array


static func _setup() -> void:
	if not P.is_empty():
		return
	P = from_hex(P_HEX)
	N = from_hex(N_HEX)
	KP = _trim(from_hex(KP_HEX))
	KN = _trim(from_hex(KN_HEX))
	P32 = _shl5(P)
	N32 = _shl5(N)
	G = [from_hex(GX_HEX), from_hex(GY_HEX), one()]
	_p_minus_2 = _bytes_minus_small(P_HEX, 2)
	_n_minus_2 = _bytes_minus_small(N_HEX, 2)
	# (p + 1) / 4: p ≡ 3 (mod 4), so this is p >> 2 plus one
	var p := PackedByteArray(P_HEX.hex_decode())
	var q := PackedByteArray()
	q.resize(32)
	var carry := 0
	for i in 32:
		var v: int = (carry << 8) | p[i]
		q[i] = v >> 2
		carry = v & 3
	var cv := 1
	for i in range(31, -1, -1):
		var v2: int = q[i] + cv
		q[i] = v2 & 0xFF
		cv = v2 >> 8
	_p_sqrt = q
	_half_n = from_bytes(_bytes_half(N_HEX))


static func _bytes_minus_small(hex: String, k: int) -> PackedByteArray:
	var b := PackedByteArray(hex.hex_decode())
	var borrow := k
	for i in range(31, -1, -1):
		var v: int = b[i] - borrow
		borrow = 0
		if v < 0:
			v += 256
			borrow = 1
		b[i] = v
	return b


static func _bytes_half(hex: String) -> PackedByteArray:
	var b := PackedByteArray(hex.hex_decode())
	var carry := 0
	for i in 32:
		var v: int = (carry << 8) | b[i]
		b[i] = v >> 1
		carry = v & 1
	return b


# ── limbs ───────────────────────────────────────────────────────────────────

static func zero() -> PackedInt64Array:
	var z := PackedInt64Array()
	z.resize(10)
	z.fill(0)
	return z


static func one() -> PackedInt64Array:
	var z := zero()
	z[0] = 1
	return z


## Big-endian bytes (any length) → limbs (at least 10).
static func from_bytes(b: PackedByteArray) -> PackedInt64Array:
	var nbits := b.size() * 8
	var nl := maxi(10, (nbits + 25) / 26)
	var out := PackedInt64Array()
	out.resize(nl)
	out.fill(0)
	for k in nbits:
		var byte: int = b[b.size() - 1 - (k >> 3)]
		if (byte >> (k & 7)) & 1:
			out[k / 26] |= 1 << (k % 26)
	return out


static func from_hex(hex: String) -> PackedInt64Array:
	hex = hex.trim_prefix("0x")
	if hex.length() % 2 == 1:
		hex = "0" + hex
	return from_bytes(PackedByteArray(hex.hex_decode()))


## Canonical limbs → 32 big-endian bytes.
static func to_bytes(a: PackedInt64Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(32)
	out.fill(0)
	for k in 256:
		if (a[k / 26] >> (k % 26)) & 1:
			out[31 - (k >> 3)] |= 1 << (k & 7)
	return out


static func _trim(a: PackedInt64Array) -> PackedInt64Array:
	var n := a.size()
	while n > 1 and a[n - 1] == 0:
		n -= 1
	a.resize(n)
	return a


static func _shl5(a: PackedInt64Array) -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(11)
	t.fill(0)
	for i in 10:
		t[i] = a[i] << 5
	return _carry(t)


static func _carry(t: PackedInt64Array) -> PackedInt64Array:
	var c := 0
	for i in t.size():
		var v: int = t[i] + c
		t[i] = v & MASK
		c = v >> 26
	while c != 0:
		t.append(c & MASK)
		c >>= 26
	return t


## Any non-negative limb vector (limbs may be large or negative) → 10 limbs, < 2^260.
static func _reduce(t: PackedInt64Array, k: PackedInt64Array) -> PackedInt64Array:
	var kn := k.size()
	while true:
		_carry(t)
		var n := t.size()
		while n > 10 and t[n - 1] == 0:
			n -= 1
		if n <= 10:
			t.resize(10)
			return t
		var h := n - 10
		var r := PackedInt64Array()
		r.resize(maxi(10, h + kn - 1))
		r.fill(0)
		for i in 10:
			r[i] = t[i]
		for i in h:
			var hi: int = t[10 + i]
			if hi == 0:
				continue
			for j in kn:
				r[i + j] += hi * k[j]
		t = r
	return t


static func mul(a: PackedInt64Array, b: PackedInt64Array, k: PackedInt64Array) -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(19)
	t.fill(0)
	var b0 := b[0]
	var b1 := b[1]
	var b2 := b[2]
	var b3 := b[3]
	var b4 := b[4]
	var b5 := b[5]
	var b6 := b[6]
	var b7 := b[7]
	var b8 := b[8]
	var b9 := b[9]
	for i in 10:
		var ai := a[i]
		if ai == 0:
			continue
		t[i] += ai * b0
		t[i + 1] += ai * b1
		t[i + 2] += ai * b2
		t[i + 3] += ai * b3
		t[i + 4] += ai * b4
		t[i + 5] += ai * b5
		t[i + 6] += ai * b6
		t[i + 7] += ai * b7
		t[i + 8] += ai * b8
		t[i + 9] += ai * b9
	return _reduce(t, k)


static func add(a: PackedInt64Array, b: PackedInt64Array, k: PackedInt64Array) -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(10)
	for i in 10:
		t[i] = a[i] + b[i]
	return _reduce(t, k)


## a − b (mod m), with m32 = 32·m.
static func sub(a: PackedInt64Array, b: PackedInt64Array, k: PackedInt64Array, m32: PackedInt64Array) -> PackedInt64Array:
	var t := m32.duplicate()
	for i in 10:
		t[i] += a[i] - b[i]
	return _reduce(t, k)


static func mul_small(a: PackedInt64Array, s: int, k: PackedInt64Array) -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(10)
	for i in 10:
		t[i] = a[i] * s
	return _reduce(t, k)


static func cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i in range(9, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


## Fully reduced (< m).
static func canon(a: PackedInt64Array, m: PackedInt64Array) -> PackedInt64Array:
	var r := a.duplicate()
	while cmp(r, m) >= 0:
		var borrow := 0
		for i in 10:
			var v: int = r[i] - m[i] - borrow
			borrow = 0
			if v < 0:
				v += 1 << 26
				borrow = 1
			r[i] = v
	return r


static func is_zero_mod(a: PackedInt64Array, m: PackedInt64Array) -> bool:
	var c := canon(a, m)
	for i in 10:
		if c[i] != 0:
			return false
	return true


## a^e (mod m), e as 32 big-endian bytes; 4-bit fixed window.
static func pow_bytes(a: PackedInt64Array, e: PackedByteArray, k: PackedInt64Array) -> PackedInt64Array:
	var table: Array = [one(), a]
	for i in range(2, 16):
		table.append(mul(table[i - 1], a, k))
	var r := one()
	var started := false
	for byte in e:
		for nib in [byte >> 4, byte & 15]:
			if started:
				for _s in 4:
					r = mul(r, r, k)
			if nib != 0:
				r = mul(r, table[nib], k) if started else (table[nib] as PackedInt64Array).duplicate()
				started = true
	return r


# ── field (mod p) ────────────────────────────────────────────────────────────

static func fm(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	return mul(a, b, KP)


static func fsq(a: PackedInt64Array) -> PackedInt64Array:
	return mul(a, a, KP)


static func fadd(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	return add(a, b, KP)


static func fsub(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	return sub(a, b, KP, P32)


static func finv(a: PackedInt64Array) -> PackedInt64Array:
	return pow_bytes(a, _p_minus_2, KP)


# ── points ──────────────────────────────────────────────────────────────────

static func dbl(pt: Array) -> Array:
	if pt.is_empty():
		return []
	var x1: PackedInt64Array = pt[0]
	var y1: PackedInt64Array = pt[1]
	var z1: PackedInt64Array = pt[2]
	var a := fsq(x1)
	var b := fsq(y1)
	var c := fsq(b)
	var d := mul_small(fsub(fsub(fsq(fadd(x1, b)), a), c), 2, KP)
	var e := mul_small(a, 3, KP)
	var f := fsq(e)
	var x3 := fsub(f, mul_small(d, 2, KP))
	var y3 := fsub(fm(e, fsub(d, x3)), mul_small(c, 8, KP))
	var z3 := mul_small(fm(y1, z1), 2, KP)
	return [x3, y3, z3]


static func padd(p1: Array, p2: Array) -> Array:
	if p1.is_empty():
		return p2
	if p2.is_empty():
		return p1
	var z1z1 := fsq(p1[2])
	var z2z2 := fsq(p2[2])
	var u1 := fm(p1[0], z2z2)
	var u2 := fm(p2[0], z1z1)
	var s1 := fm(fm(p1[1], p2[2]), z2z2)
	var s2 := fm(fm(p2[1], p1[2]), z1z1)
	var h := fsub(u2, u1)
	var r := mul_small(fsub(s2, s1), 2, KP)
	if is_zero_mod(h, P):
		if is_zero_mod(r, P):
			return dbl(p1)
		return []
	var i := fsq(mul_small(h, 2, KP))
	var j := fm(h, i)
	var v := fm(u1, i)
	var x3 := fsub(fsub(fsq(r), j), mul_small(v, 2, KP))
	var y3 := fsub(fm(r, fsub(v, x3)), mul_small(fm(s1, j), 2, KP))
	var z3 := fm(fsub(fsub(fsq(fadd(p1[2], p2[2])), z1z1), z2z2), h)
	return [x3, y3, z3]


static func _bit(a: PackedInt64Array, k: int) -> int:
	return (a[k / 26] >> (k % 26)) & 1


## u1·P1 + u2·P2 (Shamir's trick); u1, u2 canonical scalars.
static func mul2(u1: PackedInt64Array, p1: Array, u2: PackedInt64Array, p2: Array) -> Array:
	var t3 := padd(p1, p2)
	var table := [[], p1, p2, t3]
	var q: Array = []
	for k in range(255, -1, -1):
		q = dbl(q)
		var idx := _bit(u1, k) + 2 * _bit(u2, k)
		if idx != 0:
			q = padd(q, table[idx])
	return q


static func scalar_mul(u: PackedInt64Array, pt: Array) -> Array:
	var q: Array = []
	for k in range(255, -1, -1):
		q = dbl(q)
		if _bit(u, k):
			q = padd(q, pt)
	return q


## Jacobian → [x, y] canonical; [] for infinity.
static func to_affine(pt: Array) -> Array:
	if pt.is_empty() or is_zero_mod(pt[2], P):
		return []
	var zi := finv(pt[2])
	var zi2 := fsq(zi)
	return [canon(fm(pt[0], zi2), P), canon(fm(pt[1], fm(zi2, zi)), P)]


# ── ECDSA ───────────────────────────────────────────────────────────────────

## The uncompressed public key (64 bytes X‖Y) that signed `hash` (32 bytes),
## or an empty array if the signature is malformed or recovers nothing.
## recid 0..3 (v − 27 for Ethereum's v = 27/28).
static func recover(hash: PackedByteArray, r_bytes: PackedByteArray, s_bytes: PackedByteArray, recid: int) -> PackedByteArray:
	_setup()
	if hash.size() != 32 or r_bytes.size() != 32 or s_bytes.size() != 32 or recid < 0 or recid > 3:
		return PackedByteArray()
	var r := from_bytes(r_bytes)
	var s := from_bytes(s_bytes)
	if _is_zero_raw(r) or _is_zero_raw(s) or cmp(r, N) >= 0 or cmp(s, N) >= 0:
		return PackedByteArray()
	var x := r
	if recid & 2:
		x = _carry(add_raw(r, N))
		if x.size() > 10 or cmp(x, P) >= 0:
			return PackedByteArray()
	# y² = x³ + 7
	var seven := zero()
	seven[0] = 7
	var rhs := fadd(fm(fsq(x), x), seven)
	var y := pow_bytes(rhs, _p_sqrt, KP)
	if cmp(canon(fsq(y), P), canon(rhs, P)) != 0:
		return PackedByteArray()
	y = canon(y, P)
	if (y[0] & 1) != (recid & 1):
		y = canon(fsub(zero(), y), P)
	var big_r := [x, y, one()]
	var e := canon(_reduce(from_bytes(hash), KN), N)
	var rinv := canon(pow_bytes(r, _n_minus_2, KN), N)
	var u1 := canon(sub(zero(), mul(e, rinv, KN), KN, N32), N)
	var u2 := canon(mul(s, rinv, KN), N)
	var q := to_affine(mul2(u1, G, u2, big_r))
	if q.is_empty():
		return PackedByteArray()
	var out := to_bytes(q[0])
	out.append_array(to_bytes(q[1]))
	return out


static func add_raw(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var t := PackedInt64Array()
	t.resize(10)
	for i in 10:
		t[i] = a[i] + b[i]
	return t


static func _is_zero_raw(a: PackedInt64Array) -> bool:
	for v in a:
		if v != 0:
			return false
	return true


## 64-byte public key of a 32-byte private key ([] if out of range).
static func public_key(priv: PackedByteArray) -> PackedByteArray:
	_setup()
	var d := from_bytes(priv)
	if priv.size() != 32 or _is_zero_raw(d) or cmp(d, N) >= 0:
		return PackedByteArray()
	var q := to_affine(scalar_mul(d, G))
	var out := to_bytes(q[0])
	out.append_array(to_bytes(q[1]))
	return out


## RFC 6979 (HMAC-SHA256) deterministic signature, low-s.
## {r: bytes32, s: bytes32, recid: 0..3} or {} on bad input.
static func sign(hash: PackedByteArray, priv: PackedByteArray) -> Dictionary:
	_setup()
	var d := from_bytes(priv)
	if hash.size() != 32 or priv.size() != 32 or _is_zero_raw(d) or cmp(d, N) >= 0:
		return {}
	var crypto := Crypto.new()
	var h1 := to_bytes(canon(_reduce(from_bytes(hash), KN), N))  # bits2octets
	var v := PackedByteArray()
	v.resize(32)
	v.fill(1)
	var kk := PackedByteArray()
	kk.resize(32)
	kk.fill(0)
	kk = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v + PackedByteArray([0]) + priv + h1)
	v = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v)
	kk = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v + PackedByteArray([1]) + priv + h1)
	v = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v)
	var e := canon(_reduce(from_bytes(hash), KN), N)
	for _attempt in 64:
		v = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v)
		var k := from_bytes(v)
		if not _is_zero_raw(k) and cmp(k, N) < 0:
			var rp := to_affine(scalar_mul(k, G))
			if not rp.is_empty():
				var r := canon(_reduce((rp[0] as PackedInt64Array).duplicate(), KN), N)
				var recid: int = (rp[1][0] & 1) | (2 if cmp(rp[0], N) >= 0 else 0)
				var kinv := pow_bytes(k, _n_minus_2, KN)
				var s := canon(mul(kinv, add(e, mul(r, d, KN), KN), KN), N)
				if not _is_zero_raw(r) and not _is_zero_raw(s):
					if cmp(s, _half_n) > 0:
						s = canon(sub(zero(), s, KN, N32), N)
						recid ^= 1
					return {"r": to_bytes(r), "s": to_bytes(s), "recid": recid}
		kk = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v + PackedByteArray([0]))
		v = crypto.hmac_digest(HashingContext.HASH_SHA256, kk, v)
	return {}
