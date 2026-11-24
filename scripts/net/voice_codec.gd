class_name VoiceCodec
extends RefCounted
## Voice chat codecs in plain GDScript (no GDExtension): 16 kHz mono, 20 ms
## frames (320 samples).
##   IMA-ADPCM: 4 bits a sample, 163 bytes a frame (3-byte header: predictor
##   s16 + step index, so every frame decodes on its own and a lost frame
##   loses only itself) → 65 kbit/s.
##   G.711 μ-law: 8 bits a sample, 320 bytes a frame → 128 kbit/s (fallback).
## Plus a streaming resampler from the mic's mix rate down to 16 kHz.

const STEP := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
	73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494,
	544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749,
	3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635,
	13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]


static func _to_i16(v: float) -> int:
	return clampi(int(round(v * 32767.0)), -32768, 32767)


## Floats in [-1, 1] → ADPCM frame. `state` [predictor, index] carries over
## between frames for a smoother start (pass [0, 0] for a fresh one).
static func encode_adpcm(pcm: PackedFloat32Array, state: Array = [0, 0]) -> PackedByteArray:
	var pred: int = state[0]
	var index: int = state[1]
	var n := pcm.size()
	var out := PackedByteArray()
	out.resize(3 + (n + 1) / 2)
	out.fill(0)
	out.encode_s16(0, pred)
	out[2] = index
	for i in n:
		var sample := _to_i16(pcm[i])
		var step: int = STEP[index]
		var diff := sample - pred
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var vp := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			vp += step
		step >>= 1
		if diff >= step:
			code |= 2
			diff -= step
			vp += step
		step >>= 1
		if diff >= step:
			code |= 1
			vp += step
		pred = clampi(pred - vp if code & 8 else pred + vp, -32768, 32767)
		index = clampi(index + INDEX[code], 0, 88)
		if i & 1:
			out[3 + (i >> 1)] |= code << 4
		else:
			out[3 + (i >> 1)] |= code
	state[0] = pred
	state[1] = index
	return out


static func decode_adpcm(data: PackedByteArray, samples: int = -1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if data.size() < 4:
		return out
	var pred: int = data.decode_s16(0)
	var index: int = clampi(data[2], 0, 88)
	var n := (data.size() - 3) * 2 if samples < 0 else mini(samples, (data.size() - 3) * 2)
	out.resize(n)
	for i in n:
		var byte: int = data[3 + (i >> 1)]
		var code := (byte >> 4) & 15 if i & 1 else byte & 15
		var step: int = STEP[index]
		var vp := step >> 3
		if code & 4:
			vp += step
		if code & 2:
			vp += step >> 1
		if code & 1:
			vp += step >> 2
		pred = clampi(pred - vp if code & 8 else pred + vp, -32768, 32767)
		index = clampi(index + INDEX[code], 0, 88)
		out[i] = pred / 32768.0
	return out


## G.711 μ-law.
static func encode_ulaw(pcm: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(pcm.size())
	for i in pcm.size():
		var s := _to_i16(pcm[i])
		var sign := 0
		if s < 0:
			sign = 0x80
			s = -s
		s = mini(s, 32635) + 0x84
		var exp := 7
		var mask := 0x4000
		while exp > 0 and (s & mask) == 0:
			exp -= 1
			mask >>= 1
		var mant := (s >> (exp + 3)) & 0x0F
		out[i] = ~(sign | (exp << 4) | mant) & 0xFF
	return out


static func decode_ulaw(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		var u := ~int(data[i]) & 0xFF
		var sign := u & 0x80
		var exp := (u >> 4) & 7
		var mant := u & 0x0F
		var s := (((mant << 3) + 0x84) << exp) - 0x84
		out[i] = (-s if sign else s) / 32768.0
	return out


static func decode(codec: int, data: PackedByteArray) -> PackedFloat32Array:
	if codec == NetProto.CODEC_ADPCM:
		return decode_adpcm(data, NetProto.VOICE_FRAME)
	if codec == NetProto.CODEC_ULAW:
		return decode_ulaw(data)
	return PackedFloat32Array()


## RMS level of a frame (0..1): the speaking indicator and the noise gate.
static func level(pcm: PackedFloat32Array) -> float:
	if pcm.is_empty():
		return 0.0
	var acc := 0.0
	for v in pcm:
		acc += v * v
	return sqrt(acc / pcm.size())


## Streaming resampler, stereo frames at `src_rate` → mono floats at `dst_rate`.
## Box-averages over each output step (a cheap low-pass) then linear-interpolates.
class Resampler:
	extends RefCounted
	var ratio := 1.0
	var _pos := 0.0  # fractional read position into the pending input
	var _pending := PackedFloat32Array()

	func _init(src_rate: float, dst_rate: float) -> void:
		ratio = src_rate / dst_rate

	func push(frames: PackedVector2Array) -> PackedFloat32Array:
		for f in frames:
			_pending.append((f.x + f.y) * 0.5)
		var out := PackedFloat32Array()
		var half := int(ratio * 0.5)
		while _pos + 1.0 < _pending.size():
			var i := int(_pos)
			var fr := _pos - i
			var a := _pending[i]
			var b := _pending[i + 1]
			var v := a + (b - a) * fr
			if half >= 1:
				var acc := 0.0
				var cnt := 0
				for k in range(maxi(0, i - half), mini(_pending.size(), i + half + 1)):
					acc += _pending[k]
					cnt += 1
				v = acc / cnt
			out.append(v)
			_pos += ratio
		var drop := int(_pos) - half - 1
		if drop > 0:
			_pending = _pending.slice(drop)
			_pos -= drop
		return out
