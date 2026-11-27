extends SceneTree
## A scripted remote player for tests and screenshots (docs/SERVER.md): signs in
## with a throwaway test key, joins a QING room, walks up to the first other
## player it sees (stopping a few metres in front of them, facing them), and
## says a line in free chat. Never touches the chain's write side.
##   godot --headless --path . -s res://tools/net_bot.gd -- --url=ws://127.0.0.1:8787
##       [--qing=0x…] [--name=Bob] [--head=fox] [--say="…"] [--seconds=60] [--key=0x…]
## Games (invites, docs/SERVER.md §8b):
##       [--invite=0x<wallet> --game=pool|cards --stake=2 --invite-delay=S]  invite that wallet once it is online
##       [--accept]   accept the first invite it gets
##       [--play]     play its turns: confirm the stake, sit, pool shots at the nearest ball, Twenty-One
##                    hits below --hit-below=15 then stands (cards read their blocks from the chain)
##       [--concede-after=N]  concede after N of its own game moves (0 = never)
## It replays each game with NetMatch, like the game, and reports its result to the server.
## Names and the activity feed (NetEvents):
##       [--guest]          stay a guest (no sign-in): others must see "guest"
##       [--place=arcade]   say it walked into that place of its QING (players there see it)
##       [--claim=rocket]   send a claim (receivers check it on the chain; a test key's claim fails that check)
##       [--join-me=0x…]    ask that wallet to join it (at --join-door=""|room|arcade)
##       [--accept-join]    accept a join request (reports it; a bot does not travel)
##       [--start-delay=S]  wait S seconds before connecting (a later "came online")
##       [--after-peer]     place / claim / join-me only once it sees another player in the room
## Load and voice checks (docs/AUDIT_NET_2026-11-26.md):
##       [--wander=R]       walk a circle of radius R m (3 m/s) around --at=x,y,z (or the first player it
##                          sees) instead of walking up to them; sends its pose at 10 Hz whoever is there
##       [--talk=tone:440 | --talk=wav:/abs/file.wav]  push-to-talk the whole time (real-time 20 ms frames,
##                          the game's encoder: VoiceCodec.encode_adpcm); a WAV loops (16-bit PCM, any rate)
##       [--talk-after=S]   start talking S seconds after joining
##       [--record=/abs/out.wav]  write every voice frame it receives, decoded, to a 16 kHz WAV, and a
##                          .csv beside it (arrival unix ms, sender id, seq) for latency / loss / jitter
##       [--stats]          print its byte counters every 10 s and at the end
## The daily challenge (NetDaily, docs/SERVER.md §8d):
##       [--daily=N]        play N scored tries of today's game on the day's real seed (the first block
##                          ≥ 00:00 UTC, read from the chain), each with a scripted input pattern (varied by
##                          the key), waiting out the run's length, then send the input log for the server to
##                          replay; prints each result and the board. Needs a server that lists "daily".
## It prints every event it gets ("[bot] event: …", in the feed's words) and every peer's
## name tag as this game would draw it ("[bot] tag: …"): the chain's LAU name for the
## verified wallet (read-only), the short wallet, or "guest".

const DEFAULT_QING := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const DEFAULT_KEY := "0x2f6c8e1a3b5d7f9e0c2a4b6d8f1e3c5a7b9d0e2f4a6c8b1d3e5f7a9c0b2d4e6f"

var c: Node
var nms := {}  # match id → NetMatch
var replaying := {}
var reported := {}
var my_moves := 0
var play := false
var hit_below := 15
var concede_after := 0
var acting := {}
var stake_sent := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	var url := "ws://127.0.0.1:8787"
	var qing := DEFAULT_QING
	var nm := "Bob"
	var head := "fox"
	var line := "Hello from the laptop server! Free chat, not on chain."
	var secs := 60.0
	var key := DEFAULT_KEY
	var invite_to := ""
	var game := "pool"
	var stake := ""
	var invite_delay := 0.0
	var accept := false
	var guest := false
	var place := ""
	var claim := ""
	var join_me := ""
	var join_door := "arcade"
	var accept_join := false
	var start_delay := 0.0
	var after_peer := false
	var wander := 0.0
	var at := Vector3.INF
	var talk := ""
	var talk_after := 0.0
	var record := ""
	var stats := false
	var daily := 0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"url": url = v
			"qing": qing = v
			"name": nm = v
			"head": head = v
			"say": line = v
			"seconds": secs = float(v)
			"key": key = v
			"invite": invite_to = v.to_lower()
			"game": game = v
			"stake": stake = v
			"invite-delay": invite_delay = float(v)
			"accept": accept = true
			"play": play = true
			"hit-below": hit_below = int(v)
			"concede-after": concede_after = int(v)
			"guest": guest = true
			"place": place = v
			"claim": claim = v
			"join-me": join_me = v.to_lower()
			"join-door": join_door = v
			"accept-join": accept_join = true
			"start-delay": start_delay = float(v)
			"after-peer": after_peer = true
			"wander": wander = float(v)
			"at":
				var xyz := v.split(",")
				if xyz.size() == 3:
					at = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
			"talk": talk = v
			"talk-after": talk_after = float(v)
			"record": record = v
			"stats": stats = true
			"daily": daily = clampi(int(v), 1, 3)
	c = load("res://scripts/net/net_client.gd").new()
	root.add_child(c)
	c.signer_wallet = EthSign.address_of_private(key)
	c.signer = func(m: String) -> String: return EthSign.sign_personal(m, key)
	if start_delay > 0.0:
		await create_timer(start_delay).timeout
	var t0 := Time.get_ticks_msec()
	c.connect_to(url)
	while not c.is_online() and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	if not c.is_online():
		print("[bot] no server at ", url)
		quit(1)
		return
	c.event.connect(_on_event)
	c.peer_joined.connect(_on_peer)
	if record != "":
		c.voice.connect(_on_voice)
	if guest:
		print("[bot] staying a guest (no signature)")
	else:
		c.sign_in()
		while c.wallet == "" and Time.get_ticks_msec() - t0 < 15000:
			await process_frame
		print("[bot] signed in as ", c.wallet)
	c.join(qing, {"name": nm if not guest else "", "head": head, "acc": [], "body": "male"})
	if daily > 0:
		await _daily(daily, key)
	if after_peer:
		while c.peers.is_empty() and Time.get_ticks_msec() - t0 < secs * 1000.0:
			await process_frame
		print("[bot] a player is here: acting")
	if place != "" or claim != "":
		await create_timer(1.5).timeout
		if place != "":
			print("[bot] place %s: %s" % [place, "sent" if c.send_place(place, qing) else "not sent (guest, or a server without events)"])
		if claim != "":
			print("[bot] claim %s: %s" % [claim, "sent" if c.send_claim(claim, qing) else "not sent"])
	var online := [false]
	c.online_list.connect(func(ok, rows, _e):
		if ok and rows.any(func(r): return r["wallet"] == invite_to):
			online[0] = true)
	c.invite_update.connect(func(inv):
		print("[bot] invite %s %s: %s → %s %s stake '%s'" % [inv["id"], inv["state"], inv["from"], inv["to"], inv["game"], inv["stake"]])
		var is_join: bool = inv["game"] == InviteBook.JOIN
		if inv["state"] == "pending" and inv["to"] == c.wallet and ((accept and not is_join) or (accept_join and is_join)):
			c.answer_invite(inv["id"], "accept"))
	c.match_update.connect(_on_match)
	c.match_move.connect(func(mid, mv):
		var n: NetMatch = nms.get(mid)
		if n and int(mv["seq"]) == (n.rec["log"] as Array).size() + 1:
			n.rec["log"].append(mv)
			_replay(mid))
	c.refused.connect(func(what, err): print("[bot] refused %s: %s" % [what, err]))
	var invited := invite_to == ""
	if join_me != "":
		await create_timer(1.0).timeout
		print("[bot] asking %s to join it (door '%s')" % [join_me, join_door])
		c.invite(join_me, InviteBook.JOIN, "", qing, join_door)
	var asked_at := -100000
	var said := false
	var said_at := -100000
	var pos := Vector3.ZERO
	var yaw := 0.0
	var talk_pcm := _talk_source(talk)
	var talk_t0 := -1.0
	var talk_sent := 0
	var talk_pos := 0
	var adpcm := [0, 0]
	var joined_ms := Time.get_ticks_msec()
	var stats_at := Time.get_ticks_msec()
	var phase := randf() * TAU
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if stats and Time.get_ticks_msec() - stats_at > 10000:
			stats_at = Time.get_ticks_msec()
			_print_stats(t0)
		if wander > 0.0:
			if at == Vector3.INF:
				for id in c.peers:
					var s0: Dictionary = c.peer_pose(id, Time.get_ticks_msec())
					if not s0.is_empty():
						at = s0["pos"]
						break
			var ctr := at if at != Vector3.INF else Vector3.ZERO
			var ang := phase + Time.get_ticks_msec() / 1000.0 * 3.0 / wander
			pos = ctr + Vector3(cos(ang), 0.0, sin(ang)) * wander
			yaw = -ang
			c.send_state(pos, yaw, NetProto.F_ON_FLOOR | (NetProto.F_SPEAKING if talk_t0 >= 0.0 else 0), 0)
		if not talk_pcm.is_empty() and Time.get_ticks_msec() - joined_ms >= talk_after * 1000.0:
			if talk_t0 < 0.0:
				talk_t0 = Time.get_ticks_msec()
				if wander <= 0.0:
					c.send_state(pos, yaw, NetProto.F_ON_FLOOR | NetProto.F_SPEAKING, 0, true)  # voice needs a position
				print("[bot] talking (%s), %d samples a loop" % [talk, talk_pcm.size()])
			# real time: as many 20 ms frames as the clock says, like the mic would give
			var due := int((Time.get_ticks_msec() - talk_t0) / 20.0)
			while talk_sent < due:
				var frame := PackedFloat32Array()
				frame.resize(NetProto.VOICE_FRAME)
				for i in NetProto.VOICE_FRAME:
					frame[i] = talk_pcm[talk_pos]
					talk_pos = (talk_pos + 1) % talk_pcm.size()
				c.send_voice(talk_sent & 0xFFFF, NetProto.CODEC_ADPCM, VoiceCodec.encode_adpcm(frame, adpcm))
				_talk_log.append([int(Time.get_unix_time_from_system() * 1000.0), talk_sent])
				talk_sent += 1
		if not invited and Time.get_ticks_msec() - t0 > invite_delay * 1000.0:
			if online[0]:
				invited = true
				c.invite(invite_to, game, stake, qing)
				print("[bot] invited %s to %s%s" % [invite_to, game, (" stake " + stake) if stake != "" else ""])
			elif Time.get_ticks_msec() - asked_at > 2000:
				asked_at = Time.get_ticks_msec()
				c.request_online()
		var target := {}
		for id in (c.peers if wander <= 0.0 else {}):
			var s: Dictionary = c.peer_pose(id, Time.get_ticks_msec())
			if not s.is_empty():
				target = s
				break
		if not target.is_empty():
			var ty: float = target["yaw"]
			var fwd := Vector3(sin(ty), 0.0, cos(ty))
			var right := Vector3(fwd.z, 0.0, -fwd.x)
			pos = target["pos"] + fwd * 4.5 + right * 1.2
			yaw = ty + PI
			c.send_state(pos, yaw, NetProto.F_ON_FLOOR | (NetProto.F_SPEAKING if said else 0), 0)
			if line != "" and Time.get_ticks_msec() - said_at > 12000 and c.send_chat(line):  # again every 12 s
				said_at = Time.get_ticks_msec()
				if not said:
					print("[bot] standing at %s, said: %s" % [pos, line])
				said = true
		await process_frame
	if stats:
		_print_stats(t0)
	if talk_t0 >= 0.0:
		print("[bot] talked %d frames (%.1f s)" % [talk_sent, talk_sent * 0.02])
		_write_csv(record.get_basename() + ".sent.csv" if record != "" else "", _talk_log)
	if record != "":
		_write_record(record)
	c.close()
	quit(0)


# --- load and voice checks --------------------------------------------------------

var _talk_log: Array = []      # [unix ms, seq] per frame sent
var _rec_pcm := PackedFloat32Array()
var _rec_log: Array = []       # [unix ms, sender id, seq] per frame received


## Mono floats at 16 kHz: "tone:440" (0.5 amplitude, 2 s) or "wav:/abs/path.wav" (16-bit PCM).
## Plays `n` scored tries of today's challenge (real seed, scripted inputs) and submits them.
func _daily(n: int, key: String) -> void:
	var dc = load("res://scripts/games/daily/daily_challenge.gd")
	var ds = load("res://scripts/games/daily/daily_seed.gd")
	ds.use_file = false
	var day: String = dc.day_of(int(Time.get_unix_time_from_system()))
	var sd: Dictionary = await ds.find(day)
	if sd.get("state", "") != "ok":
		print("[bot] daily: the seed block could not be read: — (%s)" % sd.get("error", ""))
		return
	var gid: String = dc.game_for(day)
	print("[bot] daily %s: %s, seed block %d" % [day, gid, int(sd["block"])])
	var salt := key.hash()
	for k in n:
		var st: Dictionary = await c.daily_start(day)
		if not st.get("ok", false):
			print("[bot] daily: no try: ", st.get("error", "—"))
			return
		var g = load(dc.script_of(gid)).new()
		g.recording = true
		g.scripted_input = 0
		g.start(int(sd["seed"]))
		var period := 40 + absi(salt + k * 7) % 50
		for i in 600:  # at most 10 s of play
			if not g.playing:
				break
			g.scripted_input = (16 if i % period < period / 3 else 0) | (1 if (i / (period + 20)) % 2 == 0 else 2)
			g.step(1.0 / 60.0)
		if g.playing:
			g.end_game()
		var steps: int = g.rec_steps.size()
		var log_text: String = dc.encode_log(g.rec_start, g.rec_steps)
		var score: int = g.score
		g.free()
		await create_timer(steps / 60.0 + 0.5).timeout  # a run can't arrive before it could have been played
		var r: Dictionary = await c.daily_submit(day, int(st["attempt"]), score, log_text)
		print("[bot] daily try %d: %d → %s" % [int(st["attempt"]), score, ("rank %d · %s" % [int(r.get("rank", 0)), r.get("check", "")]) if r.get("ok", false) else "refused: %s" % r.get("error", "")])
	var b: Dictionary = await c.daily_board(day)
	for row in b.get("rows", []):
		print("[bot] board: %s %d %s" % [row["wallet"], int(row["score"]), "✓" if row["verified"] else ""])


func _talk_source(spec: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if spec.begins_with("tone:"):
		var hz := float(spec.substr(5))
		out.resize(NetProto.VOICE_RATE * 2)
		for i in out.size():
			out[i] = 0.5 * sin(TAU * hz * i / NetProto.VOICE_RATE)
	elif spec.begins_with("wav:"):
		out = read_wav_16k(spec.substr(4))
		if out.is_empty():
			print("[bot] can't read ", spec.substr(4))
	return out


## A 16-bit PCM WAV (any rate, mono or stereo) as mono floats at 16 kHz.
static func read_wav_16k(path: String) -> PackedFloat32Array:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return PackedFloat32Array()
	var ch := 1
	var rate := 16000
	var off := 12
	while off + 8 <= b.size():
		var id := b.slice(off, off + 4).get_string_from_ascii()
		var n := b.decode_u32(off + 4)
		if id == "fmt ":
			ch = b.decode_u16(off + 10)
			rate = b.decode_u32(off + 12)
		elif id == "data":
			var frames := PackedVector2Array()
			var count := n / (2 * ch)
			frames.resize(count)
			for i in count:
				var l := b.decode_s16(off + 8 + i * 2 * ch) / 32768.0
				var r := b.decode_s16(off + 8 + i * 2 * ch + 2 * (ch - 1)) / 32768.0
				frames[i] = Vector2(l, r)
			return VoiceCodec.Resampler.new(rate, NetProto.VOICE_RATE).push(frames)
		off += 8 + n + (n & 1)
	return PackedFloat32Array()


func _on_voice(id: int, codec: int, data: PackedByteArray) -> void:
	_rec_pcm.append_array(VoiceCodec.decode(codec, data))
	_rec_log.append([int(Time.get_unix_time_from_system() * 1000.0), id, c.last_voice_seq])


func _write_record(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[bot] can't write ", path)
		return
	var n := _rec_pcm.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(NetProto.VOICE_RATE)
	f.store_32(NetProto.VOICE_RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	for v in _rec_pcm:
		f.store_16(clampi(int(round(v * 32767.0)), -32768, 32767) & 0xFFFF)
	f.close()
	_write_csv(path.get_basename() + ".csv", _rec_log)
	print("[bot] recorded %d voice frames (%.1f s) → %s" % [_rec_log.size(), n / float(NetProto.VOICE_RATE), path])


static func _write_csv(path: String, rows: Array) -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		for r in rows:
			f.store_line(",".join(r.map(func(x): return str(x))))


func _print_stats(t0: int) -> void:
	var s := maxf(0.001, (Time.get_ticks_msec() - t0) / 1000.0)
	print("[bot] stats %.0f s: in %.0f B/s (states %.0f, voice %.0f), out %.0f B/s, %d peers, rtt %d ms" % [s,
		c.counters["bytes_in"] / s, c.counters["state_bytes_in"] / s, c.counters["voice_bytes_in"] / s,
		c.counters["bytes_out"] / s, c.peers.size(), c.rtt_ms])


func _on_match(rec: Dictionary) -> void:
	var id := String(rec["id"])
	var n: NetMatch = nms.get(id)
	if n == null:
		n = NetMatch.new(rec.duplicate(true))
		nms[id] = n
		print("[bot] match %s: %s %s vs %s, stake '%s'" % [id, rec["game"], rec["players"][0], rec["players"][1], rec["stake"]])
		if play:
			c.send_move(id, "sit")
	else:
		var mine: Array = n.rec["log"]
		var theirs: Array = rec.get("log", [])
		for i in range(mine.size(), theirs.size()):
			mine.append(theirs[i])
		if rec.get("status") != "live":
			print("[bot] match %s: %s %s" % [id, rec["status"], JSON.stringify(rec.get("result", {}))])
	_replay(id)


func _replay(id: String) -> void:
	if replaying.get(id, false):
		return
	replaying[id] = true
	var n: NetMatch = nms[id]
	var bc = load("res://scripts/net/block_clock.gd")
	while true:
		if n.needs_block() >= 0:
			var b: Dictionary = await bc.first_at(n.needs_block())
			if not b.get("ok", false):
				print("[bot] %s: the deal's block can't be read: —" % id)
				break
			n.deal(b)
			print("[bot] %s dealt from block %d" % [id, b["number"]])
			continue
		var lg: Array = n.rec["log"]
		if n.applied >= lg.size():
			break
		var e: Dictionary = lg[n.applied]
		var blk := {}
		var anchor := n.hash_anchor(e)
		if anchor >= 0:
			blk = await bc.first_at(anchor)
		var r := n.apply(e, blk)
		if r["ok"] and e["op"] in ["shot", "hit", "stand", "concede"]:
			print("[bot] %s · %s" % [id, String(n.m["events"][-1]) if not n.m["events"].is_empty() else e["op"]])
	replaying[id] = false
	if n.over() and not reported.has(id):
		reported[id] = true
		c.send_result(id, n.winner_index(), n.digest())
		print("[bot] %s over: winner %d, digest %s" % [id, n.winner_index(), n.digest().left(12)])
	elif play:
		_act(id)


## Plays the bot's side: stake, then its turns (a short think first, so a viewer sees it).
func _act(id: String) -> void:
	var n: NetMatch = nms[id]
	var me := n.index_of(c.wallet)
	if me < 0 or acting.get(id, false) or n.over():
		return
	acting[id] = true
	await create_timer(1.2).timeout
	acting[id] = false
	if n.over() or n.applied < (n.rec["log"] as Array).size():
		return  # more moves arrived meanwhile: the replay calls again
	var m := n.m
	if m["status"] == "confirm":
		if not m["stake_ok"][me] and not stake_sent.has(id):
			stake_sent[id] = true  # once: the replay marks it when the server's log has it
			c.send_move(id, "stake_ok")
		return
	if not m["seated"][1 - me]:
		return  # waits for the other player to sit down at the table (their "sit" move)
	if NetMatch.turn_of(m) != me or n.needs_block() >= 0:
		return
	if concede_after > 0 and my_moves >= concede_after:
		c.send_move(id, "concede")
		print("[bot] %s: conceding" % id)
		return
	my_moves += 1
	if m["kind"] == "pool":
		var sim: PoolSim = (m["game"] as EightBall).sim
		var snap := sim.snapshot()
		var cx: int = snap[0]
		var cy: int = snap[1]
		var best := -1
		var best_d := 1 << 62
		for b in range(1, 16):
			if snap[b * 3 + 2] != 0:
				continue
			var d: int = (snap[b * 3] - cx) * (snap[b * 3] - cx) + (snap[b * 3 + 1] - cy) * (snap[b * 3 + 1] - cy)
			if d < best_d:
				best_d = d
				best = b
		var dx := 10000
		var dy := 0
		if best > 0:
			var vx := float(snap[best * 3] - cx)
			var vy := float(snap[best * 3 + 1] - cy)
			var l := sqrt(vx * vx + vy * vy)
			dx = int(round(vx / l * 10000.0))
			dy = int(round(vy / l * 10000.0))
		var power := 1000 if (m["game"] as EightBall).shots == 0 else 650
		c.send_move(id, "shot", [dx, dy, power])
		print("[bot] %s: shot at the %d ball (%d, %d, %d)" % [id, best, dx, dy, power])
	else:
		var d: Duel21 = m["game"]
		var op := "hit" if Duel21.total(d.hands[me]) < hit_below else "stand"
		c.send_move(id, op)
		print("[bot] %s: %s on %d" % [id, op, Duel21.total(d.hands[me])])



func _names() -> Node:
	var net := root.get_node_or_null("Net")
	return net.names if net else null


func _on_event(ev: Dictionary) -> void:
	var n := _names()
	var ctx := {"me": c.wallet}
	if n:
		ctx["name"] = func(w, _claimed): return n.display(w)
	print("[bot] event: %s   %s" % [NetEvents.format(ev, ctx), JSON.stringify(ev)])


var _tagged := {}


## The tag this game draws over that peer: the chain's name for its verified wallet.
func _on_peer(id: int, info: Dictionary) -> void:
	var w := String(info.get("wallet", ""))
	var guest: bool = info.get("guest", true) or w == ""
	var n := _names()
	if guest or n == null:
		print("[bot] tag: peer %d '%s' (claimed name '%s')" % [id, NetNames.tag(w, guest, {}), info.get("name", "")])
		return
	n.record(w)
	var t0 := Time.get_ticks_msec()
	while String(n.record(w).get("state", "reading")) == "reading" and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	var rec: Dictionary = n.record(w)
	print("[bot] tag: peer %d '%s' (chain read: %s, block %s; claimed name '%s')" % [id, NetNames.tag(w, false, rec), rec.get("state", "—"),
		rec.get("block", "—"), info.get("name", "")])
