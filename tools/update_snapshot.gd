extends SceneTree
## Refreshes the shipped territory snapshot from the chain:
##   godot --headless --path . -s res://tools/update_snapshot.gd
## Starts from res://assets/data/territories.json, catches up on MAP NewQing logs,
## reads new territories' fields, resolves every record's raw Compliment words,
## and writes the result back to res://assets/data/territories.json.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry = root.get_node_or_null("Registry")
	if registry == null:
		push_error("Registry autoload not available")
		quit(2)
		return
	print("snapshot: %d territories, cursor block %d" % [registry.count(), registry.cursor_block])
	var ok: bool = await registry.catch_up()
	var missing := 0
	for q in registry.all():
		if String(q.get("lon_word", "")).is_empty():
			missing += 1
	print("after catch-up: %d territories, cursor %d, missing words %d, ok=%s %s" % [
		registry.count(), registry.cursor_block, missing, ok, registry.last_error])
	if ok and missing == 0:
		registry.save_cache(ProjectSettings.globalize_path("res://assets/data/territories.json"))
		print("wrote res://assets/data/territories.json")
	quit(0 if ok and missing == 0 else 1)
