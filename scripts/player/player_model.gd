extends Node3D
## Procedural teddy bear astronaut character built from Godot primitives.
## Clockwork LAU bear head (Maria's lore: the clockwork LAU bears) with round ears, snout, and glowing eyes.
## White spacesuit body with backpack, gloves, boots, and jetpack flames.
## Full procedural animation: walk cycle, sprint, fly, falling, idle.
## Limbs use pivot Node3Ds for proper hierarchical rotation (gloves follow arms, boots follow legs).
## All colors/proportions driven by PlayerAppearance dictionary (Saat values).

# ─── Animation State Machine ──────────────────────────────────────────

enum AnimState { IDLE, WALK, SPRINT, FLY, FALLING }

var _anim_state: int = AnimState.IDLE
var _prev_anim_state: int = AnimState.IDLE  # For transition blending
var _anim_time: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _on_ground: bool = true
var _move_speed: float = 0.0
var _is_flying: bool = false
var _slope_angle: float = 0.0  # Current slope in degrees (0 = flat, positive = uphill)
var _move_direction: Vector3 = Vector3.ZERO  # Horizontal movement direction (normalized)
var _vertical_speed: float = 0.0  # For fly tilt
var _land_squash: float = 0.0     # Landing impact squash (0 = none, 1 = max)
var _land_squash_vel: float = 0.0  # Spring velocity for squash recovery
var _was_on_ground: bool = true
var _prev_fall_speed: float = 0.0  # Track fall speed before landing

# ─── Pivot Node References (rotation points for limbs) ──────────────

var _arm_pivot_left: Node3D   # Pivot at shoulder — contains upper arm + elbow_pivot
var _arm_pivot_right: Node3D
var _leg_pivot_left: Node3D   # Pivot at hip — contains upper leg + knee_pivot
var _leg_pivot_right: Node3D

# Sub-pivots for knee/elbow bending (children of main limb pivots)
var _knee_pivot_left: Node3D   # Pivot at knee — contains shin, boot parts
var _knee_pivot_right: Node3D
var _elbow_pivot_left: Node3D  # Pivot at elbow — contains forearm, glove parts
var _elbow_pivot_right: Node3D

# ─── Mesh References ─────────────────────────────────────────────────

var _head: MeshInstance3D
var _ear_left: MeshInstance3D
var _ear_right: MeshInstance3D
var _snout: MeshInstance3D
var _eye_left: MeshInstance3D
var _eye_right: MeshInstance3D
var _helmet_ring: MeshInstance3D
var _helmet_visor: MeshInstance3D
var _torso: MeshInstance3D
var _chest_panel: MeshInstance3D
var _backpack: MeshInstance3D
var _arm_left: MeshInstance3D       # Upper arm capsule (child of arm_pivot)
var _arm_right: MeshInstance3D
var _forearm_left: MeshInstance3D   # Forearm capsule (child of arm_pivot)
var _forearm_right: MeshInstance3D
var _shoulder_left: MeshInstance3D
var _shoulder_right: MeshInstance3D
var _glove_left: MeshInstance3D     # Glove (child of arm_pivot)
var _glove_right: MeshInstance3D
var _glove_thumb_left: MeshInstance3D
var _glove_thumb_right: MeshInstance3D
var _glove_cuff_left: MeshInstance3D
var _glove_cuff_right: MeshInstance3D
var _leg_left: MeshInstance3D       # Upper leg capsule (child of leg_pivot)
var _leg_right: MeshInstance3D
var _shin_left: MeshInstance3D      # Shin capsule (child of leg_pivot)
var _shin_right: MeshInstance3D
var _boot_left: MeshInstance3D      # Boot (child of leg_pivot)
var _boot_right: MeshInstance3D
var _boot_sole_left: MeshInstance3D
var _boot_sole_right: MeshInstance3D
var _boot_toe_left: MeshInstance3D
var _boot_toe_right: MeshInstance3D
var _nose: MeshInstance3D
var _belt: MeshInstance3D
var _mouth: MeshInstance3D
var _cheek_left: MeshInstance3D
var _cheek_right: MeshInstance3D
var _inner_ear_left: MeshInstance3D
var _inner_ear_right: MeshInstance3D
var _eye_shine_left: MeshInstance3D
var _eye_shine_right: MeshInstance3D
var _muzzle_pad: MeshInstance3D

# Finger meshes (children of elbow pivots)
var _finger_l1: MeshInstance3D
var _finger_l2: MeshInstance3D
var _finger_l3: MeshInstance3D
var _finger_l4: MeshInstance3D
var _finger_r1: MeshInstance3D
var _finger_r2: MeshInstance3D
var _finger_r3: MeshInstance3D
var _finger_r4: MeshInstance3D

# Boot detail meshes (children of knee pivots)
var _boot_heel_left: MeshInstance3D
var _boot_heel_right: MeshInstance3D
var _boot_cuff_left: MeshInstance3D
var _boot_cuff_right: MeshInstance3D
var _boot_tread_left: MeshInstance3D
var _boot_tread_right: MeshInstance3D

# Suit detail meshes
var _tube_left: MeshInstance3D
var _tube_right: MeshInstance3D
var _antenna_shaft: MeshInstance3D
var _antenna_tip: MeshInstance3D
var _knee_left: MeshInstance3D
var _knee_right: MeshInstance3D
var _elbow_left: MeshInstance3D
var _elbow_right: MeshInstance3D
var _status_green: MeshInstance3D
var _status_amber: MeshInstance3D
var _status_red: MeshInstance3D
var _seam_left: MeshInstance3D
var _seam_right: MeshInstance3D

# Crow companion
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

# Jetpack flame particles
var _flame_left: GPUParticles3D
var _flame_right: GPUParticles3D

# ─── Materials ───────────────────────────────────────────────────────

const CHARACTER_SHADER = preload("res://assets/shaders/character.gdshader")

var _fur_mat: StandardMaterial3D
var _suit_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _glove_mat: StandardMaterial3D   # Separate darker material for gloves
var _boot_mat: StandardMaterial3D    # Separate material for boots
var _eye_mat: StandardMaterial3D
var _snout_mat: StandardMaterial3D
var _nose_mat: StandardMaterial3D
var _backpack_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _panel_mat: StandardMaterial3D

# ShaderMaterial versions (premium character shader)
var _fur_shader_mat: ShaderMaterial
var _suit_shader_mat: ShaderMaterial
var _accent_shader_mat: ShaderMaterial
var _visor_shader_mat: ShaderMaterial
var _boot_shader_mat: ShaderMaterial
var _glove_shader_mat: ShaderMaterial
var _snout_shader_mat: ShaderMaterial  # Lighter tan fur for muzzle area

# Face detail materials
var _inner_ear_mat: StandardMaterial3D
var _eye_shine_mat: StandardMaterial3D
var _mouth_mat: StandardMaterial3D

# Status light materials (separate so they can have different emission colors)
var _status_green_mat: StandardMaterial3D
var _status_amber_mat: StandardMaterial3D
var _status_red_mat: StandardMaterial3D

# Scale factor (1.0 = default 1.8m tall)
var _scale_factor: float = 1.0
var _base_height: float = 1.8

# Default rest positions (saved during build for animation blending)
var _torso_rest_y: float = 0.95
var _arm_left_rest_rot_z: float = 8.0
var _arm_right_rest_rot_z: float = -8.0


func _ready() -> void:
	_build_model()
	GameManager.fly_mode_changed.connect(_on_fly_mode_changed)


func update_movement(vel: Vector3, on_floor: bool, flying: bool) -> void:
	## Called by player_controller each physics frame to drive animations.
	_velocity = vel
	_on_ground = on_floor
	_is_flying = flying
	_move_speed = Vector2(vel.x, vel.z).length()
	_vertical_speed = vel.y
	if _move_speed > 0.1:
		_move_direction = Vector3(vel.x, 0.0, vel.z).normalized()

	# Detect slope angle from CharacterBody3D parent
	_slope_angle = 0.0
	var parent := get_parent()
	if parent is CharacterBody3D and on_floor:
		var cb := parent as CharacterBody3D
		if cb.is_on_floor():
			var fn := cb.get_floor_normal()
			_slope_angle = rad_to_deg(acos(clampf(fn.y, -1.0, 1.0)))
			# Make slope negative when going downhill
			if vel.y < -0.5:
				_slope_angle = -_slope_angle

	# ── Landing impact detection ──
	if on_floor and not _was_on_ground:
		var impact := clampf(absf(_prev_fall_speed) / 20.0, 0.0, 1.0)
		if impact > 0.15:
			_land_squash = impact
			_land_squash_vel = 0.0
	_was_on_ground = on_floor
	if not on_floor:
		_prev_fall_speed = vel.y

	# Determine animation state
	_prev_anim_state = _anim_state
	if flying:
		_anim_state = AnimState.FLY
	elif not on_floor:
		_anim_state = AnimState.FALLING
	elif _move_speed > 7.0:
		_anim_state = AnimState.SPRINT
	elif _move_speed > 0.5:
		_anim_state = AnimState.WALK
	else:
		_anim_state = AnimState.IDLE


func _build_model() -> void:
	## Construct all mesh parts as children with proper hierarchy.
	## Limbs use pivot Node3Ds at joints so children rotate together.

	# --- Materials ---

	# Bear-brown fur (warm medium brown)
	_fur_mat = StandardMaterial3D.new()
	_fur_mat.albedo_color = Color(0.45, 0.30, 0.18)
	_fur_mat.roughness = 0.9
	_fur_mat.metallic = 0.0

	# PulseChain-themed spacesuit — deep purple/indigo base
	_suit_mat = StandardMaterial3D.new()
	_suit_mat.albedo_color = Color(0.22, 0.14, 0.38)  # Deep PulseChain purple
	_suit_mat.roughness = 0.45
	_suit_mat.metallic = 0.08

	# Suit accents — electric blue/purple metallic trim
	_accent_mat = StandardMaterial3D.new()
	_accent_mat.albedo_color = Color(0.35, 0.22, 0.55)  # Brighter purple accent
	_accent_mat.roughness = 0.30
	_accent_mat.metallic = 0.4

	# Astronaut gloves — dark charcoal with purple tint
	_glove_mat = StandardMaterial3D.new()
	_glove_mat.albedo_color = Color(0.18, 0.15, 0.25)
	_glove_mat.roughness = 0.55
	_glove_mat.metallic = 0.05

	# Astronaut boots — dark purple-black, rugged
	_boot_mat = StandardMaterial3D.new()
	_boot_mat.albedo_color = Color(0.15, 0.12, 0.22)
	_boot_mat.roughness = 0.6
	_boot_mat.metallic = 0.15

	# Visor — transparent blue-tinted glass, no emission
	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = Color(0.15, 0.25, 0.4, 0.6)
	_visor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_visor_mat.roughness = 0.1
	_visor_mat.metallic = 0.6

	# --- Character Shader Materials (premium PBR) ---
	_fur_shader_mat = ShaderMaterial.new()
	_fur_shader_mat.shader = CHARACTER_SHADER
	_fur_shader_mat.set_shader_parameter("surface_mode", 0)
	_fur_shader_mat.set_shader_parameter("base_color", Vector3(0.45, 0.30, 0.18))
	_fur_shader_mat.set_shader_parameter("base_roughness", 0.9)

	_suit_shader_mat = ShaderMaterial.new()
	_suit_shader_mat.shader = CHARACTER_SHADER
	_suit_shader_mat.set_shader_parameter("surface_mode", 1)
	_suit_shader_mat.set_shader_parameter("base_color", Vector3(0.22, 0.14, 0.38))  # PulseChain purple
	_suit_shader_mat.set_shader_parameter("base_roughness", 0.45)
	_suit_shader_mat.set_shader_parameter("base_metallic", 0.08)
	_suit_shader_mat.set_shader_parameter("power_accent", Vector3(0.55, 0.36, 0.95))  # Electric purple energy lines

	_accent_shader_mat = ShaderMaterial.new()
	_accent_shader_mat.shader = CHARACTER_SHADER
	_accent_shader_mat.set_shader_parameter("surface_mode", 3)
	_accent_shader_mat.set_shader_parameter("base_color", Vector3(0.35, 0.22, 0.55))  # Purple metallic
	_accent_shader_mat.set_shader_parameter("base_roughness", 0.30)
	_accent_shader_mat.set_shader_parameter("base_metallic", 0.4)

	_visor_shader_mat = ShaderMaterial.new()
	_visor_shader_mat.shader = CHARACTER_SHADER
	_visor_shader_mat.set_shader_parameter("surface_mode", 2)
	_visor_shader_mat.set_shader_parameter("base_color", Vector3(0.15, 0.25, 0.4))
	_visor_shader_mat.set_shader_parameter("emission_color", Vector3(0.2, 0.4, 0.7))
	_visor_shader_mat.set_shader_parameter("emission_strength", 0.0)  # No emission by default

	_boot_shader_mat = ShaderMaterial.new()
	_boot_shader_mat.shader = CHARACTER_SHADER
	_boot_shader_mat.set_shader_parameter("surface_mode", 1)
	_boot_shader_mat.set_shader_parameter("base_color", Vector3(0.15, 0.12, 0.22))  # Dark purple-black
	_boot_shader_mat.set_shader_parameter("base_roughness", 0.6)
	_boot_shader_mat.set_shader_parameter("base_metallic", 0.15)

	_glove_shader_mat = ShaderMaterial.new()
	_glove_shader_mat.shader = CHARACTER_SHADER
	_glove_shader_mat.set_shader_parameter("surface_mode", 1)
	_glove_shader_mat.set_shader_parameter("base_color", Vector3(0.18, 0.15, 0.25))  # Dark charcoal-purple
	_glove_shader_mat.set_shader_parameter("base_roughness", 0.55)

	# Chest control panel — dark indicator surface, no glow
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.albedo_color = Color(0.12, 0.12, 0.15)
	_panel_mat.roughness = 0.3
	_panel_mat.metallic = 0.4

	# Beady eyes — dark glossy, no glow
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.06, 0.04, 0.03)
	_eye_mat.roughness = 0.15
	_eye_mat.metallic = 0.4

	# Lighter tan snout area
	_snout_mat = StandardMaterial3D.new()
	_snout_mat.albedo_color = Color(0.55, 0.42, 0.30)
	_snout_mat.roughness = 0.85

	# Dark nose
	_nose_mat = StandardMaterial3D.new()
	_nose_mat.albedo_color = Color(0.1, 0.08, 0.06)
	_nose_mat.roughness = 0.25
	_nose_mat.metallic = 0.15

	# Face detail materials
	_inner_ear_mat = StandardMaterial3D.new()
	_inner_ear_mat.albedo_color = Color(0.62, 0.45, 0.38)  # Pinkish-tan inner ear
	_inner_ear_mat.roughness = 0.80

	_eye_shine_mat = StandardMaterial3D.new()
	_eye_shine_mat.albedo_color = Color(0.95, 0.95, 0.95)  # White specular highlight
	_eye_shine_mat.roughness = 0.05
	_eye_shine_mat.metallic = 0.0

	_mouth_mat = StandardMaterial3D.new()
	_mouth_mat.albedo_color = Color(0.08, 0.05, 0.04)  # Dark mouth line
	_mouth_mat.roughness = 0.7

	# Snout shader material (fur mode with lighter tan base)
	_snout_shader_mat = ShaderMaterial.new()
	_snout_shader_mat.shader = CHARACTER_SHADER
	_snout_shader_mat.set_shader_parameter("surface_mode", 0)  # Fur mode
	_snout_shader_mat.set_shader_parameter("base_color", Vector3(0.55, 0.42, 0.30))
	_snout_shader_mat.set_shader_parameter("base_roughness", 0.85)

	# Backpack — white matching suit, NO emission (status lights handle glow)
	_backpack_mat = StandardMaterial3D.new()
	_backpack_mat.albedo_color = Color(0.85, 0.85, 0.88)
	_backpack_mat.roughness = 0.4
	_backpack_mat.metallic = 0.15

	# Status light materials — colored but no emission/glow
	_status_green_mat = StandardMaterial3D.new()
	_status_green_mat.albedo_color = Color(0.1, 0.5, 0.15)
	_status_green_mat.roughness = 0.2
	_status_green_mat.metallic = 0.3
	_status_amber_mat = StandardMaterial3D.new()
	_status_amber_mat.albedo_color = Color(0.6, 0.45, 0.08)
	_status_amber_mat.roughness = 0.2
	_status_amber_mat.metallic = 0.3
	_status_red_mat = StandardMaterial3D.new()
	_status_red_mat.albedo_color = Color(0.5, 0.08, 0.05)
	_status_red_mat.roughness = 0.2
	_status_red_mat.metallic = 0.3

	# All Y positions are relative to bottom of feet = 0
	# Total height ~1.8m: boots 0-0.14, legs 0.14-0.65, torso 0.65-1.25, head 1.25-1.75

	# ─── Leg Pivots (at hip joints) ─────────────────────────────────
	# Pivot at hip so rotating moves the entire leg + knee + boot as one unit
	_leg_pivot_left = Node3D.new()
	_leg_pivot_left.name = "LegPivotLeft"
	_leg_pivot_left.position = Vector3(-0.13, 0.65, 0.0)  # Hip joint
	add_child(_leg_pivot_left)

	_leg_pivot_right = Node3D.new()
	_leg_pivot_right.name = "LegPivotRight"
	_leg_pivot_right.position = Vector3(0.13, 0.65, 0.0)  # Hip joint
	add_child(_leg_pivot_right)

	# Upper legs (children of leg pivots, positioned relative to hip)
	_leg_left = _make_capsule_child("LegLeft", 0.1, 0.35, _suit_mat, _leg_pivot_left)
	_leg_left.position = Vector3(0.0, -0.16, 0.0)  # Centered in upper leg

	_leg_right = _make_capsule_child("LegRight", 0.1, 0.35, _suit_mat, _leg_pivot_right)
	_leg_right.position = Vector3(0.0, -0.16, 0.0)

	# ── Knee Sub-Pivots (at knee joint, children of leg pivots) ──
	# Shin, boots, and knee torus are children of knee_pivot so they bend together
	_knee_pivot_left = Node3D.new()
	_knee_pivot_left.name = "KneePivotLeft"
	_knee_pivot_left.position = Vector3(0.0, -0.30, 0.0)  # Knee joint position
	_leg_pivot_left.add_child(_knee_pivot_left)

	_knee_pivot_right = Node3D.new()
	_knee_pivot_right.name = "KneePivotRight"
	_knee_pivot_right.position = Vector3(0.0, -0.30, 0.0)
	_leg_pivot_right.add_child(_knee_pivot_right)

	# Knee joints (children of knee pivots — at local origin)
	_knee_left = _make_torus_child("KneeLeft", 0.065, 0.015, _accent_mat, _knee_pivot_left)
	_knee_left.position = Vector3.ZERO

	_knee_right = _make_torus_child("KneeRight", 0.065, 0.015, _accent_mat, _knee_pivot_right)
	_knee_right.position = Vector3.ZERO

	# Shins (children of knee pivots — positioned below knee)
	_shin_left = _make_capsule_child("ShinLeft", 0.09, 0.28, _suit_mat, _knee_pivot_left)
	_shin_left.position = Vector3(0.0, -0.12, 0.0)  # Was -0.42 from hip, now -0.12 from knee

	_shin_right = _make_capsule_child("ShinRight", 0.09, 0.28, _suit_mat, _knee_pivot_right)
	_shin_right.position = Vector3(0.0, -0.12, 0.0)

	# Boots — rounded astronaut boots with ankle cuff, heel, and treaded sole

	# Ankle cuff — metallic trim ring at top of boot
	_boot_cuff_left = _make_torus_child("BootCuffLeft", 0.095, 0.015, _accent_mat, _knee_pivot_left)
	_boot_cuff_left.position = Vector3(0.0, -0.22, 0.0)

	_boot_cuff_right = _make_torus_child("BootCuffRight", 0.095, 0.015, _accent_mat, _knee_pivot_right)
	_boot_cuff_right.position = Vector3(0.0, -0.22, 0.0)

	# Main boot body — capsule instead of box for rounded shape
	_boot_left = _make_capsule_child("BootLeft", 0.09, 0.18, _boot_mat, _knee_pivot_left)
	_boot_left.position = Vector3(0.0, -0.29, 0.02)

	_boot_right = _make_capsule_child("BootRight", 0.09, 0.18, _boot_mat, _knee_pivot_right)
	_boot_right.position = Vector3(0.0, -0.29, 0.02)

	# Boot toe cap — larger, more prominent rounded front
	_boot_toe_left = _make_sphere_child("BootToeLeft", 0.075, _boot_mat, _knee_pivot_left)
	_boot_toe_left.position = Vector3(0.0, -0.31, 0.10)
	_boot_toe_left.scale = Vector3(1.1, 0.65, 0.9)

	_boot_toe_right = _make_sphere_child("BootToeRight", 0.075, _boot_mat, _knee_pivot_right)
	_boot_toe_right.position = Vector3(0.0, -0.31, 0.10)
	_boot_toe_right.scale = Vector3(1.1, 0.65, 0.9)

	# Heel bump — small sphere at the back
	_boot_heel_left = _make_sphere_child("BootHeelLeft", 0.05, _boot_mat, _knee_pivot_left)
	_boot_heel_left.position = Vector3(0.0, -0.32, -0.06)
	_boot_heel_left.scale = Vector3(0.9, 0.7, 0.8)

	_boot_heel_right = _make_sphere_child("BootHeelRight", 0.05, _boot_mat, _knee_pivot_right)
	_boot_heel_right.position = Vector3(0.0, -0.32, -0.06)
	_boot_heel_right.scale = Vector3(0.9, 0.7, 0.8)

	# Boot sole — wider, slightly protruding
	_boot_sole_left = _make_box_child("BootSoleLeft", Vector3(0.18, 0.035, 0.25), _accent_mat, _knee_pivot_left)
	_boot_sole_left.position = Vector3(0.0, -0.36, 0.02)

	_boot_sole_right = _make_box_child("BootSoleRight", Vector3(0.18, 0.035, 0.25), _accent_mat, _knee_pivot_right)
	_boot_sole_right.position = Vector3(0.0, -0.36, 0.02)

	# Tread ridges — thin strips across the sole bottom
	_boot_tread_left = _make_box_child("BootTreadLeft", Vector3(0.16, 0.008, 0.22), _accent_mat, _knee_pivot_left)
	_boot_tread_left.position = Vector3(0.0, -0.375, 0.02)

	_boot_tread_right = _make_box_child("BootTreadRight", Vector3(0.16, 0.008, 0.22), _accent_mat, _knee_pivot_right)
	_boot_tread_right.position = Vector3(0.0, -0.375, 0.02)

	# --- Belt (torus at waist) ---
	_belt = _make_torus("Belt", 0.18, 0.025, _accent_mat)
	_belt.position = Vector3(0.0, 0.65, 0.0)

	# --- Torso (bulky suit) ---
	_torso = _make_capsule("Torso", 0.24, 0.55, _suit_mat)
	_torso.position = Vector3(0.0, 0.95, 0.0)

	# --- Suit Seam Lines (thin strips along torso sides) ---
	_seam_left = _make_box("SeamLeft", Vector3(0.01, 0.45, 0.01), _accent_mat)
	_seam_left.position = Vector3(-0.22, 0.95, 0.0)

	_seam_right = _make_box("SeamRight", Vector3(0.01, 0.45, 0.01), _accent_mat)
	_seam_right.position = Vector3(0.22, 0.95, 0.0)

	# --- Chest control panel ---
	_chest_panel = _make_box("ChestPanel", Vector3(0.16, 0.1, 0.04), _panel_mat)
	_chest_panel.position = Vector3(0.0, 0.95, 0.24)

	# --- Shoulder pads ---
	_shoulder_left = _make_sphere("ShoulderLeft", 0.1, _suit_mat)
	_shoulder_left.position = Vector3(-0.3, 1.1, 0.0)

	_shoulder_right = _make_sphere("ShoulderRight", 0.1, _suit_mat)
	_shoulder_right.position = Vector3(0.3, 1.1, 0.0)

	# ─── Arm Pivots (at shoulder joints) ────────────────────────────
	# Pivot at shoulder so rotating moves the entire arm + elbow + glove as one
	_arm_pivot_left = Node3D.new()
	_arm_pivot_left.name = "ArmPivotLeft"
	_arm_pivot_left.position = Vector3(-0.3, 1.08, 0.0)  # Shoulder joint
	_arm_pivot_left.rotation_degrees.z = 8.0
	add_child(_arm_pivot_left)

	_arm_pivot_right = Node3D.new()
	_arm_pivot_right.name = "ArmPivotRight"
	_arm_pivot_right.position = Vector3(0.3, 1.08, 0.0)  # Shoulder joint
	_arm_pivot_right.rotation_degrees.z = -8.0
	add_child(_arm_pivot_right)

	# Upper arms (children of arm pivots, positioned relative to shoulder)
	_arm_left = _make_capsule_child("ArmLeft", 0.07, 0.28, _suit_mat, _arm_pivot_left)
	_arm_left.position = Vector3(0.0, -0.12, 0.0)

	_arm_right = _make_capsule_child("ArmRight", 0.07, 0.28, _suit_mat, _arm_pivot_right)
	_arm_right.position = Vector3(0.0, -0.12, 0.0)

	# ── Elbow Sub-Pivots (at elbow joint, children of arm pivots) ──
	# Forearm, gloves, and elbow torus are children of elbow_pivot so they bend together
	_elbow_pivot_left = Node3D.new()
	_elbow_pivot_left.name = "ElbowPivotLeft"
	_elbow_pivot_left.position = Vector3(0.0, -0.25, 0.0)  # Elbow joint position
	_arm_pivot_left.add_child(_elbow_pivot_left)

	_elbow_pivot_right = Node3D.new()
	_elbow_pivot_right.name = "ElbowPivotRight"
	_elbow_pivot_right.position = Vector3(0.0, -0.25, 0.0)
	_arm_pivot_right.add_child(_elbow_pivot_right)

	# Elbow joints (children of elbow pivots — at local origin)
	_elbow_left = _make_torus_child("ElbowLeft", 0.05, 0.012, _accent_mat, _elbow_pivot_left)
	_elbow_left.position = Vector3.ZERO

	_elbow_right = _make_torus_child("ElbowRight", 0.05, 0.012, _accent_mat, _elbow_pivot_right)
	_elbow_right.position = Vector3.ZERO

	# Forearms (children of elbow pivots — positioned below elbow)
	_forearm_left = _make_capsule_child("ForearmLeft", 0.065, 0.2, _suit_mat, _elbow_pivot_left)
	_forearm_left.position = Vector3(0.0, -0.10, 0.0)  # Was -0.35 from shoulder, now -0.10 from elbow

	_forearm_right = _make_capsule_child("ForearmRight", 0.065, 0.2, _suit_mat, _elbow_pivot_right)
	_forearm_right.position = Vector3(0.0, -0.10, 0.0)

	# Glove cuffs — ring around wrist (children of elbow pivots)
	_glove_cuff_left = _make_torus_child("GloveCuffLeft", 0.055, 0.012, _accent_mat, _elbow_pivot_left)
	_glove_cuff_left.position = Vector3(0.0, -0.18, 0.0)

	_glove_cuff_right = _make_torus_child("GloveCuffRight", 0.055, 0.012, _accent_mat, _elbow_pivot_right)
	_glove_cuff_right.position = Vector3(0.0, -0.18, 0.0)

	# Astronaut gloves — rounded palm (sphere instead of box)
	_glove_left = _make_sphere_child("GloveLeft", 0.06, _glove_mat, _elbow_pivot_left)
	_glove_left.position = Vector3(0.0, -0.23, 0.01)
	_glove_left.scale = Vector3(0.85, 0.65, 1.0)  # Flattened palm shape

	_glove_right = _make_sphere_child("GloveRight", 0.06, _glove_mat, _elbow_pivot_right)
	_glove_right.position = Vector3(0.0, -0.23, 0.01)
	_glove_right.scale = Vector3(0.85, 0.65, 1.0)

	# Finger bumps — 4 small capsules in a row along front edge of palm (left hand)
	_finger_l1 = _make_capsule_child("FingerL1", 0.016, 0.05, _glove_mat, _elbow_pivot_left)
	_finger_l1.position = Vector3(-0.03, -0.245, 0.055)
	_finger_l1.rotation_degrees.x = 10.0  # Slightly curled

	_finger_l2 = _make_capsule_child("FingerL2", 0.017, 0.055, _glove_mat, _elbow_pivot_left)
	_finger_l2.position = Vector3(-0.01, -0.25, 0.06)
	_finger_l2.rotation_degrees.x = 8.0  # Middle finger — slightly longer

	_finger_l3 = _make_capsule_child("FingerL3", 0.016, 0.05, _glove_mat, _elbow_pivot_left)
	_finger_l3.position = Vector3(0.01, -0.245, 0.055)
	_finger_l3.rotation_degrees.x = 10.0

	_finger_l4 = _make_capsule_child("FingerL4", 0.014, 0.04, _glove_mat, _elbow_pivot_left)
	_finger_l4.position = Vector3(0.028, -0.24, 0.05)
	_finger_l4.rotation_degrees.x = 12.0  # Pinky — shorter, more curled

	# Right hand fingers (mirrored X positions)
	_finger_r1 = _make_capsule_child("FingerR1", 0.016, 0.05, _glove_mat, _elbow_pivot_right)
	_finger_r1.position = Vector3(0.03, -0.245, 0.055)
	_finger_r1.rotation_degrees.x = 10.0

	_finger_r2 = _make_capsule_child("FingerR2", 0.017, 0.055, _glove_mat, _elbow_pivot_right)
	_finger_r2.position = Vector3(0.01, -0.25, 0.06)
	_finger_r2.rotation_degrees.x = 8.0

	_finger_r3 = _make_capsule_child("FingerR3", 0.016, 0.05, _glove_mat, _elbow_pivot_right)
	_finger_r3.position = Vector3(-0.01, -0.245, 0.055)
	_finger_r3.rotation_degrees.x = 10.0

	_finger_r4 = _make_capsule_child("FingerR4", 0.014, 0.04, _glove_mat, _elbow_pivot_right)
	_finger_r4.position = Vector3(-0.028, -0.24, 0.05)
	_finger_r4.rotation_degrees.x = 12.0

	# Thumbs — angled capsules (not boxes) protruding outward
	_glove_thumb_left = _make_capsule_child("GloveThumbLeft", 0.018, 0.05, _glove_mat, _elbow_pivot_left)
	_glove_thumb_left.position = Vector3(0.045, -0.22, 0.035)
	_glove_thumb_left.rotation_degrees.z = -20.0
	_glove_thumb_left.rotation_degrees.x = 15.0  # Angled forward and outward

	_glove_thumb_right = _make_capsule_child("GloveThumbRight", 0.018, 0.05, _glove_mat, _elbow_pivot_right)
	_glove_thumb_right.position = Vector3(-0.045, -0.22, 0.035)
	_glove_thumb_right.rotation_degrees.z = 20.0
	_glove_thumb_right.rotation_degrees.x = 15.0

	# --- Backpack (life support) ---
	_backpack = _make_box("Backpack", Vector3(0.26, 0.32, 0.14), _backpack_mat)
	_backpack.position = Vector3(0.0, 0.95, -0.2)

	# --- Backpack Status Lights ---
	_status_green = _make_sphere("StatusGreen", 0.015, _status_green_mat)
	_status_green.position = Vector3(0.0, 1.05, -0.28)

	_status_amber = _make_sphere("StatusAmber", 0.015, _status_amber_mat)
	_status_amber.position = Vector3(0.0, 1.0, -0.28)

	_status_red = _make_sphere("StatusRed", 0.015, _status_red_mat)
	_status_red.position = Vector3(0.0, 0.95, -0.28)

	# --- Oxygen Tubes (backpack to helmet) ---
	_tube_left = _make_capsule("TubeLeft", 0.015, 0.35, _accent_mat)
	_tube_left.position = Vector3(-0.1, 1.1, -0.12)
	_tube_left.rotation_degrees.x = -15.0
	_tube_left.rotation_degrees.z = 5.0

	_tube_right = _make_capsule("TubeRight", 0.015, 0.35, _accent_mat)
	_tube_right.position = Vector3(0.1, 1.1, -0.12)
	_tube_right.rotation_degrees.x = -15.0
	_tube_right.rotation_degrees.z = -5.0

	# --- Helmet Ring (torus at neck — spacesuit collar) ---
	_helmet_ring = _make_torus("HelmetRing", 0.22, 0.04, _accent_mat)
	_helmet_ring.position = Vector3(0.0, 1.24, 0.0)

	# --- Helmet Visor (partial sphere in front of face) ---
	_helmet_visor = _make_sphere("HelmetVisor", 0.26, _visor_mat)
	_helmet_visor.position = Vector3(0.0, 1.48, 0.06)
	_helmet_visor.scale = Vector3(0.9, 0.75, 0.5)  # Flattened dome in front

	# --- Head (wide, round, slightly flattened) ---
	_head = _make_sphere("Head", 0.24, _fur_mat)
	_head.position = Vector3(0.0, 1.48, 0.0)
	_head.scale = Vector3(1.08, 0.88, 0.95)  # Wider, slightly squashed

	# --- Antenna ---
	_antenna_shaft = _make_capsule("AntennaShaft", 0.01, 0.15, _accent_mat)
	_antenna_shaft.position = Vector3(0.06, 1.75, -0.02)

	_antenna_tip = _make_sphere("AntennaTip", 0.02, _panel_mat)
	_antenna_tip.position = Vector3(0.06, 1.84, -0.02)

	# --- Ears (round, set wide on top of the head) ---
	_ear_left = _make_sphere("EarLeft", 0.075, _fur_mat)
	_ear_left.position = Vector3(-0.18, 1.70, -0.04)
	_ear_left.scale = Vector3(1.0, 0.85, 0.7)  # Slightly flattened

	_ear_right = _make_sphere("EarRight", 0.075, _fur_mat)
	_ear_right.position = Vector3(0.18, 1.70, -0.04)
	_ear_right.scale = Vector3(1.0, 0.85, 0.7)

	# --- Inner Ears (lighter patches inside the ears) ---
	_inner_ear_left = _make_sphere("InnerEarLeft", 0.045, _inner_ear_mat)
	_inner_ear_left.position = Vector3(-0.18, 1.70, -0.01)

	_inner_ear_right = _make_sphere("InnerEarRight", 0.045, _inner_ear_mat)
	_inner_ear_right.position = Vector3(0.18, 1.70, -0.01)

	# --- Muzzle Pad (cream/tan area around the snout) ---
	_muzzle_pad = _make_sphere("MuzzlePad", 0.13, _snout_mat)
	_muzzle_pad.position = Vector3(0.0, 1.42, 0.14)
	_muzzle_pad.scale = Vector3(1.2, 1.0, 0.9)

	# --- Snout (prominent rounded muzzle) ---
	_snout = _make_sphere("Snout", 0.10, _snout_mat)
	_snout.position = Vector3(0.0, 1.41, 0.20)
	_snout.scale = Vector3(1.1, 0.75, 1.1)

	# --- Nose (wide oval nose) ---
	_nose = _make_sphere("Nose", 0.038, _nose_mat)
	_nose.position = Vector3(0.0, 1.44, 0.28)
	_nose.scale = Vector3(1.3, 0.8, 0.9)

	# --- Cheeks (subtle bulges on either side of snout — face roundness) ---
	_cheek_left = _make_sphere("CheekLeft", 0.06, _fur_mat)
	_cheek_left.position = Vector3(-0.10, 1.42, 0.14)

	_cheek_right = _make_sphere("CheekRight", 0.06, _fur_mat)
	_cheek_right.position = Vector3(0.10, 1.42, 0.14)

	# --- Eyes (slightly large, wide apart) ---
	_eye_left = _make_sphere("EyeLeft", 0.045, _eye_mat)
	_eye_left.position = Vector3(-0.09, 1.53, 0.19)

	_eye_right = _make_sphere("EyeRight", 0.045, _eye_mat)
	_eye_right.position = Vector3(0.09, 1.53, 0.19)

	# --- Eye Shines (tiny white specular dot — brings eyes to life) ---
	_eye_shine_left = _make_sphere("EyeShineLeft", 0.012, _eye_shine_mat)
	_eye_shine_left.position = Vector3(-0.075, 1.545, 0.225)

	_eye_shine_right = _make_sphere("EyeShineRight", 0.012, _eye_shine_mat)
	_eye_shine_right.position = Vector3(0.075, 1.545, 0.225)

	# --- Mouth (thin dark curve below the nose) ---
	_mouth = _make_capsule("Mouth", 0.008, 0.06, _mouth_mat)
	_mouth.position = Vector3(0.0, 1.385, 0.24)
	_mouth.rotation_degrees.z = 90.0  # Horizontal orientation
	_mouth.scale = Vector3(1.0, 1.0, 0.3)  # Flatten against face

	# --- Jetpack Flames (hidden by default, shown when flying) ---
	_flame_left = _create_flame_particles("FlameLeft")
	_flame_left.position = Vector3(-0.08, 0.72, -0.24)

	_flame_right = _create_flame_particles("FlameRight")
	_flame_right.position = Vector3(0.08, 0.72, -0.24)



	# --- Crow Companion ---
	_build_crow()

	# --- Apply premium shader materials to main body parts ---
	_apply_shader_materials()


func _apply_shader_materials() -> void:
	## Replace StandardMaterial3D with character shader on major body parts.
	## Keeps legacy materials on small detail parts (status lights, nose, eyes).
	if _head: _head.material_override = _fur_shader_mat
	if _ear_left: _ear_left.material_override = _fur_shader_mat
	if _ear_right: _ear_right.material_override = _fur_shader_mat
	if _snout: _snout.material_override = _snout_shader_mat  # Lighter tan fur for muzzle
	if _muzzle_pad: _muzzle_pad.material_override = _snout_shader_mat
	if _cheek_left: _cheek_left.material_override = _fur_shader_mat
	if _cheek_right: _cheek_right.material_override = _fur_shader_mat
	if _inner_ear_left: _inner_ear_left.material_override = _fur_shader_mat
	if _inner_ear_right: _inner_ear_right.material_override = _fur_shader_mat

	if _torso: _torso.material_override = _suit_shader_mat
	if _arm_left: _arm_left.material_override = _suit_shader_mat
	if _arm_right: _arm_right.material_override = _suit_shader_mat
	if _forearm_left: _forearm_left.material_override = _suit_shader_mat
	if _forearm_right: _forearm_right.material_override = _suit_shader_mat
	if _leg_left: _leg_left.material_override = _suit_shader_mat
	if _leg_right: _leg_right.material_override = _suit_shader_mat
	if _shin_left: _shin_left.material_override = _suit_shader_mat
	if _shin_right: _shin_right.material_override = _suit_shader_mat
	if _shoulder_left: _shoulder_left.material_override = _suit_shader_mat
	if _shoulder_right: _shoulder_right.material_override = _suit_shader_mat

	if _boot_left: _boot_left.material_override = _boot_shader_mat
	if _boot_right: _boot_right.material_override = _boot_shader_mat
	if _boot_sole_left: _boot_sole_left.material_override = _accent_shader_mat
	if _boot_sole_right: _boot_sole_right.material_override = _accent_shader_mat
	if _boot_toe_left: _boot_toe_left.material_override = _boot_shader_mat
	if _boot_toe_right: _boot_toe_right.material_override = _boot_shader_mat
	if _boot_cuff_left: _boot_cuff_left.material_override = _accent_shader_mat
	if _boot_cuff_right: _boot_cuff_right.material_override = _accent_shader_mat
	if _boot_heel_left: _boot_heel_left.material_override = _boot_shader_mat
	if _boot_heel_right: _boot_heel_right.material_override = _boot_shader_mat
	if _boot_tread_left: _boot_tread_left.material_override = _accent_shader_mat
	if _boot_tread_right: _boot_tread_right.material_override = _accent_shader_mat

	if _glove_left: _glove_left.material_override = _glove_shader_mat
	if _glove_right: _glove_right.material_override = _glove_shader_mat
	if _glove_thumb_left: _glove_thumb_left.material_override = _glove_shader_mat
	if _glove_thumb_right: _glove_thumb_right.material_override = _glove_shader_mat
	for f in [_finger_l1, _finger_l2, _finger_l3, _finger_l4, _finger_r1, _finger_r2, _finger_r3, _finger_r4]:
		if f: f.material_override = _glove_shader_mat

	if _belt: _belt.material_override = _accent_shader_mat
	if _helmet_ring: _helmet_ring.material_override = _accent_shader_mat
	if _helmet_visor: _helmet_visor.material_override = _visor_shader_mat
	if _backpack: _backpack.material_override = _suit_shader_mat

	if _seam_left: _seam_left.material_override = _accent_shader_mat
	if _seam_right: _seam_right.material_override = _accent_shader_mat
	if _tube_left: _tube_left.material_override = _accent_shader_mat
	if _tube_right: _tube_right.material_override = _accent_shader_mat


func set_territory_power(power: float) -> void:
	## Update character shader with territory power (energy lines on suit).
	for mat in [_suit_shader_mat, _boot_shader_mat, _glove_shader_mat, _accent_shader_mat]:
		if mat:
			mat.set_shader_parameter("territory_power", power)


func trigger_shield_flash() -> void:
	## Shield shimmer effect when taking damage.
	for mat in [_suit_shader_mat, _fur_shader_mat, _boot_shader_mat, _glove_shader_mat, _visor_shader_mat, _accent_shader_mat, _snout_shader_mat]:
		if mat:
			mat.set_shader_parameter("shield_flash", 1.0)
	# Tween the flash down
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		for mat in [_suit_shader_mat, _fur_shader_mat, _boot_shader_mat, _glove_shader_mat, _visor_shader_mat, _accent_shader_mat, _snout_shader_mat]:
			if mat:
				mat.set_shader_parameter("shield_flash", v)
	, 1.0, 0.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## The crow companion appears only for a wallet holding >= 25 CROWS, which makes
## it a universal bouncer of every room (CROWS rule, docs/LEARNINGS.md §5).
## Drawn grey while the player has no bars anywhere (gear rule). Desaturates
## every StandardMaterial3D on the model; originals are kept to restore colour.
func modulate_grey(grey: bool) -> void:
	if grey == _grey:
		return
	_grey = grey
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m == null:
			continue
		if not _orig_colors.has(m):
			_orig_colors[m] = m.albedo_color
		var c: Color = _orig_colors[m]
		var lum := c.get_luminance()
		m.albedo_color = Color(lum, lum, lum * 1.05, c.a) if grey else c


var _grey := false
var _orig_colors := {}


func set_crow(visible_now: bool) -> void:
	if _crow_pivot:
		_crow_pivot.visible = visible_now


func apply_appearance(appearance: Dictionary) -> void:
	## Apply identity-driven colors and proportions.
	## body_color -> fur (Spirit-driven, but stays warm brown range)
	## accent_color -> suit accent trim (soul-driven)
	## emission_color -> eyes + panel glow (aura-driven)
	var body_color: Color = appearance.get("body_color", Color(0.45, 0.30, 0.18))
	var accent_color: Color = appearance.get("accent_color", Color(0.4, 0.5, 0.7))
	var emission_color: Color = appearance.get("emission_color", Color(0.4, 0.3, 0.2))
	var emission_intensity: float = appearance.get("emission_intensity", 0.1)
	var target_height: float = appearance.get("height", 1.8)

	# --- Bear fur: blend identity color with bear brown so it stays bear-like ---
	var bear_brown := Color(0.45, 0.30, 0.18)
	var fur_color := bear_brown.lerp(body_color, 0.35)  # Mostly brown, tinted by identity
	_fur_mat.albedo_color = fur_color
	_snout_mat.albedo_color = fur_color.lightened(0.25)

	# --- Suit is PulseChain purple, accents get identity tint ---
	_suit_mat.albedo_color = Color(0.22, 0.14, 0.38)
	var accent_tint := Color(0.35, 0.22, 0.55).lerp(accent_color, 0.15)
	_accent_mat.albedo_color = accent_tint

	# Gloves and boots: dark with subtle identity tint
	_glove_mat.albedo_color = Color(0.18, 0.15, 0.25).lerp(accent_color, 0.08)
	_boot_mat.albedo_color = Color(0.15, 0.12, 0.22).lerp(accent_color, 0.08)

	# Backpack: matches suit, no emission
	_backpack_mat.albedo_color = Color(0.85, 0.85, 0.88)

	# --- Update shader materials with identity colors (no emission) ---
	if _fur_shader_mat:
		_fur_shader_mat.set_shader_parameter("base_color", Vector3(fur_color.r, fur_color.g, fur_color.b))
	if _suit_shader_mat:
		var pulse_accent := Color(0.55, 0.36, 0.95).lerp(accent_color, 0.3)
		_suit_shader_mat.set_shader_parameter("power_accent", Vector3(pulse_accent.r, pulse_accent.g, pulse_accent.b))
	if _accent_shader_mat:
		_accent_shader_mat.set_shader_parameter("base_color", Vector3(accent_tint.r, accent_tint.g, accent_tint.b))
	if _visor_shader_mat:
		_visor_shader_mat.set_shader_parameter("emission_strength", 0.0)
	if _boot_shader_mat:
		var boot_col := Color(0.15, 0.12, 0.22).lerp(accent_color, 0.08)
		_boot_shader_mat.set_shader_parameter("base_color", Vector3(boot_col.r, boot_col.g, boot_col.b))
	if _glove_shader_mat:
		var glove_col := Color(0.18, 0.15, 0.25).lerp(accent_color, 0.08)
		_glove_shader_mat.set_shader_parameter("base_color", Vector3(glove_col.r, glove_col.g, glove_col.b))
	if _snout_shader_mat:
		var snout_col := fur_color.lightened(0.25)
		_snout_shader_mat.set_shader_parameter("base_color", Vector3(snout_col.r, snout_col.g, snout_col.b))

	# --- Scale from height ---
	_scale_factor = target_height / _base_height
	scale = Vector3(_scale_factor, _scale_factor, _scale_factor)


func set_flying(flying: bool) -> void:
	_is_flying = flying
	if _flame_left:
		_flame_left.emitting = flying
	if _flame_right:
		_flame_right.emitting = flying


func _on_fly_mode_changed(flying: bool) -> void:
	set_flying(flying)


# ─── Animation Loop ──────────────────────────────────────────────────

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0

	# Accumulate animation time based on movement speed
	_anim_time += _move_speed * delta * 0.5

	match _anim_state:
		AnimState.IDLE:
			_animate_idle(t, delta)
		AnimState.WALK:
			_animate_walk(t, delta, 16.0, 10.0)
		AnimState.SPRINT:
			_animate_walk(t, delta, 26.0, 16.0)
		AnimState.FLY:
			_animate_fly(t, delta)
		AnimState.FALLING:
			_animate_falling(t, delta)

	# ── Landing squash/stretch spring ──
	if absf(_land_squash) > 0.001 or absf(_land_squash_vel) > 0.001:
		# Damped spring: bounces back from squash through stretch to rest
		var spring_k := 80.0  # Stiffness
		var damp := 8.0       # Damping
		_land_squash_vel += (-spring_k * _land_squash - damp * _land_squash_vel) * delta
		_land_squash += _land_squash_vel * delta
		# Apply squash to torso: compress Y, expand X/Z
		if _torso:
			var sq := _land_squash * 0.25
			_torso.scale = Vector3(1.0 + sq * 0.6, 1.0 - sq, 1.0 + sq * 0.6)
	elif _torso and _torso.scale != Vector3.ONE:
		_torso.scale = _torso.scale.lerp(Vector3.ONE, 10.0 * delta)

	# Always-on ambient details
	_animate_details(t, delta)

	# Crow companion orbits above
	_animate_crow(t, delta)


func _animate_idle(t: float, delta: float) -> void:
	## Idle: relaxed breathing, weight shifting, curious head tilts, fidgeting.
	## Teddy bear personality: slightly inquisitive, occasionally looking around.
	var blend := 5.0 * delta

	# Breathing — multi-frequency for organic feel
	var breath := sin(t * 1.8) * 0.5 + sin(t * 0.7) * 0.3
	# Occasional deep breath / sigh (every ~15s)
	var deep_breath := maxf(0.0, sin(t * 0.42)) * maxf(0.0, sin(t * 0.42 - 0.15)) * 2.0

	if _torso:
		var target_y := _torso_rest_y + (breath + deep_breath) * 0.014
		_torso.position.y = lerpf(_torso.position.y, target_y, blend)
		# Relaxed posture with slight slouch
		_torso.rotation_degrees.x = lerpf(_torso.rotation_degrees.x, 2.0 + deep_breath * 1.5, blend)
		# Weight shift — slow, lazy figure-8 pattern
		_torso.rotation_degrees.z = lerpf(_torso.rotation_degrees.z, sin(t * 0.5) * 2.5 + sin(t * 0.3) * 1.2, blend)
		# Hip turn with occasional bigger look-around
		var look_around := sin(t * 0.25) * 3.0 + sin(t * 0.08) * 6.0 * maxf(0.0, sin(t * 0.08 + 0.5))
		_torso.rotation_degrees.y = lerpf(_torso.rotation_degrees.y, look_around, blend)

	# Legs: weight shifting between feet, contrapposto stance
	var weight_phase := sin(t * 0.3)
	if _leg_pivot_left:
		_leg_pivot_left.rotation_degrees.x = lerpf(_leg_pivot_left.rotation_degrees.x, sin(t * 0.4) * 2.0, blend)
		_leg_pivot_left.rotation_degrees.z = lerpf(_leg_pivot_left.rotation_degrees.z, weight_phase * -1.0, blend)
	if _leg_pivot_right:
		_leg_pivot_right.rotation_degrees.x = lerpf(_leg_pivot_right.rotation_degrees.x, sin(t * 0.4 + 1.0) * 2.0, blend)
		_leg_pivot_right.rotation_degrees.z = lerpf(_leg_pivot_right.rotation_degrees.z, weight_phase * 1.0, blend)

	# Knees: contrapposto — weight on one leg, other relaxed
	if _knee_pivot_left:
		_knee_pivot_left.rotation_degrees.x = lerpf(_knee_pivot_left.rotation_degrees.x, maxf(0.0, weight_phase) * 8.0, blend)
	if _knee_pivot_right:
		_knee_pivot_right.rotation_degrees.x = lerpf(_knee_pivot_right.rotation_degrees.x, maxf(0.0, -weight_phase) * 8.0, blend)

	# Arms: gentle sway with occasional fidget (touching helmet, adjusting glove)
	var fidget := maxf(0.0, sin(t * 0.12)) * maxf(0.0, sin(t * 0.12 - 0.2))  # ~every 26s
	if _arm_pivot_left:
		var arm_x := 2.0 + sin(t * 0.7) * 3.0 + fidget * 15.0  # Fidget reaches up
		_arm_pivot_left.rotation_degrees.x = lerpf(_arm_pivot_left.rotation_degrees.x, arm_x, blend)
		_arm_pivot_left.rotation_degrees.z = lerpf(_arm_pivot_left.rotation_degrees.z, _arm_left_rest_rot_z + sin(t * 0.5) * 2.0, blend)
	if _arm_pivot_right:
		_arm_pivot_right.rotation_degrees.x = lerpf(_arm_pivot_right.rotation_degrees.x, 2.0 + sin(t * 0.7 + 1.5) * 3.0, blend)
		_arm_pivot_right.rotation_degrees.z = lerpf(_arm_pivot_right.rotation_degrees.z, _arm_right_rest_rot_z - sin(t * 0.5) * 2.0, blend)

	# Elbows: natural relaxed bend, curls more during fidget
	if _elbow_pivot_left:
		_elbow_pivot_left.rotation_degrees.x = lerpf(_elbow_pivot_left.rotation_degrees.x, -10.0 + sin(t * 0.6) * 3.0 - fidget * 35.0, blend)
	if _elbow_pivot_right:
		_elbow_pivot_right.rotation_degrees.x = lerpf(_elbow_pivot_right.rotation_degrees.x, -10.0 + sin(t * 0.6 + 1.2) * 3.0, blend)

	# Head: curious tilts, slow look-around, occasional upward glance
	if _head:
		var curiosity := sin(t * 0.15) * 5.0 + sin(t * 0.3) * 3.0  # Bigger look-around
		_head.rotation_degrees.y = lerpf(_head.rotation_degrees.y, curiosity, blend)
		_head.rotation_degrees.x = lerpf(_head.rotation_degrees.x, sin(t * 1.8) * 1.5 - deep_breath * 2.0, blend)
		# Cute head tilt (teddy bear personality)
		_head.rotation_degrees.z = lerpf(_head.rotation_degrees.z, sin(t * 0.18) * 4.0, blend)


func _animate_walk(t: float, delta: float, leg_amplitude: float, arm_amplitude: float) -> void:
	## Walk/Sprint cycle with organic motion. Includes hip rotation, shoulder counter-roll,
	## asymmetric timing, body sway, and slope adaptation.
	var blend := 8.0 * delta  # Slightly softer blend for smoother transitions
	var phase := _anim_time * 4.0

	var is_sprint := leg_amplitude > 25.0
	var speed_factor := clampf(_move_speed / 14.0, 0.0, 1.0)  # 0 at walk, 1 at full sprint

	# ── Slope adaptation ──
	var slope_lean := clampf(_slope_angle * 0.4, -12.0, 15.0)  # Lean into hills
	var slope_stride_mod := 1.0 - clampf(absf(_slope_angle) / 60.0, 0.0, 0.3)  # Shorter strides on slopes

	# ── Torso: forward lean + slope lean + sway + bob ──
	var base_lean := clampf(_move_speed * 0.35, 0.0, 5.0) + slope_lean
	if is_sprint:
		base_lean += 3.0  # Extra lean when sprinting
	if _torso:
		_torso.rotation_degrees.x = lerpf(_torso.rotation_degrees.x, base_lean, blend)
		# Side-to-side sway (hips shift with each step) — key to not looking robotic
		var sway := sin(phase) * (2.5 + speed_factor * 1.5)
		_torso.rotation_degrees.z = lerpf(_torso.rotation_degrees.z, sway, blend)
		# Hip rotation around Y axis (torso twists with walk cycle)
		_torso.rotation_degrees.y = lerpf(_torso.rotation_degrees.y, sin(phase) * (3.0 + speed_factor * 3.0), blend)
		# Bounce: double-frequency bob with slight asymmetry
		var bob := absf(sin(phase * 2.0 + 0.2)) * (0.02 + speed_factor * 0.025)
		_torso.position.y = lerpf(_torso.position.y, _torso_rest_y + bob, blend)

	# ── Leg swing with asymmetric timing ──
	# Real walking has a faster forward swing and slower push-back
	var left_leg_raw := sin(phase)
	var right_leg_raw := sin(phase + PI)
	# Asymmetric: sharper forward, slower back
	var left_leg_shaped := left_leg_raw + sin(phase * 2.0) * 0.15
	var right_leg_shaped := right_leg_raw + sin((phase + PI) * 2.0) * 0.15

	var stride := leg_amplitude * slope_stride_mod
	if _leg_pivot_left:
		_leg_pivot_left.rotation_degrees.x = lerpf(_leg_pivot_left.rotation_degrees.x, left_leg_shaped * stride, blend)
		# Subtle outward splay during swing
		_leg_pivot_left.rotation_degrees.z = lerpf(_leg_pivot_left.rotation_degrees.z, sin(phase + 0.5) * 1.5, blend)
	if _leg_pivot_right:
		_leg_pivot_right.rotation_degrees.x = lerpf(_leg_pivot_right.rotation_degrees.x, right_leg_shaped * stride, blend)
		_leg_pivot_right.rotation_degrees.z = lerpf(_leg_pivot_right.rotation_degrees.z, sin(phase + PI + 0.5) * -1.5, blend)

	# ── Knee bending — natural delayed response ──
	var knee_bend_max: float = 45.0 if is_sprint else 22.0
	var knee_bend_min: float = 5.0 if is_sprint else 2.0
	# Uphill: more knee bend on the pushing leg
	var slope_knee_bonus := clampf(_slope_angle * 0.3, 0.0, 10.0)

	if _knee_pivot_left:
		var forward_factor := maxf(0.0, sin(phase + 0.5))  # Delayed peak
		var back_factor := maxf(0.0, -sin(phase + 0.2)) * 0.4  # Slight bend on push-back too
		var knee_target := knee_bend_min + (forward_factor + back_factor) * (knee_bend_max - knee_bend_min) + slope_knee_bonus * forward_factor
		_knee_pivot_left.rotation_degrees.x = lerpf(_knee_pivot_left.rotation_degrees.x, knee_target, blend)
	if _knee_pivot_right:
		var forward_factor := maxf(0.0, sin(phase + PI + 0.5))
		var back_factor := maxf(0.0, -sin(phase + PI + 0.2)) * 0.4
		var knee_target := knee_bend_min + (forward_factor + back_factor) * (knee_bend_max - knee_bend_min) + slope_knee_bonus * forward_factor
		_knee_pivot_right.rotation_degrees.x = lerpf(_knee_pivot_right.rotation_degrees.x, knee_target, blend)

	# ── Arms: counter-swing with natural bend and shoulder roll ──
	var arm_swing := arm_amplitude * 0.65
	var left_arm_sin := sin(phase + PI + 0.15)  # Slight phase offset — arms trail legs
	var right_arm_sin := sin(phase + 0.15)

	if _arm_pivot_left:
		_arm_pivot_left.rotation_degrees.x = lerpf(_arm_pivot_left.rotation_degrees.x, left_arm_sin * arm_swing, blend)
		# Arms swing slightly inward during forward swing (natural cross-body motion)
		var inward := maxf(0.0, left_arm_sin) * 3.0
		_arm_pivot_left.rotation_degrees.z = lerpf(_arm_pivot_left.rotation_degrees.z, _arm_left_rest_rot_z - inward, blend)
	if _arm_pivot_right:
		_arm_pivot_right.rotation_degrees.x = lerpf(_arm_pivot_right.rotation_degrees.x, right_arm_sin * arm_swing, blend)
		var inward := maxf(0.0, right_arm_sin) * 3.0
		_arm_pivot_right.rotation_degrees.z = lerpf(_arm_pivot_right.rotation_degrees.z, _arm_right_rest_rot_z + inward, blend)

	# ── Elbows: natural bend with more curl when arm swings forward ──
	var elbow_bend_max: float = 40.0 if is_sprint else 18.0
	var elbow_bend_min: float = 8.0 if is_sprint else 5.0

	if _elbow_pivot_left:
		var forward_factor := maxf(0.0, left_arm_sin)
		var elbow_target := -(elbow_bend_min + forward_factor * (elbow_bend_max - elbow_bend_min))
		_elbow_pivot_left.rotation_degrees.x = lerpf(_elbow_pivot_left.rotation_degrees.x, elbow_target, blend)
	if _elbow_pivot_right:
		var forward_factor := maxf(0.0, right_arm_sin)
		var elbow_target := -(elbow_bend_min + forward_factor * (elbow_bend_max - elbow_bend_min))
		_elbow_pivot_right.rotation_degrees.x = lerpf(_elbow_pivot_right.rotation_degrees.x, elbow_target, blend)

	# ── Head: counter-rotation for stability + look-ahead tilt ──
	if _head:
		_head.rotation_degrees.x = lerpf(_head.rotation_degrees.x, -base_lean * 0.3, blend)
		# Head counter-sways opposite torso twist (keeps eyes level)
		_head.rotation_degrees.y = lerpf(_head.rotation_degrees.y, -sin(phase) * 2.5, blend)
		_head.rotation_degrees.z = lerpf(_head.rotation_degrees.z, -sin(phase) * 1.5, blend)
		# Excited head bob during sprint (teddy bear energy)
		if is_sprint:
			_head.rotation_degrees.x += sin(phase * 2.0) * 2.0


func _animate_fly(t: float, delta: float) -> void:
	## Flying: dynamic pose that responds to direction. Arms stream back like a diver,
	## body tilts with velocity, legs trail with wind resistance feel.
	var blend := 5.0 * delta

	# Tilt based on vertical speed — diving down or boosting up
	var vert_tilt := clampf(_vertical_speed * 2.0, -20.0, 25.0)  # Nose down when descending
	var horiz_speed := _move_speed
	var speed_tilt := clampf(horiz_speed * 0.6, 0.0, 18.0)  # Lean forward when moving fast

	# Wind buffet — subtle random perturbation at speed
	var wind := sin(t * 3.7) * 2.0 + sin(t * 5.3) * 1.0

	if _torso:
		_torso.rotation_degrees.x = lerpf(_torso.rotation_degrees.x, speed_tilt + vert_tilt * 0.5, blend)
		# Bank into turns — torso rolls based on lateral velocity relative to facing
		var bank := clampf(_velocity.x * 0.3, -8.0, 8.0) + wind * 0.5
		_torso.rotation_degrees.z = lerpf(_torso.rotation_degrees.z, bank, blend)
		_torso.position.y = lerpf(_torso.position.y, _torso_rest_y, blend)

	# Arms: stream back like a skydiver, hands trail behind at speed
	# At low speed: relaxed spread; at high speed: swept back
	var arm_sweep := clampf(horiz_speed * 1.5, 0.0, 25.0)  # How far back arms go
	var arm_spread := lerpf(30.0, 12.0, clampf(horiz_speed / 20.0, 0.0, 1.0))  # Less spread at speed

	if _arm_pivot_left:
		_arm_pivot_left.rotation_degrees.x = lerpf(_arm_pivot_left.rotation_degrees.x, 10.0 + arm_sweep + sin(t * 1.2) * 3.0, blend)
		_arm_pivot_left.rotation_degrees.z = lerpf(_arm_pivot_left.rotation_degrees.z, arm_spread + wind * 0.8, blend)
	if _arm_pivot_right:
		_arm_pivot_right.rotation_degrees.x = lerpf(_arm_pivot_right.rotation_degrees.x, 10.0 + arm_sweep + sin(t * 1.2 + 0.7) * 3.0, blend)
		_arm_pivot_right.rotation_degrees.z = lerpf(_arm_pivot_right.rotation_degrees.z, -arm_spread - wind * 0.8, blend)

	# Elbows: more bent at low speed (relaxed), straighter when streaming back
	var elbow_bend := lerpf(-25.0, -8.0, clampf(horiz_speed / 20.0, 0.0, 1.0))
	if _elbow_pivot_left:
		_elbow_pivot_left.rotation_degrees.x = lerpf(_elbow_pivot_left.rotation_degrees.x, elbow_bend + sin(t * 1.8) * 4.0, blend)
	if _elbow_pivot_right:
		_elbow_pivot_right.rotation_degrees.x = lerpf(_elbow_pivot_right.rotation_degrees.x, elbow_bend + sin(t * 1.8 + 1.2) * 4.0, blend)

	# Legs: trail behind, slightly apart, with knee bend that responds to speed
	var leg_trail := 10.0 + clampf(horiz_speed * 0.5, 0.0, 15.0)
	if _leg_pivot_left:
		_leg_pivot_left.rotation_degrees.x = lerpf(_leg_pivot_left.rotation_degrees.x, leg_trail + sin(t * 0.9) * 3.0, blend)
		_leg_pivot_left.rotation_degrees.z = lerpf(_leg_pivot_left.rotation_degrees.z, -4.0 + wind * 0.3, blend)
	if _leg_pivot_right:
		_leg_pivot_right.rotation_degrees.x = lerpf(_leg_pivot_right.rotation_degrees.x, leg_trail + sin(t * 0.9 + 1.5) * 3.0, blend)
		_leg_pivot_right.rotation_degrees.z = lerpf(_leg_pivot_right.rotation_degrees.z, 4.0 - wind * 0.3, blend)

	# Knees: relaxed dangle with gentle wind motion
	if _knee_pivot_left:
		_knee_pivot_left.rotation_degrees.x = lerpf(_knee_pivot_left.rotation_degrees.x, 15.0 + sin(t * 1.1) * 5.0 + wind * 0.5, blend)
	if _knee_pivot_right:
		_knee_pivot_right.rotation_degrees.x = lerpf(_knee_pivot_right.rotation_degrees.x, 15.0 + sin(t * 1.1 + 1.8) * 5.0 - wind * 0.5, blend)

	# Head: counter-tilt to keep looking forward, slight wind wobble
	if _head:
		_head.rotation_degrees.x = lerpf(_head.rotation_degrees.x, -(speed_tilt + vert_tilt * 0.3) * 0.4, blend)
		_head.rotation_degrees.z = lerpf(_head.rotation_degrees.z, wind * 0.6, blend)

	# Jetpack flame intensity scales with speed
	if _flame_left and _flame_right:
		var intensity := 0.6 + clampf(horiz_speed / 20.0, 0.0, 0.4) + sin(t * 12.0) * 0.15
		_flame_left.amount_ratio = intensity
		_flame_right.amount_ratio = intensity


func _animate_falling(t: float, delta: float) -> void:
	## Falling in low gravity — more controlled than Earth falling.
	## Slight arm reach, legs prepare for landing, body adjusts to fall speed.
	var blend := 6.0 * delta
	var fall_speed := absf(minf(_vertical_speed, 0.0))  # How fast we're falling
	var fall_intensity := clampf(fall_speed / 15.0, 0.0, 1.0)  # 0 = gentle, 1 = fast fall

	# Body: slight backward lean that increases with fall speed
	if _torso:
		var tilt := lerpf(3.0, -5.0, fall_intensity)  # Lean back more at high speed
		_torso.rotation_degrees.x = lerpf(_torso.rotation_degrees.x, tilt, blend)
		_torso.rotation_degrees.z = lerpf(_torso.rotation_degrees.z, sin(t * 1.5) * 3.0 * fall_intensity, blend)
		_torso.position.y = lerpf(_torso.position.y, _torso_rest_y, blend)

	# Arms: reach out for balance at low speed, up and back at high speed
	var arm_raise := lerpf(15.0, 40.0, fall_intensity)  # More raised when falling fast
	var arm_sway := 4.0 + fall_intensity * 6.0
	if _arm_pivot_left:
		_arm_pivot_left.rotation_degrees.z = lerpf(_arm_pivot_left.rotation_degrees.z, arm_raise + sin(t * 2.5) * arm_sway, blend)
		_arm_pivot_left.rotation_degrees.x = lerpf(_arm_pivot_left.rotation_degrees.x, -8.0 + sin(t * 1.8) * 6.0, blend)
	if _arm_pivot_right:
		_arm_pivot_right.rotation_degrees.z = lerpf(_arm_pivot_right.rotation_degrees.z, -arm_raise + sin(t * 2.5 + 1.0) * arm_sway, blend)
		_arm_pivot_right.rotation_degrees.x = lerpf(_arm_pivot_right.rotation_degrees.x, -8.0 + sin(t * 1.8 + PI) * 6.0, blend)

	# Elbows: bent for balance, waving gently
	if _elbow_pivot_left:
		_elbow_pivot_left.rotation_degrees.x = lerpf(_elbow_pivot_left.rotation_degrees.x, -20.0 + sin(t * 2.2) * 8.0, blend)
	if _elbow_pivot_right:
		_elbow_pivot_right.rotation_degrees.x = lerpf(_elbow_pivot_right.rotation_degrees.x, -20.0 + sin(t * 2.2 + 1.5) * 8.0, blend)

	# Legs: prepare for landing — slightly bent, feet down
	var leg_spread := 3.0 + fall_intensity * 5.0
	if _leg_pivot_left:
		_leg_pivot_left.rotation_degrees.z = lerpf(_leg_pivot_left.rotation_degrees.z, -leg_spread, blend)
		_leg_pivot_left.rotation_degrees.x = lerpf(_leg_pivot_left.rotation_degrees.x, 5.0 + sin(t * 1.3) * 3.0, blend)
	if _leg_pivot_right:
		_leg_pivot_right.rotation_degrees.z = lerpf(_leg_pivot_right.rotation_degrees.z, leg_spread, blend)
		_leg_pivot_right.rotation_degrees.x = lerpf(_leg_pivot_right.rotation_degrees.x, 5.0 + sin(t * 1.3 + 1.0) * 3.0, blend)

	# Knees: progressively bend to prepare for landing
	var knee_prep := 8.0 + fall_intensity * 15.0
	if _knee_pivot_left:
		_knee_pivot_left.rotation_degrees.x = lerpf(_knee_pivot_left.rotation_degrees.x, knee_prep + sin(t * 1.5) * 3.0, blend)
	if _knee_pivot_right:
		_knee_pivot_right.rotation_degrees.x = lerpf(_knee_pivot_right.rotation_degrees.x, knee_prep + sin(t * 1.5 + PI) * 3.0, blend)

	# Head: looks down at ground as fall intensifies, slight panic wobble
	if _head:
		_head.rotation_degrees.x = lerpf(_head.rotation_degrees.x, fall_intensity * 8.0, blend)
		_head.rotation_degrees.z = lerpf(_head.rotation_degrees.z, sin(t * 4.0) * fall_intensity * 4.0, blend)
		# Look around frantically when falling fast
		_head.rotation_degrees.y = lerpf(_head.rotation_degrees.y, sin(t * 3.0) * fall_intensity * 6.0, blend)


func _animate_details(t: float, delta: float) -> void:
	## Always-on ambient details: ears, eyes, antenna, status lights.
	var _blend := 8.0 * delta

	# Ear wiggle (inner ears follow outer ears)
	if _ear_left:
		_ear_left.rotation.z = sin(t * 1.5) * 0.06
	if _ear_right:
		_ear_right.rotation.z = sin(t * 1.5 + 1.0) * -0.06
	if _inner_ear_left:
		_inner_ear_left.rotation.z = sin(t * 1.5) * 0.06
	if _inner_ear_right:
		_inner_ear_right.rotation.z = sin(t * 1.5 + 1.0) * -0.06

	# Antenna sway
	if _antenna_shaft:
		_antenna_shaft.rotation_degrees.x = sin(t * 2.5) * 3.0
		_antenna_shaft.rotation_degrees.z = sin(t * 1.8) * 2.0
	if _antenna_tip:
		_antenna_tip.position.x = 0.06 + sin(t * 2.5) * 0.005
		_antenna_tip.position.z = -0.02 + sin(t * 1.8) * 0.003

	# No emission animation — character has zero glow



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
