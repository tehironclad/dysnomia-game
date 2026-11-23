class_name Solid
extends RefCounted
## Makes structures solid: static collision the player (a CharacterBody3D on
## move_and_slide) and the camera's spring arm bump into. Shapes are simple
## boxes and cylinders sized to what you see.


## A box of `size`, centred at `at` in `parent`'s space, turned by `yaw` (radians).
static func box(parent: Node3D, size: Vector3, at: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation.y = yaw
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	return body


## An upright cylinder standing on `at` (its base), `height` tall.
static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at + Vector3(0.0, height * 0.5, 0.0)
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	body.add_child(cs)
	return body


## A box around everything `node` draws (its meshes' combined bounds, in the
## node's own space), added as a child so it moves with it.
static func wrap(node: Node3D, shrink: float = 0.9) -> StaticBody3D:
	var aabb := AABB()
	var first := true
	var inv := node.global_transform.affine_inverse() if node.is_inside_tree() else Transform3D()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var to_node: Transform3D = (inv * m.global_transform) if node.is_inside_tree() else _relative(node, m)
		var b := to_node * m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if first or aabb.size.length() < 0.01:
		return null
	var size := Vector3(aabb.size.x * shrink, aabb.size.y, aabb.size.z * shrink)
	var body := StaticBody3D.new()
	body.position = aabb.get_center()
	node.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	return body


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
