class_name RaveMusic
extends AudioStreamPlayer3D
## The arcade's DJ set: RaveTrack's synthesised loop, streamed live through an AudioStreamGenerator
## from the DJ booth (positional), on the Music bus (the game's music volume applies).
##
## A worker thread renders the cycle's distinct bars once (a second or so, the first bar first);
## each frame tops the generator up with the next bars of the 16-bar arrangement. The beat clock
## (`clock`, `beats()`, `beat_phase()`, the `beat` signal) follows what the speakers are playing:
## frames pushed minus frames still queued. With no audio device (headless, a dummy driver) it runs on
## wall time, so the lights and the dancers keep the same beat either way.

signal beat(n: int)  ## every beat (n counts from the start of the set)
signal bar_started(n: int)

const BUFFER_S := 0.3
const DUCK_DB := -13.0  ## inside a cabinet dive the room goes quiet, not silent
const BASE_DB := -4.0

var style: Dictionary = {}
var sp: Dictionary = {}
var clock := 0.0  ## seconds into the set (the beat clock)
var ducked := false
var _gen: AudioStreamGenerator
var _pb: AudioStreamGeneratorPlayback
var _bars := {}  # key → PackedVector2Array
var _mutex := Mutex.new()
var _thread: Thread
var _quit := false
var _next_bar := 0  ## the bar being pushed
var _offset := 0  ## frames of it already pushed
var _pushed := 0  ## frames pushed in all
var _started := false
var _last_beat := -1
var _last_bar := -1
var _consumed_at := 0  ## _pushed - queued, last frame (to see if the device plays)
var _idle_s := 0.0
var _start_frames := 0  ## the set's frames before the bar it started at


## `start_bar`: begin the set at this bar (previews: --rave-bar=N shows the drop at once).
func setup(p_style: Dictionary, start_bar: int = 0) -> void:
	style = p_style
	_next_bar = maxi(0, start_bar)
	sp = RaveTrack.spec(style)
	name = "RaveMusic"
	bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	volume_db = BASE_DB
	unit_size = 9.0
	max_distance = 60.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	panning_strength = 0.6
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = RaveTrack.RATE
	_gen.buffer_length = BUFFER_S
	stream = _gen
	_thread = Thread.new()
	_thread.start(_render_all.bind(sp.duplicate()))


func bpm() -> float:
	return float(sp.get("bpm", 124))


## Beats into the set (fractional).
func beats() -> float:
	return clock * bpm() / 60.0


## 0..1 through the current beat (0 = the kick).
func beat_phase() -> float:
	return fposmod(beats(), 1.0)


func bar() -> int:
	return int(floor(beats() / 4.0))


func section() -> String:
	return RaveTrack.section(bar())


## Inside a cabinet dive: quieter (eased in _process).
func set_ducked(on: bool) -> void:
	ducked = on


func _render_all(p_sp: Dictionary) -> void:
	var kit := RaveTrack.make_kit(p_sp)
	for k in RaveTrack.keys_in_order():
		if _quit:
			return
		var parts: PackedStringArray = String(k).split(":")
		var frames := RaveTrack.render(p_sp, parts[0], int(parts[1]), kit)
		_mutex.lock()
		_bars[k] = frames
		_mutex.unlock()


func _bar_frames(b: int) -> PackedVector2Array:
	_mutex.lock()
	var f: PackedVector2Array = _bars.get(RaveTrack.bar_key(b), PackedVector2Array())
	if f.is_empty():
		# Not rendered yet: the same chord's intro bar stands in (rendered first).
		f = _bars.get("intro:%d" % RaveTrack.chord_of(b), PackedVector2Array())
	_mutex.unlock()
	return f


func _process(delta: float) -> void:
	var before := clock
	clock += delta
	if not _started:
		if not _bar_frames(_next_bar).is_empty():
			_started = true
			clock = _next_bar * 4.0 * 60.0 / bpm()
			before = clock
			_start_frames = _next_bar * RaveTrack.bar_samples(sp)
			_consumed_at = _start_frames
			play()
			_pb = get_stream_playback() as AudioStreamGeneratorPlayback
	if _pb:
		_fill()
		# Follow the speakers: what has been played = pushed − still queued.
		var queued := int(_gen.buffer_length * _gen.mix_rate) - _pb.get_frames_available()
		var played := _pushed - maxi(0, queued) + _start_frames
		if played != _consumed_at:
			_consumed_at = played
			_idle_s = 0.0
			var audio_clock := float(played) / RaveTrack.RATE - AudioServer.get_output_latency()
			if absf(audio_clock - clock) > 0.25:
				clock = audio_clock  # a real gap (a hitch, the start): jump
				before = clock
			else:
				clock = lerpf(clock, audio_clock, 0.08)
		else:
			_idle_s += delta  # a dummy driver: wall time keeps the beat
	clock = maxf(clock, before)  # small corrections never run the lights backwards
	var want := BASE_DB + (DUCK_DB if ducked else 0.0)
	volume_db = move_toward(volume_db, want, delta * 30.0)
	var b := int(floor(beats()))
	if b != _last_beat:
		_last_beat = b
		beat.emit(b)
		var br := b / 4
		if br != _last_bar:
			_last_bar = br
			bar_started.emit(br)


func _fill() -> void:
	var room := _pb.get_frames_available()
	var guard := 0
	while room > 0 and guard < 8:
		guard += 1
		var f := _bar_frames(_next_bar)
		if f.is_empty():
			return
		var take := mini(room, f.size() - _offset)
		if take <= 0:
			_next_bar += 1
			_offset = 0
			continue
		_pb.push_buffer(f.slice(_offset, _offset + take))
		_pushed += take
		_offset += take
		room -= take
		if _offset >= f.size():
			_next_bar += 1
			_offset = 0


func _exit_tree() -> void:
	_quit = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
