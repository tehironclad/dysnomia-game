extends TestCase
## Automatic graphics: what the hardware asks for, and following the frame
## rate. Levels: 0 Potato, 1 Low, 2 Medium, 3 High, 4 Ultra. No network.


func _rec(t: int, name: String, cores: int = 8, ram: float = 16.0, method: String = "forward_plus") -> Dictionary:
	return Config.recommend(t, name, cores, ram, method)


func test_recommend_by_hardware() -> void:
	var r := _rec(2, "NVIDIA GeForce RTX 2070 SUPER", 16, 32.0)
	eq([r["quality"], r["renderer"]], [3, "forward_plus"], "a strong card: High on the full renderer")
	eq(_rec(2, "NVIDIA GeForce GTX 1050 Ti")["quality"], 2, "a mid card: Medium")
	eq(_rec(2, "NVIDIA GeForce GT 1030")["quality"], 1, "an entry card: Low")
	r = _rec(1, "Intel(R) UHD Graphics 620", 4, 8.0)
	eq([r["quality"], r["renderer"]], [0, "gl_compatibility"], "old Intel graphics: Potato, lightweight renderer")
	eq(_rec(1, "Intel(R) Iris(R) Xe Graphics")["quality"], 1, "a newer iGPU: Low")
	r = _rec(4, "llvmpipe (LLVM 15.0.7, 256 bits)")
	eq([r["quality"], r["renderer"]], [0, "gl_compatibility"], "no GPU at all")
	r = _rec(0, "Microsoft Basic Render Driver")
	eq(r["renderer"], "gl_compatibility", "Windows' fallback driver is software")
	eq(_rec(2, "NVIDIA GeForce RTX 4070", 8, 4.0)["quality"], 1, "little RAM caps the level")
	eq(_rec(1, "Apple M1")["quality"], 2, "Apple silicon: Medium")
	eq(_rec(1, "Apple M2 Pro")["quality"], 3, "Apple Pro/Max: High")
	eq(_rec(1, "Intel(R) Iris(TM) Plus Graphics 655")["quality"], 1, "an Intel Mac: Low")
	check(String(_rec(2, "NVIDIA GeForce RTX 2070 SUPER")["why"]).contains("dedicated GPU"), "the reason names the card")


func test_follow_the_frame_rate() -> void:
	eq(Config.decide(2, 18.0, 30.0, 10.0, false), 1, "stutters: one level down")
	eq(Config.decide(0, 10.0, 30.0, 10.0, false), 0, "never below Potato")
	eq(Config.decide(1, 60.0, 3.0, 4.0, false), 2, "lots of headroom: one level up")
	eq(Config.decide(3, 60.0, 3.0, 4.0, false), 3, "auto stops at High")
	eq(Config.decide(1, 60.0, 3.0, 4.0, true), 1, "no going back up after a step down")
	eq(Config.decide(1, 60.0, 0.0, 4.0, false), 1, "no GPU timing (lightweight renderer): no step up")
	eq(Config.decide(2, 40.0, 9.0, 6.0, false), 2, "fine as it is")


func test_relaunch_args_never_override_the_path_of_an_exported_build() -> void:
	# A release template quits on --path ("compiled without support for path overrides").
	var none := PackedStringArray()
	eq(Config.relaunch_args("gl_compatibility", true, "/x/", none), PackedStringArray(["--rendering-method", "gl_compatibility"]),
		"exported: the renderer only")
	eq(Config.relaunch_args("gl_compatibility", false, "/src/game/", none),
		PackedStringArray(["--path", "/src/game/", "--rendering-method", "gl_compatibility"]), "from source: the project too")
	eq(Config.relaunch_args("forward_plus", true, "/x/", PackedStringArray(["--quality=1"])),
		PackedStringArray(["--rendering-method", "forward_plus", "--", "--quality=1"]), "user args ride along")
