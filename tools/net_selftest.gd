extends SceneTree
## End-to-end check of the game server with scripted headless clients
## (docs/SERVER.md). Two signed-in clients with throwaway test keys (A, B) and
## a guest (G) join one QING room and check: sign-in by personal_sign +
## ecrecover, presence at 10 Hz (with interpolation), chat, voice frames of a
## synthetic tone, guests can't talk, leaderboards, rate limits, size limits,
## flooding, and session-token reconnects. Sign-in v2 (docs/SECURITY_AUDIT.md): the
## client builds the text itself; a signature made for another host (a relay by a
## malicious server) or after its expiry is refused; tokens are stored hashed and are
## only sent back to the URL that issued them. Prints measured bandwidth.
## The activity feed (NetEvents): sign-ins, arrivals, guests, places, claims, games and
## their agreed results, board records reach the right players (signed-in or the room),
## within their limits, and a reconnect inside the grace is not news. "Join me" requests
## go through the invite book (no match opened).
## The daily challenge (NetDaily): attempts start only signed in, a run is scored by the server's
## replay of its input log (a forged score and a too-early run are refused), three tries a day, the
## rate limit, plain scores can't reach a daily board, a #1 is a daily_record event, and the next
## UTC day is a new board with yesterday's winner. Its seed block comes from a fixture here (no network).
##   godot --headless --path . -s res://tools/net_selftest.gd [-- --url=ws://127.0.0.1:8787 | --port=18787]
## Without --url it starts its own server in this process (port 18787, data in
## user://server_selftest). Exit code 0 = every check passed.

const ROOM := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const KEY_A := "0x8b2a5c8f8e1f1c6f3d9a0b4e2c7d5f1a9e3b6c8d0f2a4c6e8b1d3f5a7c9e0b2d"
const KEY_B := "0x2f6c8e1a3b5d7f9e0c2a4b6d8f1e3c5a7b9d0e2f4a6c8b1d3e5f7a9c0b2d4e6f"
const KEY_C := "0x5d3a7c9e1b2f4a6c8e0d2b4f6a8c1e3d5f7b9a0c2e4d6f8a1b3c5e7d9f0a2b4c"

var failures := 0
var checks := 0
var server: Node
var clients: Array = []
var evs := {}  # client name → [events]


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
	evs[label] = []
	c.event.connect(func(ev): evs[label].append(ev))
	return c


## Events of kind `k` that client `label` got (about `w`, when given).
func got_ev(label: String, k: String, w: String = "") -> Array:
	return (evs.get(label, []) as Array).filter(func(e): return e["k"] == k and (w == "" or e.get("w", "") == w))


func _run() -> void:
	Engine.max_fps = 120
	var url := ""
	var port := 18787
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):  # its own server's port (another run may hold 18787)
			port = clampi(int(a.substr(7)), 1024, 65535)
		if a.begins_with("--url="):
			url = a.substr(6)
	if url == "":
		server = load("res://scripts/net/server/game_server.gd").new()
		server.port = port
		server.server_name = "selftest"
		server.data_dir = "user://server_selftest"
		server.quiet = true
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://server_selftest/leaderboards.json"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://server_selftest/daily.json"))
		root.add_child(server)
		var up: bool = server.start()
		ok(up, "server listens on 127.0.0.1:%d" % port)
		if not up:
			print("the port is taken (another server or self-test?): try --port=<free port>")
			quit(1)
			return
		url = "ws://127.0.0.1:%d" % port
	print("server: ", url)

	var a := make_client("A", KEY_A)
	var b := make_client("B", KEY_B)
	var g := make_client("G", "")
	for c in [a, b, g]:
		c.connect_to(url)
	ok(await wait_until(func(): return a.is_online() and b.is_online() and g.is_online(), 8.0), "three clients connected (welcome received)")
	ok(a.my_id != b.my_id and a.login_message.contains(a.nonce), "distinct ids; login message carries the nonce")
	ok(a.login_message.begins_with(NetProto.LOGIN_TITLE + "\n") and a.login_message.contains("\nHost: 127.0.0.1\n") and a.login_message.contains("not a transaction"),
		"the client built the sign-in text itself: title, this host, the nonce, not a transaction")

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
	# A relay: a malicious server got G to sign ITS text (another host) with this server's
	# nonce, and replays it here. Refused before any ecrecover.
	await wait_until(func(): return g.login_message != "", 3.0)
	forged[0] = ""
	var relay_text: String = NetClient.login_for("wss://evil.example/", g.server_name, g.nonce, g.issued)
	g._send(NetProto.json_msg(NetProto.C_AUTH, {"wallet": EthSign.address_of_private(KEY_B), "sig": EthSign.sign_personal(relay_text, KEY_B), "host": "evil.example"}))
	ok(await wait_until(func(): return forged[0] != "", 5.0) and g.wallet == "" and forged[0].contains("another server"), "a sign-in signed for another host (a relay) is refused (%s)" % forged[0])
	# The same signature without saying the host: the server checks it against its own host's text
	await wait_until(func(): return g.login_message != "" and not relay_text.contains(g.nonce), 3.0)
	forged[0] = ""
	relay_text = NetClient.login_for("wss://evil.example/", g.server_name, g.nonce, g.issued)
	g._send(NetProto.json_msg(NetProto.C_AUTH, {"wallet": EthSign.address_of_private(KEY_B), "sig": EthSign.sign_personal(relay_text, KEY_B)}))
	ok(await wait_until(func(): return forged[0] != "", 5.0) and g.wallet == "", "…and without naming the host, it recovers to nobody here (%s)" % forged[0])
	# An expired text: the server's clock for this nonce is moved back past the TTL
	if server:
		await wait_until(func(): return not relay_text.contains(g.nonce), 3.0)
		forged[0] = ""
		var gp = server._peers.get(g.my_id)
		gp.issued -= NetProto.LOGIN_TTL_S + 5
		g._send(NetProto.json_msg(NetProto.C_AUTH, {"wallet": EthSign.address_of_private(KEY_B), "sig": EthSign.sign_personal(
			NetClient.login_for(g.url, g.server_name, g.nonce, gp.issued), KEY_B), "host": "127.0.0.1"}))
		ok(await wait_until(func(): return forged[0] != "", 5.0) and g.wallet == "" and forged[0].contains("expired"), "an expired sign-in text is refused (%s)" % forged[0])
		var toks := FileAccess.get_file_as_string("user://server_selftest/tokens.json")
		ok(toks != "" and not toks.contains(a.token) and not toks.contains(b.token) and toks.contains(a.token.sha256_text()), "the server stores session tokens hashed, never the tokens")

	# ── rooms and presence ──
	a.join(ROOM, {"name": "Alice", "head": "rat", "acc": ["crown"], "body": "female"})
	b.join(ROOM, {"name": "Bob", "head": "fox", "acc": [], "body": "male"})
	g.join(ROOM, {"name": "", "head": "bear", "acc": [], "body": "male"})
	ok(await wait_until(func(): return b.peers.has(a.my_id) and a.peers.has(b.my_id) and b.peers.has(g.my_id), 5.0), "peers see each other in the QING room")
	ok(String(b.peers.get(a.my_id, {}).get("name", "")) == "Alice" and String(b.peers[a.my_id]["wallet"]) == a.wallet, "B sees A's name and verified wallet")
	ok(bool(b.peers.get(g.my_id, {}).get("guest", false)), "B sees G as a guest")
	await _events(url, a, b, g)
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

	await _invites(a, b, g)

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
	ok(await wait_until(func(): return not got_ev("B", "record", a.wallet).is_empty(), 3.0), "B is told A set a new #1 on the board (record event)")
	if not got_ev("B", "record", a.wallet).is_empty():
		var rec: Dictionary = got_ev("B", "record", a.wallet)[0]
		ok(int(rec["score"]) == 4200 and rec["board"] == board and not rec["verified"], "…with the score, the board and its check: %s" % NetEvents.format(rec))
	ok(got_ev("G", "record").is_empty(), "a guest is not sent signed-in players' events")
	await _daily(a, b, g)

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

	# ── places: "<qing>/arcade" is a room of its own (PlaceBase's presence) ──
	await _places(a, b, g)

	# ── malformed input from a signed-in client: wrong JSON types, truncated binary ──
	# Every handler must shrug (refuse, strike or ignore): no script error on the server
	# (the run's output is checked for "SCRIPT ERROR" by tools/net_audit.sh), no crash,
	# and the well-behaved players are not disturbed.
	await _fuzz(url)
	ok(a.is_online() and b.is_online(), "after the malformed-input barrage A and B are still connected")
	var probe := make_client("P", "")
	probe.connect_to(url)
	ok(await wait_until(func(): return probe.is_online(), 5.0), "the server still welcomes new players")
	probe.close()

	# ── reconnect with the session token: no new signature ──
	var tok: String = a.token
	var signed := [0]
	a.signer = func(message: String) -> String:
		signed[0] += 1
		return EthSign.sign_personal(message, KEY_A)
	_await_resync = true
	var b_online0 := got_ev("B", "online", a.wallet).size()
	a.close()
	ok(await wait_until(func(): return not b.peers.has(a.my_id) or b.peers.size() < 3, 5.0), "B saw A leave")
	var first_seen := {}  # peer id → the first S_PEER B got for it
	b.peer_joined.connect(func(id, info):
		if not first_seen.has(id):
			first_seen[id] = (info as Dictionary).duplicate())
	var g_guest0 := got_ev("B", "guest").size() + got_ev("G", "guest").size()
	a.token = tok
	a.connect_to(url)
	a.room = ROOM
	ok(await wait_until(func(): return a.wallet != "", 8.0) and signed[0] == 0, "A reconnected and signed in by token (no wallet prompt)")
	ok(await wait_until(func(): return b.peers.values().any(func(p): return p.get("wallet", "") == a.wallet), 5.0), "B sees A back in the room")
	ok(first_seen.has(a.my_id) and String(first_seen[a.my_id].get("wallet", "")) == a.wallet,
		"a token reconnect joins the room already signed in (B's first sight of A names its wallet, not 'guest')")
	ok(got_ev("B", "guest").size() + got_ev("G", "guest").size() == g_guest0, "…and the room is not told 'a guest arrived'")
	ok(await wait_until(func(): return _resynced, 5.0), "after the reconnect the server sent A its games again (S_MATCH %s)" % _match_id)
	await wait_s(1.5)
	ok(got_ev("B", "online", a.wallet).size() == b_online0 and got_ev("B", "offline", a.wallet).is_empty(), "a reconnect inside the grace is not news: no went offline / came online for A")

	# A token goes back only to the server that issued it
	var kept: String = a.token
	a.connect_to("ws://127.0.0.1:1")
	ok(kept != "" and a.token == "", "connecting to another server URL drops the session token (it is never sent elsewhere)")
	a.close()

	# ── everyone leaves: the server keeps nothing of them (no ghost peers or rooms) ──
	for c in clients:
		c.close()
	if server:
		ok(await wait_until(func(): return server._peers.is_empty() and server._rooms.is_empty(), 5.0),
			"everyone left: no peers, no rooms left on the server (%d, %d)" % [server._peers.size(), server._rooms.size()])
		ok(await wait_until(func(): return server._orphan_tasks.is_empty(), 5.0), "no signature check left waiting")
		print("      server stats: ", JSON.stringify(server.stats))
	print("\n%d checks, %d failed" % [checks, failures])
	await wait_s(0.3)
	if server:
		server.stop()
	quit(1 if failures > 0 else 0)


## A and B walk into the arcade of ROOM (room "<ROOM>/arcade"); G stays outside.
func _places(a: Node, b: Node, g: Node) -> void:
	var arcade := ROOM + "/arcade"
	a.join(arcade, a.profile)
	b.join(arcade, b.profile)
	ok(await wait_until(func(): return not g.peers.has(a.my_id) and not g.peers.has(b.my_id), 5.0), "G (outside) sees A and B leave into the arcade")
	a.send_state(Vector3(1, 0, 2), 0.0, NetProto.F_ON_FLOOR, 0, true)
	b.send_state(Vector3(2, 0, 2), 0.0, NetProto.F_ON_FLOOR, 0, true)
	ok(await wait_until(func(): return a.peers.has(b.my_id) and b.peers.has(a.my_id) and not a.peers.has(g.my_id), 5.0), "in the arcade A and B see each other, not G")
	ok(await wait_until(func(): return not b.peer_pose(a.my_id, Time.get_ticks_msec()).is_empty(), 3.0), "B gets A's pose in the arcade")
	var heard_g := []
	var heard_b := []
	g.chat.connect(func(_i, _w, _n, t, _p): heard_g.append(t))
	b.chat.connect(func(_i, _w, _n, t, _p): heard_b.append(t))
	await wait_s(1.2)
	a.send_chat("in the arcade")
	ok(await wait_until(func(): return heard_b.has("in the arcade"), 3.0) and not heard_g.has("in the arcade"), "say-chat in the arcade reaches the arcade only")
	var arr0 := got_ev("G", "arrive").size() + got_ev("G", "guest").size()
	a.join(ROOM, a.profile)
	b.join(ROOM, b.profile)
	ok(await wait_until(func(): return g.peers.has(a.my_id) and g.peers.has(b.my_id), 5.0), "back outside: G sees them again")
	await wait_s(0.5)
	ok(got_ev("G", "arrive").size() + got_ev("G", "guest").size() == arr0, "coming back out of the arcade is not a new arrival")
	a.send_state(Vector3(0, 2, 0), 0.0, NetProto.F_ON_FLOOR, 0, true)
	b.send_state(Vector3(3, 2, 0), 0.0, NetProto.F_ON_FLOOR, 0, true)
	await wait_s(0.3)


const KEY_Z := "0x7e1c3a5b9d2f4e6a8c0b1d3f5e7a9c2b4d6f8e0a1c3b5d7f9e2a4c6b8d0f1e3a"


## A signed-in client sends every message type with wrong JSON types and every
## binary type truncated. A fresh client whenever the server kicks one (strikes).
func _fuzz(url: String) -> void:
	var weird := [{}, [], [1, 2], "x", -1, 1e300, true, null, {"a": {}}]
	var keys := ["req", "room", "name", "head", "acc", "body", "text", "board", "entry", "n", "to", "game", "stake",
		"door", "id", "answer", "match", "op", "a", "winner", "digest", "token", "wallet", "sig", "host", "place", "claim",
		"day", "attempt", "score", "log"]
	var json_types := [NetProto.C_AUTH, NetProto.C_JOIN, NetProto.C_CHAT, NetProto.C_LB_SUBMIT, NetProto.C_LB_TOP,
		NetProto.C_PROFILE, NetProto.C_INFO, NetProto.C_ONLINE, NetProto.C_INVITE, NetProto.C_ANSWER, NetProto.C_MOVE,
		NetProto.C_RESULT, NetEvents.C_PLACE, NetEvents.C_CLAIM, NetDaily.C_DAILY_START, NetDaily.C_DAILY_SUBMIT, NetDaily.C_DAILY_BOARD]
	var msgs: Array = []
	for t in json_types:
		for w in weird:
			var body := {}
			for k in keys:
				body[k] = w
			msgs.append(NetProto.json_msg(t, body))
		msgs.append(NetProto.json_msg(t, {"entry": {"score": {}}, "a": [{}, [], "1"], "acc": [{}, 5, null]}))
		var raw := PackedByteArray([t])
		raw.append_array("[1,2,3]".to_utf8_buffer())
		msgs.append(raw)
		var bad := PackedByteArray([t, 0xff, 0xfe, 0x00, 0x7b])
		msgs.append(bad)
	for t in [NetProto.C_STATE, NetProto.C_PING, NetProto.C_VOICE, NetBump.C_BUMP, NetProto.C_LEAVE]:
		for n in range(1, 20):
			var b := PackedByteArray([t])
			for i in n - 1:
				b.append(randi() % 256)
			msgs.append(b)
	var z: Node = null
	var sent := 0
	var kicked := 0
	for msg in msgs:
		if z == null or not z.is_online():
			if z != null:
				kicked += 1
				z.close()
			z = make_client("Z%d" % kicked, KEY_Z)
			z.connect_to(url)
			await wait_until(func(): return z.is_online(), 5.0)
			z.sign_in()
			await wait_until(func(): return z.wallet != "", 5.0)
			z.join(ROOM, {"name": "fuzz"})
			z.send_state(Vector3(1, 2, 3), 0.0, 0, 0, true)
			await wait_s(0.2)
		z._send(msg)
		sent += 1
		if sent % 6 == 0:
			await wait_s(0.25)  # under the message and byte buckets: this is about content, not floods
	await wait_s(0.5)
	print("      fuzz: %d malformed messages from signed-in clients, %d kicked for strikes" % [sent, kicked])
	if z:
		z.close()


## The daily challenge over this server (needs the in-process server: its clock moves the day).
func _daily(a: Node, b: Node, g: Node) -> void:
	if server == null:
		print("      daily: skipped (needs the in-process server)")
		return
	# A fixture for the chain: the self-test runs without a network. Never used by the game.
	var fixture := "0x" + "5e".repeat(32)
	DailySeed.use_file = false
	DailySeed.clear()
	DailySeed.override = func(_d): return {"ok": true, "block": 28000000, "hash": fixture, "timestamp": 0}
	var base := int(Time.get_unix_time_from_system())
	var off := [0]
	server.daily.clock = func(): return base + off[0]
	var day: String = server.daily.today()
	ok(a.features.has("daily") and a.has_daily(), "the welcome lists \"daily\"")
	var empty: Dictionary = await b.daily_board(day)
	ok(empty.get("ok", false) and (empty["rows"] as Array).is_empty() and empty["game"] == DailyChallenge.game_for(day), "today's board starts empty, for %s" % empty.get("game"))
	var gs: Dictionary = await g.daily_start(day)
	ok(not gs.get("ok", true) and String(gs.get("error", "")).contains("sign in"), "a guest can't start a scored try (%s)" % gs.get("error"))
	var st: Dictionary = await a.daily_start(day)
	ok(st.get("ok", false) and int(st.get("attempt", 0)) == 1 and int(st.get("left", -1)) == 2, "A starts try 1 of 3: %s" % st)
	server._peers[a.my_id].b_daily = TokenBucket.new(100.0, 100.0)  # the rate limit is checked with G below
	# A real run of the day's game on the day's seed, recorded (as a client records it).
	var gid := DailyChallenge.game_for(day)
	var seed := DailyChallenge.seed_from_hash(day, fixture)
	var gm = load(DailyChallenge.script_of(gid)).new()
	gm.recording = true
	gm.scripted_input = 0
	gm.start(seed)
	for i in 1800:
		if not gm.playing:
			break
		gm.scripted_input = (ArcadeGame.IN_FIRE if i % 50 < 20 else 0) | (ArcadeGame.IN_LEFT if (i / 90) % 2 == 0 else ArcadeGame.IN_RIGHT)
		gm.step(ArcadeGame.DT)
	if gm.playing:
		gm.end_game()
	var score: int = gm.score
	var log_text := DailyChallenge.encode_log(gm.rec_start, gm.rec_steps)
	var secs: float = gm.rec_steps.size() / 60.0
	gm.free()
	var early: Dictionary = await a.daily_submit(day, 1, score, log_text)
	ok(secs < 5.0 or (not early.get("ok", true) and String(early.get("error", "")).contains("longer than the time")), "a %.0f s run sent at once is refused (%s)" % [secs, early.get("error")])
	off[0] = 120
	var forged: Dictionary = await a.daily_submit(day, 1, score + 500, log_text)
	ok(not forged.get("ok", true) and String(forged.get("error", "")).contains("replay") and int(forged.get("score", -1)) == score,
		"a forged score is refused by the replay (%s)" % forged.get("error"))
	var good: Dictionary = await a.daily_submit(day, 1, score, log_text)
	ok(good.get("ok", false) and int(good.get("score", -1)) == score and int(good.get("rank", 0)) == 1 and good.get("verified", false),
		"the true score is replayed, verified, #1: %d (%s)" % [score, good.get("check", good.get("error"))])
	var again: Dictionary = await a.daily_submit(day, 1, score, log_text)
	ok(not again.get("ok", true) and String(again.get("error", "")).contains("already"), "one score per try (%s)" % again.get("error"))
	var never: Dictionary = await a.daily_submit(day, 3, score, log_text)
	ok(not never.get("ok", true) and String(never.get("error", "")).contains("never started"), "a try that was never started takes no score")
	ok(await wait_until(func(): return not got_ev("B", "daily_record", a.wallet).is_empty(), 3.0), "B is told A took #1 (daily_record event)")
	if not got_ev("B", "daily_record", a.wallet).is_empty():
		var ev: Dictionary = got_ev("B", "daily_record", a.wallet)[0]
		ok(ev["board"] == DailyChallenge.board_id(day) and int(ev["score"]) == score and ev["game"] == gid, "…%s" % NetEvents.format(ev))
	ok(got_ev("G", "daily_record").is_empty(), "a guest is not sent it")
	var s2: Dictionary = await a.daily_start(day)
	var s3: Dictionary = await a.daily_start(day)
	var s4: Dictionary = await a.daily_start(day)
	ok(s2.get("ok", false) and s3.get("ok", false) and not s4.get("ok", true) and String(s4.get("error", "")).contains("no scored attempts left"),
		"three tries a day: the 4th is refused (%s)" % s4.get("error"))
	var plain: Dictionary = await a.lb_submit(DailyChallenge.board_id(day), {"score": 999999})
	ok(not plain.get("ok", true), "a plain score can't reach a daily board (%s)" % plain.get("error"))
	var lbt: Dictionary = await b.lb_top(DailyChallenge.board_id(day), 10)
	ok(lbt.get("ok", false) and (lbt["rows"] as Array).size() == 1 and lbt["rows"][0]["wallet"] == a.wallet, "C_LB_TOP reads the daily board too")
	var ab: Dictionary = await a.daily_board(day)
	ok(ab.get("ok", false) and int(ab["me"]["rank"]) == 1 and int(ab["me"]["used"]) == 3 and int(ab["me"]["streak"]) == 1 and ab["seed"]["state"] == "ok",
		"A's board: #1, 3 tries used, streak 1, the seed block: %s" % ab.get("me"))
	var bb: Dictionary = await b.daily_board(day)
	ok(bb.get("ok", false) and int(bb["me"]["rank"]) == 0 and bb["rows"][0]["wallet"] == a.wallet and bb["rows"][0]["verified"], "B sees A's verified row, and no rank of its own")
	# The rate limit: a guest asking for the board in a burst
	var slow := 0
	for i in 8:
		var r: Dictionary = await g.daily_board(day)
		if not r.get("ok", false) and String(r.get("error", "")).contains("slow down"):
			slow += 1
	ok(slow > 0, "the daily messages are rate-limited (%d of 8 refused)" % slow)
	# 00:00 UTC: a new day, a new board and new tries; yesterday's winner is A
	off[0] = DailyChallenge.seconds_left(base) + 30 + DailyChallenge.GRACE_S
	var day2: String = server.daily.today()
	var nb: Dictionary = await b.daily_board(day2)
	ok(day2 != day and nb.get("ok", false) and (nb["rows"] as Array).is_empty() and nb["yesterday"]["winner"].get("wallet", "") == a.wallet,
		"the reset: %s's board is empty, yesterday's winner is A" % day2)
	var old: Dictionary = await a.daily_submit(day, 2, 0, "v1:0:")
	ok(not old.get("ok", true) and String(old.get("error", "")).contains("closed"), "yesterday's board is closed (%s)" % old.get("error"))
	var n1: Dictionary = await a.daily_start(day2)
	ok(n1.get("ok", false) and int(n1.get("attempt", 0)) == 1, "a new day's first try starts")
	var ab2: Dictionary = await a.daily_board(day2)
	ok(int(ab2.get("me", {}).get("streak", 0)) == 2, "two days in a row: streak 2")
	server.daily.clock = Callable()
	DailySeed.override = Callable()
	DailySeed.clear()


var _match_id := ""
var _await_resync := false
var _resynced := false


## Invites and a head-to-head game over the server: who is online, invite /
## decline / cancel / accept / expire, the stake confirmations, moves relayed in
## order with the server's stamp, both machines replaying the same pool table
## (NetMatch), agreed results, and the limits (guests, strangers, rate, bad moves).
func _invites(a: Node, b: Node, g: Node) -> void:
	var seen := {"a": [], "b": []}  # invites as each side received them
	var recs := {"a": {}, "b": {}}  # match records, with S_MOVE appended in order
	var refused := {"a": [], "b": [], "g": []}
	var online := {"a": null, "g": null}
	for pair in [["a", a], ["b", b]]:
		var k: String = pair[0]
		var c: Node = pair[1]
		c.invite_update.connect(func(inv): seen[k].append(inv.duplicate()))
		c.match_update.connect(func(r):
			recs[k][r["id"]] = r
			if k == "a" and _await_resync and r["id"] == _match_id:
				_resynced = true)
		c.match_move.connect(func(mid, mv):
			var r: Dictionary = recs[k].get(mid, {})
			if not r.is_empty() and int(mv["seq"]) == (r["log"] as Array).size() + 1:
				r["log"].append(mv))
		c.refused.connect(func(what, err): refused[k].append("%s: %s" % [what, err]))
	g.refused.connect(func(what, err): refused["g"].append("%s: %s" % [what, err]))
	a.online_list.connect(func(okk, rows, _e): online["a"] = [okk, rows])
	g.online_list.connect(func(okk, rows, err): online["g"] = [okk, rows, err])
	var last := func(k: String) -> Dictionary: return seen[k][-1] if not seen[k].is_empty() else {}

	# who is online: signed-in players only, never yourself, guests can't ask
	g.request_online()
	a.request_online()
	ok(await wait_until(func(): return online["a"] != null and online["g"] != null, 5.0), "online lists answered")
	if online["a"] != null:
		var rows: Array = online["a"][1]
		ok(online["a"][0] and rows.size() == 1 and rows[0]["wallet"] == b.wallet and rows[0]["name"] == "Bob" and rows[0]["room"] == ROOM,
			"A sees B online (name, room), not itself, not the guest: %s" % JSON.stringify(rows))
	if online["g"] != null:
		ok(not online["g"][0] and (online["g"][1] as Array).is_empty(), "a guest can't list who is online (%s)" % online["g"][2])

	# refusals: a guest can't invite; nobody can invite a guest or a stranger
	g.invite(a.wallet, "pool", "", ROOM)
	b.invite("0x" + "42".repeat(20), "pool", "", ROOM)
	ok(await wait_until(func(): return refused["g"].size() >= 1 and refused["b"].size() >= 1, 5.0), "a guest can't invite; an offline wallet can't be invited (%s | %s)" % [refused["g"], refused["b"]])
	refused["b"].clear()

	# invite → decline
	a.invite(b.wallet, "pool", "2", ROOM)
	ok(await wait_until(func(): return not last.call("a").is_empty() and not last.call("b").is_empty(), 5.0), "both players got the invite")
	var inv: Dictionary = last.call("b")
	ok(inv.get("state") == "pending" and inv.get("from") == a.wallet and inv.get("to") == b.wallet and inv.get("stake") == "2" and inv.get("from_name") == "Alice" and inv.get("game") == "pool",
		"B's invite: pending, from Alice's verified wallet, pool, stake 2 Ⓐ")
	ok(int(inv.get("expires", 0)) - int(inv.get("created", 0)) == InviteBook.TTL_S, "it expires after %d s" % InviteBook.TTL_S)
	b.answer_invite(String(inv.get("id", "")), "cancel")
	ok(await wait_until(func(): return refused["b"].size() >= 1, 5.0), "only the inviter can cancel (%s)" % refused["b"])
	b.answer_invite(String(inv.get("id", "")), "decline")
	ok(await wait_until(func(): return last.call("a").get("state") == "declined" and last.call("b").get("state") == "declined", 5.0), "B declined: both see it")

	# invite → cancel
	a.invite(b.wallet, "cards", "", ROOM)
	await wait_until(func(): return last.call("b").get("state") == "pending" and last.call("b").get("game") == "cards", 5.0)
	a.answer_invite(String(last.call("b").get("id", "")), "cancel")
	ok(await wait_until(func(): return last.call("b").get("state") == "cancelled", 5.0), "A cancelled: B sees it")

	# invite → accept → a match
	await wait_s(5.5)  # A's invite bucket: one every 5 s after a burst of 3
	a.invite(b.wallet, "pool", "2", ROOM)
	await wait_until(func(): return last.call("b").get("state") == "pending" and last.call("b").get("game") == "pool", 5.0)
	b.answer_invite(String(last.call("b").get("id", "")), "accept")
	ok(await wait_until(func(): return recs["a"].size() == 1 and recs["b"].size() == 1, 5.0), "accepted: both players got the match")
	ok(last.call("a").get("state") == "accepted" and String(last.call("a").get("match", "")).begins_with("n"), "the invite names its match")
	if recs["a"].is_empty():
		return
	_match_id = String(recs["a"].keys()[0])
	var ra: Dictionary = recs["a"][_match_id]
	ok(ra["players"] == [a.wallet, b.wallet] and ra["stake"] == "2" and ra["room"] == ROOM and ra["names"] == ["Alice", "Bob"],
		"match: the inviter breaks (player 0), stake 2 Ⓐ, at A's QING")

	# the rate limit on invites
	refused["a"].clear()
	a.invite(b.wallet, "cards", "", ROOM)
	ok(await wait_until(func(): return refused["a"].any(func(s): return String(s).contains("Slow down")), 5.0), "invites are rate-limited (%s)" % refused["a"])

	# moves: only the two players; unknown moves are refused; order and stamps from the server
	g.send_move(_match_id, "concede")
	ok(await wait_until(func(): return not refused["g"].is_empty() and String(refused["g"][-1]).begins_with("move"), 5.0), "a guest can't move (%s)" % refused["g"][-1])
	a.send_move(_match_id, "stake_ok")
	b.send_move(_match_id, "stake_ok")
	await wait_until(func(): return (recs["a"][_match_id]["log"] as Array).size() == 2, 5.0)
	a.send_move(_match_id, "shot", [10000, 150, 1000])
	ok(await wait_until(func(): return (recs["a"][_match_id]["log"] as Array).size() == 3 and (recs["b"][_match_id]["log"] as Array).size() == 3, 5.0), "three moves relayed to both")
	var lg: Array = recs["b"][_match_id]["log"]
	ok(lg.size() == 3 and lg[0]["by"] == 0 and lg[1]["by"] == 1 and lg[2]["op"] == "shot" and (lg[2]["a"] as Array).map(func(v): return int(v)) == [10000, 150, 1000] and int(lg[2]["t"]) >= int(lg[0]["t"]) and int(lg[0]["t"]) > 1_600_000_000_000,
		"moves carry seq, the mover's index (from the signed-in wallet), the integers and the server's ms clock")
	var na := NetMatch.replay(recs["a"][_match_id], func(_s): return {})
	var nb := NetMatch.replay(recs["b"][_match_id], func(_s): return {})
	ok(na.m["status"] == "playing" and na.m["stake_state"] == "agreed" and (na.m["game"] as EightBall).shots == 1, "the replay: stake agreed by both, the break played")
	ok(na.digest() == nb.digest(), "both machines replay the same table (%s)" % na.digest().left(12))
	var strikes0: int = server.stats["kicked"] if server else 0
	a.send_move(_match_id, "teleport", [1])
	await wait_s(0.3)
	ok(a.is_online() and (not server or server.stats["kicked"] == strikes0), "an unknown move is a strike, not relayed (A still connected)")
	ok((recs["b"][_match_id]["log"] as Array).size() == 3, "…and B never saw it")

	# the end: B concedes, both report their replay; the server marks it agreed
	b.send_move(_match_id, "concede")
	await wait_until(func(): return (recs["a"][_match_id]["log"] as Array).size() == 4 and (recs["b"][_match_id]["log"] as Array).size() == 4, 5.0)
	na = NetMatch.replay(recs["a"][_match_id], func(_s): return {})
	nb = NetMatch.replay(recs["b"][_match_id], func(_s): return {})
	ok(na.over() and na.m["winner"] == a.wallet and Wager.code(na.m) == "owed", "B conceded: A won; B owes the 2 Ⓐ (honour-bound, checked on chain later)")
	a.send_result(_match_id, na.winner_index(), na.digest())
	b.send_result(_match_id, nb.winner_index(), nb.digest())
	ok(await wait_until(func(): return recs["a"][_match_id]["status"] == "over" and recs["b"][_match_id]["status"] == "over", 5.0), "both results agree: the server marks the game over")
	ok(int(recs["b"][_match_id]["result"].get("winner", -1)) == 0 and recs["b"][_match_id]["result"].get("agreed") == true, "result: player 0, agreed")
	b.send_move(_match_id, "concede")
	ok(await wait_until(func(): return refused["b"].any(func(s): return String(s).contains("over")), 5.0), "no moves after the end")
	ok(got_ev("G", "match").is_empty() and not got_ev("B", "match", a.wallet).is_empty(), "the accepted game was announced to signed-in players (match), not to the guest")
	ok(await wait_until(func(): return not got_ev("B", "result", a.wallet).is_empty(), 3.0), "the agreed result is announced: %s" % (NetEvents.format(got_ev("B", "result", a.wallet)[0]) if not got_ev("B", "result", a.wallet).is_empty() else "—"))
	if not got_ev("B", "result", a.wallet).is_empty():
		var rv: Dictionary = got_ev("B", "result", a.wallet)[0]
		ok(rv["w2"] == b.wallet and rv["game"] == "pool" and rv["stake"] == "2" and not rv.get("push", false), "…A beat B at pool, stake 2 Ⓐ")

	# "Join me": the same book and limits; accepting opens no game
	await wait_s(5.5)
	var m0: int = recs["b"].size()
	a.invite(b.wallet, InviteBook.JOIN, "", ROOM, "arcade")
	ok(await wait_until(func(): return last.call("b").get("game") == InviteBook.JOIN and last.call("b").get("state") == "pending", 5.0), "B got A's join request")
	ok(String(last.call("b").get("door", "x")) == "arcade" and String(last.call("b").get("stake", "x")) == "", "…to the arcade of A's QING, no stake")
	b.answer_invite(String(last.call("b").get("id", "")), "accept")
	ok(await wait_until(func(): return last.call("a").get("state") == "accepted" and last.call("a").get("game") == InviteBook.JOIN, 5.0), "B accepted: A is told")
	await wait_s(0.4)
	ok(recs["b"].size() == m0 and String(last.call("a").get("match", "")) == "", "no game was opened for a join")
	ok(not got_ev("A", "join", b.wallet).is_empty(), "the feed says B is on the way: %s" % (NetEvents.format(got_ev("A", "join", b.wallet)[0]) if not got_ev("A", "join", b.wallet).is_empty() else "—"))
	await wait_s(5.5)
	refused["a"].clear()
	a.invite(b.wallet, InviteBook.JOIN, "5", ROOM, "arcade")
	ok(await wait_until(func(): return not refused["a"].is_empty(), 5.0), "a join request with a stake is refused (%s)" % refused["a"])
	ok(refused["a"].any(func(e): return String(e).contains("stake")), "…because of the stake, not the rate")

	# expiry (in-process server only: its clock is moved, not waited for)
	if server:
		await wait_s(5.0)  # B's invite bucket
		var before: int = seen["a"].size()
		b.invite(a.wallet, "cards", "", ROOM)
		await wait_until(func(): return seen["a"].size() > before, 5.0)
		var id := String(last.call("a").get("id", ""))
		if server.invites.invites.has(id):
			server.invites.invites[id]["expires"] = int(Time.get_unix_time_from_system()) - 1
		ok(await wait_until(func(): return last.call("a").get("state") == "expired" and last.call("b").get("state") == "expired", 4.0), "an unanswered invite expires: both are told")
		ok(server.stats["invites"] >= 4 and server.stats["matches"] == 1, "server counted %d invites, %d match" % [server.stats["invites"], server.stats["matches"]])


class GameServerLimits:
	const MAX_STRIKES := 20


## The activity feed's events (NetEvents) over the server.
func _events(url: String, a: Node, b: Node, g: Node) -> void:
	ok(a.features.has("events"), "the welcome lists the events feature")
	# arrivals: A and B were announced to each other; the guest's arrival to the room only
	ok(await wait_until(func(): return not got_ev("A", "arrive", b.wallet).is_empty() or not got_ev("B", "arrive", a.wallet).is_empty(), 3.0),
		"a signed-in player arriving in a QING is announced (arrive)")
	ok(await wait_until(func(): return not got_ev("A", "guest").is_empty() and not got_ev("B", "guest").is_empty(), 3.0), "the room is told a guest arrived")
	var gev: Array = got_ev("A", "guest")
	ok(not gev.is_empty() and gev[0]["w"] == "" and gev[0]["room"] == ROOM, "the guest event names no one: %s" % (NetEvents.format(gev[0]) if not gev.is_empty() else "—"))
	ok(got_ev("G", "arrive").is_empty() and got_ev("G", "online").is_empty(), "the guest gets no signed-in players' events")
	# a re-join of the same QING is the same visit
	var n0 := got_ev("A", "arrive", b.wallet).size()
	b.leave()
	await wait_s(0.2)
	b.join(ROOM, {"name": "Bob", "head": "fox", "acc": [], "body": "male"})
	await wait_s(0.6)
	ok(got_ev("A", "arrive", b.wallet).size() == n0, "back in the same QING soon after: not announced again")
	# a new signed-in player: everyone signed in is told; then they leave (the grace, moved by the test)
	var c := make_client("C", KEY_C)
	c.connect_to(url)
	await wait_until(func(): return c.is_online(), 5.0)
	c.sign_in()
	ok(await wait_until(func(): return not got_ev("A", "online", c.signer_wallet).is_empty() and not got_ev("B", "online", c.signer_wallet).is_empty(), 8.0),
		"C signed in: A and B see \"came online\" (%s)" % (NetEvents.format(got_ev("A", "online", c.signer_wallet)[0]) if not got_ev("A", "online", c.signer_wallet).is_empty() else "—"))
	ok(got_ev("G", "online").is_empty(), "…the guest does not")
	var cw: String = c.wallet
	c.close()
	if server:
		await wait_until(func(): return server._gone.has(cw), 3.0)
		ok(server._gone.has(cw) and got_ev("A", "offline", cw).is_empty(), "C left: not \"offline\" during the grace")
		server._gone[cw]["at"] -= NetEvents.OFFLINE_GRACE_S + 1.0
		ok(await wait_until(func(): return not got_ev("A", "offline", cw).is_empty(), 3.0), "after the grace: \"went offline\"")
	# places: to the QING's room only; once per place for a while; a guest's place says nothing
	ok(a.send_place("arcade", ROOM), "A says it walked into the arcade")
	ok(await wait_until(func(): return not got_ev("B", "place", a.wallet).is_empty(), 3.0), "B (in that QING) is told: %s" % (NetEvents.format(got_ev("B", "place", a.wallet)[0]) if not got_ev("B", "place", a.wallet).is_empty() else "—"))
	ok(not a.send_place("arcade", ROOM), "the client doesn't repeat the same place at once")
	a._send(NetEvents.place_msg("arcade", ROOM))  # past the client's own check
	g._send(NetEvents.place_msg("pub", ROOM))
	await wait_s(0.5)
	ok(got_ev("B", "place", a.wallet).size() == 1, "the server drops a repeat of the same place")
	ok(got_ev("B", "place").filter(func(e): return e["place"] == "pub").is_empty(), "a guest's place is not announced")
	# a bad place is a strike, not an event
	var bad := PackedByteArray([NetEvents.C_PLACE])
	bad.append_array("{\"place\":\"vault\",\"room\":\"x\"}".to_utf8_buffer())
	var strikes0: int = server._peers[a.my_id].strikes if server else 0
	a._send(bad)
	await wait_s(0.3)
	ok(not server or server._peers[a.my_id].strikes == strikes0 + 1, "an unknown place is a strike")
	# the sender's limit: a burst of places (different ones) is cut to the bucket's burst
	var before := got_ev("B", "place", a.wallet).size()
	for pl in ["pub", "hall", "void", "pub", "hall", "void"]:
		a._send(NetEvents.place_msg(pl, ROOM))
	await wait_s(0.6)
	var more := got_ev("B", "place", a.wallet).size() - before
	ok(more >= 1 and more <= int(NetEvents.SENDER_BURST), "a burst of places is rate-limited: %d of 6 relayed" % more)
	# a claim: relayed as a claim (receivers check the chain before showing it)
	await wait_s(5.5)  # A's event bucket refills a little
	ok(a.send_claim("rocket", ROOM), "A claims the rocket")
	ok(await wait_until(func(): return not got_ev("B", "claim", a.wallet).is_empty(), 3.0), "B gets the claim, to be checked on the chain (NetActivity) before it is shown")
