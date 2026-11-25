class_name ChatHud
extends CanvasLayer
## ChatFeed's overlay (it lives in the autoload, so it survives scene changes):
## the dock (ChatFeedPanel) and the bar bottom-left, the HUD's chat corner;
## the history panel in the middle (Y). Shown in
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
	# The dock: bottom-left, the HUD's chat corner (HudLayout). The bar opens
	# under it and pushes it up; the history opens in the middle of the screen.
	feed = ChatFeedPanel.new()
	feed.name = "Feed"
	_root.add_child(feed)
	feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feed.offset_left = HudLayout.MARGIN
	feed.offset_bottom = -HudLayout.DOCK_BOTTOM
	feed.offset_top = -HudLayout.DOCK_BOTTOM
	bar = ChatBar.new()
	bar.name = "Bar"
	_root.add_child(bar)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_left = HudLayout.MARGIN
	bar.offset_bottom = -HudLayout.DOCK_BOTTOM
	bar.offset_top = -HudLayout.DOCK_BOTTOM
	bar.opened.connect(func():
		feed.visible = true
		if feed.collapsed:
			feed.set_collapsed(false)
		feed.foot.visible = false  # the bar lists its own keys
		_place_feed.call_deferred()
		feed.mark_read())
	bar.resized.connect(func():
		if bar.is_open():
			_place_feed())
	bar.closed.connect(func():
		feed.foot.visible = not feed.collapsed
		feed.offset_bottom = -HudLayout.DOCK_BOTTOM
		feed.offset_top = -HudLayout.DOCK_BOTTOM)
	var h := feed.history
	_root.add_child(h)
	# Beside the dock (whose lines it continues), between the HUD's two columns.
	h.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	h.offset_left = HudLayout.MARGIN + HudLayout.DOCK_W + HudLayout.GAP * 2
	h.offset_right = h.offset_left + h.custom_minimum_size.x
	h.offset_top = -h.custom_minimum_size.y * 0.5
	h.offset_bottom = h.custom_minimum_size.y * 0.5
	_refresh()


## The dock sits on top of the open bar.
func _place_feed() -> void:
	var y := -HudLayout.DOCK_BOTTOM - bar.size.y - HudLayout.GAP
	feed.offset_bottom = y
	feed.offset_top = y


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
	if event.is_action_pressed("chat_dock"):
		get_viewport().set_input_as_handled()
		feed.toggle_collapsed()
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
