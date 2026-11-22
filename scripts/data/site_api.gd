class_name SiteApi
extends Node
## Optional accelerator: the Entropy site's chain-backed endpoints
## (default https://systm0.vercel.app). Every feature must also work without
## it. Never use it for XP/levels/achievements (those endpoints are Redis-backed
## and empty in production). See docs/LEARNINGS.md §8.
##
## Returns {ok: true, data} or {ok: false, error}.

const TIMEOUT_S := 20.0

var base_url := Contracts.DEFAULT_SITE_API
var enabled := true


func get_json(path: String, query: Dictionary = {}) -> Dictionary:
	if not enabled or base_url.is_empty():
		return {"ok": false, "error": "site API disabled"}
	var url := base_url.trim_suffix("/") + path
	if not query.is_empty():
		var parts: PackedStringArray = []
		for k in query:
			parts.append("%s=%s" % [String(k).uri_encode(), str(query[k]).uri_encode()])
		url += "?" + "&".join(parts)
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return {"ok": false, "error": "request error"}
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return {"ok": false, "error": "http %d / result %d" % [r[1], r[0]]}
	var json := JSON.new()
	if json.parse((r[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return {"ok": false, "error": "non-JSON response"}
	return {"ok": true, "data": json.data}


## Chain-backed endpoints the game may use.
func qing_chat(qing: String, limit: int = 100, after: int = -1) -> Dictionary:
	var q := {"qing": qing, "limit": limit}
	if after >= 0:
		q["after"] = after
	return _expect_key(await get_json("/api/qing-chat", q), "messages")


func void_messages(limit: int = 200) -> Dictionary:
	return _expect_key(await get_json("/api/void-messages", {"limit": limit}), "messages")


func entity(address: String) -> Dictionary:
	return await get_json("/api/d-entity", {"address": address})


func leaders(kind: String = "hypobar", limit: int = 100) -> Dictionary:
	return await get_json("/api/d-leaders", {"type": kind, "limit": limit})


func world_watch() -> Dictionary:
	return _expect_key(await get_json("/api/world-watch"), "status")


func players_snapshot() -> Dictionary:
	return await get_json("/data/players.json")


static func _expect_key(r: Dictionary, key: String) -> Dictionary:
	if r["ok"] and not (r["data"] is Dictionary and r["data"].has(key)):
		return {"ok": false, "error": "unexpected response shape (no '%s')" % key}
	return r
