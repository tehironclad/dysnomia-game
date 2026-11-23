class_name BarColumns
extends Node3D
## The field of bars (WP 5.2): one column per player with bars here, on an arc
## behind the Core (seen past the Room from the arrival point), ordered by Hypobar (the board from TerritoryState:
## YUE.Bar(QING) over known players, so a floor). Height is log10(Hypobar);
## the leader wears a crown. A column that grew since the last read flashes.
## Columns are the same for every viewer; only the small "YOU" tag is personal.

const MAX_COLUMNS := 24
const RADIUS := 22.0
const ARC_FROM := 196.0  # 270° is straight behind the Room (-Z)
const ARC_TO := 344.0

var _cols := {}  # wallet → {root, body, mat, label, crown, last: PackedInt64Array, flash}
var _tint := Color("#7fd3ff")


func setup(tint: Color) -> void:
	_tint = tint


static func height_for(hypobar: PackedInt64Array) -> float:
	if BigInt.is_zero(hypobar):
		return 0.15
	return clampf(0.5 + 1.3 * BigInt.log10(hypobar), 0.5, 16.0)


static func short(wallet: String) -> String:
	return "%s…%s" % [wallet.left(6), wallet.right(4)]


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
		# The leader stands straight behind the Room; the rest alternate outwards.
		var slot := 0.5 + (0.5 if i % 2 == 1 else -0.5) * ceilf(i / 2.0) / ceilf(maxf(1.0, n - 1) / 2.0)
		var a := deg_to_rad(lerpf(ARC_FROM, ARC_TO, slot))
		c["root"].position = Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		var h := height_for(row["hypobar"])
		var body: MeshInstance3D = c["body"]
		body.scale = Vector3(1.0, h, 1.0)
		body.position.y = h * 0.5
		var hb: PackedInt64Array = row["hypobar"]
		var grew: bool = not (c["last"] as PackedInt64Array).is_empty() and BigInt.cmp(hb, c["last"]) > 0
		c["last"] = hb
		if grew:
			c["flash"] = 1.0
		var lab: Label3D = c["label"]
		lab.text = "#%d %s\n%s Hypobar%s" % [i + 1, short(w), TokenFormat.group(BigInt.to_decimal(hb)),
			"\nYOU" if me != "" and w == me else ""]
		lab.position.y = h + 1.1
		var crown: Node3D = c["crown"]
		crown.visible = i == 0
		crown.position.y = h + 0.35
	for w in _cols.keys():
		if not keep.has(w):
			(_cols[w]["root"] as Node).queue_free()
			_cols.erase(w)


func _make(wallet: String) -> Dictionary:
	var root := Node3D.new()
	root.name = "Col_" + wallet.substr(2, 8)
	add_child(root)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.34
	cyl.height = 1.0
	cyl.radial_segments = 8
	body.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _tint
	mat.emission_enabled = true
	mat.emission = _tint
	mat.emission_energy_multiplier = 1.4
	body.material_override = mat
	root.add_child(body)
	var lab := Label3D.new()
	lab.font = DeepFieldTheme.mono_font()
	lab.font_size = 36
	lab.pixel_size = 0.01
	lab.modulate = DeepFieldTheme.INK
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(lab)
	var crown := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.32
	tor.outer_radius = 0.46
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
	return {"root": root, "body": body, "mat": mat, "label": lab, "crown": crown, "last": PackedInt64Array(), "flash": 0.0}


func _process(delta: float) -> void:
	for w in _cols:
		var c: Dictionary = _cols[w]
		if c["flash"] > 0.0:
			c["flash"] = maxf(0.0, c["flash"] - delta * 0.6)
			(c["mat"] as StandardMaterial3D).emission_energy_multiplier = 1.4 + 4.0 * c["flash"]
		(c["crown"] as Node3D).rotation.y += delta * 0.8
