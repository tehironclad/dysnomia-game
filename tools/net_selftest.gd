extends SceneTree
## End-to-end check of the game server with scripted headless clients
## (docs/SERVER.md). Two signed-in clients with throwaway test keys (A, B) and
## a guest (G) join one QING room and check: sign-in by personal_sign +
## ecrecover, presence at 10 Hz (with interpolation), chat, voice frames of a
## synthetic tone, guests can't talk, leaderboards, rate limits, size limits,
## flooding, and session-token reconnects. Prints measured bandwidth.
##   godot --headless --path . -s res://tools/net_selftest.gd [-- --url=ws://127.0.0.1:8787]
## Without --url it starts its own server in this process (port 18787, data in
## user://server_selftest). Exit code 0 = every check passed.

const ROOM := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const KEY_A := "0x8b2a5c8f8e1f1c6f3d9a0b4e2c7d5f1a9e3b6c8d0f2a4c6e8b1d3f5a7c9e0b2d"
const KEY_B := "0x2f6c8e1a3b5d7f9e0c2a4b6d8f1e3c5a7b9d0e2f4a6c8b1d3e5f7a9c0b2d4e6f"

var failures := 0
var checks := 0
var server: Node
var clients: Array = []


func _initialize() -> void:
	_run.call_deferred()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("PASS  ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func wait_until(cond: Callable, timeout_s: float = 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			return false
		await process_frame
	return true


func wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await process_frame


func make_client(label: String, key: String) -> Node:
	var c: Node = load("res://scripts/net/net_client.gd").new()
	c.name = label
	root.add_child(c)
	if key != "":
		c.signer_wallet = EthSign.address_of_private(key)
		c.signer = func(message: String) -> String: return EthSign.sign_personal(message, key)
	clients.append(c)
	return c


func _run() -> void:
	Engine.max_fps = 120
	var url := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--url="):
			url = a.substr(6)
	if url == "":
		server = load("res://scripts/net/server/game_server.gd").new()
		server.port = 18787
		server.server_name = "selftest"
		server.data_dir = "user://server_selftest"
		server.quiet = true
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://server_selftest/leaderboards.json"))
		root.add_child(server)
		ok(server.start(), "server listens on 127.0.0.1:18787")
		url = "ws://127.0.0.1:18787"
	print("server: ", url)

	var a := make_client("A", KEY_A)
	var b := make_client("B", KEY_B)
	var g := make_client("G", "")
	for c in [a, b, g]:
		c.connect_to(url)
	ok(await wait_until(func(): return a.is_online() and b.is_online() and g.is_online(), 8.0), "three clients connected (welcome received)")
	ok(a.my_id != b.my_id and a.login_message.contains(a.nonce), "distinct ids; login message carries the nonce")

	# ── sign-in ──
	var t_auth := Time.get_ticks_msec()
	a.sign_in()
	b.sign_in()
	ok(await wait_until(func(): return a.wallet != "" and b.wallet != "", 10.0), "A and B signed in by personal_sign (%d ms incl. ecrecover)" % (Time.get_ticks_msec() - t_auth))
	ok(a.wallet == a.signer_wallet and b.wallet == b.signer_wallet, "server recovered the right wallets: %s, %s" % [a.wallet, b.wallet])
	# a forged claim: G signs with key B's message but claims A's wallet
	var forged := [""]
	g.auth_failed.connect(func(r): forged[0] = r)
	g._send(NetProto.json_msg(NetProto.C_AUTH, {"wallet": a.wallet, "sig": EthSign.sign_personal(g.login_message, KEY_B)}))
	ok(await wait_until(func(): return forged[0] != "", 5.0) and g.wallet == "", "a signature from another key is refused (%s)" % forged[0])

	# ── rooms and presence ──
	a.join(ROOM, {"name": "Alice", "head": "rat", "acc": ["crown"], "body": "female"})
	b.join(ROOM, {"name": "Bob", "head": "fox", "acc": [], "body": "male"})
	g.join(ROOM, {"name": "", "head": "bear", "acc": [], "body": "male"})
	ok(await wait_until(func(): return b.peers.has(a.my_id) and a.peers.has(b.my_id) and b.peers.has(g.my_id), 5.0), "peers see each other in the QING room")
	ok(String(b.peers.get(a.my_id, {}).get("name", "")) == "Alice" and String(b.peers[a.my_id]["wallet"]) == a.wallet, "B sees A's name and verified wallet")
	ok(bool(b.peers.get(g.my_id, {}).get("guest", false)), "B sees G as a guest")
	var b_in0: int = b.counters["state_bytes_in"]
	var a_out0: int = a.counters["state_bytes_out"]
	var t0 := Time.get_ticks_msec()
	var sent := 0
	while Time.get_ticks_msec() - t0 < 3000:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if a.send_state(Vector3(10.0 * cos(t), 2.0, 10.0 * sin(t)), t, NetProto.F_ON_FLOOR, 0):
			sent += 1
		b.send_state(Vector3(5, 2, 5), 0.0, NetProto.F_ON_FLOOR, 0)
		await process_frame
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	ok(sent >= 27 and sent <= 32, "A sent %d states in %.1f s (10 Hz)" % [sent, secs])
	await wait_s(0.3)
	var pose: Dictionary = b.peer_pose(a.my_id, Time.get_ticks_msec())
	var tt := (Time.get_ticks_msec() - t0 - NetInterp.DELAY_MS) / 1000.0
	ok(not pose.is_empty(), "B has an interpolated pose for A")
	if not pose.is_empty():
		var expect := Vector3(10.0 * cos(minf(tt, secs)), 2.0, 10.0 * sin(minf(tt, secs)))
		print("      A drawn at %s on B (A's last sent ≈ %s)" % [pose["pos"], expect])
		ok((pose["pos"] as Vector3).distance_to(expect) < 2.5, "interpolated pose follows A's circle")
	var state_up := float(a.counters["state_bytes_out"] - a_out0) / secs
	var state_down := float(b.counters["state_bytes_in"] - b_in0) / secs
	print("      presence payload: up %.0f B/s per player; down %.0f B/s on B (2 others moving)" % [state_up, state_down])

	# ── chat ──
	var got := []
	b.chat.connect(func(id, w, n, text, pos): got.append([id, w, n, text, pos]))
	var g_notes := []
	g.notice.connect(func(code, text): g_notes.append(code))
	a.send_chat("hello from A\u0007 ✓")
	ok(await wait_until(func(): return got.size() >= 1, 5.0), "B received A's chat")
	if got.size() >= 1:
		ok(got[0][1] == a.wallet and got[0][2] == "Alice" and got[0][3] == "hello from A ✓", "chat carries wallet, name, cleaned text: %s" % [got[0].slice(1, 4)])
		ok((got[0][4] as Vector3).distance_to(Vector3(0, 2, 0)) < 12.0, "chat carries the speaker's position")
	got.clear()
	g.send_chat("guest says hi")
	ok(await wait_until(func(): return g_notes.has("guest"), 5.0), "guest's chat refused with a notice")
	await wait_s(0.4)
	ok(got.is_empty(), "nothing from the guest reached B")

	# ── voice: a synthetic 440 Hz tone ──
	var frames := []
	b.voice.connect(func(id, codec, data): frames.append([id, codec, data]))
	var st := [0, 0]
	var v_out0: int = a.counters["voice_bytes_out"]
	var tv := Time.get_ticks_msec()
	for f in 50:
		var pcm := PackedFloat32Array()
		pcm.resize(NetProto.VOICE_FRAME)
		for i in NetProto.VOICE_FRAME:
			pcm[i] = 0.4 * sin(TAU * 440.0 * (f * NetProto.VOICE_FRAME + i) / 16000.0)
		a.send_voice(f, NetProto.CODEC_ADPCM, VoiceCodec.encode_adpcm(pcm, st))
		while Time.get_ticks_msec() - tv < (f + 1) * 20:
			await process_frame
	var vsecs := (Time.get_ticks_msec() - tv) / 1000.0
	ok(await wait_until(func(): return frames.size() >= 50, 5.0), "B received %d/50 voice frames from A" % frames.size())
	if frames.size() > 10:
		var dec := VoiceCodec.decode(frames[10][1], frames[10][2])
		var zc := 0
		for i in range(1, dec.size()):
			if (dec[i - 1] < 0.0) != (dec[i] < 0.0):
				zc += 1
		var hz := zc / 2.0 / (dec.size() / 16000.0)
		ok(frames[10][0] == a.my_id and absf(hz - 440.0) < 40.0 and VoiceCodec.level(dec) > 0.2, "decoded frame is A's 440 Hz tone (%.0f Hz, rms %.2f)" % [hz, VoiceCodec.level(dec)])
	print("      voice payload: %.0f B/s up (ADPCM 16 kHz, 50 frames/s)" % (float(a.counters["voice_bytes_out"] - v_out0) / vsecs))
	frames.clear()
	g.send_state(Vector3(1, 2, 1), 0.0, 0, 0, true)
	for f in 10:
		g.send_voice(f, NetProto.CODEC_ADPCM, PackedByteArray([0, 0, 0, 1, 2, 3]))
	await wait_s(0.5)
	ok(frames.is_empty(), "a guest's voice is not relayed")
	# radius: B far away hears nothing
	b.send_state(Vector3(400, 2, 400), 0.0, NetProto.F_ON_FLOOR, 0, true)
	await wait_s(0.3)
	for f in 5:
		a.send_voice(100 + f, NetProto.CODEC_ADPCM, VoiceCodec.encode_adpcm(PackedFloat32Array([0.1, 0.2]), [0, 0]))
	await wait_s(0.5)
	ok(frames.is_empty(), "voice stays within the radius (B 560 m away hears nothing)")
	b.send_state(Vector3(5, 2, 5), 0.0, NetProto.F_ON_FLOOR, 0, true)

	# ── leaderboards ──
	var board := ROOM + "/arcade:void_lanes"
	var empty: Dictionary = await b.lb_top(ROOM + "/arcade:never_played", 10)
	ok(empty.get("ok", false) and (empty.get("rows", [1]) as Array).is_empty(), "an empty board is empty (no invented rows)")
	var sub: Dictionary = await a.lb_submit(board, {"score": 4200})
	ok(sub.get("ok", false) and not sub["row"]["verified"], "A's arcade score accepted, marked unverified: %s" % sub.get("row", {}).get("check", sub.get("error")))
	var gsub: Dictionary = await g.lb_submit(board, {"score": 99999})
	ok(not gsub.get("ok", true), "a guest can't submit (%s)" % gsub.get("error"))
	var fair: Dictionary = await a.lb_submit(ROOM + "/fair:striker", {"score": 999999999, "tx": "0x" + "ab".repeat(32)})
	ok(not fair.get("ok", true), "a fair score above the game's maximum is refused (%s)" % fair.get("error"))
	var top: Dictionary = await b.lb_top(board, 10)
	ok(top.get("ok", false) and top["rows"].size() == 1 and int(top["rows"][0]["score"]) == 4200 and top["rows"][0]["wallet"] == a.wallet, "B reads the board: one real row")

	# ── server info (what the site's pulse node reads): counts only ──
	if server:
		var inf: Dictionary = server.info(5, server._now())
		var here := (inf["rooms"] as Array).filter(func(r): return r["room"] == ROOM)
		ok(int(inf["players"]) == 3 and int(inf["signed_in"]) == 2 and int(inf["guests"]) == 1 and here.size() == 1 and int(here[0]["players"]) == 3,
			"info counts 3 players in the room, 2 signed in (%s)" % JSON.stringify(inf).left(160))
		ok((inf["boards"] as Array).any(func(r): return r["board"] == board and int(r["rows"]) == 1), "info lists the board with its row count")
		ok(not JSON.stringify(inf).contains(a.wallet.trim_prefix("0x")), "info names no wallet")
		ok(NetProto.size_ok(NetProto.json_msg(NetProto.C_INFO, {"req": 123456})), "a C_INFO request fits its size limit")

	# ── bumps (NetBump): running into another player ──
	ok(a.features.has("bump"), "the welcome lists the bump feature")
	var bumps := []
	b.bump_received.connect(func(from, target, yaw, level): bumps.append([from, target, yaw, level]))
	var seen := []
	g.bump_received.connect(func(from, target, _yaw, _level): seen.append([from, target]))
	a.send_state(Vector3(6.0, 2, 5), 0.0, NetProto.F_ON_FLOOR, 0, true)
	b.send_state(Vector3(5, 2, 5), 0.0, NetProto.F_ON_FLOOR, 0, true)
	g.send_state(Vector3(60, 2, 60), 0.0, NetProto.F_ON_FLOOR, 0, true)
	await wait_s(0.3)
	ok(a.send_bump(b.my_id, 1.0, BumpMath.FALL), "A ran into B: a bump is sent")
	ok(await wait_until(func(): return bumps.size() >= 1, 3.0), "B is told it was bumped")
	if bumps.size() >= 1:
		ok(int(bumps[0][0]) == a.my_id and int(bumps[0][1]) == b.my_id and int(bumps[0][3]) == BumpMath.STUMBLE
			and absf(float(bumps[0][2]) - 1.0) < 0.03, "from A, on B, a stumble at most, the push's direction: %s" % [bumps[0]])
	ok(await wait_until(func(): return seen.any(func(e): return int(e[1]) == b.my_id), 3.0), "the room sees B stumble too")
	ok(not a.send_bump(b.my_id, 1.0, BumpMath.STUMBLE), "the client doesn't re-send at once")
	a._send(NetBump.bump_msg(b.my_id, 0.5, BumpMath.STUMBLE))  # straight past the client's own cooldown
	await wait_s(0.4)
	ok(bumps.size() == 1, "the server drops a second bump on B inside its cooldown")
	a._send(NetBump.bump_msg(g.my_id, 0.5, BumpMath.STUMBLE))
	await wait_s(0.4)
	ok(not seen.any(func(e): return int(e[1]) == g.my_id), "a bump on someone 60 m away is dropped")

	# ── rate limits ──
	got.clear()
	var a_notes := []
	a.notice.connect(func(code, _t): a_notes.append(code))
	await wait_s(4.0)  # let A's chat bucket refill
	for i in 20:
		a.send_chat("spam %d" % i)
	await wait_s(1.0)
	ok(got.size() >= 3 and got.size() <= 6 and a_notes.has("slow"), "chat flood: %d of 20 relayed, then 'slow down'" % got.size())
	var b_states0: int = b.counters["state_bytes_in"]
	var tf := Time.get_ticks_msec()
	for i in 200:  # 200 states at once, far over 15/s
		a._send(NetProto.state_msg(i, Vector3(i * 0.01, 2, 0), 0, 0, 0))
	await wait_s(1.0)
	var relayed: int = (b.counters["state_bytes_in"] - b_states0) / 22
	ok(relayed <= 14, "state flood: B got %d updates in %.1f s (server keeps ≤ 10 Hz relay)" % [relayed, (Time.get_ticks_msec() - tf) / 1000.0])
	ok(a.is_online(), "A is throttled, not kicked, for a short burst")
	# oversize and malformed: a misbehaving client is kicked after strikes
	var m := make_client("M", "")
	m.connect_to(url)
	await wait_until(func(): return m.is_online(), 5.0)
	var big := PackedByteArray([NetProto.C_CHAT])
	big.resize(3000)
	for i in GameServerLimits.MAX_STRIKES + 2:
		m._send(big)
		m._send(PackedByteArray([200, 1, 2]))
	ok(await wait_until(func(): return not m.is_online(), 5.0), "oversize/unknown messages: the client is disconnected after strikes")
	var f := make_client("F", "")
	f.connect_to(url)
	await wait_until(func(): return f.is_online(), 5.0)
	for i in 3000:  # ~50 a frame: far over every bucket, under the socket's queue
		f._send(NetProto.ping_msg(NetProto.C_PING, i))
		if i % 50 == 0:
			await process_frame
			if not f.is_online():
				break
	ok(await wait_until(func(): return not f.is_online(), 8.0), "a flooding client is disconnected")
	ok(a.is_online() and b.is_online(), "well-behaved clients stay connected")

	# ── reconnect with the session token: no new signature ──
	var tok: String = a.token
	var signed := [0]
	a.signer = func(message: String) -> String:
		signed[0] += 1
		return EthSign.sign_personal(message, KEY_A)
	a.close()
	ok(await wait_until(func(): return not b.peers.has(a.my_id) or b.peers.size() < 3, 5.0), "B saw A leave")
	a.token = tok
	a.connect_to(url)
	a.room = ROOM
	ok(await wait_until(func(): return a.wallet != "", 8.0) and signed[0] == 0, "A reconnected and signed in by token (no wallet prompt)")
	ok(await wait_until(func(): return b.peers.values().any(func(p): return p.get("wallet", "") == a.wallet), 5.0), "B sees A back in the room")

	if server:
		print("      server stats: ", JSON.stringify(server.stats))
	print("\n%d checks, %d failed" % [checks, failures])
	for c in clients:
		c.close()
	await wait_s(0.3)
	if server:
		server.stop()
	quit(1 if failures > 0 else 0)


class GameServerLimits:
	const MAX_STRIKES := 20
