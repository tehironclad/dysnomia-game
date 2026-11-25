class_name VoiceLines
extends RefCounted
## Spoken lines with subtitles, ready for real recordings. Each line has an id and its words.
## If a recording exists at res://assets/audio/voices/<speaker>/<id>.ogg (or .wav, .mp3), it
## plays from the speaker (3D, on the SFX bus); the subtitle always shows. With no recording the
## subtitle shows alone: there is no synthesised voice.
##
## The owner means to record Sunny's real voice (2026-11-25): the files to record, and the words
## for each, are in assets/audio/voices/sunny/README.md (a test keeps it in step with SUNNY).
## A line's words are what the recording says; a subtitle may add a measured detail after them
## ("· block 26,103,442"), which is never voiced.

const ROOT := "res://assets/audio/voices/"
const EXTS := ["ogg", "wav", "mp3"]

## Sunny, behind the bar at Sunny's Pub. id → the words to record.
const SUNNY := {
	"greeting": "Welcome to Sunny's! Come on up to the bar, friend.",
	"come_closer": "Come up to the bar, friend. The menu's on the board.",
	"menu_open": "What'll it be? Every drink here is your own call, on the chain.",
	"order_taken": "Coming right up.",
	"payment_waiting": "Just need your say-so in the wallet, friend. Take your time.",
	"payment_failed": "Hm. That one didn't go through. No harm done; nothing was poured.",
	"pour": "Watch this.",
	"here_you_go": "Here you go. Enjoy.",
	"cheers": "Cheers!",
	"round_cheers": "A round for the house! Cheers, everyone!",
	"order_another": "Another one? The menu's right here.",
	"goodbye": "Come back soon. The lights stay on.",
	"idle_bottles": "These bottles won't polish themselves.",
	"idle_taps": "Every one of these taps runs straight to the chain.",
	"idle_sunflowers": "Sunflowers face the sun. Regulars face the bar.",
	"idle_pool": "Pool table's free, if you fancy a game.",
	"idle_quiet": "Quiet night. I like a quiet night.",
}
const IDLE_SUNNY := ["idle_bottles", "idle_taps", "idle_sunflowers", "idle_pool", "idle_quiet"]
const SPEAKERS := {"sunny": SUNNY}
const NAMES := {"sunny": "Sunny"}

static var _streams := {}  # "speaker/id" → AudioStream, or null once looked for and not found


## The words of a line ("" if there's no such line).
static func text(speaker: String, id: String) -> String:
	return String(SPEAKERS.get(speaker, {}).get(id, ""))


static func ids(speaker: String) -> Array:
	return SPEAKERS.get(speaker, {}).keys()


## The files a recording may be dropped in as, in the order they are looked for.
static func candidates(speaker: String, id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for e in EXTS:
		out.append("%s%s/%s.%s" % [ROOT, speaker, id, e])
	return out


## How long a subtitle stays when nothing is voiced: long enough to read (2.5–9 s).
static func reading_seconds(words: String) -> float:
	var n := words.split(" ", false).size()
	return clampf(1.4 + 0.36 * n, 2.5, 9.0)


## The recording, if there is one: an imported clip (the usual case), else a file dropped in
## without an import (.ogg / .wav / .mp3 read from disk). null if none. Looked up once.
static func stream(speaker: String, id: String) -> AudioStream:
	var key := speaker + "/" + id
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = null
	for p in candidates(speaker, id):
		if ResourceLoader.exists(p):
			s = load(p) as AudioStream
			if s:
				break
	if s == null:
		for p in candidates(speaker, id):
			if not FileAccess.file_exists(p):
				continue
			match p.get_extension():
				"ogg":
					s = AudioStreamOggVorbis.load_from_file(p)
				"wav":
					s = AudioStreamWAV.load_from_file(p)
				"mp3":
					var m := AudioStreamMP3.new()
					m.data = FileAccess.get_file_as_bytes(p)
					s = m
			if s:
				break
	_streams[key] = s
	return s


## Forget what was looked up (a recording was just added).
static func rescan() -> void:
	_streams.clear()


## Says a line: plays its recording from `at` if there is one. Returns {text, voiced, seconds}:
## the subtitle to show (the words, then `detail` if given) and how long to show it.
static func say(at: Node3D, speaker: String, id: String, detail: String = "") -> Dictionary:
	var words := text(speaker, id)
	var sub := words if detail == "" else (words + "  " + detail if words != "" else detail)
	var s := stream(speaker, id) if words != "" else null
	var secs := reading_seconds(sub)
	if s and at and at.is_inside_tree() and DisplayServer.get_name() != "headless":
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		p.unit_size = 6.0
		p.position = Vector3(0, 1.7, 0)  # the speaker's head
		at.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
		secs = maxf(secs, s.get_length() + 0.8)
	return {"text": sub, "voiced": s != null, "seconds": secs}
