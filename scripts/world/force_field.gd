extends Node3D
## A single force field wall between territories.
## Contains a translucent mesh (territory_border shader), collision body,
## base particle emitter (energy sparks), and ground glow light.
## Can be dissolved with a noise-burn animation when the player Joins.

enum State { ACTIVE, DISSOLVING, DISABLED }

var _state: int = State.ACTIVE
var _mesh_instance: MeshInstance3D
var _collision_body: StaticBody3D
var _material: ShaderMaterial
var _direction: int  # TerritoryManager.Direction enum value
var _base_particles: GPUParticles3D
var _ground_light: OmniLight3D

signal dissolved(direction: int)


func setup(direction: int, width: float, height: float, biome_seed: int) -> void:
	## Create the force field wall geometry, collision, particles, and lighting.
	_direction = direction

	# --- Shader Material ---
	var shader := load("res://assets/shaders/territory_border.gdshader") as Shader
	_material = ShaderMaterial.new()
	_material.shader = shader

	# Color tinted by neighbor biome
	var hue := fmod(float(biome_seed % 1000) / 1000.0, 1.0)
	var border_color := Color.from_hsv(hue, 0.55, 0.85)
	_material.set_shader_parameter("border_color", Vector3(border_color.r, border_color.g, border_color.b))
	_material.set_shader_parameter("pulse_speed", 0.8 + float(direction) * 0.3)
	_material.set_shader_parameter("opacity", 0.2)
	_material.set_shader_parameter("fresnel_power", 2.5)
	_material.set_shader_parameter("border_height", height)
	_material.set_shader_parameter("dissolve_progress", 0.0)

	# --- Visual Mesh (QuadMesh standing upright) ---
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "FieldMesh"
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.position.y = height / 2.0
	add_child(_mesh_instance)

	# --- Collision Body ---
	_collision_body = StaticBody3D.new()
	_collision_body.name = "FieldCollision"

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var extended_height := height + 50.0
	box.size = Vector3(width + 12.0, extended_height, 5.0)
	col_shape.shape = box
	col_shape.position.y = (height - 50.0) / 2.0

	_collision_body.add_child(col_shape)
	add_child(_collision_body)

	# --- Base Energy Particles (sparks drifting up along wall) ---
	_base_particles = GPUParticles3D.new()
	_base_particles.name = "BaseParticles"
	_base_particles.amount = 80
	_base_particles.lifetime = 3.0
	_base_particles.explosiveness = 0.0
	_base_particles.randomness = 1.0
	_base_particles.fixed_fps = 30
	_base_particles.visibility_aabb = AABB(Vector3(-width * 0.5, -2, -2), Vector3(width, height + 10, 4))
	_base_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(width * 0.48, 0.5, 0.3)
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 15.0
	pmat.initial_velocity_min = 1.0
	pmat.initial_velocity_max = 3.5
	pmat.gravity = Vector3(0.0, 0.5, 0.0)  # Upward drift (energy rises)
	pmat.scale_min = 0.03
	pmat.scale_max = 0.1
	pmat.damping_min = 0.2
	pmat.damping_max = 0.6
	pmat.turbulence_enabled = true
	pmat.turbulence_noise_strength = 1.2
	pmat.turbulence_noise_speed_random = 0.3
	pmat.turbulence_noise_scale = 4.0
	pmat.turbulence_influence_min = 0.05
	pmat.turbulence_influence_max = 0.2

	# Color: match border tint, glow then fade
	var pgrad := Gradient.new()
	pgrad.set_color(0, Color(border_color.r, border_color.g, border_color.b, 0.0))
	pgrad.add_point(0.1, Color(border_color.r * 1.3, border_color.g * 1.3, border_color.b * 1.3, 0.7))
	pgrad.add_point(0.5, Color(border_color.r, border_color.g, border_color.b, 0.4))
	pgrad.set_color(1, Color(border_color.r * 0.5, border_color.g * 0.5, border_color.b * 0.5, 0.0))
	var ptex := GradientTexture1D.new()
	ptex.gradient = pgrad
	pmat.color_ramp = ptex

	_base_particles.process_material = pmat

	# Soft-circle draw mesh (not flat quads)
	var pquad := QuadMesh.new()
	pquad.size = Vector2(1.0, 1.0)
	var pdraw := ShaderMaterial.new()
	var pshader := Shader.new()
	pshader.code = _get_spark_shader()
	pdraw.shader = pshader
	pquad.surface_set_material(0, pdraw)
	_base_particles.draw_pass_1 = pquad

	_base_particles.position.y = 0.5
	add_child(_base_particles)

	# --- Ground glow light ---
	_ground_light = OmniLight3D.new()
	_ground_light.name = "GroundGlow"
	_ground_light.light_color = border_color
	_ground_light.light_energy = 0.8
	_ground_light.omni_range = 8.0
	_ground_light.omni_attenuation = 1.5
	_ground_light.shadow_enabled = false
	_ground_light.position.y = 1.5
	add_child(_ground_light)


func dissolve(duration: float = 1.5) -> void:
	## Start the dissolve animation. Force field burns away over duration seconds.
	if _state != State.ACTIVE:
		return
	_state = State.DISSOLVING

	if _collision_body:
		_collision_body.queue_free()
		_collision_body = null

	var tween := create_tween()
	tween.tween_method(_set_dissolve_progress, 0.0, 1.0, duration)
	tween.tween_callback(_on_dissolve_complete)

	# Fade out particles and light alongside dissolve
	if _base_particles:
		var ptween := create_tween()
		ptween.tween_property(_base_particles, "amount_ratio", 0.0, duration * 0.8)
	if _ground_light:
		var ltween := create_tween()
		ltween.tween_property(_ground_light, "light_energy", 0.0, duration)


func _set_dissolve_progress(value: float) -> void:
	if _material:
		_material.set_shader_parameter("dissolve_progress", value)


func _on_dissolve_complete() -> void:
	_state = State.DISABLED
	if _mesh_instance:
		_mesh_instance.queue_free()
		_mesh_instance = null
	if _base_particles:
		_base_particles.queue_free()
		_base_particles = null
	if _ground_light:
		_ground_light.queue_free()
		_ground_light = null
	dissolved.emit(_direction)


func is_active() -> bool:
	return _state == State.ACTIVE


func disable_collision() -> void:
	## Remove collision without visual dissolve (e.g., for fly mode).
	if _collision_body:
		_collision_body.queue_free()
		_collision_body = null


func _get_spark_shader() -> String:
	return """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

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
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	float alpha = exp(-d * d * 5.0);
	ALBEDO = COLOR.rgb * (1.0 + exp(-d * d * 15.0) * 0.5);
	ALPHA = alpha * COLOR.a;
}
"""
