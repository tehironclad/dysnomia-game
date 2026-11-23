extends SceneTree
## Headless test for the native Supabase Realtime client + community layer.
##
## Needs a Phoenix/Supabase-Realtime compatible server (a local mock is fine). Run two
## instances against it, plus the offline check:
##   godot --headless --path . -s tools/test_realtime.gd -- --role=a --realtime-url=ws://127.0.0.1:54321 --guest-id-file=user://rt_test_a.cfg
##   godot --headless --path . -s tools/test_realtime.gd -- --role=b --realtime-url=ws://127.0.0.1:54321 --guest-id-file=user://rt_test_b.cfg
##   godot --headless --path . -s tools/test_realtime.gd -- --role=offline
##
## Role a = wallet player "Alice" (tier 3). Role b = guest (no wallet, no LAU).
## a & b: both see each other in presence, positions propagate both ways, moments cross,
## say/emote reach the other avatar, online counter / invite text; b quits abruptly and a
## must see the leave diff remove b's avatar. offline: Config default URL (unreachable from
## the sandbox) and a refused port fail quietly with backoff and no crash.
## Exit code 0 = all passed. Prints "[rt-test] ALL PASSED".

const MultiplayerManagerScript = preload("res://scripts/multiplayer/multiplayer_manager.gd")
const CommunityIdentityScript = preload("res://scripts/multiplayer/community_identity.gd")
const RemotePlayerScript = preload("res://scripts/multiplayer/remote_player.gd")

const QING := "0x1234567890abcdef1234567890abcdef12345678"
const WALLET_A := "0xaaaa00000000000000000000000000000000beef"
const POS_A := Vector3(5, 2, 7)
const POS_B := Vector3(-3, 2, 4)

var role := "a"
var _world: Node3D
var _player: CharacterBody3D
var _mm: Node
var _hub: Node
var _fails := 0
var _passed: Dictionary = {}
var _t0 := 0
var _moments: Array = []
var _left: Array = []
var _step := 0
var _step_t := 0
var _sent_mark := 0


func _initialize() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.substr(7)
	_t0 = Time.get_ticks_msec()
	print("[rt-test] role=%s" % role)
	var gm := root.get_node_or_null("GameManager")
	gm.territory_address = QING
	gm.territory_name = "Sunny's"
	gm.lau_username = ""
	gm.player_identity = "Anonymous"

	if role == "b":
		# Guest id: generated once, persisted, stable across reloads
		var id1: String = CommunityIdentityScript.get_guest_id()
		CommunityIdentityScript.clear_cache()
		var id2: String = CommunityIdentityScript.get_guest_id()
		_check("guest id format (%s)" % id1, CommunityIdentityScript.is_valid_guest_id(id1))
		_check("guest id stable across reload", id1 == id2)
		var ident: Dictionary = CommunityIdentityScript.resolve("", "")
		_check("guest name Guest-XXXX (%s)" % ident.name, ident.name == "Guest-" + id1.right(4).to_upper() and ident.guest)
		gm.lau_username = ""

	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.add_to_group("player")
	_world.add_child(_player)
	_player.position = Vector3(0, 1.3, 0)  # root isn't in-tree yet during _initialize

	_mm = MultiplayerManagerScript.new()
	_mm.name = "MultiplayerManager"
	if role == "offline":
		_mm.auto_announce_arrival = false
	_world.add_child(_mm)
	_mm.set_spawn_parent(_world)
	if role == "a":
		_mm.set_local_player(_player, WALLET_A, "Alice", 3)
		_mm.activate()
	# role b / offline: never call set_local_player → manager self-activates as a guest
	_mm.player_left.connect(func(w: String, _u: String) -> void: _left.append(w))


func _check(name: String, ok: bool) -> void:
	print("[rt-test] %s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _once(tag: String, ok: bool, label: String = "") -> void:
	if ok and not _passed.has(tag):
		_passed[tag] = true
		_check(label if not label.is_empty() else tag, true)


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _finish() -> void:
	if _fails == 0:
		print("[rt-test] ALL PASSED (%s)" % role)
	else:
		print("[rt-test] %d FAILED (%s)" % [_fails, role])
	quit(1 if _fails > 0 else 0)


func _bind_hub() -> void:
	if _hub == null:
		_hub = _world.get_node_or_null("CommunityHub")
		if _hub:
			_hub.moment_received.connect(func(k: String, d: Dictionary, n: String) -> void:
				_moments.append({"k": k, "d": d, "n": n}))


func _find_moment(kind: String, from_self: bool) -> Dictionary:
	for m in _moments:
		if m.k == kind and bool(m.d.get("self", false)) == from_self:
			return m
	return {}


func _process(delta: float) -> bool:
	_bind_hub()
	match role:
		"a": return _run_a(delta)
		"b": return _run_b(delta)
		_: return _run_offline(delta)


# ─── Role A: wallet player ──────────────────────────────────────────────

func _remote_b() -> Node3D:
	for k in _mm.get_remote_players():
		if str(k).begins_with("guest-"):
			return _mm.get_remote_players()[k]
	return null


func _run_a(_delta: float) -> bool:
	if _elapsed() > 45.0:
		for need in ["joined", "sees_b", "pos_b", "moment_b", "say_b", "emote_b", "counts", "left_b"]:
			if not _passed.has(need):
				_check("timeout waiting for: " + need, false)
		_finish()
		return true
	_once("joined", _mm.is_native_joined(), "A joined QING channel natively (key=%s)" % _mm.get_local_key())
	var rb := _remote_b()
	if rb and not _passed.has("sees_b"):
		_once("sees_b", true, "A sees guest B in presence as '%s'" % rb.username)
		_check("B name tag is Guest-XXXX", rb.username.begins_with("Guest-"))
		_check("B name tag guest colour", rb._label.modulate.is_equal_approx(RemotePlayerScript.name_tag_color(0, true)))
		_player.global_position = POS_A
		_player.velocity = Vector3(1, 0, 0)
		_hub.announce("house_round", {"drink": "Pulse Ale"})
		_step = 1
		_step_t = Time.get_ticks_msec()
	if rb:
		_once("pos_b", rb.target_position.distance_to(POS_B) < 0.05, "A received B's position %s" % str(POS_B))
		_once("say_b", rb.get_last_chat() == "hello pub", "B's chat bubble 'hello pub' above B's avatar on A")
		_once("emote_b", rb.last_emote_id == 2, "B's emote (Dance) shown on B's avatar on A")
	var mb := _find_moment("board_post", false)
	if not mb.is_empty() and not _passed.has("moment_b"):
		_once("moment_b", true, "A got B's board_post moment from '%s'" % mb.n)
		_check("moment data preserved + qing/here flags", mb.d.get("board") == "Memes" and mb.d.get("qing") == QING and mb.d.get("here") == true)
	if _passed.has("sees_b") and not _passed.has("counts") and _hub.get_online_here() == 2:
		_once("counts", true, "online counter: '%s'" % _hub.counter_text())
		_check("counter text", _hub.counter_text() == "2 in Sunny's · 2 on Dysnomia")
		var inv: String = _hub.invite_text()
		print("[rt-test] invite: " + inv)
		_check("invite text", inv.begins_with("Come hang at SUNNY'S on Dysnomia — QING 0x1234…5678") and inv.ends_with("· 2 here now"))
		var self_round := _find_moment("house_round", true)
		_check("own announce echoed locally (self=true)", not self_round.is_empty())
		var feed = _hub.get_node_or_null("CommunityLayer/CommunityFeed")
		var toasts: PackedStringArray = feed.get_toast_texts() if feed else PackedStringArray()
		print("[rt-test] feed toasts: %s" % str(toasts))
		_check("feed shows 'You bought a round'", " ".join(toasts).contains("You bought a round for the house"))
	# Rate limit: move continuously for 1 s, then idle
	if _step == 1 and Time.get_ticks_msec() - _step_t > 1500:
		_step = 2
		_step_t = Time.get_ticks_msec()
		_sent_mark = _mm.pos_broadcasts_sent
	elif _step == 2:
		_player.global_position += Vector3(0.05, 0, 0)
		_player.velocity = Vector3(3, 0, 0)
		if Time.get_ticks_msec() - _step_t >= 1000:
			var n: int = _mm.pos_broadcasts_sent - _sent_mark
			_check("moving: %d pos broadcasts in 1 s (≤ 11)" % n, n <= 11 and n >= 5)
			_player.global_position = POS_A
			_player.velocity = Vector3.ZERO
			_step = 3
			_step_t = Time.get_ticks_msec()
			_sent_mark = -1
	elif _step == 3:
		if _sent_mark < 0 and Time.get_ticks_msec() - _step_t > 300:
			_sent_mark = _mm.pos_broadcasts_sent  # after the snap-back + stop packet
		if _sent_mark >= 0 and Time.get_ticks_msec() - _step_t > 2300:
			var n2: int = _mm.pos_broadcasts_sent - _sent_mark
			_check("idle: %d pos broadcasts in 2 s (only when moved)" % n2, n2 == 0)
			_step = 4
	if _passed.has("sees_b") and rb == null and _left.size() > 0 and not _passed.has("left_b"):
		_once("left_b", true, "B disconnected → leave diff → B's avatar removed")
		_check("remote count back to 0", _mm.get_player_count() == 0)
		_check("online here back to 1", _hub.get_online_here() == 1)
	if _passed.has("left_b") and _step >= 4:
		for need in ["pos_b", "moment_b", "say_b", "emote_b", "counts"]:
			if not _passed.has(need):
				_check("missing before B left: " + need, false)
		_finish()
		return true
	return false


# ─── Role B: guest ──────────────────────────────────────────────────────

func _remote_a() -> Node3D:
	return _mm.get_remote_player(WALLET_A)


func _run_b(_delta: float) -> bool:
	if _elapsed() > 40.0:
		for need in ["joined", "sees_a", "pos_a", "round_a"]:
			if not _passed.has(need):
				_check("timeout waiting for: " + need, false)
		_finish()
		return true
	_once("joined", _mm.is_native_joined(), "B (guest) joined natively as %s / '%s'" % [_mm.get_local_key(), _mm.get_local_name()])
	if _passed.has("joined") and _step == 0:
		_check("guest presence key", _mm.get_local_key().begins_with("guest-") and _mm.is_guest())
		_step = 1
	var ra := _remote_a()
	if ra and not _passed.has("sees_a"):
		_once("sees_a", true, "B sees A in presence as '%s' tier %d" % [ra.username, ra.tier])
		_check("A's name + tier from presence", ra.username == "Alice" and ra.tier == 3)
		_check("A's name tag tier colour", ra._label.modulate.is_equal_approx(RemotePlayerScript.name_tag_color(3)))
		_player.global_position = POS_B
		_hub.announce("board_post", {"board": "Memes", "nested": {"x": 1}})
		_check("say broadcast sent", _hub.say("hello pub"))
		_check("emote broadcast sent", _hub.send_emote(2))
		_check("own chat bubble on local player", _player.get_node_or_null("CommunityChatBubble") != null)
	if ra:
		_once("pos_a", ra.target_position.distance_to(POS_A) < 0.05, "B received A's position %s" % str(POS_A))
	var mr := _find_moment("house_round", false)
	if not mr.is_empty() and not _passed.has("round_a"):
		_once("round_a", true, "B got A's house_round moment from '%s'" % mr.n)
		_check("house_round here=true, qing set, data kept", mr.d.get("here") == true and mr.d.get("qing") == QING and mr.d.get("drink") == "Pulse Ale")
		_check("everyone cheers: A's avatar claps", ra != null and ra.last_emote_id == 7)
		_step_t = Time.get_ticks_msec()
	if _passed.has("pos_a") and _passed.has("round_a") and Time.get_ticks_msec() - _step_t > 1500:
		print("[rt-test] B quitting abruptly (no phx_leave) to test the leave diff")
		_finish()
		return true
	return false


# ─── Role offline ───────────────────────────────────────────────────────

func _run_offline(_delta: float) -> bool:
	var rt: Node = _mm.get_realtime()
	var e := _elapsed()
	if _step == 0 and e > 0.5:
		print("[rt-test] endpoint (Config default): %s" % rt.endpoint.left(70))
		_check("default endpoint built from Config", rt.endpoint.begins_with("wss://tftfafepodpolrufefrt.supabase.co/realtime/v1/websocket?apikey=") and rt.endpoint.ends_with("&vsn=1.0.0"))
		_step = 1
	if _step == 1 and e > 9.5:
		_check("unreachable default: not open, no crash (attempts=%d, state=%s)" % [rt.get_attempts(), rt.get_status_text()], not rt.is_open() and rt.get_attempts() >= 1)
		_check("manager degraded to offline mode (guest, no bridge)", _mm.get_transport_mode() == "offline" and _mm.get_player_count() == 0)
		_check("hub still usable offline (announce/invite)", _hub != null and _hub.invite_text().begins_with("Come hang at SUNNY'S"))
		_hub.announce("promotion", {"tier": 4})
		_check("offline announce still echoes locally", not _find_moment("promotion", true).is_empty())
		rt.configure("ws://127.0.0.1:1/realtime/v1", "anon")
		_step = 2
		_step_t = Time.get_ticks_msec()
	if _step == 2 and Time.get_ticks_msec() - _step_t > 5000:
		_check("refused port: not open, backing off (attempts=%d, next in %.1fs)" % [rt.get_attempts(), rt.get_retry_in()], not rt.is_open() and rt.get_attempts() >= 2)
		_check("backoff steps capped at 60 s", RealtimeClient.BACKOFF_STEPS.back() == 60.0)
		_check("endpoint builder: bare project URL", RealtimeClient.build_endpoint("https://abc.supabase.co", "K") == "wss://abc.supabase.co/realtime/v1/websocket?apikey=K&vsn=1.0.0")
		_check("endpoint builder: disabled when empty", RealtimeClient.build_endpoint("", "K") == "")
		_finish()
		return true
	return false
