extends CharacterBody3D
## Lunar rover vehicle for Dysnomia.
## Player enters/exits with V key. Vehicle provides faster ground movement
## and protection from creatures. Built procedurally from primitives.

signal player_mounted
signal player_dismounted

enum VehicleType { ROVER, HOVERBIKE, TANK }

var vehicle_type: int = VehicleType.ROVER
var is_mounted: bool = false
var _player: CharacterBody3D
var _terrain: Node3D

# Vehicle stats
var max_speed: float = 25.0
var acceleration_rate: float = 12.0
var brake_force: float = 15.0
var turn_speed: float = 2.5
var _current_speed: float = 0.0

# Mesh references
var _chassis: MeshInstance3D
var _wheel_fl: MeshInstance3D
var _wheel_fr: MeshInstance3D
var _wheel_bl: MeshInstance3D
var _wheel_br: MeshInstance3D
var _cabin: MeshInstance3D
var _headlight_l: MeshInstance3D
var _headlight_r: MeshInstance3D
var _chassis_mat: StandardMaterial3D
var _chassis_shader_mat: ShaderMaterial
var _wheel_mat: StandardMaterial3D
var _light_mat: StandardMaterial3D
var _dust_trail: GPUParticles3D
var _headlight_spot_l: SpotLight3D
var _headlight_spot_r: SpotLight3D

# Polish feature nodes
var _dashboard: MeshInstance3D
var _hover_glow: OmniLight3D
var _turret_pivot: Node3D
var _suspension_time: float = 0.0
var _hover_glow_time: float = 0.0

const GRAVITY: float = 3.2
const VEHICLE_SHADER = preload("res://assets/shaders/vehicle.gdshader")


func initialize(type: int, spawn_pos: Vector3, player: CharacterBody3D, terrain: Node3D) -> void:
	vehicle_type = type
	_player = player
	_terrain = terrain
	position = spawn_pos

	match type:
		VehicleType.ROVER:
			max_speed = 25.0
			acceleration_rate = 12.0
			turn_speed = 2.0
		VehicleType.HOVERBIKE:
			max_speed = 40.0
			acceleration_rate = 18.0
			turn_speed = 3.5
		VehicleType.TANK:
			max_speed = 15.0
			acceleration_rate = 8.0
			turn_speed = 1.2

	_build_model()
	_build_dust_trail()


func _build_dust_trail() -> void:
	## Vehicle kicks up dust when moving across the surface.
	_dust_trail = GPUParticles3D.new()
	_dust_trail.name = "VehicleDust"
	_dust_trail.amount = 30
	_dust_trail.lifetime = 1.5
	_dust_trail.explosiveness = 0.0
	_dust_trail.randomness = 0.5
	_dust_trail.emitting = false
	_dust_trail.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 6, 16))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(1.0, 0.1, 0.3)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3(0, -0.5, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.25
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.0
	mat.turbulence_noise_scale = 3.0
	mat.turbulence_influence_min = 0.05
	mat.turbulence_influence_max = 0.2

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.55, 0.5, 0.45, 0.4))
	color_ramp.add_point(0.4, Color(0.5, 0.47, 0.43, 0.25))
	color_ramp.set_color(1, Color(0.4, 0.38, 0.35, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	_dust_trail.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_dust_trail.draw_pass_1 = quad
	# Soft-circle shader so dust looks like clouds, not squares
	var dust_shader_mat := ShaderMaterial.new()
	var dust_shader := Shader.new()
	dust_shader.code = """
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
	vec2 c = UV - vec2(0.5);
	float d = length(c) * 2.0;
	float alpha = exp(-d * d * 4.0);
	ALBEDO = COLOR.rgb;
	ALPHA = alpha * COLOR.a;
}
"""
	dust_shader_mat.shader = dust_shader
	quad.surface_set_material(0, dust_shader_mat)

	add_child(_dust_trail)
	_dust_trail.position = Vector3(0, 0.1, -1.2)  # Behind vehicle


func _build_model() -> void:
	# Chassis material — metallic white with accent
	_chassis_mat = StandardMaterial3D.new()
	_chassis_mat.albedo_color = Color(0.85, 0.85, 0.88)
	_chassis_mat.roughness = 0.35
	_chassis_mat.metallic = 0.3

	# Vehicle shader for premium look
	_chassis_shader_mat = ShaderMaterial.new()
	_chassis_shader_mat.shader = VEHICLE_SHADER
	_chassis_shader_mat.set_shader_parameter("base_color", Vector3(0.85, 0.85, 0.88))
	_chassis_shader_mat.set_shader_parameter("accent_color", Vector3(0.3, 0.5, 1.0))
	_chassis_shader_mat.set_shader_parameter("base_roughness", 0.35)
	_chassis_shader_mat.set_shader_parameter("base_metallic", 0.6)

	_wheel_mat = StandardMaterial3D.new()
	_wheel_mat.albedo_color = Color(0.2, 0.2, 0.22)
	_wheel_mat.roughness = 0.8
	_wheel_mat.metallic = 0.1

	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(1.0, 0.95, 0.8)
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1.0, 0.95, 0.8)
	_light_mat.emission_energy_multiplier = 3.0

	match vehicle_type:
		VehicleType.ROVER:
			_build_rover()
		VehicleType.HOVERBIKE:
			_build_hoverbike()
		VehicleType.TANK:
			_build_tank()

	# Collision shape
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 3.0)
	col.shape = box
	col.position.y = 0.6
	add_child(col)


func _build_rover() -> void:
	# Main chassis — rectangular body
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(1.8, 0.5, 3.0)
	_chassis = MeshInstance3D.new()
	_chassis.name = "Chassis"
	_chassis.mesh = chassis_mesh
	_chassis.material_override = _chassis_shader_mat
	_chassis.position = Vector3(0, 0.6, 0)
	_chassis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_chassis)

	# Cabin — rounded top
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.4, 0.6, 1.2)
	_cabin = MeshInstance3D.new()
	_cabin.name = "Cabin"
	_cabin.mesh = cabin_mesh
	_cabin.material_override = _chassis_shader_mat
	_cabin.position = Vector3(0, 1.15, -0.3)
	_cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_cabin)

	# Wheels — 4 cylinders
	_wheel_fl = _make_wheel("WheelFL", Vector3(-0.9, 0.25, 1.0))
	_wheel_fr = _make_wheel("WheelFR", Vector3(0.9, 0.25, 1.0))
	_wheel_bl = _make_wheel("WheelBL", Vector3(-0.9, 0.25, -1.0))
	_wheel_br = _make_wheel("WheelBR", Vector3(0.9, 0.25, -1.0))

	# Headlights
	_headlight_l = _make_light("HeadL", Vector3(-0.6, 0.7, 1.5))
	_headlight_r = _make_light("HeadR", Vector3(0.6, 0.7, 1.5))

	# Actual SpotLight3D headlights for illumination
	_headlight_spot_l = _make_headlight_spot(Vector3(-0.6, 0.7, 1.5))
	_headlight_spot_r = _make_headlight_spot(Vector3(0.6, 0.7, 1.5))

	# Dashboard panel in front of driver
	_build_dashboard(Vector3(0, 1.05, 0.5))


func _make_headlight_spot(pos: Vector3) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_energy = 2.5
	light.light_color = Color(1.0, 0.95, 0.85)
	light.spot_range = 35.0
	light.spot_angle = 30.0
	light.spot_attenuation = 0.9
	light.shadow_enabled = true
	light.shadow_bias = 0.05
	light.visible = false  # Enabled on mount
	light.position = pos
	light.rotation_degrees.x = -10.0  # Tilt slightly downward
	add_child(light)
	return light


func _build_hoverbike() -> void:
	# Sleek elongated body
	var chassis_mesh := CapsuleMesh.new()
	chassis_mesh.radius = 0.4
	chassis_mesh.height = 3.5
	_chassis = MeshInstance3D.new()
	_chassis.name = "Chassis"
	_chassis.mesh = chassis_mesh
	_chassis.material_override = _chassis_mat
	_chassis.position = Vector3(0, 0.8, 0)
	_chassis.rotation_degrees.x = 90  # Lay it flat
	_chassis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_chassis)

	# Headlight
	_headlight_l = _make_light("HeadL", Vector3(0, 0.9, 1.8))

	# SpotLight3D headlights — hoverbike has two as well, placed close together
	_headlight_spot_l = _make_headlight_spot(Vector3(-0.15, 0.9, 1.8))
	_headlight_spot_r = _make_headlight_spot(Vector3(0.15, 0.9, 1.8))

	# Dashboard panel
	_build_dashboard(Vector3(0, 1.0, 0.6))

	# Hover glow underneath
	_build_hover_glow()


func _build_tank() -> void:
	# Wide heavy chassis
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(2.5, 0.7, 3.5)
	_chassis = MeshInstance3D.new()
	_chassis.name = "Chassis"
	_chassis.mesh = chassis_mesh
	_chassis.material_override = _chassis_mat
	_chassis.position = Vector3(0, 0.5, 0)
	_chassis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_chassis)

	# Turret
	var turret_mesh := CapsuleMesh.new()
	turret_mesh.radius = 0.5
	turret_mesh.height = 1.2
	_cabin = MeshInstance3D.new()
	_cabin.name = "Turret"
	_cabin.mesh = turret_mesh
	_cabin.material_override = _chassis_mat
	_cabin.position = Vector3(0, 1.2, -0.2)
	_cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_cabin)

	# Treads (simplified as boxes)
	var tread_mat := StandardMaterial3D.new()
	tread_mat.albedo_color = Color(0.15, 0.15, 0.17)
	tread_mat.roughness = 0.9

	for side in [-1, 1]:
		var tread_mesh := BoxMesh.new()
		tread_mesh.size = Vector3(0.4, 0.4, 3.8)
		var tread := MeshInstance3D.new()
		tread.name = "Tread%s" % ("L" if side < 0 else "R")
		tread.mesh = tread_mesh
		tread.material_override = tread_mat
		tread.position = Vector3(side * 1.3, 0.25, 0)
		tread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(tread)

	# Tank headlights — mounted on front of chassis
	_headlight_l = _make_light("HeadL", Vector3(-0.8, 0.6, 1.8))
	_headlight_r = _make_light("HeadR", Vector3(0.8, 0.6, 1.8))
	_headlight_spot_l = _make_headlight_spot(Vector3(-0.8, 0.6, 1.8))
	_headlight_spot_r = _make_headlight_spot(Vector3(0.8, 0.6, 1.8))

	# Dashboard panel inside tank
	_build_dashboard(Vector3(0, 0.95, 0.5))

	# Turret pivot with barrel
	_build_turret_pivot()


func _make_wheel(node_name: String, pos: Vector3) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.3
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = _wheel_mat
	inst.position = pos
	inst.rotation_degrees.z = 90  # Wheel orientation
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)
	return inst


func _make_light(node_name: String, pos: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = _light_mat
	inst.position = pos
	add_child(inst)
	return inst


func _build_dashboard(pos: Vector3) -> void:
	## Small flat panel in front of the driver position.
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.6, 0.35, 0.05)
	_dashboard = MeshInstance3D.new()
	_dashboard.name = "Dashboard"
	_dashboard.mesh = dash_mesh
	_dashboard.position = pos

	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.08, 0.08, 0.12)
	dash_mat.roughness = 0.2
	dash_mat.metallic = 0.7
	dash_mat.emission_enabled = true
	dash_mat.emission = Color(0.1, 0.4, 0.6)
	dash_mat.emission_energy_multiplier = 0.6
	_dashboard.material_override = dash_mat
	_dashboard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dashboard)


func _build_hover_glow() -> void:
	## Cyan omni light underneath the hoverbike for hover effect.
	_hover_glow = OmniLight3D.new()
	_hover_glow.name = "HoverGlow"
	_hover_glow.light_color = Color(0.0, 0.85, 1.0)
	_hover_glow.light_energy = 1.5
	_hover_glow.omni_range = 4.0
	_hover_glow.omni_attenuation = 1.5
	_hover_glow.shadow_enabled = false
	_hover_glow.position = Vector3(0, 0.15, 0)
	add_child(_hover_glow)


func _build_turret_pivot() -> void:
	## Separate pivot node for turret rotation on tank. Reparents the turret mesh.
	_turret_pivot = Node3D.new()
	_turret_pivot.name = "TurretPivot"
	_turret_pivot.position = Vector3(0, 1.2, -0.2)
	add_child(_turret_pivot)

	# Build turret barrel extending forward from the pivot
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.08
	barrel_mesh.bottom_radius = 0.1
	barrel_mesh.height = 1.8
	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	barrel.mesh = barrel_mesh
	barrel.material_override = _chassis_mat
	barrel.rotation_degrees.x = 90  # Lay horizontal (forward)
	barrel.position = Vector3(0, 0.0, 1.4)
	barrel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_turret_pivot.add_child(barrel)


func _update_headlights_for_time() -> void:
	## Enable headlights automatically during night hours.
	var t := GameManager.time_of_day
	var is_night := t < 0.22 or t > 0.78
	if _headlight_spot_l:
		_headlight_spot_l.visible = is_mounted and is_night
	if _headlight_spot_r:
		_headlight_spot_r.visible = is_mounted and is_night
	# Also update headlight mesh emission
	if _light_mat:
		_light_mat.emission_energy_multiplier = 3.0 if (is_mounted and is_night) else 0.5


func _update_suspension_bob(delta: float) -> void:
	## Subtle vertical oscillation on ground vehicles based on speed.
	if vehicle_type == VehicleType.HOVERBIKE:
		return
	if not is_mounted or not _chassis:
		return
	var speed_ratio := absf(_current_speed) / max_speed
	if speed_ratio < 0.05:
		# Settle back to rest position smoothly
		_chassis.position.y = move_toward(_chassis.position.y, _get_chassis_rest_y(), delta * 2.0)
		return
	_suspension_time += delta * (3.0 + speed_ratio * 5.0)
	var bob_amplitude := 0.02 + speed_ratio * 0.04
	var bob_offset := sin(_suspension_time) * bob_amplitude
	_chassis.position.y = _get_chassis_rest_y() + bob_offset


func _get_chassis_rest_y() -> float:
	match vehicle_type:
		VehicleType.ROVER:
			return 0.6
		VehicleType.TANK:
			return 0.5
		_:
			return 0.8


func _update_hover_glow(delta: float) -> void:
	## Pulsing cyan glow under hoverbike.
	if vehicle_type != VehicleType.HOVERBIKE or not _hover_glow:
		return
	_hover_glow_time += delta * 2.5
	var pulse := 1.0 + sin(_hover_glow_time) * 0.5
	_hover_glow.light_energy = pulse * (2.0 if is_mounted else 0.8)


func _update_turret_rotation(delta: float) -> void:
	## Slowly rotate turret toward camera look direction.
	if vehicle_type != VehicleType.TANK or not _turret_pivot or not is_mounted:
		return
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	# Get camera forward direction projected onto the XZ plane
	var cam_forward := -camera.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	if cam_forward.length_squared() < 0.001:
		return
	# Target angle in local space: convert world direction to local
	var local_forward := global_transform.basis.inverse() * cam_forward
	var target_angle := atan2(-local_forward.x, -local_forward.z)
	# Smoothly rotate toward target
	var current_angle := _turret_pivot.rotation.y
	_turret_pivot.rotation.y = lerp_angle(current_angle, target_angle, delta * 2.0)


func _physics_process(delta: float) -> void:
	if not is_mounted:
		# Parked vehicle — apply gravity
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		# Still update passive visuals while parked
		_update_hover_glow(delta)
		return

	# ── Mounted movement ──
	# Apply gravity
	if not is_on_floor() and vehicle_type != VehicleType.HOVERBIKE:
		velocity.y -= GRAVITY * delta

	# Hoverbike hovers above ground
	if vehicle_type == VehicleType.HOVERBIKE and _terrain and _terrain.has_method("get_height_at"):
		var target_y: float = _terrain.get_height_at(position.x, position.z) + 1.5
		velocity.y = (target_y - position.y) * 5.0

	# Input
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_right", "move_left")
	var braking := Input.is_action_pressed("crouch_descend")

	# Acceleration / braking
	if braking:
		_current_speed = move_toward(_current_speed, 0.0, brake_force * delta)
	elif absf(throttle) > 0.1:
		_current_speed = move_toward(_current_speed, throttle * max_speed, acceleration_rate * delta)
	else:
		_current_speed = move_toward(_current_speed, 0.0, brake_force * 0.3 * delta)

	# Steering — only when moving
	if absf(_current_speed) > 0.5:
		rotation.y += steer * turn_speed * delta * sign(_current_speed)

	# Apply velocity in vehicle's forward direction
	var forward := -global_transform.basis.z
	velocity.x = forward.x * _current_speed
	velocity.z = forward.z * _current_speed

	move_and_slide()

	# Animate wheels
	_animate_wheels(delta)

	# Dust trail — emit when moving on ground
	if _dust_trail:
		var speed_ratio := absf(_current_speed) / max_speed
		_dust_trail.emitting = is_on_floor() and speed_ratio > 0.15
		if _dust_trail.emitting:
			var mat_d: ParticleProcessMaterial = _dust_trail.process_material as ParticleProcessMaterial
			if mat_d:
				mat_d.initial_velocity_max = 1.0 + speed_ratio * 4.0

	# Update vehicle shader speed parameter
	if _chassis_shader_mat:
		_chassis_shader_mat.set_shader_parameter("vehicle_speed", absf(_current_speed) / max_speed)

	# Polish updates — suspension bob, hover glow, turret rotation
	_update_suspension_bob(delta)
	_update_hover_glow(delta)
	_update_turret_rotation(delta)
	_update_headlights_for_time()

	# Sync player position to vehicle
	if _player and is_instance_valid(_player):
		_player.global_position = global_position + Vector3(0, 1.5, 0)
		_player.rotation.y = rotation.y


func mount(player: CharacterBody3D) -> void:
	## Player enters the vehicle.
	is_mounted = true
	_player = player
	_player.set_physics_process(false)
	_player.visible = false  # Hide player model while in vehicle
	# Headlights are now controlled by _update_headlights_for_time() each frame
	_update_headlights_for_time()
	# Dashboard emits slightly brighter when mounted
	if _dashboard:
		var dash_mat: StandardMaterial3D = _dashboard.material_override as StandardMaterial3D
		if dash_mat:
			dash_mat.emission_energy_multiplier = 1.2
	player_mounted.emit()


func dismount() -> void:
	## Player exits the vehicle.
	if not _player or not is_instance_valid(_player):
		return

	is_mounted = false
	_current_speed = 0.0
	_player.set_physics_process(true)
	_player.visible = true
	# Turn off headlights on dismount
	if _headlight_spot_l:
		_headlight_spot_l.visible = false
	if _headlight_spot_r:
		_headlight_spot_r.visible = false
	# Stop dust trail
	if _dust_trail:
		_dust_trail.emitting = false
	# Dim dashboard on dismount
	if _dashboard:
		var dash_mat: StandardMaterial3D = _dashboard.material_override as StandardMaterial3D
		if dash_mat:
			dash_mat.emission_energy_multiplier = 0.6
	# Reset suspension
	_suspension_time = 0.0
	# Place player beside vehicle
	_player.global_position = global_position + global_transform.basis.x * 2.0 + Vector3(0, 1.0, 0)
	_player.velocity = Vector3.ZERO
	player_dismounted.emit()


func _animate_wheels(delta: float) -> void:
	if vehicle_type != VehicleType.ROVER:
		return
	var wheel_rotation := _current_speed * delta * 3.0
	for w in [_wheel_fl, _wheel_fr, _wheel_bl, _wheel_br]:
		if w:
			w.rotation.x += wheel_rotation
