class_name ChatInputGuard
extends RefCounted
## While the chat bar has the keyboard, no gameplay action may fire. Movement,
## vehicles, base jumping, rides and the arcade poll Input.is_action_pressed,
## which sees keys even when a LineEdit has focus; so the guard lifts the
## events off every action except the UI's own (ui_*) and the chat's (chat*),
## releases any held action, and puts every event back on restore. Nothing is
## saved to disk: the InputMap in memory is the only thing touched.

static var _saved := {}  # action → Array[InputEvent]


static func kept(action: String) -> bool:
	return action.begins_with("ui_") or action.begins_with("chat")


static func is_suspended() -> bool:
	return not _saved.is_empty()


static func suspend() -> void:
	if is_suspended():
		return
	for a in InputMap.get_actions():
		var action := String(a)
		if kept(action):
			continue
		var evs: Array = InputMap.action_get_events(action)
		if evs.is_empty():
			continue
		_saved[action] = evs.duplicate()
		InputMap.action_erase_events(action)
		if Input.is_action_pressed(action):
			Input.action_release(action)


static func restore() -> void:
	for action in _saved:
		if InputMap.has_action(action):
			for e in _saved[action]:
				InputMap.action_add_event(action, e)
	_saved.clear()
