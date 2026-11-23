class_name TerritoryScore
extends AudioStreamPlayer
## A territory's score (WP 7.3): a slow drone computed from its own numbers,
## rendered once into a looping AudioStreamWAV and cached under
## user://cache/score. Nothing is synthesised per frame.
##
## - root pitch: Entropy mod 24 semitones above A1 (55 Hz);
## - the chord: four partials whose intervals are picked by the Julia constant
##   c (its two coordinates choose from consonant ratios);
## - each partial breathes on its own slow LFO; every frequency is snapped to a
##   whole number of cycles per loop, so the loop is seamless.
## The same territory always sounds the same, for every visitor.

const RATE := 16000
const LOOP_S := 8.0
const VERSION := 1
const CACHE_DIR := "user://cache/score"
const RATIOS := [1.0, 1.5, 2.0, 2.5, 3.0, 3.75, 4.0, 4.5, 5.0, 6.0]


var _thread: Thread


## Plays the score; a first visit renders it on a worker thread (cached after).
func play_for(address: String, params: Dictionary, entropy_decimal: String) -> void:
	bus = "Music"
	volume_db = -10.0
	var cached := load_cached(address)
	if cached:
		stream = cached
		play()
		return
	_thread = Thread.new()
	_thread.start(func():
		var w := render(voices(params, entropy_decimal))
		_ready_to_play.call_deferred(address, w))


func _ready_to_play(address: String, w: AudioStreamWAV) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	w.save_to_wav(_path(address))
	if is_inside_tree():
		stream = w
		play()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


static func _path(address: String) -> String:
	return "%s/%s_v%d.wav" % [CACHE_DIR, address.to_lower(), VERSION]


static func load_cached(address: String) -> AudioStreamWAV:
	if not FileAccess.file_exists(_path(address)):
		return null
	var w := AudioStreamWAV.load_from_file(_path(address))
	if w:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(RATE * LOOP_S)
	return w


## Pure: the partials {freq, amp, lfo} for a territory (snapped to the loop).
static func voices(params: Dictionary, entropy_decimal: String) -> Array:
	var e := BigInt.from_decimal(entropy_decimal)
	var semis: int = int(BigInt.divmod_small(e, 24)[1]) if not BigInt.is_zero(e) else 0
	var root := 55.0 * pow(2.0, float(semis) / 12.0)
	var c: Array = params.get("c", [0.0, 0.0])
	var a := int(absf(float(c[0])) * 1000.0)
	var b := int(absf(float(c[1])) * 1000.0)
	var picks := [0, 2 + a % 3, 4 + b % 3, 7 + (a + b) % 3]
	var out: Array = []
	for i in picks.size():
		var f: float = root * RATIOS[picks[i]]
		f = roundf(f * LOOP_S) / LOOP_S  # whole cycles per loop
		var lfo := (1.0 + float((a + b * (i + 1)) % 3)) / LOOP_S  # 1..3 breaths per loop
		out.append({"freq": f, "amp": 0.34 / (1.0 + i * 0.55), "lfo": lfo, "phase": float(i) * 1.7})
	return out


static func render(vs: Array) -> AudioStreamWAV:
	var n := int(RATE * LOOP_S)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var incs: Array = []
	var lfos: Array = []
	for v in vs:
		incs.append(TAU * float(v["freq"]) / RATE)
		lfos.append(TAU * float(v["lfo"]) / RATE)
	for i in n:
		var s := 0.0
		for k in vs.size():
			var env := 0.55 + 0.45 * sin(lfos[k] * i + float(vs[k]["phase"]))
			s += float(vs[k]["amp"]) * env * sin(incs[k] * i)
		pcm.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = pcm
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


