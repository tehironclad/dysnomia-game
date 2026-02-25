extends Node3D
## Terrain-aware ambient soundscape for Dysnomia.
## Uses AudioStreamGenerator for procedural placeholder sounds — no asset files needed.
## Manages: suit breathing, footsteps (terrain-aware), wind hum, beat station hum.
##
## Performance: buffers are filled in small batches per frame (max 512 samples)
## to avoid blocking the main thread with thousands of trig calls.

var _player: CharacterBody3D
var _beat_station_pos: Vector3
var _territory_activity: float = 0.0

# Audio players
var _breathing: AudioStreamPlayer
var _footstep: AudioStreamPlayer3D
var _wind: AudioStreamPlayer
var _station_hum: AudioStreamPlayer3D

# State tracking
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.5
var _terrain_gen: Node3D

# Phase accumulators for continuous waveforms (avoids Time.get_ticks_msec per sample)
var _breath_phase: float = 0.0
var _wind_phase: float = 0.0
var _hum_phase_60: float = 0.0
var _hum_phase_120: float = 0.0
var _hum_phase_180: float = 0.0
var _hum_mod_phase: float = 0.0

# Max samples to push per frame per buffer — keeps CPU budget bounded
const MAX_SAMPLES_PER_FRAME: int = 512
const MIX_RATE: float = 11025.0  # Half rate — more than enough for ambient effects


func initialize(p_player: CharacterBody3D, terrain_gen: Node3D,
		beat_station_pos: Vector3) -> void:
	_player = p_player
	_terrain_gen = terrain_gen
	_beat_station_pos = beat_station_pos
	_setup_breathing()
	_setup_footstep()
	_setup_wind()
	_setup_station_hum()


func set_territory_activity(activity: float) -> void:
	_territory_activity = activity
	# Wind volume scales with activity
	if _wind:
		_wind.volume_db = lerpf(-40.0, -18.0, activity)


func _setup_breathing() -> void:
	_breathing = AudioStreamPlayer.new()
	_breathing.name = "SuitBreathing"
	_breathing.bus = &"Master"
	_breathing.volume_db = -28.0
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.5
	_breathing.stream = stream
	add_child(_breathing)
	_breathing.play()


func _setup_footstep() -> void:
	_footstep = AudioStreamPlayer3D.new()
	_footstep.name = "Footstep"
	_footstep.unit_size = 5.0
	_footstep.max_distance = 20.0
	_footstep.volume_db = -12.0
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.1
	_footstep.stream = stream
	add_child(_footstep)


func _setup_wind() -> void:
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	_wind.bus = &"Master"
	_wind.volume_db = -40.0  # Starts silent, scales with activity
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.5
	_wind.stream = stream
	add_child(_wind)
	_wind.play()


func _setup_station_hum() -> void:
	_station_hum = AudioStreamPlayer3D.new()
	_station_hum.name = "StationHum"
	_station_hum.unit_size = 8.0
	_station_hum.max_distance = 30.0
	_station_hum.volume_db = -15.0
	_station_hum.position = _beat_station_pos + Vector3(0, 5, 0)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.5
	_station_hum.stream = stream
	add_child(_station_hum)
	_station_hum.play()


func _process(delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		return

	_update_footsteps(delta)
	_fill_breathing_buffer()
	_fill_wind_buffer()
	_fill_station_hum_buffer()

	# Position footstep player at player feet
	if _footstep:
		_footstep.global_position = _player.global_position


func _update_footsteps(delta: float) -> void:
	if not _player:
		return

	var on_floor: bool = _player.is_on_floor()
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()

	if on_floor and speed > 1.0:
		# Adjust interval by speed — faster = more frequent footsteps
		_footstep_interval = clampf(0.8 / (speed * 0.15), 0.2, 0.8)
		_footstep_timer += delta
		if _footstep_timer >= _footstep_interval:
			_footstep_timer = 0.0
			_play_footstep()
	else:
		_footstep_timer = 0.0


func _play_footstep() -> void:
	if not _footstep:
		return
	# Determine terrain type at player position for sound variation
	var height: float = _player.global_position.y
	var slope: float = 0.5  # Default flat

	if _terrain_gen and is_instance_valid(_terrain_gen) and _terrain_gen.has_method("get_height_at"):
		var px := _player.global_position.x
		var pz := _player.global_position.z
		var h_center: float = _terrain_gen.get_height_at(px, pz)
		var h_right: float = _terrain_gen.get_height_at(px + 0.5, pz)
		var h_fwd: float = _terrain_gen.get_height_at(px, pz + 0.5)
		slope = absf(h_right - h_center) + absf(h_fwd - h_center)

	# Play short procedural click/crunch
	if not _footstep.playing:
		_footstep.play()

	var playback = _footstep.get_stream_playback() as AudioStreamGeneratorPlayback
	if not playback:
		return
	# Generate a short burst based on terrain type
	var frames := int(MIX_RATE * 0.06)  # 60ms burst
	var base_freq := 200.0  # Soft crunch for flat regolith
	if slope > 1.0:
		base_freq = 800.0  # Metallic clicks on steep slope
	elif height < -3.0:
		base_freq = 100.0  # Muffled thuds in craters

	var count := mini(frames, playback.get_frames_available())
	var inv_rate := 1.0 / MIX_RATE
	for i in range(count):
		var t := float(i) * inv_rate
		var envelope := maxf(0.0, 1.0 - t * 16.0)  # Quick decay
		var noise_val := randf() * 2.0 - 1.0
		var tone := sin(t * base_freq * TAU) * 0.3
		var sample := (noise_val * 0.7 + tone * 0.3) * envelope * 0.15
		playback.push_frame(Vector2(sample, sample))


func _fill_breathing_buffer() -> void:
	if not _breathing or not _breathing.playing:
		return
	var playback = _breathing.get_stream_playback() as AudioStreamGeneratorPlayback
	if not playback:
		return
	var frames_avail := playback.get_frames_available()
	if frames_avail == 0:
		return

	# Clamp to budget — remainder will be filled next frame
	var count := mini(frames_avail, MAX_SAMPLES_PER_FRAME)

	# Phase-accumulator approach: one sin() per sample, no Time.get_ticks_msec()
	var phase_step := TAU / (MIX_RATE * 4.0)  # 4-second breath cycle
	for i in range(count):
		_breath_phase += phase_step
		var breath_env := absf(sin(_breath_phase)) * 0.3
		var noise_val := randf() * 2.0 - 1.0
		var sample := noise_val * breath_env * 0.05
		playback.push_frame(Vector2(sample, sample))

	# Keep phase bounded to avoid float precision loss
	if _breath_phase > TAU:
		_breath_phase -= TAU


func _fill_wind_buffer() -> void:
	if not _wind or not _wind.playing or _territory_activity < 0.02:
		return
	var playback = _wind.get_stream_playback() as AudioStreamGeneratorPlayback
	if not playback:
		return
	var frames_avail := playback.get_frames_available()
	if frames_avail == 0:
		return

	var count := mini(frames_avail, MAX_SAMPLES_PER_FRAME)
	var phase_step := 0.3 / MIX_RATE  # Gust oscillation frequency
	var act := _territory_activity

	for i in range(count):
		_wind_phase += phase_step
		var noise_val := randf() * 2.0 - 1.0
		var gust := sin(_wind_phase * TAU) * 0.5 + 0.5
		var sample := noise_val * gust * 0.04 * act
		playback.push_frame(Vector2(sample, sample))

	if _wind_phase > 1.0:
		_wind_phase -= 1.0


func _fill_station_hum_buffer() -> void:
	if not _station_hum or not _station_hum.playing:
		return
	var playback = _station_hum.get_stream_playback() as AudioStreamGeneratorPlayback
	if not playback:
		return
	var frames_avail := playback.get_frames_available()
	if frames_avail == 0:
		return

	var count := mini(frames_avail, MAX_SAMPLES_PER_FRAME)

	# Phase increments for each harmonic (per sample)
	var step_60 := 60.0 * TAU / MIX_RATE
	var step_120 := 120.0 * TAU / MIX_RATE
	var step_180 := 180.0 * TAU / MIX_RATE
	var step_mod := 0.7 * TAU / MIX_RATE

	for i in range(count):
		_hum_phase_60 += step_60
		_hum_phase_120 += step_120
		_hum_phase_180 += step_180
		_hum_mod_phase += step_mod

		# Low drone with harmonics
		var hum := sin(_hum_phase_60) * 0.3
		hum += sin(_hum_phase_120) * 0.15
		hum += sin(_hum_phase_180) * 0.08
		# Slow modulation
		var mod := sin(_hum_mod_phase) * 0.3 + 0.7
		var sample := hum * mod * 0.06
		playback.push_frame(Vector2(sample, sample))

	# Keep phases bounded
	if _hum_phase_60 > TAU:
		_hum_phase_60 = fmod(_hum_phase_60, TAU)
	if _hum_phase_120 > TAU:
		_hum_phase_120 = fmod(_hum_phase_120, TAU)
	if _hum_phase_180 > TAU:
		_hum_phase_180 = fmod(_hum_phase_180, TAU)
	if _hum_mod_phase > TAU:
		_hum_mod_phase = fmod(_hum_mod_phase, TAU)
