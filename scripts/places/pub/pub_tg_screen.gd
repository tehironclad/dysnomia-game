class_name PubTgScreen
extends Node3D
## The TV on Sunny's Pub's back wall: the latest lines of Sunny's Pub on Telegram,
## as the game server's bridge relays them (Net.tg_lines, NetTg). Labelled on its face
## as Telegram, free, not on chain: a Telegram name is free text, never a LAU, so it
## always reads "<name> · Telegram" and never carries a ✓. With no server, or one that
## does not bridge Telegram, the screen is quietly dark (the pub's name, nothing else).
##
## A SubViewport (VIEW_PX) drawn on a quad; it re-renders only when the lines change.
## Type is the Deep Field sizes × TYPE_SCALE (fs), so on a 720p screen a line stays ≥ FS_MIN
## from the middle of the room (the screen is SIZE_M wide). tools/screenshot.gd --view=tv.

const SIZE_M := Vector2(4.2, 2.3625)
const VIEW_PX := Vector2i(800, 450)
const TYPE_SCALE := 2.1
const ROWS := 3
const TEXT_CHARS := 44  ## a line's text on the TV (the dock and its history show it all)
const TG_BLUE := Color("#7cc7ff")

var viewport: SubViewport
var _root: Control
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _foot: Label
var _idle: Label
var _dirty := true
var _frames := 0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = VIEW_PX
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	_build_face()
	# The set: a dark bezel and the screen (unshaded: it needs no light of its own).
	var bezel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE_M.x + 0.12, SIZE_M.y + 0.12, 0.08)
	bezel.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.03, 0.03, 0.035)
	bmat.roughness = 0.35
	bmat.metallic = 0.4
	bezel.material_override = bmat
	bezel.position = Vector3(0, 0, -0.03)
	bezel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bezel)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = SIZE_M
	screen.mesh = q
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_texture = viewport.get_texture()
	smat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = smat
	screen.position = Vector3(0, 0, 0.012)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.name = "Screen"
	add_child(screen)
	var n := _net()
	if n != null and n.has_signal("telegram_changed"):
		n.telegram_changed.connect(func(): _dirty = true)
	refresh()


func _net() -> Node:
	return get_node_or_null("/root/Net") if is_inside_tree() else null


static func fs(base: int) -> int:
	return int(round(float(base) * TYPE_SCALE))


func _label(size: int, color: Color, mono: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", DeepFieldTheme.mono_font() if mono else DeepFieldTheme.display_font())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_face() -> void:
	_root = Control.new()
	_root.size = Vector2(VIEW_PX)
	_root.theme = DeepFieldTheme.get_theme()
	viewport.add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.04)
	bg.size = Vector2(VIEW_PX)
	_root.add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(TG_BLUE, 0.85)
	stripe.size = Vector2(VIEW_PX.x, 8)
	_root.add_child(stripe)
	var col := VBoxContainer.new()
	col.position = Vector2(24, 16)
	col.size = Vector2(VIEW_PX.x - 48, VIEW_PX.y - 24)
	col.add_theme_constant_override("separation", 8)
	_root.add_child(col)
	_title = _label(fs(DeepFieldTheme.FS_MIN), TG_BLUE)
	col.add_child(_title)
	_sub = _label(fs(DeepFieldTheme.FS_MIN), DeepFieldTheme.MUTED, true)
	col.add_child(_sub)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list)
	_foot = _label(fs(DeepFieldTheme.FS_MIN), DeepFieldTheme.DIM, true)
	col.add_child(_foot)
	_idle = _label(fs(DeepFieldTheme.FS_DISPLAY), Color(1.0, 0.78, 0.4, 0.35))
	_idle.text = "SUNNY'S PUB"
	_idle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_idle.size = Vector2(VIEW_PX)
	_root.add_child(_idle)


## Pure: the rows the screen draws: the newest `n` lines, oldest first, each
## {who, text, age, color}; `speaker` is NetTg.speaker's chain-name callable.
static func screen_rows(lines: Array, speaker: Callable, n: int = ROWS) -> Array:
	var out: Array = []
	for l in lines.slice(maxi(0, lines.size() - n)):
		out.append({"who": NetTg.speaker(l, speaker), "text": NetTg.clip(String(l.get("text", "")), TEXT_CHARS),
			"age": NetTg.clock(int(l.get("ts", 0))) + (" · edited" if bool(l.get("edited", false)) else ""),
			"color": TG_BLUE if String(l.get("src", "")) == "tg" else (DeepFieldTheme.ICE if String(l.get("src", "")) == "game" else Color("#ffd27a"))})
	return out


func refresh() -> void:
	_dirty = false
	var n := _net()
	var on: bool = n != null and n.has_method("telegram_available") and n.telegram_available()
	_idle.visible = not on
	for c in [_title, _sub, _list]:
		(c as Control).visible = on
	_foot.visible = false  # the dock and the bar say how to write; the TV stays big enough to read
	for c in _list.get_children():
		c.queue_free()
	if on:
		_title.text = "%s · TELEGRAM" % NetTg.GROUP.to_upper()
		_sub.text = "free · not on chain"
		var rows := screen_rows(n.tg_lines, func(w: String) -> String: return n.names.display(w) if n.names else NetProto.short_wallet(w))
		if rows.is_empty():
			var e := _label(fs(DeepFieldTheme.FS_MIN), DeepFieldTheme.MUTED)
			e.text = "Nothing said yet. Lines show here as people write there."
			_list.add_child(e)
		for r in rows:
			var rl := RichTextLabel.new()
			rl.bbcode_enabled = true
			rl.fit_content = true
			rl.scroll_active = false
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size = Vector2(VIEW_PX.x - 48, 0)
			rl.add_theme_font_size_override("normal_font_size", fs(DeepFieldTheme.FS_MIN))
			rl.add_theme_font_size_override("bold_font_size", fs(DeepFieldTheme.FS_MIN))
			rl.text = "[b][color=#%s]%s[/color][/b]  %s  [color=#5d6578]%s[/color]" % [(r["color"] as Color).to_html(false),
				ChatLines.esc(r["who"]), ChatLines.esc(r["text"]), ChatLines.esc(r["age"])]
			_list.add_child(rl)
		_foot.text = "Write to it from the chat bar outside: %s, then %s to TG (signed-in players) · %s: these lines in the chat dock" % [
			ControlsHelp.key_of("chat"), ControlsHelp.key_of("chat_mode"), ControlsHelp.key_of("chat_source")]
	_frames = 3


func _process(_delta: float) -> void:
	if _dirty:
		refresh()
	if _frames > 0:
		_frames -= 1  # re-render a few frames after a change (labels lay out first)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
