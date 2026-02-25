extends Node3D
## Footstep dust puffs and landing dust clouds.
## Uses soft-circle shader particles for realistic mist look (no flat squares).
## Spawns brief particle bursts when the player steps on the ground
## or lands from a height.

var _player: CharacterBody3D
var _dust_puff: GPUParticles3D
var _landing_cloud: GPUParticles3D
var _step_timer: float = 0.0
var _was_on_floor: bool = false
var _prev_velocity_y: float = 0.0

const STEP_INTERVAL_WALK: float = 0.45
const STEP_INTERVAL_RUN: float = 0.28


func initialize(player: CharacterBody3D) -> void:
	_player = player
	_build_dust_puff()
	_build_landing_cloud()


func _build_dust_puff() -> void:
	## Small puff of regolith on each footstep.
	_dust_puff = GPUParticles3D.new()
	_dust_puff.name = "FootDustPuff"
	_dust_puff.one_shot = true
	_dust_puff.explosiveness = 0.9
	_dust_puff.amount = 12
	_dust_puff.lifetime = 1.0
	_dust_puff.emitting = false
	_dust_puff.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	_dust_puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust_puff)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.2
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3(0, -0.3, 0)
	mat.scale_min = 0.06
	mat.scale_max = 0.18
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.5
	mat.turbulence_noise_scale = 3.0
	mat.turbulence_influence_min = 0.02
	mat.turbulence_influence_max = 0.1

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.55, 0.5, 0.45, 0.0))
	color_ramp.add_point(0.1, Color(0.55, 0.5, 0.45, 0.35))
	color_ramp.add_point(0.5, Color(0.50, 0.47, 0.43, 0.2))
	color_ramp.set_color(1, Color(0.45, 0.42, 0.38, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	_dust_puff.process_material = mat

	# Soft-circle shader mesh
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_dust_puff.draw_pass_1 = quad
	quad.surface_set_material(0, _make_soft_particle_material())


func _build_landing_cloud() -> void:
	## Larger dust cloud on hard landings.
	_landing_cloud = GPUParticles3D.new()
	_landing_cloud.name = "LandingCloud"
	_landing_cloud.one_shot = true
	_landing_cloud.explosiveness = 0.95
	_landing_cloud.amount = 30
	_landing_cloud.lifetime = 2.0
	_landing_cloud.emitting = false
	_landing_cloud.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	_landing_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_landing_cloud)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.4
	mat.direction = Vector3(0, 0.2, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -0.2, 0)
	mat.scale_min = 0.15
	mat.scale_max = 0.6
	mat.damping_min = 1.5
	mat.damping_max = 4.0
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 2.0
	mat.turbulence_noise_scale = 2.5
	mat.turbulence_influence_min = 0.1
	mat.turbulence_influence_max = 0.35

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.55, 0.5, 0.45, 0.0))
	color_ramp.add_point(0.08, Color(0.55, 0.5, 0.45, 0.45))
	color_ramp.add_point(0.35, Color(0.50, 0.47, 0.43, 0.3))
	color_ramp.add_point(0.7, Color(0.45, 0.42, 0.38, 0.12))
	color_ramp.set_color(1, Color(0.4, 0.38, 0.35, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	_landing_cloud.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_landing_cloud.draw_pass_1 = quad
	quad.surface_set_material(0, _make_soft_particle_material())


func _physics_process(delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		return

	var on_floor := _player.is_on_floor()
	var h_speed := Vector2(_player.velocity.x, _player.velocity.z).length()

	# Landing detection — trigger dust cloud on hard landing
	if on_floor and not _was_on_floor:
		var fall_speed := absf(_prev_velocity_y)
		if fall_speed > 3.0:
			_emit_landing_cloud(fall_speed)

	# Footstep dust while walking/running on ground
	if on_floor and h_speed > 2.0:
		var is_sprinting := h_speed > 10.0
		var interval := STEP_INTERVAL_RUN if is_sprinting else STEP_INTERVAL_WALK
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = interval
			_emit_dust_puff()
	else:
		_step_timer = 0.0

	_was_on_floor = on_floor
	if not on_floor:
		_prev_velocity_y = _player.velocity.y


func _emit_dust_puff() -> void:
	## Small puff at player's feet.
	if not _dust_puff:
		return
	_dust_puff.global_position = _player.global_position + Vector3(0, 0.1, 0)
	_dust_puff.emitting = false
	_dust_puff.emitting = true


func _emit_landing_cloud(fall_speed: float) -> void:
	## Larger cloud scaled by fall speed.
	if not _landing_cloud:
		return
	_landing_cloud.global_position = _player.global_position + Vector3(0, 0.2, 0)

	# Scale amount and velocity by impact intensity
	var intensity := clampf(fall_speed / 15.0, 0.3, 1.0)
	var mat: ParticleProcessMaterial = _landing_cloud.process_material as ParticleProcessMaterial
	if mat:
		mat.initial_velocity_min = 1.0 + intensity * 3.0
		mat.initial_velocity_max = 3.0 + intensity * 6.0
		mat.scale_max = 0.3 + intensity * 0.5

	_landing_cloud.emitting = false
	_landing_cloud.emitting = true


func _make_soft_particle_material() -> ShaderMaterial:
	## Shared soft-circle shader so particles look like mist, not squares.
	var shader_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

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
	float alpha = exp(-dist * dist * 4.0);
	ALBEDO = COLOR.rgb;
	ALPHA = alpha * COLOR.a;
}
"""
	shader_mat.shader = shader
	return shader_mat
