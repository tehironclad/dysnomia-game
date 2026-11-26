class_name Shares
extends RefCounted
## Config.crowd() / Config.particles() for classes that -s tools compile before the autoloads
## exist (naming `Config` there is a compile error, which broke tools/probe_bump.gd through
## AvatarExtras, FairFx and FairKit; audit 2026-11-25). Without the autoload: the full count.


static func crowd(n: int, floor_n: int = 0) -> int:
	var c := _config()
	return c.crowd(n, floor_n) if c else maxi(floor_n, n)


static func particles(n: int) -> int:
	var c := _config()
	return c.particles(n) if c else maxi(1, n)


static func _config() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Config") if tree and tree.root else null
