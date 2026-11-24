class_name BarColumns
extends Node3D
## The skyline (WP 5.2, grown up): one tower per player with bars here, on two
## staggered rings behind the Core. The skyline IS the board: a tower's height
## is that player's Hypobar at this QING (log scale, 3 m floors; YUE.Bar over
## known players, so a floor), its lit windows follow the territory's energy
## (Epibar total), the leader's tower carries a crown beacon, and a tower that
## grew since the last read flashes. Same for every viewer; only the small
## "YOU" tag is personal.

const MAX_COLUMNS := 24
const RINGS := [36.0, 43.0]
const ARC_FROM := 200.0  # 270° is straight behind the Room (-Z)
const ARC_TO := 340.0
const FLOOR_M := 3.0
const TOWER_SHADER := preload("res://assets/shaders/tower.gdshader")

var _cols := {}  # wallet → {root, body, mat, label, crown, beacon, last, flash}
var _tint := Color("#7fd3ff")
var _height_at: Callable  # (x, z) → ground height in this node's space
var energy := 0.0


func setup(tint: Color, height_at: Callable = Callable()) -> void:
	_tint = tint
	_height_at = height_at


## Floors for a Hypobar (1 floor ≈ every 0.7 of an order of magnitude).
static func floors_for(hypobar: PackedInt64Array) -> int:
	if BigInt.is_zero(hypobar):
		return 0
	return clampi(int(ceil(BigInt.log10(hypobar) * 1.4)), 1, 16)


static func height_for(hypobar: PackedInt64Array) -> float:
	var f := floors_for(hypobar)
	return 0.15 if f == 0 else f * FLOOR_M


static func short(wallet: String) -> String:
	return "%s…%s" % [wallet.left(6), wallet.right(4)]


func set_energy(e: float) -> void:
	energy = e
	for w in _cols:
		(_cols[w]["mat"] as ShaderMaterial).set_shader_parameter("energy", e)


## Rebuilds from the board ([{wallet, yue, hypobar, epibar}] sorted desc).
func update_board(board: Array, block: int, me: String = "") -> void:
	var rows: Array = board.slice(0, MAX_COLUMNS)
	var keep := {}
	var n := rows.size()
	for i in n:
		var row: Dictionary = rows[i]
		var w: String = row["wallet"]
		keep[w] = true
		var c: Dictionary = _cols.get(w, {})
		if c.is_empty():
			c = _make(w)
			_cols[w] = c
		# The leader stands straight behind the Room; the rest alternate outwards,
		# every other one on the outer ring.
		var slot := 0.5 + (0.5 if i % 2 == 1 else -0.5) * ceilf(i / 2.0) / ceilf(maxf(1.0, n - 1) / 2.0)
		var a := deg_to_rad(lerpf(ARC_FROM, ARC_TO, slot))
		var r: float = RINGS[0] if i % 2 == 0 or n <= 3 else RINGS[1]
		var at := Vector3(cos(a) * r, 0.0, sin(a) * r)
		at.y = _height_at.call(at.x, at.z) - 0.5 if _height_at.is_valid() else 0.0
		c["root"].position = at
		c["root"].rotation.y = -a + PI * 0.5
		var hb: PackedInt64Array = row["hypobar"]
		var h := height_for(hb)
		var width := 5.0 if i == 0 else 3.6
		var body: MeshInstance3D = c["body"]
		body.scale = Vector3(width, h, width)
		body.position.y = h * 0.5
		var solid: StaticBody3D = c["solid"]
		((solid.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(width, h, width)
		var podium: MeshInstance3D = c["root"].get_node("Podium")
		podium.scale = Vector3(width + 1.3, 1.7, width + 1.3)
		podium.position.y = 0.85
		var band: MeshInstance3D = c["root"].get_node("Band")
		band.scale = Vector3(width + 1.34, 0.06, width + 1.34)
		band.position.y = 1.4
		solid.position.y = h * 0.5
		var grew: bool = not (c["last"] as PackedInt64Array).is_empty() and BigInt.cmp(hb, c["last"]) > 0
		c["last"] = hb
		if grew:
			c["flash"] = 1.0
		var lab: Label3D = c["label"]
		lab.text = "#%d %s\n%s Hypobar · %d floor%s%s" % [i + 1, short(w), TokenFormat.group(BigInt.to_decimal(hb)),
			floors_for(hb), "" if floors_for(hb) == 1 else "s", "\nYOU" if me != "" and w == me else ""]
		lab.position.y = h + 2.4
		var crown: Node3D = c["crown"]
		crown.visible = i == 0
		crown.position.y = h + 0.6
		var beacon: Node3D = c["beacon"]
		beacon.visible = i == 0
		beacon.position.y = h + 0.6
	for w in _cols.keys():
		if not keep.has(w):
			(_cols[w]["root"] as Node).queue_free()
			_cols.erase(w)


## A player's tower here: {root, height, width} (its root stands on the ground,
## +Z pointing away from the Core), or {} when they have no bars here.
func tower_of(wallet: String) -> Dictionary:
	var c: Dictionary = _cols.get(wallet.to_lower(), _cols.get(wallet, {}))
	if c.is_empty() or not is_instance_valid(c["root"]):
		return {}
	var body: MeshInstance3D = c["body"]
	return {"root": c["root"], "height": body.scale.y, "width": body.scale.x}


func _make(wallet: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Tower_" + wallet.substr(2, 8)
	add_child(root)
	var body := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3.ONE
	body.mesh = bx
	var mat := ShaderMaterial.new()
	mat.shader = TOWER_SHADER
	mat.set_shader_parameter("tint", _tint)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("seed", float(BigInt.mod_int(BigInt.from_hex(wallet), 997)))
	body.material_override = mat
	root.add_child(body)
	var solid := Solid.box(root, Vector3.ONE, Vector3.ZERO)  # resized with the tower
	# The tower's base: a dark podium and a lit band, sized with the tower
	# (detail only: the height is the number).
	var podium := MeshInstance3D.new()
	podium.name = "Podium"
	podium.mesh = bx
	podium.material_override = CoreDressing.dark_metal()
	root.add_child(podium)
	var band := MeshInstance3D.new()
	band.name = "Band"
	band.mesh = bx
	band.material_override = CoreDressing.glow(_tint, 1.6)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(band)
	var lab := Label3D.new()
	lab.font = DeepFieldTheme.mono_font()
	lab.font_size = 44
	lab.pixel_size = 0.012
	lab.modulate = DeepFieldTheme.INK
	lab.outline_size = 8
	lab.outline_modulate = Color(0, 0, 0, 0.8)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(lab)
	var crown := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.4
	tor.outer_radius = 1.65
	crown.mesh = tor
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color("#ffd27a")
	cm.emission_enabled = true
	cm.emission = Color("#ffd27a")
	cm.emission_energy_multiplier = 2.5
	crown.material_override = cm
	crown.visible = false
	root.add_child(crown)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color("#ffd27a")
	beacon.light_energy = 2.0
	beacon.omni_range = 14.0
	beacon.visible = false
	root.add_child(beacon)
	return {"root": root, "body": body, "solid": solid, "mat": mat, "label": lab, "crown": crown, "beacon": beacon, "last": PackedInt64Array(), "flash": 0.0}


func _process(delta: float) -> void:
	for w in _cols:
		var c: Dictionary = _cols[w]
		if c["flash"] > 0.0:
			c["flash"] = maxf(0.0, c["flash"] - delta * 0.6)
			(c["mat"] as ShaderMaterial).set_shader_parameter("flash", c["flash"])
		(c["crown"] as Node3D).rotation.y += delta * 0.8
