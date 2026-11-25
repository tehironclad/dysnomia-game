class_name BlockClock
extends RefCounted
## Which block deals a card in a game played over the game server (NetMatch):
## the first block whose timestamp is at or after a given unix second. Both
## players' machines find the same block, read from the chain (read-only).
## Nothing is guessed: {ok: false} when the chain can't be read, and the replay
## waits and asks again. Reaches the Chain autoload by path, so tools run with
## -s (net_bot) can use it too.

const BLOCK_S := 10        # PulseChain's block time: only for the first estimate
const WAIT_MAX_S := 120.0  # how long to wait for the block to be mined
const MAX_READS := 120

static var _found := {}    # unix s → {ok, hash, number, timestamp}
static var _blocks := {}   # number → {hash, number, timestamp}


static func _chain() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Chain") if tree else null


## One block ({hash, number, timestamp}) or {} when it can't be read.
static func read(n) -> Dictionary:
	if n is int and _blocks.has(n):
		return _blocks[n]
	var ch := _chain()
	if ch == null:
		return {}
	var rpc = ch.get("rpc")  # Chain.rpc (Node.rpc is a method: read the property by name)
	var r: Dictionary = await rpc.get_block(n)
	if not r.get("ok", false) or not (r.get("result") is Dictionary):
		return {}
	var res: Dictionary = r["result"]
	var b := {"hash": String(res.get("hash", "")), "number": String(res.get("number", "0x0")).hex_to_int(),
		"timestamp": String(res.get("timestamp", "0x0")).hex_to_int()}
	if not (String(b["hash"]).begins_with("0x") and String(b["hash"]).length() == 66):
		return {}
	_blocks[int(b["number"])] = b
	return b


## The first block with timestamp ≥ unix_s: {ok, hash, number, timestamp} or {ok: false, error}.
## Waits (polling every 2 s) until such a block exists.
static func first_at(unix_s: int) -> Dictionary:
	if _found.has(unix_s):
		return _found[unix_s]
	var tree := Engine.get_main_loop() as SceneTree
	var t0 := Time.get_ticks_msec()
	var head := {}
	while true:
		head = await read("latest")
		if not head.is_empty() and int(head["timestamp"]) >= unix_s:
			break
		if Time.get_ticks_msec() - t0 > WAIT_MAX_S * 1000.0:
			return {"ok": false, "error": "no block at or after %d yet (or the chain can't be read): —" % unix_s}
		await tree.create_timer(2.0).timeout
	var top := int(head["number"])
	var n := top - maxi(0, (int(head["timestamp"]) - unix_s) / BLOCK_S)
	var b: Dictionary = head
	if n != top:
		b = await read(n)
	var reads := 0
	# A couple of secant steps (block times drift), then walk to the exact first block.
	for _i in 3:
		if b.is_empty():
			break
		var step := (unix_s - int(b["timestamp"])) / BLOCK_S
		if absi(step) < 2:
			break
		n = clampi(n + step, 0, top)
		b = await read(n)
		reads += 1
	while not b.is_empty() and reads < MAX_READS:
		reads += 1
		if int(b["timestamp"]) < unix_s:
			if n >= top:
				return {"ok": false, "error": "the head moved back: —"}
			n += 1
			b = await read(n)
			continue
		var prev := {}
		if n > 0:
			prev = await read(n - 1)
		if prev.is_empty() and n > 0:
			b = {}
			break
		if not prev.is_empty() and int(prev["timestamp"]) >= unix_s:
			n -= 1
			b = prev
			continue
		break
	if b.is_empty() or reads >= MAX_READS:
		return {"ok": false, "error": "a block could not be read: —"}
	var out := {"ok": true, "hash": b["hash"], "number": b["number"], "timestamp": b["timestamp"]}
	_found[unix_s] = out
	return out
