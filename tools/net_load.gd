extends SceneTree
## Load check for the game server (docs/AUDIT_NET_2026-11-26.md): N scripted players
## in one process, each its own connection and throwaway test key, signed in (or
## guests), walking circles in one QING room at 10 Hz; some talk (voice frames of a
## tone, real time). Prints what one player receives and sends (bytes/s by kind), the
## presence rate it sees, the round trip, and the server's own counters (C_INFO).
## Optional reconnect storm: every player drops and reconnects R times.
##   godot --headless --path . -s res://tools/net_load.gd -- --url=ws://127.0.0.1:8787
##       [--n=20] [--seconds=60] [--talkers=2] [--guests=0] [--qing=0x…] [--storm=0]
## Never touches the chain. Exit 0 when every player connected, signed in and saw all
## the others (and, after a storm, the server holds exactly the players still connected).

const DEFAULT_QING := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"

var clients: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _key(i: int) -> String:
	return "0x" + ("load-test-key-%d" % i).sha256_text()


func _make(i: int, url: String, guest: bool) -> Node:
	var c: Node = load("res://scripts/net/net_client.gd").new()
	c.name = "L%d" % i
	root.add_child(c)
	if not guest:
		var k := _key(i)
		c.signer_wallet = EthSign.address_of_private(k)
		c.signer = func(m: String) -> String: return EthSign.sign_personal(m, k)
	c.connect_to(url)
	return c


func _wait(cond: Callable, s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > s * 1000.0:
			return false
		await process_frame
	return true


func _run() -> void:
	Engine.max_fps = 60
	var url := "ws://127.0.0.1:8787"
	var n := 20
	var secs := 60.0
	var talkers := 2
	var guests := 0
	var qing := DEFAULT_QING
	var storm := 0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"url": url = v
			"n": n = clampi(int(v), 1, 200)
			"seconds": secs = float(v)
			"talkers": talkers = int(v)
			"guests": guests = int(v)
			"qing": qing = v
			"storm": storm = int(v)
	var ok := true
	# who is there already (other players, a game client watching): the counts below are on top
	var probe := _make(9999, url, true)
	await _wait(func(): return probe.is_online(), 10.0)
	var base_info := await _info(probe)
	var base := int(base_info.get("connections", 1)) - 1
	var base_room := 0
	for r in base_info.get("rooms", []):
		if String(r.get("room", "")) == qing.to_lower():
			base_room = int(r.get("players", 0))
	probe.close()
	print("[load] already there: %d connections, %d in the room" % [base, base_room])
	var t0 := Time.get_ticks_msec()
	for i in n:
		clients.append(_make(i, url, i >= n - guests))
	ok = await _wait(func(): return clients.all(func(c): return c.is_online()), 20.0)
	print("[load] %d/%d connected in %d ms" % [clients.filter(func(c): return c.is_online()).size(), n, Time.get_ticks_msec() - t0])
	var t1 := Time.get_ticks_msec()
	for c in clients:
		if c.signer_wallet != "":
			c.sign_in()
	var signed_ok: bool = await _wait(func(): return clients.all(func(c): return c.signer_wallet == "" or c.wallet != ""), 60.0)
	print("[load] %d signed in in %d ms (server checks 4 signatures a second)" % [clients.filter(func(c): return c.wallet != "").size(), Time.get_ticks_msec() - t1])
	ok = ok and signed_ok
	for i in clients.size():
		clients[i].join(qing, {"name": "load%d" % i, "head": "fox", "acc": [], "body": "male"})
	var all_seen: bool = await _wait(func(): return clients.all(func(c): return c.peers.size() == n - 1 + base_room), 20.0)
	print("[load] every player sees the %d others: %s" % [n - 1 + base_room, all_seen])
	ok = ok and all_seen
	# walk and talk
	for c in clients:
		for k in c.counters:
			c.counters[k] = 0
	var tone := PackedFloat32Array()
	tone.resize(NetProto.VOICE_FRAME)
	for i in tone.size():
		tone[i] = 0.4 * sin(TAU * 300.0 * i / NetProto.VOICE_RATE)
	var sent := 0
	var tw := Time.get_ticks_msec()
	var poses := {}  # sampled pose updates seen by client 0 (distinct snapshots)
	var frames := 0
	var worst_frame := 0
	var last := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < secs * 1000.0:
		var now := Time.get_ticks_msec()
		worst_frame = maxi(worst_frame, now - last)
		last = now
		frames += 1
		for i in clients.size():
			var ang := i * TAU / n + now / 1000.0 * 3.0 / 6.0
			clients[i].send_state(Vector3(cos(ang), 0, sin(ang)) * 6.0, -ang, NetProto.F_ON_FLOOR, 0)
		var due := int((now - tw) / 20.0)
		while sent < due:
			for i in mini(talkers, clients.size()):
				clients[i].send_voice(sent & 0xFFFF, NetProto.CODEC_ADPCM, VoiceCodec.encode_adpcm(tone, [0, 0]))
			sent += 1
		await process_frame
	var el := (Time.get_ticks_msec() - tw) / 1000.0
	var c0: Node = clients[n - 1]  # a listener (not a talker)
	print("[load] %.0f s, %d players, %d talking: one listener receives %.0f B/s (presence %.0f, voice %.0f), sends %.0f B/s; rtt %d ms" % [
		el, n, talkers, c0.counters["bytes_in"] / el, c0.counters["state_bytes_in"] / el, c0.counters["voice_bytes_in"] / el,
		c0.counters["bytes_out"] / el, c0.rtt_ms])
	var total_in := 0
	for c in clients:
		total_in += int(c.counters["bytes_in"])
	print("[load] the server sent %.0f KB/s to all %d (≈ %.2f Mbit/s of payload); this process: %d frames, worst gap %d ms" % [
		total_in / el / 1000.0, n, total_in / el * 8.0 / 1e6, frames, worst_frame])
	var info := await _info(clients[0])
	print("[load] server: ", JSON.stringify(info))
	# reconnect storm: everyone drops and comes back, `storm` times
	for r in storm:
		for c in clients:
			c.close()
		await _wait(func(): return false, 0.3)
		for c in clients:
			c.connect_to(url)
			c.room = qing
		var back: bool = await _wait(func(): return clients.all(func(c): return c.is_online()), 20.0)
		for c in clients:
			if c.signer_wallet != "" and c.token == "":
				c.sign_in()
		await _wait(func(): return clients.all(func(c): return c.signer_wallet == "" or c.wallet != ""), 60.0)
		print("[load] storm %d: all back %s" % [r + 1, back])
		ok = ok and back
	if storm > 0:
		await _wait(func(): return clients.all(func(c): return c.peers.size() == n - 1 + base_room), 20.0)
		var inf := await _info(clients[0])
		var conns := int(inf.get("connections", -1))
		print("[load] after the storm the server holds %d connections (expected %d: no ghosts), every player sees %d others: %s" % [conns, n + base, n - 1 + base_room,
			clients.all(func(c): return c.peers.size() == n - 1 + base_room)])
		ok = ok and conns == n + base and clients.all(func(c): return c.peers.size() == n - 1 + base_room)
	for c in clients:
		c.close()
	print("[load] %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)


func _info(c: Node) -> Dictionary:
	var got := [{}]
	c.last_info = {}
	c._send(NetProto.json_msg(NetProto.C_INFO, {"req": 77}))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		if c.last_info.size() > 0:
			got[0] = c.last_info
			break
	return got[0]
