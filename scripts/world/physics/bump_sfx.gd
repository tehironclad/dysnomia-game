class_name BumpSfx
extends RefCounted
## The sounds of bumping into things, synthesised like FairSfx (its tone and
## noise helpers; no sample files), each rendered once on first use and played
## positionally (AudioStreamPlayer3D, freed when done). Silent headless.
##
##   wood   a crate or stool going over     metal  a bin or keg (inharmonic clang)
##   glass  a glass or bottle (a clink)     soft   something padded (a thump)
##   oof    someone bumped (a short falling voice-ish grunt)
##   thud   someone landing on the ground

const RATE := FairSfx.RATE

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


## One-shot at a global position, parented to `host` (freed when done).
## `strength` 0..1 sets the loudness; the pitch wanders a little each time.
static func play_at(host: Node, at: Vector3, id: String, strength: float = 1.0) -> void:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.stream = stream(id)
	p.pitch_scale = randf_range(0.88, 1.12)
	p.volume_db = linear_to_db(clampf(strength, 0.05, 1.0)) - 2.0
	p.unit_size = 6.0
	p.max_distance = 40.0
	host.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


static func _render(id: String) -> PackedFloat32Array:
	var b: PackedFloat32Array
	match id:
		"wood":
			b = FairSfx._buf(0.42)
			FairSfx._noise(b, 0.0, 0.06, 0.7, 0.35, 8.0, false, 61)
			FairSfx._tone(b, 210.0, 150.0, 0.0, 0.25, 0.7, 7.0)
			FairSfx._tone(b, 520.0, 470.0, 0.0, 0.12, 0.25, 9.0)
			FairSfx._noise(b, 0.16, 0.05, 0.35, 0.3, 8.0, false, 62)  # it lands
			FairSfx._tone(b, 180.0, 130.0, 0.16, 0.2, 0.4, 7.0)
		"metal":
			b = FairSfx._buf(0.8)
			FairSfx._noise(b, 0.0, 0.03, 0.5, 0.8, 9.0, true, 63)
			for p in [[410.0, 0.35], [1130.0, 0.22], [1873.0, 0.14], [2650.0, 0.08]]:
				FairSfx._tone(b, float(p[0]), float(p[0]) * 0.985, 0.0, 0.75, float(p[1]), 5.0)
			FairSfx._tone(b, 120.0, 70.0, 0.0, 0.2, 0.5, 8.0)
		"glass":
			b = FairSfx._buf(0.5)
			FairSfx._noise(b, 0.0, 0.015, 0.3, 0.9, 9.0, true, 65)
			FairSfx._tone(b, 2637.0, 2637.0, 0.0, 0.4, 0.3, 6.0)
			FairSfx._tone(b, 3951.0, 3951.0, 0.0, 0.3, 0.15, 7.0)
			FairSfx._tone(b, 3136.0, 3136.0, 0.12, 0.3, 0.14, 7.0)  # a second clink as it rolls
		"soft":
			b = FairSfx._buf(0.3)
			FairSfx._tone(b, 110.0, 60.0, 0.0, 0.28, 0.8, 7.0)
			FairSfx._noise(b, 0.0, 0.08, 0.4, 0.15, 7.0, false, 67)
		"oof":
			b = FairSfx._buf(0.38)
			# A short voiced grunt: a buzzy fundamental falling, two formant-ish tones over it.
			FairSfx._tone(b, 230.0, 150.0, 0.0, 0.34, 0.35, 3.5, true)
			FairSfx._tone(b, 690.0, 520.0, 0.0, 0.3, 0.18, 4.0)
			FairSfx._tone(b, 1150.0, 900.0, 0.0, 0.25, 0.08, 5.0)
			FairSfx._noise(b, 0.0, 0.3, 0.12, 0.2, 4.0, false, 69, 0.02)
		"thud":
			b = FairSfx._buf(0.4)
			FairSfx._tone(b, 95.0, 45.0, 0.0, 0.35, 0.9, 6.0)
			FairSfx._noise(b, 0.0, 0.1, 0.5, 0.2, 7.0, false, 71)
		_:
			b = FairSfx._buf(0.05)
	return b
