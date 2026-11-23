extends SceneTree
## Dev screenshot harness. Usage:
##   godot --path . -s tools/shot.gd -- out.png px py pz tx ty tz [frames]
##   optional 9th arg: graphics quality 0..3 (lavapipe needs <=1)
## Env: SHOT_TOD=0.45 (time of day), SHOT_NOSHADER=terrain (lavapipe cannot run terrain.gdshader)
## Loads scenes/main.tscn, parks a free camera at (px,py,pz) looking at (tx,ty,tz),
## waits for the scene to settle, and saves the viewport to out.png.

var _args: PackedStringArray
var _frames := 0
var _wait := 90
var _cam: Camera3D

func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	if _args.size() >= 8:
		_wait = int(_args[7])
	var cfg = root.get_node_or_null("Config")
	if cfg and _args.size() >= 9:
		cfg.graphics_quality = int(_args[8])
	# SHOT_STRIP=particles,canvas,... hides node kinds that crash software Vulkan
	var strip := OS.get_environment("SHOT_STRIP").split(",", false)
	if strip.size() > 0:
		node_added.connect(func(n: Node) -> void:
			if "particles" in strip and (n is GPUParticles3D or n is GPUParticles2D):
				n.set_deferred("visible", false)
			if "canvas" in strip and n is CanvasLayer:
				n.set_deferred("visible", false)
			if "fogvol" in strip and n is FogVolume:
				n.set_deferred("visible", false)
			if "decal" in strip and n is Decal:
				n.set_deferred("visible", false))
	change_scene_to_file.call_deferred("res://scenes/main.tscn")

func _strip_shaders(n: Node, names: PackedStringArray) -> void:
	# SHOT_NOSHADER=terrain,crystal,... swaps matching ShaderMaterials for grey (crash bisecting)
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var m := gi.material_override
		if m is ShaderMaterial and m.shader and _match(m.shader.resource_path, names):
			var grey := StandardMaterial3D.new()
			grey.albedo_color = Color(0.42, 0.40, 0.38)
			grey.roughness = 0.95
			gi.material_override = grey
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var sm := mi.get_active_material(i)
				if sm is ShaderMaterial and sm.shader and _match(sm.shader.resource_path, names):
					mi.set_surface_override_material(i, StandardMaterial3D.new())
		if n is GPUParticles3D and _match("particles", names):
			n.visible = false
	for c in n.get_children():
		_strip_shaders(c, names)

func _y(v: String, x: float, z: float) -> float:
	if v.begins_with("+") and current_scene and current_scene.get("territory"):
		return current_scene.territory.get_height_at(x, z) + float(v.substr(1))
	return float(v)

func _match(path: String, names: PackedStringArray) -> bool:
	for nm in names:
		if nm == "*" or path.contains(nm):
			return true
	return false

func _process(_delta: float) -> bool:
	_frames += 1
	var tod := OS.get_environment("SHOT_TOD")
	if not tod.is_empty():
		var gm = root.get_node_or_null("GameManager")
		if gm:
			gm.time_of_day = float(tod)
			gm.day_cycle_speed = 0.0
	if _frames < 4 and current_scene and current_scene.get("_terrain_material"):
		var tm: ShaderMaterial = current_scene.get("_terrain_material")
		for k in OS.get_environment("SHOT_TERRAIN_ZERO").split(",", false):
			tm.set_shader_parameter(k, 0.0)
	var ns := OS.get_environment("SHOT_NOSHADER").split(",", false)
	if ns.size() > 0 and current_scene:
		_strip_shaders(current_scene, ns)
	if _cam == null and _frames > 2 and current_scene:
		_cam = Camera3D.new()
		_cam.fov = 70.0
		_cam.far = 2000.0
		current_scene.add_child(_cam)
		# Hide HUD/UI layers so the still shows the world only (SHOT_UI=1 keeps the
		# attraction UI and fills it with demo content for reviewing the panels)
		var keep_ui := OS.get_environment("SHOT_UI") == "1"
		for c in current_scene.get_children():
			if c is CanvasLayer and not (keep_ui and c.name == "AttractionUI"):
				c.visible = false
		if keep_ui and current_scene.get("_attraction_ui"):
			var ui = current_scene._attraction_ui
			var item: Dictionary = AttractionCatalog.ride("rocket")
			ui.show_ticket(item, "Pays 1 AFFECTION to Sunny QING (the QING keeper).", "42.5", "Your bars here: HYPO 1.24M · EPI 806.1K")
			ui.set_ticket_status("Ticket broadcast — boarding as soon as the block confirms (~10 s).", AttractionUI.PULSE)
			ui.show_bar_report({"item": AttractionCatalog.drink("rho_rocks"), "hypo_before": 1240000, "hypo_after": 1311200,
				"d_hypo": 71200, "epi_before": 806100, "epi_after": 806100, "d_epi": 0}, "Sunny QING")
			ui._report_timer = 9999.0
			ui.set_caption("T-3")
			ui.show_bar_menu("Sunny QING — Bar", AttractionCatalog.DRINKS, "Press a number to order.  Balance 42.5 AFFECTION · Your bars here: HYPO 1.24M · EPI 806.1K")
	if _cam and _cam.is_inside_tree():
		# A y value written "+N" means N metres above the terrain at that x/z
		var p := Vector3(float(_args[1]), _y(_args[2], float(_args[1]), float(_args[3])), float(_args[3]))
		var t := Vector3(float(_args[4]), _y(_args[5], float(_args[4]), float(_args[6])), float(_args[6]))
		_cam.global_position = p
		_cam.look_at(t)
		_cam.make_current()
	if _frames == _wait:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_args[0])
		print("[shot] saved ", _args[0])
		quit()
	return false
