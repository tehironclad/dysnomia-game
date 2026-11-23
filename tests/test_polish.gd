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


func _ps(lau: String, yue: String, name: String) -> PlayerState:
	var ps := PlayerState.new()
	ps.ok = true
	ps.wallet = "0x18f621662d6a1f23700ea32d146b32195dc33111"
	ps.lau = lau
	ps.yue = yue
	ps.username = name
	return ps


func test_acts_follow_the_chain() -> void:
	var none := Acts.evaluate(null, null, {}, {})
	for k in none:
		check(not none[k], "%s done with nothing read" % k)
	eq(Acts.current(none), "arrive")
	var lau := "0xcce83cff8b531eaddcf11ab414c59dc046d1aac7"
	var yue := "0x59b1053f656ed839d3cd9587b6364cd7e86207dd"
	var rd := Readiness.new()
	rd.state = "not-ready"
	rd.holdings = {"fomalhaute": {"verdict": "ok"}, "fornax": {"verdict": "wrong-place"}, "tethys": {"verdict": "ok"}, "qzu": {"verdict": "thin"}}
	var d := Acts.evaluate(_ps(lau, yue, "enteh"), rd, {"0xq": []}, {"arrived": true})
	for k in ["arrive", "forge", "bind", "name", "wake", "play", "first_su"]:
		check(d[k], "%s should be done" % k)
	check(not d["gather"], "Fornax in the wrong place fails the four")
	check(not d["first_beat"] and not d["range"])
	eq(Acts.current(d), "open_door")
	rd.state = "blocked"
	check(not Acts.evaluate(_ps(lau, yue, "x"), rd, {}, {})["play"], "ZeroHoldings means Play is not done")
	rd.state = "ready"
	rd.holdings["fornax"] = {"verdict": "ok"}
	rd.beat = {"dione": "0x0", "charge": "0x0", "deimos": "0x0", "yeo": "0x4a"}
	var r := Acts.evaluate(_ps(lau, yue, "x"), rd, {}, {})
	check(r["gather"] and r["first_beat"] and r["range"])
	check(not r["first_code"], "WORLD acts stay locked")
	rd.beat["yeo"] = "0x0"
	check(not Acts.evaluate(_ps(lau, yue, "x"), rd, {}, {})["range"], "Yeo 0 is not range")
