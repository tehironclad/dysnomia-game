class_name ControlsHelp
extends PanelContainer
## F1: the controls, read from the InputMap itself, so this list can never
## disagree with the bindings (WP 7.4).

const ACTIONS := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump (triple jump in low gravity)"], ["sprint", "Sprint"], ["crouch_descend", "Crouch / descend (flying) · glass lift at the YUE Exchange: down to the lobby"],
	["look_left", "Look left (arrow keys / right stick: look while running)"], ["look_up", "Look up"],
	["toggle_fly", "Fly on / off (off in the air: you keep going, fall and land)"], ["toggle_camera", "First / third person"], ["interact", "Use: pylon Su · door: enter the hall · centre Beat · plinth WORLD · monolith: the Void · cabinet: dive in · pool or card table: sit down · fair stall: play (then the one button) · Swap Hall counter: swap on PulseX · YUE Exchange desk: Hong / Hung"],
	["inspect", "How is this drawn?"], ["open_field", "The Field (all territories)"],
	["field_search", "The Field: search QINGs (type; Up/Down pick, Enter fly there)"], ["field_next", "The Field: next result"], ["field_prev", "The Field: previous result"], ["field_warp", "The Field: warp to the selected QING"], ["field_zoom_in", "The Field: zoom in (arrow keys turn the globe)"], ["field_zoom_out", "The Field: zoom out"], ["flashlight", "Flashlight (headlights when driving)"],
	["wingsuit", "Base jump: wingsuit on / off (in freefall)"], ["parachute", "Base jump: open the canopy"],
	["vehicle_enter", "Vehicle pad: get in / out (W/S drive, A/D steer, Space hop or lift, Shift boost, Ctrl brake)"], ["vehicle_reset", "Vehicle: back on its wheels"],
	["chat", "Chat bar anywhere in the territory (Enter send, Esc close); in a hall or the Void: the board"], ["arcade_start", "Arcade, inside a cabinet: play a credit"], ["arcade_view", "Arcade, inside a cabinet: 3D world / classic screen"], ["table_shoot", "Pool, seated: hold for power, release to strike · fair games: throw / swing / shoot (or Use)"], ["table_hit", "Twenty-One, seated: hit"], ["table_stand", "Twenty-One, seated: stand"], ["table_view", "Seated at a table: overhead / table view"], ["table_lobby", "Seated at a table: the games list (challenge, accept, concede, pay)"], ["fair_post", "Fair game result: post your score to the room (one approval; checked by replay)"], ["bar_menu", "Bar menu (at the counter in Sunny's Pub)"], ["opportunities", "Opportunities: hot spots, leads in reach, crowns, streak"], ["guide", "Guide: the acts"], ["settings", "Settings"], ["toggle_debug", "Performance overlay"], ["controls_help", "This list"],
	["chat_history", "Room chat history (scroll; hover a line for its block)"], ["chat_quick_1", "Quick line 1 into the chat bar (2–4: more; Enter sends)"], ["chat_recall_prev", "Chat bar: recall the previous line"], ["chat_mode", "Chat bar: say (free) / post (on chain), when the presence server is up"], ["push_to_talk", "Push to talk (online voice; turn the mic on in Settings · Online & voice)"],
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
