extends Node
## Push-to-talk voice capture for Net (opt-in: Settings → Online & voice).
## AudioStreamMicrophone on a muted bus with an AudioEffectCapture; frames are
## resampled to 16 kHz mono, cut into 20 ms frames, IMA-ADPCM encoded
## (VoiceCodec) and sent only while the push_to_talk action is held.
## The mic is not opened at all until the player turns it on.

const BUS := "NetMic"

var talking := false
var level := 0.0           # last frame's RMS (the local talking meter)
var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _rs: VoiceCodec.Resampler
var _buf := PackedFloat32Array()
var _seq := 0
var _adpcm_state := [0, 0]
var _open := false


func _process(_delta: float) -> void:
	var want: bool = Net.mic_enabled and Net.is_online()
	if want != _open:
		_set_open(want)
	if not _open:
		_set_talking(false)
		return
	var held := Input.is_action_pressed("push_to_talk") and not _typing() and Net.can_talk()
	var n := _capture.get_frames_available()
	if n > 0:
		var pcm := _rs.push(_capture.get_buffer(n))
		if held:
			_buf.append_array(pcm)
	if not held:
		_buf.clear()
		_adpcm_state = [0, 0]
	_set_talking(held)
	while _buf.size() >= NetProto.VOICE_FRAME:
		var frame := _buf.slice(0, NetProto.VOICE_FRAME)
		_buf = _buf.slice(NetProto.VOICE_FRAME)
		level = VoiceCodec.level(frame)
		Net.client.send_voice(_seq, NetProto.CODEC_ADPCM, VoiceCodec.encode_adpcm(frame, _adpcm_state))
		_seq = (_seq + 1) & 0xFFFF


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _set_talking(on: bool) -> void:
	if on != talking:
		talking = on
		Net.speaking_changed.emit(on)


func _set_open(on: bool) -> void:
	_open = on
	if not on:
		if _player:
			_player.stop()
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		push_warning("[Net] audio input is disabled in project settings")
		_open = false
		Net.mic_enabled = false
		return
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
		AudioServer.set_bus_mute(idx, true)  # never hear yourself
	_capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	apply_device()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS
		add_child(_player)
	_rs = VoiceCodec.Resampler.new(AudioServer.get_mix_rate(), NetProto.VOICE_RATE)
	_capture.clear_buffer()
	_player.play()


func apply_device() -> void:
	if Net.mic_device in AudioServer.get_input_device_list():
		AudioServer.input_device = Net.mic_device
