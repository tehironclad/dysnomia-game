class_name ChatHud
extends CanvasLayer
## ChatFeed's overlay (it lives in the autoload, so it survives scene changes):
## the feed and the bar bottom-left, the history panel on the left. Shown in
## the territory, the arcade and the pub (the feed keeps running there); the
## bar works in the territory (places open their own chat panel with T).

const LAYER := 11  # just above the HUD (10); panels, seats and dives cover it

var feed: ChatFeedPanel
var bar: ChatBar
var _root: Control


func _ready() -> void:
	layer = LAYER
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = DeepFieldTheme.get_theme()
	add_child(_root)
	feed = ChatFeedPanel.new()
	feed.name = "Feed"
	_root.add_child(feed)
	feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feed.offset_left = 20
	feed.offset_bottom = -132
	feed.offset_top = -132
	bar = ChatBar.new()
	bar.name = "Bar"
	_root.add_child(bar)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = 20
	bar.offset_bottom = -120
	bar.offset_top = -120
	bar.opened.connect(func():
		feed.visible = true
		feed.offset_bottom = -132 - 150  # the feed sits above the open bar
		feed.offset_top = feed.offset_bottom
		feed.mark_read())
	bar.closed.connect(func():
		feed.offset_bottom = -132
		feed.offset_top = -132)
	var h := feed.history
	_root.add_child(h)
	h.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	h.offset_left = 420  # right of the HUD's territory column
	h.offset_top = -300
	_refresh()


func on_scene(_s: Node) -> void:
	if bar.is_open():
		bar.close()
	if feed.is_history_open():
		feed.toggle_history()
	_refresh()


func _refresh() -> void:
	var v: bool = ChatFeed.feed_visible()
	if _root.visible != v:
		_root.visible = v
		if not v and bar.is_open():
			bar.close()


var _t := 0.0


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or bar.is_open():
		return
	if event.is_action_pressed("chat_history"):
		get_viewport().set_input_as_handled()
		feed.toggle_history()
		return
	if feed.is_history_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		feed.toggle_history()
		return
	if not ChatFeed.bar_allowed():
		return
	if event.is_action_pressed("chat"):
		get_viewport().set_input_as_handled()
		if feed.is_history_open():
			feed.toggle_history()
		bar.open()
		return
	for i in ChatDraft.QUICK.size():
		if event.is_action_pressed("chat_quick_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			bar.open(ChatDraft.quick(i))
			return
