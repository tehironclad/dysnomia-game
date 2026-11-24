class_name FairSfx
extends RefCounted
## The midway's sounds, synthesised (no sample files): each one is rendered once into an
## AudioStreamWAV on first use (a few ms of GDScript) and kept. Played one-shot on the SFX bus.
##
##   thud   the mallet on the pad          bell     the striker's bell (inharmonic partials)
##   whoosh a throw leaving the hand       clack    a puck / ring landing
##   smash  a crystal shattering           bang     the counter gun
##   pop    a score pop-up                 coin     a bonus target
##   buzz   a wrong one                    tick     the wheel's clapper
##   flip   a card turning                 aww      a near miss (a falling "ohh")
##   cheer  the crowd                      fanfare  a grand prize
##   streak a rising chime (pitch it by the streak)

const RATE := 22050

static var _cache := {}


static func stream(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var buf := _render(id)
	var pcm := PackedByteArray()
	pcm.resize(buf.size() * 2)
	for i in buf.size():
		pcm.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = pcm
	_cache[id] = w
	return w


## One-shot, parented to `at` (freed when done). pitch 1 = as rendered.
static func play(at: Node, id: String, pitch: float = 1.0, db: float = 0.0) -> void:
	if at == null or not at.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer.new()
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.stream = stream(id)
	p.pitch_scale = pitch
	p.volume_db = db
	at.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * sec))
	return b


## A decaying sine (optionally sweeping from f0 to f1) added into b.
static func _tone(b: PackedFloat32Array, f0: float, f1: float, start: float, dur: float, amp: float, decay: float = 5.0, square: bool = false) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var u := float(i) / n
		var f := lerpf(f0, f1, u)
		ph += TAU * f / RATE
		var v := sin(ph)
		if square:
			v = signf(v) * 0.6
		var env := minf(1.0, float(i) / (RATE * 0.004)) * exp(-decay * u)
		b[s0 + i] += amp * env * v


## Noise through a one-pole low-pass (lp 0..1, higher = brighter), optionally high-passed.
static func _noise(b: PackedFloat32Array, start: float, dur: float, amp: float, lp: float, decay: float, hp: bool = false, seed_v: int = 1, attack: float = 0.003) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var y := 0.0
	for i in n:
		if s0 + i >= b.size():
			break
		var x := rng.randf_range(-1.0, 1.0)
		y += lp * (x - y)
		var v := (x - y) if hp else y
		var u := float(i) / n
		var env := minf(1.0, float(i) / (RATE * attack)) * exp(-decay * u)
		b[s0 + i] += amp * env * v


static func _render(id: String) -> PackedFloat32Array:
	var b: PackedFloat32Array
	match id:
		"thud":
			b = _buf(0.45)
			_tone(b, 120.0, 42.0, 0.0, 0.4, 0.9, 6.0)
			_noise(b, 0.0, 0.08, 0.6, 0.25, 8.0, false, 3)
			_tone(b, 900.0, 600.0, 0.0, 0.03, 0.25, 9.0)
		"bell":
			b = _buf(2.6)
			for p in [[1.0, 0.5], [2.76, 0.3], [5.40, 0.18], [8.93, 0.1], [2.0, 0.22]]:
				_tone(b, 1046.5 * float(p[0]), 1046.5 * float(p[0]), 0.0, 2.5, float(p[1]) * 0.7, 4.0 + float(p[0]) * 0.6)
			_noise(b, 0.0, 0.02, 0.3, 0.9, 6.0, true, 5)
		"whoosh":
			b = _buf(0.4)
			_noise(b, 0.0, 0.38, 0.55, 0.12, 2.5, false, 9, 0.12)
		"clack":
			b = _buf(0.2)
			_noise(b, 0.0, 0.05, 0.6, 0.7, 9.0, true, 11)
			_tone(b, 1250.0, 1100.0, 0.0, 0.12, 0.35, 9.0)
			_tone(b, 380.0, 300.0, 0.0, 0.1, 0.3, 8.0)
		"smash":
			b = _buf(0.9)
			_noise(b, 0.0, 0.85, 0.7, 0.85, 4.0, true, 13)
			var rng := RandomNumberGenerator.new()
			rng.seed = 17
			for i in 14:
				var f := rng.randf_range(2500.0, 7000.0)
				_tone(b, f, f, rng.randf_range(0.0, 0.25), 0.35, 0.12, 7.0)
		"bang":
			b = _buf(0.5)
			_noise(b, 0.0, 0.3, 1.0, 0.5, 9.0, false, 19)
			_tone(b, 160.0, 50.0, 0.0, 0.25, 0.8, 7.0)
		"pop":
			b = _buf(0.18)
			_tone(b, 420.0, 1300.0, 0.0, 0.14, 0.5, 4.0)
		"coin":
			b = _buf(0.5)
			_tone(b, 987.8, 987.8, 0.0, 0.08, 0.35, 1.0, true)
			_tone(b, 1318.5, 1318.5, 0.07, 0.4, 0.35, 4.0, true)
		"buzz":
			b = _buf(0.45)
			_tone(b, 150.0, 120.0, 0.0, 0.4, 0.5, 2.0, true)
			_tone(b, 155.0, 125.0, 0.0, 0.4, 0.4, 2.0, true)
		"tick":
			b = _buf(0.05)
			_noise(b, 0.0, 0.02, 0.5, 0.8, 9.0, true, 23)
			_tone(b, 2200.0, 2000.0, 0.0, 0.03, 0.3, 8.0)
		"flip":
			b = _buf(0.22)
			_noise(b, 0.0, 0.2, 0.5, 0.4, 3.0, true, 29, 0.05)
		"aww":
			b = _buf(1.1)
			for k in 6:
				var f := 210.0 + k * 37.0
				_tone(b, f, f * 0.72, 0.02 * k, 1.0, 0.09, 2.2)
			_noise(b, 0.0, 1.0, 0.18, 0.08, 2.5, false, 31, 0.1)
		"cheer":
			b = _buf(2.8)
			_noise(b, 0.0, 2.75, 0.5, 0.18, 1.4, false, 37, 0.15)
			_noise(b, 0.0, 2.75, 0.25, 0.6, 1.6, true, 41, 0.1)
			var rng := RandomNumberGenerator.new()
			rng.seed = 43
			for i in 46:  # claps and whistles
				_noise(b, rng.randf_range(0.0, 2.3), 0.04, rng.randf_range(0.3, 0.6), 0.9, 7.0, true, 50 + i)
			for i in 3:
				var f := rng.randf_range(1800.0, 2600.0)
				_tone(b, f, f * 1.25, rng.randf_range(0.1, 1.2), 0.45, 0.12, 1.5)
		"fanfare":
			b = _buf(1.6)
			var notes := [523.25, 659.25, 783.99, 1046.5]
			for i in notes.size():
				_tone(b, notes[i], notes[i], i * 0.11, 0.5 if i < 3 else 1.2, 0.28, 2.5, true)
				_tone(b, notes[i] * 2.0, notes[i] * 2.0, i * 0.11, 0.4 if i < 3 else 1.0, 0.1, 3.0)
		"streak":
			b = _buf(0.45)
			_tone(b, 880.0, 880.0, 0.0, 0.2, 0.3, 4.0)
			_tone(b, 1318.5, 1318.5, 0.06, 0.38, 0.3, 4.0)
		_:
			b = _buf(0.05)
	return b
