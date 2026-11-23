extends SceneTree
## Headless runtime check: load a real territory from the chain (read-only),
## enter the world scene, run a few hundred frames, report HUD card state.
##   godot --headless --path . -s res://tools/boot_territory.gd [-- --qing=0x…]

var _qing := "0xd127839b83cbf537c29b7d268c135f745a0da2e8"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qing="):
			_qing = a.substr(7)
	_run.call_deferred()


func _run() -> void:
	print("territory load: ok=%s err=" % root.get_node("Registry").has_territory(_qing))
	Travel.go(self, _qing)
	for i in 300:
		await process_frame
	var card = _find(root, "TerritoryCard")
	if card == null:
		print("FAIL no TerritoryCard in the HUD")
		quit(1)
		return
	print("card: %s | %s | entropy %s | map %s" % [card._name.text, card._rarity.text, card._entropy.text, card._coords.text])
	print("inspector entries: %s" % str(root.get_node("Inspector").visible_entries().map(func(e): return e["title"])))
	quit(0)


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null
