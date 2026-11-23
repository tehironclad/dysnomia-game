extends SceneTree
## Renders the avatar in a lit studio: every head in a line-up, or one head in
## a strip of animation poses. Needs a renderer (Xvfb + lavapipe):
##   xvfb-run … godot --path . --resolution 1600x900 -s res://tools/avatar_sheet.gd -- \
##       --out=/abs/sheet.png [--mode=heads|poses|closeup] [--head=rat] [--acc=crown,halo]
## Nothing here touches the chain.

var _out := ""
var _mode := "heads"
var _head := "bear"
var _acc: Array = []
var _body := "male"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a.begins_with("--head="):
			_head = a.substr(7)
		elif a.begins_with("--body="):
			_body = a.substr(7)
		elif a.begins_with("--acc="):
			_acc = Array(a.substr(6).split(",", false))
	_run.call_deferred()


func _studio() -> Node3D:
	var root := Node3D.new()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 28, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.75, 1.0)
	root.add_child(rim)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.08, 0.085, 0.11)
	fm.roughness = 0.6
	floor.material_override = fm
	root.add_child(floor)
	return root


func _model(kind: String, acc: Array, at: Vector3) -> Node3D:
	var m := Node3D.new()
	m.set_script(load("res://scripts/player/human_avatar.gd"))
	m.position = at
	current_scene.add_child(m)
	m.set_body(_body)
	m.set_head(kind, acc)
	return m


func _label(text: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.004
	l.position = at
	l.modulate = Color(0.85, 0.9, 1.0)
	current_scene.add_child(l)


func _run() -> void:
	var root := _studio()
	root.name = "Studio"
	get_root().add_child(root)
	current_scene = root
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var models: Array = []
	if _mode == "heads":
		var kinds: Array = AvatarHeads.KINDS
		var acc_for := {"rat": ["crown"], "bird": [], "skull": ["horns"], "robot": [], "frog": ["wizard"], "dog": ["halo"]}
		for i in kinds.size():
			var x := (i - (kinds.size() - 1) * 0.5) * 0.95
			models.append(_model(kinds[i], acc_for.get(kinds[i], []), Vector3(x, 0, 0)))
			_label(kinds[i], Vector3(x, 2.25, 0))
		cam.fov = 40
		cam.position = Vector3(0, 1.4, 13.5)
		cam.look_at(Vector3(0, 1.05, 0))
	elif _mode == "closeup":
		models.append(_model(_head, _acc, Vector3(-0.55, 0, 0)))
		var side := _model(_head, _acc, Vector3(0.75, 0, 0))
		side.rotation_degrees.y = -65  # the left arm (and its Aura patch) toward the camera
		# A stand-in for the Aura fractal patch (Gear draws the real one).
		var g := GradientTexture2D.new()
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color(0.1, 0.2, 0.6))
		g.gradient.set_color(1, Color(0.6, 1.0, 0.9))
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		for m in [models[0], side]:
			m.set_arm_patch(g)
		cam.fov = 35
		cam.position = Vector3(0, 1.45, 4.2)
		cam.look_at(Vector3(0.1, 1.15, 0))
	else:  # poses: idle, walk ×3, sprint ×2, falling, flying
		var poses := [["idle", Vector3.ZERO, true, false], ["walk", Vector3(0, 0, 6), true, false], ["walk", Vector3(0, 0, 6), true, false],
			["walk", Vector3(0, 0, 6), true, false], ["sprint", Vector3(0, 0, 14), true, false], ["sprint", Vector3(0, 0, 14), true, false],
			["fall", Vector3(0, -6, 2), false, false], ["fly", Vector3(0, 1, 12), false, true]]
		for i in poses.size():
			var x := (i - (poses.size() - 1) * 0.5) * 1.15
			var m := _model(_head, _acc, Vector3(x, 0, 0))
			m.rotation_degrees.y = 90  # side-on: the gait reads best in profile
			m.set_meta("pose", poses[i])
			m.set_meta("phase", i * 0.37)  # staggered phases across the walk/run frames
			models.append(m)
			_label(poses[i][0], Vector3(x, 2.25, 0))
		cam.fov = 36
		cam.position = Vector3(0, 1.3, 13.5)
		cam.look_at(Vector3(0, 1.0, 0))
	# Let the animation run; poses get staggered phases.
	for f in 90:
		for m in models:
			if m.has_meta("pose"):
				var p: Array = m.get_meta("pose")
				m.update_movement(p[1], p[2], p[3])
				if f == 30 and m.anim:
					m.anim.seek(float(m.get_meta("phase")), true)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved ", _out)
	quit()
