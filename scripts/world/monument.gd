extends Node3D
## QING Mausoleum — a massive walk-in structure inspired by Chinese Qing dynasty tombs.
## Each territory gets a unique mausoleum with seed-determined style, proportions, and colors.
## The front hall leads to a back room (inner sanctum) where the energy tesseract awaits.

signal player_entered_range
signal player_exited_range

const MONUMENT_SHADER = preload("res://assets/shaders/monument.gdshader")
const BEACON_SHADER = preload("res://assets/shaders/monument_beacon.gdshader")
const CIRCLE_SHADER = preload("res://assets/shaders/monument_circle.gdshader")
const TESSERACT_SHADER = preload("res://assets/shaders/tesseract.gdshader")

const INTERACTION_RADIUS: float = 15.0
const BEACON_HEIGHT: float = 100.0
const CIRCLE_GROUND_SIZE: float = 70.0

var _params: Dictionary = {}
var _wall_material: ShaderMaterial
var _pillar_material: ShaderMaterial
var _beacon_material: ShaderMaterial
var _circle_material: ShaderMaterial
var _tesseract_material: ShaderMaterial
var _floor_material: ShaderMaterial

# Tesseract animation state
var _tesseract_mesh: ImmediateMesh
var _tesseract_instance: MeshInstance3D
var _tesseract_light: OmniLight3D
var _outer_angle: float = 0.0
var _inner_angle: float = 0.0
var _tesseract_base_y: float = 0.0

var _glow_light: OmniLight3D
var _player_in_range: bool = false


var _entrance_light: SpotLight3D
var _tesseract_particles: GPUParticles3D

func initialize(seed_value: int) -> void:
	## Build the entire mausoleum from a seed value.
	_params = MonumentGenerator.get_monument_params(seed_value)

	_create_materials()
	_build_platform()
	_build_walls()
	_build_back_room()
	_build_roof()
	_build_pillars()
	_build_entrance_gate()
	_build_guardians()
	_build_spirit_way()
	_build_tesseract()
	_build_tesseract_particles()
	_build_entrance_light()
	_build_beacon()
	_build_ground_circle()
	_build_glow_light()
	_build_interaction_area()


func update_territory_state() -> void:
	## Update visual intensity from current territory state.
	var power := clampf(float(GameManager.territory_charge) / 1e12, 0.0, 1.0)
	var bar_sum: int = GameManager.territory_hypobar + GameManager.territory_epibar
	var activity := clampf(float(bar_sum) / 1e12, 0.0, 1.0)

	var scalars: Dictionary = GameManager.faung_scalars
	var tint_r := clampf(float(scalars.get("phi", 0)) / 1e15, 0.0, 0.3)
	var tint_g := clampf(float(scalars.get("eta", 0)) / 1e15, 0.0, 0.3)
	var tint_b := clampf(float(scalars.get("mu", 0)) / 1e15, 0.0, 0.3)
	var tint := Vector3(tint_r, tint_g, tint_b)

	for mat in [_wall_material, _pillar_material, _floor_material]:
		if mat:
			mat.set_shader_parameter("territory_power", power)
			mat.set_shader_parameter("territory_activity", activity)
			mat.set_shader_parameter("power_tint", tint)

	if _tesseract_material:
		_tesseract_material.set_shader_parameter("territory_power", power)

	if _beacon_material:
		_beacon_material.set_shader_parameter("territory_power", power)

	if _circle_material:
		_circle_material.set_shader_parameter("territory_power", power)

	if _glow_light:
		_glow_light.light_energy = _params.get("glow_energy", 2.0) * (0.3 + power * 0.7)

	if _tesseract_light:
		_tesseract_light.light_energy = (1.0 + power * 3.0)

	if _entrance_light:
		_entrance_light.light_energy = 1.0 + power * 1.5

	if _tesseract_particles and is_instance_valid(_tesseract_particles):
		_tesseract_particles.amount = int(20.0 + power * 40.0)
		_tesseract_particles.speed_scale = 0.5 + activity * 1.0


func _process(delta: float) -> void:
	if _params.is_empty():
		return

	# Animate tesseract
	var speed: float = _params.get("tesseract_speed", 0.5)
	_outer_angle += speed * delta
	_inner_angle -= speed * 1.3 * delta

	if _tesseract_mesh:
		_rebuild_tesseract_mesh()

	# Bob tesseract
	if _tesseract_instance:
		var bob := sin(Time.get_ticks_msec() * 0.001 * 0.8) * 0.5
		_tesseract_instance.position.y = _tesseract_base_y + bob

	# Pulse glow light
	if _glow_light:
		var pulse := sin(Time.get_ticks_msec() * 0.001 * 1.2) * 0.15 + 0.85
		_glow_light.light_energy = _params.get("glow_energy", 2.0) * pulse

	# Pulse tesseract light
	if _tesseract_light:
		var pulse := sin(Time.get_ticks_msec() * 0.001 * 1.8) * 0.3 + 0.7
		_tesseract_light.light_energy = 2.0 * pulse


# ─── Material Setup ────────────────────────────────────────────────────

func _create_materials() -> void:
	var accent: Color = _params.get("accent_color", Color.CYAN)
	var accent_dark: Color = _params.get("accent_color_dark", Color(0.3, 0.15, 0.15))

	# Pillar material (bright accent)
	_pillar_material = ShaderMaterial.new()
	_pillar_material.shader = MONUMENT_SHADER
	_pillar_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))
	_pillar_material.set_shader_parameter("glow_intensity", 1.0)
	_pillar_material.set_shader_parameter("wall_darken", 0.0)

	# Wall material (darker, more muted)
	_wall_material = ShaderMaterial.new()
	_wall_material.shader = MONUMENT_SHADER
	_wall_material.set_shader_parameter("accent_color", Vector3(accent_dark.r, accent_dark.g, accent_dark.b))
	_wall_material.set_shader_parameter("glow_intensity", 0.6)
	_wall_material.set_shader_parameter("wall_darken", 0.6)

	# Floor material (very dark, minimal glow)
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = MONUMENT_SHADER
	_floor_material.set_shader_parameter("accent_color", Vector3(accent_dark.r * 0.5, accent_dark.g * 0.5, accent_dark.b * 0.5))
	_floor_material.set_shader_parameter("glow_intensity", 0.2)
	_floor_material.set_shader_parameter("wall_darken", 0.9)

	# Beacon material
	_beacon_material = ShaderMaterial.new()
	_beacon_material.shader = BEACON_SHADER
	_beacon_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))

	# Ground circle material
	_circle_material = ShaderMaterial.new()
	_circle_material.shader = CIRCLE_SHADER
	_circle_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))

	# Tesseract material
	_tesseract_material = ShaderMaterial.new()
	_tesseract_material.shader = TESSERACT_SHADER
	_tesseract_material.set_shader_parameter("accent_color", Vector3(accent.r, accent.g, accent.b))


# ─── Platform ──────────────────────────────────────────────────────────

func _build_platform() -> void:
	## Stepped rectangular platform with collision floor the player walks on.
	var steps: int = _params.get("platform_steps", 3)
	var step_h: float = _params.get("platform_step_height", 2.0)
	var cw: float = _params.get("chamber_width", 50.0)
	var cd: float = _params.get("chamber_depth", 35.0)
	var wt: float = _params.get("wall_thickness", 4.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	var total_depth: float = cd + brd  # Platform spans main hall + back room

	# Collision body for all platform surfaces
	var platform_body := StaticBody3D.new()
	platform_body.name = "PlatformCollision"

	for i in steps:
		var overhang: float = (steps - i) * 3.0
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "Platform_%d" % i

		var box := BoxMesh.new()
		box.size = Vector3(cw + wt * 2.0 + overhang, step_h, total_depth + wt + overhang)
		mesh_inst.mesh = box
		mesh_inst.material_override = _wall_material
		mesh_inst.position.y = step_h * 0.5 + step_h * i
		# Center platform under the full structure (main hall + back room)
		mesh_inst.position.z = -(total_depth * 0.5) + wt * 0.5

		add_child(mesh_inst)

		# Add collision for each step
		_add_box_collision(platform_body,
			mesh_inst.position,
			box.size)

	# Floor surface at top of platform — this is what the player walks on
	var top_y: float = _platform_top_y()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "FloorSurface"
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(cw, 0.5, total_depth)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = _floor_material
	floor_mesh.position = Vector3(0.0, top_y + 0.25, -(total_depth * 0.5))
	add_child(floor_mesh)

	# Floor collision (the walkable top surface)
	_add_box_collision(platform_body,
		Vector3(0.0, top_y + 0.25, -(total_depth * 0.5)),
		Vector3(cw, 0.5, total_depth))

	add_child(platform_body)


func _platform_top_y() -> float:
	var steps: int = _params.get("platform_steps", 3)
	var step_h: float = _params.get("platform_step_height", 2.0)
	return steps * step_h


# ─── Walls (Main Hall) ────────────────────────────────────────────────

func _build_walls() -> void:
	## Walls for the main hall — left, right, and a dividing back wall
	## with a doorway leading to the back room.
	## Entrance faces +Z (toward player spawn at z=0).
	var cw: float = _params.get("chamber_width", 50.0)
	var cd: float = _params.get("chamber_depth", 35.0)
	var wh: float = _params.get("wall_height", 30.0)
	var wt: float = _params.get("wall_thickness", 4.0)
	var base_y: float = _platform_top_y()
	var brew: float = _params.get("back_room_entrance_width", 6.0)

	# Collision body for main hall walls
	var wall_body := StaticBody3D.new()
	wall_body.name = "WallCollision"

	# Left wall (west, -X side) — spans full depth (main hall + back room)
	var brd: float = _params.get("back_room_depth", 18.0)
	var full_depth: float = cd + brd
	var left := _make_wall_mesh(Vector3(wt, wh, full_depth))
	left.name = "WallLeft"
	left.position = Vector3(-(cw * 0.5 + wt * 0.5), base_y + wh * 0.5, -(full_depth * 0.5))
	add_child(left)
	_add_box_collision(wall_body, left.position, Vector3(wt, wh, full_depth))

	# Right wall (east, +X side) — same
	var right := _make_wall_mesh(Vector3(wt, wh, full_depth))
	right.name = "WallRight"
	right.position = Vector3(cw * 0.5 + wt * 0.5, base_y + wh * 0.5, -(full_depth * 0.5))
	add_child(right)
	_add_box_collision(wall_body, right.position, Vector3(wt, wh, full_depth))

	# Dividing wall between main hall and back room — two sections flanking the doorway
	var divider_z: float = -cd
	var divider_section_width: float = (cw - brew) * 0.5
	if divider_section_width > 1.0:
		for side in [-1.0, 1.0]:
			var div := _make_wall_mesh(Vector3(divider_section_width, wh, wt))
			div.name = "Divider_%s" % ("L" if side < 0 else "R")
			div.position = Vector3(
				side * (brew * 0.5 + divider_section_width * 0.5),
				base_y + wh * 0.5,
				divider_z
			)
			add_child(div)
			_add_box_collision(wall_body, div.position, Vector3(divider_section_width, wh, wt))

	# Lintel over divider doorway
	var div_lintel := MeshInstance3D.new()
	div_lintel.name = "DividerLintel"
	var dl_box := BoxMesh.new()
	dl_box.size = Vector3(brew + 2.0, wt * 0.5, wt)
	div_lintel.mesh = dl_box
	div_lintel.material_override = _pillar_material
	div_lintel.position = Vector3(0.0, base_y + wh - wt * 0.25, divider_z)
	add_child(div_lintel)

	add_child(wall_body)


# ─── Back Room ─────────────────────────────────────────────────────────

func _build_back_room() -> void:
	## Inner sanctum behind the main hall — the tesseract hides here.
	## Only a back wall needed (side walls are shared with main hall).
	var cw: float = _params.get("chamber_width", 50.0)
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	var brw: float = _params.get("back_room_width", 25.0)
	var wh: float = _params.get("wall_height", 30.0)
	var wt: float = _params.get("wall_thickness", 4.0)
	var base_y: float = _platform_top_y()

	var back_room_body := StaticBody3D.new()
	back_room_body.name = "BackRoomCollision"

	# Back wall of the entire structure (far north, -Z end)
	var back_z: float = -(cd + brd)
	var back := _make_wall_mesh(Vector3(cw + wt * 2.0, wh, wt))
	back.name = "WallBack"
	back.position = Vector3(0.0, base_y + wh * 0.5, back_z)
	add_child(back)
	_add_box_collision(back_room_body, back.position, Vector3(cw + wt * 2.0, wh, wt))

	# Inner side walls to narrow the back room (if back room is narrower than main hall)
	if brw < cw - 2.0:
		var inner_wall_depth: float = brd
		var inner_wall_x_offset: float = (brw * 0.5 + wt * 0.5)
		var inner_wall_z: float = -(cd + brd * 0.5)

		for side in [-1.0, 1.0]:
			var inner := _make_wall_mesh(Vector3(wt, wh, inner_wall_depth))
			inner.name = "BackRoomInner_%s" % ("L" if side < 0 else "R")
			inner.position = Vector3(side * inner_wall_x_offset, base_y + wh * 0.5, inner_wall_z)
			add_child(inner)
			_add_box_collision(back_room_body, inner.position, Vector3(wt, wh, inner_wall_depth))

	add_child(back_room_body)


func _make_wall_mesh(size: Vector3) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = _wall_material
	return mesh_inst


func _add_box_collision(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)


# ─── Roof ──────────────────────────────────────────────────────────────

func _build_roof() -> void:
	## Style-dependent roof spanning the entire structure.
	var style: int = _params.get("style", 0)
	var cw: float = _params.get("chamber_width", 50.0)
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	var wh: float = _params.get("wall_height", 30.0)
	var wt: float = _params.get("wall_thickness", 4.0)
	var rh: float = _params.get("roof_height", 15.0)
	var base_y: float = _platform_top_y() + wh
	var total_depth: float = cd + brd
	var full_w: float = cw + wt * 2.0 + 2.0  # Slight overhang

	var roof_group := Node3D.new()
	roof_group.name = "RoofGroup"
	roof_group.position.z = -(total_depth * 0.5)

	match style:
		MonumentGenerator.MausoleumStyle.IMPERIAL:
			_build_roof_imperial(roof_group, full_w, total_depth + 2.0, rh, base_y)
		MonumentGenerator.MausoleumStyle.PAGODA:
			_build_roof_pagoda(roof_group, full_w, total_depth + 2.0, rh, base_y)
		MonumentGenerator.MausoleumStyle.FORTRESS:
			_build_roof_fortress(roof_group, full_w, total_depth + 2.0, rh, base_y)
		MonumentGenerator.MausoleumStyle.SPIRIT:
			_build_roof_spirit(roof_group, full_w, total_depth + 2.0, rh, base_y)

	add_child(roof_group)

	# Roof collision — flat slab covering the entire structure top
	var roof_body := StaticBody3D.new()
	roof_body.name = "RoofCollision"
	add_child(roof_body)
	var roof_col := CollisionShape3D.new()
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(full_w, 2.0, total_depth + 2.0)
	roof_col.shape = roof_shape
	roof_col.position = Vector3(0.0, base_y + 1.0, -(total_depth * 0.5))
	roof_body.add_child(roof_col)


func _build_roof_imperial(group: Node3D, w: float, d: float, rh: float, base_y: float) -> void:
	## Hip-and-gable: flat base + prism peak.
	var slab := MeshInstance3D.new()
	slab.name = "RoofSlab"
	var box := BoxMesh.new()
	box.size = Vector3(w, 1.0, d)
	slab.mesh = box
	slab.material_override = _pillar_material
	slab.position.y = base_y + 0.5
	group.add_child(slab)

	var peak := MeshInstance3D.new()
	peak.name = "RoofPeak"
	var prism := PrismMesh.new()
	prism.size = Vector3(w * 0.9, rh, d * 0.8)
	peak.mesh = prism
	peak.material_override = _pillar_material
	peak.position.y = base_y + 1.0 + rh * 0.5
	group.add_child(peak)


func _build_roof_pagoda(group: Node3D, w: float, d: float, rh: float, base_y: float) -> void:
	## Multi-tier stepped: 3 layers of decreasing size.
	var tier_h: float = rh / 3.0
	for i in 3:
		var scale_f: float = 1.0 - float(i) * 0.2
		var tier := MeshInstance3D.new()
		tier.name = "RoofTier_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(w * scale_f + 2.0, tier_h * 0.6, d * scale_f + 2.0)
		tier.mesh = box
		tier.material_override = _pillar_material
		tier.position.y = base_y + 0.5 + float(i) * tier_h
		group.add_child(tier)


func _build_roof_fortress(group: Node3D, w: float, d: float, rh: float, base_y: float) -> void:
	## Flat roof with raised parapet edge.
	var slab := MeshInstance3D.new()
	slab.name = "RoofSlab"
	var box := BoxMesh.new()
	box.size = Vector3(w, 1.5, d)
	slab.mesh = box
	slab.material_override = _wall_material
	slab.position.y = base_y + 0.75
	group.add_child(slab)

	# Parapet: raised edge around perimeter
	var parapet_h: float = rh * 0.4
	for side_data in [
		{"pos": Vector3(0.0, 0.0, d * 0.5), "size": Vector3(w, parapet_h, 1.0)},
		{"pos": Vector3(0.0, 0.0, -d * 0.5), "size": Vector3(w, parapet_h, 1.0)},
		{"pos": Vector3(w * 0.5, 0.0, 0.0), "size": Vector3(1.0, parapet_h, d)},
		{"pos": Vector3(-w * 0.5, 0.0, 0.0), "size": Vector3(1.0, parapet_h, d)},
	]:
		var p := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = side_data.size
		p.mesh = pbox
		p.material_override = _pillar_material
		p.position = side_data.pos
		p.position.y = base_y + 1.5 + parapet_h * 0.5
		group.add_child(p)


func _build_roof_spirit(group: Node3D, w: float, d: float, rh: float, base_y: float) -> void:
	## Sweeping curved roof: two angled prisms creating wing-like effect.
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.name = "RoofWing_%s" % ("L" if side < 0 else "R")
		var prism := PrismMesh.new()
		prism.size = Vector3(w * 0.5, rh * 0.8, d * 0.9)
		wing.mesh = prism
		wing.material_override = _pillar_material
		wing.position = Vector3(side * w * 0.25, base_y + rh * 0.4, 0.0)
		wing.rotation_degrees.z = side * 10.0  # Slight angle outward
		group.add_child(wing)


# ─── Pillars ───────────────────────────────────────────────────────────

func _build_pillars() -> void:
	## Large cylinder columns at chamber corners, along walls, and flanking entrances.
	var cw: float = _params.get("chamber_width", 50.0)
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	var wh: float = _params.get("wall_height", 30.0)
	var pr: float = _params.get("pillar_radius", 1.5)
	var base_y: float = _platform_top_y()

	# Front corners
	var positions: Array[Vector3] = [
		Vector3(-cw * 0.5, 0.0, 0.0),      # Front-left
		Vector3(cw * 0.5, 0.0, 0.0),       # Front-right
	]

	# Back corners (full structure back)
	positions.append(Vector3(-cw * 0.5, 0.0, -(cd + brd)))
	positions.append(Vector3(cw * 0.5, 0.0, -(cd + brd)))

	# Divider wall corners (where main hall meets back room)
	positions.append(Vector3(-cw * 0.5, 0.0, -cd))
	positions.append(Vector3(cw * 0.5, 0.0, -cd))

	# Interior pillars along main hall (2 rows flanking center)
	var interior_inset: float = cw * 0.3
	var hall_pillar_count: int = 3
	for i in hall_pillar_count:
		var z_pos: float = -cd * (float(i + 1) / float(hall_pillar_count + 1))
		positions.append(Vector3(-interior_inset, 0.0, z_pos))
		positions.append(Vector3(interior_inset, 0.0, z_pos))

	# StaticBody for all pillar collisions
	var pillar_body := StaticBody3D.new()
	pillar_body.name = "PillarCollision"
	add_child(pillar_body)

	for i in positions.size():
		var pillar := _make_pillar(pr, wh + 1.0)
		pillar.name = "Pillar_%d" % i
		pillar.position = positions[i]
		pillar.position.y = base_y + (wh + 1.0) * 0.5
		add_child(pillar)

		# Cylinder collision shape for this pillar
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = pr
		shape.height = wh + 1.0
		col.shape = shape
		col.position = positions[i]
		col.position.y = base_y + (wh + 1.0) * 0.5
		pillar_body.add_child(col)


func _make_pillar(radius: float, height: float) -> MeshInstance3D:
	## Create a fluted column with vertical grooves — classical architectural style.
	## Uses SurfaceTool to generate a cylinder with sinusoidal radius modulation.
	var mesh_inst := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var flute_count: int = 16  # Number of flutes (vertical grooves)
	var segments: int = flute_count * 2  # Need 2x for groove peaks and valleys
	var rings: int = 12
	var flute_depth: float = radius * 0.12  # Depth of the grooves

	for ring in range(rings + 1):
		var v: float = float(ring) / float(rings)
		var y: float = (v - 0.5) * height
		# Slight taper: bottom is wider than top
		var ring_radius: float = radius * (1.0 - v * 0.15)

		for seg in range(segments + 1):
			var u: float = float(seg) / float(segments)
			var angle: float = u * TAU

			# Fluted radius modulation: sinusoidal grooves
			var flute_mod: float = cos(angle * float(flute_count)) * flute_depth
			var r: float = ring_radius + flute_mod

			var px: float = cos(angle) * r
			var pz: float = sin(angle) * r

			# Normal: radial + flute perturbation
			var nr: float = cos(angle)
			var nz_val: float = sin(angle)
			# Flute normal perturbation (tangential)
			var flute_normal_mod: float = -sin(angle * float(flute_count)) * flute_depth * float(flute_count) / ring_radius
			var nx: float = nr - flute_normal_mod * (-nz_val)
			var ny: float = 0.0
			var nz: float = nz_val - flute_normal_mod * nr
			var normal := Vector3(nx, ny, nz).normalized()

			st.set_normal(normal)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(px, y, pz))

	# Generate triangle indices
	for ring in range(rings):
		for seg in range(segments):
			var current: int = ring * (segments + 1) + seg
			var next: int = current + segments + 1

			st.add_index(current)
			st.add_index(next)
			st.add_index(current + 1)

			st.add_index(current + 1)
			st.add_index(next)
			st.add_index(next + 1)

	# Capital (top): wider decorative disc
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = radius * 1.1
	cap_mesh.bottom_radius = radius * 1.2
	cap_mesh.height = height * 0.04
	cap_mesh.radial_segments = flute_count

	# Base (bottom): wider decorative disc
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = radius * 1.2
	base_mesh.bottom_radius = radius * 1.3
	base_mesh.height = height * 0.05
	base_mesh.radial_segments = flute_count

	st.generate_tangents()
	var column_mesh := st.commit()

	mesh_inst.mesh = column_mesh
	mesh_inst.material_override = _pillar_material

	# Add capital at top
	var cap_inst := MeshInstance3D.new()
	cap_inst.name = "Capital"
	cap_inst.mesh = cap_mesh
	cap_inst.material_override = _pillar_material
	cap_inst.position.y = height * 0.5 - height * 0.02
	mesh_inst.add_child(cap_inst)

	# Add base at bottom
	var base_inst := MeshInstance3D.new()
	base_inst.name = "Base"
	base_inst.mesh = base_mesh
	base_inst.material_override = _pillar_material
	base_inst.position.y = -height * 0.5 + height * 0.025
	mesh_inst.add_child(base_inst)

	return mesh_inst


# ─── Entrance Gate ─────────────────────────────────────────────────────

func _build_entrance_gate() -> void:
	## Lintel beam spanning the doorway between front pillars.
	var cw: float = _params.get("chamber_width", 50.0)
	var ew: float = _params.get("entrance_width", 15.0)
	var wh: float = _params.get("wall_height", 30.0)
	var wt: float = _params.get("wall_thickness", 4.0)
	var base_y: float = _platform_top_y()

	var lintel := MeshInstance3D.new()
	lintel.name = "Lintel"
	var box := BoxMesh.new()
	box.size = Vector3(ew + 4.0, 2.0, wt)
	lintel.mesh = box
	lintel.material_override = _pillar_material
	lintel.position = Vector3(0.0, base_y + wh - 1.0, 0.0)
	add_child(lintel)

	# Entrance collision body for side panels
	var entrance_body := StaticBody3D.new()
	entrance_body.name = "EntranceCollision"

	# Side panels flanking the entrance (partial walls on either side of doorway)
	var side_width: float = (cw - ew) * 0.5
	if side_width > 1.0:
		for side in [-1.0, 1.0]:
			var panel := _make_wall_mesh(Vector3(side_width, wh, wt))
			panel.name = "EntrancePanel_%s" % ("L" if side < 0 else "R")
			panel.position = Vector3(
				side * (ew * 0.5 + side_width * 0.5),
				base_y + wh * 0.5,
				0.0
			)
			add_child(panel)
			_add_box_collision(entrance_body, panel.position, Vector3(side_width, wh, wt))

	add_child(entrance_body)


# ─── Guardians ─────────────────────────────────────────────────────────

func _build_guardians() -> void:
	## Two guardian statues flanking the entrance path — scaled up.
	var gt: int = _params.get("guardian_type", 0)
	var base_y: float = _platform_top_y()

	for side in [-1.0, 1.0]:
		var guardian := Node3D.new()
		guardian.name = "Guardian_%s" % ("L" if side < 0 else "R")
		guardian.position = Vector3(side * 15.0, 0.0, 18.0)  # In front of entrance

		match gt:
			MonumentGenerator.GuardianType.PILLAR:
				_build_guardian_pillar(guardian)
			MonumentGenerator.GuardianType.OBELISK:
				_build_guardian_obelisk(guardian)
			MonumentGenerator.GuardianType.LANTERN:
				_build_guardian_lantern(guardian)
			MonumentGenerator.GuardianType.STELE:
				_build_guardian_stele(guardian)

		add_child(guardian)


func _build_guardian_pillar(parent: Node3D) -> void:
	# Fluted guardian pillar with ornate capital
	var pillar := _make_pillar(1.2, 12.0)
	pillar.position.y = 6.0
	parent.add_child(pillar)
	# Ornate cap: sphere + ring
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.5
	sphere.height = 3.0
	cap.mesh = sphere
	cap.material_override = _pillar_material
	cap.position.y = 13.0
	parent.add_child(cap)
	# Decorative ring at junction
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.3
	torus.outer_radius = 1.8
	ring.mesh = torus
	ring.material_override = _pillar_material
	ring.position.y = 11.5
	parent.add_child(ring)


func _build_guardian_obelisk(parent: Node3D) -> void:
	# Tapered obelisk with hieroglyphic base band
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 1.5
	cyl.height = 14.0
	cyl.radial_segments = 4
	mesh_inst.mesh = cyl
	mesh_inst.material_override = _pillar_material
	mesh_inst.position.y = 7.0
	parent.add_child(mesh_inst)
	# Pyramidion cap
	var cap := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(1.2, 2.0, 1.2)
	cap.mesh = prism
	cap.material_override = _pillar_material
	cap.position.y = 15.0
	parent.add_child(cap)
	# Base plinth
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 1.5, 2.5)
	base.mesh = box
	base.material_override = _wall_material
	base.position.y = 0.75
	parent.add_child(base)


func _build_guardian_lantern(parent: Node3D) -> void:
	# Hexagonal base pedestal
	var base := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = 1.2
	base_cyl.bottom_radius = 1.8
	base_cyl.height = 6.0
	base_cyl.radial_segments = 6
	base.mesh = base_cyl
	base.material_override = _wall_material
	base.position.y = 3.0
	parent.add_child(base)
	# Lantern housing — open-frame structure
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.5, 3.5, 2.5)
	body.mesh = box
	body.material_override = _pillar_material
	body.position.y = 8.0
	parent.add_child(body)
	# Inner glow sphere (emissive core)
	var glow := MeshInstance3D.new()
	var glow_sphere := SphereMesh.new()
	glow_sphere.radius = 0.9
	glow_sphere.height = 1.8
	glow.mesh = glow_sphere
	var glow_mat := StandardMaterial3D.new()
	var accent: Color = _params.get("accent_color", Color.CYAN)
	glow_mat.albedo_color = accent * 0.5
	glow_mat.emission_enabled = true
	glow_mat.emission = accent
	glow_mat.emission_energy_multiplier = 2.5
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = glow_mat
	glow.position.y = 8.0
	parent.add_child(glow)
	# Roof cap
	var top := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(3.0, 2.0, 3.0)
	top.mesh = prism
	top.material_override = _pillar_material
	top.position.y = 11.0
	parent.add_child(top)
	# OmniLight at lantern
	var lantern_light := OmniLight3D.new()
	lantern_light.light_color = accent
	lantern_light.light_energy = 1.5
	lantern_light.omni_range = 12.0
	lantern_light.shadow_enabled = false
	lantern_light.position.y = 8.0
	parent.add_child(lantern_light)


func _build_guardian_stele(parent: Node3D) -> void:
	## Stone tablet with base plinth and crown.
	# Base plinth
	var plinth := MeshInstance3D.new()
	var plinth_box := BoxMesh.new()
	plinth_box.size = Vector3(4.5, 2.0, 1.8)
	plinth.mesh = plinth_box
	plinth.material_override = _wall_material
	plinth.position.y = 1.0
	parent.add_child(plinth)
	# Main tablet
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.5, 10.0, 1.0)
	mesh_inst.mesh = box
	mesh_inst.material_override = _pillar_material
	mesh_inst.position.y = 7.0
	parent.add_child(mesh_inst)
	# Crown: rounded top
	var crown := MeshInstance3D.new()
	var crown_sphere := SphereMesh.new()
	crown_sphere.radius = 2.0
	crown_sphere.height = 2.5
	crown_sphere.radial_segments = 8
	crown_sphere.rings = 4
	crown.mesh = crown_sphere
	crown.material_override = _pillar_material
	crown.position.y = 12.5
	crown.scale = Vector3(0.9, 0.6, 0.5)
	parent.add_child(crown)


# ─── Spirit Way ────────────────────────────────────────────────────────

func _build_spirit_way() -> void:
	## Large pillars lining the approach path toward the entrance.
	var count: int = _params.get("spirit_way_count", 4)

	for i in count:
		var z_pos: float = 25.0 + float(i) * 10.0  # Start 25m in front, spaced 10m apart
		for side in [-1.0, 1.0]:
			var pillar := _make_pillar(0.6, 6.0)
			pillar.name = "SpiritWay_%d_%s" % [i, "L" if side < 0 else "R"]
			pillar.position = Vector3(side * 10.0, 3.0, z_pos)
			add_child(pillar)


# ─── Tesseract ─────────────────────────────────────────────────────────

func _build_tesseract() -> void:
	## Energy tesseract: rotating wireframe hypercube hidden in the back room.
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	var wh: float = _params.get("wall_height", 30.0)
	var base_y: float = _platform_top_y()

	_tesseract_mesh = ImmediateMesh.new()
	_tesseract_instance = MeshInstance3D.new()
	_tesseract_instance.name = "Tesseract"
	_tesseract_instance.mesh = _tesseract_mesh
	_tesseract_instance.material_override = _tesseract_material
	_tesseract_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Position tesseract in center of back room
	var back_room_center_z: float = -(cd + brd * 0.5)
	_tesseract_base_y = base_y + wh * 0.4
	_tesseract_instance.position = Vector3(0.0, _tesseract_base_y, back_room_center_z)

	add_child(_tesseract_instance)

	# Tesseract light — bright accent filling the back room
	_tesseract_light = OmniLight3D.new()
	_tesseract_light.name = "TesseractLight"
	var accent: Color = _params.get("accent_color", Color.CYAN)
	_tesseract_light.light_color = accent
	_tesseract_light.light_energy = 3.0
	_tesseract_light.omni_range = 40.0
	_tesseract_light.omni_attenuation = 1.2
	_tesseract_light.shadow_enabled = false
	_tesseract_light.position = _tesseract_instance.position
	add_child(_tesseract_light)

	# Initial build
	_rebuild_tesseract_mesh()


func _rebuild_tesseract_mesh() -> void:
	## Reconstruct tesseract wireframe geometry each frame.
	var size: float = _params.get("tesseract_size", 6.0)
	var outer_half: float = size * 0.8  # Outer cube half-edge
	var inner_half: float = size * 0.5  # Inner cube half-edge

	# Compute rotated vertices
	var outer_verts: Array[Vector3] = _cube_vertices(outer_half, _outer_angle, 0.0)
	var inner_verts: Array[Vector3] = _cube_vertices(inner_half, _inner_angle, _inner_angle * 0.3)

	# Cube edge indices (12 edges)
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),  # Back face
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),  # Front face
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),  # Connecting
	]

	_tesseract_mesh.clear_surfaces()
	_tesseract_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Outer cube edges
	for edge in edges:
		_tesseract_mesh.surface_add_vertex(outer_verts[edge.x])
		_tesseract_mesh.surface_add_vertex(outer_verts[edge.y])

	# Inner cube edges
	for edge in edges:
		_tesseract_mesh.surface_add_vertex(inner_verts[edge.x])
		_tesseract_mesh.surface_add_vertex(inner_verts[edge.y])

	# Connector lines (inner↔outer vertices)
	for i in 8:
		_tesseract_mesh.surface_add_vertex(outer_verts[i])
		_tesseract_mesh.surface_add_vertex(inner_verts[i])

	_tesseract_mesh.surface_end()


func _cube_vertices(half: float, y_angle: float, x_angle: float) -> Array[Vector3]:
	## Returns 8 vertices of a cube rotated by y_angle and x_angle.
	var base: Array[Vector3] = [
		Vector3(-half, -half, -half),
		Vector3( half, -half, -half),
		Vector3( half,  half, -half),
		Vector3(-half,  half, -half),
		Vector3(-half, -half,  half),
		Vector3( half, -half,  half),
		Vector3( half,  half,  half),
		Vector3(-half,  half,  half),
	]

	var cos_y := cos(y_angle)
	var sin_y := sin(y_angle)
	var cos_x := cos(x_angle)
	var sin_x := sin(x_angle)

	var result: Array[Vector3] = []
	result.resize(8)
	for i in 8:
		var v := base[i]
		# Rotate around Y
		var rx: float = v.x * cos_y + v.z * sin_y
		var rz: float = -v.x * sin_y + v.z * cos_y
		# Rotate around X
		var ry: float = v.y * cos_x - rz * sin_x
		rz = v.y * sin_x + rz * cos_x

		result[i] = Vector3(rx, ry, rz)

	return result


# ─── Tesseract Particles ──────────────────────────────────────────

func _build_tesseract_particles() -> void:
	## Ambient energy motes floating around the tesseract — visible through the wireframe.
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	var base_y: float = _platform_top_y()
	var wh: float = _params.get("wall_height", 30.0)
	var accent: Color = _params.get("accent_color", Color.CYAN)

	_tesseract_particles = GPUParticles3D.new()
	_tesseract_particles.name = "TesseractParticles"
	_tesseract_particles.amount = 40
	_tesseract_particles.lifetime = 4.0
	_tesseract_particles.explosiveness = 0.0
	_tesseract_particles.randomness = 0.5
	_tesseract_particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 5.0
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3(0.0, 0.2, 0.0)  # Slow upward drift
	mat.scale_min = 0.05
	mat.scale_max = 0.2
	mat.damping_min = 0.5
	mat.damping_max = 1.0

	# Color: accent with fade
	var gradient := Gradient.new()
	gradient.set_color(0, Color(accent.r, accent.g, accent.b, 0.0))
	gradient.add_point(0.2, Color(accent.r, accent.g, accent.b, 0.8))
	gradient.add_point(0.7, Color(accent.r, accent.g, accent.b, 0.5))
	gradient.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = gradient
	mat.color_ramp = color_tex
	_tesseract_particles.process_material = mat

	# Draw pass: soft-circle shader quad (no hard square edges)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	_tesseract_particles.draw_pass_1 = quad
	var tess_shader_mat := ShaderMaterial.new()
	var tess_shader := Shader.new()
	tess_shader.code = """
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
	float core = exp(-d * d * 15.0);
	ALBEDO = COLOR.rgb * (1.0 + core * 1.5);
	ALPHA = alpha * COLOR.a;
}
"""
	tess_shader_mat.shader = tess_shader
	quad.surface_set_material(0, tess_shader_mat)

	var back_room_center_z: float = -(cd + brd * 0.5)
	_tesseract_particles.position = Vector3(0.0, base_y + wh * 0.4, back_room_center_z)
	add_child(_tesseract_particles)


# ─── Entrance Light ──────────────────────────────────────────────

func _build_entrance_light() -> void:
	## SpotLight3D shining into the entrance — dramatic temple illumination.
	var accent: Color = _params.get("accent_color", Color.CYAN)
	var wh: float = _params.get("wall_height", 30.0)
	var base_y: float = _platform_top_y()

	_entrance_light = SpotLight3D.new()
	_entrance_light.name = "EntranceLight"
	# Warm accent-tinted light
	_entrance_light.light_color = accent.lerp(Color.WHITE, 0.5)
	_entrance_light.light_energy = 1.5
	_entrance_light.spot_range = wh * 1.5
	_entrance_light.spot_angle = 45.0
	_entrance_light.spot_angle_attenuation = 0.8
	_entrance_light.shadow_enabled = true
	_entrance_light.shadow_bias = 0.05

	# Position: above entrance, pointing inward and slightly down
	_entrance_light.position = Vector3(0.0, base_y + wh * 0.85, 2.0)
	_entrance_light.rotation_degrees = Vector3(-35.0, 0.0, 0.0)  # Angled into the hall

	add_child(_entrance_light)


# ─── Beacon ────────────────────────────────────────────────────────────

func _build_beacon() -> void:
	## Tall translucent vertical beam above the mausoleum.
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Beacon"

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.25
	cyl.height = BEACON_HEIGHT
	cyl.radial_segments = 6
	mesh_inst.mesh = cyl
	mesh_inst.material_override = _beacon_material

	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	mesh_inst.position = Vector3(0.0, BEACON_HEIGHT * 0.5, -(cd + brd * 0.5))
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_inst)


# ─── Ground Circle ─────────────────────────────────────────────────────

func _build_ground_circle() -> void:
	## Flat quad on the ground with procedural ring pattern.
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "GroundCircle"

	var quad := QuadMesh.new()
	quad.size = Vector2(CIRCLE_GROUND_SIZE, CIRCLE_GROUND_SIZE)
	mesh_inst.mesh = quad
	mesh_inst.material_override = _circle_material

	mesh_inst.rotation_degrees.x = -90.0
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	mesh_inst.position = Vector3(0.0, 0.05, -(cd + brd) * 0.5)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_inst)


# ─── Glow Light ────────────────────────────────────────────────────────

func _build_glow_light() -> void:
	## Accent-colored ambient light illuminating the mausoleum.
	var accent: Color = _params.get("accent_color", Color.CYAN)

	_glow_light = OmniLight3D.new()
	_glow_light.name = "GlowLight"
	_glow_light.light_color = accent
	_glow_light.light_energy = _params.get("glow_energy", 2.0)
	_glow_light.omni_range = _params.get("glow_range", 60.0)
	_glow_light.omni_attenuation = 1.5
	_glow_light.shadow_enabled = false

	var wh: float = _params.get("wall_height", 30.0)
	var cd: float = _params.get("chamber_depth", 35.0)
	_glow_light.position = Vector3(0.0, _platform_top_y() + wh * 0.7, -cd * 0.5)

	add_child(_glow_light)


# ─── Interaction Area ──────────────────────────────────────────────────

func _build_interaction_area() -> void:
	## Area3D centered on the tesseract in the back room for proximity detection.
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = 1  # Detect player (layer 1)

	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACTION_RADIUS
	col_shape.shape = sphere
	col_shape.name = "InteractionShape"

	area.add_child(col_shape)

	# Center the interaction area at the tesseract position (back room)
	var cd: float = _params.get("chamber_depth", 35.0)
	var brd: float = _params.get("back_room_depth", 18.0)
	area.position = Vector3(0.0, _platform_top_y() + 5.0, -(cd + brd * 0.5))

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = true
		player_entered_range.emit()


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = false
		player_exited_range.emit()


func is_player_in_range() -> bool:
	return _player_in_range


# ─── Static Beacon Helper ──────────────────────────────────────────────

static func create_beacon_pillar(accent_color: Color, beacon_height: float = 80.0) -> MeshInstance3D:
	## Create a standalone beacon pillar (for neighbor territories).
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "NeighborBeacon"

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.15
	cyl.height = beacon_height
	cyl.radial_segments = 6
	mesh_inst.mesh = cyl

	var mat := ShaderMaterial.new()
	mat.shader = BEACON_SHADER
	mat.set_shader_parameter("accent_color", Vector3(accent_color.r, accent_color.g, accent_color.b))
	mat.set_shader_parameter("beam_opacity", 0.04)
	mesh_inst.material_override = mat

	mesh_inst.position.y = beacon_height * 0.5
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return mesh_inst
