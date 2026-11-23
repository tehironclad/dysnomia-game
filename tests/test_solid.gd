extends TestCase
## Solid: collision sized to what you see. No network.


func test_box_and_cylinder() -> void:
	var root := Node3D.new()
	var b := Solid.box(root, Vector3(2, 3, 4), Vector3(1, 1.5, 0), PI * 0.5)
	var sh := (b.get_child(0) as CollisionShape3D).shape as BoxShape3D
	eq(sh.size, Vector3(2, 3, 4))
	eq(b.position, Vector3(1, 1.5, 0))
	var c := Solid.cylinder(root, 0.9, 10.0, Vector3(5, 0, 0))
	eq(c.position, Vector3(5, 5, 0), "a cylinder stands on its base")
	root.free()


func test_wrap_follows_the_meshes() -> void:
	var prop := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 1, 4)
	mi.mesh = bm
	mi.position = Vector3(0, 0.5, 1)
	prop.add_child(mi)
	var body := Solid.wrap(prop, 1.0)
	check(body != null, "a body was added")
	var sh := (body.get_child(0) as CollisionShape3D).shape as BoxShape3D
	eq(sh.size, Vector3(2, 1, 4))
	eq(body.position, Vector3(0, 0.5, 1), "centred on what's drawn")
	var empty := Node3D.new()
	check(Solid.wrap(empty) == null, "nothing drawn, nothing solid")
	empty.free()
	prop.free()
