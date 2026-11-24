extends Node
## Autoload "ChatFeed": QING chat from anywhere in the territory.
##
## - Keeps the current territory's room live (a RoomFeed, shared with the hall,
##   the arcade/pub tables and Phenomena through feed_for), across scene
##   changes: the feed keeps running in the arcade, the pub and the fair.
## - Owns the HUD overlay (ChatHud: the chat bar, T; the feed; the history, Y).
## - Posts room lines through the write pipeline: identity and door checks,
##   simulate (eth_call from the wallet) → sign → receipt verified from the
##   chain → the line read back from that block's logs → YUE.Bar(QING) re-read
##   at block − 1 and block. Lines typed while one is signing queue, and go
##   together as one transaction (ChatOutbox).
## - Free mode: when an autoload "Net" exists (the presence server), "say"
##   sends through Net.send_chat (free, not on chain) and Net.chat_received
##   lines join the feed tagged "say". Net is only looked up at runtime.
## - World hooks: `bubble(line)` for every new line, `bubble_for(wallet)` the
##   node a speaker's bubble floats over (register_speaker), or null.

signal outbox_changed
signal current_changed(feed: RoomFeed)
signal bubble(line: Dictionary)
signal posted(lines: Array, res: Dictionary)
signal mode_changed(mode: String)
signal note_changed

const HISTORY := 60
const FEED_SCENES := [Travel.TERRITORY_SCENE, Travel.ARCADE_SCENE, Travel.PUB_SCENE]

var feeds := {}  # qing → RoomFeed
var current: RoomFeed
var outbox := ChatOutbox.new()
var draft := ChatDraft.new()
var mode := "post"  # post | say (say only when Net exists)
var omega: Fact = Fact.loading("⌊Fornax(QING) / QING.Entropy()⌋")
var gas_note := ""  # eth_estimateGas for one line, from the session's wallet
var last_room: RoomState
var hud: CanvasLayer
var _speakers := {}  # wallet → WeakRef(Node3D)
var _scene: Node
var _pumping := false
var _batch: Array = []
var _label := ""
var _net_bound := false
var _gas_for := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	outbox.changed.connect(func(): outbox_changed.emit())
	Wallet.tx_stage.connect(_on_stage)
	(func() -> void:
		hud = load("res://scripts/ui/chat_hud.gd").new()
		hud.name = "ChatHud"
		add_child(hud)).call_deferred()
	var t := Timer.new()
	t.wait_time = 0.25
	t.timeout.connect(_watch_scene)
	add_child(t)
	t.start()


# --- Feeds -----------------------------------------------------------------------

## The shared live feed of a room (created on first use), with at least
## `history` lines of history loading.
func feed_for(qing: String, territory: Dictionary = {}, history: int = HISTORY) -> RoomFeed:
	qing = qing.to_lower()
	var f: RoomFeed = feeds.get(qing)
	if f == null or not is_instance_valid(f):
		f = RoomFeed.new()
		var t := territory if not territory.is_empty() else Registry.get_territory(qing)
		if t.is_empty():
			t = {"address": qing}
		f.setup("room", t)
		add_child(f)
		feeds[qing] = f
		f.arrived.connect(_on_arrived.bind(f))
	f.ensure_history(history)
	return f


## Makes `qing` the current room (the HUD shows it); other rooms' feeds stop.
func follow(qing: String) -> void:
	qing = qing.to_lower()
	if qing == "" or Registry.get_territory(qing).is_empty():
		return
	if current and is_instance_valid(current) and current.qing == qing:
		return
	current = feed_for(qing)
	for k in feeds.keys():
		if k != qing:
			(feeds[k] as Node).queue_free()
			feeds.erase(k)
	current_changed.emit(current)
	measure_gas()


func _watch_scene() -> void:
	var s := get_tree().current_scene
	if s == _scene:
		return
	_scene = s
	_bind_net()
	if s == null:
		return
	if s.scene_file_path in FEED_SCENES and GameManager.territory_address != "":
		follow(GameManager.territory_address)
	if hud and hud.has_method("on_scene"):
		hud.on_scene(s)


## Whether the HUD feed belongs on screen in this scene right now.
func feed_visible() -> bool:
	var s := get_tree().current_scene
	if s == null or not (s.scene_file_path in FEED_SCENES):
		return false
	var vm = s.get("view_mode")
	if vm is String and vm != "" and vm != "hud" and vm != "chat":
		return false
	if s.has_method("_any_open") and s.call("_any_open"):
		return false  # a cabinet dive, a table seat or a panel has the screen
	return true


## The chat bar works where the scene does not take T itself (places open
## their own panel with T).
func bar_allowed() -> bool:
	var s := get_tree().current_scene
	return s != null and s.scene_file_path == Travel.TERRITORY_SCENE and feed_visible()


func stats() -> Dictionary:
	if current == null or not is_instance_valid(current):
		return {"count": 0, "floor": false, "from_block": -1, "speakers": []}
	return ChatLines.day_stats(current.lines, current.head_seen, current.capped)


func _on_arrived(fresh: Array, f: RoomFeed) -> void:
	if f != current:
		return
	# Resolve the speakers' wallets (tx.from) first, so bubble_for can find them.
	await f.resolve_wallets(fresh)
	for l in fresh:
		bubble.emit(l)


# --- Free mode (Net) ---------------------------------------------------------------

func net() -> Node:
	return get_node_or_null("/root/Net")


func can_say() -> bool:
	var n := net()
	return n != null and n.has_method("send_chat")


func _bind_net() -> void:
	var n := net()
	if n == null or _net_bound:
		return
	if n.has_signal("chat_received"):
		n.connect("chat_received", _on_net_chat)
		_net_bound = true


func _on_net_chat(wallet, uname, text, world_pos = null) -> void:
	var w := String(wallet).to_lower()
	if w != "" and w == Session.wallet and _said_recently(String(text)):
		return  # our own line coming back: already shown
	var l := ChatLines.say_line(w, String(uname), String(text), Time.get_ticks_msec())
	if world_pos is Vector3:
		l["world_pos"] = world_pos
	if current and is_instance_valid(current):
		current.add_say(l)


var _my_says: Array = []  # [{text, ms}]


func _said_recently(text: String) -> bool:
	var now := Time.get_ticks_msec()
	for s in _my_says:
		if s["text"] == text and now - int(s["ms"]) < 10000:
			return true
	return false


func set_mode(m: String) -> void:
	mode = "say" if m == "say" and can_say() else "post"
	mode_changed.emit(mode)


func toggle_mode() -> void:
	set_mode("post" if mode == "say" else "say")


## What posting does here, for the bar.
func post_note() -> String:
	var om := "Ω —"
	if omega.has_value():
		var o := BigInt.coerce(omega.value)
		om = "Ω = 0 here: no Hypobar" if BigInt.is_zero(o) else "+Ω %s Hypobar to your bar here" % TokenFormat.group(BigInt.to_decimal(o))
	return "POST · on chain · %s · 1 wallet approval%s" % [om, (" · " + gas_note) if gas_note != "" else ""]


func say_note() -> String:
	return "SAY · free · not on chain (presence server) · adds nothing to the territory"


# --- Sending ---------------------------------------------------------------------------

## Sends a line in the current mode. Returns "" or why nothing was sent (the
## text stays in the bar then).
func submit(text: String) -> String:
	var why := ChatDraft.reject_reason(text)
	if why == "empty":
		return "Nothing to send."
	if why != "":
		return why.capitalize() + "."
	text = text.strip_edges()
	if mode == "say" and can_say():
		draft.remember(text)
		net().call("send_chat", text)
		_my_says.append({"text": text, "ms": Time.get_ticks_msec()})
		if _my_says.size() > 8:
			_my_says.pop_front()
		var nm := Session.player.username if Session.player != null else ""
		if current:
			current.add_say(ChatLines.say_line(Session.wallet, nm if nm != "" else "you", text, Time.get_ticks_msec()))
		return ""
	if current == null:
		return "No room here: — (the territory is not known)."
	draft.remember(text)
	outbox.add(text, current.qing)
	_pump()
	return ""


func _pump() -> void:
	if _pumping:
		return
	_pumping = true
	while true:
		var batch := outbox.take_batch()
		if batch.is_empty():
			break
		_batch = batch
		await _send(batch)
		_batch = []
	_pumping = false


func _send(batch: Array) -> void:
	var qing: String = batch[0]["qing"]
	var t := Registry.get_territory(qing)
	var place := String(t.get("name", qing))
	var ib: String = ChatController._identity_blocker()
	if ib != "":
		outbox.fail(batch, ib, "identity")
		return
	var sb: String = ChatController._signer_blocker()
	if sb != "":
		outbox.fail(batch, sb, "signer")
		return
	outbox.set_stage(batch, "checking the door…")
	var room: RoomState = await RoomState.read(qing, Session.player)
	last_room = room
	if not room.ok:
		outbox.fail(batch, "the door could not be read: — (%s)" % room.error, "door")
		return
	var rb := room.chat_blocker()
	if rb != "":
		outbox.fail(batch, rb, "join" if room.lau != "" and not room.banned and not room.admitted else "identity")
		return
	var texts: Array = batch.map(func(e): return e["text"])
	var tx := ChatOutbox.encode_batch(qing, texts, place)
	if texts.size() > 1:
		# Each line simulated inside one aggregate3 eth_call (allowFailure true) so
		# a revert is decoded per line; the signed batch uses allowFailure false.
		outbox.set_stage(batch, "simulating %d lines from your wallet…" % texts.size())
		var calls: Array = texts.map(func(x): return Multicall.make_call(Contracts.CHOA, "Chat(address,string)", [qing, x]))
		var sims: Array = await Chain.multicall.run(calls, Wallet.address)
		for i in sims.size():
			if not sims[i]["ok"]:
				var rv: Dictionary = Abi.decode_revert(String(sims[i]["data"])) if String(sims[i].get("data", "")) != "" else {"name": "", "message": "simulation failed (—)"}
				outbox.fail(batch, "simulation says line %d would fail: %s" % [i + 1, rv["message"]], ChatOutbox.classify({"stage": "simulate", "revert": rv}))
				return
	_label = tx["label"]
	var res: Dictionary = await Wallet.send(tx["label"], tx["to"], tx["data"])
	_label = ""
	if not res["ok"]:
		outbox.fail(batch, String(res["message"]), ChatOutbox.classify(res))
		return
	var block: int = res["block"]
	outbox.set_stage(batch, "mined in block %d · reading the line back…" % block)
	var f := feed_for(qing)
	var mine: Array = await f.read_back(res["hash"], block)
	var delta := await _bar_delta(qing, block)
	if mine.size() < batch.size():
		outbox.confirm(batch, block, res["hash"], "mined in block %d, but %d of %d line%s not found in that block's logs: —" % [
			block, batch.size() - mine.size(), batch.size(), "" if batch.size() == 1 else "s"])
	else:
		outbox.confirm(batch, block, res["hash"], "on chain · block %d%s" % [block, delta])
	posted.emit(mine, res)
	Acts.set_flag(Session.wallet, "door")


## "· +N Hypobar here" measured from YUE.Bar(QING) at block − 1 and block.
func _bar_delta(qing: String, block: int) -> String:
	var ps: PlayerState = Session.player
	if ps == null or not ps.has_yue():
		return ""
	var a := await Chain.rpc.call_decoded(ps.yue, "Bar(address)", [qing], ["uint256", "uint256"], "", block - 1)
	var b := await Chain.rpc.call_decoded(ps.yue, "Bar(address)", [qing], ["uint256", "uint256"], "", block)
	if not a["ok"] or not b["ok"]:
		return " · Hypobar change: —"
	var d := BigInt.sub(BigInt.from_hex(b["values"][0]), BigInt.from_hex(a["values"][0]))
	return " · +%s Hypobar here (YUE.Bar at %d → %d)" % [TokenFormat.group(BigInt.to_decimal(d)), block - 1, block]


func _on_stage(label: String, stage: String, info: Dictionary) -> void:
	if label == "" or label != _label or _batch.is_empty():
		return
	var n := _batch.size()
	match stage:
		"simulate": outbox.set_stage(_batch, "simulating from your wallet…")
		"sign": outbox.set_stage(_batch, "waiting for your approval in the wallet (1 approval for %d line%s)…" % [n, "" if n == 1 else "s"])
		"pending": outbox.set_stage(_batch, "sent %s… · waiting for the receipt" % String(info.get("hash", "")).left(12))
		"confirmed": outbox.set_stage(_batch, "mined in block %d · reading the line back…" % int(info.get("block", -1)))


## Join the current room (cover rooms): the door's own steps (approve cover + 1
## wei, then Join), each through Wallet.send, then Admitted(LAU) re-read.
## Returns a status line.
func join() -> String:
	if current == null:
		return "No room here."
	var b: String = ChatController._identity_blocker()
	if b == "":
		b = ChatController._signer_blocker()
	if b != "":
		return b
	var room: RoomState = await RoomState.read(current.qing, Session.player)
	last_room = room
	if not room.ok:
		return "The door could not be read: —"
	if room.admitted:
		return "Already admitted here (QING.Admitted(LAU) at block %d)." % room.block
	if not room.can_afford():
		return "You hold %s; the cover is %s." % [room.fmt(room.balance), room.fmt(room.cover)]
	for step in room.join_steps():
		var res: Dictionary = await Wallet.send(step["label"], step["to"], step["data"])
		if not res["ok"]:
			return "%s: %s" % [step["label"], res["message"]]
	room = await RoomState.read(current.qing, Session.player)
	last_room = room
	if room.admitted:
		Acts.set_flag(Session.wallet, "door")
		return "Admitted (QING.Admitted(LAU) is true at block %d) for a day. Enter re-sends your line." % room.block
	return "Join was mined, but Admitted(LAU) still reads false at block %d." % room.block


## One line's gas from the session's wallet (eth_estimateGas, CHOA.Chat) and
## the node's gas price. Shown on the bar; "" until measured.
func measure_gas() -> void:
	if current == null or Session.wallet == "" or Session.player == null or not Session.player.has_lau():
		return
	var key := "%s@%s" % [Session.wallet, current.qing]
	if key == _gas_for:
		return
	_gas_for = key
	var data := Abi.encode_call("Chat(address,string)", [current.qing, "gm ☀️"])
	var g: Dictionary = await Chain.rpc.estimate_gas(Session.wallet, Contracts.CHOA, data)
	if not g["ok"]:
		var why: String = g["revert"]["message"] if g.get("kind") == "revert" else "—"
		gas_note = "gas: — (the estimate reverts: %s)" % why
		note_changed.emit()
		return
	var p: Dictionary = await Chain.rpc.gas_price()
	var gas: int = g["gas"]
	if p["ok"]:
		var fee := BigInt.mul(BigInt.from_int(gas), p["wei"])
		gas_note = "≈ %s gas ≈ %s PLS" % [TokenFormat.group(str(gas)), TokenFormat.wei_to_tokens(fee, 18, 1)]
	else:
		gas_note = "≈ %s gas" % TokenFormat.group(str(gas))
	note_changed.emit()


# --- Speakers in the world ---------------------------------------------------------------

## A node that stands for a present player (the local avatar; remote avatars
## from the presence server). Bubbles for their lines float over it.
func register_speaker(wallet: String, node: Node3D) -> void:
	if wallet == "" or node == null:
		return
	_speakers[wallet.to_lower()] = weakref(node)


func unregister_speaker(wallet: String) -> void:
	_speakers.erase(wallet.to_lower())


## The node to float `wallet`'s speech bubble over, or null (then the line
## rises as an echo from the QING's Core).
func bubble_for(wallet: String) -> Node3D:
	var r: WeakRef = _speakers.get(wallet.to_lower())
	if r == null:
		return null
	var n = r.get_ref()
	if n == null or not is_instance_valid(n) or not (n as Node).is_inside_tree():
		_speakers.erase(wallet.to_lower())
		return null
	return n
