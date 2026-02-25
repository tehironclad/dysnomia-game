class_name CreatureModel
## Static factory for detailed procedural creature meshes.
## Each builder returns a Node3D root with 15-25 mesh primitives arranged
## into a distinctive silhouette.  Intended to replace the simple primitives
## generated inside creature.gd._build_model().

const CREATURE_DETAIL_SHADER = preload("res://assets/shaders/creature_detail.gdshader")


# =====================================================================
#  STALKER  --  Sleek quadruped predator
# =====================================================================
static func build_stalker() -> Node3D:
	var root := Node3D.new()
	root.name = "StalkerModel"

	# -- Materials --
	var body_mat := _make_body_mat(Color(0.12, 0.13, 0.20))       # dark blue-grey
	var accent_mat := _make_accent_mat(Color(0.08, 0.10, 0.16))   # slightly darker
	var glow_mat := _make_emissive_mat(Color(0.1, 0.85, 0.95), 2.5) # cyan bioluminescence
	var eye_mat := _make_emissive_mat(Color(1.0, 0.15, 0.1), 3.0)   # red eyes

	# Shader material for main body surfaces
	var shader_mat := _make_shader_mat(
		Vector3(0.12, 0.13, 0.20),
		Vector3(0.1, 0.85, 0.95),
		0.6
	)

	# -- Body core (elongated capsule) --
	var body := _capsule(1.6, 0.28)
	body.name = "Body"
	body.rotation_degrees.x = 90.0  # lay horizontal
	body.position = Vector3(0.0, 0.75, 0.0)
	body.scale = Vector3(0.9, 1.0, 1.15)
	body.material_override = shader_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)

	# -- Ribcage / upper torso bulge --
	var torso := _capsule(0.7, 0.32)
	torso.name = "Torso"
	torso.rotation_degrees.x = 90.0
	torso.position = Vector3(0.0, 0.82, 0.10)
	torso.material_override = shader_mat
	torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(torso)

	# -- Head (narrow triangle approximated by scaled sphere) --
	var head := _sphere(0.18)
	head.name = "Head"
	head.scale = Vector3(0.7, 0.85, 1.3)
	head.position = Vector3(0.0, 0.88, 0.85)
	head.material_override = shader_mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(head)

	# -- Snout --
	var snout := _capsule(0.22, 0.08)
	snout.name = "Snout"
	snout.rotation_degrees.x = 80.0
	snout.position = Vector3(0.0, 0.84, 1.05)
	snout.material_override = accent_mat
	snout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(snout)

	# -- Antennae (2 thin cylinders) --
	for side in [-1.0, 1.0]:
		var antenna := _cylinder(0.35, 0.015)
		antenna.name = "Antenna_R" if side > 0 else "Antenna_L"
		antenna.position = Vector3(side * 0.08, 1.08, 0.80)
		antenna.rotation_degrees = Vector3(-25.0, 0.0, side * 20.0)
		antenna.material_override = glow_mat
		antenna.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(antenna)

	# -- Eyes (2 small glowing spheres) --
	for side in [-1.0, 1.0]:
		var eye := _sphere(0.045)
		eye.name = "Eye_R" if side > 0 else "Eye_L"
		eye.position = Vector3(side * 0.09, 0.93, 0.98)
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(eye)

	# -- Bioluminescent side stripes (flat boxes, 2 per side) --
	for side in [-1.0, 1.0]:
		for i in range(2):
			var stripe := _box(Vector3(0.02, 0.06, 0.30))
			stripe.name = "Stripe_%s_%d" % ["R" if side > 0 else "L", i]
			stripe.position = Vector3(side * 0.30, 0.78 + i * 0.08, 0.0 + i * 0.20)
			stripe.material_override = glow_mat
			stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(stripe)

	# -- Legs (4 digitigrade legs: upper + lower segment + joint sphere) --
	var leg_positions := [
		Vector3(-0.22, 0.55, 0.40),   # front-left
		Vector3(0.22, 0.55, 0.40),    # front-right
		Vector3(-0.24, 0.55, -0.35),  # back-left
		Vector3(0.24, 0.55, -0.35),   # back-right
	]
	var leg_names := ["FL", "FR", "BL", "BR"]
	for i in range(4):
		var lp: Vector3 = leg_positions[i]
		var ln: String = leg_names[i]

		# Upper leg
		var upper := _cylinder(0.28, 0.04)
		upper.name = "Leg_%s_Upper" % ln
		upper.position = lp
		upper.rotation_degrees.x = 15.0 if i < 2 else -10.0
		upper.material_override = body_mat
		upper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(upper)

		# Knee joint
		var knee := _sphere(0.05)
		knee.name = "Leg_%s_Knee" % ln
		knee.position = lp + Vector3(0.0, -0.25, 0.04 if i < 2 else -0.03)
		knee.material_override = accent_mat
		root.add_child(knee)

		# Lower leg
		var lower := _cylinder(0.30, 0.03)
		lower.name = "Leg_%s_Lower" % ln
		lower.position = lp + Vector3(0.0, -0.45, 0.08 if i < 2 else -0.06)
		lower.rotation_degrees.x = -20.0 if i < 2 else 10.0
		lower.material_override = body_mat
		lower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(lower)

	# -- Tail (3 thin segments, tapering) --
	var tail_z := -0.75
	for seg in range(3):
		var r := 0.035 - seg * 0.008
		var tail := _cylinder(0.30, r)
		tail.name = "Tail_%d" % seg
		tail.rotation_degrees.x = 75.0 + seg * 8.0
		tail.position = Vector3(0.0, 0.68 - seg * 0.06, tail_z - seg * 0.28)
		tail.material_override = accent_mat
		tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(tail)

	return root


# =====================================================================
#  CRAWLER  --  Armored beetle tank
# =====================================================================
static func build_crawler() -> Node3D:
	var root := Node3D.new()
	root.name = "CrawlerModel"

	var body_mat := _make_body_mat(Color(0.30, 0.22, 0.15))        # dark brown
	var plate_mat := _make_body_mat(Color(0.50, 0.32, 0.14))       # rust/brown
	var accent_mat := _make_accent_mat(Color(0.85, 0.50, 0.12))    # orange accent
	var eye_mat := _make_emissive_mat(Color(1.0, 0.6, 0.1), 2.0)   # orange eyes
	var glow_mat := _make_emissive_mat(Color(0.9, 0.45, 0.08), 1.5) # orange glow seams

	var shader_mat := _make_shader_mat(
		Vector3(0.30, 0.22, 0.15),
		Vector3(0.9, 0.45, 0.08),
		0.4
	)

	# -- Body segments (4 capsules, widest in middle) --
	var seg_data := [
		{"h": 0.50, "r": 0.30, "pos": Vector3(0.0, 0.40, 0.55)},   # head segment
		{"h": 0.60, "r": 0.42, "pos": Vector3(0.0, 0.42, 0.18)},   # thorax
		{"h": 0.65, "r": 0.45, "pos": Vector3(0.0, 0.42, -0.22)},  # abdomen front
		{"h": 0.50, "r": 0.35, "pos": Vector3(0.0, 0.40, -0.55)},  # abdomen rear
	]
	for i in range(seg_data.size()):
		var s: Dictionary = seg_data[i]
		var seg := _capsule(s["h"], s["r"])
		seg.name = "Segment_%d" % i
		seg.rotation_degrees.x = 90.0
		seg.position = s["pos"]
		seg.scale = Vector3(1.0, 1.0, 0.7)  # flatten vertically
		seg.material_override = shader_mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(seg)

	# -- Armored back plates (3 overlapping boxes like beetle elytra) --
	for i in range(3):
		var plate := _box(Vector3(0.40 - i * 0.03, 0.04, 0.32))
		plate.name = "Plate_%d" % i
		plate.position = Vector3(0.0, 0.62 + i * 0.04, -0.05 - i * 0.22)
		plate.rotation_degrees.x = -5.0 * i
		plate.material_override = plate_mat
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(plate)

	# -- Plate edge glow strips --
	for i in range(3):
		var strip := _box(Vector3(0.38 - i * 0.03, 0.01, 0.02))
		strip.name = "PlateGlow_%d" % i
		strip.position = Vector3(0.0, 0.63 + i * 0.04, 0.10 - i * 0.22)
		strip.material_override = glow_mat
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(strip)

	# -- Mandibles (2 curved cylinders at front) --
	for side in [-1.0, 1.0]:
		var mandible := _cylinder(0.22, 0.035)
		mandible.name = "Mandible_R" if side > 0 else "Mandible_L"
		mandible.position = Vector3(side * 0.14, 0.32, 0.78)
		mandible.rotation_degrees = Vector3(60.0, 0.0, side * -25.0)
		mandible.material_override = accent_mat
		mandible.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mandible)

	# -- Eyes (2 small beady spheres) --
	for side in [-1.0, 1.0]:
		var eye := _sphere(0.05)
		eye.name = "Eye_R" if side > 0 else "Eye_L"
		eye.position = Vector3(side * 0.16, 0.48, 0.68)
		eye.material_override = eye_mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(eye)

	# -- 6 short arthropod legs (3 per side: front, mid, rear) --
	var z_offsets := [0.35, 0.0, -0.35]
	for side in [-1.0, 1.0]:
		for li in range(3):
			# Coxa (upper)
			var coxa := _cylinder(0.16, 0.04)
			coxa.name = "Leg_%s_%d_Coxa" % ["R" if side > 0 else "L", li]
			coxa.position = Vector3(side * 0.38, 0.28, z_offsets[li])
			coxa.rotation_degrees = Vector3(0.0, 0.0, side * 50.0)
			coxa.material_override = body_mat
			coxa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(coxa)

			# Tibia (lower)
			var tibia := _cylinder(0.18, 0.03)
			tibia.name = "Leg_%s_%d_Tibia" % ["R" if side > 0 else "L", li]
			tibia.position = Vector3(side * 0.52, 0.12, z_offsets[li])
			tibia.rotation_degrees = Vector3(0.0, 0.0, side * -15.0)
			tibia.material_override = body_mat
			tibia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(tibia)

	return root


# =====================================================================
#  FLOATER  --  Jellyfish-like aerial creature
# =====================================================================
static func build_floater() -> Node3D:
	var root := Node3D.new()
	root.name = "FloaterModel"

	var body_mat := _make_translucent_mat(Color(0.50, 0.30, 0.55, 0.65)) # purple
	var membrane_mat := _make_translucent_mat(Color(0.55, 0.28, 0.60, 0.40)) # lighter purple
	var glow_mat := _make_emissive_mat(Color(0.95, 0.25, 0.80), 3.5) # magenta glow
	var inner_glow_mat := _make_emissive_mat(Color(1.0, 0.35, 0.90), 5.0) # bright inner
	var tentacle_mat := _make_translucent_mat(Color(0.60, 0.35, 0.65, 0.50))

	var shader_mat := _make_shader_mat(
		Vector3(0.50, 0.30, 0.55),
		Vector3(0.95, 0.25, 0.80),
		1.0
	)

	# -- Dome body (vertically squashed sphere) --
	var dome := _sphere(0.50)
	dome.name = "Dome"
	dome.scale = Vector3(1.0, 0.55, 1.0)
	dome.position = Vector3(0.0, 1.2, 0.0)
	dome.material_override = shader_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(dome)

	# -- Dome cap (smaller sphere on top for depth) --
	var cap := _sphere(0.35)
	cap.name = "DomeCap"
	cap.scale = Vector3(1.0, 0.45, 1.0)
	cap.position = Vector3(0.0, 1.32, 0.0)
	cap.material_override = membrane_mat
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cap)

	# -- Inner glow orb --
	var orb := _sphere(0.15)
	orb.name = "InnerOrb"
	orb.position = Vector3(0.0, 1.15, 0.0)
	orb.material_override = inner_glow_mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(orb)

	# -- Equator ring (TorusMesh) --
	var ring := _torus(0.42, 0.03)
	ring.name = "EquatorRing"
	ring.position = Vector3(0.0, 1.05, 0.0)
	ring.material_override = glow_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

	# -- Membrane fins (4 flat boxes around equator) --
	for i in range(4):
		var angle := i * TAU / 4.0
		var fin := _box(Vector3(0.18, 0.005, 0.10))
		fin.name = "Fin_%d" % i
		fin.position = Vector3(cos(angle) * 0.42, 1.05, sin(angle) * 0.42)
		fin.rotation_degrees.y = rad_to_deg(-angle)
		fin.material_override = membrane_mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fin)

	# -- Tentacles (5 chains, 3 segments each) --
	for t in range(5):
		var t_angle := t * TAU / 5.0
		var base_x := cos(t_angle) * 0.22
		var base_z := sin(t_angle) * 0.22
		for seg in range(3):
			var tentacle := _cylinder(0.20 - seg * 0.03, 0.018 - seg * 0.004)
			tentacle.name = "Tentacle_%d_%d" % [t, seg]
			tentacle.position = Vector3(
				base_x + cos(t_angle) * seg * 0.04,
				0.90 - seg * 0.22,
				base_z + sin(t_angle) * seg * 0.04
			)
			tentacle.rotation_degrees = Vector3(
				randf_range(-8.0, 8.0),
				0.0,
				randf_range(-8.0, 8.0)
			)
			if seg == 2:
				tentacle.material_override = glow_mat
			else:
				tentacle.material_override = tentacle_mat
			tentacle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(tentacle)

	# -- Dangling bioluminescent nodules (3 at bottom of select tentacles) --
	for n in range(3):
		var n_angle := n * TAU / 3.0 + 0.3
		var nub := _sphere(0.03)
		nub.name = "Nodule_%d" % n
		nub.position = Vector3(cos(n_angle) * 0.18, 0.22, sin(n_angle) * 0.18)
		nub.material_override = inner_glow_mat
		nub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(nub)

	return root


# =====================================================================
#  BURROWER  --  Worm-like ambush predator
# =====================================================================
static func build_burrower() -> Node3D:
	var root := Node3D.new()
	root.name = "BurrowerModel"

	var body_mat := _make_body_mat(Color(0.28, 0.25, 0.22))         # earthy brown-grey
	var dark_mat := _make_body_mat(Color(0.18, 0.16, 0.14))         # darker underside
	var nub_mat := _make_emissive_mat(Color(0.95, 0.18, 0.12), 2.0) # red sensory
	var jaw_mat := _make_accent_mat(Color(0.35, 0.28, 0.22))        # jaw ring
	var spine_mat := _make_accent_mat(Color(0.22, 0.20, 0.18))      # spines

	var shader_mat := _make_shader_mat(
		Vector3(0.28, 0.25, 0.22),
		Vector3(0.95, 0.18, 0.12),
		0.45
	)

	# -- Body segments (6 spheres, decreasing in size) --
	var seg_sizes := [0.30, 0.34, 0.32, 0.28, 0.22, 0.16]
	var seg_z := 0.0
	for i in range(seg_sizes.size()):
		var r: float = seg_sizes[i]
		var seg := _sphere(r)
		seg.name = "Segment_%d" % i
		seg.scale = Vector3(1.0, 0.85, 1.15)  # slightly elongated along Z
		seg.position = Vector3(0.0, 0.35 + r * 0.3, seg_z)
		seg.material_override = shader_mat if i < 4 else body_mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(seg)
		seg_z -= r * 1.6

	# -- Drill-head (tapered cylinder at front) --
	var drill := _cylinder(0.30, 0.10)
	drill.name = "DrillHead"
	drill.rotation_degrees.x = 90.0
	drill.position = Vector3(0.0, 0.38, 0.42)
	drill.scale = Vector3(1.0, 1.0, 0.6)  # taper by squishing
	drill.material_override = dark_mat
	drill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(drill)

	# -- Drill tip (smaller cylinder) --
	var tip := _cylinder(0.15, 0.04)
	tip.name = "DrillTip"
	tip.rotation_degrees.x = 90.0
	tip.position = Vector3(0.0, 0.36, 0.60)
	tip.material_override = spine_mat
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(tip)

	# -- Jaw ring (TorusMesh) --
	var jaw := _torus(0.22, 0.035)
	jaw.name = "JawRing"
	jaw.position = Vector3(0.0, 0.35, 0.35)
	jaw.rotation_degrees.x = 90.0
	jaw.material_override = jaw_mat
	jaw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(jaw)

	# -- Sensory nubs around head (6 small spheres in a ring) --
	for i in range(6):
		var angle := i * TAU / 6.0
		var nub := _sphere(0.035)
		nub.name = "SensoryNub_%d" % i
		nub.position = Vector3(
			cos(angle) * 0.20,
			0.38 + sin(angle) * 0.08,
			0.30
		)
		nub.material_override = nub_mat
		nub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(nub)

	# -- Dorsal spines (6 thin angled cylinders along the back) --
	seg_z = 0.0
	for i in range(6):
		var r: float = seg_sizes[i] if i < seg_sizes.size() else 0.14
		var spine := _cylinder(0.16 - i * 0.012, 0.015)
		spine.name = "Spine_%d" % i
		spine.position = Vector3(0.0, 0.35 + r * 0.3 + r * 0.7, seg_z)
		spine.rotation_degrees.x = -35.0
		spine.rotation_degrees.z = (i % 2) * 10.0 - 5.0  # slight alternating lean
		spine.material_override = spine_mat
		spine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(spine)
		seg_z -= r * 1.6

	# -- Lateral ridges (small boxes along sides of first 3 segments) --
	seg_z = 0.0
	for i in range(3):
		var r: float = seg_sizes[i]
		for side in [-1.0, 1.0]:
			var ridge := _box(Vector3(0.04, 0.025, 0.10))
			ridge.name = "Ridge_%d_%s" % [i, "R" if side > 0 else "L"]
			ridge.position = Vector3(side * (r * 0.9), 0.30, seg_z)
			ridge.material_override = dark_mat
			ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(ridge)
		seg_z -= r * 1.6

	return root


# =====================================================================
#  UTILITY  --  Hurt flash and death dissolve (work on any model root)
# =====================================================================

static func apply_hurt_flash(model: Node3D) -> void:
	## Temporarily tints all mesh materials red for 0.2 seconds.
	if not model or not is_instance_valid(model):
		return

	var meshes: Array[MeshInstance3D] = []
	for child in model.get_children():
		if child is MeshInstance3D:
			meshes.append(child as MeshInstance3D)

	# Flash ON: set shader hurt_flash or swap to red tint
	for mi in meshes:
		var mat := mi.material_override
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("hurt_flash", 1.0)
		elif mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.emission_enabled = true
			sm.emission = Color(1.0, 0.2, 0.1)
			sm.emission_energy_multiplier = 2.0

	# Flash OFF after 0.2 s
	if model.is_inside_tree():
		model.get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if not is_instance_valid(model):
				return
			for mi in meshes:
				if not is_instance_valid(mi):
					continue
				var mat := mi.material_override
				if mat is ShaderMaterial:
					(mat as ShaderMaterial).set_shader_parameter("hurt_flash", 0.0)
				elif mat is StandardMaterial3D:
					(mat as StandardMaterial3D).emission_enabled = false
		)


static func apply_death_dissolve(model: Node3D) -> void:
	## Fades out all meshes over ~1 second using a tween.
	## For ShaderMaterial meshes, drives the "dissolve" uniform 0->1.
	## For StandardMaterial3D, fades albedo alpha and shrinks scale.
	if not model or not is_instance_valid(model):
		return
	if not model.is_inside_tree():
		return

	var shader_mats: Array[ShaderMaterial] = []
	var std_mats: Array[StandardMaterial3D] = []

	for child in model.get_children():
		if child is MeshInstance3D:
			var mat = (child as MeshInstance3D).material_override
			if mat is ShaderMaterial and not shader_mats.has(mat):
				shader_mats.append(mat as ShaderMaterial)
			elif mat is StandardMaterial3D and not std_mats.has(mat):
				std_mats.append(mat as StandardMaterial3D)

	var tween := model.create_tween()
	tween.set_parallel(true)

	# Drive shader dissolve uniform
	for smat in shader_mats:
		tween.tween_method(func(v: float) -> void:
			if is_instance_valid(smat):
				smat.set_shader_parameter("dissolve", v)
		, 0.0, 1.0, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Fade standard materials
	for sm in std_mats:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_method(func(v: float) -> void:
			if is_instance_valid(sm):
				var c := sm.albedo_color
				sm.albedo_color = Color(c.r, c.g, c.b, 1.0 - v)
		, 0.0, 1.0, 1.0)

	# Shrink the whole model as well
	tween.set_parallel(false)
	tween.tween_property(model, "scale", Vector3(0.01, 0.01, 0.01), 0.3)


# =====================================================================
#  INTERNAL HELPERS  --  Mesh & material constructors
# =====================================================================

static func _capsule(height: float, radius: float) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.height = height
	m.radius = radius
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


static func _sphere(radius: float) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


static func _cylinder(height: float, radius: float) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.height = height
	m.top_radius = radius
	m.bottom_radius = radius
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


static func _box(size: Vector3) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


static func _torus(inner_radius: float, outer_radius: float) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner_radius
	m.outer_radius = inner_radius + outer_radius
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


static func _make_body_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mat.metallic = 0.05
	return mat


static func _make_accent_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.60
	mat.metallic = 0.15
	return mat


static func _make_emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.3
	mat.metallic = 0.2
	return mat


static func _make_translucent_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic = 0.0
	return mat


static func _make_shader_mat(base: Vector3, glow: Vector3, intensity: float) -> ShaderMaterial:
	if not CREATURE_DETAIL_SHADER:
		# Fallback: return a simple material without the shader
		var fallback := ShaderMaterial.new()
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = CREATURE_DETAIL_SHADER
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("glow_color", glow)
	mat.set_shader_parameter("glow_intensity", intensity)
	mat.set_shader_parameter("hurt_flash", 0.0)
	mat.set_shader_parameter("dissolve", 0.0)
	return mat
