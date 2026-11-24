extends TestCase
## Outfits: every design sews for both bodies, binds to the Universal rig, the
## UAL clips still resolve on that rig, and the outfit a wallet draws is the
## same everywhere (it depends on the address alone). No network.

const WALLET := "0x6d936484072482335a7a479f92a6d3cd7979829e"
const CLIPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump", "Jump_Start", "Jump_Land",
	"Swim_Fwd", "Driving", "Sitting_Idle", "Sitting_Talking", "Idle_Talking", "Interact", "Dance"]


func test_every_outfit_sews_and_binds_to_the_rig() -> void:
	for body in ["male", "female"]:
		var rig := OutfitTailor.rig(body)
		var sk: Skeleton3D = rig.get_node("Armature/Skeleton3D")
		eq(sk.get_bone_count(), 65, "%s rig bones" % body)
		for kind in Outfits.KINDS:
			var o := OutfitTailor.build(body, kind)
			var mesh: ArrayMesh = o["mesh"]
			var skin: Skin = o["skin"]
			check(skin != null, "%s/%s has a skin" % [body, kind])
			check(mesh.get_surface_count() >= 2, "%s/%s has garments and tailoring" % [body, kind])
			eq(mesh.get_surface_count(), (o["atlases"] as Array).size(), "%s/%s one atlas per surface" % [body, kind])
			check((o["atlases"] as Array).has("tailored"), "%s/%s has the tailored surface (at least the neck)" % [body, kind])
			if skin:
				for i in skin.get_bind_count():
					check(sk.find_bone(skin.get_bind_name(i)) >= 0, "%s/%s bind %s on the rig" % [body, kind, skin.get_bind_name(i)])
			var tris := 0
			for s in mesh.get_surface_count():
				tris += mesh.surface_get_array_index_len(s) / 3
				var a := mesh.surface_get_arrays(s)
				var nv := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				eq((a[Mesh.ARRAY_BONES] as PackedInt32Array).size(), nv * 4, "%s/%s surface %d: 4 influences" % [body, kind, s])
				var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
				var bad := 0
				for v in nv:
					var t := w[v * 4] + w[v * 4 + 1] + w[v * 4 + 2] + w[v * 4 + 3]
					if absf(t - 1.0) > 0.02:
						bad += 1
				eq(bad, 0, "%s/%s surface %d weights sum to 1" % [body, kind, s])
			check(tris > 4000 and tris < 30000, "%s/%s triangles %d" % [body, kind, tris])
			var anchors: Dictionary = o["anchors"]
			check((anchors["chest"] as Vector3).z > 0.05 and (anchors["back"] as Vector3).z < -0.05, "%s/%s chest in front, back behind" % [body, kind])
		rig.free()


func test_animation_set_resolves_on_the_rig() -> void:
	var lib := HumanAvatar.library()
	for body in ["male", "female"]:
		var rig := OutfitTailor.rig(body)
		var sk: Skeleton3D = rig.get_node("Armature/Skeleton3D")
		for c in CLIPS:
			check(lib.has_animation(c), "clip %s" % c)
			if not lib.has_animation(c):
				continue
			var a := lib.get_animation(c)
			var missing := 0
			for t in a.get_track_count():
				var p := a.track_get_path(t)
				if p.get_subname_count() > 0 and sk.find_bone(p.get_concatenated_subnames()) < 0:
					missing += 1
			eq(missing, 0, "%s: %s tracks all name rig bones" % [body, c])
		rig.free()


func test_identity_outfit_is_stable() -> void:
	var a := Outfits.for_identity(WALLET)
	eq(Outfits.for_identity(WALLET.to_upper().replace("0X", "0x")), a, "case does not matter")
	eq(Outfits.for_identity(" " + WALLET + " "), a, "whitespace does not matter")
	# Pinned: FNV-1a 32 of the lowercase address. A change here re-dresses every player.
	eq(Outfits.hash32(WALLET), 1248320632, "hash32 pinned")
	eq(Outfits.hash32("a"), 0xe40c292c, "FNV-1a reference vector")
	eq(a["kind"], Outfits.KINDS[1248320632 % Outfits.KINDS.size()], "kind from the hash")
	var seen := {}
	for i in 200:
		seen[Outfits.for_identity("0x%040x" % (i * 7919 + 1))["kind"]] = true
	eq(seen.size(), Outfits.KINDS.size(), "every design is drawn by some wallet")
	eq(Outfits.colors(a["kind"], a["seed"]), Outfits.colors(a["kind"], a["seed"]), "colours are a function of the seed")


func test_palettes_fill_every_slot() -> void:
	for kind in Outfits.KINDS:
		check(Outfits.DESIGNS.has(kind) and Outfits.PALETTES.has(kind) and Outfits.LABELS.has(kind), kind)
		for p in Outfits.PALETTES[kind]:
			eq((p as Array).size(), Outfits.SLOTS.size(), "%s palette size" % kind)
		var c := Outfits.colors(kind, 12345)
		for s in Outfits.SLOTS + ["skin"]:
			check(c.has(s), "%s colour %s" % [kind, s])
	for k in Outfits.CROWD:
		check(Outfits.KINDS.has(k), "crowd outfit %s" % k)


func test_avatar_wears_and_changes_outfits() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var av := HumanAvatar.new()
	av.civilian = true
	av.outfit_kind = "robe"
	root.add_child(av)
	check(av.outfit_mesh != null and av.outfit_mesh.mesh != null, "wears a mesh")
	eq(av.outfit_kind, "robe")
	var m: Material = av.outfit_mesh.get_surface_override_material(0)
	check(m != null, "materials set")
	av.wear_identity(WALLET)
	var want := Outfits.for_identity(WALLET)
	eq(av.outfit_kind, want["kind"], "identity kind")
	eq(av.outfit_seed, want["seed"], "identity seed")
	av.set_outfit("formal", 3)
	eq(av.outfit_kind, "formal")
	check(av.outfit_mesh != null and is_instance_valid(av.outfit_mesh), "re-dressed")
	av.set_suit_colors(Color.RED, Color.BLUE)
	eq(av.outfit_color("main"), Color.RED, "suit colour override")
	av.set_body("female")
	eq(av.outfit_kind, "formal", "the outfit survives a body change")
	av.modulate_grey(true)
	check(av.get("_glove_right") != null, "a hand hold point for the fair")
	av.free()
