class_name VehicleAudio
extends RefCounted
## Engine loops for the garage vehicles, synthesised once and kept: a seamless
## 0.5 s loop per engine (tones at whole multiples of 2 Hz so they wrap exactly;
## the noise part is cross-faded across the seam). The vehicle plays it on the
## SFX bus and bends pitch and volume with speed and thrust.

const RATE := 22050
const LOOP_S := 0.5
## engine → [[freq Hz, amp, harmonics], …], noise amount, noise smoothing (0..1), tremolo Hz, tremolo depth
const DEFS := {
	"rover": {"tones": [[110.0, 0.35, 3], [220.0, 0.12, 1]], "noise": 0.06, "smooth": 0.9, "trem": 8.0, "depth": 0.15},
	"hoverbike": {"tones": [[196.0, 0.25, 6], [392.0, 0.08, 2]], "noise": 0.12, "smooth": 0.7, "trem": 0.0, "depth": 0.0},
	"skimmer": {"tones": [[148.0, 0.18, 4]], "noise": 0.32, "smooth": 0.55, "trem": 0.0, "depth": 0.0},
	"hopper": {"tones": [[74.0, 0.22, 3]], "noise": 0.45, "smooth": 0.82, "trem": 0.0, "depth": 0.0},
	"crawler": {"tones": [[42.0, 0.4, 8], [84.0, 0.1, 2]], "noise": 0.08, "smooth": 0.93, "trem": 12.0, "depth": 0.45},
}

static var _cache := {}


static func engine(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var d: Dictionary = DEFS.get(kind, DEFS["rover"])
	var n := int(RATE * LOOP_S)
	var fade := int(RATE * 0.05)
	var buf := samples(d, n, fade, hash(kind))
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = pcm
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_cache[kind] = w
	return w


## The loop's samples (pure; tested for a seamless wrap and a bounded peak).
static func samples(d: Dictionary, n: int, fade: int, seed_v: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for tone in d["tones"]:
		var f: float = tone[0]
		var amp: float = tone[1]
		var harmonics: int = tone[2]
		for h in range(1, harmonics + 1):
			var a := amp / float(h)
			var w := TAU * f * h / RATE
			for i in n:
				buf[i] += a * sin(w * i)
	# Smoothed noise, cross-faded so the loop has no click.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := PackedFloat32Array()
	noise.resize(n + fade)
	var y := 0.0
	var k: float = d["smooth"]
	for i in n + fade:
		y = y * k + rng.randf_range(-1.0, 1.0) * (1.0 - k)
		noise[i] = y
	var norm := 1.0 / maxf(0.05, sqrt((1.0 - k) / (1.0 + k)))
	for i in n:
		var v := noise[i]
		if i < fade:
			var t := float(i) / fade
			v = noise[i] * t + noise[n + i] * (1.0 - t)
		buf[i] += float(d["noise"]) * v * norm * 0.35
	var trem: float = d["trem"]
	if trem > 0.0:
		for i in n:
			buf[i] *= 1.0 - float(d["depth"]) * 0.5 * (1.0 + sin(TAU * trem * i / RATE))
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	if peak > 0.0:
		var s := 0.7 / peak
		for i in n:
			buf[i] *= s
	return buf
