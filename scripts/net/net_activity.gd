class_name NetActivity
extends Node
## The activity feed's source (a child of the Net autoload: Net.activity): online
## players' actions, as lines with the player's face and colour. Two sources only:
## - the game server's events (NetEvents: sign-ins, QING arrivals, places, games and
##   their agreed results, leaderboard records) — what the server itself knows;
## - this machine's own chain reads (add_local): a 🎪 fair score line in this QING
##   checked against its ticket's receipt and replayed, a Hypobar rise measured
##   between two reads of the territory, a wager's Transfer log. A player's claim the
##   server relays ("I unlocked the rocket") is shown only once the chain agrees.
## Nothing is made up: no event, no line. Names come from the chain (LauNames).
## Lines go through NetEvents.Gate (no repeats within 30 s, a few a second at most);
## the last NetEvents.HISTORY stay for the notification panel (this session).

signal added(item: Dictionary)
signal updated(item: Dictionary)

var items: Array = []    # oldest first: {n, ev, text, at (unix s), ms, color, wallet, head}
var here := ""           # the QING this player is in ("" between places)
var gate := NetEvents.Gate.new()
var _n := 0
var _checking := {}      # claim key → true


func net() -> Node:
	return get_parent()


func _ready() -> void:
	var n := net()
	if n == null or n.get("client") == null:
		return
	n.client.event.connect(on_server_event)
	n.names.resolved.connect(_on_resolved)


func me() -> String:
	var n := net()
	var w: String = n.client.wallet if n and n.client and n.client.wallet != "" else ""
	if w == "":
		var s := get_node_or_null("/root/Session")
		w = String(s.wallet) if s else ""
	return w


## A server event (already cleaned by NetClient).
func on_server_event(ev: Dictionary) -> void:
	if ev.is_empty() or not NetEvents.relevant(ev, me(), here):
		return
	if String(ev["k"]) == "claim":
		_check_claim(ev)
		return
	_add(ev)


## A fact this machine read from the chain itself (LOCAL_KINDS), for this player only.
func add_local(ev: Dictionary) -> void:
	if not NetEvents.LOCAL_KINDS.has(String(ev.get("k", ""))):
		push_warning("[Net] not a chain fact kind: %s" % ev.get("k", ""))
		return
	if not ev.has("t"):
		ev["t"] = int(Time.get_unix_time_from_system())
	_add(ev)


func _add(ev: Dictionary) -> Dictionary:
	if not gate.admit(NetEvents.dedupe_key(ev), Time.get_ticks_msec() / 1000.0):
		return {}
	_n += 1
	var w := String(ev.get("w", ""))
	var item := {"n": _n, "ev": ev, "text": text_of(ev), "at": int(Time.get_unix_time_from_system()), "ms": Time.get_ticks_msec(),
		"color": NetEvents.color_of(String(ev["k"])), "wallet": w, "head": head_of(w)}
	if item["text"] == "":
		return {}
	items.append(item)
	if items.size() > NetEvents.HISTORY:
		items = items.slice(items.size() - NetEvents.HISTORY)
	added.emit(item)
	return item


func text_of(ev: Dictionary) -> String:
	var n := net()
	return NetEvents.format(ev, {"me": me(), "name": func(w, _claimed): return n.names.display(w),
		"place": place_name, "game": game_title})


## A player's face for the feed: their LAU's head (from the chain), or a guest's.
func head_of(w: String) -> String:
	if w == "":
		return "human"
	var rec: Dictionary = net().names.record(w)
	return String(rec.get("head", "bear")) if String(rec.get("state", "")) == "ok" else "bear"


func place_name(room: String) -> String:
	var reg := get_node_or_null("/root/Registry")
	var t: Dictionary = reg.get_territory(room) if reg else {}
	var nm := String(t.get("name", ""))
	return nm if nm != "" else NetProto.short_wallet(room)


static func game_title(g: String) -> String:
	if g in ["pool", "cards"]:
		return InviteBook.title_of(g)
	if MidwayGame.GAMES.has(g):
		return MidwayGame.title(g).capitalize()
	return g.replace("_", " ")


## A name was read: the lines naming that wallet say it now.
func _on_resolved(w: String) -> void:
	for i in range(items.size() - 1, maxi(-1, items.size() - 30), -1):
		var it: Dictionary = items[i]
		var ev: Dictionary = it["ev"]
		if String(ev.get("w", "")) == w or String(ev.get("w2", "")) == w:
			var t := text_of(ev)
			var h := head_of(String(it["wallet"]))
			if t != it["text"] or h != it["head"]:
				it["text"] = t
				it["head"] = h
				updated.emit(it)


# --- Claims: shown only once the chain agrees ------------------------------------

func _check_claim(ev: Dictionary) -> void:
	var key := "%s|%s|%s" % [ev["claim"], ev["w"], ev.get("room", "")]
	if _checking.has(key):
		return
	_checking[key] = true
	var ok := false
	if String(ev["claim"]) == "rocket":
		# The rocket's rule, from the chain: every fair game's ticket paid to that QING (FairProgress).
		var r: Dictionary = await FairProgress.refresh(String(ev["w"]), String(ev.get("room", "")))
		ok = bool(r.get("ok", false)) and FairProgress.unlocked(FairProgress.played(r["codes"], FairBoard.state_of(String(ev.get("room", ""))).get("rows", []), String(ev["w"])))
		if not ok:
			print("[Net] %s's rocket claim at %s is not on the chain (yet): not shown" % [ev["w"], ev.get("room", "")])
	_checking.erase(key)
	if ok:
		_add(ev)


# --- Chain facts this machine reads itself ------------------------------------------

## A fresh room line (ChatFeed.bubble): a 🎪 fair score is shown once its ticket's receipt
## and its replay check out (FairBoard.verify), like the stall's board counts it.
func on_room_line(l: Dictionary, qing: String) -> void:
	var p := FairBoard.parse(String(l.get("text", "")))
	var w := String(l.get("wallet", "")).to_lower()
	if p.is_empty() or w == "" or String(l.get("source", "")) == "say":
		return
	var rc: Dictionary = await FairBoard.receipt(String(p["ticket"]))
	var line := l.duplicate()
	line["from"] = w
	var row := FairBoard.verify(line, rc, qing)
	if row.get("verified", false):
		add_local({"k": "fair", "w": w, "game": String(row["game"]), "score": int(row["score"]), "room": qing,
			"block": int(row.get("line_block", 0))})


var _board_prev := {}   # wallet → hypobar (PackedInt64Array)
var _board_block := -1
var _board_qing := ""


## A territory read (TerritoryState.changed): each known player's Hypobar here,
## compared with the last read. A rise is a measured fact (both reads, their blocks).
func on_territory_read(st: TerritoryState) -> void:
	if st == null or st.block < 0 or not st.total_hypobar.has_value():
		return
	if st.address != _board_qing:
		_board_qing = st.address
		_board_prev = {}
		_board_block = -1
	if st.block == _board_block:
		return
	var now := {}
	for r in st.board:
		now[String(r["wallet"])] = r["hypobar"]
	if _board_block >= 0:
		for w in now:
			if _board_prev.has(w) and BigInt.cmp(now[w], _board_prev[w]) > 0:
				add_local({"k": "hypobar", "w": w, "room": st.address, "block": st.block,
					"amount": NetEvents.grouped_dec(BigInt.to_decimal(BigInt.sub(now[w], _board_prev[w])))})
	_board_prev = now
	_board_block = st.block
