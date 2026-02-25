extends GPUParticles3D
## Atmospheric haze particles that appear as territory gets terraformed.
## Replaces screen-space fog quad with volumetric particle clouds.
## At atmo_activity = 0 (vacuum): completely invisible.
## At atmo_activity = 1 (full atmosphere): dense ground-hugging haze.
## Follows the player so fog is always around them.

var _player: Node3D
var _process_mat: ParticleProcessMaterial
var _draw_mat: ShaderMaterial
var _activity: float = 0.0


func initialize(camera_or_player: Node3D = null) -> void:
	_player = camera_or_player

	# ── Particle system config ──
	amount = 200
	lifetime = 8.0
	explosiveness = 0.0
	randomness = 1.0
	fixed_fps = 20
	visibility_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 40, 160))
	emitting = false  # Starts off — enabled when activity > 0

	# ── Process material ──
	_process_mat = ParticleProcessMaterial.new()

	# Emission: large box around player, ground-hugging
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_mat.emission_box_extents = Vector3(60.0, 3.0, 60.0)

	# Drift: very slow lateral movement (wind-like)
	_process_mat.direction = Vector3(0.3, 0.1, 0.2)
	_process_mat.spread = 90.0
	_process_mat.initial_velocity_min = 0.1
	_process_mat.initial_velocity_max = 0.6
	_process_mat.angular_velocity_min = -3.0
	_process_mat.angular_velocity_max = 3.0

	# Gravity: very slight sink (fog settles in low gravity)
	_process_mat.gravity = Vector3(0.0, -0.04, 0.0)

	# Size: large soft blobs — 3-12m diameter billboards
	_process_mat.scale_min = 3.0
	_process_mat.scale_max = 12.0

	# Color ramp: fade in, hold, fade out — soft translucent blue-grey
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.55, 0.58, 0.68, 0.0))     # Fade in
	color_ramp.add_point(0.15, Color(0.55, 0.58, 0.68, 0.06))  # Visible
	color_ramp.add_point(0.5, Color(0.50, 0.54, 0.65, 0.08))   # Peak
	color_ramp.add_point(0.8, Color(0.48, 0.52, 0.62, 0.04))   # Fading
	color_ramp.set_color(1, Color(0.45, 0.50, 0.60, 0.0))      # Gone
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	_process_mat.color_ramp = color_tex

	# Damping — very slow deceleration
	_process_mat.damping_min = 0.1
	_process_mat.damping_max = 0.3

	# Turbulence — gentle swirling makes it look organic
	_process_mat.turbulence_enabled = true
	_process_mat.turbulence_noise_strength = 1.5
	_process_mat.turbulence_noise_speed_random = 0.2
	_process_mat.turbulence_noise_scale = 5.0
	_process_mat.turbulence_influence_min = 0.1
	_process_mat.turbulence_influence_max = 0.3

	process_material = _process_mat

	# ── Draw pass: billboarded quad with soft-circle shader ──
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)  # Scaled by particle scale
	draw_pass_1 = quad

	# Custom shader material — soft radial falloff for cloud-like look
	_draw_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _get_fog_particle_shader()
	_draw_mat.shader = shader
	draw_pass_1.surface_set_material(0, _draw_mat)

	# Rendering settings
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	transparency = 0.5  # Sort with transparent objects


func set_atmo_activity(activity: float) -> void:
	_activity = activity
	var show := activity > 0.02
	emitting = show
	visible = show

	if _process_mat:
		# Scale particle count + opacity with activity
		amount = int(clampf(lerpf(40, 300, activity), 40, 300))

		# More particles emit from a taller column at high activity
		_process_mat.emission_box_extents = Vector3(60.0, lerpf(2.0, 8.0, activity), 60.0)

		# Slightly faster drift at high activity (more atmospheric circulation)
		_process_mat.initial_velocity_max = lerpf(0.3, 1.2, activity)

		# More turbulence with more atmosphere
		_process_mat.turbulence_noise_strength = lerpf(0.8, 3.0, activity)

	if _draw_mat:
		_draw_mat.set_shader_parameter("fog_opacity", clampf(activity * 0.12, 0.0, 0.12))


func set_sun_direction(sun_dir: Vector3) -> void:
	if _draw_mat:
		_draw_mat.set_shader_parameter("sun_direction", sun_dir)


func set_player(p: Node3D) -> void:
	_player = p


func _process(_delta: float) -> void:
	# Follow the player so fog is always around them
	if _player and is_instance_valid(_player):
		global_position = Vector3(
			_player.global_position.x,
			_player.global_position.y - 2.0,
			_player.global_position.z
		)


func _get_fog_particle_shader() -> String:
	return """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Soft radial falloff for cloud-like fog particles.
// Each particle is a billboarded quad with a smooth circle.

uniform float fog_opacity : hint_range(0.0, 0.3) = 0.06;
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);

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
	// Soft circle: radial falloff from center of quad
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;

	// Smooth gaussian-ish falloff — soft edges, no hard circle
	float alpha = exp(-dist * dist * 3.0);
	alpha *= fog_opacity * COLOR.a;

	// Subtle sun-side brightening
	float sun_factor = dot(normalize(sun_direction), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
	vec3 fog_col = COLOR.rgb * (0.8 + sun_factor * 0.4);

	ALBEDO = fog_col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""
