class_name Exchanges
extends Node3D
## The territory's two exchange places, added by territory_v2 as one node (under
## the Core):
##   - the Swap Hall (SwapHall): PLS ⇄ Dysnomia tokens on PulseX, a surveyed lot
##     with working terminals at Wild, the hall from Outpost up;
##   - the YUE Exchange (YueFloor): Hong / Hung desks at fixed rates, in the sky
##     lobby of the territory's tower (a stop of its glass lift) from Settlement up,
##     else at the Swap Hall's YUE counter.
## Owns the two panels (SwapPanel, YuePanel) on their own CanvasLayer, so they show
## in previews with the HUD hidden. Everything placed depends only on territory state.

var hall: SwapHall
var yue_floor: YueFloor
var swap_panel: SwapPanel
var yue_panel: YuePanel
var _territory: Dictionary = {}
var _hud: Node
var _player: CharacterBody3D
var _landmark: Landmark
var _tint := Color("#7fd3ff")
var _tier := -1
var _layer: CanvasLayer
var _pending_view := ""
var _camera: Camera3D


func setup(territory: Dictionary, hud: Node, player: CharacterBody3D, height_fn: Callable, tint: Color, ground_mat: Material, others: Array, landmark: Landmark) -> void:
	_territory = territory
	_hud = hud
	_player = player
	_landmark = landmark
	_tint = tint
	var qing := String(territory["address"]).to_lower()
	var asset := String(territory.get("asset", "")).to_lower()
	var avoid: Array = others.duplicate()
	if landmark:
		avoid.append([landmark.site.get("at", LandmarkPlan.PREFER), LandmarkPlan.PLAZA_R])
		avoid.append([landmark.ring.get("at", Vector2(0, 150)), LandmarkPlan.RING_R])
		landmark.built.connect(_on_tower_built)
	hall = SwapHall.new()
	hall.name = "SwapHall"
	add_child(hall)
	hall.setup(qing, asset, hud, player, height_fn, tint, ground_mat, avoid)
	hall.use_swap.connect(open_swap)
	hall.use_yue.connect(open_yue)
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)
	var place := String(territory.get("name", ""))
	swap_panel = SwapPanel.new()
	center.add_child(swap_panel)
	swap_panel.setup(qing, place, asset)
	swap_panel.closed.connect(_resume)
	yue_panel = YuePanel.new()
	center.add_child(yue_panel)
	yue_panel.setup(qing, place, asset, "the Swap Hall's counter")
	yue_panel.closed.connect(_resume)


func set_development(tier: int) -> void:
	_tier = tier
	hall.set_tier(tier, _tower_note())


func _tower_note() -> String:
	if _landmark == null or not _landmark.has_tower() or yue_floor == null or not is_instance_valid(yue_floor):
		return ""
	return "in the %s sky lobby, %d m up the glass lift" % [String(_landmark.spec["title"]), int(yue_floor.floor_y)]


func _on_tower_built() -> void:
	var tower := _landmark.tower_node()
	if tower == null or _landmark.spec.is_empty():
		return
	yue_floor = YueFloor.new()
	yue_floor.name = "YueExchangeFloor"
	tower.add_child(yue_floor)
	var title := LandmarkPlan.sign_name(_landmark.spec["kind"], String(_territory.get("name", "")))
	yue_floor.build(_landmark.spec, _landmark.lift_info, _player, _hud, _tint, title)
	_landmark.exchange_y = yue_floor.floor_y
	yue_floor.use_desk.connect(open_yue)
	yue_panel.set_titles("YUE EXCHANGE · %s · %d M" % [title, int(yue_floor.floor_y)], yue_panel._sub.text)
	if _tier >= 0:
		hall.set_tier(_tier, _tower_note())
	print("[YueExchange] floor at %d m in the %s (lift stop)" % [int(yue_floor.floor_y), title])
	_read_floor_boards()
	if _pending_view != "":
		var v := _pending_view
		_pending_view = ""
		frame(v, _camera)


func _read_floor_boards() -> void:
	var qing := String(_territory["address"])
	var d: Dictionary = await YueExchange.read_desk(qing, String(_territory.get("asset", "")), "", "")
	var rated = await YueExchange.rated_scan()
	if yue_floor and is_instance_valid(yue_floor):
		yue_floor.show_desk(d, String(_territory.get("name", "")), rated)


func open_swap() -> void:
	_pause()
	swap_panel.open()


func open_yue() -> void:
	_pause()
	yue_panel.open()


func _pause() -> void:
	if _player:
		_player.process_mode = Node.PROCESS_MODE_DISABLED


func _resume() -> void:
	if swap_panel.is_open() or yue_panel.is_open():
		return
	if _player and _pending_view == "" and _camera == null:
		_player.process_mode = Node.PROCESS_MODE_INHERIT
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Screenshot views (territory_v2 --view=…): swap (outside) | swap_in | swap_panel |
## yue (the sky lobby floor; the Swap Hall counter where there is no tower) | yue_panel.
func frame(view: String, camera: Camera3D) -> void:
	_camera = camera
	if view.begins_with("yue") and _landmark and _landmark.has_tower() and (yue_floor == null or not is_instance_valid(yue_floor)):
		_pending_view = view  # framed once the tower is built
		return
	if view.begins_with("yue") and yue_floor and is_instance_valid(yue_floor):
		# --view=yue_board / yue_list: square on to a side board
		camera.global_transform = yue_floor.preview_transform(view.substr(4) if view in ["yue_board", "yue_list"] else "")
		camera.fov = 70.0
	elif view == "swap":
		camera.global_transform = hall.preview_transform("out")
		camera.fov = 62.0
	else:
		camera.global_transform = hall.preview_transform("in")
		camera.fov = 72.0
	if view.ends_with("_panel"):
		_open_later(swap_panel if view == "swap_panel" else yue_panel)


## Previews: open a panel once the screenshot tool has set --session's wallet.
func _open_later(panel: ExchangePanel) -> void:
	await get_tree().create_timer(2.0).timeout
	if panel == swap_panel:
		await swap_panel.open()
		swap_panel._amount.text = "1000"
		swap_panel.quote()
	else:
		await yue_panel.open()
		yue_panel._amount.text = "0.0001"
		yue_panel._plan_trade()
