class_name Knockable
extends Node
## A small loose thing you can bump and topple: a bin, a crate, a barrel, a
## stool, a glass. It stays a plain mesh (no body, no collider) until a bumper
## (the player on foot or flying low, a vehicle, another player's avatar, or
## another knocked prop) touches it; then KnockWorld gives it a RigidBody3D for
## as long as it moves, writes the body's pose back to the mesh, and drops the
## body again once it lies still. It goes home after a while, out of view
## (BumpMath.may_reset). Transient and local: nothing about it is state.
##
##   Knockable.add(model, 30.0, "wood")                 # a node: it moves the node
##   Knockable.add(model, 4.0, "metal", {"cyl": true})  # an upright cylinder shape
##   Knockable.add_slots(mmi, 40.0, "wood", {"cyl": true})  # each MultiMesh instance
##
## Not for buildings, rides, stalls or anything Solid: those stay put.

const SOUNDS := ["wood", "metal", "glass", "soft"]

var shape_cyl := false
## Shape size in the target's own (unscaled) space: box = full size; cylinder =
## (diameter, height, diameter).
var size := Vector3.ONE
## The shape's centre in the target's own space.
var center := Vector3.ZERO
var mass := 10.0
var sound := "wood"
## What moves: a Node3D (the default: the parent), or a MultiMesh slot.
var target: Node3D
var mm_owner: MultiMeshInstance3D
var mm_index := -1
## The slot's transform in mm_owner's space, kept here (reading a MultiMesh back
## is a round trip to the RenderingServer, and nothing at all headless).
var slot_xf := Transform3D()
## A static collider standing in for it while it rests (switched off while knocked).
var collider: CollisionObject3D

# --- KnockWorld's bookkeeping --------------------------------------------------
var home := Transform3D()      ## global, where it belongs
var home_known := false
var body: RigidBody3D           ## only while it moves
var lying := false              ## knocked and still, off its spot
var knocked_at := -1.0
var moving_since := 0.0
var still_t := 0.0
var cell := Vector2i(1 << 30, 0)
var radius := 0.3               ## horizontal reach of the shape, as it stands now
var half_h := 0.3               ## half its height, as it stands now
var centre_g := Vector3.ZERO    ## the shape's centre, global, as it stands now
var ghost: StaticBody3D         ## a stand-in support while something knocked lies on it
var world: Node


## Makes `node` knockable: measures what it draws (Solid.wrap's way) for the
## shape. opts: cyl (bool), shrink (0.9), sound, collider (a body to switch off
## while knocked), center / size (override the measure).
static func add(node: Node3D, p_mass: float, p_sound: String = "wood", opts: Dictionary = {}) -> Knockable:
	var k := Knockable.new()
	k.name = "Knockable"
	k.mass = p_mass
	k.sound = p_sound
	k.shape_cyl = bool(opts.get("cyl", false))
	k.collider = opts.get("collider")
	var aabb := local_aabb(node)
	var shrink := float(opts.get("shrink", 0.9))
	k.size = opts.get("size", Vector3(maxf(aabb.size.x * shrink, 0.04), maxf(aabb.size.y, 0.04), maxf(aabb.size.z * shrink, 0.04)))
	k.center = opts.get("center", aabb.get_center() if aabb.size != Vector3.ZERO else Vector3(0, k.size.y * 0.5, 0))
	if k.shape_cyl:
		var d := maxf(k.size.x, k.size.z)
		k.size = Vector3(d, k.size.y, d)
	node.add_to_group(FarProxy.LIVE_GROUP)  # it moves: never merged into a far stand-in
	node.add_child(k)
	return k


## One Knockable per instance of a MultiMesh (instances are few: barrels, stools).
## opts.xforms: the instance transforms as set (else they are read back).
static func add_slots(mmi: MultiMeshInstance3D, p_mass: float, p_sound: String = "wood", opts: Dictionary = {}) -> Array:
	var out: Array = []
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null:
		return out
	var aabb := mm.mesh.get_aabb()
	var shrink := float(opts.get("shrink", 0.9))
	var sz: Vector3 = opts.get("size", Vector3(aabb.size.x * shrink, aabb.size.y, aabb.size.z * shrink))
	if bool(opts.get("cyl", false)):
		var d := maxf(sz.x, sz.z)
		sz = Vector3(d, sz.y, d)
	mmi.add_to_group(FarProxy.LIVE_GROUP)
	for i in mm.instance_count:
		var k := Knockable.new()
		k.name = "Knockable%d" % i
		k.mass = p_mass
		k.sound = p_sound
		k.shape_cyl = bool(opts.get("cyl", false))
		k.size = sz
		k.center = opts.get("center", aabb.get_center())
		k.mm_owner = mmi
		k.mm_index = i
		var xfs: Array = opts.get("xforms", [])
		k.slot_xf = xfs[i] if i < xfs.size() else mm.get_instance_transform(i)
		mmi.add_child(k)
		out.append(k)
	return out


## The box around everything `node` draws, in its own space (before or after it
## joins the tree).
static func local_aabb(node: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for gi in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if not (gi is MeshInstance3D) or (gi as MeshInstance3D).mesh == null:
			continue
		var m := gi as MeshInstance3D
		var b := _relative(node, m) * m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _enter_tree() -> void:
	if target == null and mm_owner == null:
		target = get_parent() as Node3D
	world = KnockWorld.of(self)
	if world:
		world.enlist(self)


func _exit_tree() -> void:
	if world and is_instance_valid(world):
		world.forget(self)
	world = null


## Where the mesh is now (global).
func get_xf() -> Transform3D:
	if mm_owner:
		return mm_owner.global_transform * slot_xf
	return target.global_transform if target else Transform3D()


func set_xf(g: Transform3D) -> void:
	if mm_owner:
		slot_xf = mm_owner.global_transform.affine_inverse() * g
		mm_owner.multimesh.set_instance_transform(mm_index, slot_xf)
	elif target:
		target.global_transform = g


func ready_to_enlist() -> bool:
	return is_inside_tree() and (mm_owner != null or target != null) and (mm_owner == null or mm_owner.multimesh != null)


## The body's pose for a mesh pose `g` (the shape's centre, no scale), and back.
func body_xf(g: Transform3D) -> Transform3D:
	return Transform3D(g.basis.orthonormalized(), g * center)


func mesh_xf(b: Transform3D) -> Transform3D:
	var s := home.basis.get_scale()
	return b * Transform3D(Basis.from_scale(s), -(s * center))


## The shape's extents in global units (the home scale applied).
func global_size() -> Vector3:
	return (size * home.basis.get_scale()).abs()


## Refreshes centre_g, radius and half_h for the mesh pose `g`.
func update_bounds(g: Transform3D) -> void:
	var b := body_xf(g)
	centre_g = b.origin
	var e := global_size() * 0.5
	# The shape's axis-aligned half extents after its rotation.
	var ax := b.basis
	var hx := absf(ax.x.x) * e.x + absf(ax.y.x) * e.y + absf(ax.z.x) * e.z
	var hy := absf(ax.x.y) * e.x + absf(ax.y.y) * e.y + absf(ax.z.y) * e.z
	var hz := absf(ax.x.z) * e.x + absf(ax.y.z) * e.y + absf(ax.z.z) * e.z
	radius = maxf(hx, hz) * (0.85 if shape_cyl else 0.8)
	half_h = hy
