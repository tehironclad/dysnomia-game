extends Node
## Solar flare event — intensifies the sun, overlays a warm orange screen tint,
## and pulses chromatic aberration periodically.
## Restores original sun state on cleanup.
## Spawned and managed by WeatherSystem.

const SUN_ENERGY_MULTIPLIER: float = 3.0     # How much to boost sun energy
const TINT_COLOR: Color = Color(1.0, 0.7, 0.3, 0.08)  # Warm orange overlay
const TINT_PEAK_ALPHA: float = 0.12          # Maximum tint opacity at full intensity
const PULSE_INTERVAL: float = 5.0            # Seconds between chromatic pulses
const PULSE_DURATION: float = 0.6            # How long each chromatic pulse lasts
const INTENSITY_VARIATION_SPEED: float = 0.8  # How fast intensity oscillates

var _sun: DirectionalLight3D
var _player: Node3D
var _original_energy: float = 1.0
var _original_color: Color = Color.WHITE
var _screen_tint: ColorRect
var _elapsed: float = 0.0
var _duration: float = 60.0
var _pulse_timer: float = 3.0   # First pulse after 3s
var _pulse_elapsed: float = -1.0  # -1 = not pulsing
var _chromatic_rect: ColorRect


func set_duration(d: float) -> void:
	_duration = maxf(d, 10.0)


func initialize(player: Node3D, sun: DirectionalLight3D) -> void:
	_player = player
	_sun = sun

	# Store original sun state for restoration
	if _sun and is_instance_valid(_sun):
		_original_energy = _sun.light_energy
		_original_color = _sun.light_color

	# Create screen tint overlay (warm orange wash)
	_create_screen_tint()

	# Create chromatic aberration overlay
	_create_chromatic_overlay()


func _create_screen_tint() -> void:
	## Fullscreen ColorRect with warm orange tint — added to the scene tree's
	## viewport via a CanvasLayer so it renders on top of 3D.
	var canvas := CanvasLayer.new()
	canvas.name = "SolarFlareTintLayer"
	canvas.layer = 90  # High layer to render over most UI
	add_child(canvas)

	_screen_tint = ColorRect.new()
	_screen_tint.name = "SolarFlareTint"
	_screen_tint.color = Color(TINT_COLOR.r, TINT_COLOR.g, TINT_COLOR.b, 0.0)
	_screen_tint.anchors_preset = Control.PRESET_FULL_RECT
	_screen_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_screen_tint)


func _create_chromatic_overlay() -> void:
	## Fullscreen overlay that simulates chromatic aberration pulses
	## using a simple color-shifted transparent layer.
	var canvas := CanvasLayer.new()
	canvas.name = "SolarFlareChromaLayer"
	canvas.layer = 91
	add_child(canvas)

	_chromatic_rect = ColorRect.new()
	_chromatic_rect.name = "ChromaticPulse"
	_chromatic_rect.color = Color(0.0, 0.0, 0.0, 0.0)  # Invisible by default
	_chromatic_rect.anchors_preset = Control.PRESET_FULL_RECT
	_chromatic_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_chromatic_rect)


func _process(delta: float) -> void:
	_elapsed += delta

	# Fade envelope: ramp up first 3s, sustain, ramp down last 3s
	var fade := _get_fade_factor()

	# Pulsing intensity variation (slow sine wave)
	var pulse_mod := 0.85 + 0.15 * sin(_elapsed * INTENSITY_VARIATION_SPEED * TAU)
	var intensity := fade * pulse_mod

	# Update sun energy
	if _sun and is_instance_valid(_sun):
		var target_energy := _original_energy * lerpf(1.0, SUN_ENERGY_MULTIPLIER, intensity)
		_sun.light_energy = target_energy
		# Shift sun color slightly warmer
		_sun.light_color = _original_color.lerp(Color(1.0, 0.85, 0.6), intensity * 0.4)

	# Update screen tint alpha
	if _screen_tint and is_instance_valid(_screen_tint):
		_screen_tint.color.a = TINT_PEAK_ALPHA * intensity

	# Chromatic aberration pulse timer
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer = PULSE_INTERVAL
		_pulse_elapsed = 0.0  # Start a pulse

	# Animate chromatic pulse
	if _pulse_elapsed >= 0.0:
		_pulse_elapsed += delta
		if _pulse_elapsed >= PULSE_DURATION:
			_pulse_elapsed = -1.0  # End pulse
			if _chromatic_rect and is_instance_valid(_chromatic_rect):
				_chromatic_rect.color.a = 0.0
		else:
			_animate_chromatic_pulse()


func _animate_chromatic_pulse() -> void:
	## Flash a brief red-cyan split overlay to simulate chromatic aberration.
	if not _chromatic_rect or not is_instance_valid(_chromatic_rect):
		return

	var t := _pulse_elapsed / PULSE_DURATION
	# Sharp attack, quick decay
	var alpha := sin(t * PI) * 0.06
	# Alternate red/cyan tint
	if fmod(_pulse_elapsed * 20.0, 2.0) < 1.0:
		_chromatic_rect.color = Color(1.0, 0.2, 0.1, alpha)
	else:
		_chromatic_rect.color = Color(0.1, 0.8, 1.0, alpha)


func _get_fade_factor() -> float:
	var fade := 1.0
	if _elapsed < 3.0:
		fade = _elapsed / 3.0
	elif _elapsed > _duration - 3.0:
		fade = (_duration - _elapsed) / 3.0
	return clampf(fade, 0.0, 1.0)


func cleanup() -> void:
	## Restore sun to its original state.
	if _sun and is_instance_valid(_sun):
		_sun.light_energy = _original_energy
		_sun.light_color = _original_color
