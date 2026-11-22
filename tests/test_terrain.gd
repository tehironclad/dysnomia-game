extends TestCase
## The visible ground and the collision ground must be the same heights.

const ILLINOIS := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func test_mesh_and_collider_share_heights() -> void:
	var t := DeepFieldTerrain.new()
	t.build(Registry.get_territory(ILLINOIS))
	var hf := t.heightfield
	eq(hf.n, DeepFieldTerrain.SAMPLES)
	var body: StaticBody3D = t.get_node("GroundBody")
	var shape := (body.get_child(0) as CollisionShape3D).shape as HeightMapShape3D
	eq(shape.map_width, hf.n)
	eq(shape.map_depth, hf.n)
	check(shape.map_data == hf.heights, "collider uses the heightfield verbatim")
	var mesh: ArrayMesh = (t.get_node("GroundMesh") as MeshInstance3D).mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var worst := 0.0
	for i in range(0, verts.size(), 997):
		var v := verts[i]
		worst = maxf(worst, absf(v.y - hf.height_at(v.x, v.z)))
	check(worst < 1e-3, "mesh vertices sit on the heightfield (worst %f m)" % worst)
	near(t.height_at(0, 0), hf.core_height, 1e-4, "core")
	t.free()
