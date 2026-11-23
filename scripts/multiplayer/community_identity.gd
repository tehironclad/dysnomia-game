class_name CommunityIdentity
extends RefCounted
## Who the local player is on the realtime channels.
##   Wallet players  → presence key = wallet (lowercase), same as wallet.html.
##   Everyone else   → presence key = stable guest id ("guest-" + 8 hex), generated once
##                     and stored in user://community_guest.cfg.
## Display name: LAU username if loaded, else the wallet short form, else "Guest-XXXX".
## Nothing else about the player is ever put on the wire.

const GUEST_PREFIX: String = "guest-"

## Overridable for tests (two instances on one machine share user://).
## Also settable via cmdline user arg --guest-id-file=<path>.
static var guest_id_path: String = "user://community_guest.cfg"

static var _cached_guest_id: String = ""


static func _resolved_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--guest-id-file="):
			return arg.substr(16)
	return guest_id_path


static func get_guest_id() -> String:
	## Stable per-install guest id. Generated on first call, persisted thereafter.
	var path := _resolved_path()
	if not _cached_guest_id.is_empty() and _cached_guest_id_path == path:
		return _cached_guest_id
	var cf := ConfigFile.new()
	var id := ""
	if cf.load(path) == OK:
		id = str(cf.get_value("guest", "id", ""))
	if not is_valid_guest_id(id):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		id = GUEST_PREFIX + "%08x" % (rng.randi() & 0xffffffff)
		cf.set_value("guest", "id", id)
		cf.save(path)
	_cached_guest_id = id
	_cached_guest_id_path = path
	return id


static var _cached_guest_id_path: String = ""


static func clear_cache() -> void:
	_cached_guest_id = ""
	_cached_guest_id_path = ""


static func is_valid_guest_id(id: String) -> bool:
	if not id.begins_with(GUEST_PREFIX) or id.length() != GUEST_PREFIX.length() + 8:
		return false
	return id.substr(GUEST_PREFIX.length()).is_valid_hex_number()


static func is_guest_key(key: String) -> bool:
	return key.begins_with(GUEST_PREFIX)


static func guest_display_name(guest_id: String) -> String:
	return "Guest-" + guest_id.right(4).to_upper()


static func short_wallet(w: String) -> String:
	if w.length() < 12:
		return w
	return w.left(6) + ".." + w.right(4)


static func resolve(wallet: String, username: String = "") -> Dictionary:
	## → {key, name, guest}. username overrides the fallback name when non-empty.
	var w := wallet.strip_edges().to_lower()
	var lau_name := ""
	var gm := _game_manager()
	if gm:
		lau_name = str(gm.get("lau_username"))
		if lau_name == "<null>":
			lau_name = ""
	var name := username.strip_edges()
	if name == "Anonymous":
		name = ""
	if name.is_empty():
		name = lau_name
	if w.begins_with("0x") and w.length() >= 10:
		return {"key": w, "name": name if not name.is_empty() else short_wallet(w), "guest": false}
	var gid := get_guest_id()
	return {"key": gid, "name": name if not name.is_empty() else guest_display_name(gid), "guest": true}


static func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("GameManager")
	return null


static func sanitize_text(t: String, max_len: int = 120) -> String:
	## Chat/emote text: single line, trimmed, bounded.
	var s := t.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	if s.length() > max_len:
		s = s.left(max_len - 1) + "…"
	return s
