extends SceneTree
## Compiles every .gd in the project with the autoloads present (unlike
## per-script --check-only, which can't see autoload singletons).
##   godot --headless --path . -s res://tools/compile_check.gd
## Exit code 0 = every script compiled.

const ROOTS := ["res://scripts", "res://scenes", "res://addons", "res://tests", "res://tools"]


func _initialize() -> void:
	var files: PackedStringArray = []
	for r in ROOTS:
		_collect(r, files)
	var bad := 0
	for f in files:
		if f == get_script().resource_path:
			continue  # re-loading the running main-loop script deadlocks
		if OS.get_environment("COMPILE_CHECK_VERBOSE") != "":
			printerr("load ", f)
		var s = ResourceLoader.load(f, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
		if not (s is GDScript) or not s.can_instantiate():
			bad += 1
			print("FAIL ", f)
	# Shaders: assigning code runs the preprocessor + compiler; errors print as
	# "SHADER ERROR", which tools/check.sh turns into a failure.
	var shaders := 0
	for f in DirAccess.get_files_at("res://assets/shaders"):
		if f.ends_with(".gdshader"):
			var sh := Shader.new()
			sh.code = FileAccess.get_file_as_string("res://assets/shaders/" + f)
			sh.get_shader_uniform_list()  # compilation is lazy; this forces it
			shaders += 1
	print("%d scripts, %d failed to compile; %d shaders checked" % [files.size(), bad, shaders])
	quit(1 if bad > 0 else 0)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	for sub in d.get_directories():
		_collect(dir_path + "/" + sub, out)
