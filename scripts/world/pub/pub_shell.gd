class_name PubShell
extends RefCounted
## The cantina's building: plinth, container-steel walls with real window/door openings,
## brick + plank interior lining, vaulted/gable/skillion roof with exposed trusses,
## porch with awning, railings and string lights, neon signage and rooftop/yard kit.
## Also owns all the collision for the shell.

var sign_light: OmniLight3D
var porch_light: OmniLight3D
var sign_mesh: MeshInstance3D       # Personalised name (TextMesh)
var beacon: MeshInstance3D          # Blinking antenna tip
var neon_nodes: Array[MeshInstance3D] = []   # Exterior neon, flickered/flared by the building

var _root: Node3D
var _L: PubLayout
var _body: StaticBody3D
var _b: PubKit.Batch          # Shadow-casting exterior geometry
var _bi: PubKit.Batch         # Interior geometry (no shadows)
var _rng := RandomNumberGenerator.new()

var _shell: BaseMaterial3D
var _roof: BaseMaterial3D
var _plate: BaseMaterial3D
var _brick: BaseMaterial3D
var _wains: BaseMaterial3D
var _steel: StandardMaterial3D
var _dark: StandardMaterial3D
var _glass: StandardMaterial3D


func build(root: Node3D, layout: PubLayout, body: StaticBody3D) -> void:
	_root = root
	_L = layout
	_body = body
	_rng.seed = int(layout.p["detail_seed"])
	_b = PubKit.Batch.new()
	_bi = PubKit.Batch.new()
	var tint: Color = _L.p["shell_tint"]
	_shell = PubKit.pbr("container_side", 2.6, tint)
	_roof = PubKit.pbr("container_side", 2.2, tint.darkened(0.45), false)
	_roof.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plate = PubKit.pbr("metal_plate", 1.6, Color(0.8, 0.8, 0.82), true, 1.0, 0.35)
	_brick = PubKit.pbr("brick_wall_02", 2.4, Color(0.92, 0.8, 0.72))
	_wains = PubKit.pbr("dark_planks", 1.4, Color(0.8, 0.7, 0.62))
	_steel = PubKit.flat(Color(0.13, 0.13, 0.14), 0.42, 0.85)
	_dark = PubKit.flat(Color(0.05, 0.05, 0.055), 0.6, 0.5)
	_glass = PubKit.glass(Color(0.55, 0.68, 0.72, 0.16))

	_build_plinth_and_floor()
	_build_walls()
	_build_windows()
	_build_door()
	_build_roof()
	_build_porch()
	_build_signage()
	_build_rooftop()
	_build_yard()
	_b.commit(_root, true, "Shell")
	_bi.commit(_root, false, "Lining")


# ─── Plinth, floor ─────────────────────────────────────────────────────────

func _build_plinth_and_floor() -> void:
	var w := _L.w
	var d := _L.d
	var fy := PubLayout.FY
	var T := PubLayout.T
	# Foundation slab (sinks a little into the regolith so uneven ground never shows a gap)
	_b.box_at(Vector3(2.0 * (w + T) + 0.5, fy + 1.2, 2.0 * (d + T) + 0.5),
		Vector3(0, (fy - 1.2) * 0.5 - 0.01, 0), _plate)
	# Interior floor — dark planks
	var floor_mat := PubKit.pbr("dark_wooden_planks", 2.2, Color(0.95, 0.88, 0.82))
	PubKit.mesh_instance(_box_mesh(Vector3(2.0 * w, 0.04, 2.0 * d)), Vector3(0, fy - 0.019, 0), floor_mat, _root)
	# Baseboards
	for sz in [-1.0, 1.0]:
		_bi.box_at(Vector3(2.0 * w, 0.14, 0.03), Vector3(0, fy + 0.07, sz * (d - 0.035)), _dark)
	for sx in [-1.0, 1.0]:
		_bi.box_at(Vector3(0.03, 0.14, 2.0 * d), Vector3(sx * (w - 0.035), fy + 0.07, 0), _dark)

	# Collision: one slab under building + porch, and a ramp under the front steps
	var porch_end := d + T + PubLayout.PORCH_D
	_coll(Vector3(2.0 * (w + T) + 0.5, 0.8, porch_end + d + T + 0.25),
		Vector3(0, fy - 0.4, (porch_end - (d + T + 0.25)) * 0.5))
	var ramp := CollisionShape3D.new()
	var rs := BoxShape3D.new()
	var run := 0.32 * 3.0 + 0.3
	rs.size = Vector3(2.8, 0.1, sqrt(run * run + fy * fy) + 0.1)
	ramp.shape = rs
	ramp.position = Vector3(0, fy * 0.5 - 0.06, porch_end + run * 0.5)
	ramp.rotation.x = atan2(fy, run)
	_body.add_child(ramp)


# ─── Walls ─────────────────────────────────────────────────────────────────

func _build_walls() -> void:
	var w := _L.w
	var d := _L.d
	var T := PubLayout.T
	var fy := PubLayout.FY
	var eave := _L.eave
	var door := [[0.0, PubLayout.DOOR_W, -1.0, fy + PubLayout.DOOR_H]]
	var fw := _abs_openings(_L.front_windows) + door
	var lw := _abs_openings(_L.left_windows)
	var rw := _abs_openings(_L.right_windows)
	var top_l := _L.roof_y(-(w + T * 0.5)) - 0.03
	var top_r := _L.roof_y(w + T * 0.5) - 0.03
	top_l = maxf(top_l, eave - 0.1)
	top_r = maxf(top_r, eave - 0.1)

	# Exterior shell (container steel), corners overlap so there are no cracks
	_wall_run(_b, _shell, "x", d + T * 0.5, -w - T, w + T, 0.0, eave, T, fw)
	_wall_run(_b, _shell, "x", -d - T * 0.5, -w - T, w + T, 0.0, eave, T, [])
	_wall_run(_b, _shell, "z", -w - T * 0.5, -d, d, 0.0, top_l, T, lw)
	_wall_run(_b, _shell, "z", w + T * 0.5, -d, d, 0.0, top_r, T, rw)
	# Gable / vault end caps above the eave (outside skin + brick inside)
	var gp := _L.gable_poly()
	for sz in [-1.0, 1.0]:
		var cap := PubKit.cap(gp, sz * (d + T), sz, 2.6)
		var mi := PubKit.mesh_instance(cap, Vector3.ZERO, _shell, _root, true)
		mi.material_override = _shell
		var inner := PubKit.cap(gp, sz * (d - 0.02), -sz, 2.4)
		PubKit.mesh_instance(inner, Vector3.ZERO, _brick, _root)
		# Fill the wall thickness at the top edge of the cap
		_b.box_at(Vector3(2.0 * (w + T), 0.12, T + 0.04), Vector3(0, eave + 0.02, sz * (d + T * 0.5)), _dark)

	# Corner columns + plinth band + eave band (silhouette and grime lines)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var top := top_l if sx < 0.0 else top_r
			_b.box_at(Vector3(0.42, top + 0.05, 0.42), Vector3(sx * (w + T * 0.5), top * 0.5, sz * (d + T * 0.5)), _steel)
	_b.box_at(Vector3(2.0 * (w + T) + 0.06, 0.32, 0.06), Vector3(0, 0.16, d + T + 0.03), _steel)
	_b.box_at(Vector3(2.0 * (w + T) + 0.06, 0.32, 0.06), Vector3(0, 0.16, -d - T - 0.03), _steel)
	for sx in [-1.0, 1.0]:
		_b.box_at(Vector3(0.06, 0.32, 2.0 * (d + T)), Vector3(sx * (w + T + 0.03), 0.16, 0), _steel)
	_b.box_at(Vector3(2.0 * (w + T) + 0.1, 0.18, 0.1), Vector3(0, eave - 0.09, d + T + 0.05), _steel)

	# Interior lining: plank wainscot to 1.1 m, exposed brick above, chair rail
	var wy := fy + 1.1
	_wall_run(_bi, _wains, "x", -d + 0.015, -w, w, fy, wy, 0.03, [])
	_wall_run(_bi, _brick, "x", -d + 0.015, -w, w, wy, eave, 0.03, [])
	_wall_run(_bi, _wains, "x", d - 0.015, -w, w, fy, wy, 0.03, fw)
	_wall_run(_bi, _brick, "x", d - 0.015, -w, w, wy, eave, 0.03, fw)
	_wall_run(_bi, _wains, "z", -w + 0.015, -d, d, fy, wy, 0.03, lw)
	_wall_run(_bi, _brick, "z", -w + 0.015, -d, d, wy, top_l, 0.03, lw)
	_wall_run(_bi, _wains, "z", w - 0.015, -d, d, fy, wy, 0.03, rw)
	_wall_run(_bi, _brick, "z", w - 0.015, -d, d, wy, top_r, 0.03, rw)
	var rail := PubKit.pbr("wood_table_001", 1.0, Color(0.55, 0.4, 0.3))
	for sz in [-1.0, 1.0]:
		_rail_run("x", sz * (d - 0.045), -w, w, wy, fw if sz > 0.0 else [], rail)
	_rail_run("z", -w + 0.045, -d, d, wy, lw, rail)
	_rail_run("z", w - 0.045, -d, d, wy, rw, rail)

	# Collision — walls (windows are glass, so only the door is open)
	var h := eave
	_coll(Vector3(2.0 * (w + T), h, T), Vector3(0, h * 0.5, -d - T * 0.5))
	_coll(Vector3(T, h, 2.0 * d), Vector3(-w - T * 0.5, h * 0.5, 0))
	_coll(Vector3(T, h, 2.0 * d), Vector3(w + T * 0.5, h * 0.5, 0))
	var side := w + T - PubLayout.DOOR_W * 0.5
	for sx in [-1.0, 1.0]:
		_coll(Vector3(side, h, T), Vector3(sx * (PubLayout.DOOR_W * 0.5 + side * 0.5), h * 0.5, d + T * 0.5))
	_coll(Vector3(PubLayout.DOOR_W, h - fy - PubLayout.DOOR_H, T),
		Vector3(0, fy + PubLayout.DOOR_H + (h - fy - PubLayout.DOOR_H) * 0.5, d + T * 0.5))


func _abs_openings(list: Array) -> Array:
	var out := []
	for o in list:
		out.append([o[0], o[1], PubLayout.FY + o[2], PubLayout.FY + o[3]])
	return out


func _wall_run(batch: PubKit.Batch, mat: Material, axis: String, fixed: float, a0: float, a1: float,
		y0: float, y1: float, thick: float, openings: Array) -> void:
	## A straight wall from a0 to a1 along `axis`, with rectangular holes
	## ([centre, width, sill_y, top_y], absolute). Emits only the solid pieces.
	if y1 - y0 < 0.01:
		return
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p[0] < q[0])
	var cur := a0
	for o in ops:
		var o0: float = o[0] - o[1] * 0.5
		var o1: float = o[0] + o[1] * 0.5
		var sill := clampf(o[2], y0, y1)
		var top := clampf(o[3], y0, y1)
		if top - sill < 0.01:
			continue
		_wall_piece(batch, mat, axis, fixed, cur, o0, y0, y1, thick)
		_wall_piece(batch, mat, axis, fixed, o0, o1, y0, sill, thick)
		_wall_piece(batch, mat, axis, fixed, o0, o1, top, y1, thick)
		cur = o1
	_wall_piece(batch, mat, axis, fixed, cur, a1, y0, y1, thick)


func _wall_piece(batch: PubKit.Batch, mat: Material, axis: String, fixed: float, a0: float, a1: float,
		y0: float, y1: float, thick: float) -> void:
	if a1 - a0 < 0.005 or y1 - y0 < 0.005:
		return
	var mid := (a0 + a1) * 0.5
	var ym := (y0 + y1) * 0.5
	if axis == "x":
		batch.box_at(Vector3(a1 - a0, y1 - y0, thick), Vector3(mid, ym, fixed), mat)
	else:
		batch.box_at(Vector3(thick, y1 - y0, a1 - a0), Vector3(fixed, ym, mid), mat)


func _rail_run(axis: String, fixed: float, a0: float, a1: float, y: float, openings: Array, mat: Material) -> void:
	var cur := a0
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p[0] < q[0])
	for o in ops:
		if o[2] > y or o[3] < y:
			continue
		_wall_piece(_bi, mat, axis, fixed, cur, o[0] - o[1] * 0.5, y - 0.03, y + 0.04, 0.06)
		cur = o[0] + o[1] * 0.5
	_wall_piece(_bi, mat, axis, fixed, cur, a1, y - 0.03, y + 0.04, 0.06)


# ─── Windows & door ────────────────────────────────────────────────────────

func _build_windows() -> void:
	var w := _L.w
	var d := _L.d
	var T := PubLayout.T
	for o in _abs_openings(_L.front_windows):
		_window("x", d + T * 0.5, o, 1.0)
	for o in _abs_openings(_L.left_windows):
		_window("z", -w - T * 0.5, o, -1.0)
	for o in _abs_openings(_L.right_windows):
		_window("z", w + T * 0.5, o, 1.0)


func _window(axis: String, fixed: float, o: Array, out_sign: float) -> void:
	var c: float = o[0]
	var ww: float = o[1]
	var y0: float = o[2]
	var y1: float = o[3]
	var hh := y1 - y0
	var depth := PubLayout.T + 0.08
	var f := 0.09
	var pieces := [
		[Vector3(ww + 2 * f, f, depth), Vector3(0, y1 + f * 0.5, 0)],
		[Vector3(ww + 2 * f, f, depth), Vector3(0, y0 - f * 0.5, 0)],
		[Vector3(f, hh, depth), Vector3(-ww * 0.5 - f * 0.5, (y0 + y1) * 0.5, 0)],
		[Vector3(f, hh, depth), Vector3(ww * 0.5 + f * 0.5, (y0 + y1) * 0.5, 0)],
		[Vector3(0.05, hh, 0.08), Vector3(0, (y0 + y1) * 0.5, 0)],                 # Mullion
		[Vector3(ww, 0.04, 0.08), Vector3(0, y0 + hh * 0.62, 0)],                  # Transom
		[Vector3(ww + 0.3, 0.06, 0.22), Vector3(0, y0 - 0.12, out_sign * (depth * 0.5 + 0.05))],  # Outer sill
	]
	for pc in pieces:
		var sz: Vector3 = pc[0]
		var lp: Vector3 = pc[1]
		if axis == "x":
			_b.box_at(sz, Vector3(c + lp.x, lp.y, fixed + lp.z), _steel)
		else:
			_b.box_at(Vector3(sz.z, sz.y, sz.x), Vector3(fixed + lp.z, lp.y, c + lp.x), _steel)
	var pane := QuadMesh.new()
	pane.size = Vector2(ww, hh)
	var mi := PubKit.mesh_instance(pane, Vector3.ZERO, _glass, _root)
	if axis == "x":
		mi.position = Vector3(c, (y0 + y1) * 0.5, fixed)
	else:
		mi.position = Vector3(fixed, (y0 + y1) * 0.5, c)
		mi.rotation_degrees.y = 90.0


func _build_door() -> void:
	var d := _L.d
	var T := PubLayout.T
	var fy := PubLayout.FY
	var dw := PubLayout.DOOR_W
	var dh := PubLayout.DOOR_H
	var z := d + T * 0.5
	var accent: Color = _L.p["accent_color"]
	var neon := PubKit.neon(accent, 3.5)
	# Chunky airlock surround
	_b.box_at(Vector3(dw + 0.7, 0.35, T + 0.3), Vector3(0, fy + dh + 0.175, z), _steel)
	for sx in [-1.0, 1.0]:
		_b.box_at(Vector3(0.35, dh + 0.35, T + 0.3), Vector3(sx * (dw * 0.5 + 0.175), fy + (dh + 0.35) * 0.5, z), _steel)
		# Lit strips inside the jambs
		_b.box_at(Vector3(0.04, dh - 0.2, 0.06), Vector3(sx * (dw * 0.5 + 0.02), fy + dh * 0.5, z + T * 0.5 + 0.1), neon)
		# Sliding leaves parked open against the facade
		var leaf := _b
		leaf.box_at(Vector3(1.15, dh - 0.05, 0.07), Vector3(sx * (dw * 0.5 + 0.62), fy + dh * 0.5, z + T * 0.5 + 0.2), _plate)
		var port := PubKit.mesh_instance(PubKit.cyl(0.2, 0.2, 0.09, 20), Vector3(sx * (dw * 0.5 + 0.62), fy + dh * 0.62, z + T * 0.5 + 0.2), PubKit.glass(Color(0.9, 0.7, 0.45, 0.5), Color(1.0, 0.7, 0.4), 1.2), _root)
		port.rotation_degrees.x = 90.0
	_b.box_at(Vector3(dw, 0.04, 0.06), Vector3(0, fy + dh - 0.08, z + T * 0.5 + 0.1), neon)
	# Threshold plate
	_b.box_at(Vector3(dw, 0.03, T + 0.4), Vector3(0, fy + 0.012, z), PubKit.flat(Color(0.5, 0.45, 0.35), 0.35, 0.9))


# ─── Roof ──────────────────────────────────────────────────────────────────

func _build_roof() -> void:
	var w := _L.w
	var d := _L.d
	var T := PubLayout.T
	var eave := _L.eave
	var z0 := -d - T - 0.45
	var z1 := d + T + 0.45
	var prof := _L.roof_profile()
	var roof := PubKit.extrude(prof, z0, z1, _L.roof_style == 0, 2.2)
	var mi := PubKit.mesh_instance(roof, Vector3.ZERO, _roof, _root, true)
	mi.name = "Roof"
	# Barge boards along the front/back roof edges and fascia along the eaves
	for zz in [z0, z1]:
		for i in prof.size() - 1:
			_seg_box(_b, prof[i], prof[i + 1], zz, Vector2(0.22, 0.12), Vector2(0.0, 0.0), _steel)
	for e in [prof[0], prof[prof.size() - 1]]:
		_b.box_at(Vector3(0.1, 0.22, z1 - z0), Vector3(e.x, e.y - 0.05, 0), _steel)
	# Gutter + downpipes on the low eaves
	for e in [prof[0], prof[prof.size() - 1]]:
		if e.y > eave + 0.5:
			continue
		var gx: float = e.x + signf(e.x) * 0.08
		_b.box_at(Vector3(0.14, 0.1, z1 - z0), Vector3(gx, e.y - 0.12, 0), _dark)
		for zz in [-d + 0.4, d - 1.3]:
			_b.add_mesh(PubKit.cyl(0.05, 0.05, e.y - 0.1), Transform3D(Basis(), Vector3(gx, (e.y - 0.1) * 0.5, zz)), _dark)

	# Exposed steel trusses inside: ribs following the roof + tie beams at eave height
	var n_ribs := int(ceil(2.0 * d / 2.7))
	var inner := PackedVector2Array()
	for v in prof:
		if absf(v.x) <= w + 0.01:
			inner.append(v)
	inner.insert(0, Vector2(-w, _L.roof_y(-w)))
	inner.append(Vector2(w, _L.roof_y(w)))
	var rib_mat := PubKit.flat(Color(0.09, 0.085, 0.08), 0.5, 0.75)
	for i in n_ribs + 1:
		var zr := lerpf(-d + 0.25, d - 0.25, float(i) / float(n_ribs))
		for k in inner.size() - 1:
			_seg_box(_bi, inner[k], inner[k + 1], zr, Vector2(0.16, 0.12), Vector2(0.0, -0.12), rib_mat)
		_bi.box_at(Vector3(2.0 * w, 0.2, 0.12), Vector3(0, eave - 0.1, zr), rib_mat)
		if _L.roof_style != 2:
			_bi.box_at(Vector3(0.1, _L.roof_y(0.0) - eave - 0.2, 0.1), Vector3(0, (eave + _L.roof_y(0.0) - 0.2) * 0.5, zr), rib_mat)
	# Purlins running front-to-back
	for fx in [-0.6, -0.25, 0.25, 0.6]:
		var px: float = fx * w
		_bi.box_at(Vector3(0.1, 0.14, 2.0 * d), Vector3(px, _L.roof_y(px) - 0.3, 0), rib_mat)
	# Longitudinal beam over the bar for the pendant lamps
	_bi.box_at(Vector3(_L.bar_x1 - _L.bar_x0, 0.16, 0.12), Vector3(_L.bar_cx, eave - 0.3, _L.counter_z), rib_mat)


func _seg_box(batch: PubKit.Batch, a: Vector2, b: Vector2, z: float, size: Vector2, offset: Vector2, mat: Material) -> void:
	## Box spanning profile segment a→b at depth z (size = height × depth), shifted along its normal.
	var dv := b - a
	var len := dv.length()
	if len < 0.01:
		return
	var nrm := Vector2(-dv.y, dv.x) / len
	var mid := (a + b) * 0.5 + nrm * (offset.y - size.x * 0.5 * 0.0)
	var basis := Basis(Vector3(0, 0, 1), atan2(dv.y, dv.x))
	batch.box(Vector3(len + 0.02, size.x, size.y), Transform3D(basis, Vector3(mid.x, mid.y, z)), mat)


# ─── Porch ─────────────────────────────────────────────────────────────────

func _build_porch() -> void:
	var w := _L.w
	var d := _L.d
	var T := PubLayout.T
	var fy := PubLayout.FY
	var pd := PubLayout.PORCH_D
	var z0 := d + T
	var z1 := z0 + pd
	var px := w - 0.4
	var deck := PubKit.pbr("metal_plate", 1.2, Color(0.75, 0.72, 0.68), true, 1.0, 0.4)
	_b.box_at(Vector3(2.0 * px, fy + 1.0, pd), Vector3(0, (fy - 1.0) * 0.5, (z0 + z1) * 0.5), deck)
	_b.box_at(Vector3(2.0 * px + 0.04, 0.1, 0.06), Vector3(0, fy - 0.06, z1), _steel)
	# Steps down to the regolith, nosings picked out in safety yellow
	var n_steps := 3
	var tread := 0.32
	for i in n_steps:
		var top := fy * float(n_steps - i) / float(n_steps + 1)
		var sz := z1 + tread * (float(i) + 0.5)
		_b.box_at(Vector3(2.8, top + 0.8, tread), Vector3(0, (top - 0.8) * 0.5, sz), deck)
		_b.box_at(Vector3(2.8, 0.025, 0.05), Vector3(0, top + 0.002, sz + tread * 0.5 - 0.03), PubKit.flat(Color(0.9, 0.65, 0.1), 0.5, 0.3))

	# Railings (posts + top/mid rails), gap for the steps
	var post_h := 1.02
	var runs := [[Vector3(-px, 0, z1 - 0.06), Vector3(-1.45, 0, z1 - 0.06)],
		[Vector3(1.45, 0, z1 - 0.06), Vector3(px, 0, z1 - 0.06)],
		[Vector3(-px, 0, z0 + 0.1), Vector3(-px, 0, z1 - 0.06)],
		[Vector3(px, 0, z0 + 0.1), Vector3(px, 0, z1 - 0.06)]]
	for r in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 1.5)))
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			_b.box_at(Vector3(0.07, post_h, 0.07), Vector3(p.x, fy + post_h * 0.5, p.z), _steel)
		var mid := (a + b) * 0.5
		var along := b - a
		var sz := Vector3(absf(along.x) + 0.07, 0.06, absf(along.z) + 0.07)
		_b.box_at(sz, Vector3(mid.x, fy + post_h, mid.z), _steel)
		_b.box_at(Vector3(maxf(sz.x - 0.04, 0.03), 0.03, maxf(sz.z - 0.04, 0.03)), Vector3(mid.x, fy + 0.52, mid.z), _steel)
		_coll(Vector3(maxf(sz.x, 0.12), 1.1, maxf(sz.z, 0.12)), Vector3(mid.x, fy + 0.55, mid.z))

	# Awning: sloped steel sheet on posts, sheltering the whole porch
	var ay0 := fy + 3.5
	var ay1 := fy + 3.05
	var slope := atan2(ay0 - ay1, pd + 0.3)
	var awn_mat := PubKit.pbr("container_side", 1.8, (_L.p["shell_tint"] as Color).darkened(0.5), true)
	_b.box_at(Vector3(2.0 * px + 0.4, 0.05, pd + 0.5), Vector3(0, (ay0 + ay1) * 0.5, (z0 + z1) * 0.5 + 0.1), awn_mat, Vector3(slope, 0, 0))
	_b.box_at(Vector3(2.0 * px + 0.4, 0.16, 0.12), Vector3(0, ay1 - 0.1, z1 - 0.1), _steel)
	var post_xs := [-px + 0.06, -1.6, 1.6, px - 0.06]
	for x in post_xs:
		_b.box_at(Vector3(0.12, ay1 - fy, 0.12), Vector3(x, fy + (ay1 - fy) * 0.5, z1 - 0.1), _steel)
		_coll(Vector3(0.14, 2.6, 0.14), Vector3(x, fy + 1.3, z1 - 0.1))
	# String lights sagging between the awning posts
	var bulbs: Array[Vector3] = []
	for i in post_xs.size() - 1:
		var a := Vector3(post_xs[i], ay1 - 0.2, z1 - 0.05)
		var b := Vector3(post_xs[i + 1], ay1 - 0.2, z1 - 0.05)
		var n := maxi(3, int(a.distance_to(b) / 0.42))
		for k in range(1, n):
			var t := float(k) / float(n)
			var p := a.lerp(b, t)
			p.y -= sin(t * PI) * 0.28
			bulbs.append(p)
	# ...and a second strand zig-zagging under the awning
	for i in 9:
		var t := float(i) / 8.0
		bulbs.append(Vector3(lerpf(-px + 0.5, px - 0.5, t), lerpf(ay0, ay1, 0.5) - 0.25 - sin(t * PI * 4.0) * 0.08, (z0 + z1) * 0.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bulb := SphereMesh.new()
	bulb.radius = 0.045
	bulb.height = 0.1
	bulb.radial_segments = 8
	bulb.rings = 4
	mm.mesh = bulb
	mm.instance_count = bulbs.size()
	for i in bulbs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), bulbs[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = PubKit.neon(Color(1.0, 0.72, 0.38), 7.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "StringLights"
	_root.add_child(mmi)

	# Warm porch light under the awning
	porch_light = OmniLight3D.new()
	porch_light.light_color = Color(1.0, 0.72, 0.45)
	porch_light.light_energy = 2.2
	porch_light.omni_range = 7.5
	porch_light.omni_attenuation = 1.4
	porch_light.position = Vector3(0, ay1 - 0.5, (z0 + z1) * 0.5)
	porch_light.shadow_enabled = false
	_root.add_child(porch_light)

	# Wall lanterns either side of the door
	for sx in [-1.0, 1.0]:
		var lx: float = sx * (PubLayout.DOOR_W * 0.5 + 1.5)
		_b.box_at(Vector3(0.22, 0.34, 0.16), Vector3(lx, fy + 2.55, z0 + 0.08), _dark)
		PubKit.mesh_instance(PubKit.cyl(0.07, 0.07, 0.24, 10), Vector3(lx, fy + 2.55, z0 + 0.2),
			PubKit.neon(Color(1.0, 0.78, 0.5), 5.0), _root)

	# Porch furniture: barrel tables with stools, planters by the door
	for sx in [-1.0, 1.0]:
		var bx: float = sx * (w * 0.55)
		var bz := (z0 + z1) * 0.5 + 0.2
		PubKit.place(_root, "wine_barrel_01", Vector3(bx, fy, bz), _rng.randf_range(0, 360), 1.0, true)
		_coll(Vector3(0.7, 0.9, 0.7), Vector3(bx, fy + 0.45, bz))
		for k in 2:
			var ang := _rng.randf_range(0, TAU)
			PubKit.place(_root, "metal_stool_01", Vector3(bx + cos(ang) * 0.75, fy, bz + sin(ang) * 0.75), _rng.randf_range(0, 360), 1.0, true)
		PubKit.place(_root, "potted_plant_04", Vector3(sx * (PubLayout.DOOR_W * 0.5 + 0.75), fy, z0 + 0.45), _rng.randf_range(0, 360), 3.2, true)


# ─── Signage ───────────────────────────────────────────────────────────────

func _build_signage() -> void:
	var w := _L.w
	var d := _L.d
	var T := PubLayout.T
	var fy := PubLayout.FY
	var sc: Color = _L.p["sign_color"]
	var accent: Color = _L.p["accent_color"]
	var z := d + T + 0.08
	var sign_w := minf(2.0 * w - 1.6, 10.5)
	var sy := maxf(fy + 4.25, _L.eave + 0.05)
	# Backing board with a lit frame
	_b.box_at(Vector3(sign_w, 1.3, 0.14), Vector3(0, sy, z), _dark)
	var frame := PubKit.neon(accent, 3.0)
	for sy2 in [-0.62, 0.62]:
		_b.box_at(Vector3(sign_w - 0.1, 0.035, 0.04), Vector3(0, sy + sy2, z + 0.08), frame)
	for sx in [-1.0, 1.0]:
		_b.box_at(Vector3(0.035, 1.24, 0.04), Vector3(sx * (sign_w * 0.5 - 0.05), sy, z + 0.08), frame)
	# Brackets up to the roof edge
	for sx in [-0.4, 0.4]:
		_b.box_at(Vector3(0.08, 0.8, 0.08), Vector3(sx * sign_w, sy + 0.95, z - 0.02), _steel)
	# Name — refreshed later by set_sign_text()
	sign_mesh = MeshInstance3D.new()
	sign_mesh.name = "SignText"
	sign_mesh.material_override = PubKit.neon(sc, 5.5)
	sign_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign_mesh.position = Vector3(0, sy + 0.1, z + 0.1)
	sign_mesh.set_meta("max_w", sign_w - 0.7)
	_root.add_child(sign_mesh)
	neon_nodes.append(sign_mesh)
	var sub := MeshInstance3D.new()
	sub.mesh = PubKit.text_mesh("~  COLD AFFECTION  ·  OPEN ALL CYCLE  ~", 0.0048, 0.015)
	sub.material_override = PubKit.neon(_L.p["neon_b"], 3.0)
	sub.position = Vector3(0, sy - 0.42, z + 0.1)
	sub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(sub)
	neon_nodes.append(sub)

	# Sign glow on the porch and the regolith out front
	sign_light = OmniLight3D.new()
	sign_light.light_color = sc.lerp(Color.WHITE, 0.25)
	sign_light.light_energy = 2.4
	sign_light.omni_range = 14.0
	sign_light.omni_attenuation = 1.2
	sign_light.position = Vector3(0, fy + 3.9, z + 2.6)
	sign_light.shadow_enabled = false
	_root.add_child(sign_light)

	# Blade sign on the right corner: vertical BAR, readable from the street
	var bx := w + T + 0.95
	var bz := d - 0.35
	var by := _L.eave - 1.5
	_b.box_at(Vector3(0.9, 2.5, 0.12), Vector3(bx, by, bz), _dark)
	for ay in [1.0, -1.0]:
		_b.box_at(Vector3(0.6, 0.08, 0.08), Vector3(w + T + 0.27, by + ay, bz), _steel)
	var na: Color = _L.p["neon_a"]
	var letters := "BAR"
	for i in letters.length():
		for face in [1.0, -1.0]:
			var lm := MeshInstance3D.new()
			lm.mesh = PubKit.text_mesh(letters[i], 0.011, 0.03)
			lm.material_override = PubKit.neon(na, 5.0)
			lm.position = Vector3(bx, by + 0.75 - float(i) * 0.75, bz + face * 0.08)
			lm.rotation_degrees.y = 0.0 if face > 0.0 else 180.0
			lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root.add_child(lm)
			neon_nodes.append(lm)
	var edge := PubKit.neon(na, 2.5)
	for sy3 in [-1.24, 1.24]:
		_b.box_at(Vector3(0.9, 0.03, 0.14), Vector3(bx, by + sy3, bz), edge)

	# "OPEN" neon hanging in the left front window (reads mirrored from inside — as it should)
	var fw: Array = _L.front_windows[0]
	var open := MeshInstance3D.new()
	open.mesh = PubKit.text_mesh("OPEN", 0.008, 0.02)
	open.material_override = PubKit.neon(Color(1.0, 0.18, 0.15), 6.0)
	open.position = Vector3(fw[0], fy + fw[2] + 0.55, d - 0.05)
	_root.add_child(open)
	neon_nodes.append(open)


func set_sign_text(text: String) -> void:
	if sign_mesh == null:
		return
	var tm := PubKit.text_mesh(text, 0.01, 0.04)
	sign_mesh.mesh = tm
	# Fit long QING names inside the board
	var ab := tm.get_aabb()
	var max_w: float = sign_mesh.get_meta("max_w", 8.0)
	var s := 1.0
	if ab.size.x > max_w:
		s = max_w / ab.size.x
	sign_mesh.scale = Vector3(s, s, 1.0)


# ─── Rooftop and yard ──────────────────────────────────────────────────────

func _build_rooftop() -> void:
	var w := _L.w
	var d := _L.d
	# Antenna mast with cross-arms and a blinking beacon
	var ax := w * 0.45
	var az := -d * 0.45
	var ay := _L.roof_y(ax) - 0.1
	_b.add_mesh(PubKit.cyl(0.05, 0.08, 4.6, 8), Transform3D(Basis(), Vector3(ax, ay + 2.3, az)), _steel)
	for i in 3:
		var yy := ay + 1.6 + float(i) * 0.9
		_b.box_at(Vector3(1.2 - float(i) * 0.3, 0.04, 0.04), Vector3(ax, yy, az), _steel)
		_b.box_at(Vector3(0.04, 0.04, 0.8 - float(i) * 0.2), Vector3(ax, yy + 0.3, az), _steel)
	beacon = PubKit.mesh_instance(_sphere(0.08), Vector3(ax, ay + 4.65, az), PubKit.neon(Color(1.0, 0.1, 0.05), 8.0), _root)
	# Guy wires
	for k in 3:
		var ang := float(k) * TAU / 3.0 + 0.4
		var foot := Vector3(ax + cos(ang) * 1.6, 0, az + sin(ang) * 1.6)
		foot.y = _L.roof_y(foot.x)
		var top := Vector3(ax, ay + 3.6, az)
		_line(_b, foot, top, 0.012, _dark)

	# Satellite dish on a short stub, aimed at the sky
	var dx := -w * 0.35
	var dz := -d * 0.25
	var dy := _L.roof_y(dx)
	_b.add_mesh(PubKit.cyl(0.07, 0.09, 0.9, 8), Transform3D(Basis(), Vector3(dx, dy + 0.4, dz)), _steel)
	var dish := PubKit.mesh_instance(PubKit.cyl(0.85, 0.12, 0.32, 24), Vector3(dx, dy + 1.0, dz),
		PubKit.flat(Color(0.8, 0.8, 0.78), 0.45, 0.5), _root, true)
	dish.rotation_degrees = Vector3(-40, 25, 0)
	var feed := PubKit.mesh_instance(PubKit.cyl(0.015, 0.015, 0.9, 6), Vector3.ZERO, _steel, _root, true)
	feed.position = dish.position + dish.basis.y * 0.55
	feed.rotation = dish.rotation

	# Vent stacks poking through the roof
	for i in 3:
		var vx := lerpf(-w * 0.75, w * 0.1, float(i) / 2.0) + _rng.randf_range(-0.4, 0.4)
		var vz := _rng.randf_range(-d * 0.6, d * 0.5)
		var vy := _L.roof_y(vx)
		var vh := _rng.randf_range(0.7, 1.3)
		_b.add_mesh(PubKit.cyl(0.14, 0.14, vh + 0.4, 12), Transform3D(Basis(), Vector3(vx, vy + vh * 0.5 - 0.2, vz)), _steel)
		_b.add_mesh(PubKit.cyl(0.24, 0.2, 0.12, 12), Transform3D(Basis(), Vector3(vx, vy + vh + 0.05, vz)), _dark)


func _build_yard() -> void:
	var w := _L.w
	var d := _L.d
	var T := PubLayout.T
	var fy := PubLayout.FY
	# HVAC units on the right flank, piped into the wall
	var hx := w + T + 0.75
	for i in 2:
		var hz := -d * 0.5 + float(i) * 1.5
		_b.box_at(Vector3(1.0, 1.0, 1.3), Vector3(hx, 0.5, hz), _plate)
		_b.box_at(Vector3(1.04, 0.06, 1.34), Vector3(hx, 1.02, hz), _dark)
		var fan := PubKit.mesh_instance(PubKit.cyl(0.42, 0.42, 0.04, 20), Vector3(hx, 1.06, hz), _dark, _root)
		fan.name = "HvacFan%d" % i
		_b.add_mesh(PubKit.cyl(0.06, 0.06, 0.9, 8), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(w + T + 0.25 - 0.2, 0.75, hz + 0.35)),
			PubKit.flat(Color(0.55, 0.35, 0.2), 0.4, 0.9))
		_coll(Vector3(1.0, 1.0, 1.3), Vector3(hx, 0.5, hz))
	# Copper pipe run along the right wall
	var copper := PubKit.flat(Color(0.6, 0.36, 0.22), 0.38, 0.95)
	for k in 2:
		var py := fy + 2.3 + float(k) * 0.28
		_b.add_mesh(PubKit.cyl(0.055, 0.055, 2.0 * d - 1.0, 10), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(w + T + 0.1, py, -0.5)), copper)
	for i in int(2.0 * d / 1.6):
		_b.box_at(Vector3(0.14, 0.7, 0.05), Vector3(w + T + 0.07, fy + 2.45, -d + 0.4 + float(i) * 1.6), _dark)

	# Gas tanks on the left flank
	for i in 3:
		var tz := -d + 1.2 + float(i) * 0.7
		PubKit.place(_root, "Barrel_01", Vector3(-w - T - 0.55, 0.0, tz), _rng.randf_range(0, 360), 1.05, true)
	_coll(Vector3(0.8, 1.0, 2.2), Vector3(-w - T - 0.55, 0.5, -d + 1.9))
	_b.add_mesh(PubKit.cyl(0.04, 0.04, 2.0, 8), Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3(-w - T - 0.12, 1.0, -d + 1.9)), copper)

	# Back yard: crates, kegs, a staff door with its own little lamp
	var bz := -d - T
	_b.box_at(Vector3(1.1, 2.3, 0.08), Vector3(w * 0.45, 1.15 + 0.05, bz - 0.04), _plate)
	_b.box_at(Vector3(1.3, 0.1, 0.1), Vector3(w * 0.45, 2.4, bz - 0.06), _steel)
	PubKit.mesh_instance(PubKit.cyl(0.08, 0.08, 0.14, 10), Vector3(w * 0.45, 2.65, bz - 0.1),
		PubKit.neon(Color(1.0, 0.75, 0.45), 4.0), _root)
	var cx := -w * 0.35
	var stack := [Vector3(0, 0, 0), Vector3(0.86, 0, 0.1), Vector3(0.4, 0.33, 0.04), Vector3(-0.1, 0, 0.55)]
	for i in stack.size():
		var p: Vector3 = stack[i]
		PubKit.place(_root, "wooden_crate_01", Vector3(cx + p.x, p.y, bz - 0.55 - p.z), _rng.randf_range(-12, 12), 1.0, true)
	_coll(Vector3(2.0, 0.7, 1.2), Vector3(cx + 0.4, 0.35, bz - 0.8))
	for i in 4:
		var kp := Vector3(w * 0.05 + float(i % 2) * 0.62, 0.0, bz - 0.5 - float(i / 2) * 0.62)
		PubKit.place(_root, "Barrel_01", kp, _rng.randf_range(0, 360), 0.95, true)
	PubKit.place(_root, "wine_barrel_01", Vector3(w * 0.05 + 1.5, 0.37, bz - 0.7), 0.0, Vector3(1, 1, 1), true).rotation_degrees = Vector3(0, 20, 90)
	_coll(Vector3(2.2, 0.9, 1.4), Vector3(w * 0.05 + 0.7, 0.45, bz - 0.8))


# ─── Helpers ───────────────────────────────────────────────────────────────

func _coll(size: Vector3, pos: Vector3) -> void:
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	c.position = pos
	_body.add_child(c)


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	return s


func _line(batch: PubKit.Batch, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var len := a.distance_to(b)
	var up := (b - a) / len
	var basis := Basis(Quaternion(Vector3.UP, up))
	batch.add_mesh(PubKit.cyl(r, r, len, 4), Transform3D(basis, (a + b) * 0.5), mat)
