extends TestCase
## Avatar heads from a LAU's own on-chain text (Username, name, symbol).


func test_real_laus() -> void:
	# From the site's LAU registry (chain-read names and symbols).
	eq(AvatarHeads.kind_for("RatKing", "RatKing", "🐀👑"), "rat")
	eq(AvatarHeads.accessories_for("RatKing", "RatKing", "🐀👑"), ["crown"])
	eq(AvatarHeads.kind_for("enteh", "enter teh", "enteh"), "bear", "no creature named: the LAU bear")
	eq(AvatarHeads.kind_for("Cpt.Cavy", "Guinea Pirate 🐹", "ARRR"), "hamster")
	eq(AvatarHeads.kind_for("ogwebchef888", "Hey Zeus", "😇"), "bear")
	eq(AvatarHeads.accessories_for("ogwebchef888", "Hey Zeus", "😇"), ["halo"])


func test_whole_words_only() -> void:
	eq(AvatarHeads.kind_for("pirate", "karate", "ratio"), "bear", "'rat' inside a word is not a rat")
	eq(AvatarHeads.kind_for("x", "the cat", "C"), "cat")
	eq(AvatarHeads.kind_for("👽", "", ""), "alien")
	eq(AvatarHeads.kind_for("pepe", "dog", ""), "frog", "the username speaks first")


func test_every_kind_builds() -> void:
	for k in AvatarHeads.KINDS:
		if k == "human":
			continue  # the body's own head: nothing to build
		var parts := AvatarHeads.build_parts(k)
		check(parts.get_child_count() >= 4, "%s has parts" % k)
		parts.free()
		# Baked: one mesh instance, one surface, the shared head material.
		var h := AvatarHeads.build(k)
		check(h is MeshInstance3D and (h as MeshInstance3D).mesh.get_surface_count() == 1, "%s bakes into one surface" % k)
		check((h as MeshInstance3D).mesh.get_aabb().size.y > 0.2, "%s baked mesh has its size" % k)
		var again := AvatarHeads.build(k)
		check((again as MeshInstance3D).mesh == (h as MeshInstance3D).mesh, "%s baked mesh is shared" % k)
		again.free()
		h.free()
	for a in AvatarHeads.ACCESSORIES:
		var n := AvatarHeads.accessory_parts(a)
		check(n.get_child_count() >= 1, "%s has parts" % a)
		n.free()
		var b := AvatarHeads.accessory(a)
		check(b is MeshInstance3D and (b as MeshInstance3D).mesh.get_surface_count() == 1, "%s bakes" % a)
		b.free()
