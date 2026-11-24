class_name Keccak
extends RefCounted
## Keccak-256 (Ethereum's hash: the original Keccak padding 0x01…0x80, not
## SHA3-256's 0x06). Pure GDScript on 64-bit lanes; GDScript ints are signed
## 64-bit, so rotations mask the arithmetic right shift.
## Checked against tests/golden/selectors.json and tests/golden/ecrecover.json.

const RATE := 136
## Rotation offsets r[x + 5y].
const ROT := [0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14]
## Round constants as [high 32 bits, low 32 bits] (a literal above 2^63 would not parse).
const RC_HL := [
	[0x00000000, 0x00000001], [0x00000000, 0x00008082], [0x80000000, 0x0000808A], [0x80000000, 0x80008000],
	[0x00000000, 0x0000808B], [0x00000000, 0x80000001], [0x80000000, 0x80008081], [0x80000000, 0x00008009],
	[0x00000000, 0x0000008A], [0x00000000, 0x00000088], [0x00000000, 0x80008009], [0x00000000, 0x8000000A],
	[0x00000000, 0x8000808B], [0x80000000, 0x0000008B], [0x80000000, 0x00008089], [0x80000000, 0x00008003],
	[0x80000000, 0x00008002], [0x80000000, 0x00000080], [0x00000000, 0x0000800A], [0x80000000, 0x8000000A],
	[0x80000000, 0x80008081], [0x80000000, 0x00008080], [0x00000000, 0x80000001], [0x80000000, 0x80008008],
]

static var _rc: PackedInt64Array
## pi: lane x+5y moves to y + 5*((2x+3y) % 5)
static var _pi: PackedInt32Array


static func _init_tables() -> void:
	if not _rc.is_empty():
		return
	_rc.resize(24)
	for i in 24:
		_rc[i] = (int(RC_HL[i][0]) << 32) | int(RC_HL[i][1])
	_pi.resize(25)
	for x in 5:
		for y in 5:
			_pi[x + 5 * y] = y + 5 * ((2 * x + 3 * y) % 5)


static func _rotl(v: int, n: int) -> int:
	if n == 0:
		return v
	return (v << n) | ((v >> (64 - n)) & ((1 << n) - 1))


static func _permute(a: PackedInt64Array) -> void:
	var c := PackedInt64Array()
	c.resize(5)
	var b := PackedInt64Array()
	b.resize(25)
	for rnd in 24:
		for x in 5:
			c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
		for x in 5:
			var d: int = c[(x + 4) % 5] ^ _rotl(c[(x + 1) % 5], 1)
			for y in 5:
				a[x + 5 * y] ^= d
		for i in 25:
			b[_pi[i]] = _rotl(a[i], ROT[i])
		for y in 5:
			var o := 5 * y
			var b0 := b[o]
			var b1 := b[o + 1]
			var b2 := b[o + 2]
			var b3 := b[o + 3]
			var b4 := b[o + 4]
			a[o] = b0 ^ (~b1 & b2)
			a[o + 1] = b1 ^ (~b2 & b3)
			a[o + 2] = b2 ^ (~b3 & b4)
			a[o + 3] = b3 ^ (~b4 & b0)
			a[o + 4] = b4 ^ (~b0 & b1)
		a[0] ^= _rc[rnd]


## Keccak-256 of `data` → 32 bytes.
static func digest(data: PackedByteArray) -> PackedByteArray:
	_init_tables()
	var msg := data.duplicate()
	var pad := RATE - (msg.size() % RATE)
	var start := msg.size()
	msg.resize(start + pad)
	for i in range(start, msg.size()):
		msg[i] = 0
	msg[start] = msg[start] | 0x01
	msg[msg.size() - 1] = msg[msg.size() - 1] | 0x80
	var st := PackedInt64Array()
	st.resize(25)
	st.fill(0)
	var off := 0
	while off < msg.size():
		for i in 17:  # RATE / 8 lanes
			st[i] ^= msg.decode_s64(off + i * 8)
		_permute(st)
		off += RATE
	var out := PackedByteArray()
	out.resize(32)
	for i in 4:
		out.encode_s64(i * 8, st[i])
	return out


static func hash_hex(data: PackedByteArray) -> String:
	return "0x" + digest(data).hex_encode()


static func hash_text(text: String) -> PackedByteArray:
	return digest(text.to_utf8_buffer())
