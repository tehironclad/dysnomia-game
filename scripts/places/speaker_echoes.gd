class_name SpeakerEchoes
extends Node3D
## Echoes: translucent holograms of the last few people who spoke on a board
## (room lines or Void lines read from the chain). Each wears the head its
## username asks for (AvatarHeads, name only: the log has no LAU name or
## symbol) and carries its last line and block above it. They are history made
## visible, not live players: the label says when they spoke.

const MAX := 6

var spots: Array = []  # [Transform3D] where echoes stand, filled in order
var _figures := {}  # speaker key → {node, label}
var _holo: StandardMaterial3D


func _ready() -> void:
	_holo = StandardMaterial3D.new()
	_holo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_holo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_holo.cull_mode = BaseMaterial3D.CULL_DISABLED
	_holo.albedo_color = Color(0.35, 0.8, 1.0, 0.28)
	_holo.emission_enabled = true
	_holo.emission = Color(0.3, 0.75, 1.0)
	_holo.emission_energy_multiplier = 0.6


static func speaker_key(l: Dictionary) -> String:
	return "%s|%s" % [String(l.get("name", "")), String(l.get("aura", ""))]


## Rebuilds from the board (chain order): the latest MAX distinct speakers.
func update_from(lines: Array) -> void:
	var latest := {}  # key → line (their newest)
	var order: Array = []
	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		var k := speaker_key(l)
		if not latest.has(k):
			latest[k] = l
			order.append(k)
			if order.size() >= mini(MAX, spots.size()):
				break
	for k in _figures.keys():
		if not latest.has(k):
			(_figures[k]["node"] as Node).queue_free()
			_figures.erase(k)
	for i in order.size():
		var k: String = order[i]
		var l: Dictionary = latest[k]
		if not _figures.has(k):
			_figures[k] = _make(l)
		var f: Dictionary = _figures[k]
		(f["node"] as Node3D).transform = spots[i]
		var nm: String = l["name"] if l["name"] != "" else "?"
		var badge := " ✓" if l.get("badge", "") == "og" else (" ⚠" if l.get("badge", "") == "imposter" else "")
		(f["label"] as Label3D).text = "%s%s · block %d\n%s" % [nm, badge, l["block"], String(l["text"]).left(80)]


func _make(l: Dictionary) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var av := HumanAvatar.new()
	av.name = "Avatar"
	root.add_child(av)
	var nm := String(l.get("name", ""))
	av.set_head(AvatarHeads.kind_for(nm, "", ""), AvatarHeads.accessories_for(nm, "", ""))
	for mi in av.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = _holo
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	av.extras.visible = false
	var lab := Label3D.new()
	lab.font = DeepFieldTheme.mono_font()
	lab.font_size = 26
	lab.pixel_size = 0.0042
	lab.width = 460.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color(0.75, 0.92, 1.0)
	lab.outline_size = 6
	lab.outline_modulate = Color(0, 0, 0, 0.8)
	lab.position = Vector3(0, 2.05, 0)
	root.add_child(lab)
	return {"node": root, "label": lab}
