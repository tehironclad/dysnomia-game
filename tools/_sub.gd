extends SceneTree
var f := 0
func _initialize():
	var path := OS.get_cmdline_user_args()[0]
	var n: Node = load(path).instantiate()
	root.add_child.call_deferred(n)
	var c := Camera3D.new(); root.add_child.call_deferred(c)
func _process(_d):
	f += 1
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/sub.png"); print("ok"); quit()
	return false
