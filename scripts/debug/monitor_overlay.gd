# Adapted from monitor_overlay plugin by HungryProton (MIT License)
# Performance monitoring overlay with real-time graphs.

extends VBoxContainer

const DebugGraph = preload("res://scripts/debug/debug_graph.gd")

var _graphs: Array = []
var _t: float = 0.0
var _t_limit: float = 1.0 / 30.0  # 30 Hz sampling
var _built: bool = false

# Which monitors to display (preconfigured for Dysnomia game)
var show_fps: bool = true
var show_process: bool = true
var show_draw_calls: bool = true
var show_video_memory: bool = true
var show_objects_drawn: bool = true
var show_physics_3d: bool = true

# Graph appearance
var graph_height: int = 40
var graph_color: Color = Color(0.4, 0.8, 1.0, 0.9)  # Dysnomia blue
var bg_color: Color = Color(0.01, 0.01, 0.03, 0.65)


func _ready() -> void:
	custom_minimum_size.x = 280
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild_ui()


func _rebuild_ui() -> void:
	# Clear existing
	for graph in _graphs:
		graph.queue_free()
	_graphs.clear()

	# Create header
	var header := Label.new()
	header.text = "Performance Monitor"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_graphs.push_back(header)

	# Add separator
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)
	_graphs.push_back(sep)

	if show_fps:
		_create_graph(Performance.TIME_FPS, "FPS")
	if show_process:
		_create_graph(Performance.TIME_PROCESS, "Frame Time", "s")
	if show_draw_calls:
		_create_graph(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, "Draw Calls")
	if show_objects_drawn:
		_create_graph(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, "Objects Drawn")
	if show_video_memory:
		_create_graph(Performance.RENDER_VIDEO_MEM_USED, "Video Memory", "B")
	if show_physics_3d:
		_create_graph(Performance.PHYSICS_3D_ACTIVE_OBJECTS, "Physics Objects")

	_built = true


func _create_graph(monitor: int, monitor_name: String, unit: String = "") -> void:
	var graph := Control.new()
	graph.set_script(DebugGraph)
	graph.monitor = monitor
	graph.monitor_name = monitor_name
	graph.font = ThemeDB.fallback_font
	graph.font_size = 13
	graph.custom_minimum_size.y = graph_height
	graph.max_points = 80
	graph.background_color = bg_color
	graph.graph_color = graph_color
	graph.plot_graph = true
	graph.unit = unit
	graph.normalize_units = true
	graph.thickness = 1.0
	graph.antialiased = false
	graph.name = monitor_name
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(graph)
	_graphs.push_back(graph)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= _t_limit:
		_t = 0.0
		for item in _graphs:
			if item is Control and item.has_method("_draw"):
				item.queue_redraw()
