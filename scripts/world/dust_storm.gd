extends Node3D
## Massive dust storm event — blankets territory in swirling grey-brown particles.
## Follows the player, applying a subtle wind push force each frame.
## Fades in over the first 3 seconds and fades out over the last 3 seconds.
## Spawned and managed by WeatherSystem.

const FOLLOW_RADIUS: float = 100.0   # Particle spread radius around player
const PARTICLE_COUNT: int = 600
const PARTICLE_LIFETIME: float = 3.0
const WIND_FORCE: float = 1.2        # Lateral push on player (m/s added per frame)
const FADE_TIME: float = 3.0         # Seconds to fade in/out

var _player: Node3D
var _wind_direction: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0
var _duration: float = 60.0
var _particles: GPUParticles3D
var _process_mat: ParticleProcessMaterial
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func set_duration(d: float) -> void:
	_duration = maxf(d, 10.0)


func get_elapsed() -> float:
	return _elapsed


func initialize(player: Node3D) -> void:
	_player = player
	_rng.seed = Time.get_ticks_msec()

	# Random horizontal wind direction
	var angle := _rng.randf() * TAU
	_wind_direction = Vector3(cos(angle), 0.0, sin(angle)).normalized()

	_build_particles()


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "DustStormParticles"
	add_child(_particles)

	_particles.amount = PARTICLE_COUNT
	_particles.lifetime = PARTICLE_LIFETIME
	_particles.explosiveness = 0.0
	_particles.randomness = 0.9
	_particles.fixed_fps = 30
	_particles.visibility_aabb = AABB(
		Vector3(-FOLLOW_RADIUS, -5.0, -FOLLOW_RADIUS),
		Vector3(FOLLOW_RADIUS * 2.0, 40.0, FOLLOW_RADIUS * 2.0)
	)
	_particles.emitting = true

	# Process material — wide horizontal spread, wind-driven
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(FOLLOW_RADIUS, 15.0, FOLLOW_RADIUS)

	_process_mat.direction = _wind_direction
	_process_mat.spread = 25.0
	_process_mat.initial_velocity_min = 4.0
	_process_mat.initial_velocity_max = 12.0
	_process_mat.angular_velocity_min = -60.0
	_process_mat.angular_velocity_max = 60.0
	_process_mat.gravity = Vector3(0.0, -0.3, 0.0)
	_process_mat.scale_min = 0.4
	_process_mat.scale_max = 1.8
	_process_mat.damping_min = 0.2
	_process_mat.damping_max = 1.0

	# Turbulence for chaotic swirling
	_process_mat.turbulence_enabled = true
	_process_mat.turbulence_noise_strength = 6.0
	_process_mat.turbulence_noise_speed_random = 0.4
	_process_mat.turbulence_noise_scale = 4.0
	_process_mat.turbulence_influence_min = 0.2
	_process_mat.turbulence_influence_max = 0.6

	# Grey-brown regolith dust color ramp
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.55, 0.50, 0.44, 0.0))
	color_ramp.add_point(0.08, Color(0.52, 0.48, 0.42, 0.10))
	color_ramp.add_point(0.4, Color(0.50, 0.46, 0.40, 0.14))
	color_ramp.add_point(0.75, Color(0.47, 0.44, 0.38, 0.10))
	color_ramp.set_color(1, Color(0.42, 0.40, 0.35, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	_process_mat.color_ramp = color_tex

	_particles.process_material = _process_mat

	# Draw pass — billboarded soft quad (same style as dust_devil.gd)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	_particles.draw_pass_1 = quad

	var draw_mat := _create_draw_material()
	quad.surface_set_material(0, draw_mat)

	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_particles.transparency = 0.5


func _create_draw_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
uniform float opacity : hint_range(0.0, 0.3) = 0.12;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(vec3(0.0, 1.0, 0.0), 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	float alpha = exp(-dist * dist * 2.0);
	alpha *= opacity * COLOR.a;
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""
	mat.shader = shader
	mat.set_shader_parameter("opacity", 0.12)
	return mat


func _process(delta: float) -> void:
	_elapsed += delta

	# Follow player position
	if _player and is_instance_valid(_player):
		global_position = _player.global_position

		# Apply wind push to player velocity (small lateral force)
		if _player is CharacterBody3D:
			var fade := _get_fade_factor()
			var push := _wind_direction * WIND_FORCE * fade * delta
			_player.velocity.x += push.x
			_player.velocity.z += push.z

	# Fade particles in/out
	var fade := _get_fade_factor()
	if _process_mat:
		_process_mat.emission_box_extents = Vector3(
			FOLLOW_RADIUS * fade,
			15.0 * fade,
			FOLLOW_RADIUS * fade
		)


func _get_fade_factor() -> float:
	## Returns 0..1 fade multiplier: ramps up in first FADE_TIME,
	## ramps down in last FADE_TIME, full intensity in between.
	var fade := 1.0
	if _elapsed < FADE_TIME:
		fade = _elapsed / FADE_TIME
	elif _elapsed > _duration - FADE_TIME:
		fade = (_duration - _elapsed) / FADE_TIME
	return clampf(fade, 0.0, 1.0)


func cleanup() -> void:
	if _particles and is_instance_valid(_particles):
		_particles.emitting = false
