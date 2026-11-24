class_name ControlsHelp
extends PanelContainer
## F1: the controls, read from the InputMap itself, so this list can never
## disagree with the bindings (WP 7.4).

const ACTIONS := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump (triple jump in low gravity)"], ["sprint", "Sprint"], ["crouch_descend", "Crouch / descend (flying)"],
	["look_left", "Look left (arrow keys / right stick: look while running)"], ["look_up", "Look up"],
	["toggle_fly", "Fly"], ["toggle_camera", "First / third person"], ["interact", "Use: pylon Su · door: enter the hall · centre Beat · plinth WORLD · monolith: the Void"],
	["inspect", "How is this drawn?"], ["open_field", "The Field (all territories)"], ["flashlight", "Flashlight (headlights when driving)"],
	["vehicle_enter", "Vehicle pad: get in / out (W/S drive, A/D steer, Space hop or lift, Shift boost, Ctrl brake)"], ["vehicle_reset", "Vehicle: back on its wheels"],
	["chat", "Speak (in a hall or the Void)"], ["arcade_start", "Arcade, inside a cabinet: play a credit"], ["arcade_view", "Arcade, inside a cabinet: 3D world / classic screen"], ["bar_menu", "Bar menu (at the counter in Sunny's Pub)"], ["opportunities", "Opportunities: hot spots, leads in reach, crowns, streak"], ["guide", "Guide: the acts"], ["settings", "Settings"], ["toggle_debug", "Performance overlay"], ["controls_help", "This list"],
]

var _text: Label


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.94
	add_theme_stylebox_override("panel", sb)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = "CONTROLS"
	col.add_child(title)
	_text = Label.new()
	_text.theme_type_variation = "MonoLabel"
	_text.add_theme_font_size_override("font_size", 13)
	col.add_child(_text)


static func key_of(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var names: PackedStringArray = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			names.append(OS.get_keycode_string(code))
		elif e is InputEventMouseButton:
			names.append("Mouse %d" % e.button_index)
	return " / ".join(names) if not names.is_empty() else "—"


static func lines() -> String:
	var out: PackedStringArray = []
	for a in ACTIONS:
		out.append("%-10s %s" % [key_of(a[0]), a[1]])
	out.append("%-10s %s" % ["Mouse", "Look"])
	out.append("%-10s %s" % ["Click", "Capture the mouse to look around"])
	out.append("%-10s %s" % ["Esc", "Release the mouse; close a panel"])
	return "\n".join(out)


func toggle() -> void:
	_text.text = lines()
	visible = not visible
