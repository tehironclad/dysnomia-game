class_name Cues
extends RefCounted
## Event cues (WP 7.3), each tied to a chain event: a Su cascade (bars moved),
## a heartbeat (Beat confirmed), a shimmer (a new territory), a tick (a room or
## Void line), a low tone (a write failed). Rendered once on first use and kept;
## played one-shot on the SFX bus.

const RATE := 22050
const DEFS := {
	# [[freq, start_s, dur_s, amp], …]
	"cascade": [[523.25, 0.0, 0.35, 0.3], [659.25, 0.08, 0.35, 0.25], [783.99, 0.16, 0.45, 0.22], [1046.5, 0.24, 0.6, 0.18]],
	"beat": [[55.0, 0.0, 0.22, 0.7], [110.0, 0.0, 0.12, 0.3], [55.0, 0.32, 0.26, 0.6], [110.0, 0.32, 0.14, 0.25]],
	"founded": [[1318.5, 0.0, 1.2, 0.12], [1760.0, 0.15, 1.1, 0.10], [2093.0, 0.3, 1.0, 0.08], [2637.0, 0.45, 0.9, 0.06]],
	"line": [[880.0, 0.0, 0.09, 0.18], [1320.0, 0.05, 0.08, 0.12]],
	"mention": [[987.77, 0.0, 0.14, 0.18], [1318.5, 0.09, 0.16, 0.16], [1975.5, 0.18, 0.3, 0.1]],
	"fail": [[146.8, 0.0, 0.5, 0.3], [138.6, 0.0, 0.5, 0.25]],
	"confirm": [[659.25, 0.0, 0.18, 0.22], [987.77, 0.1, 0.35, 0.2]],
}

static var _cache := {}


static func stream(cue: String) -> AudioStreamWAV:
	if _cache.has(cue):
		return _cache[cue]
	var notes: Array = DEFS.get(cue, [])
	var dur := 0.0
	for nt in notes:
		dur = maxf(dur, float(nt[1]) + float(nt[2]))
	var n := int(RATE * (dur + 0.05))
	var buf := PackedFloat32Array()
	buf.resize(n)
	for nt in notes:
		var f: float = nt[0]
		var s0 := int(float(nt[1]) * RATE)
		var len := int(float(nt[2]) * RATE)
		var amp: float = nt[3]
		for i in len:
			if s0 + i >= n:
				break
			var t := float(i) / RATE
			var env := minf(1.0, t * 200.0) * exp(-4.5 * float(i) / len)
			buf[s0 + i] += amp * env * sin(TAU * f * t)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = pcm
	_cache[cue] = w
	return w


## One-shot on the SFX bus, parented to `at` (freed when done).
static func play(at: Node, cue: String) -> void:
	if at == null or not at.is_inside_tree() or not DEFS.has(cue):
		return
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = stream(cue)
	at.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
