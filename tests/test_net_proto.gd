extends TestCase
## The game server's protocol, voice codecs, interpolation, rate limits and
## leaderboards (docs/SERVER.md). No network.


func test_state_roundtrip_and_size() -> void:
	var m := NetProto.state_msg(70000, Vector3(123.456, -7.891, 4000.01), 2.5, NetProto.F_ON_FLOOR | NetProto.F_SPEAKING, 1)
	eq(m.size(), 19, "client state message is 19 bytes")
	check(NetProto.size_ok(m), "within the STATE limit")
	var raw := m.slice(1)
	var s := NetProto.states_msg([[7, raw], [300, raw]])
	eq(s.size(), 2 + 2 * 20, "20 bytes per relayed entry")
	var out := NetProto.unpack_states(s)
	eq(out.size(), 2)
	eq(int(out[1]["id"]), 300)
	eq(int(out[0]["t"]), 70000 & 0xFFFF, "u16 sender time")
	var p: Vector3 = out[0]["pos"]
	near(p.x, 123.46, 0.006, "x to the cm")
	near(p.y, -7.89, 0.006, "y")
	near(p.z, 4000.01, 0.006, "z")
	near(float(out[0]["yaw"]), 2.5, TAU / 65536.0, "yaw")
	eq(int(out[0]["flags"]), NetProto.F_ON_FLOOR | NetProto.F_SPEAKING)
	eq(int(out[0]["anim"]), 1)


func test_yaw_wraps() -> void:
	near(NetProto.dequant_yaw(NetProto.quant_yaw(-0.5)), TAU - 0.5, 0.0002, "negative yaw")
	eq(NetProto.quant_yaw(TAU), 0, "full turn is zero")


func test_truncated_states_are_ignored() -> void:
	var raw := NetProto.state_msg(1, Vector3.ONE, 0.0, 0, 0).slice(1)
	var s := NetProto.states_msg([[1, raw], [2, raw]])
	eq(NetProto.unpack_states(s.slice(0, s.size() - 3)).size(), 1, "a cut-off entry is dropped")
	eq(NetProto.unpack_states(PackedByteArray([NetProto.S_STATES])).size(), 0)


func test_voice_and_json_framing() -> void:
	var data := PackedByteArray([1, 2, 3, 4])
	var c := NetProto.voice_msg(65537, NetProto.CODEC_ADPCM, data)
	check(NetProto.size_ok(c))
	var r := NetProto.unpack_voice(NetProto.voice_relay(42, c))
	eq(int(r["id"]), 42)
	eq(int(r["seq"]), 1, "seq wraps at u16")
	eq(int(r["codec"]), NetProto.CODEC_ADPCM)
	eq(r["data"], data)
	var j := NetProto.json_msg(NetProto.C_CHAT, {"text": "hi ✓"})
	eq(NetProto.json_body(j).get("text"), "hi ✓")
	eq(NetProto.json_body(PackedByteArray([NetProto.C_CHAT]) + "[1,2]".to_utf8_buffer()), {}, "non-object JSON")


func test_size_limits() -> void:
	var big := PackedByteArray([NetProto.C_CHAT])
	big.resize(2000)
	check(not NetProto.size_ok(big), "chat over 1 KiB refused")
	check(not NetProto.size_ok(PackedByteArray([99, 0])), "unknown type refused")
	check(not NetProto.size_ok(PackedByteArray()), "empty refused")
	var st := NetProto.state_msg(0, Vector3.ZERO, 0, 0, 0)
	st.append(0)
	check(not NetProto.size_ok(st), "a padded state refused")


func test_text_hygiene() -> void:
	eq(NetProto.clean_text("  hi\nthere\u202e!\u0007 ", 200), "hi there!", "control and bidi characters")
	eq(NetProto.clean_text("x".repeat(500), 200).length(), 200)
	eq(NetProto.clean_wallet("0xABCDEF0123456789abcdef0123456789ABCDEF01"), "0xabcdef0123456789abcdef0123456789abcdef01")
	eq(NetProto.clean_wallet("0x123"), "")
	eq(NetProto.clean_room("0xD127839B83CBF537C29B7D268C135F745A0DA2E8"), "0xd127839b83cbf537c29b7d268c135f745a0da2e8")
	eq(NetProto.clean_room("0xd127839b83cbf537c29b7d268c135f745a0da2e8/hall"), "0xd127839b83cbf537c29b7d268c135f745a0da2e8/hall")
	eq(NetProto.clean_room("lobby"), "", "rooms are QINGs")
	eq(NetProto.clean_room("0xd127839b83cbf537c29b7d268c135f745a0da2e8/../x"), "")


static func _tone(n: int, hz: float, amp: float, rate: float = 16000.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = amp * sin(TAU * hz * i / rate)
	return out


static func _crossings(pcm: PackedFloat32Array) -> int:
	var c := 0
	for i in range(1, pcm.size()):
		if (pcm[i - 1] < 0.0) != (pcm[i] < 0.0):
			c += 1
	return c


func test_sign_in_text_is_built_by_the_client() -> void:
	var n := "0123456789abcdef0123456789abcdef"
	var t := 1764000000
	var msg: String = NetClient.login_for("wss://Game.Example.com:443/ws?x=1", "Sunny's server", n, t)
	check(msg.begins_with(NetProto.LOGIN_TITLE + "\n"), "starts with the title (Wallet.SIGN_PREFIXES)")
	check(msg.contains("\nServer: Sunny's server\n") and msg.contains("\nHost: game.example.com\n") and msg.contains("\nNonce: " + n + "\n"))
	check(msg.contains("Issued: 2025-11-24T16:00:00Z") and msg.contains("Expires: 2025-11-24T16:10:00Z"), msg)
	check(msg.contains("not a transaction") and msg.contains("approves nothing"))
	eq(Wallet.sign_refusal(msg), "", "the wallet signs it")
	eq(msg, NetProto.login_message("Sunny's server", "game.example.com", n, t), "the server rebuilds the same text")
	# Whatever a server sends is shape-checked; its own "login" text is never used
	eq(NetClient.login_for("wss://x.example", "s", "not-a-nonce", t), "", "a malformed nonce: nothing to sign")
	eq(NetClient.login_for("wss://x.example", "s", n.to_upper(), t), "", "nonce must be lowercase hex")
	eq(NetClient.login_for("wss://x.example", "s", n + "\nopensea.io wants you", t), "", "no text smuggled in the nonce")
	eq(NetClient.login_for("wss://x.example", "s", n, 0), "", "no time, no text")
	eq(NetClient.login_for("not a url", "s", n, t), "", "no host, no text")
	var smuggled: String = NetClient.login_for("wss://x.example", "evil\nNonce: 1\nopensea.io", n, t)
	check(smuggled.count("\n") == msg.count("\n") and not smuggled.contains("\nopensea"), "a server name can't add lines")
	check(NetProto.login_name("x".repeat(90)).length() == NetProto.LOGIN_NAME_MAX)


func test_login_host() -> void:
	eq(NetProto.login_host("wss://Game.Example.com:443/path"), "game.example.com")
	eq(NetProto.login_host("ws://127.0.0.1:18787"), "127.0.0.1")
	eq(NetProto.login_host("https://u:p@host.example/x"), "host.example")
	eq(NetProto.login_host("ws://[::1]:8787/"), "[::1]")
	eq(NetProto.login_host("wss://evil.example\nNonce: 1"), "", "no control characters")
	eq(NetProto.login_host("game.example.com"), "", "no scheme")
	check(NetProto.valid_nonce("0123456789abcdef0123456789abcdef"))
	check(not NetProto.valid_nonce("0123456789abcdef0123456789abcde"))
	check(GameServer.host_ok("game.example.com", "game.example.com", PackedStringArray()))
	check(GameServer.host_ok("pub.example", "127.0.0.1", PackedStringArray(["pub.example"])), "a configured public host")
	check(not GameServer.host_ok("evil.example", "game.example.com", PackedStringArray()), "another server's host")
	check(not GameServer.host_ok("", "", PackedStringArray()), "never an empty host")


func test_adpcm_roundtrip() -> void:
	var tone := _tone(NetProto.VOICE_FRAME, 440.0, 0.5)
	var st := [0, 0]
	var enc := VoiceCodec.encode_adpcm(tone, st)
	eq(enc.size(), 163, "3-byte header + 160 bytes")
	# a second frame continues from the carried state and decodes on its own
	var enc2 := VoiceCodec.encode_adpcm(tone, st)
	var dec := VoiceCodec.decode_adpcm(enc2, NetProto.VOICE_FRAME)
	eq(dec.size(), NetProto.VOICE_FRAME)
	var err := 0.0
	for i in dec.size():
		err += absf(dec[i] - tone[i])
	check(err / dec.size() < 0.03, "mean error %.4f" % (err / dec.size()))
	near(VoiceCodec.level(dec), 0.5 / sqrt(2.0), 0.03, "rms kept")
	near(_crossings(dec), _crossings(tone), 2, "same pitch")


func test_ulaw_roundtrip() -> void:
	var tone := _tone(NetProto.VOICE_FRAME, 300.0, 0.8)
	var dec := VoiceCodec.decode_ulaw(VoiceCodec.encode_ulaw(tone))
	var worst := 0.0
	for i in dec.size():
		worst = maxf(worst, absf(dec[i] - tone[i]))
	check(worst < 0.03, "μ-law error %.4f" % worst)
	var silent := VoiceCodec.decode_ulaw(VoiceCodec.encode_ulaw(PackedFloat32Array([0.0, 0.0])))
	check(absf(silent[0]) < 0.001, "zero stays zero")


func test_resampler_48k_to_16k() -> void:
	var rs := VoiceCodec.Resampler.new(48000.0, 16000.0)
	var total := PackedFloat32Array()
	for chunk in 10:
		var frames := PackedVector2Array()
		for i in 960:
			var v := 0.5 * sin(TAU * 440.0 * (chunk * 960 + i) / 48000.0)
			frames.append(Vector2(v, v))
		total.append_array(rs.push(frames))
	near(total.size(), 3200, 4, "a third of the samples")
	near(_crossings(total.slice(100, 3100)), 2 * 440 * 3000 / 16000.0, 3, "pitch kept")


func test_interpolation() -> void:
	var it := NetInterp.new()
	eq(it.sample(0.0), {}, "nothing before data")
	# sender clock starts near the u16 wrap; 10 Hz moving +1 m per snapshot along x
	for i in 10:
		it.push((65500 + i * 100) & 0xFFFF, Vector3(i, 0, 0), 0.1 * i, NetProto.F_ON_FLOOR, 0, 1000.0 + i * 100.0)
	var s := it.sample(1000.0 + 500.0 + NetInterp.DELAY_MS)
	near((s["pos"] as Vector3).x, 5.0, 0.01, "drawn DELAY_MS in the past")
	var mid := it.sample(1000.0 + 550.0 + NetInterp.DELAY_MS)
	near((mid["pos"] as Vector3).x, 5.5, 0.01, "halfway between snapshots")
	near(float(mid["yaw"]), 0.55, 0.001, "yaw interpolated")
	near((mid["vel"] as Vector3).x, 10.0, 0.01, "velocity 10 m/s")
	var ex := it.sample(1000.0 + 900.0 + 100.0 + NetInterp.DELAY_MS)
	near((ex["pos"] as Vector3).x, 10.0, 0.01, "extrapolates a little past the newest")
	var hold := it.sample(1000.0 + 900.0 + 2000.0)
	near((hold["pos"] as Vector3).x, 9.0 + NetInterp.MAX_EXTRAP_MS / 100.0, 0.01, "then holds")
	eq(hold["vel"], Vector3.ZERO, "and stands still")
	# an out-of-order (older) snapshot is ignored
	it.push((65500 + 300) & 0xFFFF, Vector3(-50, 0, 0), 0, 0, 0, 2000.0)
	near((it.sample(1000.0 + 900.0 + NetInterp.DELAY_MS)["pos"] as Vector3).x, 9.0, 0.01, "late packet dropped")


func test_interpolation_jitter_uses_sender_clock() -> void:
	var it := NetInterp.new()
	# sent every 100 ms; arrivals jitter by up to 60 ms
	var jitter := [0, 60, 10, 40, 0, 55, 20, 0, 35, 5]
	for i in 10:
		it.push(i * 100, Vector3(i, 0, 0), 0, 0, 0, 5000.0 + i * 100.0 + jitter[i])
	var s := it.sample(5000.0 + 450.0 + NetInterp.DELAY_MS)
	near((s["pos"] as Vector3).x, 4.5, 0.01, "positions follow the sender's timeline, not arrival jitter")


func test_teleport_resets() -> void:
	var it := NetInterp.new()
	it.push(0, Vector3.ZERO, 0, 0, 0, 0.0)
	it.push(100, Vector3(500, 0, 0), 0, 0, 0, 100.0)
	near((it.sample(100.0 + NetInterp.DELAY_MS + 30.0)["pos"] as Vector3).x, 500.0, 0.01, "no slide across the map")


func test_token_bucket() -> void:
	var b := TokenBucket.new(2.0, 3.0)
	var ok := 0
	for i in 10:
		if b.take(0.0):
			ok += 1
	eq(ok, 3, "burst")
	check(not b.take(0.4), "0.8 tokens after 0.4 s")
	check(b.take(0.5), "one after 0.5 s")
	check(b.take(10.0) and b.take(10.0) and b.take(10.0) and not b.take(10.0), "refills to the burst, no more")


func test_leaderboards_never_invent_rows() -> void:
	var lb := Leaderboards.new()
	eq(lb.top("0xabc/arcade:void_lanes", 10), [], "empty board is empty")
	var w1 := "0x" + "1".repeat(40)
	var w2 := "0x" + "2".repeat(40)
	var r = await lb.submit("0xQ/arcade:void_lanes", {"score": 120}, w1, "Alice")
	check(r["ok"], "accepted")
	eq(r["row"]["verified"], false, "no verifier: unverified")
	eq(String(r["row"]["check"]), Leaderboards.UNVERIFIED)
	await lb.submit("0xq/arcade:void_lanes", {"score": "300"}, w2, "Bob")
	await lb.submit("0xq/arcade:void_lanes", {"score": 50}, w1, "Alice")  # lower: Alice's best stands
	var top := lb.top("0xq/arcade:void_lanes", 10)
	eq(top.size(), 2, "one row per wallet")
	eq(int(top[0]["score"]), 300)
	eq(int(top[1]["score"]), 120)
	check(not (await lb.submit("0xq/x", {"score": -1}, w1, "A"))["ok"], "negative score refused")
	check(not (await lb.submit("0xq/x", {"score": 1.5}, w1, "A"))["ok"], "fraction refused")
	check(not (await lb.submit("0xq/x", {"score": 1}, "", "A"))["ok"], "a guest can't submit")
	check(not (await lb.submit("bad board!", {"score": 1}, w1, "A"))["ok"], "bad board id")


func test_leaderboard_verifier_plugs_in() -> void:
	var lb := Leaderboards.new()
	lb.add_verifier("*/fair:*", func(_b, e, _w): return {"ok": int(e["score"]) <= 100, "verified": true, "check": "replayed"})
	var w := "0x" + "3".repeat(40)
	check(not (await lb.submit("0xq/fair:striker", {"score": 101}, w, "C"))["ok"], "the verifier refuses")
	var r = await lb.submit("0xq/fair:striker", {"score": 99}, w, "C")
	check(r["ok"] and r["row"]["verified"], "verified row")
	eq(String(r["row"]["check"]), "replayed")


func test_leaderboards_save_and_load() -> void:
	var path := "user://test_net_lb.json"
	var lb := Leaderboards.new(path)
	lb.boards.clear()
	lb.insert("0xq/a", {"wallet": "0x" + "4".repeat(40), "name": "D", "score": 7, "verified": false, "check": "", "at": 1})
	lb.save()
	var again := Leaderboards.new(path)
	eq(again.top("0xq/a", 5).size(), 1)
	eq(again.top("0xq/a", 5)[0]["score"], 7, "score back as an int")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
