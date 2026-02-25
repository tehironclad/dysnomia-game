extends Node
## Manages helmet HUD overlay, chromatic aberration, and motion blur.
## Created by HUD controller, updated every frame with player state.

const HELMET_SHADER = preload("res://assets/shaders/helmet_hud.gdshader")
const CHROMATIC_SHADER = preload("res://assets/shaders/chromatic_aberration.gdshader")
const MOTION_SHADER = preload("res://assets/shaders/motion_blur.gdshader")

var _helmet_rect: ColorRect
var _chromatic_rect: ColorRect
var _motion_rect: ColorRect

var _helmet_shader: ShaderMaterial
var _chromatic_shader: ShaderMaterial
var _motion_shader: ShaderMaterial

var _chromatic_tween: Tween
var _elapsed: float = 0.0
var _player: Node3D
var _prev_position: Vector3 = Vector3.ZERO


func initialize(hud: CanvasLayer, player: Node3D) -> void:
	_player = player
	if player:
		_prev_position = player.global_position

	# ── Helmet HUD overlay (topmost layer, drawn last) ──
	if HELMET_SHADER:
		_helmet_shader = ShaderMaterial.new()
		_helmet_shader.shader = HELMET_SHADER

	_helmet_rect = ColorRect.new()
	_helmet_rect.name = "HelmetHUD"
	_helmet_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	if _helmet_shader:
		_helmet_rect.material = _helmet_shader
	_helmet_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_helmet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_helmet_rect.z_index = 90
	hud.add_child(_helmet_rect)

	# ── Chromatic aberration (post-process, behind helmet) ──
	if CHROMATIC_SHADER:
		_chromatic_shader = ShaderMaterial.new()
		_chromatic_shader.shader = CHROMATIC_SHADER
		_chromatic_shader.set_shader_parameter("strength", 0.0)

	_chromatic_rect = ColorRect.new()
	_chromatic_rect.name = "ChromaticAberration"
	_chromatic_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	if _chromatic_shader:
		_chromatic_rect.material = _chromatic_shader
	_chromatic_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chromatic_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chromatic_rect.z_index = 80
	_chromatic_rect.visible = false  # Start hidden — shown only during pulses
	hud.add_child(_chromatic_rect)

	# ── Motion blur (post-process, behind chromatic) ──
	if MOTION_SHADER:
		_motion_shader = ShaderMaterial.new()
		_motion_shader.shader = MOTION_SHADER
		_motion_shader.set_shader_parameter("intensity", 0.0)

	_motion_rect = ColorRect.new()
	_motion_rect.name = "MotionBlur"
	_motion_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	if _motion_shader:
		_motion_rect.material = _motion_shader
	_motion_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_motion_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion_rect.z_index = 70
	_motion_rect.visible = false  # Start hidden — shown only when moving fast
	hud.add_child(_motion_rect)

	# Apply initial config state
	_apply_config()


func update(delta: float, player: Node3D) -> void:
	if not player:
		return

	_elapsed += delta

	# ── Helmet HUD updates ──
	if Config.helmet_hud_enabled and _helmet_shader:
		_helmet_shader.set_shader_parameter("time_elapsed", _elapsed)
		_helmet_shader.set_shader_parameter("enabled", 1.0)

		# Heading from player's Y rotation (yaw)
		var yaw_deg: float = rad_to_deg(-player.rotation.y)
		var heading := fmod(yaw_deg + 360.0, 360.0)
		_helmet_shader.set_shader_parameter("heading", heading)

		# Health (from weapon system if available)
		var weapon_sys = player.get_node_or_null("WeaponSystem")
		if weapon_sys and weapon_sys.has_method("get_health_percent"):
			_helmet_shader.set_shader_parameter("health", weapon_sys.get_health_percent())
		else:
			_helmet_shader.set_shader_parameter("health", 1.0)

		# O2 is always full (lunar suit — no mechanic yet)
		_helmet_shader.set_shader_parameter("oxygen", 1.0)
	elif _helmet_shader:
		_helmet_shader.set_shader_parameter("enabled", 0.0)

	# ── Motion blur ──
	if Config.screen_effects_enabled and _motion_shader:
		var velocity := player.global_position - _prev_position
		_prev_position = player.global_position

		var speed := velocity.length() / delta if delta > 0.0 else 0.0

		# Only blur above sprint speed (14 m/s)
		var blur_intensity := clampf((speed - 14.0) / 30.0, 0.0, 0.8)

		if blur_intensity > 0.01:
			# Convert 3D velocity to approximate screen-space direction
			var camera := player.get_viewport().get_camera_3d() if player.get_viewport() else null
			var vel_uv := Vector2.ZERO
			if camera and speed > 1.0:
				var cam_fwd := -camera.global_basis.z
				var cam_right := camera.global_basis.x
				var cam_up := camera.global_basis.y
				vel_uv.x = velocity.dot(cam_right)
				vel_uv.y = -velocity.dot(cam_up)
				if vel_uv.length() > 0.001:
					vel_uv = vel_uv.normalized()

			_motion_shader.set_shader_parameter("intensity", blur_intensity)
			_motion_shader.set_shader_parameter("velocity_uv", vel_uv)
			_motion_rect.visible = true
		else:
			_motion_shader.set_shader_parameter("intensity", 0.0)
			_motion_rect.visible = false
	elif _motion_rect:
		_motion_rect.visible = false
		if _motion_shader:
			_motion_shader.set_shader_parameter("intensity", 0.0)


func trigger_chromatic_pulse(intensity: float = 0.015, duration: float = 0.4) -> void:
	## Trigger a brief chromatic aberration pulse (damage, beat, etc.).
	if not Config.screen_effects_enabled:
		return
	if not _chromatic_shader:
		return

	# Kill existing tween
	if _chromatic_tween and _chromatic_tween.is_valid():
		_chromatic_tween.kill()

	# Show the rect and set to peak, then decay
	if _chromatic_rect:
		_chromatic_rect.visible = true
	_chromatic_shader.set_shader_parameter("strength", intensity)
	_chromatic_tween = create_tween()
	_chromatic_tween.tween_method(
		func(v: float): _chromatic_shader.set_shader_parameter("strength", v),
		intensity, 0.0, duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	# Hide the rect when the pulse finishes
	_chromatic_tween.tween_callback(func():
		if _chromatic_rect:
			_chromatic_rect.visible = false
	)


func set_helmet_visible(vis: bool) -> void:
	if _helmet_rect:
		_helmet_rect.visible = vis


func set_motion_blur_enabled(en: bool) -> void:
	if _motion_rect:
		_motion_rect.visible = en


func _apply_config() -> void:
	if _helmet_rect:
		_helmet_rect.visible = Config.helmet_hud_enabled
	# Motion blur and chromatic rects start hidden — they are shown only when
	# their effect is actively being rendered (blur_intensity > 0 or chromatic pulse).
	# This avoids the version_get_shader error from rendering with inactive shaders.
	if _motion_rect and not Config.screen_effects_enabled:
		_motion_rect.visible = false
	if _chromatic_rect and not Config.screen_effects_enabled:
		_chromatic_rect.visible = false
