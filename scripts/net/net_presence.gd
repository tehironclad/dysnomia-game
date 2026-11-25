class_name NetPresence
extends Node3D
## Online presence in one territory (Net): joins the QING's room, sends the
## local player's pose at 10 Hz, draws everyone else (RemotePlayer) and plays
## their voice, and puts the online status line on the HUD. Chat bubbles over
## remote players come from ChatLife (RemotePlayer registers as a speaker).
## Added by the territory scene with one line; does nothing when offline.
##   var p := NetPresence.new(); add_child(p); p.setup(qing, player, hud)

var qing := ""
var player: Node3D
var hud: CanvasLayer
var feed: NetChatFeed
var remotes := {}  # peer id → RemotePlayer


func setup(p_qing: String, p_player: Node3D, p_hud: CanvasLayer) -> void:
	qing = p_qing.to_lower()
	player = p_player
	hud = p_hud
	if hud:
		feed = NetChatFeed.new()
		feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		feed.position = Vector2(20, -330)
		feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
		hud.add_child(feed)
	var c := Net.client
	if c == null:
		return
	c.peer_joined.connect(_on_peer)
	c.peer_left.connect(_on_left)
	_bumps_setup(c)
	Net.voice_pcm.connect(_on_voice)
	if not Session.changed.is_connected(Net.refresh_profile):  # autoload to autoload: outlives this scene
		Session.changed.connect(Net.refresh_profile)
	for id in c.peers:
		_on_peer(id, c.peers[id])
	Net.enter_room(qing)


var _frames := 0


func _exit_tree() -> void:
	if Net.client:
		Net.leave_room()


func _on_peer(id: int, info: Dictionary) -> void:
	var r: RemotePlayer = remotes.get(id)
	if r == null:
		r = RemotePlayer.new()
		r.name = "Remote%d" % id
		add_child(r)
		r.setup(info)
		r.visible = false  # until its first pose
		remotes[id] = r
	else:
		r.apply_info(info)


func _on_left(id: int) -> void:
	var r: RemotePlayer = remotes.get(id)
	if r:
		r.queue_free()
	remotes.erase(id)


func _on_voice(id: int, pcm: PackedFloat32Array, _level: float) -> void:
	var r: RemotePlayer = remotes.get(id)
	if r:
		r.play_voice(pcm, Net.voice_volume)


func local_flags() -> int:
	var f := 0
	if player is CharacterBody3D and (player as CharacterBody3D).is_on_floor():
		f |= NetProto.F_ON_FLOOR
	if bool(player.get("is_flying")):
		f |= NetProto.F_FLYING
	if bool(player.get("is_crouching")):
		f |= NetProto.F_CROUCH
	if not player.is_physics_processing() or not player.visible:
		f |= NetProto.F_SEATED  # driving or on a ride: drawn seated for others
	return f


func _process(_delta: float) -> void:
	var c := Net.client
	if c == null:
		return
	# Connect once the territory has finished loading (its first frames are long:
	# a handshake waiting behind them could time out).
	_frames += 1
	if _frames == 20:
		Net.start()
	if player and Net.is_online():
		var model := player.get_node_or_null("PlayerModel") as Node3D
		var yaw := model.global_rotation.y if model else player.global_rotation.y
		Net.send_state(player.global_position, yaw, local_flags())
	var now := float(Time.get_ticks_msec())
	for id in remotes:
		var r: RemotePlayer = remotes[id]
		var s := c.peer_pose(id, now)
		if not s.is_empty():
			r.visible = true
			r.apply_pose(s)


# ── bumps (NetBump) ─────────────────────────────────────────────────────────

var _bumped_at := -100.0  ## when the local player was last bumped (ms clock, s)


func _bumps_setup(c: NetClient) -> void:
	c.bump_received.connect(_on_bump_received)
	var kw := KnockWorld.of(self)
	if kw:
		kw.character_bumped.connect(_on_character_bumped)


## We ran into someone: if it was another player, tell the room.
func _on_character_bumped(st: Node, level: int, dir: Vector3, bumper: Node3D) -> void:
	if bumper != player or not (st is Stumble) or (st as Stumble).peer_id < 0:
		return
	if Net.client:
		Net.client.send_bump((st as Stumble).peer_id, BumpMath.yaw_of(dir), level)


## Someone ran into a player here: that avatar stumbles; if it was us, a brief stagger.
func _on_bump_received(_from_id: int, target_id: int, yaw: float, level: int) -> void:
	var dir := BumpMath.dir_of(yaw)
	if Net.client and target_id == Net.client.my_id:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _bumped_at < NetBump.TARGET_COOLDOWN_S or player == null or not player.has_method("bump_stagger"):
			return
		_bumped_at = now
		player.bump_stagger(BumpMath.stagger_seconds(maxi(level, BumpMath.STUMBLE)), dir * (1.2 if level >= BumpMath.STUMBLE else 0.5))
		return
	var r: RemotePlayer = remotes.get(target_id)
	var st := Stumble.on(r.avatar) if r else null
	if st and st.ready_for(level):
		st.bump(dir, level)
