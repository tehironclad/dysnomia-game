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
	eq(Config.decide(2, 40.0, 9.0, 6.0, false), 2, "fine as it is (dynamic resolution still has room)")
	eq(Config.decide(2, 40.0, 9.0, 6.0, false, 60.0, true), 1, "the render scale at its floor and under 3/4 of the target: down")
	eq(Config.decide(2, 28.0, 30.0, 6.0, false, 30.0, true), 2, "a 30 fps target held: stays")
	eq(Config.decide(1, 60.0, 3.0, 4.0, false, 60.0, false, false), 1, "no step up while the render scale is below its top")
	eq(Config.decide(3, 60.0, 2.0, 3.0, false, 60.0, false, true, 4), 4, "Ultra only where calibration allowed it (top 4)")


func test_recommend_classes() -> void:
	# The starting guesses for the hardware classes in docs/BUILDING.md (calibration measures from there).
	var r := _rec(1, "Intel(R) HD Graphics 630", 8, 56.0)
	eq([r["quality"], r["renderer"]], [0, "gl_compatibility"], "HD 630 laptop: Potato, Compatibility")
	eq(_rec(1, "Mesa Intel(R) UHD Graphics 620 (KBL GT2)", 8, 16.0)["quality"], 0, "Linux Mesa HD/UHD: Potato")
	eq(_rec(1, "AMD Radeon 780M")["quality"], 2, "RDNA3 APU: Medium")
	eq(_rec(1, "AMD Radeon(TM) Vega 8 Graphics")["quality"], 1, "Vega APU: Low")
	eq(_rec(2, "Quadro M1200")["quality"], 1, "Maxwell Quadro laptop: Low")
	eq(_rec(2, "NVIDIA GeForce GTX 1060 6GB")["quality"], 2, "GTX 10x0: Medium")
	eq(_rec(2, "AMD Radeon RX 5700 XT")["quality"], 2, "RX 5000: Medium")
	eq(_rec(2, "AMD Radeon RX 7800 XT")["quality"], 3, "RX 7800: High")
	eq(_rec(1, "Apple M4")["quality"], 2, "Apple M base: Medium")
	eq(_rec(2, "AMD Radeon Pro 5500M")["quality"], 2, "Intel Mac with Radeon Pro: Medium")


func test_dynamic_scale_holds_the_target() -> void:
	var d := DynamicScale.new()
	d.configure(0.5, 1.0, 1.0, 60.0)
	var changed := false
	for i in 200:  # the GPU takes 25 ms a frame at full scale: too slow for 60
		if d.feed(1.0 / 40.0, 25.0, 25.0 * d.scale * d.scale):
			changed = true
	check(changed and d.scale < 1.0, "lowers the scale (%.2f)" % d.scale)
	check(d.scale >= 0.75 and d.scale <= 0.85, "settles near √(16.7/25) ≈ 0.82 (%.2f)" % d.scale)
	var low := d.scale
	for i in 400:  # now cheap: 6 ms at full scale
		d.feed(1.0 / 60.0, 16.7, 6.0 * d.scale * d.scale)
	check(d.scale > low and d.at_max(), "raises back to the top with headroom (%.2f)" % d.scale)
	d.configure(0.5, 1.0, 1.0, 60.0)
	for i in 200:  # CPU-bound: slow frames, idle GPU
		d.feed(1.0 / 30.0, 33.0, 5.0)
	eq(d.scale, 1.0, "a CPU-bound frame keeps the resolution")
	d.configure(0.5, 0.8, 0.6, 60.0)
	for i in 400:  # hopeless: pinned at the floor
		d.feed(1.0 / 20.0, 50.0, 48.0)
	check(d.pinned_low(), "pinned at the floor: the level steps next")
	eq(d.scale, 0.5)


func test_dynamic_scale_without_gpu_timing() -> void:
	var d := DynamicScale.new()  # Compatibility: frame time only, probes upward slowly
	d.configure(0.4, 0.8, 0.6, 30.0)
	for i in 100:
		d.feed(1.0 / 25.0, 40.0, 0.0)
	check(d.scale < 0.6, "slow frames lower it (%.2f)" % d.scale)
	var s := d.scale
	for i in 500:  # holding 30 fps exactly (V-Sync can't show headroom)
		d.feed(1.0 / 30.0, 33.3, 0.0)
	check(d.scale > s, "a held target probes upward (%.2f)" % d.scale)


func test_render_scale_follows_window_pixels() -> void:
	eq(DynamicScale.for_window(0.5, 0.55, Vector2i(1920, 1080)), 0.5, "Potato at 1080p: its own 50 %")
	eq(DynamicScale.for_window(1.0, 3.7, Vector2i(1920, 1080)), 1.0, "High at 1080p: native")
	eq(DynamicScale.for_window(1.0, 3.7, Vector2i(3840, 2160)), 0.65, "High at 4K: ≈ 1440p of work")
	eq(DynamicScale.for_window(0.8, 2.1, Vector2i(2880, 1800)), 0.65, "Medium on a Retina MacBook: ≈ 1080p of work")


func test_calibration_decisions() -> void:
	var t := 1000.0 / 60.0
	eq(GraphicsCalibration.next(2, 30.0, {2: 30.0}, t), {"done": false, "level": 1}, "too slow: measure one level down")
	eq(GraphicsCalibration.next(1, 12.0, {2: 30.0, 1: 12.0}, t), {"done": true, "level": 1}, "fits, and the level above failed: done")
	eq(GraphicsCalibration.next(2, 6.0, {2: 6.0}, t), {"done": false, "level": 3}, "lots of headroom: try one up")
	eq(GraphicsCalibration.next(3, 12.0, {2: 6.0, 3: 12.0}, t), {"done": true, "level": 3}, "High fits: done (no Ultra without big headroom)")
	eq(GraphicsCalibration.next(3, 5.0, {2: 3.0, 3: 5.0}, t), {"done": false, "level": 4}, "High under 40 %: Ultra gets measured")
	eq(GraphicsCalibration.next(3, 5.0, {3: 5.0}, t, 3), {"done": true, "level": 3}, "performance mode / top 3: no Ultra")
	eq(GraphicsCalibration.next(0, 40.0, {1: 45.0, 0: 40.0}, t), {"done": true, "level": 0}, "Potato is the floor")
	eq(GraphicsCalibration.target_fps_for(0, {0: 40.0}, t), 30, "even Potato misses 60: hold 30")
	eq(GraphicsCalibration.target_fps_for(0, {0: 12.0}, t), 60, "Potato at 60: keep 60")
	eq(GraphicsCalibration.better_renderer({"gl_compatibility": {"level": 0, "cost_ms": 30.0}}), "", "one renderer: nothing to compare")
	eq(GraphicsCalibration.better_renderer({"gl_compatibility": {"level": 0, "cost_ms": 30.0}, "forward_plus": {"level": 0, "cost_ms": 22.0}}), "forward_plus", "same level: the cheaper frame")
	eq(GraphicsCalibration.better_renderer({"gl_compatibility": {"level": 1, "cost_ms": 15.0}, "forward_plus": {"level": 0, "cost_ms": 9.0}}), "gl_compatibility", "the higher level wins")
	var steps := 0
	var lv := 2
	var res := {}
	var n := {"done": false, "level": lv}
	while not bool(n["done"]) and steps < 10:  # a machine where every level costs 50 ms: walks down, stops at Potato
		lv = int(n["level"])
		res[lv] = 50.0
		n = GraphicsCalibration.next(lv, 50.0, res, t)
		steps += 1
	eq([n["level"], steps], [0, 3], "walks down to Potato in three measurements")


func test_hybrid_hint() -> void:
	check(Config.hybrid_hint_for("Intel(R) HD Graphics 630", ["Intel(R) HD Graphics 630", "NVIDIA Quadro M1200"]).contains("NVIDIA Quadro M1200"), "an Optimus laptop on its iGPU: names the dedicated one")
	eq(Config.hybrid_hint_for("NVIDIA Quadro M1200", ["Intel(R) HD Graphics 630", "NVIDIA Quadro M1200"]), "", "already on the dedicated GPU")
	eq(Config.hybrid_hint_for("Intel(R) HD Graphics 630", ["Intel(R) HD Graphics 630"]), "", "an iGPU-only laptop: nothing to say")


func test_relaunch_args() -> void:
	# An exported game aborts on --path ("compiled without support for path overrides"):
	# the 0.9.0 release closed itself on first launch. Only the editor binary gets it.
	eq(Config.relaunch_args("gl_compatibility", true, "/p/"), ["--rendering-method", "gl_compatibility"], "exported: no --path")
	eq(Config.relaunch_args("mobile", false, "/p/"), ["--path", "/p/", "--rendering-method", "mobile"], "from the project: --path")
