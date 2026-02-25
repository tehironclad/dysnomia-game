extends GPUParticles3D
## Ambient dust particles floating near the lunar surface.
## Subtle regolith motes that drift in low gravity.
## Uses a soft-circle shader so particles look like floating mist, not flat squares.
## More visible during terraforming (territory activity increases emission).

var _player: Node3D
var _base_emission_rate: float = 8.0  # Particles per second (minimal dust)
var _active_emission_rate: float = 40.0  # During high terraform activity


func _ready() -> void:
	# Configure particle system
	amount = 120
	lifetime = 6.0
	explosiveness = 0.0
	randomness = 1.0
	fixed_fps = 30
	visibility_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 12, 60))
	emitting = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Create particle material
	var mat := ParticleProcessMaterial.new()

	# Emission: box around player at ground level
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(20.0, 1.5, 20.0)

	# Direction: mostly upward drift (low gravity) with random spread
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.4
	mat.angular_velocity_min = -15.0
	mat.angular_velocity_max = 15.0

	# Gravity: very weak pull back down (Dysnomia low gravity)
	mat.gravity = Vector3(0.0, -0.15, 0.0)

	# Size: tiny motes — 2-6cm diameter
	mat.scale_min = 0.02
	mat.scale_max = 0.08

	# Color: regolith grey with transparency — gentler fade
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.5, 0.48, 0.45, 0.0))     # Fade in
	color_ramp.add_point(0.1, Color(0.52, 0.50, 0.47, 0.15))  # Gently visible
	color_ramp.add_point(0.4, Color(0.50, 0.48, 0.45, 0.2))   # Peak
	color_ramp.add_point(0.75, Color(0.45, 0.43, 0.40, 0.1))  # Fading
	color_ramp.set_color(1, Color(0.4, 0.38, 0.36, 0.0))      # Gone

	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex

	# Damping — slow down over time (dust settling)
	mat.damping_min = 0.3
	mat.damping_max = 0.8

	# Turbulence — makes dust swirl naturally
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.8
	mat.turbulence_noise_speed_random = 0.3
	mat.turbulence_noise_scale = 3.0
	mat.turbulence_influence_min = 0.05
	mat.turbulence_influence_max = 0.15

	process_material = mat

	# Draw pass: quad with soft-circle shader (no hard square edges)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	draw_pass_1 = quad

	var shader_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _get_soft_particle_shader()
	shader_mat.shader = shader
	draw_pass_1.surface_set_material(0, shader_mat)


func initialize(player: Node3D) -> void:
	_player = player


func set_activity_level(activity: float) -> void:
	## More terraforming = more dust kicked up.
	var target_rate: float = lerpf(_base_emission_rate, _active_emission_rate, clampf(activity, 0.0, 1.0))
	amount = int(clampf(target_rate * lifetime, 20, 300))

	# Also brighten dust slightly when terraforming is active
	var mat: ParticleProcessMaterial = process_material as ParticleProcessMaterial
	if mat:
		# More turbulence during active terraforming
		mat.turbulence_noise_strength = lerpf(0.8, 2.5, activity)


func _process(_delta: float) -> void:
	# Follow the player horizontally, stay at ground level
	if _player and is_instance_valid(_player):
		global_position = Vector3(_player.global_position.x, _player.global_position.y - 1.0, _player.global_position.z)


func _get_soft_particle_shader() -> String:
	return """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

void vertex() {
	// Billboard: always face camera
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
	// Soft radial falloff — gaussian blob, invisible at edges
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	float alpha = exp(-dist * dist * 4.5);
	// Very soft, wispy mote
	alpha *= COLOR.a;
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""
