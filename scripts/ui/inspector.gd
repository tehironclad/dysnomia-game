extends CanvasLayer
## Autoload "Inspector": "How is this drawn?" (key H, action "inspect").
##
## Every image is a real number, and the game can say which number it drew and
## how. Any node that draws something from chain data registers an explanation:
##   Inspector.register(self, "Ground", "Filled Julia set of z²+c, c from QING.Entropy() …")
## The overlay lists the explanations of every registered node that is
## currently visible in the tree. Entries vanish when their node leaves the tree.

var _entries := {}  # instance_id → {node: WeakRef, title, text}
var _panel: PanelContainer
var _text: RichTextLabel


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.theme = DeepFieldTheme.get_theme()
	_panel.visible = false
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -560
	_panel.offset_right = -24
	_panel.offset_top = 24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var head := Label.new()
	head.theme_type_variation = "DisplayLabel"
	head.text = "HOW IS THIS DRAWN?"
	box.add_child(head)
	var sub := Label.new()
	sub.theme_type_variation = "MutedLabel"
	sub.text = "Every image is a real number. The numbers are the chain's; the drawing is ours."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(500, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	add_child(_panel)


func register(node: Node, title: String, text: String) -> void:
	var id := node.get_instance_id()
	if not _entries.has(id) and not node.tree_exiting.is_connected(unregister.bind(node)):
		node.tree_exiting.connect(unregister.bind(node), CONNECT_ONE_SHOT)
	_entries[id] = {"node": weakref(node), "title": title, "text": text}
	if _panel and _panel.visible:
		_refresh()


func unregister(node: Node) -> void:
	_entries.erase(node.get_instance_id())
	if _panel and _panel.visible:
		_refresh()


func is_open() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh()


## Visible explanations, for tests and other UIs.
func visible_entries() -> Array:
	var out: Array = []
	for id in _entries.keys():
		var e: Dictionary = _entries[id]
		var n = e["node"].get_ref()
		if n == null:
			_entries.erase(id)
			continue
		var shown: bool = n.is_visible_in_tree() if (n is CanvasItem or n is Node3D) else n.is_inside_tree()
		if shown:
			out.append(e)
	return out


func _refresh() -> void:
	var parts: PackedStringArray = []
	for e in visible_entries():
		# Titles and texts carry chain strings (territory names): escaped, never BBCode
		parts.append("[color=#a8e6ff]%s[/color]\n[code]%s[/code]" % [ChatLines.esc(String(e["title"]).to_upper()), ChatLines.esc(String(e["text"]))])
	if parts.is_empty():
		parts.append("[color=#8e97a9]Nothing on screen is drawn from chain data yet.[/color]")
	_text.text = "\n\n".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inspect"):
		toggle()
		get_viewport().set_input_as_handled()
