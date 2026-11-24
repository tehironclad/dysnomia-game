class_name MinigameSfx
## Tiny procedural sound kit for the Cantina tables. No asset files: each cue is a short
## 16-bit mono PCM clip synthesised once and cached. Cheap enough to fire on every tick.
##   MinigameSfx.play(self, "win")
## Cues: tick, roll, land, win, big, jackpot, bust, flip, match, miss, coin, nudge, alarm

const RATE := 22050

static var _cache: Dictionary = {}
static var muted: bool = false


static func play(owner: Node, cue: String, volume_db: float = -10.0, pitch: float = 1.0) -> void:
	if muted or owner == null or not owner.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var stream := _stream(cue)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	owner.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _stream(cue: String) -> AudioStreamWAV:
	if _cache.has(cue):
		return _cache[cue]
	var notes: Array = []  # [freq, dur, wave] — wave: 0 sine, 1 square, 2 noise
	match cue:
		"tick": notes = [[1400.0, 0.025, 1]]
		"roll": notes = [[0.0, 0.05, 2]]
		"land": notes = [[220.0, 0.06, 0], [0.0, 0.03, 2]]
		"flip": notes = [[900.0, 0.03, 1]]
		"coin": notes = [[988.0, 0.05, 1], [1319.0, 0.09, 1]]
		"match": notes = [[660.0, 0.07, 0], [990.0, 0.12, 0]]
		"miss": notes = [[300.0, 0.08, 1], [240.0, 0.1, 1]]
		"win": notes = [[523.0, 0.08, 0], [659.0, 0.08, 0], [784.0, 0.16, 0]]
		"big": notes = [[523.0, 0.07, 1], [659.0, 0.07, 1], [784.0, 0.07, 1], [1047.0, 0.25, 0]]
		"jackpot": notes = [[523.0, 0.06, 1], [659.0, 0.06, 1], [784.0, 0.06, 1], [1047.0, 0.06, 1],
			[784.0, 0.06, 1], [1047.0, 0.06, 1], [1319.0, 0.35, 0]]
		"bust": notes = [[392.0, 0.1, 1], [311.0, 0.1, 1], [233.0, 0.25, 1]]
		"nudge": notes = [[700.0, 0.04, 1], [500.0, 0.04, 1]]
		"alarm": notes = [[880.0, 0.06, 1], [0.0, 0.04, 0], [880.0, 0.06, 1]]
		_: return null
	var data := PackedByteArray()
	var noise := RandomNumberGenerator.new()
	noise.seed = 369
	for n in notes:
		var f: float = n[0]
		var count := int(float(n[1]) * RATE)
		var phase := 0.0
		for i in count:
			var t := float(i) / float(count)
			var env := minf(1.0, t * 30.0) * pow(1.0 - t, 1.6)
			var s := 0.0
			match int(n[2]):
				0: s = sin(phase * TAU)
				1: s = 0.55 if fmod(phase, 1.0) < 0.5 else -0.55
				2: s = noise.randf_range(-0.7, 0.7)
			if f <= 0.0 and int(n[2]) != 2:
				s = 0.0
			phase += f / RATE
			var v := clampi(int(s * env * 22000.0), -32768, 32767)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_cache[cue] = w
	return w
