extends Node
## Autoload "Alerts": "while you were away" and the alerts that bring you back.
##
## While you were away (AwayDiff, AwayRead, AwayStore): once a wallet is known and
## Session has read it, the baseline this computer stored at your last visit is
## compared with the chain now, and one card lists only what really changed, each
## with its block or tx: new lines in your rooms, lines naming your LAU, your QINGs'
## Hypobar/tier and leads, your bars, new QINGs. The front door shows it (right
## column), the notification panel keeps it, and on arrival a compact copy shows for
## a while unless you saw it already. First visit: no card, only the baseline. The
## baseline is kept current during the visit (bars, rooms read, the registry, the
## boards every 10 min) and saved at least once a minute and on quit.
##
## Alerts (AlertGate merges repeats and paces them; AlertPrefs = the player's choices,
## F2 · Online & voice): a toast (AlertOverlay), a note under the bell (Invites.notes)
## and a short sound when
##   - a room line names you: the current room's live feed (ChatFeed) and ONE
##     eth_getLogs every WATCH_S over every room you belong to (address list);
##   - someone invites you or asks you to join them (Invites' notes, the game server);
##   - someone arrives in one of your QINGs (the server's "arrive" events, Net.activity);
##   - you lose a crown (Session.lead_changed: the board of known players).
## Your own lines never alert (same Aura). An unfocused window also asks the OS for
## attention (taskbar flash: DisplayServer.window_request_attention); Godot has no
## native OS notification, so none is faked.

signal away_changed
signal raised(toast: Dictionary)

const WATCH_S := 30.0
const TOTALS_S := 600.0
const SAVE_S := 60.0
const ARRIVAL_CARD_S := 30.0
const SEEN_AFTER_S := 4.0  # a card on screen this long counts as seen (the arrival card then stays away)
const FRONT_DOOR := "res://scenes/ui/front_door.tscn"
const PLACE_SCENES := [Travel.TERRITORY_SCENE, Travel.HALL_SCENE, Travel.ARCADE_SCENE, Travel.PUB_SCENE, Travel.VOID_SCENE]
const CUES := {"mention": "mention", "invite": "alert", "arrive": "alert", "crown": "crown"}

var prefs := AlertPrefs.new()
var gate := AlertGate.new()
var overlay: AlertOverlay
var away_state := "hidden"  # hidden | reading | ready
var away_card: Dictionary = {}
var away_dismissed := false
var away_seen := false
var away_preview := -1      # --away-since=<block>: the baseline read from the chain at that block (never saved)
var rooms: Array = []       # your rooms (AwayRead.rooms_for), watched for mentions
var my_qings := {}
var pending_line: Dictionary = {}

var _server := false
var _away_for := ""
var _base: Dictionary = {}
var _base_wallet := ""
var _no_save := false
var _read_only := false     # a tool run (-s) or a read-only view of a wallet (--session=): the baseline is never written
var _dirty := false
var _save_t := 0.0
var _watch_t := 0.0
var _totals_t := 0.0
var _watch_after := -1
var _watching := false
var _seen_keys := {}
var _feed: RoomFeed
var _primed := {}
var _scene: Node
var _seen_t := 0.0
var _arrival_done := false
var _tick := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.has("--server") or args.has("--alerts-off"):
		_server = true
		return
	for a in args:
		if a.begins_with("--away-since="):
			away_preview = int(a.substr(13))
		elif a.begins_with("--session="):
			_read_only = true
	var all_args := OS.get_cmdline_args()
	if all_args.has("-s") or all_args.has("--script"):
		_read_only = true
	prefs.load_prefs()
	Session.changed.connect(_on_session)
	Session.lead_changed.connect(_on_leads)
	Registry.updated.connect(func(_n): _on_registry())
	_bind.call_deferred()


func _bind() -> void:
	overlay = AlertOverlay.new()
	add_child(overlay)
	Invites.note_added.connect(_on_note)
	ChatFeed.current_changed.connect(_bind_feed)
	if ChatFeed.current != null:
		_bind_feed(ChatFeed.current)
	var net := get_node_or_null("/root/Net")
	if net != null and net.get("activity") != null:
		net.activity.added.connect(_on_activity)


func _exit_tree() -> void:
	save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _process(delta: float) -> void:
	if _server:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for t in gate.release(now):
		if overlay:
			overlay.show_toast(t)
	if _card_on_screen():
		_seen_t += delta
		if _seen_t >= SEEN_AFTER_S:
			away_seen = true
	_tick += delta
	if _tick < 0.5:
		return
	var dt := _tick
	_tick = 0.0
	var s := get_tree().current_scene
	if s != _scene:
		_scene = s
		if overlay:
			overlay.place(s != null and s.scene_file_path == FRONT_DOOR)
	_maybe_arrival_card()
	_maybe_open_line()
	_watch_t += dt
	_totals_t += dt
	_save_t += dt
	if _watch_t >= WATCH_S:
		_watch_t = 0.0
		_watch()
	if _totals_t >= TOTALS_S:
		_totals_t = 0.0
		_refresh_totals()
	if _save_t >= SAVE_S:
		_save_t = 0.0
		if _dirty:
			save()


func _card_on_screen() -> bool:
	if overlay and overlay.card_visible():
		return true
	var s := get_tree().current_scene
	if s and s.scene_file_path == FRONT_DOOR and away_state == "ready" and not away_dismissed:
		return true  # the front door's own card (right column)
	return false


# --- While you were away ------------------------------------------------------------------

func _on_session() -> void:
	var w := Session.wallet
	if w == "":
		_reset()
		return
	var ps: PlayerState = Session.player
	if ps == null or ps.wallet != w or not ps.ok:
		return
	if ps.has_yue() and Session.bars_block != ps.block:
		return  # wait for this read's bars
	if not _primed.has(w):
		_primed[w] = true  # from now on a lead change is live news (the card covers the ones before)
	if _away_for != w:
		save()  # the previous wallet's visit, before this one's card replaces it
		_away_for = w
		away_dismissed = false
		away_seen = false
		_arrival_done = false
		_run_away(w)
		return
	if _base_wallet == w and ps.has_yue() and Session.bars_block > 0:
		var before := int(_base.get("bars_block", -1))
		_base = AwayDiff.with_bars(_base, AwayDiff.bars_dec(Session.bars), Session.bars_block)
		if int(_base.get("bars_block", -1)) != before:
			_dirty = true


func _reset() -> void:
	save()
	_away_for = ""
	_base = {}
	_base_wallet = ""
	rooms = []
	my_qings = {}
	_watch_after = -1
	away_state = "hidden"
	away_card = {}
	away_dismissed = false
	away_seen = false
	_arrival_done = false
	if overlay:
		overlay.hide_card()
	away_changed.emit()


func _run_away(w: String) -> void:
	var prev := AwayStore.load_for(w)
	var opts := {"player": Session.player}
	if Session.player != null and Session.player.has_yue() and Session.bars_block == Session.player.block:
		opts["bars"] = Session.bars
		opts["bars_block"] = Session.bars_block
	_no_save = false
	if away_preview > 0:
		var pv := await AwayRead.at_block(w, away_preview, opts)
		if not pv.is_empty():
			prev = pv
			_no_save = true
	if not prev.is_empty():
		away_state = "reading"
		away_card = {"since": int(prev["block"]), "preview": bool(prev.get("preview", false))}
		away_changed.emit()
	var now := await AwayRead.read(w, prev, opts)
	if Session.wallet != w:
		return  # switched wallets meanwhile
	var card := AwayDiff.compute(prev, now, AwayDiff.me_of(Session.player, w), names_for(now))
	_base = AwayDiff.next_baseline(prev, now, int(Time.get_unix_time_from_system()))
	_base_wallet = w
	rooms = now.get("rooms_list", [])
	my_qings = {}
	for q in rooms:
		my_qings[q] = true
	_watch_after = int(now["rooms_to"]) if bool(now.get("rooms_ok", false)) else int(now.get("block", -1))
	_dirty = true
	save()
	away_card = card
	away_state = "hidden" if bool(card.get("first", false)) else "ready"
	for line in AwayDiff.lines(card):
		print("[Away] ", line)
	away_changed.emit()


## Every QING a read mentions → its name (else the short address).
static func names_for(now: Dictionary) -> Dictionary:
	var out := {}
	var add := func(q: String) -> void:
		var t: Dictionary = Registry.get_territory(q)
		if not t.is_empty():
			out[q] = String(t.get("name", ""))
	for q in now.get("rooms_list", []):
		add.call(String(q))
	for q in now.get("bars", {}):
		add.call(String(q))
	for q in now.get("qings", {}):
		add.call(String(q))
	return out


## The notification panel opened (true) or closed: while it is open the toasts and the
## arrival card step aside (it lists them), and the card counts as seen.
func panel_shown(on: bool) -> void:
	if on:
		away_seen = true
	if overlay:
		overlay.set_hidden(on)


func dismiss_away() -> void:
	away_dismissed = true
	away_seen = true
	if overlay:
		overlay.hide_card()
	away_changed.emit()


func _maybe_arrival_card() -> void:
	if _arrival_done or away_state != "ready" or away_dismissed or away_seen or overlay == null:
		return
	var s := get_tree().current_scene
	if s == null or not (s.scene_file_path in PLACE_SCENES):
		return
	if s.get("is_built") == false:
		return
	_arrival_done = true
	overlay.show_card(away_card, ARRIVAL_CARD_S)


## Writes the baseline (at most once a minute, and on quit). Never in a preview.
func save() -> void:
	_dirty = false
	if _no_save or _read_only or _base_wallet == "" or _base.is_empty():
		return
	AwayStore.save_for(_base_wallet, _base)


func _on_registry() -> void:
	if _base.is_empty() or Registry.catching_up or Registry.last_error != "":
		return
	_base = AwayDiff.with_registry(_base, Registry.count(), Registry.cursor_block)
	_dirty = true


func _refresh_totals() -> void:
	if _base_wallet == "" or rooms.is_empty():
		return
	var w := _base_wallet
	var head := await Chain.refresh_head()
	if head < 0 or w != _base_wallet:
		return
	var ps: PlayerState = Session.player
	var tmp := {"qings": {}, "qings_failed": []}
	await AwayRead.totals(tmp, rooms.slice(0, AwayRead.QINGS_MAX), head, w, ps.yue if ps != null and ps.has_yue() else "")
	if w == _base_wallet:
		_base = AwayDiff.with_qings(_base, tmp["qings"])
		_dirty = true


# --- Mentions in your rooms ------------------------------------------------------------------

## One eth_getLogs over every room you belong to, for the blocks since the last look.
func _watch() -> void:
	if _watching or _base_wallet == "" or rooms.is_empty() or _watch_after <= 0:
		return
	_watching = true
	var head := await Chain.refresh_head()
	if head > _watch_after:
		var r: Dictionary = await Chain.logs.scan(rooms, [Contracts.TOPIC_ROOM_CHAT], _watch_after + 1, head)
		if r["ok"]:
			var by := AwayRead.split_lines(r["logs"], rooms, {"block": _watch_after})
			var all: Array = []
			for q in by:
				for l in by[q]:
					all.append(l)
					_on_line(l, q)
			_watch_after = head
			_base = AwayDiff.with_rooms_seen(_base, rooms, head, all)
			_dirty = true
	_watching = false


func _bind_feed(f: RoomFeed) -> void:
	if _feed != null and is_instance_valid(_feed) and _feed.arrived.is_connected(_on_feed_arrived):
		_feed.arrived.disconnect(_on_feed_arrived)
	_feed = f
	if f != null and not f.arrived.is_connected(_on_feed_arrived):
		f.arrived.connect(_on_feed_arrived)


func _on_feed_arrived(fresh: Array) -> void:
	if _feed == null or not is_instance_valid(_feed):
		return
	for l in fresh:
		_on_line(l, _feed.qing)


## A new room line from any source: alerts once if it names you (never your own).
## `replay` (screenshots and checks): a real line from the chain, passed through again.
func _on_line(l: Dictionary, qing: String, replay: bool = false) -> bool:
	if String(l.get("source", "chain")) == "say" or int(l.get("block", -1)) <= 0:
		return false  # only room lines (chain truth) name you
	var k := ChatLines.key(l)
	if _seen_keys.has(k) and not replay:
		return false
	_seen_keys[k] = true
	var me := AwayDiff.me_of(Session.player, Session.wallet)
	if not AwayDiff.names_you(l, me):
		return false
	var place := String(Registry.get_territory(qing).get("name", NetProto.short_wallet(qing)))
	var here := _feed != null and is_instance_valid(_feed) and _feed.qing == qing and ChatFeed.feed_visible()
	raise("mention", "mention|" + qing, {"who": ChatLines.speaker(l), "place": place, "text": ChatLines.clean_text(String(l.get("text", "")), 90),
		"ref": k, "go": {"to": "line", "qing": qing, "key": k, "block": int(l["block"])},
		"note": ("replayed · block %s" % TokenFormat.group(str(int(l["block"])))) if replay else "block %s" % TokenFormat.group(str(int(l["block"]))),
		"quiet_sound": here and _focused()})  # the dock chimes for its own room
	return true


## Screenshots and checks: the newest `n` real lines of the current room, through the
## mention path again (a line that names the session's LAU alerts; others don't).
func replay_lines(n: int) -> int:
	if _feed == null or not is_instance_valid(_feed):
		return 0
	var hits := 0
	for l in _feed.lines.slice(maxi(0, _feed.lines.size() - n)):
		if _on_line(l, _feed.qing, true):
			hits += 1
	return hits


# --- Invites, arrivals, crowns ---------------------------------------------------------------

func _on_note(x: Dictionary) -> void:
	if x.get("alerts", false):
		return  # one of ours (a mention, an arrival, a crown)
	if String(x.get("kind", "")) == "invite":
		raise("invite", "invite", {"text": String(x["text"]), "ref": String(x.get("ref", "")), "go": {"to": "invite", "id": String(x.get("ref", ""))}}, false)
		return
	# Other game notes (accepted, declined, results, refusals): a toast as before, no sound.
	var t := gate.push({"kind": "game", "group": "game", "text": String(x["text"]), "go": {"to": "invite", "id": String(x.get("ref", ""))}}, Time.get_ticks_msec() / 1000.0)
	if overlay and String(t["action"]) != "held":
		overlay.show_toast(t["toast"])


func _on_activity(item: Dictionary) -> void:
	var ev: Dictionary = item.get("ev", {})
	if String(ev.get("k", "")) != "arrive":
		return
	var room := String(ev.get("room", "")).get_slice("/", 0)
	var w := String(ev.get("w", ""))
	if not my_qings.has(room) or w == "" or w == Session.wallet:
		return
	var net := get_node_or_null("/root/Net")
	var who: String = net.names.display(w) if net and net.names else NetProto.short_wallet(w)
	raise("arrive", "arrive|" + room, {"who": who, "place": String(Registry.get_territory(room).get("name", NetProto.short_wallet(room))),
		"text": String(item.get("text", "")), "ref": w, "go": {"to": "qing", "qing": room}, "note": "game server"})


func _on_leads(lost: Array, _gained: Array, block: int) -> void:
	if not _primed.has(Session.wallet):
		return  # the first read of this launch: since the last visit, the card's business
	for a in lost:
		var place := String(Registry.get_territory(a).get("name", NetProto.short_wallet(a)))
		raise("crown", "crown", {"place": place, "text": "Lead lost at %s · someone passed you (YUE.Bar of known players, block %s)" % [place, TokenFormat.group(str(block))],
			"ref": String(a), "go": {"to": "qing", "qing": String(a)}, "note": "block %s" % TokenFormat.group(str(block))})


# --- Raising one ----------------------------------------------------------------------------

## An alert of `kind` (AlertGate.KINDS): merged/paced by the gate, a toast, a note under
## the bell (unless the note exists already), the sound, and the taskbar flash when the
## window is not focused. Off kinds do nothing.
func raise(kind: String, group: String, a: Dictionary, add_note: bool = true) -> Dictionary:
	if _server or not prefs.on(kind):
		return {}
	a["kind"] = kind
	a["group"] = group
	var now := Time.get_ticks_msec() / 1000.0
	var res := gate.push(a, now)
	if add_note:
		var one := {"kind": kind, "count": 1, "who": a.get("who", ""), "place": a.get("place", ""), "text": a.get("text", "")}
		Invites.add_note(kind, AlertGate.text_of(one), String(a.get("ref", "")), {"alerts": true, "go": a.get("go", {})})
	if overlay and String(res["action"]) != "held":
		overlay.show_toast(res["toast"])
	if prefs.sound and not a.get("quiet_sound", false) and gate.sound_ok(now):
		Cues.play(self, String(CUES.get(kind, "alert")))
	if prefs.flash and not _focused() and gate.attention_ok(now):
		DisplayServer.window_request_attention()
	raised.emit(res["toast"])
	return res


static func _focused() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	return DisplayServer.window_is_focused()


# --- Going there -------------------------------------------------------------------------------

## A card line or a toast was clicked: {to: "qing"|"line"|"invite", qing, key, block, id}.
func go(target: Dictionary) -> void:
	var s := get_tree().current_scene
	for p in (s.find_children("NotificationPanel", "", true, false) if s else []):
		if p.has_method("close"):
			p.close()
	match String(target.get("to", "")):
		"qing":
			var q := String(target.get("qing", ""))
			if q != "" and not (s and s.scene_file_path == Travel.TERRITORY_SCENE and GameManager.territory_address == q):
				Warp.to(get_tree(), q)
		"line":
			pending_line = target.duplicate()
			var q := String(target.get("qing", ""))
			if not (s and s.scene_file_path == Travel.TERRITORY_SCENE and GameManager.territory_address == q):
				Warp.to(get_tree(), q)
			_maybe_open_line()
		"invite":
			var p = s.find_child("NotificationPanel", true, false) if s else null
			if p and p.has_method("open"):
				p.open()


## After a "line" click: once in that territory with its room read, the history opens at the line.
func _maybe_open_line() -> void:
	if pending_line.is_empty():
		return
	var s := get_tree().current_scene
	var q := String(pending_line.get("qing", ""))
	if s == null or s.scene_file_path != Travel.TERRITORY_SCENE or GameManager.territory_address != q or s.get("is_built") == false:
		return
	var f: RoomFeed = ChatFeed.current
	if f == null or f.qing != q or not f.is_loaded():
		return
	var panel = ChatFeed.hud.get("feed") if ChatFeed.hud else null
	if panel == null or not panel.has_method("open_history_at"):
		return
	var target := pending_line
	pending_line = {}
	panel.open_history_at(String(target.get("key", "")), int(target.get("block", -1)))
