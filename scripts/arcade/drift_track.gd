class_name DriftTrack
extends RefCounted
## The track of Entropy Drift's 3D world, read from the chain, never invented.
##
## bytes = SHA-256("<QING.Entropy() decimal>:<32-byte hash, lower-case 0x hex>"). The hash is the
## block hash of the block that holds the credit's AFFECTION transfer (a paid run), or the latest
## block's hash (the demo). When no hash could be read the track is flat and straight, `ok` is false
## and the source says "—": nothing stands in for chain data.
##
## The track is a sequence of segments, SEG px of the game's distance each (the 2D field's own units).
## Segment i bends by curve(i) and climbs by hill(i), both from the bytes; between segment centres
## the values are smoothstepped, so the road never jumps. The run's seed also comes from the bytes,
## so the shards and motes of a paid run are the chain's entropy too.

const SEG := 1200.0
const MAX_CURVE := 0.0026  ## bend (1/m) at a byte of 0 or 255
const MAX_HILL := 0.0011

var bytes := PackedByteArray()
var ok := false
var source := "—"  ## where the bytes came from, for the HUD
var block := -1
var hash_hex := ""


static func make(entropy_dec: String, hash_hex_in: String, block_n: int = -1, what: String = "block") -> DriftTrack:
	var t := DriftTrack.new()
	var h := hash_hex_in.strip_edges().to_lower()
	if not h.begins_with("0x"):
		h = "0x" + h
	if h.length() != 66 or not h.substr(2).is_valid_hex_number() or entropy_dec == "":
		t.bytes.resize(32)
		t.source = "track: — (no %s hash read; flat road)" % what
		return t
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%s:%s" % [entropy_dec, h]).to_utf8_buffer())
	t.bytes = ctx.finish()
	t.ok = true
	t.block = block_n
	t.hash_hex = h
	var where := ("%s #%s" % [what, ArcadeScores.grouped(block_n)]) if block_n >= 0 else what
	t.source = "track: SHA-256(QING.Entropy() : %s hash %s…%s)" % [where, h.substr(0, 8), h.right(4)]
	return t


## The run's seed: the first six bytes (48 bits). 0 for a flat (unread) track.
func seed() -> int:
	if not ok:
		return 0
	var s := 0
	for i in 6:
		s = (s << 8) | bytes[i]
	return s


func _curve_i(i: int) -> float:
	if not ok:
		return 0.0
	return (float(bytes[posmod(i, 32)]) - 127.5) / 127.5 * MAX_CURVE


func _hill_i(i: int) -> float:
	if not ok:
		return 0.0
	return (float(bytes[posmod(i * 7 + 3, 32)]) - 127.5) / 127.5 * MAX_HILL


static func _blend(a: float, b: float, f: float) -> float:
	return lerpf(a, b, f * f * (3.0 - 2.0 * f))


## The road's bend at distance d (px of the 2D field): positive bends right.
func curve_at(d: float) -> float:
	var x := d / SEG
	var i := floori(x)
	return _blend(_curve_i(i), _curve_i(i + 1), x - i)


## The road's climb at distance d: positive rises ahead.
func hill_at(d: float) -> float:
	var x := d / SEG
	var i := floori(x)
	return _blend(_hill_i(i), _hill_i(i + 1), x - i)


## The track's hue (0..1): the road's neon colour.
func hue() -> float:
	return float(bytes[31]) / 255.0 if ok else 0.53
