extends GPUParticles3D
## A single dust devil — swirling vortex column that drifts across terrain.
## Spawned by DustDevilSpawner, self-destructs after lifetime expires.

var _lifetime: float = 20.0
var _age: float = 0.0
var _drift_direction: Vector2 = Vector2(1.0, 0.3).normalized()
var _drift_speed: float = 2.0
var _terrain_gen: Node3D
var _process_mat: ParticleProcessMaterial


func initialize(terrain_gen: Node3D, start_pos: Vector3, p_lifetime: float,
		drift_dir: Vector2, drift_speed: float, scale_mult: float) -> void:
	_terrain_gen = terrain_gen
	_lifetime = p_lifetime
	_drift_direction = drift_dir.normalized()
	_drift_speed = drift_speed
	global_position = start_pos

	# Particle system config
	amount = int(50 * scale_mult)
	lifetime = 4.0
	explosiveness = 0.0
	randomness = 0.8
	fixed_fps = 20
	visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 30, 16))
	emitting = true

	_process_mat = ParticleProcessMaterial.new()
	# Tight cylindrical emission — tall and narrow
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(1.5 * scale_mult, 8.0 * scale_mult, 1.5 * scale_mult)

	# Upward swirling motion
	_process_mat.direction = Vector3(0.0, 1.0, 0.0)
	_process_mat.spread = 30.0
	_process_mat.initial_velocity_min = 2.0
	_process_mat.initial_velocity_max = 6.0
	_process_mat.angular_velocity_min = -180.0
	_process_mat.angular_velocity_max = 180.0
	_process_mat.gravity = Vector3(0.0, 0.5, 0.0)  # Net upward in the vortex
	_process_mat.scale_min = 0.3 * scale_mult
	_process_mat.scale_max = 1.2 * scale_mult
	_process_mat.damping_min = 0.5
	_process_mat.damping_max = 1.5

	# Strong turbulence — swirling vortex feel
	_process_mat.turbulence_enabled = true
	_process_mat.turbulence_noise_strength = 4.0
	_process_mat.turbulence_noise_speed_random = 0.5
	_process_mat.turbulence_noise_scale = 3.0
	_process_mat.turbulence_influence_min = 0.3
	_process_mat.turbulence_influence_max = 0.7

	# Color ramp: brownish-grey regolith dust
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.50, 0.47, 0.42, 0.0))
	color_ramp.add_point(0.1, Color(0.50, 0.47, 0.42, 0.12))
	color_ramp.add_point(0.5, Color(0.48, 0.45, 0.40, 0.15))
	color_ramp.add_point(0.8, Color(0.45, 0.43, 0.38, 0.08))
	color_ramp.set_color(1, Color(0.40, 0.38, 0.35, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	_process_mat.color_ramp = color_tex
	process_material = _process_mat

	# Draw pass: billboarded soft quad with gaussian falloff
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	draw_pass_1 = quad
	var draw_mat := _create_draw_material()
	quad.surface_set_material(0, draw_mat)

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	transparency = 0.5


func _create_draw_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
uniform float opacity : hint_range(0.0, 0.3) = 0.1;
void vertex() {
	// Billboard — face camera but stay upright
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
	float alpha = exp(-dist * dist * 2.5);
	alpha *= opacity * COLOR.a;
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""
	mat.shader = shader
	mat.set_shader_parameter("opacity", 0.1)
	return mat


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return

	# Drift across terrain
	global_position.x += _drift_direction.x * _drift_speed * delta
	global_position.z += _drift_direction.y * _drift_speed * delta

	# Snap to terrain height
	if _terrain_gen and is_instance_valid(_terrain_gen) and _terrain_gen.has_method("get_height_at"):
		var h: float = _terrain_gen.get_height_at(global_position.x, global_position.z)
		global_position.y = h + 0.5

	# Fade in at start, fade out at end
	var fade := 1.0
	if _age < 2.0:
		fade = _age / 2.0
	elif _age > _lifetime - 3.0:
		fade = (_lifetime - _age) / 3.0
	fade = clampf(fade, 0.0, 1.0)

	if _process_mat:
		_process_mat.emission_box_extents.x = 1.5 * fade
		_process_mat.emission_box_extents.z = 1.5 * fade
