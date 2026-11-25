class_name RaveTrack
extends RefCounted
## The arcade's dance track, synthesised from nothing: an original four-on-the-floor loop, kick, clap,
## hats, an off-beat bass and an arpeggio over a minor progression, in the territory's tempo and key
## (RaveStyle). No samples, no recordings: every sound is computed here.
##
## The song is a 16-bar cycle: INTRO (bars 0–3: drums and bass), DROP (4–11: everything), BREAK
## (12–13: pad and arp, no kick) and BUILD (14–15: a snare roll and a riser back into the intro).
## Bar k plays chord k % 4. A bar renders to stereo frames once (render); RaveMusic streams them
## into an AudioStreamGenerator. Pure and deterministic: the same style renders the same samples.

const RATE := 22050
const STEPS := 16
const SWING := 0.08  ## odd 16ths are this fraction of a step late
const SECTIONS := ["intro", "intro", "intro", "intro", "drop", "drop", "drop", "drop",
	"drop", "drop", "drop", "drop", "break", "break", "build", "build"]
## Chord tones (semitones over the key's root) per groove: four chords of a minor progression.
const PROGRESSIONS := [
	[[0, 3, 7], [8, 12, 15], [3, 7, 10], [10, 14, 17]],  # i  VI  III VII
	[[0, 3, 7], [10, 14, 17], [8, 12, 15], [7, 11, 14]],  # i  VII VI  V
	[[0, 3, 7], [5, 8, 12], [8, 12, 15], [7, 10, 14]],  # i  iv  VI  v
	[[0, 3, 7], [8, 12, 15], [10, 14, 17], [3, 7, 10]],  # i  VI  VII III
]
## Arp: chord-tone index per 16th (3 = the root an octave up); -1 rests.
const ARPS := [
	[0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 2, 1, 3],
	[0, 2, 1, 3, 0, 2, 1, 3, 0, 2, 1, 3, 2, 1, 0, -1],
	[3, 2, 1, 0, 1, 2, 3, 2, 3, 1, 2, 0, 1, 2, 3, -1],
	[0, -1, 2, 1, 3, -1, 2, 1, 0, -1, 2, 3, 1, 2, 3, 2],
]
## Bass: per 16th, 0 rest, 1 the root, 2 the root an octave up.
const BASSES := [
	[0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 2],
	[0, 0, 1, 1, 0, 0, 1, 2, 0, 0, 1, 1, 0, 0, 2, 1],
	[0, 1, 1, 0, 0, 1, 2, 0, 0, 1, 1, 0, 0, 1, 2, 1],
	[0, 0, 1, 2, 0, 0, 1, 0, 0, 0, 1, 2, 0, 1, 0, 2],
]


## {bpm, root, groove, rate} from a RaveStyle.
static func spec(style: Dictionary) -> Dictionary:
	return {"bpm": int(style.get("bpm", 124)), "root": int(style.get("root", 0)), "groove": int(style.get("groove", 0)) % 4, "rate": RATE}


static func beat_s(sp: Dictionary) -> float:
	return 60.0 / float(sp["bpm"])


static func bar_samples(sp: Dictionary) -> int:
	return int(round(float(RATE) * beat_s(sp) * 4.0))


static func section(bar: int) -> String:
	return SECTIONS[posmod(bar, STEPS)]


static func chord_of(bar: int) -> int:
	return posmod(bar, 4)


## The cache key of bar `bar`'s audio (bars with the same key sound the same).
static func bar_key(bar: int) -> String:
	return "%s:%d" % [section(bar), chord_of(bar)]


## Every distinct bar of the cycle, in the order the song first needs them.
static func keys_in_order() -> Array:
	var out: Array = []
	for b in STEPS:
		var k := bar_key(b)
		if not out.has(k):
			out.append(k)
	return out


## Hz of a note `semis` above the key's root in octave `oct` (0 = the bass, A1 = 55 Hz).
static func hz(sp: Dictionary, semis: int, oct: int = 0) -> float:
	return 55.0 * pow(2.0, (float(sp["root"]) + float(semis)) / 12.0 + float(oct))


## The one-shots every bar mixes from (mono): kick, clap, hats, bass notes, arp plucks.
static func make_kit(sp: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7A7E + int(sp["root"]) * 31 + int(sp["groove"])
	var step := beat_s(sp) / 4.0
	var kit := {"kick": _kick(), "clap": _clap(rng), "hat": _hat(rng, 0.045, 70.0), "open": _hat(rng, 0.2, 13.0),
		"snare": _clap(rng, 0.09), "bass": {}, "pluck": {}}
	var prog: Array = PROGRESSIONS[int(sp["groove"])]
	for chord in prog:
		var root: int = chord[0]
		for o in [0, 1]:
			var k := "%d:%d" % [root, o]
			if not kit["bass"].has(k):
				kit["bass"][k] = _bass(hz(sp, root, o + 1), step * 1.7)
		for i in 4:
			var semis: int = chord[i] if i < 3 else chord[0] + 12
			if not kit["pluck"].has(semis):
				kit["pluck"][semis] = _pluck(hz(sp, semis, 3), 0.22)
	return kit


## Renders one bar: stereo frames, bar_samples(sp) long, |sample| < 1.
static func render(sp: Dictionary, sec: String, chord: int, kit: Dictionary = {}) -> PackedVector2Array:
	if kit.is_empty():
		kit = make_kit(sp)
	var n := bar_samples(sp)
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	var step := float(n) / STEPS
	var g := int(sp["groove"])
	var tones: Array = PROGRESSIONS[g][posmod(chord, 4)]
	var drums := sec != "break"
	for s in STEPS:
		var at := int(round(s * step + (SWING * step if s % 2 == 1 else 0.0)))
		if drums and s % 4 == 0 and (sec != "build" or s == 0):
			_add(l, r, kit["kick"], at, 0.95, 0.5)
		if (sec == "drop" or sec == "intro") and (s == 4 or s == 12):
			_add(l, r, kit["clap"], at, 0.45, 0.5)
		if drums:
			if s % 4 == 2:
				_add(l, r, kit["open"], at, 0.2, 0.62)
			elif sec != "build":
				_add(l, r, kit["hat"], at, 0.16 if s % 2 == 0 else 0.1, 0.38)
		if sec == "build":
			# The snare roll climbs: every 16th, louder toward the next bar.
			var bar_t := float(s) / STEPS
			_add(l, r, kit["snare"], at, 0.12 + 0.3 * bar_t, 0.5)
		if sec == "intro" or sec == "drop":
			var b: int = BASSES[g][s]
			if b > 0:
				_add(l, r, kit["bass"]["%d:%d" % [int(tones[0]), b - 1]], at, 0.55, 0.5)
		if sec != "intro":
			var ai: int = ARPS[g][s]
			if ai >= 0:
				var semis: int = tones[ai] if ai < 3 else int(tones[0]) + 12
				_add(l, r, kit["pluck"][semis], at, 0.2 if sec == "drop" else 0.32, 0.5 + (0.22 if s % 2 == 0 else -0.22))
	if sec == "break":
		var pad := _pad(sp, tones, n)
		_add(l, r, pad, 0, 0.55, 0.5)
	if sec == "build":
		_add(l, r, _riser(n), 0, 0.22, 0.5)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		out[i] = Vector2(soft_clip(l[i]), soft_clip(r[i]))
	return out


## A gentle saturator: about ×0.8 for quiet samples, approaching ±1 and never reaching it.
static func soft_clip(x: float) -> float:
	return x * 0.8 / sqrt(1.0 + x * x * 0.64)


## Mixes mono `src` into l/r from `at` with gain and pan (0 left … 1 right); cut at the bar's end.
static func _add(l: PackedFloat32Array, r: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float, pan: float) -> void:
	var gl := gain * cos(pan * PI * 0.5) * 1.41
	var gr := gain * sin(pan * PI * 0.5) * 1.41
	var m := mini(src.size(), l.size() - at)
	for i in m:
		var v := src[i]
		l[at + i] += v * gl
		r[at + i] += v * gr


static func _kick() -> PackedFloat32Array:
	var n := int(RATE * 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 44.0 + 110.0 * exp(-t * 32.0)
		ph += TAU * f / RATE
		var click := exp(-t * 400.0) * 0.4
		out[i] = (sin(ph) * exp(-t * 8.0) + click) * 1.0
	return out


static func _clap(rng: RandomNumberGenerator, len_s: float = 0.22) -> PackedFloat32Array:
	var n := int(RATE * len_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.45
		var bp := lp - prev  # a crude band: low-passed, then differenced
		prev = lp
		var env := exp(-t * 20.0)
		for k in 3:  # three hands, a few ms apart
			var tk := t - k * 0.011
			if tk >= 0.0 and tk < 0.008:
				env += 0.6
		out[i] = bp * env * 2.2
	return out


static func _hat(rng: RandomNumberGenerator, len_s: float, decay: float) -> PackedFloat32Array:
	var n := int(RATE * len_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		out[i] = (w - prev) * 0.5 * exp(-t * decay)
		prev = w
	return out


static func _bass(f: float, len_s: float) -> PackedFloat32Array:
	var n := int(RATE * len_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		ph = fmod(ph + f / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		var cut := 0.08 + 0.3 * exp(-t * 18.0)  # a plucky filter that closes
		lp += (saw - lp) * cut
		var env := minf(1.0, t * 300.0) * exp(-t * 4.0) * clampf((len_s - t) * 60.0, 0.0, 1.0)
		out[i] = (lp + sin(ph * TAU) * 0.6) * env
	return out


static func _pluck(f: float, len_s: float) -> PackedFloat32Array:
	var n := int(RATE * len_s)
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / RATE
		p1 = fmod(p1 + f / RATE, 1.0)
		p2 = fmod(p2 + f * 1.006 / RATE, 1.0)
		var sq := (1.0 if p1 < 0.5 else -1.0) * 0.5 + (p2 * 2.0 - 1.0) * 0.5
		out[i] = sq * minf(1.0, t * 500.0) * exp(-t * 15.0)
	return out


static func _pad(sp: Dictionary, tones: Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var fs: Array = []
	for s in tones:
		fs.append(hz(sp, int(s), 2))
		fs.append(hz(sp, int(s), 2) * 1.004)
	var ph := []
	ph.resize(fs.size())
	ph.fill(0.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in fs.size():
			ph[k] = fmod(float(ph[k]) + float(fs[k]) / RATE, 1.0)
			v += float(ph[k]) * 2.0 - 1.0
		lp += (v / fs.size() - lp) * 0.06
		out[i] = lp * minf(1.0, t * 3.0) * clampf((float(n - i) / RATE) * 12.0, 0.0, 1.0)
	return out


static func _riser(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x415E
	var lp := 0.0
	for i in n:
		var u := float(i) / n
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.02 + 0.5 * u * u)
		out[i] = lp * u * u
	return out
