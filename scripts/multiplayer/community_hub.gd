class_name CommunityHub
extends Node
## Shared moments + online counts + invite text — the social layer on top of the realtime
## channels owned by MultiplayerManager.
##
## Lives at Main/CommunityHub (MultiplayerManager creates it as its sibling if main.gd
## doesn't). Any code can reach it:
##     CommunityHub.emit_moment("ride", {"ride": "Upsilon Rocket"})     # static, no-op if absent
##     get_tree().get_first_node_in_group("community_hub").announce(...)
##
## Wire format — broadcast event `moment` on the QING channel AND on `dysnomia:global`:
##   {id, w: <wallet|guest id>, n: <username>, k: <kind>, d: {…small flat data…},
##    qing: <qing address, lowercase>, qn: <qing name>}
## Receivers de-duplicate by id (a player in the same QING gets it on both channels).
##
## moment_received(kind, data, from_name) — data is the sender's data plus:
##   qing (String, address the moment happened in), qing_name, here (bool: same QING as us),
##   self (bool: our own announce, echoed locally), from (sender key).
## Kinds used by the game: ride, house_round, board_post, promotion, arrival.

signal moment_received(kind: String, data: Dictionary, from_name: String)
signal online_counts_changed(here: int, total: int)

const GLOBAL_CHANNEL: String = "dysnomia:global"
const CommunityFeedScript = preload("res://scripts/ui/community_feed.gd")
const CommunityIdentityScript = preload("res://scripts/multiplayer/community_identity.gd")

const ANNOUNCE_COOLDOWN_MS: int = 1500
const ARRIVAL_COOLDOWN_MS: int = 300000   # one arrival per QING per 5 min
const MAX_DATA_KEYS: int = 8
const CHAT_BUBBLE_MAX_AGE_MS: int = 180000

static var instance: Node = null

## Build the "HAPPENING NOW" feed + online counter UI. Set false before add_child to skip.
var create_ui: bool = true

var _mm: Node = null
var _rt: Node = null
var _seen_ids: Array[String] = []
var _last_announce: Dictionary = {}   # kind (or arrival|qing) → msec
var _here: int = 0
var _total: int = 0
var _chat_seen: Dictionary = {}
var _chat_primed: bool = false
var _recent_say: Dictionary = {}       # "name|text" → msec
var _feed: Control = null
var _layer: CanvasLayer = null
# Emote wheel hook
var _wheel: Node = null
var _wheel_was_visible: bool = false
var _wheel_hover: int = -1
var _wheel_signaled: bool = false


func _enter_tree() -> void:
	instance = self
	add_to_group("community_hub")


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	if create_ui:
		_layer = CanvasLayer.new()
		_layer.name = "CommunityLayer"
		_layer.layer = 5
		add_child(_layer)
		_feed = CommunityFeedScript.new()
		_feed.name = "CommunityFeed"
		_layer.add_child(_feed)
		_feed.bind(self)
	get_tree().node_added.connect(_on_node_added)
	var cm := get_node_or_null("/root/ChainManager")
	if cm and cm.has_signal("chat_messages_received"):
		cm.chat_messages_received.connect(_on_chain_chat)


static func get_instance() -> Node:
	return instance if instance and is_instance_valid(instance) else null


static func emit_moment(kind: String, data: Dictionary = {}) -> void:
	## Fire-and-forget from anywhere; silently does nothing without a hub.
	var h := get_instance()
	if h:
		h.announce(kind, data)


func bind(manager: Node) -> void:
	if _mm == manager:
		return
	_mm = manager
	_rt = manager.get_realtime() if manager.has_method("get_realtime") else null
	if _rt:
		_rt.broadcast_received.connect(_on_broadcast)
		_rt.presence_synced.connect(func(_c: String, _s: Dictionary) -> void: _recount())
		_rt.presence_joined.connect(func(_c: String, _k: String, _m: Dictionary) -> void: _recount())
		_rt.presence_left.connect(func(_c: String, _k: String) -> void: _recount())
		_rt.connection_changed.connect(func(_o: bool) -> void: _recount())
		_rt.channel_left.connect(func(_c: String) -> void: _recount())


# ─── Moments ────────────────────────────────────────────────────────────

func announce(kind: String, data: Dictionary = {}) -> void:
	## Broadcast a shared moment to this QING + the whole of Dysnomia, and echo it locally.
	var k := kind.strip_edges().to_lower().left(24)
	if k.is_empty():
		return
	var now := Time.get_ticks_msec()
	var qing := _qing_address()
	var gate := k if k != "arrival" else "arrival|" + qing
	var cool := ANNOUNCE_COOLDOWN_MS if k != "arrival" else ARRIVAL_COOLDOWN_MS
	if _last_announce.has(gate) and now - int(_last_announce[gate]) < cool:
		return
	_last_announce[gate] = now

	var clean := sanitize_data(data)
	var id := "%08x%06x" % [randi() & 0xffffffff, randi() & 0xffffff]
	_remember(id)
	var my_key: String = _mm.get_local_key() if _mm else ""
	var my_name: String = _mm.get_local_name() if _mm else "You"
	var qn := _qing_name()
	var payload := {"id": id, "w": my_key, "n": my_name, "k": k, "d": clean, "qing": qing, "qn": qn}
	if _rt and _mm:
		var qc: String = _mm.get_qing_channel()
		if not qc.is_empty():
			_rt.send_broadcast(qc, "moment", payload)
		_rt.send_broadcast(GLOBAL_CHANNEL, "moment", payload)

	var local := clean.duplicate()
	local["qing"] = qing
	local["qing_name"] = qn
	local["here"] = true
	local["self"] = true
	local["from"] = my_key
	moment_received.emit(k, local, my_name)


func _on_broadcast(channel: String, event: String, p: Dictionary) -> void:
	if event != "moment" or _mm == null:
		return
	if channel != GLOBAL_CHANNEL and channel != _mm.get_qing_channel():
		return
	var id := str(p.get("id", ""))
	if id.is_empty() or _seen_ids.has(id):
		return
	_remember(id)
	var from_key := str(p.get("w", "")).to_lower()
	if from_key == _mm.get_local_key():
		return
	var k := str(p.get("k", "")).to_lower().left(24)
	if k.is_empty():
		return
	var d = p.get("d", {})
	var data := sanitize_data(d if d is Dictionary else {})
	var qing := str(p.get("qing", "")).to_lower().left(42)
	data["qing"] = qing
	data["qing_name"] = CommunityIdentityScript.sanitize_text(str(p.get("qn", "")), 40)
	data["here"] = not qing.is_empty() and qing == _qing_address()
	data["self"] = false
	data["from"] = from_key
	var from_name: String = CommunityIdentityScript.sanitize_text(str(p.get("n", "")), 32)
	if from_name.is_empty() or from_name == "<null>":
		from_name = CommunityIdentityScript.guest_display_name(from_key) if CommunityIdentityScript.is_guest_key(from_key) \
			else CommunityIdentityScript.short_wallet(from_key)
	# Everyone in the pub cheers for a round: remote avatars clap on our screen.
	if k == "house_round" and data.here and _mm.has_method("play_emote_on_all"):
		_mm.play_emote_on_all(7)
	moment_received.emit(k, data, from_name)


func _remember(id: String) -> void:
	_seen_ids.append(id)
	if _seen_ids.size() > 128:
		_seen_ids = _seen_ids.slice(_seen_ids.size() - 96)


static func sanitize_data(d: Dictionary) -> Dictionary:
	## Moments carry only a few small flat values (no nested objects, bounded strings).
	var out := {}
	for key in d:
		if out.size() >= MAX_DATA_KEYS:
			break
		var ks := str(key).left(24)
		var v = d[key]
		match typeof(v):
			TYPE_STRING, TYPE_STRING_NAME:
				out[ks] = CommunityIdentityScript.sanitize_text(str(v), 80)
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				out[ks] = v
			_:
				pass
	return out


static func describe(kind: String, data: Dictionary, from_name: String) -> String:
	## One-line human text for a moment (used by the toast feed; handy for Telegram too).
	var n := from_name if not from_name.is_empty() else "Someone"
	var where := str(data.get("qing_name", ""))
	var text := ""
	match kind:
		"ride":
			var ride := str(data.get("ride", data.get("name", data.get("title", "a ride"))))
			text = "🚀 %s boarded the %s" % [n, ride] if ride != "a ride" else "🚀 %s hopped on a ride" % n
		"house_round":
			text = "🍻 %s bought a round for the house!" % n
		"board_post":
			var board := str(data.get("board", data.get("wing", "")))
			text = "🖼 %s posted to the %s board" % [n, board] if not board.is_empty() else "🖼 %s posted to a board" % n
		"promotion":
			var t := str(data.get("tier_name", data.get("title", "")))
			if t.is_empty() and data.has("tier"):
				t = "tier %s" % str(data.tier)
			text = "⭐ %s rose to %s" % [n, t] if not t.is_empty() else "⭐ %s was promoted" % n
		"arrival":
			text = "👋 %s arrived%s" % [n, (" at " + where) if not where.is_empty() else ""]
			return text
		_:
			var msg := str(data.get("text", kind.replace("_", " ")))
			text = "✨ %s: %s" % [n, msg]
	if not bool(data.get("here", true)) and not where.is_empty():
		text += " · " + where
	return text


# ─── Online counts / invite ─────────────────────────────────────────────

func _recount() -> void:
	var here := 0
	var total := 0
	if _rt and _mm:
		var qc: String = _mm.get_qing_channel()
		if not qc.is_empty() and _rt.is_joined(qc):
			here = _rt.presence_count(qc)
		if _rt.is_joined(GLOBAL_CHANNEL):
			total = _rt.presence_count(GLOBAL_CHANNEL)
	total = maxi(total, here)
	if here != _here or total != _total:
		_here = here
		_total = total
		online_counts_changed.emit(here, total)


func get_online_here() -> int:
	return _here


func get_online_total() -> int:
	return _total


func is_online() -> bool:
	return _rt != null and _rt.is_open()


func counter_text() -> String:
	## "12 in Sunny's · 48 on Dysnomia" (empty when offline).
	if _total <= 0:
		return ""
	var qn := _qing_name()
	if _here > 0 and not qn.is_empty():
		return "%d in %s · %d on Dysnomia" % [_here, qn.left(28), _total]
	return "%d on Dysnomia" % _total


func invite_text() -> String:
	## Short shareable invite for Telegram, e.g.
	## "Come hang at SUNNY'S on Dysnomia — QING 0x1a2b…9f3e · 12 here now"
	var qn := _qing_name()
	var qa := _qing_address()
	var text := ""
	if qa.is_empty() or qa == "0x0":
		text = "Come hang out on Dysnomia"
		if _total > 0:
			text += " · %d online now" % _total
		return text
	var short := qa.left(6) + "…" + qa.right(4) if qa.length() > 12 else qa
	text = "Come hang at %s on Dysnomia — QING %s" % [(qn if not qn.is_empty() else "a QING").to_upper(), short]
	if _here > 0:
		text += " · %d here now" % _here
	return text


func _qing_address() -> String:
	if _mm and _mm.has_method("get_qing_address") and not str(_mm.get_qing_address()).is_empty():
		return str(_mm.get_qing_address()).to_lower()
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		var a := str(gm.get("territory_address")).to_lower()
		return "" if a == "0x0" else a
	return ""


func _qing_name() -> String:
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		var n := str(gm.get("territory_name")).strip_edges()
		if n != "<null>":
			return n
	return ""


# ─── Chat → bubbles ─────────────────────────────────────────────────────

func say(text: String) -> bool:
	## Speech bubble over our head for everyone in this QING (no chain tx).
	if _mm == null:
		return false
	_recent_say[_say_key(_mm.get_local_name(), text)] = Time.get_ticks_msec()
	return _mm.send_say(text)


func send_emote(emote_id: int) -> bool:
	return _mm.send_emote(emote_id) if _mm else false


func _say_key(n: String, t: String) -> String:
	return n.strip_edges().to_lower() + "|" + CommunityIdentityScript.sanitize_text(t).to_lower()


func _on_chain_chat(messages: Array) -> void:
	## Territory chat list from ChainManager (API/chain poll + local echo on send).
	## New local-echo lines → `say` broadcast (instant bubble for everyone, guests included);
	## new on-chain lines from someone here → bubble over their avatar.
	if _mm == null:
		return
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var fresh: Array = []
	for m in messages:
		if not (m is Dictionary):
			continue
		var sig := "%s|%s|%s|%s" % [m.get("username", ""), m.get("message", ""), m.get("block", 0), m.get("ts", 0)]
		if _chat_seen.has(sig):
			continue
		_chat_seen[sig] = true
		fresh.append(m)
	if _chat_seen.size() > 600:
		_chat_seen.clear()
		_chat_primed = false
	if not _chat_primed:
		_chat_primed = true
		# History: no bubbles, except a local echo sent right now
		fresh = fresh.filter(func(m: Dictionary) -> bool: return str(m.get("source", "")) == "local")
	var tick := Time.get_ticks_msec()
	for m in fresh:
		var text := str(m.get("message", ""))
		var uname := str(m.get("username", ""))
		if text.strip_edges().is_empty():
			continue
		var sk := _say_key(uname, text)
		if str(m.get("source", "")) == "local":
			if _recent_say.has(sk) and tick - int(_recent_say[sk]) < 10000:
				continue
			_recent_say[sk] = tick
			_mm.send_say(text)
			continue
		var ts := int(m.get("ts", 0))
		if ts <= 0 or now_ms - ts > CHAT_BUBBLE_MAX_AGE_MS:
			continue
		if _recent_say.has(sk) and tick - int(_recent_say[sk]) < 300000:
			continue  # already shown via a live `say`
		_recent_say[sk] = tick
		var rp = _mm.find_remote_by_name(uname)
		if rp:
			rp.show_chat(text)
	if _recent_say.size() > 200:
		_recent_say.clear()


# ─── Emote wheel hook ───────────────────────────────────────────────────
# The HUD's emote wheel only POSTs to the entropy API (wallet players). Watch it so every
# emote — guests included — is also broadcast on the QING channel.

func _on_node_added(n: Node) -> void:
	if n.has_signal("emote_selected") and n.has_method("get_hovered_segment"):
		_wheel = n
		_wheel_was_visible = false
		n.emote_selected.connect(func(eid: int) -> void:
			_wheel_signaled = true
			send_emote(eid))
		if n.has_signal("wheel_closed"):
			n.wheel_closed.connect(func() -> void: _wheel_signaled = true)


func _process(_delta: float) -> void:
	if _wheel == null:
		return
	if not is_instance_valid(_wheel):
		_wheel = null
		return
	var vis: bool = _wheel.visible
	if vis:
		if not _wheel_was_visible:
			_wheel_signaled = false
		_wheel_hover = _wheel.get_hovered_segment()
	elif _wheel_was_visible:
		# Q-release path selects without a signal; Esc cancels.
		if not _wheel_signaled and _wheel_hover >= 0 and not Input.is_key_pressed(KEY_ESCAPE):
			send_emote(_wheel_hover)
		_wheel_hover = -1
	_wheel_was_visible = vis
