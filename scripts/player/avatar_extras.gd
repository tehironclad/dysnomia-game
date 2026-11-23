class_name AvatarExtras
extends Node3D
## The crow companion (only for a wallet holding >= 25 CROWS: a universal
## bouncer) and the jetpack flames, shared by the avatar. Moved out of the old
## procedural bear model unchanged.

var _crow_pivot: Node3D        # Orbiting pivot point above player
var _crow_body: MeshInstance3D
var _crow_head: MeshInstance3D
var _crow_beak: MeshInstance3D
var _crow_wing_left_pivot: Node3D
var _crow_wing_right_pivot: Node3D
var _crow_wing_left: MeshInstance3D
var _crow_wing_right: MeshInstance3D
var _crow_tail: MeshInstance3D
var _crow_eye_left: MeshInstance3D
var _crow_eye_right: MeshInstance3D
var _crow_mat: StandardMaterial3D
var _crow_beak_mat: StandardMaterial3D
var _crow_eye_mat: StandardMaterial3D
var _crow_orbit_angle: float = 0.0  # Current orbit position
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


var _crow_bank_angle: float = 0.0    # Current bank (roll) angle
var _crow_glide_timer: float = 0.0   # Time until next glide/flap transition
var _crow_is_gliding: bool = false   # Whether currently in glide mode


func _build_crow() -> void:
	## Build a procedural crow with proper bird proportions.
	## Streamlined teardrop body, pointed wings, fan tail, sharp beak.

	# Feather material — near-black with subtle iridescent sheen
	_crow_mat = StandardMaterial3D.new()
	_crow_mat.albedo_color = Color(0.04, 0.04, 0.06)  # Deep black feathers
	_crow_mat.roughness = 0.55  # Feathers have some sheen
	_crow_mat.metallic = 0.15   # Slight iridescence

	# Beak — dark horn material
	_crow_beak_mat = StandardMaterial3D.new()
	_crow_beak_mat.albedo_color = Color(0.08, 0.06, 0.04)  # Nearly black beak
	_crow_beak_mat.roughness = 0.25
	_crow_beak_mat.metallic = 0.1

	# Eyes — dark glossy beads, no glow
	_crow_eye_mat = StandardMaterial3D.new()
	_crow_eye_mat.albedo_color = Color(0.02, 0.02, 0.02)
	_crow_eye_mat.roughness = 0.05
	_crow_eye_mat.metallic = 0.5

	# Crow pivot — orbits around the player
	_crow_pivot = Node3D.new()
	_crow_pivot.name = "CrowPivot"
	_crow_pivot.position = Vector3(0.0, 2.4, 0.0)  # Above player's head
	_crow_pivot.visible = false  # only for a real CROWS holder (set_crow)
	add_child(_crow_pivot)

	# Body — elongated teardrop (wider at chest, tapers to tail)
	_crow_body = _make_sphere_child("CrowBody", 0.09, _crow_mat, _crow_pivot)
	_crow_body.scale = Vector3(0.55, 0.5, 1.6)  # Streamlined teardrop

	# Head — slightly smaller, positioned forward and up
	_crow_head = _make_sphere_child("CrowHead", 0.04, _crow_mat, _crow_pivot)

	# Beak — elongated pointed wedge (proper crow beak)
	_crow_beak = MeshInstance3D.new()
	_crow_beak.name = "CrowBeak"
	var beak_mesh := PrismMesh.new()
	beak_mesh.size = Vector3(0.018, 0.014, 0.05)
	_crow_beak.mesh = beak_mesh
	_crow_beak.material_override = _crow_beak_mat
	_crow_beak.layers = 0x2  # Layer 2 only — excluded from player's own flashlight
	_crow_pivot.add_child(_crow_beak)

	# Eyes — small glossy beads on sides of head
	_crow_eye_left = _make_sphere_child("CrowEyeL", 0.008, _crow_eye_mat, _crow_pivot)
	_crow_eye_right = _make_sphere_child("CrowEyeR", 0.008, _crow_eye_mat, _crow_pivot)

	# Wing pivots — at shoulder of bird body
	_crow_wing_left_pivot = Node3D.new()
	_crow_wing_left_pivot.name = "CrowWingLPivot"
	_crow_pivot.add_child(_crow_wing_left_pivot)

	_crow_wing_right_pivot = Node3D.new()
	_crow_wing_right_pivot.name = "CrowWingRPivot"
	_crow_pivot.add_child(_crow_wing_right_pivot)

	# Wings — tapered shape (wider at body, narrow at tip)
	# Inner wing section (wider)
	_crow_wing_left = _make_box_child("CrowWingL", Vector3(0.14, 0.005, 0.09), _crow_mat, _crow_wing_left_pivot)
	_crow_wing_left.position = Vector3(-0.08, 0.0, 0.01)
	# Wing tip extension (tapered)
	var wing_tip_l := _make_box_child("CrowWingTipL", Vector3(0.08, 0.004, 0.06), _crow_mat, _crow_wing_left_pivot)
	wing_tip_l.position = Vector3(-0.19, 0.002, 0.02)
	wing_tip_l.rotation_degrees.y = 8.0  # Swept back

	_crow_wing_right = _make_box_child("CrowWingR", Vector3(0.14, 0.005, 0.09), _crow_mat, _crow_wing_right_pivot)
	_crow_wing_right.position = Vector3(0.08, 0.0, 0.01)
	var wing_tip_r := _make_box_child("CrowWingTipR", Vector3(0.08, 0.004, 0.06), _crow_mat, _crow_wing_right_pivot)
	wing_tip_r.position = Vector3(0.19, 0.002, 0.02)
	wing_tip_r.rotation_degrees.y = -8.0

	# Tail fan — wider, fan-shaped (crows have distinctive fan tails)
	_crow_tail = _make_box_child("CrowTail", Vector3(0.06, 0.005, 0.07), _crow_mat, _crow_pivot)
	# Secondary tail feathers for fan effect
	var tail_l := _make_box_child("CrowTailL", Vector3(0.04, 0.004, 0.06), _crow_mat, _crow_pivot)
	tail_l.rotation_degrees.y = 15.0
	var tail_r := _make_box_child("CrowTailR", Vector3(0.04, 0.004, 0.06), _crow_mat, _crow_pivot)
	tail_r.rotation_degrees.y = -15.0

	# Feet — tiny dark talons tucked under body (visible during flight)
	var foot_mat := StandardMaterial3D.new()
	foot_mat.albedo_color = Color(0.06, 0.05, 0.04)
	foot_mat.roughness = 0.3
	var foot_l := _make_box_child("CrowFootL", Vector3(0.008, 0.02, 0.025), foot_mat, _crow_pivot)
	var foot_r := _make_box_child("CrowFootR", Vector3(0.008, 0.02, 0.025), foot_mat, _crow_pivot)

	# Store tail sub-parts for animation
	_crow_tail.set_meta("tail_l", tail_l)
	_crow_tail.set_meta("tail_r", tail_r)
	_crow_tail.set_meta("foot_l", foot_l)
	_crow_tail.set_meta("foot_r", foot_r)


func _animate_crow(t: float, delta: float) -> void:
	## Crow companion with realistic flight: soaring, banking into turns,
	## alternating between flapping and gliding, body tilt, tail fanning.
	if not _crow_pivot:
		return

	# ── Orbit with variable speed (faster in flap, slower in glide) ──
	var orbit_speed := 0.5 if _crow_is_gliding else 0.7
	_crow_orbit_angle += delta * orbit_speed
	if _crow_orbit_angle > TAU:
		_crow_orbit_angle -= TAU

	# Varied orbit radius: not a perfect circle — figure-8 influenced
	var orbit_radius := 1.3 + sin(_crow_orbit_angle * 2.0) * 0.25
	# Height variation: soars up when banking, dips between turns
	var height_wave := sin(_crow_orbit_angle * 2.0) * 0.35 + sin(_crow_orbit_angle * 3.0) * 0.12

	var cx := cos(_crow_orbit_angle) * orbit_radius
	var cz := sin(_crow_orbit_angle) * orbit_radius
	var cy := height_wave

	var crow_pos := Vector3(cx, cy, cz)
	var crow_forward := Vector3(-sin(_crow_orbit_angle), 0.0, cos(_crow_orbit_angle)).normalized()
	var crow_right := crow_forward.cross(Vector3.UP).normalized()
	var yaw := atan2(-crow_forward.x, -crow_forward.z)

	# ── Banking: body rolls into turns ──
	var turn_rate := orbit_speed / orbit_radius
	var target_bank := clampf(turn_rate * 25.0, -35.0, 35.0)
	# Add height-based bank: bank more when climbing
	if height_wave > 0.15:
		target_bank += 8.0
	_crow_bank_angle = lerpf(_crow_bank_angle, target_bank, 3.0 * delta)

	# ── Flap/glide cycle ──
	_crow_glide_timer -= delta
	if _crow_glide_timer <= 0.0:
		_crow_is_gliding = not _crow_is_gliding
		if _crow_is_gliding:
			_crow_glide_timer = randf_range(1.5, 3.0)  # Glide 1.5-3 seconds
		else:
			_crow_glide_timer = randf_range(2.0, 4.5)  # Flap 2-4.5 seconds

	# ── Wing animation ──
	var flap: float
	var wing_sweep: float = 0.0  # Forward/back sweep angle
	if _crow_is_gliding:
		# Glide: wings held out with gentle wobble
		flap = lerpf(5.0, 5.0 + sin(t * 1.2) * 3.0, 1.0)
		wing_sweep = 5.0  # Wings swept slightly back
	else:
		# Flap: powerful downstroke, quick upstroke (asymmetric)
		var flap_phase := fmod(t * 7.0, TAU)
		var downstroke := maxf(0.0, sin(flap_phase))  # Slow, powerful
		var upstroke := maxf(0.0, -sin(flap_phase)) * 0.7  # Quick, compact
		flap = (downstroke - upstroke) * 40.0
		# Wings sweep forward on downstroke for thrust
		wing_sweep = -downstroke * 8.0

	# ── Position all parts ──
	if _crow_body:
		_crow_body.position = crow_pos
		_crow_body.rotation.y = yaw
		_crow_body.rotation.z = deg_to_rad(_crow_bank_angle)
		# Pitch: nose up when climbing, down when descending
		var pitch := clampf(height_wave * 8.0, -12.0, 15.0)
		_crow_body.rotation.x = deg_to_rad(pitch)
		# Subtle bob synced to wingbeats
		if not _crow_is_gliding:
			_crow_body.position.y += sin(t * 14.0) * 0.005

	if _crow_head:
		_crow_head.position = crow_pos + crow_forward * 0.13 + Vector3(0, 0.035, 0)
		_crow_head.rotation.y = yaw
		# Head turns slightly to look around (crows are curious)
		_crow_head.rotation.y += sin(t * 0.8) * 0.15
	if _crow_beak:
		_crow_beak.position = crow_pos + crow_forward * 0.18 + Vector3(0, 0.028, 0)
		_crow_beak.rotation.y = yaw
		_crow_beak.rotation.x = deg_to_rad(-90.0)  # Point forward

	# Eyes positioned on head sides
	if _crow_eye_left:
		_crow_eye_left.position = crow_pos + crow_forward * 0.14 + crow_right * 0.025 + Vector3(0, 0.042, 0)
	if _crow_eye_right:
		_crow_eye_right.position = crow_pos + crow_forward * 0.14 - crow_right * 0.025 + Vector3(0, 0.042, 0)

	# Tail: fans out during turns and gliding
	var tail_spread := 0.0
	if _crow_is_gliding:
		tail_spread = 5.0 + absf(_crow_bank_angle) * 0.3
	else:
		tail_spread = 3.0
	if _crow_tail:
		_crow_tail.position = crow_pos - crow_forward * 0.16 + Vector3(0, -0.01, 0)
		_crow_tail.rotation.y = yaw
		# Tail tilts for steering
		_crow_tail.rotation.z = deg_to_rad(_crow_bank_angle * 0.5)
		# Fan sub-feathers
		var tail_l = _crow_tail.get_meta("tail_l", null)
		var tail_r = _crow_tail.get_meta("tail_r", null)
		if tail_l:
			tail_l.position = crow_pos - crow_forward * 0.14 + crow_right * 0.02 + Vector3(0, -0.008, 0)
			tail_l.rotation.y = yaw + deg_to_rad(tail_spread)
		if tail_r:
			tail_r.position = crow_pos - crow_forward * 0.14 - crow_right * 0.02 + Vector3(0, -0.008, 0)
			tail_r.rotation.y = yaw - deg_to_rad(tail_spread)
		# Feet tuck under body
		var foot_l = _crow_tail.get_meta("foot_l", null)
		var foot_r = _crow_tail.get_meta("foot_r", null)
		if foot_l:
			foot_l.position = crow_pos + crow_right * 0.015 + Vector3(0, -0.035, 0)
		if foot_r:
			foot_r.position = crow_pos - crow_right * 0.015 + Vector3(0, -0.035, 0)

	# Wing pivots
	if _crow_wing_left_pivot:
		_crow_wing_left_pivot.position = crow_pos + crow_right * 0.04 + Vector3(0, 0.015, 0)
		_crow_wing_left_pivot.rotation.y = yaw
		_crow_wing_left_pivot.rotation_degrees.z = flap
		_crow_wing_left_pivot.rotation_degrees.x = wing_sweep
	if _crow_wing_right_pivot:
		_crow_wing_right_pivot.position = crow_pos - crow_right * 0.04 + Vector3(0, 0.015, 0)
		_crow_wing_right_pivot.rotation.y = yaw
		_crow_wing_right_pivot.rotation_degrees.z = -flap
		_crow_wing_right_pivot.rotation_degrees.x = wing_sweep


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
