class_name HumanAvatar
extends Node3D
## The player's avatar: a rigged, skinned body (Quaternius Universal Base
## Characters, CC0) driven by motion-captured animations (Quaternius
## Universal Animation Library, CC0: the two share one 65-bone skeleton),
## wearing the head the player's LAU asks for (AvatarHeads) on its Head bone.
##
## Locomotion picks Idle / Walk / Jog / Sprint by speed, matching playback to
## the ground speed so the feet don't skate; Crouch, Jump (start, loop, land)
## and a swimming stroke for jetpack flight. Blends are crossfades.
##
## Same interface as the old procedural model, so the controller, Gear and the
## territory scene drive it unchanged: update_movement, set_head,
## apply_appearance, modulate_grey, set_crow, set_flying, set_territory_power.

const DIR := "res://assets/characters/quaternius/"
const BODIES := {"male": DIR + "Superhero_Male_FullBody.gltf", "female": DIR + "Superhero_Female_FullBody.gltf"}
const ANIMS := DIR + "UAL1_Standard.glb"
const LOOPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump", "Swim_Fwd", "Swim_Idle",
	"Driving", "Sitting_Idle", "Sitting_Talking", "Idle_Talking", "Dance"]
## Ground speed (m/s) at which each clip plays at 1×.
const CLIP_SPEED := {"Walk": 1.7, "Jog_Fwd": 3.9, "Sprint": 6.2, "Crouch_Fwd": 1.3}
const HEAD_SCALE := 0.58
const FABRIC := Color(0.075, 0.078, 0.095)
const ARMOUR := Color(0.27, 0.28, 0.32)
const XFADE := 0.22

static var _library: AnimationLibrary

var body_kind := "male"
var head_kind := "bear"
var body: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var extras: AvatarExtras
var _head_attach: BoneAttachment3D
var _head: Node3D
var _back: BoneAttachment3D
var _head_bone := -1
var _hide_human_head := true
var _clip := ""
## A clip held regardless of movement (NPCs: "Sitting_Idle", "Idle_Talking"…); "" = follow movement.
var hold_clip := ""
var hold_speed := 1.0
## Set before adding to the tree: an off-duty NPC (no armour, badge, patch or
## jetpack): about 16 meshes instead of 55, for rooms full of regulars.
var civilian := false
var _vel := Vector3.ZERO
var _on_floor := true
var _flying := false
var _was_on_floor := true
var _fall_speed := 0.0
var _land_t := 0.0
var _bank := 0.0
var _last_yaw := 0.0
var _grey := false
var _fly_blend := 0.0
var _fly_speed := 0.0
var _fly_pitch := 0.0
var _seat_clip := ""  ## "" = on foot; else the clip held while seated (a vehicle: "Driving")
var air_pose := ""  ## base jumping: "" (jetpack) | freefall | wingsuit | canopy
var _materials: Array = []  # [StandardMaterial3D, original albedo texture]
var _suit_mat: StandardMaterial3D
var _plate_mat: StandardMaterial3D
var _boot_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _trim_color := Color(0.45, 0.85, 1.0)
## The AFFECTION token's symbol (AFFECTION.symbol() reads "Ⓐ"), worn on every suit's chest.
const AFFECTION_GLOW := Color(1.0, 0.56, 0.78)
var _patch_tex: Texture2D  # the player's Aura fractal, worn as a patch on the left arm
var _patch: Node3D


func _ready() -> void:
	extras = AvatarExtras.new()
	extras.name = "Extras"
	add_child(extras)
	_build(body_kind)
	set_head("bear")


static func library() -> AnimationLibrary:
	if _library == null:
		var src: Node = load(ANIMS).instantiate()
		var ap: AnimationPlayer = src.get_node("AnimationPlayer")
		_library = ap.get_animation_library("").duplicate(true)
		src.free()
		for n in LOOPS:
			if _library.has_animation(n):
				_library.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return _library


func _build(kind: String) -> void:
	if body:
		# The flames live on the old body's jetpack: bring them home first.
		for f in [extras._flame_left, extras._flame_right]:
			if f and f.get_parent() != extras:
				f.get_parent().remove_child(f)
				extras.add_child(f)
		body.free()
		_head_attach = null
		_head = null
		_back = null
	body_kind = kind if BODIES.has(kind) else "male"
	body = load(BODIES[body_kind]).instantiate()
	body.name = "Body"
	add_child(body)
	skeleton = body.get_node("Armature/Skeleton3D")
	_head_bone = skeleton.find_bone("Head")
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	body.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", library())
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_clip = ""
	_play("Idle")
	anim.advance(0.0)
	_collect_materials()
	_dress()
	if not civilian:
		_build_back()
	_self_layer()
	if head_kind != "":
		set_head(head_kind)


func _collect_materials() -> void:
	_materials.clear()
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var mat := m.get_active_material(i)
			if mat is StandardMaterial3D:
				var copy := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.set_surface_override_material(i, copy)
				_materials.append([copy, copy.albedo_texture])


## The suit: the body becomes a dark sci-fi bodysuit (its own normal and
## roughness maps keep the muscle detail), with gunmetal armour, boots, a
## collar, a belt and glowing trim bolted to the bones.
func _dress() -> void:
	for pair in _materials:
		var m: StandardMaterial3D = pair[0]
		if m.resource_name.contains("Superhero") or (m.albedo_texture and m.albedo_texture.resource_path.contains("Superhero")):
			m.albedo_texture = null
			m.albedo_color = FABRIC
			m.metallic = 0.15
			m.roughness = 0.62
			m.rim_enabled = true
			m.rim = 0.2
			_suit_mat = m
	_plate_mat = StandardMaterial3D.new()
	_plate_mat.albedo_color = ARMOUR
	_plate_mat.metallic = 0.8
	_plate_mat.roughness = 0.3
	_boot_mat = StandardMaterial3D.new()
	_boot_mat.albedo_color = Color(0.05, 0.05, 0.06)
	_boot_mat.metallic = 0.3
	_boot_mat.roughness = 0.45
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trim_mat.albedo_color = _trim_color
	_trim_mat.emission_enabled = true
	_trim_mat.emission = _trim_color
	_trim_mat.emission_energy_multiplier = 1.8
	if civilian:
		return  # out of uniform: the bodysuit and the head only
	var female := body_kind == "female"
	var chest := 0.95 if female else 1.0
	# Torso
	_piece("spine_03", "sphere", Vector3(0.0, 0.06, 0.075), Vector3(0.19 * chest, 0.1, 0.055), _plate_mat)
	_piece("spine_03", "box", Vector3(0.0, -0.06, 0.133), Vector3(0.012, 0.05, 0.01), _trim_mat)
	_affection_badge()
	for i in 3:
		_piece("spine_01", "box", Vector3(0.0, 0.05 + i * 0.055, 0.105 - i * 0.004), Vector3(0.2 - i * 0.015, 0.042, 0.03), _plate_mat)
	_piece("neck_01", "torus", Vector3(0.0, -0.035, 0.015), Vector3(0.085, 0.11, 0.0), _plate_mat)
	_piece("pelvis", "torus", Vector3(0.0, 0.03, 0.035), Vector3(0.16, 0.185, 0.75), _plate_mat)
	_piece("pelvis", "box", Vector3(0.0, 0.03, 0.155), Vector3(0.06, 0.04, 0.02), _trim_mat)
	for side in [1.0, -1.0]:
		var l := "_l" if side > 0.0 else "_r"
		# Arms (T-pose: along X)
		_piece("upperarm" + l, "sphere", Vector3(side * 0.035, 0.035, 0.0), Vector3(0.085, 0.05, 0.08), _plate_mat)
		_piece("lowerarm" + l, "box", Vector3(side * 0.13, 0.0, 0.0), Vector3(0.15, 0.08, 0.085), _plate_mat)
		_piece("lowerarm" + l, "box", Vector3(side * 0.13, 0.0, 0.045), Vector3(0.06, 0.012, 0.008), _trim_mat)
		_piece("hand" + l, "box", Vector3(side * 0.035, 0.0, 0.0), Vector3(0.045, 0.06, 0.08), _boot_mat)
		# Legs (along -Y)
		_piece("thigh" + l, "box", Vector3(0.0, -0.2, 0.075), Vector3(0.12, 0.2, 0.035), _plate_mat)
		_piece("thigh" + l, "box", Vector3(side * 0.085, -0.2, 0.0), Vector3(0.012, 0.24, 0.012), _trim_mat)
		_piece("calf" + l, "sphere", Vector3(0.0, 0.0, 0.055), Vector3(0.05, 0.055, 0.03), _plate_mat)
		_piece("calf" + l, "box", Vector3(0.0, -0.2, 0.06), Vector3(0.1, 0.22, 0.03), _plate_mat)
		_piece("foot" + l, "sphere", Vector3(0.0, -0.02, 0.03), Vector3(0.062, 0.06, 0.15), _boot_mat)
		_piece("foot" + l, "box", Vector3(0.0, -0.072, 0.03), Vector3(0.11, 0.022, 0.27), _plate_mat)
	_build_patch()


## Ⓐ in the middle of the chest plate: a dark disc, a glowing ring and an A.
func _affection_badge() -> void:
	var h := Node3D.new()
	h.scale = Vector3.ONE * 1.35
	_attach("spine_03", Vector3(0.0, 0.045, 0.132)).get_node("Holder").add_child(h)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = AFFECTION_GLOW
	glow.emission_enabled = true
	glow.emission = AFFECTION_GLOW
	glow.emission_energy_multiplier = 2.2
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 0.004
	cm.radial_segments = 32
	disc.mesh = cm
	disc.material_override = _boot_mat
	disc.rotation_degrees.x = 90.0
	h.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.039
	tm.outer_radius = 0.046
	tm.rings = 32
	ring.mesh = tm
	ring.material_override = glow
	ring.rotation_degrees.x = 90.0
	ring.scale = Vector3(1.0, 0.3, 1.0)
	ring.position.z = 0.003
	h.add_child(ring)
	var lean := rad_to_deg(atan2(0.021, 0.056))
	for side in [-1.0, 1.0]:  # the two legs of the A
		_badge_bar(h, Vector3(side * 0.0105, 0.0, 0.004), Vector3(0.008, 0.06, 0.004), side * lean, glow)
	_badge_bar(h, Vector3(0.0, -0.007, 0.004), Vector3(0.024, 0.007, 0.004), 0.0, glow)


func _badge_bar(parent: Node3D, at: Vector3, size: Vector3, roll_deg: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees.z = roll_deg
	parent.add_child(mi)


## Re-colours the suit (the bartender wears cream and brown).
func set_suit_colors(fabric: Color, armour: Color) -> void:
	if _suit_mat:
		_suit_mat.albedo_color = fabric
	if _plate_mat:
		_plate_mat.albedo_color = armour
		_plate_mat.metallic = 0.2


## The Aura patch on the outside of the left upper arm (Gear supplies the
## fractal). Its top points at the shoulder when the arm hangs down.
func set_arm_patch(tex: Texture2D) -> void:
	_patch_tex = tex
	if skeleton:
		_build_patch()
		_self_layer()


func _build_patch() -> void:
	if _patch and is_instance_valid(_patch):
		_patch.get_parent().get_parent().queue_free()
	_patch = null
	if _patch_tex == null:
		return
	var h: Node3D = _attach("upperarm_l", Vector3(0.13, 0.052, 0.0)).get_node("Holder")
	_patch = Node3D.new()
	# Face +Y (outward with the arm down), image-up toward the shoulder (-X), image-right toward the back.
	_patch.basis = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	h.add_child(_patch)
	var edge := MeshInstance3D.new()
	var eq := QuadMesh.new()
	eq.size = Vector2(0.088, 0.088)
	edge.mesh = eq
	edge.material_override = _trim_mat
	_patch.add_child(edge)
	var face := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.078, 0.078)
	face.mesh = fq
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = _patch_tex
	face.material_override = fm
	face.position.z = 0.0015
	_patch.add_child(face)


## A mesh on `bone`, placed in body space (offset from the bone, at rest).
## Shapes: sphere (size = radii), box (size), torus (x inner, y outer, z flatten).
func _piece(bone: String, shape: String, offset: Vector3, size: Vector3, mat: Material) -> void:
	var ba := _attach(bone, offset)
	var mi := MeshInstance3D.new()
	match shape:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 24
			sm.rings = 12
			mi.mesh = sm
			mi.scale = size
		"torus":
			var tm := TorusMesh.new()
			tm.inner_radius = size.x
			tm.outer_radius = size.y
			mi.mesh = tm
			if size.z > 0.0:
				mi.scale = Vector3(1.0, 1.0, size.z)
		_:
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
	mi.material_override = mat
	ba.get_node("Holder").add_child(mi)


## A node following `bone`, with its own axes realigned to the body's (Y up,
## Z forward) at rest, so attachments are authored in body space.
func _attach(bone: String, offset: Vector3) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	var holder := Node3D.new()
	holder.name = "Holder"
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(bone))
	holder.transform = Transform3D(rest.basis.inverse(), rest.basis.inverse() * offset)
	ba.add_child(holder)
	return ba


func _build_back() -> void:
	# A slim jetpack on the upper back; the flames come out of its two nozzles.
	_back = _attach("spine_03", Vector3(0.0, -0.02, -0.16))
	var h: Node3D = _back.get_node("Holder")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.23, 0.27)
	metal.metallic = 0.8
	metal.roughness = 0.3
	var pack := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.26, 0.3, 0.1)
	pack.mesh = bx
	pack.material_override = metal
	h.add_child(pack)
	var trim := StandardMaterial3D.new()
	trim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trim.albedo_color = Color(0.45, 0.85, 1.0)
	trim.emission_enabled = true
	trim.emission = Color(0.45, 0.85, 1.0)
	trim.emission_energy_multiplier = 1.6
	var strip := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.18, 0.012, 0.012)
	strip.mesh = sb
	strip.material_override = trim
	strip.position = Vector3(0, 0.09, -0.052)
	h.add_child(strip)
	for sx in [-1.0, 1.0]:
		var noz := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.05
		c.height = 0.08
		noz.mesh = c
		noz.material_override = metal
		noz.position = Vector3(sx * 0.075, -0.18, 0.0)
		h.add_child(noz)
	for f in [extras._flame_left, extras._flame_right]:
		if f:
			f.get_parent().remove_child(f)
			h.add_child(f)
	if extras._flame_left:
		extras._flame_left.position = Vector3(-0.075, -0.24, 0.0)
		extras._flame_right.position = Vector3(0.075, -0.24, 0.0)


## Swaps the head. "human" shows the body's own head; anything else hides it
## (the Head bone is collapsed) and builds that head on the Head bone.
func set_head(kind: String, accessories: Array = []) -> void:
	if not (kind in AvatarHeads.KINDS):
		kind = "bear"
	head_kind = kind
	if _head_attach:
		_head_attach.queue_free()
		_head_attach = null
	_hide_human_head = kind != "human"
	# On the neck (the Head bone itself is collapsed when a creature head is worn).
	_head_attach = _attach("neck_01", Vector3(0.0, 0.045, 0.03))
	var holder: Node3D = _head_attach.get_node("Holder")
	var scaled := Node3D.new()
	scaled.scale = Vector3.ONE * HEAD_SCALE
	holder.add_child(scaled)
	if _hide_human_head:
		_head = AvatarHeads.build(kind)
		scaled.add_child(_head)
	else:
		# "human": the suit covers the face, so wear it as a helmet with a visor.
		_head = Node3D.new()
		scaled.add_child(_head)
		var shell := StandardMaterial3D.new()
		shell.albedo_color = Color(0.16, 0.17, 0.2)
		shell.metallic = 0.85
		shell.roughness = 0.25
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.02, 0.03, 0.05)
		glass.metallic = 0.9
		glass.roughness = 0.05
		glass.emission_enabled = true
		glass.emission = _trim_color * 0.35
		AvatarHeads._sphere(_head, 0.22, shell, Vector3(0, 0.25, -0.01), Vector3(1.0, 1.05, 1.05))
		var visor := AvatarHeads._sphere(_head, 0.2, glass, Vector3(0, 0.25, 0.06), Vector3(0.92, 0.62, 0.9))
		visor.rotation_degrees.x = -6.0
		_hide_human_head = true
	var top := 0.46 if kind != "alien" else 0.56
	if kind == "human":
		top = 0.38
	for a in accessories:
		scaled.add_child(AvatarHeads.accessory(a, top))
	if _grey:
		_grey = false
		modulate_grey(true)
	_self_layer()


## Every mesh of the avatar on render layer 2: the camera sees it, the player's
## own flashlight (light_cull_mask without layer 2) never lights it.
func _self_layer() -> void:
	for vi in find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers = 2


## Base jumping (BaseJump): the flying pose without the jetpack's flames, shaped
## for a belly-to-earth freefall, a wingsuit (arms and legs spread for the
## membranes) or hanging under a canopy (hands up on the toggles). "" = normal.
func set_air_pose(p: String) -> void:
	air_pose = p


func update_movement(vel: Vector3, on_floor: bool, flying: bool) -> void:
	_vel = vel
	_on_floor = on_floor
	_flying = flying
	if not on_floor:
		_fall_speed = minf(_fall_speed, vel.y)


func _play(clip: String, speed: float = 1.0) -> void:
	if not anim.has_animation(clip):
		clip = "Idle"
	if clip != _clip:
		anim.play(clip, XFADE)
		_clip = clip
	anim.speed_scale = speed


func _crouching() -> bool:
	var p := get_parent()
	return p != null and "is_crouching" in p and bool(p.get("is_crouching"))


func _process(delta: float) -> void:
	if anim == null:
		return
	var speed := Vector2(_vel.x, _vel.z).length()
	if _seat_clip != "":
		_play(_seat_clip)
		extras.set_flames(false, Vector3.ZERO, Vector3.ZERO)
		_fly_blend = 0.0
		speed = 0.0
	elif _flying:
		# Flying: the Idle clip keeps the torso alive; the arms and legs are posed
		# over it (_fly_pose) and the whole body pitches into the direction of travel.
		_play("Idle")
		_fly_blend = minf(1.0, _fly_blend + delta * 3.0)
		_fly_speed = speed
		if air_pose == "":
			extras.set_flames(true, Vector3.ZERO, Vector3.ZERO, 0.6 + clampf(speed / 30.0, 0.0, 0.4))
		else:
			extras.set_flames(false, Vector3.ZERO, Vector3.ZERO)
	else:
		extras.set_flames(false, Vector3.ZERO, Vector3.ZERO)
		_fly_blend = maxf(0.0, _fly_blend - delta * 4.0)
		if hold_clip != "":
			_play(hold_clip, hold_speed)
		elif not _on_floor:
			if _was_on_floor and _vel.y > 1.0:
				_play("Jump_Start")
			elif _clip != "Jump_Start" or not anim.is_playing() or anim.current_animation_position > 0.25:
				_play("Jump")
		elif not _was_on_floor and _fall_speed < -5.0:
			_land_t = 0.35
			_play("Jump_Land", 1.3)
		elif _land_t > 0.0:
			_land_t -= delta
		elif _crouching():
			_play("Crouch_Fwd" if speed > 0.4 else "Crouch_Idle", maxf(0.6, speed / CLIP_SPEED["Crouch_Fwd"]) if speed > 0.4 else 1.0)
		elif speed < 0.4:
			_play("Idle")
		elif speed < 4.5:
			_play("Walk", clampf(speed / CLIP_SPEED["Walk"], 0.7, 2.4))
		elif speed < 10.0:
			_play("Jog_Fwd", clampf(speed / CLIP_SPEED["Jog_Fwd"], 0.8, 2.2))
		else:
			_play("Sprint", clampf(speed / CLIP_SPEED["Sprint"], 0.9, 2.4))
	if _on_floor:
		_fall_speed = 0.0
	_was_on_floor = _on_floor
	anim.advance(delta)
	if _fly_blend > 0.0:
		_fly_pose(delta)
	else:
		body.transform = Transform3D.IDENTITY
	# Hide the human head under a creature head: collapse the Head bone.
	if _hide_human_head and _head_bone >= 0:
		skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * 0.001)
	# Lean into turns (yaw rate × speed), like a runner banking.
	var yaw := global_rotation.y
	var rate := wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.0001)
	_last_yaw = yaw
	_bank = lerpf(_bank, clampf(-rate * speed * 0.02, -0.25, 0.25), clampf(6.0 * delta, 0.0, 1.0))
	if _fly_blend <= 0.0:
		body.rotation.z = _bank


## The flying pose, layered over the clip: arms down along the sides and swept
## back (palms trailing), legs together and straight with a soft knee, the
## head lifted to look ahead, and the body pitched forward with speed about
## the hips. Rotations are in skeleton space relative to the T-pose rest.
const FLY_PIVOT := Vector3(0.0, 1.0, 0.0)


func _fly_pose(delta: float) -> void:
	var w := _fly_blend
	var sp := clampf(_fly_speed / 30.0, 0.0, 1.0)
	var climb := clampf(_vel.y / 10.0, -1.0, 1.0)
	var pitch_deg := lerpf(10.0, 78.0, sp) - climb * 25.0
	var spread_deg := lerpf(14.0, 6.0, sp)
	var elbow_deg := 8.0
	var leg_deg := 3.0
	var knee_deg := 14.0
	match air_pose:
		"freefall":
			pitch_deg = 86.0
			spread_deg = 68.0
			elbow_deg = 38.0
			leg_deg = 9.0
			knee_deg = 48.0
		"wingsuit":
			pitch_deg = 80.0 - climb * 10.0
			spread_deg = 46.0
			leg_deg = 12.0
			knee_deg = 4.0
		"canopy":
			pitch_deg = 6.0
			spread_deg = 140.0
			elbow_deg = 30.0
			knee_deg = 10.0
	_fly_pitch = lerpf(_fly_pitch, deg_to_rad(pitch_deg), clampf(4.0 * delta, 0.0, 1.0))
	var t := Time.get_ticks_msec() / 1000.0
	var sweep := deg_to_rad(lerpf(8.0, 28.0, sp)) if air_pose == "" else deg_to_rad(6.0)
	for side in [1.0, -1.0]:
		var l := "_l" if side > 0.0 else "_r"
		var down := Basis(Vector3.BACK, -side * deg_to_rad(78.0))  # T-pose arm → hanging at the side
		var back := Basis(Vector3.RIGHT, sweep + 0.04 * sin(t * 2.0 + side))
		var out := Basis(Vector3.BACK, side * deg_to_rad(spread_deg))
		var arm := back * out * down
		_set_global("upperarm" + l, arm, w)
		_set_global("lowerarm" + l, Basis(Vector3.RIGHT, deg_to_rad(elbow_deg)) * arm, w, "upperarm" + l, arm)
		var leg := Basis(Vector3.BACK, side * deg_to_rad(leg_deg)) * Basis(Vector3.RIGHT, deg_to_rad(4.0 + 3.0 * sin(t * 2.2 + side)))
		_set_global("thigh" + l, leg, w)
		_set_global("calf" + l, Basis(Vector3.RIGHT, deg_to_rad(knee_deg)) * leg, w, "thigh" + l, leg)
	# Look ahead: the neck counters most of the pitch.
	_set_global("neck_01", Basis(Vector3.RIGHT, _fly_pitch * 0.75 * w), w)
	# Pitch the whole body about the hips, banking into turns.
	var rot := Basis(Vector3.RIGHT, _fly_pitch * w) * Basis(Vector3.BACK, _bank * 1.5 * w)
	body.transform = Transform3D(rot, FLY_PIVOT - rot * FLY_PIVOT + Vector3(0.0, 0.15 * w, 0.0))


## Poses `bone` so its skeleton-space orientation is `delta * rest` (blended
## by w with the clip). `parent_delta` gives the parent's posed orientation
## when we posed the parent too.
func _set_global(bone: String, delta_basis: Basis, w: float, parent: String = "", parent_delta: Basis = Basis()) -> void:
	var b := skeleton.find_bone(bone)
	if b < 0:
		return
	var p := skeleton.get_bone_parent(b)
	var want := delta_basis * skeleton.get_bone_global_rest(b).basis
	var parent_global: Basis
	if parent != "":
		parent_global = parent_delta * skeleton.get_bone_global_rest(skeleton.find_bone(parent)).basis
	else:
		parent_global = skeleton.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var local := (parent_global.orthonormalized().inverse() * want.orthonormalized()).get_rotation_quaternion()
	var cur := skeleton.get_bone_pose_rotation(b)
	skeleton.set_bone_pose_rotation(b, cur.slerp(local, w))


func apply_appearance(appearance: Dictionary) -> void:
	var h: float = appearance.get("height", 1.8)
	scale = Vector3.ONE * clampf(h / 1.8, 0.9, 1.1)
	# Trim glows in the wearer's accent colour (from their Soul).
	var accent: Color = appearance.get("accent_color", Color(0.45, 0.85, 1.0))
	_trim_color = accent.lerp(Color(0.45, 0.85, 1.0), 0.3)
	if _trim_mat and not _grey:
		_trim_mat.albedo_color = _trim_color
		_trim_mat.emission = _trim_color


## No bars anywhere: drawn without colour (the site's avatar rule).
func modulate_grey(grey: bool) -> void:
	if grey == _grey:
		return
	_grey = grey
	if _trim_mat:
		var c := Color(0.55, 0.56, 0.6) if grey else _trim_color
		_trim_mat.albedo_color = c
		_trim_mat.emission = c
		_trim_mat.emission_energy_multiplier = 0.4 if grey else 1.8
	if _head:
		for mi in _head.find_children("*", "MeshInstance3D", true, false):
			var hm := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if hm:
				if not hm.has_meta("orig"):
					hm.set_meta("orig", hm.albedo_color)
				var o: Color = hm.get_meta("orig")
				var lum := o.get_luminance()
				hm.albedo_color = Color(lum, lum, lum * 1.05, o.a) if grey else o
	for pair in _materials:
		var m: StandardMaterial3D = pair[0]
		var tex: Texture2D = pair[1]
		if tex == null:
			continue
		m.albedo_texture = _grey_of(tex) if grey else tex


static var _grey_cache := {}


static func _grey_of(tex: Texture2D) -> Texture2D:
	if _grey_cache.has(tex):
		return _grey_cache[tex]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.adjust_bcs(1.0, 1.0, 0.0)
	var t := ImageTexture.create_from_image(img)
	_grey_cache[tex] = t
	return t


func set_crow(on: bool) -> void:
	extras.set_crow(on)


## Seated in a vehicle (GarageSite): hold `clip` ("" = back on foot).
func set_seated(clip: String) -> void:
	_seat_clip = clip
	_vel = Vector3.ZERO
	_on_floor = true
	_was_on_floor = true


func set_flying(_on: bool) -> void:
	pass  # flight is read from update_movement


## Kept for the territory scene; the suit has no power lines to light.
func set_territory_power(_p: float) -> void:
	pass


## A local body choice ("male"/"female"), like the head picker.
func set_body(kind: String) -> void:
	if kind != body_kind and BODIES.has(kind):
		_build(kind)
