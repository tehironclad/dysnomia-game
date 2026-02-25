# Adapted from monitor_overlay plugin by HungryProton (MIT License)
# Performance graph widget for real-time monitoring.

extends Control

var monitor: int
var monitor_name: String
var max_points: int = 100
var font: Font
var font_size: int = 13
var background_color: Color = Color(0.0, 0.0, 0.0, 0.5)
var graph_color: Color = Color.ORANGE
var normalize_units: bool = true
var plot_graph: bool = true
var unit: String = ""
var thickness: float = 1.0
var antialiased: bool = false

var _history: Array = []
var _last_value: float = 0.0


func _draw() -> void:
	_update_history()
	_draw_background_panel()
	if plot_graph:
		_draw_graph()
	_draw_text()


func _draw_background_panel() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, background_color)


func _draw_text() -> void:
	var s_value := _normalize_value(_last_value)
	var text := monitor_name + ": " + s_value
	var position := Vector2(4, font_size + 2)
	if font:
		draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)


func _draw_graph() -> void:
	if _history.size() < 2:
		return

	# Get value range
	var min_value: float = _history[0]
	var max_value: float = _history[0]
	for value in _history:
		min_value = min(value, min_value)
		max_value = max(value, max_value)

	if min_value == max_value:
		min_value -= 1.0
		max_value += 1.0

	# Convert to 2D coordinates
	var x: float = 0.0
	var offset: float = size.x / float(max_points)
	var height: float = size.y
	var margin: float = height / 10.0
	var points := PackedVector2Array()

	for value in _history:
		var v: float = remap(value, min_value, max_value, margin, height - margin)
		if x > 0:
			points.push_back(Vector2(x, height - v))
		x += offset

	if points.size() > 1:
		draw_polyline(points, graph_color, thickness, antialiased)


func _update_history() -> void:
	_last_value = Performance.get_monitor(monitor)
	if not plot_graph:
		return

	_history.push_back(_last_value)
	if _history.size() >= max_points:
		_history.pop_front()


func _normalize_value(value: float) -> String:
	var result := str(snapped(value, 0.01)) + unit

	if not normalize_units or value == 0.0:
		return result

	if value > 1000.0:
		var v := value
		var index := -1
		while v > 1000.0 and index < 3:
			v /= 1000.0
			index += 1
		var scale := ["K", "M", "G", "T"]
		result = str(snapped(v, 0.001)) + scale[index] + unit

	elif value < 1.0:
		var v := value
		var index := -1
		while v < 1.0 and index < 2:
			v *= 1000.0
			index += 1
		var scale := ["m", "u", "n"]
		result = str(snapped(v, 0.001)) + scale[index] + unit

	return result
