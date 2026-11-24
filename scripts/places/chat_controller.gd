class_name ChatController
extends CanvasLayer
## Chat in a place you stand in (the QING hall, the Void): reads the board's
## history from the chain, tails new lines while you're there, and posts
## through Wallet.send (simulate → sign → receipt → read the line back from
## that block's logs). In a room it also shows the door (cover, Admitted) and
## runs Join (approve cover + 1 wei, Join, verify Admitted).
##
## Places listen to `lines_changed` to draw the board in 3D; the ChatPanel is
## the typing surface (T to open, Esc to close).

signal lines_changed(lines: Array, fresh: Array)
signal opened
signal closed
signal posted(line: Dictionary)

const TAIL_S := 8.0

var mode := "room"  # "room" | "void"
var qing := ""
var territory: Dictionary = {}
var lines: Array = []
var history_limit := 80  # room lines read at arrival (the game rooms read more: their tables replay them)
var chat: ChatPanel
var room: RoomState
var _door_btn: Button
var _busy := false
var _after := -1
var _polling := false


func setup(p_mode: String, q: Dictionary = {}) -> void:
	mode = p_mode
	territory = q
	qing = String(q.get("address", "")).to_lower()
	layer = 20
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	chat = ChatPanel.new()
	center.add_child(chat)
	_door_btn = Button.new()
	_door_btn.visible = false
	_door_btn.pressed.connect(_join)
	chat.get_child(0).add_child(_door_btn)
	chat.get_child(0).move_child(_door_btn, 2)
	chat.closed.connect(func():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		closed.emit())
	chat.post_requested.connect(_post)
	Wallet.tx_stage.connect(func(_l, stage, _i):
		if stage == "failed": Cues.play(self, "fail")
		elif stage == "confirmed": Cues.play(self, "confirm"))
	var t := Timer.new()
	t.wait_time = TAIL_S
	t.timeout.connect(_tail)
	add_child(t)
	t.start()
	_load_history()
	if mode == "room":
		_refresh_door()


func title() -> String:
	return "THE VOID" if mode == "void" else "THE ROOM · %s" % String(territory.get("name", qing))


func _load_history() -> void:
	var head := await Chain.refresh_head()
	if head < 0:
		return
	var h: Dictionary
	if mode == "room":
		h = await ChatLog.room_history(qing, int(territory.get("block", Contracts.MAP_FIRST_BLOCK)), head, history_limit)
	else:
		h = await ChatLog.void_history(head, 100)
	lines = h["lines"]
	_after = head
	chat.set_lines(lines, ("Lines from block %d to %d." % [h["scanned_from"], head]) if h["ok"] else "History incomplete: the log scan stopped (—).")
	lines_changed.emit(lines, [])


func _tail() -> void:
	if _polling or _after < 0:
		return
	_polling = true
	var head := await Chain.refresh_head()
	if head > _after:
		var r: Dictionary = await ChatLog.tail(qing if mode == "room" else Contracts.FOMALHAUTE, mode == "room", _after, head)
		if r["ok"]:
			_after = head
			var fresh := _merge(r["lines"])
			if not fresh.is_empty():
				chat.append_lines(fresh)
				Cues.play(self, "line")
				lines_changed.emit(lines, fresh)
	_polling = false


func _merge(more: Array) -> Array:
	var seen := {}
	for l in lines:
		seen["%s:%d" % [l["tx"], l["log_index"]]] = true
	var fresh: Array = []
	for l in more:
		var k := "%s:%d" % [l["tx"], l["log_index"]]
		if not seen.has(k):
			seen[k] = true
			lines.append(l)
			fresh.append(l)
	return fresh


func open() -> void:
	chat.show_panel(title(), "One board for everyone: Fomalhaute's LogEvent lines (from block %d), written by LAU.Chat. ✓ OG / ⚠ imposter compare the speaking LAU's Aura with the name's owner." % Contracts.VOID_CHAT_FROM_BLOCK if mode == "void" else (room.describe() if room else "Reading the door…"))
	chat.set_lines(lines, "")
	if mode == "void":
		var ib := _identity_blocker()
		chat.set_blocker(ib if ib != "" else _signer_blocker())
	else:
		_refresh_door()
	opened.emit()


func is_open() -> bool:
	return chat.is_open()


static func _signer_blocker() -> String:
	if Wallet.address == "":
		return "View only: connect this wallet at the front door to sign."
	if Wallet.address != Session.wallet:
		return "The connected wallet differs from the session's."
	if not Wallet.is_connected_to_chain():
		return "Switch the wallet to PulseChain (369)."
	return ""


static func _identity_blocker() -> String:
	if Session.wallet == "":
		return "Connect a wallet at the front door to speak."
	var ps: PlayerState = Session.player
	if ps == null:
		return "Reading your identity… try again in a moment."
	if ps.error != "":
		return "Couldn't read your identity from the chain: %s. Check the RPC in Settings, or try again." % ps.error
	if not ps.has_lau():
		return "No LAU yet: Enter the Void at the front door to create your identity."
	return ""


func _refresh_door() -> void:
	var ps: PlayerState = Session.player if Session.wallet != "" else null
	room = await RoomState.read(qing, ps)
	if not chat.is_open():
		return
	chat.set_subtitle(room.describe())
	if not room.ok:
		chat.set_blocker("The door could not be read: —")
		return
	var blocker := room.chat_blocker() if ps != null else "Connect a wallet at the front door to speak here."
	if blocker == "":
		blocker = _signer_blocker()
	chat.set_blocker(blocker)
	var steps := room.join_steps()
	_door_btn.visible = not steps.is_empty() and room.has_cover()
	if _door_btn.visible:
		var first: Dictionary = steps[0]
		_door_btn.text = "%s  (%d step%s)" % [first["label"], steps.size(), "s" if steps.size() > 1 else ""]
		_door_btn.disabled = _signer_blocker() != "" or not room.can_afford()
		if not room.can_afford():
			chat.set_status("You hold %s; the cover is %s." % [room.fmt(room.balance), room.fmt(room.cover)])


func _join() -> void:
	if _busy or room == null:
		return
	_busy = true
	_door_btn.disabled = true
	for step in room.join_steps():
		chat.track(step["label"])
		var res: Dictionary = await Wallet.send(step["label"], step["to"], step["data"])
		if not res["ok"]:
			_busy = false
			_refresh_door()
			return
	_busy = false
	await _refresh_door()
	if room.admitted:
		chat.set_status("Admitted (QING.Admitted(LAU) is true at block %d). The door is open to you for a day." % room.block)
		Acts.set_flag(Session.wallet, "door")
	else:
		chat.set_status("Join was mined, but Admitted(LAU) still reads false at block %d." % room.block)


func _post(text: String) -> void:
	if _busy:
		return
	_busy = true
	var to := ""
	var data := ""
	var emitter := ""
	var label := ""
	if mode == "room":
		to = Contracts.CHOA
		data = Abi.encode_call("Chat(address,string)", [qing, text])
		emitter = qing
		label = "Room line at %s" % String(territory.get("name", qing))
	else:
		to = Session.player.lau
		data = Abi.encode_call("Chat(string)", [text])
		emitter = Contracts.FOMALHAUTE
		label = "Void line"
	chat.track(label)
	var res: Dictionary = await Wallet.send(label, to, data)
	_busy = false
	if not res["ok"]:
		return
	chat.clear_input()
	var r: Dictionary = await ChatLog.tail(emitter, mode == "room", res["block"] - 1, res["block"])
	var mine: Array = r["lines"].filter(func(l): return l["tx"] == res["hash"])
	if mine.is_empty():
		chat.set_status("Mined in block %d, but the line was not found in that block's logs: —." % res["block"])
		return
	var fresh := _merge(mine)
	chat.append_lines(fresh)
	chat.set_status("Posted: read back from the chain in block %d." % res["block"])
	lines_changed.emit(lines, fresh)
	posted.emit(mine[0])
	if mode == "room":
		Acts.set_flag(Session.wallet, "door")
