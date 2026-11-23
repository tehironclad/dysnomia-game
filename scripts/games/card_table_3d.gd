class_name CardTable3D
extends Node3D
## A round card table. It lays out the room's latest Twenty-One hands (from
## the replayed lines): player 0's cards on the near side, player 1's across.

const TOP := 0.78

var _cards_root: Node3D
var _label: Label3D


func build() -> void:
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.32, 0.06, 0.08)
	felt.roughness = 0.95
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.13, 0.06)
	wood.roughness = 0.4
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.95
	cm.bottom_radius = 0.95
	cm.height = 0.05
	cm.radial_segments = 48
	top.mesh = cm
	top.material_override = felt
	top.position.y = TOP - 0.025
	add_child(top)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.04
	tm.rings = 48
	rim.mesh = tm
	rim.material_override = wood
	rim.position.y = TOP
	add_child(rim)
	var leg := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.1
	lc.bottom_radius = 0.35
	lc.height = TOP - 0.05
	leg.mesh = lc
	leg.material_override = wood
	leg.position.y = (TOP - 0.05) * 0.5
	add_child(leg)
	_cards_root = Node3D.new()
	add_child(_cards_root)
	_label = Label3D.new()
	_label.font = DeepFieldTheme.mono_font()
	_label.font_size = 28
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, TOP + 0.9, 0)
	_label.modulate = Color(1.0, 0.9, 0.8)
	add_child(_label)
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 1.0
	sh.height = TOP + 0.05
	cs.shape = sh
	cs.position.y = (TOP + 0.05) * 0.5
	body.add_child(cs)


func set_caption(text: String) -> void:
	_label.text = text


## Lays out two hands of card ids (Duel21).
func show_hands(hands: Array) -> void:
	for c in _cards_root.get_children():
		c.queue_free()
	for p in hands.size():
		var hand: Array = hands[p]
		var side := 1.0 if p == 0 else -1.0
		for i in hand.size():
			var x := (i - (hand.size() - 1) * 0.5) * 0.14
			_card(int(hand[i]), Vector3(x * side, TOP + 0.003 + i * 0.001, side * 0.45), 0.0 if p == 0 else PI)


func _card(c: int, at: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.position = at
	n.rotation.y = yaw
	_cards_root.add_child(n)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.14)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.92)
	mi.material_override = m
	mi.rotation_degrees.x = -90.0
	n.add_child(mi)
	var l := Label3D.new()
	l.text = Duel21.card_name(c)
	l.font_size = 48
	l.pixel_size = 0.0012
	l.modulate = Color(0.75, 0.05, 0.08) if (c / 13 == 1 or c / 13 == 2) else Color(0.05, 0.05, 0.05)
	l.rotation_degrees.x = -90.0
	l.position = Vector3(0, 0.002, 0)
	n.add_child(l)
