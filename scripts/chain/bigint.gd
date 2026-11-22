class_name BigInt
extends RefCounted
## Arbitrary-precision unsigned integers for chain values (uint256, 240-bit
## coordinates, Waats). Values are little-endian PackedInt64Array limbs in
## base 2^24, so every intermediate product fits in a signed 64-bit int.
##
## Chain values must never pass through float. Use log10() only for display
## scaling, and to_int() only when fits_int() says so.
##
## Signed values (int256) are handled at the edges as hex strings with an
## optional leading "-" ("-0x1f"); see word_to_signed_hex / signed_to_word.

const LIMB_BITS := 24
const LIMB_BASE := 1 << 24
const LIMB_MASK := (1 << 24) - 1
const HEX_PER_LIMB := 6


static func zero() -> PackedInt64Array:
	return PackedInt64Array()


static func _trim(a: PackedInt64Array) -> PackedInt64Array:
	var n := a.size()
	while n > 0 and a[n - 1] == 0:
		n -= 1
	if n != a.size():
		a.resize(n)
	return a


static func is_zero(a: PackedInt64Array) -> bool:
	return _trim(a.duplicate()).is_empty()


static func from_int(n: int) -> PackedInt64Array:
	assert(n >= 0, "BigInt.from_int expects a non-negative int")
	var out := PackedInt64Array()
	while n > 0:
		out.append(n & LIMB_MASK)
		n >>= LIMB_BITS
	return out


static func _strip_hex(s: String) -> String:
	s = s.strip_edges().to_lower()
	if s.begins_with("0x"):
		s = s.substr(2)
	return s


## Parses an unsigned hex string (with or without 0x). Returns an empty array
## for "" or "0". Invalid characters are a programming error.
static func from_hex(s: String) -> PackedInt64Array:
	s = _strip_hex(s)
	var out := PackedInt64Array()
	var end := s.length()
	while end > 0:
		var start := maxi(0, end - HEX_PER_LIMB)
		out.append(s.substr(start, end - start).hex_to_int())
		end = start
	return _trim(out)


static func to_hex(a: PackedInt64Array) -> String:
	a = _trim(a.duplicate())
	if a.is_empty():
		return "0"
	var s := "%x" % a[a.size() - 1]
	for i in range(a.size() - 2, -1, -1):
		s += "%06x" % a[i]
	return s


## Returns a 64-character, zero-padded hex word (no 0x). Asserts a < 2^256.
static func to_word(a: PackedInt64Array) -> String:
	var h := to_hex(a)
	assert(h.length() <= 64, "BigInt.to_word: value exceeds 256 bits")
	return h.lpad(64, "0")


static func from_decimal(s: String) -> PackedInt64Array:
	s = s.strip_edges()
	var out := PackedInt64Array()
	for ch in s:
		var d := ch.unicode_at(0) - 48
		assert(d >= 0 and d <= 9, "BigInt.from_decimal: not a digit")
		out = add(mul_small(out, 10), from_int(d))
	return out


static func to_decimal(a: PackedInt64Array) -> String:
	a = _trim(a.duplicate())
	if a.is_empty():
		return "0"
	var parts: PackedStringArray = []
	while not a.is_empty():
		var qr := divmod_small(a, 1000000)
		a = qr[0]
		parts.append(str(qr[1]))
	var s := parts[parts.size() - 1]
	for i in range(parts.size() - 2, -1, -1):
		s += parts[i].lpad(6, "0")
	return s


## Accepts int, PackedInt64Array, "0x…" hex or a decimal string.
static func coerce(v) -> PackedInt64Array:
	if v is PackedInt64Array:
		return _trim(v.duplicate())
	if v is int:
		return from_int(v)
	if v is String:
		var s: String = v.strip_edges()
		if s.to_lower().begins_with("0x"):
			return from_hex(s)
		return from_decimal(s)
	assert(false, "BigInt.coerce: unsupported type")
	return PackedInt64Array()


static func cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:
	a = _trim(a.duplicate())
	b = _trim(b.duplicate())
	if a.size() != b.size():
		return 1 if a.size() > b.size() else -1
	for i in range(a.size() - 1, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


static func add(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var n := maxi(a.size(), b.size())
	var out := PackedInt64Array()
	out.resize(n + 1)
	var carry := 0
	for i in n:
		var s := carry
		if i < a.size():
			s += a[i]
		if i < b.size():
			s += b[i]
		out[i] = s & LIMB_MASK
		carry = s >> LIMB_BITS
	out[n] = carry
	return _trim(out)


## a - b; asserts a >= b.
static func sub(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	assert(cmp(a, b) >= 0, "BigInt.sub: negative result")
	var out := a.duplicate()
	var borrow := 0
	for i in out.size():
		var d := out[i] - borrow - (b[i] if i < b.size() else 0)
		if d < 0:
			d += LIMB_BASE
			borrow = 1
		else:
			borrow = 0
		out[i] = d
	return _trim(out)


## Multiplies by a small non-negative factor (< 2^24).
static func mul_small(a: PackedInt64Array, m: int) -> PackedInt64Array:
	assert(m >= 0 and m < LIMB_BASE, "BigInt.mul_small: factor out of range")
	var out := PackedInt64Array()
	out.resize(a.size() + 1)
	var carry := 0
	for i in a.size():
		var p := a[i] * m + carry
		out[i] = p & LIMB_MASK
		carry = p >> LIMB_BITS
	out[a.size()] = carry
	return _trim(out)


static func mul(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	a = _trim(a.duplicate())
	b = _trim(b.duplicate())
	if a.is_empty() or b.is_empty():
		return PackedInt64Array()
	var out := PackedInt64Array()
	out.resize(a.size() + b.size() + 1)
	for i in a.size():
		var carry := 0
		for j in b.size():
			var t := out[i + j] + a[i] * b[j] + carry
			out[i + j] = t & LIMB_MASK
			carry = t >> LIMB_BITS
		var k := i + b.size()
		while carry != 0:
			var t2 := out[k] + carry
			out[k] = t2 & LIMB_MASK
			carry = t2 >> LIMB_BITS
			k += 1
	return _trim(out)


## Returns [quotient, remainder] for a small positive divisor (< 2^31).
static func divmod_small(a: PackedInt64Array, d: int) -> Array:
	assert(d > 0 and d < (1 << 31), "BigInt.divmod_small: divisor out of range")
	var q := PackedInt64Array()
	q.resize(a.size())
	var r := 0
	for i in range(a.size() - 1, -1, -1):
		var cur := (r << LIMB_BITS) | a[i]
		q[i] = cur / d
		r = cur % d
	return [_trim(q), r]


## a mod m for m up to 2^59 (e.g. the Motzkin prime, 360e6). Works hex digit
## by hex digit: r = (r*16 + d) % m never exceeds 2^63.
static func mod_int(a: PackedInt64Array, m: int) -> int:
	assert(m > 0 and m < (1 << 59), "BigInt.mod_int: modulus out of range")
	var r := 0
	for ch in to_hex(a):
		r = (r * 16 + ch.hex_to_int()) % m
	return r


static func xor(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var n := maxi(a.size(), b.size())
	var out := PackedInt64Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0) ^ (b[i] if i < b.size() else 0)
	return _trim(out)


static func shr(a: PackedInt64Array, bits: int) -> PackedInt64Array:
	assert(bits >= 0)
	var limbs := bits / LIMB_BITS
	var rem := bits % LIMB_BITS
	var out := PackedInt64Array()
	for i in range(limbs, a.size()):
		var v := a[i] >> rem
		if rem > 0 and i + 1 < a.size():
			v |= (a[i + 1] << (LIMB_BITS - rem)) & LIMB_MASK
		out.append(v & LIMB_MASK)
	return _trim(out)


static func shl(a: PackedInt64Array, bits: int) -> PackedInt64Array:
	assert(bits >= 0)
	var out := PackedInt64Array()
	out.resize(bits / LIMB_BITS)
	var rem := bits % LIMB_BITS
	var carry := 0
	for i in a.size():
		var v := (a[i] << rem) | carry
		out.append(v & LIMB_MASK)
		carry = v >> LIMB_BITS
	if carry != 0:
		out.append(carry)
	return _trim(out)


## a mod 2^bits.
static func low_bits(a: PackedInt64Array, bits: int) -> PackedInt64Array:
	var limbs := bits / LIMB_BITS
	var rem := bits % LIMB_BITS
	var out := PackedInt64Array()
	for i in mini(limbs, a.size()):
		out.append(a[i])
	if rem > 0 and limbs < a.size():
		out.append(a[limbs] & ((1 << rem) - 1))
	return _trim(out)


static func bit_length(a: PackedInt64Array) -> int:
	a = _trim(a.duplicate())
	if a.is_empty():
		return 0
	var top := a[a.size() - 1]
	var n := 0
	while top > 0:
		top >>= 1
		n += 1
	return (a.size() - 1) * LIMB_BITS + n


static func fits_int(a: PackedInt64Array) -> bool:
	return bit_length(a) <= 63


static func to_int(a: PackedInt64Array) -> int:
	assert(fits_int(a), "BigInt.to_int: value does not fit in 63 bits")
	var v := 0
	for i in range(a.size() - 1, -1, -1):
		v = (v << LIMB_BITS) | a[i]
	return v


## Approximate base-10 logarithm, for display scaling only. -INF for zero.
static func log10(a: PackedInt64Array) -> float:
	a = _trim(a.duplicate())
	if a.is_empty():
		return -INF
	# Use the top three limbs (72 bits) as the mantissa.
	var n := a.size()
	var m := 0.0
	var used := 0
	for i in range(n - 1, maxi(-1, n - 4), -1):
		m = m * LIMB_BASE + float(a[i])
		used += 1
	return log(m) / log(10.0) + float((n - used) * LIMB_BITS) * (log(2.0) / log(10.0))


# --- int256 helpers ---------------------------------------------------------

static func pow2(bits: int) -> PackedInt64Array:
	return shl(from_int(1), bits)


## Decodes a 256-bit two's-complement word into a signed hex string ("-0x1f", "0x2a").
static func word_to_signed_hex(word_hex: String) -> String:
	var v := from_hex(word_hex)
	if bit_length(v) == 256:  # top bit set → negative
		return "-0x" + to_hex(sub(pow2(256), v))
	return "0x" + to_hex(v)


## Parses a signed value (int, "-0x…", "-123", "0x…", "123") into
## [is_negative: bool, magnitude: PackedInt64Array].
static func from_signed(v) -> Array:
	if v is int:
		return [v < 0, from_int(absi(v))]
	var s: String = String(v).strip_edges()
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	return [neg, coerce(s)]


## Encodes a signed value as a 64-char two's-complement word.
static func signed_to_word(v) -> String:
	var parts := from_signed(v)
	var mag: PackedInt64Array = parts[1]
	if not parts[0] or is_zero(mag):
		return to_word(mag)
	return to_word(sub(pow2(256), mag))
