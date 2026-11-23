class_name AvatarExtras
extends Node3D
## The crow companion (only for a wallet holding >= 25 CROWS: a universal
## bouncer; the bird itself is CrowModel) and the jetpack flames, shared by
## the avatar.

var _crow_pivot: Node3D  # flies in this node's space (the avatar's)
var _crow: CrowModel
var _flame_left: GPUParticles3D
var _flame_right: GPUParticles3D

var crow_enabled := false

func _ready() -> void:
	_build_crow()
	_crow_pivot.visible = crow_enabled
	_flame_left = _create_flame_particles("FlameLeft")
	_flame_right = _create_flame_particles("FlameRight")


func set_crow(on: bool) -> void:
	crow_enabled = on
	if _crow_pivot:
		_crow_pivot.visible = on


## Places the two flame emitters (in this node's space) and turns them on/off.
func set_flames(on: bool, left: Vector3, right: Vector3, intensity: float = 1.0) -> void:
	if _flame_left:
		_flame_left.position = left
		_flame_left.emitting = on
		_flame_left.amount_ratio = intensity
	if _flame_right:
		_flame_right.position = right
		_flame_right.emitting = on
		_flame_right.amount_ratio = intensity


func _process(delta: float) -> void:
	if _crow_pivot and _crow_pivot.visible:
		_animate_crow(Time.get_ticks_msec() / 1000.0, delta)


var _orbit := 0.0
var _bank := 0.0
var _glide := false
var _mode_t := 0.0
var _still_t := 0.0
var _perched := false


func _build_crow() -> void:
	_crow_pivot = Node3D.new()
	_crow_pivot.name = "CrowPivot"
	_crow_pivot.position = Vector3(1.5, 2.4, 0.0)
	_crow_pivot.visible = false  # only for a real CROWS holder (set_crow)
	add_child(_crow_pivot)
	_crow = CrowModel.new()
	_crow.name = "Crow"
	_crow_pivot.add_child(_crow)


## Where the crow perches: on the avatar's right shoulder, in this node's space.
func _perch_point() -> Vector3:
	var av := get_parent()
	var sk: Skeleton3D = av.get("skeleton") if av else null
	if sk:
		var b := sk.find_bone("clavicle_r")
		if b >= 0:
			var g: Transform3D = sk.global_transform * sk.get_bone_global_pose(b)
			return to_local(g.origin) + Vector3(0.0, 0.09, 0.0)
	return Vector3(-0.2, 1.62, 0.0)


func _animate_crow(_t: float, delta: float) -> void:
	## Circles above the player, flapping and gliding in turns, banking into
	## the circle; lands on the right shoulder when the player stands still a
	## few seconds, and takes off again when they move.
	var av := get_parent()
	var vel: Vector3 = av.get("_vel") if av and av.get("_vel") != null else Vector3.ZERO
	var still := Vector2(vel.x, vel.z).length() < 0.3 and absf(vel.y) < 0.3
	_still_t = _still_t + delta if still else 0.0
	_perched = _still_t > 3.0
	if _perched:
		var perch := _perch_point()
		var to := perch - _crow_pivot.position
		var dist := to.length()
		if dist > 0.03:
			# Fly in: flap, head for the shoulder, face the way it travels.
			_crow_pivot.position += to.normalized() * minf(dist, delta * maxf(1.2, dist * 2.5))
			_face(to)
			_crow_pivot.rotation.z = lerpf(_crow_pivot.rotation.z, 0.0, delta * 4.0)
			_crow.animate(delta, "flap" if dist > 0.25 else "glide", 0.0)
		else:
			_crow_pivot.position = perch
			_crow_pivot.rotation = Vector3(0.0, lerp_angle(_crow_pivot.rotation.y, 0.0, delta * 3.0), 0.0)
			_crow.animate(delta, "perch", 0.0)
		return
	_mode_t -= delta
	if _mode_t <= 0.0:
		_glide = not _glide
		_mode_t = randf_range(1.5, 3.0) if _glide else randf_range(2.0, 4.0)
	_orbit = fmod(_orbit + delta * (0.45 if _glide else 0.6), TAU)
	var r := 1.6 + sin(_orbit * 2.0) * 0.3
	var target := Vector3(cos(_orbit) * r, 2.5 + sin(_orbit * 2.0) * 0.35 + sin(_orbit * 3.0) * 0.12, sin(_orbit) * r)
	var to := target - _crow_pivot.position
	_crow_pivot.position += to * minf(1.0, delta * 3.0)  # eases back into the circle after a take-off
	var heading := Vector3(-sin(_orbit), 0.0, cos(_orbit))
	_face(heading.lerp(to, clampf(to.length() - 0.3, 0.0, 1.0)))
	_bank = lerpf(_bank, deg_to_rad(-28.0), delta * 2.0)
	_crow_pivot.rotation.z = _bank  # rolls into the turn: the circle's centre is on its right
	_crow.animate(delta, "glide" if _glide else "flap", _bank)


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	_crow_pivot.rotation.y = lerp_angle(_crow_pivot.rotation.y, yaw, 0.2)
	_crow_pivot.rotation.x = lerpf(_crow_pivot.rotation.x, clampf(dir.normalized().y, -0.5, 0.5) * 0.6, 0.1)



# ─── Mesh Builders (Root children) ──────────────────────────────────────

func _make_sphere(node_name: String, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	add_child(inst)
	return inst


func _make_box(node_name: String, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	add_child(inst)
	return inst


func _make_capsule(node_name: String, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	add_child(inst)
	return inst


func _make_torus(node_name: String, inner_radius: float, ring_radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = inner_radius + ring_radius * 2.0
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	add_child(inst)
	return inst


# ─── Mesh Builders (Parented to a specific node) ────────────────────────

func _make_sphere_child(node_name: String, radius: float, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	parent.add_child(inst)
	return inst


func _make_box_child(node_name: String, size: Vector3, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	parent.add_child(inst)
	return inst


func _make_capsule_child(node_name: String, radius: float, height: float, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	parent.add_child(inst)
	return inst


func _make_torus_child(node_name: String, inner_radius: float, ring_radius: float, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = inner_radius + ring_radius * 2.0
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inst.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	parent.add_child(inst)
	return inst



func _create_flame_particles(node_name: String) -> GPUParticles3D:
	## Create realistic jetpack flame — layered system with hot core + outer plume.
	## Uses a soft-circle shader instead of solid quads for volumetric look.
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.amount = 64
	particles.lifetime = 0.5
	particles.explosiveness = 0.0
	particles.randomness = 0.4
	particles.fixed_fps = 60
	particles.visibility_aabb = AABB(Vector3(-1.0, -3.0, -1.0), Vector3(2.0, 4.0, 2.0))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 6.0  # Tight initial cone
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0.0, 0.3, 0.0)  # Slight upward buoyancy (hot gas rises)

	mat.scale_min = 0.3
	mat.scale_max = 0.7
	mat.scale_curve = _make_flame_scale_curve()

	# Turbulence for flickering instability
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 2.0
	mat.turbulence_noise_speed_random = 0.5
	mat.turbulence_noise_scale = 8.0
	mat.turbulence_influence_min = 0.05
	mat.turbulence_influence_max = 0.2

	mat.damping_min = 0.5
	mat.damping_max = 1.5

	# Color ramp: white-hot core → blue → orange → smoke
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 0.95, 1.0))    # White-hot core
	gradient.add_point(0.1, Color(0.7, 0.85, 1.0, 0.95))  # Blue-white (hottest visible)
	gradient.add_point(0.3, Color(1.0, 0.7, 0.2, 0.85))   # Orange flame
	gradient.add_point(0.55, Color(1.0, 0.35, 0.08, 0.5))  # Deep orange-red
	gradient.add_point(0.8, Color(0.4, 0.15, 0.05, 0.2))   # Dark red ember
	gradient.set_color(1, Color(0.15, 0.1, 0.08, 0.0))     # Smoke fade

	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = gradient
	mat.color_ramp = color_ramp

	particles.process_material = mat

	# Draw pass: quad with soft-circle shader for volumetric look
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var shader_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = _get_flame_particle_shader()
	shader_mat.shader = shader
	quad.surface_set_material(0, shader_mat)

	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.layers = 0x2  # Layer 2 only — excluded from player's own flashlight

	# No OmniLight — flames are visual only, no character illumination

	add_child(particles)
	return particles


func _get_flame_particle_shader() -> String:
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
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	// Soft radial falloff — gaussian blob, not hard circle
	float alpha = exp(-dist * dist * 4.0);
	// Brighter hot core at center
	float core = exp(-dist * dist * 12.0);
	vec3 col = COLOR.rgb + vec3(core * 0.4);
	ALBEDO = col;
	ALPHA = alpha * COLOR.a;
}
"""


func _make_flame_scale_curve() -> CurveTexture:
	## Curve: quick expansion then gradual shrink (plume shape).
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))   # Starts small at nozzle
	curve.add_point(Vector2(0.15, 1.0))  # Expands quickly
	curve.add_point(Vector2(0.5, 0.7))   # Narrows
	curve.add_point(Vector2(1.0, 0.0))   # Fades to nothing
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex
