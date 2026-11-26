class_name RemotePlayer
extends Node3D
## Another player in this territory (Net): a HumanAvatar driven by the
## interpolated pose, a name tag, a speaking mark, and their voice played at
## the avatar (AudioStreamPlayer3D + AudioStreamGenerator). A signed-in player
## registers with ChatFeed as a speaker, so ChatLife floats their chat bubbles
## (free "say" lines and on-chain lines) over this avatar.
## Uses HumanAvatar's public API only (set_head, set_body, update_movement,
## set_seated). Someone driving or on a ride is drawn seated (simplified).

const TAG_Y := 2.02
const VOICE_RATE := 16000.0
const PREFILL_S := 0.08  ## voice queued before playback starts (the jitter buffer)

var peer_id := -1
var wallet := ""
var display_name := ""
## Read by HumanAvatar (its parent's crouch).
var is_crouching := false

var avatar: HumanAvatar
var tag: Label3D
var voice: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _voice_t := 0.0
var _voice_last_ms := -100000
var _voice_cap := 0
var _primed := false
var _prefill := PackedVector2Array()
var _flag_speaking := false
var _seated := false
var _head := ""


func setup(info: Dictionary) -> void:
	peer_id = int(info.get("id", -1))
	avatar = HumanAvatar.new()
	avatar.civilian = true  # ~16 meshes, like the pub's regulars
	avatar.name = "Avatar"
	add_child(avatar)
	# Bumps (NetBump): run into them and they stumble (never fall); they knock props too.
	Stumble.attach(avatar, {"peer_id": peer_id, "max_level": BumpMath.STUMBLE})
	add_to_group("knock_bumper")
	# One line, a fixed size on screen (readable far off), just under ChatLife's bubbles (2.55 m).
	tag = _label(26, Color(0.86, 0.93, 1.0))
	tag.position.y = TAG_Y
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	voice = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VOICE_RATE
	gen.buffer_length = 0.4
	voice.stream = gen
	voice.position.y = 1.6
	voice.unit_size = 8.0
	# The server relays voice within its radius (the welcome says it; 40 m by default):
	# heard, fading, all the way out to it.
	var net := get_node_or_null("/root/Net")
	var radius: float = net.client.voice_radius if net and net.client else 40.0
	voice.max_distance = clampf(radius, 5.0, 500.0) + 5.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(voice)
	apply_info(info)


func _label(px: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.font_size = px
	l.outline_size = 10
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.render_priority = 1
	l.layers = 2
	add_child(l)
	return l


var _info := {}
var _claimed := ""  # the profile this player's game last sent (name|head): a change re-reads their LAU


## Name, wallet and look from the server's peer record (also when a peer signs in
## or changes LAU mid-session: the server sends S_PEER again). The name shown is
## the chain's name for the server-verified wallet (NetNames, read by Net.names),
## never the name the player's game claims; the short wallet is always on the tag.
func apply_info(info: Dictionary) -> void:
	_info = info
	var w := String(info.get("wallet", ""))
	var net := get_node_or_null("/root/Net")
	var names: LauNames = net.names if net else null
	if w != wallet:
		var chat_feed := get_node_or_null("/root/ChatFeed")
		if chat_feed and wallet != "":
			chat_feed.unregister_speaker(wallet)
		if chat_feed and w != "":
			chat_feed.register_speaker(w, self)
		if names and not names.resolved.is_connected(_on_name):
			names.resolved.connect(_on_name)
	var claimed := "%s|%s" % [info.get("name", ""), info.get("head", "")]
	if names and w != "" and w == wallet and claimed != _claimed:
		names.refresh(w)  # they switched LAU or picked another head: read their name again
	_claimed = claimed
	wallet = w
	var guest: bool = info.get("guest", true) or wallet == ""
	var rec: Dictionary = names.record(wallet) if names and not guest else {}
	display_name = NetNames.shown(wallet, rec) if not guest else ""
	_tag_text = NetNames.tag(wallet, guest, rec)
	_tag_col = Color(0.7, 0.74, 0.8) if guest else Color(0.86, 0.93, 1.0)
	_speaking = not _speaking  # force a refresh
	_show_speaking(not _speaking)
	var head := NetNames.head(String(info.get("head", "")), rec, func(k): return AvatarHeads.KINDS.has(k))
	var acc: Array = info.get("acc", []) if info.get("acc") is Array else []
	var key := head + "|" + ",".join(acc) + "|" + String(info.get("body", "male"))
	if key != _head and avatar.is_inside_tree():
		_head = key
		avatar.set_body(String(info.get("body", "male")))
		avatar.set_head(head, acc)
	elif not avatar.is_inside_tree():
		avatar.ready.connect(func(): apply_info(info), CONNECT_ONE_SHOT)
	if avatar.is_inside_tree():
		# The outfit everyone sees comes from the wallet alone (Outfits.for_identity);
		# a synced "outfit" kind (the player's own pick) wins once the server carries one.
		var o := Outfits.for_identity(wallet)
		var synced := String(info.get("outfit", ""))
		avatar.set_outfit(synced if Outfits.DESIGNS.has(synced) else String(o["kind"]), int(o["seed"]))


## Net.names read a wallet: if it is this player's, the tag (and head) follow.
func _on_name(w: String) -> void:
	if w == wallet and wallet != "" and is_inside_tree():
		apply_info(_info)


## The tag's text (tests and tools).
func tag_text() -> String:
	return _tag_text


## A pose from NetInterp.sample().
func apply_pose(s: Dictionary) -> void:
	if s.is_empty():
		return
	global_position = s["pos"]
	avatar.rotation.y = float(s["yaw"])
	var flags: int = s["flags"]
	is_crouching = flags & NetProto.F_CROUCH != 0
	_flag_speaking = flags & NetProto.F_SPEAKING != 0
	var seated := flags & NetProto.F_SEATED != 0
	var anim: String = NetProto.ANIMS[int(s["anim"])]
	if seated != _seated:
		_seated = seated
		avatar.set_seated("Driving" if seated else "")
	avatar.hold_clip = anim if not seated else ""
	if not seated:
		avatar.update_movement(s["vel"], flags & NetProto.F_ON_FLOOR != 0, flags & NetProto.F_FLYING != 0)



## A decoded 20 ms voice frame. Frames arrive in bursts (the sender's and our frame
## rate, the network): a small jitter buffer (PREFILL_S) fills before playback starts,
## and again after the voice ran dry, so a late frame is a short wait instead of a
## click. Measured on localhost alone: frames 17 ms apart typically, up to 55 ms.
func play_voice(pcm: PackedFloat32Array, volume: float) -> void:
	_voice_t = 0.3
	_voice_last_ms = Time.get_ticks_msec()
	voice.volume_db = linear_to_db(maxf(volume, 0.001))
	var frames := PackedVector2Array()
	frames.resize(pcm.size())
	for i in pcm.size():
		frames[i] = Vector2(pcm[i], pcm[i])
	if not _primed:
		_prefill.append_array(frames)
		if _prefill.size() < int(PREFILL_S * VOICE_RATE):
			return
		_start_voice()
		return
	_push_voice(frames)


func _start_voice() -> void:
	if not voice.playing or _playback == null:
		voice.play()
		_playback = voice.get_stream_playback()
		_voice_cap = _playback.get_frames_available() if _playback else 0
	_primed = true
	var pre := _prefill
	_prefill = PackedVector2Array()
	_push_voice(pre)


func _push_voice(frames: PackedVector2Array) -> void:
	if _playback == null:
		return
	var room := _playback.get_frames_available()
	_playback.push_buffer(frames if frames.size() <= room else frames.slice(frames.size() - room))  # too far behind: keep the newest


## Jitter buffer upkeep (each frame): ran dry → fill again before playing on; a short
## tail waiting in the prefill is played once no more comes; silent for a while → stop.
func _voice_tick() -> void:
	var idle_ms := Time.get_ticks_msec() - _voice_last_ms
	if not _primed and not _prefill.is_empty() and idle_ms > int(PREFILL_S * 1000.0):
		_start_voice()  # the end of an utterance shorter than the prefill
	if _primed and _playback and _playback.get_frames_available() >= _voice_cap:
		_primed = false  # empty: the next frames fill the buffer again first
	if voice.playing and not _primed and _prefill.is_empty() and idle_ms > 2000:
		voice.stop()  # nothing to mix
		_playback = null


var _tag_text := ""
var _tag_col := Color.WHITE
var _speaking := false


## The speaking mark: "◉" before the name, in green, while they talk.
func _show_speaking(on: bool) -> void:
	if on == _speaking:
		return
	_speaking = on
	tag.text = ("◉ " + _tag_text) if on else _tag_text
	tag.modulate = Color(0.45, 1.0, 0.7) if on else _tag_col


func _exit_tree() -> void:
	var chat_feed := get_node_or_null("/root/ChatFeed")
	if chat_feed and wallet != "" and chat_feed.bubble_for(wallet) == self:
		chat_feed.unregister_speaker(wallet)


func _process(delta: float) -> void:
	_voice_tick()
	_voice_t = maxf(0.0, _voice_t - delta)
	_show_speaking(_voice_t > 0.0 or _flag_speaking)
