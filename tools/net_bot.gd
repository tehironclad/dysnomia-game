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
	c = load("res://scripts/net/net_client.gd").new()
	root.add_child(c)
	c.signer_wallet = EthSign.address_of_private(key)
	c.signer = func(m: String) -> String: return EthSign.sign_personal(m, key)
	var t0 := Time.get_ticks_msec()
	c.connect_to(url)
	while not c.is_online() and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	if not c.is_online():
		print("[bot] no server at ", url)
		quit(1)
		return
	c.sign_in()
	while c.wallet == "" and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	print("[bot] signed in as ", c.wallet)
	c.join(qing, {"name": nm, "head": head, "acc": [], "body": "male"})
	var online := [false]
	c.online_list.connect(func(ok, rows, _e):
		if ok and rows.any(func(r): return r["wallet"] == invite_to):
			online[0] = true)
	c.invite_update.connect(func(inv):
		print("[bot] invite %s %s: %s → %s %s stake '%s'" % [inv["id"], inv["state"], inv["from"], inv["to"], inv["game"], inv["stake"]])
		if accept and inv["state"] == "pending" and inv["to"] == c.wallet:
			c.answer_invite(inv["id"], "accept"))
	c.match_update.connect(_on_match)
	c.match_move.connect(func(mid, mv):
		var n: NetMatch = nms.get(mid)
		if n and int(mv["seq"]) == (n.rec["log"] as Array).size() + 1:
			n.rec["log"].append(mv)
			_replay(mid))
	c.refused.connect(func(what, err): print("[bot] refused %s: %s" % [what, err]))
	var invited := invite_to == ""
	var asked_at := -100000
	var said := false
	var said_at := -100000
	var pos := Vector3.ZERO
	var yaw := 0.0
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if not invited and Time.get_ticks_msec() - t0 > invite_delay * 1000.0:
			if online[0]:
				invited = true
				c.invite(invite_to, game, stake, qing)
				print("[bot] invited %s to %s%s" % [invite_to, game, (" stake " + stake) if stake != "" else ""])
			elif Time.get_ticks_msec() - asked_at > 2000:
				asked_at = Time.get_ticks_msec()
				c.request_online()
		var target := {}
		for id in c.peers:
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
	c.close()
	quit(0)


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
