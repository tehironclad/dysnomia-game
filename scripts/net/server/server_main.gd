extends Node
## Entry point of the headless game server (docs/SERVER.md):
##   godot --headless --path . res://scenes/net/game_server.tscn -- [--port=8787] [--name=…]
## or   godot --headless --path . -- --server [--port=8787]   (the Net autoload switches here)
## Options: --port=N  --bind=127.0.0.1  --name=<shown in the login message>
##          --max-players=200  --room-cap=64  --voice-radius=40  --data=user://server  --quiet

var server: GameServer


func _ready() -> void:
	Engine.max_fps = 60  # headless would otherwise spin a whole core
	server = GameServer.new()
	server.name = "GameServer"
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"port": server.port = clampi(int(v), 1, 65535)
			"bind": server.bind_address = v
			"name": server.server_name = NetProto.clean_text(v, 40)
			"max-players": server.max_connections = clampi(int(v), 1, 2000)
			"room-cap": server.room_cap = clampi(int(v), 2, 255)
			"voice-radius": server.voice_radius = clampf(float(v), 5.0, 500.0)
			"data": server.data_dir = v
			"quiet": server.quiet = true
	add_child(server)
	if not server.start():
		get_tree().quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if server and is_instance_valid(server):
			server.stop()
