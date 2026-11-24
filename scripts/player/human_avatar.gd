class_name HumanAvatar
extends Node3D
## The avatar: a rigged person of regular proportions, dressed in an outfit
## (Outfits: garments from Quaternius' Modular Character Outfits – Fantasy,
## CC0, re-coloured for the Field and sewn into one skinned mesh by
## OutfitTailor), driven by motion-captured animations (Quaternius Universal
## Animation Library, CC0: the same 65-bone Universal rig), wearing the head
## the player's LAU asks for (AvatarHeads) on its neck.
##
## Who wears what: wear_identity(wallet) picks the outfit and colours from the
## wallet alone, so every viewer sees the same; set_outfit(kind, seed) wears a
## given design (a player's own pick, an NPC's, or one the network syncs).
##
## Locomotion picks Idle / Walk / Jog / Sprint by speed, matching playback to
## the ground speed so the feet don't skate; Crouch, Jump (start, loop, land)
## and a swimming stroke for jetpack flight. Blends are crossfades.
##
## Interface used by the controller, Gear, NPCs and the territory scene:
## update_movement, set_head, set_body, set_outfit, wear_identity,
## set_suit_colors, apply_appearance, modulate_grey, set_crow, set_flying,
## set_territory_power, set_seated, set_air_pose, set_arm_patch.

const DIR := "res://assets/characters/quaternius/"
## The rig per body (regular proportions; the outfit is the visible body).
const BODIES := OutfitTailor.RIG
const ANIMS := DIR + "UAL1_Standard.glb"
const SHADER := "res://assets/shaders/outfit.gdshader"
const LOOPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump", "Swim_Fwd", "Swim_Idle",
	"Driving", "Sitting_Idle", "Sitting_Talking", "Idle_Talking", "Dance"]
## Ground speed (m/s) at which each clip plays at 1×.
const CLIP_SPEED := {"Walk": 1.7, "Jog_Fwd": 3.9, "Sprint": 6.2, "Crouch_Fwd": 1.3}
const HEAD_SCALE := 0.58
## Worn until someone says otherwise (the old suit's look: a flight suit).
const DEFAULT_OUTFIT := "flightsuit"
const XFADE := 0.22

static var _library: AnimationLibrary
static var _shader: Shader

var body_kind := "male"
var head_kind := "bear"
## The outfit design (Outfits.KINDS) and the seed that picks its colours.
var outfit_kind := DEFAULT_OUTFIT
var outfit_seed := 0
var body: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var extras: AvatarExtras
var outfit_mesh: MeshInstance3D
var _head_attach: BoneAttachment3D
var _head: Node3D
var _accessories: Array = []
var _back: BoneAttachment3D
var _badge: BoneAttachment3D
var _anchors := {}
var _clip := ""
## A clip held regardless of movement (NPCs: "Sitting_Idle", "Idle_Talking"…); "" = follow movement.
var hold_clip := ""
var hold_speed := 1.0
## Set before adding to the tree: an off-duty NPC (no badge, patch or jetpack).
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
var _outfit_mats: Array = []  # ShaderMaterial per outfit surface
var _skin_mat: StandardMaterial3D
var _colors := {}  # slot -> Color (Outfits.colors + set_suit_colors overrides)
var _overrides := {}
var _boot_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _trim_color := Color(0.45, 0.85, 1.0)
## The AFFECTION token's symbol (AFFECTION.symbol() reads "Ⓐ"), worn on every suit's chest.
const AFFECTION_GLOW := Color(1.0, 0.56, 0.78)
var _patch_tex: Texture2D  # the player's Aura fractal, worn as a patch on the left arm
var _patch: Node3D
var _hand_r: Node3D
## A hold point in the right hand (the fair hands out snacks), made on first
## use. Squashed like the old glove was, which the fair's holder undoes.
var _glove_right: Node3D:
	get:
		if (_hand_r == null or not is_instance_valid(_hand_r)) and skeleton:
			var ba := _attach("hand_r", Vector3(-0.075, -0.035, 0.035))
			_hand_r = Node3D.new()
			_hand_r.basis = Basis(Vector3(0, 0, 1), deg_to_rad(-78.0)) * Basis.from_scale(Vector3(0.85, 0.65, 1.0))
			ba.get_node("Holder").add_child(_hand_r)
		return _hand_r


func _ready() -> void:
	extras = AvatarExtras.new()
	extras.name = "Extras"
	add_child(extras)
	_build(body_kind)
	if _head == null:
		set_head(head_kind, _accessories)


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
		_home_flames()
		body.free()
		_head_attach = null
		_head = null
		_back = null
		_badge = null
		_patch = null
		outfit_mesh = null
	body_kind = kind if BODIES.has(kind) else "male"
	body = OutfitTailor.rig(body_kind)
	body.name = "Body"
	add_child(body)
	skeleton = body.get_node("Armature/Skeleton3D")
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	body.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", library())
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_clip = ""
	_play("Idle")
	anim.advance(0.0)
	_dress()
	if head_kind != "" and is_inside_tree():
		set_head(head_kind, _accessories)
	_self_layer()


## The flames live on the jetpack: bring them home before it goes.
func _home_flames() -> void:
	if extras == null:
		return
	for f in [extras._flame_left, extras._flame_right]:
		if f and f.get_parent() != extras:
			f.get_parent().remove_child(f)
			extras.add_child(f)


## Wears `kind` (Outfits.KINDS); `seed_value` picks its colours (-1 keeps the
## current seed). Called with the network's synced choice for remote players.
func set_outfit(kind: String, seed_value: int = -1) -> void:
	if not Outfits.DESIGNS.has(kind):
		kind = DEFAULT_OUTFIT
	if seed_value >= 0:
		outfit_seed = seed_value
	if kind == outfit_kind and (seed_value < 0 or seed_value == outfit_seed) and outfit_mesh != null:
		return
	outfit_kind = kind
	if skeleton:
		_redress()


## The outfit an identity wears for every viewer: from the wallet address only.
func wear_identity(wallet: String) -> void:
	var o := Outfits.for_identity(wallet)
	set_outfit(o["kind"], o["seed"])


func _redress() -> void:
	_home_flames()
	for n in [outfit_mesh, _back, _badge]:
		if n and is_instance_valid(n):
			n.free()
	if _patch and is_instance_valid(_patch):
		_patch.get_parent().get_parent().free()
	outfit_mesh = null
	_back = null
	_badge = null
	_patch = null
	_dress()
	if _grey:
		_grey = false
		modulate_grey(true)
	_self_layer()


func _material(atlas: String) -> Material:
	if _shader == null:
		_shader = load(SHADER)
	if atlas == "skin":
		var sk := StandardMaterial3D.new()
		var g := "Female" if body_kind == "female" else "Male"
		sk.normal_enabled = true
		sk.normal_texture = load(OutfitTailor.DIR + "T_Regular_%s_Normal.png" % g)
		sk.roughness_texture = load(OutfitTailor.DIR + "T_Regular_%s_Roughness.png" % g)
		sk.roughness = 1.0
		_skin_mat = sk
		return sk
	var m := ShaderMaterial.new()
	m.shader = _shader
	if atlas == "tailored":
		m.set_shader_parameter("textured", false)
	else:
		m.set_shader_parameter("mask_tex", load(OutfitTailor.DIR + "T_%s_Mask.png" % atlas))
		m.set_shader_parameter("normal_tex", load(OutfitTailor.DIR + "T_%s_Normal.png" % atlas))
		m.set_shader_parameter("orm_tex", load(OutfitTailor.DIR + "T_%s_ORM.png" % atlas))
	_outfit_mats.append(m)
	return m


## The outfit: one skinned mesh (OutfitTailor) under the skeleton, its
## colours from Outfits.colors(kind, seed); plus, on duty, the Ⓐ badge.
func _dress() -> void:
	var o := OutfitTailor.build(body_kind, outfit_kind)
	_anchors = o["anchors"]
	_outfit_mats.clear()
	_skin_mat = null
	outfit_mesh = MeshInstance3D.new()
	outfit_mesh.name = "Outfit"
	outfit_mesh.mesh = o["mesh"]
	outfit_mesh.skin = o["skin"]
	skeleton.add_child(outfit_mesh)
	outfit_mesh.skeleton = NodePath("..")
	var atlases: Array = o["atlases"]
	for i in atlases.size():
		outfit_mesh.set_surface_override_material(i, _material(atlases[i]))
	_colors = Outfits.colors(outfit_kind, outfit_seed)
	_apply_colors()
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
		return  # off duty: the outfit and the head only
	_affection_badge()
	_build_patch()
	_build_back()


func _apply_colors() -> void:
	var c := _colors.duplicate()
	c.merge(_overrides, true)
	for m in _outfit_mats:
		var sm := m as ShaderMaterial
		for slot in Outfits.SLOTS:
			sm.set_shader_parameter("col_" + slot, c[slot])
		sm.set_shader_parameter("col_skin", c["skin"])
		sm.set_shader_parameter("col_trim", _trim_color)
		sm.set_shader_parameter("grey", 1.0 if _grey else 0.0)
	if _skin_mat:
		var s: Color = c["skin"]
		if _grey:
			var l := s.get_luminance()
			s = Color(l, l, l * 1.05)
		_skin_mat.albedo_color = s


## The colours an outfit slot shows (Outfits.SLOTS + "skin").
func outfit_color(slot: String) -> Color:
	return _overrides.get(slot, _colors.get(slot, Color.GRAY))


func _affection_badge() -> void:
	var h := Node3D.new()
	h.scale = Vector3.ONE * 1.1
	_badge = _attach("spine_03", _anchors.get("chest", Vector3(0, 1.4, 0.13)) - _rest_origin("spine_03"))
	_badge.get_node("Holder").add_child(h)
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


## Re-colours the outfit's main cloth (`fabric`) and its straps and fittings
## (`armour`): the bartender wears cream and brown. Survives set_outfit.
func set_suit_colors(fabric: Color, armour: Color) -> void:
	_overrides = {"main": fabric, "accent": fabric.lightened(0.15), "leather": armour, "metal": armour.lightened(0.3)}
	if skeleton:
		_apply_colors()


func _rest_origin(bone: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin


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
	if _patch_tex == null or civilian:
		return
	var h: Node3D = _attach("upperarm_l", _anchors.get("arm", Vector3(0.3, 1.47, 0)) - _rest_origin("upperarm_l")).get_node("Holder")
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
	_back = _attach("spine_03", _anchors.get("back", Vector3(0, 1.38, -0.12)) - _rest_origin("spine_03") + Vector3(0.0, 0.0, -0.05))
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

func set_head(kind: String, accessories: Array = []) -> void:
	if not (kind in AvatarHeads.KINDS):
		kind = "bear"
	head_kind = kind
	_accessories = accessories
	if _head_attach:
		_head_attach.queue_free()
		_head_attach = null
	var creature := kind != "human"
	# On the neck (the Head bone itself is collapsed when a creature head is worn).
	_head_attach = _attach("neck_01", Vector3(0.0, 0.045, 0.03))
	var holder: Node3D = _head_attach.get_node("Holder")
	var scaled := Node3D.new()
	scaled.scale = Vector3.ONE * HEAD_SCALE
	holder.add_child(scaled)
	if creature:
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
	if skeleton:
		_apply_colors()


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
	if skeleton:
		_apply_colors()


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
