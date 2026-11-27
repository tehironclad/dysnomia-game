extends Node
## A mock Telegram Bot API for the bridge's checks and screenshots (tools/tg_selftest.gd,
## tools/tg_mock.gd): plain HTTP/1.1 on 127.0.0.1, one request per connection.
##   POST /bot<token>/getUpdates  {offset, timeout}: held until an update ≥ offset exists or
##                                the timeout (capped at hold_cap_s) runs out; offset confirms
##   POST /bot<token>/sendMessage {chat_id, text, …}: recorded in `sent`, answered with a message id
## Any other token: 401. Never touches the network beyond 127.0.0.1. Point a game server at it
## with TELEGRAM_API_BASE=http://127.0.0.1:<port>.
##
## Tests drive it: push_message(chat_id, fields, edited), push_update(update), `sent`,
## `requests` (every path and body seen), fail_sends (the next N sendMessage answer 429).

var port := 18790
var token := ""
var hold_cap_s := 2.0
var updates: Array = []
var sent: Array = []        # [{chat_id, text, body (the parsed request), raw}]
var requests: Array = []    # [{path, body}]
var fail_sends := 0
var retry_after := 1
var unauthorized := 0
var _next_update := 1000
var _next_msg := 5000
var _tcp := TCPServer.new()
var _conns: Array = []      # [{peer, buf, wait: {offset, until} | null, t0}]


func start() -> bool:
	return _tcp.listen(port, "127.0.0.1") == OK


func stop() -> void:
	for c in _conns:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	_tcp.stop()


## A message in chat `chat_id`; `fields` merge over {message_id, date, chat, from}. Returns the message id.
func push_message(chat_id: int, fields: Dictionary, edited: bool = false) -> int:
	var mid := int(fields.get("message_id", 0))
	if mid <= 0:
		_next_msg += 1
		mid = _next_msg
	var m := {"message_id": mid, "date": int(Time.get_unix_time_from_system()), "chat": {"id": chat_id, "type": "supergroup", "title": "Sunny's Pub (mock)"},
		"from": {"id": 42, "is_bot": false, "first_name": "Ann", "last_name": "Lee"}}
	m.merge(fields, true)
	if edited:
		m["edit_date"] = int(Time.get_unix_time_from_system())
	push_update({"edited_message" if edited else "message": m})
	return mid


func push_update(u: Dictionary) -> void:
	_next_update += 1
	u["update_id"] = _next_update
	updates.append(u)


func _process(_delta: float) -> void:
	if not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var p := _tcp.take_connection()
		if p:
			_conns.append({"peer": p, "buf": PackedByteArray(), "wait": null, "t0": Time.get_ticks_msec()})
	var now := Time.get_ticks_msec() / 1000.0
	for c in _conns.duplicate():
		var p: StreamPeerTCP = c["peer"]
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		if c["wait"] != null:
			var w: Dictionary = c["wait"]
			var ready := _pending_from(int(w["offset"]))
			if not ready.is_empty() or now >= float(w["until"]):
				_respond(c, 200, {"ok": true, "result": ready})
			continue
		var n := p.get_available_bytes()
		if n > 0:
			var got := p.get_data(n)
			if got[0] == OK:
				var b: PackedByteArray = c["buf"]
				b.append_array(got[1])
				c["buf"] = b  # packed arrays are values: store it back
		_try_request(c, now)


func _pending_from(offset: int) -> Array:
	updates = updates.filter(func(u): return int(u["update_id"]) >= offset)  # an offset confirms what came before
	return updates.duplicate(true)


func _try_request(c: Dictionary, now: float) -> void:
	var buf: PackedByteArray = c["buf"]
	var text := buf.get_string_from_utf8()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return
	var head := text.left(head_end)
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		_respond(c, 400, {"ok": false, "description": "bad request"})
		return
	var length := 0
	for l in lines:
		if l.to_lower().begins_with("content-length:"):
			length = int(l.substr(15).strip_edges())
	var body_bytes := buf.slice(head_end + 4)
	if body_bytes.size() < length:
		return
	var path := first[1]
	var body_text := body_bytes.slice(0, length).get_string_from_utf8()
	requests.append({"path": path, "body": body_text})
	var j = JSON.parse_string(body_text) if body_text != "" else {}
	var body: Dictionary = j if j is Dictionary else {}
	var prefix := "/bot%s/" % token
	if not path.begins_with(prefix):
		unauthorized += 1
		_respond(c, 401, {"ok": false, "error_code": 401, "description": "Unauthorized"})
		return
	match path.substr(prefix.length()):
		"getUpdates":
			var off := int(body.get("offset", 0))
			var ready := _pending_from(off)
			if not ready.is_empty():
				_respond(c, 200, {"ok": true, "result": ready})
			else:
				c["wait"] = {"offset": off, "until": now + minf(float(body.get("timeout", 0)), hold_cap_s)}
		"sendMessage":
			if fail_sends > 0:
				fail_sends -= 1
				_respond(c, 429, {"ok": false, "error_code": 429, "description": "Too Many Requests: retry after %d" % retry_after, "parameters": {"retry_after": retry_after}})
				return
			_next_msg += 1
			sent.append({"chat_id": str(body.get("chat_id", "")), "text": String(body.get("text", "")), "body": body, "raw": body_text, "message_id": _next_msg})
			_respond(c, 200, {"ok": true, "result": {"message_id": _next_msg, "date": int(Time.get_unix_time_from_system()),
				"chat": {"id": int(str(body.get("chat_id", "0")))}, "text": String(body.get("text", ""))}})
		_:
			_respond(c, 404, {"ok": false, "error_code": 404, "description": "Not Found"})


func _respond(c: Dictionary, code: int, d: Dictionary) -> void:
	var body := JSON.stringify(d).to_utf8_buffer()
	var reason: String = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 429: "Too Many Requests"}.get(code, "Error")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, reason, body.size()]
	var p: StreamPeerTCP = c["peer"]
	var out := head.to_utf8_buffer()
	out.append_array(body)
	p.put_data(out)
	p.disconnect_from_host()
	_conns.erase(c)
