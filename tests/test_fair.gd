extends TestCase
## The Affection Fair's placement and tier mapping. No network, no scene.


func test_tier_mapping() -> void:
	var F = load("res://scripts/world/funfair/fair_site.gd")
	eq(F.fair_tier(0), 0, "Wild → surveyed lot")
	eq(F.fair_tier(1), 0, "Outpost → surveyed lot")
	eq(F.fair_tier(2), 1, "Settlement → night market")
	eq(F.fair_tier(3), 2, "Town → fairground")
	eq(F.fair_tier(4), 3, "City → grand fair")
	eq(F.fair_tier(5), 3, "Capital → grand fair")


func test_site_is_on_land_and_clear_of_landmarks() -> void:
	var F = load("res://scripts/world/funfair/fair_site.gd")
	# An island: land (0 m) within 150 m of (40, 110), sea (−20 m) elsewhere, gentle relief.
	var island := func(x: float, z: float) -> float:
		var d := Vector2(x, z).distance_to(Vector2(40, 110))
		return (0.6 * sin(x * 0.05) if d < 150.0 else -20.0)
	var s: Dictionary = F.find_site(island)
	check(s["ok"], "a site fully on land is found")
	var at: Vector2 = s["at"]
	check(at.distance_to(Vector2(40, 110)) + F.RADIUS <= 150.0 + 0.01, "the whole footprint is on the island")
	for k in F.KEEP_CLEAR:
		check(at.distance_to(k) >= F.CLEAR_M, "clear of the Core's landmarks")
	check(float(s["top"]) - float(s["low"]) < 2.0, "flat enough")
	# Deterministic
	eq(F.find_site(island)["at"], at)


func test_no_land_gives_best_effort_not_a_fake_site() -> void:
	var F = load("res://scripts/world/funfair/fair_site.gd")
	var s: Dictionary = F.find_site(func(_x: float, _z: float) -> float: return -30.0)
	check(not s["ok"], "no fully-on-land spot is reported as such")
	check(s.has("at"), "still returns the best effort")


func test_real_relief_still_has_fair_sites() -> void:
	# The v2 relief (terraced highlands round the Core's plain) must still leave
	# flat land for the fair: a full on-land site, steps under 5 m, on real territories.
	var F = load("res://scripts/world/funfair/fair_site.gd")
	for a in ["0xd127839b83cbf537c29b7d268c135f745a0da2e8", "0xe4169cf239e2fdc6e6e4a3a6fa0a703058ce400b", Registry.all()[7]["address"]]:
		var q: Dictionary = Registry.get_territory(a)
		var hf := JuliaHeightfield.compute(DeepField.for_territory(q), a, 129)
		var core := hf.core_height
		var s: Dictionary = F.find_site(func(x: float, z: float) -> float: return hf.height_at(x, z) - core)
		check(s["ok"], "%s: a fair site on land" % q["name"])
		check(float(s["top"]) - float(s["low"]) < 5.0, "%s: flat enough (%.1f m)" % [q["name"], float(s["top"]) - float(s["low"])])


func test_far_proxy_merges_static_parts() -> void:
	var group := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color.BLUE
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var parts: Array = []
	for i in 4:
		var mi := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(1.5, 1.5, 1.5)
		mi.mesh = bx
		mi.position = Vector3(i * 3.0, 0, 0)
		mi.material_override = [red, red, blue, glass][i]
		group.add_child(mi)
		parts.append(mi)
	var tiny := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.05, 0.05, 0.05)
	tiny.mesh = tb
	group.add_child(tiny)
	var striped := MeshInstance3D.new()   # a shader-driven mesh stays live
	striped.mesh = BoxMesh.new()
	striped.material_override = ShaderMaterial.new()
	group.add_child(striped)
	var hidden := MeshInstance3D.new()    # hidden at build: shows live when it shows
	hidden.mesh = BoxMesh.new()
	hidden.visible = false
	group.add_child(hidden)
	var own := MeshInstance3D.new()       # its own range stands
	own.mesh = BoxMesh.new()
	own.visibility_range_end = 30.0
	group.add_child(own)
	var label := Label3D.new()
	label.text = "SIGN"
	group.add_child(label)
	var proxy := FarProxy.build(group)
	check(proxy != null, "a stand-in is made")
	eq(proxy.mesh.get_surface_count(), 2, "plain paints share one surface (colour per vertex); glass keeps its own")
	var paint := proxy.mesh.surface_get_arrays(0)
	eq((paint[Mesh.ARRAY_COLOR] as PackedColorArray).size(), (paint[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "a colour per vertex")
	check((paint[Mesh.ARRAY_COLOR] as PackedColorArray).has(Color(0, 0, 1, 0)), "blue kept as vertex colour")
	check(proxy.mesh.get_surface_count() > 1 and proxy.mesh.surface_get_material(1) == glass, "glass keeps its material")
	near(proxy.visibility_range_begin, FarProxy.BEGIN_M, 1e-6, "shows past BEGIN_M")
	eq(proxy.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the stand-in casts no shadow itself")
	var caster := group.get_node_or_null("FarProxyShadow") as MeshInstance3D
	check(caster != null and caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "one shadow-only caster")
	eq(caster.mesh.get_surface_count(), 1, "the caster is one surface")
	for p in parts:
		eq((p as MeshInstance3D).visibility_parent, (p as Node).get_path_to(proxy), "parts hide behind the stand-in")
	check(tiny.visibility_parent != NodePath(), "a tiny part hides with the group…")
	near(proxy.mesh.get_aabb().size.x, 10.5, 1e-3, "…but isn't in the stand-in (boxes only)")
	eq(striped.visibility_parent, NodePath(), "shader meshes stay live")
	eq(hidden.visibility_parent, NodePath(), "hidden parts stay live")
	eq(own.visibility_parent, NodePath(), "own range stands")
	eq(label.visibility_parent, NodePath(), "labels stay live")
	group.free()


func test_far_proxy_cache_shares_mesh() -> void:
	var meshes: Array = []
	for k in 2:
		var g := Node3D.new()
		for i in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.position = Vector3(i, 0, 0)
			g.add_child(mi)
		meshes.append(FarProxy.build(g, [], FarProxy.BEGIN_M, "test_far_proxy_cache").mesh)
		g.free()
	check(meshes[0] == meshes[1], "groups built alike share one stand-in mesh (their draws batch)")


func test_label_declutter_resolve() -> void:
	var a := Rect2(0, 0, 100, 20)
	var b := Rect2(50, 5, 100, 20)    # overlaps a
	var c := Rect2(300, 0, 100, 20)   # clear
	var none := Rect2()               # behind the camera / out of range
	eq(LabelDeclutter.resolve([a, b, c, none], [true, true, true, true]), [true, false, true, false], "priority wins the overlap")
	eq(LabelDeclutter.resolve([b, a, c], [true, true, true]), [true, false, true], "order is the priority")
	# Hysteresis: a label that is showing keeps its place against a near miss that a hidden one can't enter
	var d := Rect2(0, 24, 100, 20)
	eq(LabelDeclutter.resolve([a, d], [true, true]), [true, true], "shown: room enough")
	eq(LabelDeclutter.resolve([a, Rect2(0, 21, 100, 20)], [true, false]), [true, false], "hidden: needs a bit more room to come back")
