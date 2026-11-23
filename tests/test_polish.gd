extends TestCase
## Phase 7: controls come from the input map, sound is deterministic and
## loops seamlessly, settings presets are complete. No network.


func test_every_listed_control_is_bound() -> void:
	for a in ControlsHelp.ACTIONS:
		check(InputMap.has_action(a[0]), "missing action %s" % a[0])
		check(ControlsHelp.key_of(a[0]) != "—", "unbound action %s" % a[0])
	eq(ControlsHelp.key_of("interact"), "E")
	eq(ControlsHelp.key_of("open_field"), "M")


func test_score_voices_are_deterministic_and_loop() -> void:
	var q := Registry.get_territory("0xd127839b83cbf537c29b7d268c135f745a0da2e8")
	var p := DeepField.for_territory(q)
	var v1 := TerritoryScore.voices(p, String(q["entropy"]))
	var v2 := TerritoryScore.voices(p, String(q["entropy"]))
	eq(v1.size(), 4)
	for i in v1.size():
		eq(v1[i]["freq"], v2[i]["freq"])
		var cycles: float = float(v1[i]["freq"]) * TerritoryScore.LOOP_S
		near(cycles, roundf(cycles), 1e-6, "whole cycles per loop")
		var breaths: float = float(v1[i]["lfo"]) * TerritoryScore.LOOP_S
		near(breaths, roundf(breaths), 1e-6, "whole breaths per loop")
	check(float(v1[0]["freq"]) >= 55.0 and float(v1[0]["freq"]) < 220.0, "root within two octaves of A1 (Entropy mod 24 semitones)")


func test_score_render_shape() -> void:
	var w := TerritoryScore.render([{"freq": 110.0, "amp": 0.3, "lfo": 0.125, "phase": 0.0}])
	eq(w.data.size(), int(TerritoryScore.RATE * TerritoryScore.LOOP_S) * 2)
	eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD)


func test_cues_render() -> void:
	for c in Cues.DEFS:
		check(Cues.stream(c).data.size() > 1000, "cue %s" % c)


func test_quality_presets_complete() -> void:
	eq(Config.QUALITY_PRESETS.size(), Config.QUALITY_NAMES.size())
	for p in Config.QUALITY_PRESETS:
		for k in ["ssao", "ssil", "glow", "volumetric_fog", "shadow_distance", "msaa"]:
			check(p.has(k), "preset key %s" % k)
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "audio buses exist")
