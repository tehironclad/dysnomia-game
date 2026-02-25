extends Node3D
## Remote player representation — simplified teddy bear astronaut.
## Receives position/rotation updates and interpolates smoothly.
## Dead-reckoning extrapolation between 100ms server updates.
## Auto-removes after 30s without updates.

signal stale_timeout(wallet: String)

# ── Identity ──
var wallet: String = ""
var username: String = ""
var tier: int = 0
var level: int = 1

# ── Interpolation state ──
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var velocity: Vector3 = Vector3.ZERO  # Horizontal velocity for dead-reckoning
var last_update_time: float = 0.0     # Time.get_ticks_msec() of last update
var _last_speed: float = 0.0

# ── Stale timeout ──
const STALE_TIMEOUT: float = 30.0
var _stale_timer: float = 0.0

# ── Interpolation tuning ──
const LERP_SPEED: float = 7.0        # Position convergence rate
const MAX_EXTRAPOLATE: float = 10.0   # Max distance from target for dead-reckoning clamp
const VELOCITY_FADE_START: float = 0.5 # Seconds before velocity starts fading
const VELOCITY_FADE_RATE: float = 2.0  # How fast velocity fades after threshold

# ── Model parts ──
var _label: Label3D
var _leg_pivot_l: Node3D
var _leg_pivot_r: Node3D
var _arm_pivot_l: Node3D
var _arm_pivot_r: Node3D
var _visor_mesh: MeshInstance3D
var _is_speaking: bool = false

# ── Materials (shared within this remote player) ──
var _fur_mat: StandardMaterial3D
var _suit_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _boot_mat: StandardMaterial3D
var _backpack_mat: StandardMaterial3D


func _ready() -> void:
	_create_materials()
	_build_model()
	_build_label()


func initialize(p_wallet: String, p_username: String, p_tier: int, p_level: int) -> void:
	wallet = p_wallet
	username = p_username
	tier = p_tier
	level = p_level
	last_update_time = Time.get_ticks_msec()
	_stale_timer = 0.0

	# Update label
	var tier_icon := _get_tier_icon(tier)
	_label.text = "%s %s" % [tier_icon, username]

	# Scale based on tier (0.85 base → 0.94 at tier 9)
	var s := 0.85 + tier * 0.01
	scale = Vector3(s, s, s)

	# Tint based on wallet hash for variety
	_apply_wallet_tint()


func update_position(pos: Vector3, yaw: float, vx: float, vz: float) -> void:
	## Called when a position broadcast arrives (every ~100ms).
	target_position = pos
	target_yaw = yaw
	# Smooth velocity (60% new, 40% old) to prevent speed pops
	velocity.x = velocity.x * 0.4 + vx * 0.6
	velocity.z = velocity.z * 0.4 + vz * 0.6
	last_update_time = Time.get_ticks_msec()
	_stale_timer = 0.0


func set_speaking(speaking: bool) -> void:
	if _is_speaking == speaking:
		return
	_is_speaking = speaking
	if _visor_mesh and _visor_mat:
		if speaking:
			_visor_mat.albedo_color = Color(0.1, 0.4, 0.3, 0.55)  # Green tint when speaking
		else:
			_visor_mat.albedo_color = Color(0.15, 0.25, 0.4, 0.55)  # Normal blue tint


func _process(delta: float) -> void:
	# ── Stale check ──
	_stale_timer += delta
	if _stale_timer >= STALE_TIMEOUT:
		stale_timeout.emit(wallet)
		return

	# ── Dead reckoning ──
	var time_since := (Time.get_ticks_msec() - last_update_time) / 1000.0
	# Fade out velocity if no update in 0.5s to prevent runaway extrapolation
	var stale_fade := 1.0
	if time_since > VELOCITY_FADE_START:
		stale_fade = maxf(0.0, 1.0 - (time_since - VELOCITY_FADE_START) * VELOCITY_FADE_RATE)
	var vx := velocity.x * stale_fade
	var vz := velocity.z * stale_fade

	# Extrapolated target
	var dr_x := target_position.x + vx * time_since
	var dr_z := target_position.z + vz * time_since
	var dr_y := target_position.y

	# Clamp extrapolation distance
	if absf(dr_x - target_position.x) > MAX_EXTRAPOLATE:
		dr_x = target_position.x
	if absf(dr_z - target_position.z) > MAX_EXTRAPOLATE:
		dr_z = target_position.z

	# Smooth lerp convergence
	var lf := minf(1.0, LERP_SPEED * delta)
	position.x += (dr_x - position.x) * lf
	position.y += (dr_y - position.y) * lf
	position.z += (dr_z - position.z) * lf

	# Smooth yaw interpolation
	var yd := target_yaw - rotation.y
	while yd > PI:
		yd -= TAU
	while yd < -PI:
		yd += TAU
	rotation.y += yd * lf

	# ── Limb animation based on velocity ──
	var v_speed := sqrt(vx * vx + vz * vz)
	_last_speed += (v_speed - _last_speed) * minf(1.0, 5.0 * delta)
	_animate_limbs()

	# Label is a child, so it follows automatically via local position


func _animate_limbs() -> void:
	if not _leg_pivot_l:
		return
	if _last_speed > 0.1:
		var wc := Time.get_ticks_msec() * 0.003
		var swing := _last_speed * 0.2
		_leg_pivot_l.rotation.x = sin(wc) * swing
		_leg_pivot_r.rotation.x = sin(wc + PI) * swing
		_arm_pivot_l.rotation.x = sin(wc + PI) * swing * 0.6
		_arm_pivot_r.rotation.x = sin(wc) * swing * 0.6
	else:
		_leg_pivot_l.rotation.x = 0.0
		_leg_pivot_r.rotation.x = 0.0
		_arm_pivot_l.rotation.x = sin(Time.get_ticks_msec() * 0.001) * 0.02
		_arm_pivot_r.rotation.x = sin(Time.get_ticks_msec() * 0.001 + 1.0) * 0.015


# ─── Material Creation ───────────────────────────────────────────────────

func _create_materials() -> void:
	_fur_mat = StandardMaterial3D.new()
	_fur_mat.albedo_color = Color(0.55, 0.38, 0.26)
	_fur_mat.roughness = 0.85

	_suit_mat = StandardMaterial3D.new()
	_suit_mat.albedo_color = Color(0.22, 0.14, 0.38)  # PulseChain purple
	_suit_mat.roughness = 0.4
	_suit_mat.metallic = 0.08

	_accent_mat = StandardMaterial3D.new()
	_accent_mat.albedo_color = Color(0.35, 0.22, 0.55)  # Purple metallic accent
	_accent_mat.roughness = 0.30
	_accent_mat.metallic = 0.4

	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = Color(0.15, 0.25, 0.4, 0.55)
	_visor_mat.roughness = 0.1
	_visor_mat.metallic = 0.6
	_visor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.12, 0.08, 0.05)
	_eye_mat.roughness = 0.2
	_eye_mat.metallic = 0.4

	_boot_mat = StandardMaterial3D.new()
	_boot_mat.albedo_color = Color(0.25, 0.25, 0.27)
	_boot_mat.roughness = 0.5
	_boot_mat.metallic = 0.15

	_backpack_mat = StandardMaterial3D.new()
	_backpack_mat.albedo_color = Color(0.88, 0.88, 0.9)
	_backpack_mat.roughness = 0.4
	_backpack_mat.metallic = 0.15


# ─── Simplified Model Build ─────────────────────────────────────────────

func _build_model() -> void:
	# ── Head (Ted-style: wider, squashed) ──
	var head := _sphere("Head", 0.24, _fur_mat)
	head.position = Vector3(0, 1.42, 0)
	head.scale = Vector3(1.08, 0.88, 0.95)

	# Ears (wider apart, flattened like Ted)
	var ear_l := _sphere("EarL", 0.075, _fur_mat)
	ear_l.position = Vector3(-0.18, 1.60, -0.04)
	ear_l.scale = Vector3(1.0, 0.85, 0.7)
	var ear_r := _sphere("EarR", 0.075, _fur_mat)
	ear_r.position = Vector3(0.18, 1.60, -0.04)
	ear_r.scale = Vector3(1.0, 0.85, 0.7)

	# Muzzle pad (lighter face area)
	var snout_mat := StandardMaterial3D.new()
	snout_mat.albedo_color = Color(0.72, 0.58, 0.44)
	snout_mat.roughness = 0.85
	var muzzle := _sphere("Muzzle", 0.12, snout_mat)
	muzzle.position = Vector3(0, 1.36, 0.12)
	muzzle.scale = Vector3(1.2, 1.0, 0.9)

	# Snout (larger, flatter like Ted)
	var snout := _sphere("Snout", 0.10, snout_mat)
	snout.position = Vector3(0, 1.35, 0.18)
	snout.scale = Vector3(1.1, 0.75, 1.1)

	# Nose (wider oval)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.08, 0.06, 0.05)
	nose_mat.roughness = 0.3
	var nose := _sphere("Nose", 0.038, nose_mat)
	nose.position = Vector3(0, 1.38, 0.26)
	nose.scale = Vector3(1.3, 0.8, 0.9)

	# Mouth (thin dark line — Ted's expression)
	var mouth_mat := StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(0.08, 0.05, 0.04)
	mouth_mat.roughness = 0.7
	var mouth := _capsule("Mouth", 0.008, 0.06, mouth_mat)
	mouth.position = Vector3(0, 1.32, 0.22)
	mouth.rotation_degrees.z = 90.0
	mouth.scale = Vector3(1.0, 1.0, 0.3)

	# Eyes (slightly larger, wider)
	var eye_l := _sphere("EyeL", 0.045, _eye_mat)
	eye_l.position = Vector3(-0.09, 1.46, 0.17)
	var eye_r := _sphere("EyeR", 0.045, _eye_mat)
	eye_r.position = Vector3(0.09, 1.46, 0.17)

	# Helmet visor
	_visor_mesh = _sphere("Visor", 0.24, _visor_mat)
	_visor_mesh.position = Vector3(0, 1.44, 0.06)
	_visor_mesh.scale = Vector3(0.9, 0.75, 0.5)

	# Helmet ring
	var ring := _torus("HelmetRing", 0.2, 0.025, _accent_mat)
	ring.position = Vector3(0, 1.24, 0)

	# ── Torso ──
	var torso := _capsule("Torso", 0.24, 0.55, _suit_mat)
	torso.position = Vector3(0, 0.88, 0)

	# Belt
	var belt := _torus("Belt", 0.22, 0.02, _accent_mat)
	belt.position = Vector3(0, 0.65, 0)

	# Backpack
	var backpack := _box("Backpack", Vector3(0.2, 0.24, 0.1), _backpack_mat)
	backpack.position = Vector3(0, 0.95, -0.2)

	# ── Legs ──
	_leg_pivot_l = Node3D.new()
	_leg_pivot_l.name = "LegPivotL"
	_leg_pivot_l.position = Vector3(-0.1, 0.6, 0)
	add_child(_leg_pivot_l)

	var upper_leg_l := _capsule_child("UpperLegL", 0.1, 0.35, _suit_mat, _leg_pivot_l)
	upper_leg_l.position = Vector3(0, -0.2, 0)

	var boot_l := _capsule_child("BootL", 0.09, 0.18, _boot_mat, _leg_pivot_l)
	boot_l.position = Vector3(0, -0.52, 0.02)

	_leg_pivot_r = Node3D.new()
	_leg_pivot_r.name = "LegPivotR"
	_leg_pivot_r.position = Vector3(0.1, 0.6, 0)
	add_child(_leg_pivot_r)

	var upper_leg_r := _capsule_child("UpperLegR", 0.1, 0.35, _suit_mat, _leg_pivot_r)
	upper_leg_r.position = Vector3(0, -0.2, 0)

	var boot_r := _capsule_child("BootR", 0.09, 0.18, _boot_mat, _leg_pivot_r)
	boot_r.position = Vector3(0, -0.52, 0.02)

	# ── Arms ──
	_arm_pivot_l = Node3D.new()
	_arm_pivot_l.name = "ArmPivotL"
	_arm_pivot_l.position = Vector3(-0.32, 1.1, 0)
	add_child(_arm_pivot_l)

	var arm_l := _capsule_child("ArmL", 0.065, 0.4, _suit_mat, _arm_pivot_l)
	arm_l.position = Vector3(0, -0.22, 0)

	var glove_l := _sphere_child("GloveL", 0.06, _suit_mat, _arm_pivot_l)
	glove_l.position = Vector3(0, -0.48, 0)
	glove_l.scale = Vector3(0.85, 0.65, 1.0)

	_arm_pivot_r = Node3D.new()
	_arm_pivot_r.name = "ArmPivotR"
	_arm_pivot_r.position = Vector3(0.32, 1.1, 0)
	add_child(_arm_pivot_r)

	var arm_r := _capsule_child("ArmR", 0.065, 0.4, _suit_mat, _arm_pivot_r)
	arm_r.position = Vector3(0, -0.22, 0)

	var glove_r := _sphere_child("GloveR", 0.06, _suit_mat, _arm_pivot_r)
	glove_r.position = Vector3(0, -0.48, 0)
	glove_r.scale = Vector3(0.85, 0.65, 1.0)

	# Shoulder pads
	var shoulder_l := _sphere("ShoulderL", 0.09, _accent_mat)
	shoulder_l.position = Vector3(-0.3, 1.12, 0)
	var shoulder_r := _sphere("ShoulderR", 0.09, _accent_mat)
	shoulder_r.position = Vector3(0.3, 1.12, 0)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "RemotePlayerLabel"
	_label.text = username if not username.is_empty() else wallet.left(8)
	_label.font_size = 48
	_label.pixel_size = 0.005
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color(0.8, 0.9, 1.0)
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.7)
	_label.position = Vector3(0, 2.3, 0)
	add_child(_label)


func _apply_wallet_tint() -> void:
	## Generate a unique color from wallet address for visual distinction.
	if wallet.is_empty():
		return
	# Simple hash from wallet hex → hue
	var hash_val := 0
	for i in range(mini(wallet.length(), 10)):
		hash_val = hash_val * 31 + wallet.unicode_at(i)
	var hue := fmod(float(abs(hash_val)), 360.0) / 360.0
	var accent := Color.from_hsv(hue, 0.5, 0.8)

	# Accent tint on joints and eyes
	_accent_mat.albedo_color = Color(0.35, 0.22, 0.55).lerp(accent, 0.2)
	_eye_mat.albedo_color = accent.darkened(0.6)

	# Subtle suit tint (stays PulseChain purple)
	_suit_mat.albedo_color = Color(0.22, 0.14, 0.38).lerp(accent, 0.05)


func show_emote(emote_id: int) -> void:
	## Display a floating emote text above the player's head.
	var emote_icons := ["👋", "🫡", "💃", "🪑", "👉", "😂", "🤷", "👏"]
	if emote_id < 0 or emote_id >= emote_icons.size():
		return

	var emote_label := Label3D.new()
	emote_label.text = emote_icons[emote_id]
	emote_label.font_size = 96
	emote_label.pixel_size = 0.005
	emote_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	emote_label.no_depth_test = true
	emote_label.position = Vector3(0, 2.8, 0)
	add_child(emote_label)

	# Tween: float up and fade out over 2 seconds
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(emote_label, "position:y", 3.5, 2.0).set_ease(Tween.EASE_OUT)
	tw.tween_property(emote_label, "modulate:a", 0.0, 2.0).set_ease(Tween.EASE_IN).set_delay(0.5)
	tw.chain().tween_callback(emote_label.queue_free)


func cleanup() -> void:
	## Remove this remote player and its label from the scene.
	if _label and is_instance_valid(_label):
		_label.queue_free()
	queue_free()


# ─── Mesh Helpers ────────────────────────────────────────────────────────

func _sphere(n: String, radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

func _box(n: String, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

func _capsule(n: String, radius: float, height: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

func _torus(n: String, inner_r: float, ring_r: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_r
	mesh.outer_radius = inner_r + ring_r * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

func _capsule_child(n: String, radius: float, height: float, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _box_child(n: String, size: Vector3, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


func _sphere_child(n: String, radius: float, mat: StandardMaterial3D, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


# ─── Tier Icons ──────────────────────────────────────────────────────────

static func _get_tier_icon(t: int) -> String:
	var icons: Array[String] = [
		"", "", "", "", "",
		"", "", "", "", "",
	]
	if t >= 0 and t < icons.size():
		return icons[t]
	return ""
