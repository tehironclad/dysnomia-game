class_name CardTable3D
extends Node3D
## A round card table. It lays out the room's latest Twenty-One hands (from
## the replayed lines). Two seats on the near arc (player 0 on the right of
## the dealer's view, player 1 on the left), each with a stool, a name plate,
## the hand on the felt in front of it and the stake in chips; across the
## table the dealer's shoe, which says which block dealt the cards. Seated
## play (CardSeat) adds the HIT / STAND plates in front of your seat.

const TOP := 0.78
const SEAT_ANGLE := 0.62  # radians either side of +Z
const SEAT_R := 1.38  # where a seated player's eye is, from the centre
const HAND_R := 0.45
const BUTTON_R := 0.76
const CARD := Vector2(0.1, 0.14)
const CARD_GAP := 0.112
const SHOE := Vector3(0.0, TOP, -0.56)
const DEAL_TIME := 0.38
const DEAL_STAGGER := 0.22

var _cards_root: Node3D
var _label: Label3D
var _shown := [[], []]  # card ids on the felt per seat
var _plates: Array = []  # Label3D per seat
var _totals: Array = []  # Label3D per seat
var _chips: Array = []  # Node3D per seat
var _rings: Array = []  # glowing ring per seat (whose turn)
var _dealer: Label3D
var _buttons := {}  # "hit" | "stand" → {node, mat, label, rect: Rect2 in the seat's frame}
var _button_seat := -1
var _face_mat: StandardMaterial3D
var _back_mat: StandardMaterial3D


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
	_face_mat = StandardMaterial3D.new()
	_face_mat.albedo_color = Color(0.97, 0.96, 0.92)
	_face_mat.roughness = 0.5
	_back_mat = StandardMaterial3D.new()
	_back_mat.albedo_color = Color(0.1, 0.2, 0.55)
	_back_mat.roughness = 0.5
	_build_dealer(wood)
	for i in 2:
		_build_seat(i, wood)
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


# --- Layout (table-local, pure) -------------------------------------------------

static func seat_dir(i: int) -> Vector3:
	var a := SEAT_ANGLE if i == 0 else -SEAT_ANGLE
	return Vector3(sin(a), 0.0, cos(a))


## The seat's frame on the felt: origin at the table's centre, +Z toward the
## seat, +X to the seated player's right.
static func seat_basis(i: int) -> Basis:
	var z := seat_dir(i)
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z).orthonormalized()


## Where card k of n lies in front of seat i (table-local, on the felt).
static func card_spot(i: int, k: int, n: int) -> Vector3:
	var b := seat_basis(i)
	var x := (k - (n - 1) * 0.5) * CARD_GAP
	return b * Vector3(x, TOP + 0.003 + k * 0.0012, HAND_R)


## The seated eye: table-local transform looking at the hand and the dealer.
static func seat_eye(i: int) -> Transform3D:
	var at := seat_dir(i) * SEAT_R + Vector3.UP * 1.2
	var look := seat_dir(i) * 0.12 + Vector3.UP * TOP
	return Transform3D(Basis.looking_at(look - at, Vector3.UP), at)


## A point on the felt in seat i's frame (x right, z toward the seat) → "hit" / "stand" / "".
static func button_at(i: int, local: Vector3) -> String:
	var p := seat_basis(i).inverse() * local
	for k in ["hit", "stand"]:
		if _button_rect(k).has_point(Vector2(p.x, p.z)):
			return k
	return ""


static func _button_rect(kind: String) -> Rect2:
	var cx := -0.15 if kind == "hit" else 0.15
	return Rect2(Vector2(cx - 0.12, BUTTON_R - 0.06), Vector2(0.24, 0.12))


# --- Building -------------------------------------------------------------------

func _build_dealer(wood: StandardMaterial3D) -> void:
	var shoe := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.09, 0.24)
	shoe.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.04, 0.04, 0.05)
	sm.metallic = 0.4
	sm.roughness = 0.3
	shoe.material_override = sm
	shoe.position = SHOE + Vector3(0, 0.045, -0.04)
	shoe.rotation.x = -0.18
	add_child(shoe)
	var trim := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.17, 0.012, 0.012)
	trim.mesh = tb
	trim.material_override = _glow(Color(1.0, 0.8, 0.3), 2.0)
	trim.position = SHOE + Vector3(0, 0.07, 0.08)
	add_child(trim)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.1, 0.05, 0.14)
	deck.mesh = dm
	deck.material_override = _back_mat
	deck.position = SHOE + Vector3(0, 0.06, -0.05)
	deck.rotation.x = -0.18
	add_child(deck)
	_dealer = Label3D.new()
	_dealer.font = DeepFieldTheme.mono_font()
	_dealer.font_size = 44
	_dealer.pixel_size = 0.0012
	_dealer.modulate = Color(1.0, 0.85, 0.45)
	_dealer.outline_size = 8
	_dealer.outline_modulate = Color(0, 0, 0, 0.8)
	_dealer.rotation_degrees.x = -25.0  # an upright card behind the shoe, leaning back
	_dealer.position = Vector3(0, TOP + 0.24, -0.7)
	_dealer.text = "DEALT BY THE CHAIN"
	add_child(_dealer)
	var board := MeshInstance3D.new()  # the sign's board and its post
	var bb := BoxMesh.new()
	bb.size = Vector3(0.6, 0.15, 0.01)
	board.mesh = bb
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.04)
	dark.roughness = 0.4
	board.material_override = dark
	board.rotation_degrees.x = -25.0
	board.position = _dealer.position + Basis(Vector3.RIGHT, deg_to_rad(-25.0)) * Vector3(0, 0, -0.008)
	add_child(board)
	var post := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.02, 0.2, 0.02)
	post.mesh = pb
	post.material_override = dark
	post.position = Vector3(0, TOP + 0.1, -0.74)
	add_child(post)


func _build_seat(i: int, wood: StandardMaterial3D) -> void:
	var b := seat_basis(i)
	var stool := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.16
	cm.height = 0.08
	stool.mesh = cm
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.12, 0.05, 0.05)
	leather.roughness = 0.6
	stool.material_override = leather
	stool.position = seat_dir(i) * 1.45 + Vector3.UP * 0.66
	add_child(stool)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.12
	pm.height = 0.62
	post.mesh = pm
	post.material_override = wood
	post.position = seat_dir(i) * 1.45 + Vector3.UP * 0.31
	add_child(post)
	# Whose turn: a thin lit frame round the hand's place on the felt.
	var ring := Node3D.new()
	ring.basis = b
	ring.position = Vector3(0, TOP + 0.001, 0)
	var lit := _glow(Color(1.0, 0.82, 0.35), 1.3)
	for e in [[Vector3(0.7, 0.002, 0.007), Vector3(0, 0, HAND_R - 0.1)], [Vector3(0.7, 0.002, 0.007), Vector3(0, 0, HAND_R + 0.1)],
			[Vector3(0.007, 0.002, 0.2), Vector3(-0.35, 0, HAND_R)], [Vector3(0.007, 0.002, 0.2), Vector3(0.35, 0, HAND_R)]]:
		var mi := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = e[0]
		mi.mesh = em
		mi.material_override = lit
		mi.position = e[1]
		ring.add_child(mi)
	ring.visible = false
	add_child(ring)
	_rings.append(ring)
	var plate := Label3D.new()
	plate.font = DeepFieldTheme.display_font()
	plate.font_size = 44
	plate.pixel_size = 0.0011
	plate.modulate = Color(0.95, 0.92, 0.85)
	plate.outline_size = 6
	plate.outline_modulate = Color(0, 0, 0, 0.7)
	plate.basis = b * Basis(Vector3.RIGHT, -PI * 0.5)
	plate.position = b * Vector3(0, TOP + 0.002, 0.61)
	add_child(plate)
	_plates.append(plate)
	var total := Label3D.new()
	total.font = DeepFieldTheme.display_font()
	total.font_size = 64
	total.pixel_size = 0.0015
	total.modulate = Color(1.0, 0.84, 0.4)
	total.outline_size = 10
	total.outline_modulate = Color(0, 0, 0, 0.85)
	total.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	total.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM  # a note line grows upward, off the cards
	total.position = b * Vector3(0, TOP + 0.09, HAND_R - 0.15)
	add_child(total)
	_totals.append(total)
	var chips := Node3D.new()
	chips.basis = b
	add_child(chips)
	_chips.append(chips)


static func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


# --- State ----------------------------------------------------------------------

func set_caption(text: String) -> void:
	_label.text = text


## Seated play hides the floating caption (the overlay says it instead).
func show_caption(on: bool) -> void:
	if _label:
		_label.visible = on


## Lays out two hands of card ids (Duel21). With `animate`, cards that weren't
## on the felt before fly out of the shoe, one after another.
func show_hands(hands: Array, animate: bool = false) -> void:
	var same := hands.size() == 2 and _shown.size() == 2
	var keep := [0, 0]
	if same:
		for p in 2:
			var a: Array = _shown[p]
			var h: Array = hands[p]
			var k := 0
			while k < a.size() and k < h.size() and int(a[k]) == int(h[k]):
				k += 1
			keep[p] = k if k == a.size() else 0  # a hand that isn't an extension is redrawn
	for c in _cards_root.get_children():
		c.queue_free()
	var order := 0
	for p in mini(2, hands.size()):
		var hand: Array = hands[p]
		for i in hand.size():
			var spot := card_spot(p, i, hand.size())
			var fly := animate and i >= int(keep[p])
			_card(int(hand[i]), spot, p, fly, order * DEAL_STAGGER)
			if fly:
				order += 1
	_shown = [(hands[0] as Array).duplicate() if hands.size() > 0 else [], (hands[1] as Array).duplicate() if hands.size() > 1 else []]


## Name plates, totals and whose turn: seats[i] = {name, total (int or -1), turn: bool, note}.
func set_seats(seats: Array) -> void:
	for i in 2:
		var s: Dictionary = seats[i] if i < seats.size() else {}
		(_plates[i] as Label3D).text = String(s.get("name", "open seat"))
		var t := int(s.get("total", -1))
		# The note goes on its own line above: "24 BUST" side by side ran into the other seat's total.
		var note := String(s.get("note", "")).strip_edges()
		(_totals[i] as Label3D).text = (("%s\n%d" % [note, t]) if note != "" else str(t)) if t >= 0 else ""
		(_rings[i] as Node3D).visible = bool(s.get("turn", false))


## The dealer plaque across the table (which block dealt).
func set_dealer(text: String) -> void:
	_dealer.text = text


## Chips in front of each seat: n chips each (0 = none), and the stake's text.
func set_chips(n: int, text: String) -> void:
	for i in 2:
		var root: Node3D = _chips[i]
		for c in root.get_children():
			c.queue_free()
		if n <= 0:
			continue
		var cols := [Color(0.85, 0.1, 0.12), Color(0.1, 0.35, 0.85), Color(0.08, 0.55, 0.25), Color(0.05, 0.05, 0.05)]
		for k in mini(n, 12):
			var chip := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.02
			cm.bottom_radius = 0.02
			cm.height = 0.007
			cm.radial_segments = 16
			chip.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = cols[(k / 4) % cols.size()]
			m.roughness = 0.35
			chip.material_override = m
			var stack := k / 4
			chip.position = Vector3(0.3 + stack * 0.045, TOP + 0.004 + (k % 4) * 0.0072, HAND_R + 0.12)
			root.add_child(chip)
		var l := Label3D.new()
		l.text = text
		l.font = DeepFieldTheme.mono_font()
		l.font_size = 32
		l.pixel_size = 0.0014
		l.modulate = Color(1.0, 0.9, 0.6)
		l.rotation_degrees.x = -90.0
		l.position = Vector3(0.34, TOP + 0.002, HAND_R + 0.2)
		root.add_child(l)


## HIT / STAND plates in front of seat `i` (-1 hides them).
func show_buttons(i: int, enabled: bool = true) -> void:
	if _buttons.is_empty():
		_make_buttons()
	_button_seat = i
	for k in _buttons:
		var b: Dictionary = _buttons[k]
		var n: Node3D = b["node"]
		n.visible = i >= 0
		if i < 0:
			continue
		var r: Rect2 = _button_rect(k)
		n.basis = seat_basis(i)
		n.position = seat_basis(i) * Vector3(r.get_center().x, TOP + 0.004, r.get_center().y)
		var c: Color = b["color"]
		(b["mat"] as StandardMaterial3D).albedo_color = c if enabled else c.darkened(0.7)
		(b["mat"] as StandardMaterial3D).emission = c if enabled else c.darkened(0.8)
		(b["label"] as Label3D).modulate = Color(0.02, 0.02, 0.02) if enabled else Color(0.5, 0.5, 0.5)


## Lights the plate under the mouse.
func hover_button(kind: String) -> void:
	for k in _buttons:
		(_buttons[k]["mat"] as StandardMaterial3D).emission_energy_multiplier = 2.4 if k == kind else 0.9


func _make_buttons() -> void:
	for k in ["hit", "stand"]:
		var n := Node3D.new()
		add_child(n)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var r: Rect2 = _button_rect(k)
		bm.size = Vector3(r.size.x, 0.008, r.size.y)
		mi.mesh = bm
		var c := Color(0.35, 1.0, 0.55) if k == "hit" else Color(1.0, 0.75, 0.3)
		var m := _glow(c, 0.9)
		mi.material_override = m
		n.add_child(mi)
		var l := Label3D.new()
		l.text = k.to_upper()
		l.font = DeepFieldTheme.display_font()
		l.font_size = 64
		l.pixel_size = minf((r.size.x - 0.04) / maxf(1.0, l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x), (r.size.y - 0.03) / l.font.get_height(64))
		l.outline_size = 0
		l.rotation_degrees.x = -90.0
		l.position = Vector3(0, 0.006, 0)
		n.add_child(l)
		n.visible = false
		_buttons[k] = {"node": n, "mat": m, "label": l, "color": c}


func _card(c: int, at: Vector3, seat: int, fly: bool, delay: float) -> void:
	var n := Node3D.new()
	_cards_root.add_child(n)
	# Face toward the seat: the card's bottom edge on the seat's side.
	var face := seat_basis(seat)
	var front := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = CARD
	front.mesh = q
	front.material_override = _face_mat
	front.rotation_degrees.x = -90.0
	n.add_child(front)
	var back := MeshInstance3D.new()
	back.mesh = q
	back.material_override = _back_mat
	back.rotation_degrees.x = 90.0
	back.position.y = -0.0005
	n.add_child(back)
	var red := c / 13 == 1 or c / 13 == 2
	var ink := Color(0.75, 0.05, 0.08) if red else Color(0.05, 0.05, 0.05)
	var l := Label3D.new()
	l.text = Duel21.card_name(c)
	l.font_size = 56
	l.pixel_size = 0.00125 if c % 13 != 9 else 0.00098  # "10" is a glyph wider
	l.modulate = ink
	l.outline_size = 0
	l.rotation_degrees.x = -90.0
	l.position = Vector3(0, 0.0008, 0.005)
	n.add_child(l)
	var corner := Label3D.new()
	corner.text = Duel21.RANKS[c % 13]
	corner.font_size = 40
	corner.pixel_size = 0.0007
	corner.modulate = ink
	corner.outline_size = 0
	corner.rotation_degrees.x = -90.0
	corner.position = Vector3(-0.034, 0.0008, -0.052)
	n.add_child(corner)
	var tilt := Basis(Vector3.UP, (float((c * 37) % 9) - 4.0) * 0.006)  # a hand-dealt look
	var end := Transform3D(face * tilt, at)
	if not fly:
		n.transform = end
		return
	# From the shoe, face down, flipping over as it lands.
	var start := Transform3D(seat_basis(seat) * Basis(Vector3.FORWARD, PI), SHOE + Vector3(0, 0.12, 0.05))
	n.transform = start
	n.visible = delay <= 0.0
	var tw := n.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): n.visible = true)
	tw.tween_method(func(u: float):
		var e := u * u * (3.0 - 2.0 * u)
		var p := start.origin.lerp(end.origin, e) + Vector3.UP * sin(u * PI) * 0.14
		var qa := start.basis.get_rotation_quaternion()
		var qb := end.basis.get_rotation_quaternion()
		n.transform = Transform3D(Basis(qa.slerp(qb, e)), p), 0.0, 1.0, DEAL_TIME)
