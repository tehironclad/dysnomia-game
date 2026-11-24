extends SceneTree
## A scripted remote player for tests and screenshots (docs/SERVER.md): signs in
## with a throwaway test key, joins a QING room, walks up to the first other
## player it sees (stopping a few metres in front of them, facing them), and
## says a line in free chat. Never touches the chain.
##   godot --headless --path . -s res://tools/net_bot.gd -- --url=ws://127.0.0.1:8787
##       [--qing=0x…] [--name=Bob] [--head=fox] [--say="…"] [--seconds=60] [--key=0x…]

const DEFAULT_QING := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"
const DEFAULT_KEY := "0x2f6c8e1a3b5d7f9e0c2a4b6d8f1e3c5a7b9d0e2f4a6c8b1d3e5f7a9c0b2d4e6f"


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
	var c: Node = load("res://scripts/net/net_client.gd").new()
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
	var said := false
	var said_at := -100000
	var pos := Vector3.ZERO
	var yaw := 0.0
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
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
			if Time.get_ticks_msec() - said_at > 12000 and c.send_chat(line):  # again every 12 s
				said_at = Time.get_ticks_msec()
				if not said:
					print("[bot] standing at %s, said: %s" % [pos, line])
				said = true
		await process_frame
	c.close()
	quit(0)
