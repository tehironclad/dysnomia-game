extends TestCase
## Sunny's voice hook (VoiceLines: ids, words, where recordings go, the README in step) and the
## pour at the bar (PourScene's timeline; the menu out of the way while an order is out). No network.


func test_sunny_lines() -> void:
	var ids := VoiceLines.ids("sunny")
	for want in ["greeting", "order_taken", "pour", "here_you_go", "cheers", "payment_waiting", "payment_failed", "goodbye"]:
		check(want in ids, "Sunny has a %s line" % want)
	for id in ids:
		check(VoiceLines.text("sunny", id) != "", id + " has words")
		check(not VoiceLines.text("sunny", id).contains("%"), id + ": no numbers or blanks in a recorded line")
	for id in VoiceLines.IDLE_SUNNY:
		check(id in ids, "idle bark %s is a line" % id)
	eq(VoiceLines.text("sunny", "no_such_line"), "", "unknown line: no words")
	eq(VoiceLines.text("nobody", "greeting"), "", "unknown speaker")


func test_recording_paths() -> void:
	var c := VoiceLines.candidates("sunny", "cheers")
	eq(c[0], "res://assets/audio/voices/sunny/cheers.ogg", "ogg first")
	check("res://assets/audio/voices/sunny/cheers.wav" in c and "res://assets/audio/voices/sunny/cheers.mp3" in c, "wav and mp3 too")


func test_no_recording_means_subtitle_only() -> void:
	VoiceLines.rescan()
	var r := VoiceLines.say(null, "sunny", "here_you_go", "· Alpha Sour · block 1")
	check(String(r["text"]).begins_with(VoiceLines.text("sunny", "here_you_go")), "the subtitle is the line's words")
	check(String(r["text"]).ends_with("· block 1"), "then the measured detail")
	check(float(r["seconds"]) >= 2.5, "long enough to read")
	if VoiceLines.stream("sunny", "here_you_go") == null:
		check(not r["voiced"], "no file: not voiced (no synthesised voice)")
	check(VoiceLines.reading_seconds("a b c d e f g h i j k l m n o p q r s t u v w x y z") <= 9.0, "capped")


func test_readme_lists_every_line() -> void:
	var f := FileAccess.open("res://assets/audio/voices/sunny/README.md", FileAccess.READ)
	check(f != null, "the README is there")
	if f == null:
		return
	var md := f.get_as_text()
	for id in VoiceLines.ids("sunny"):
		check(md.contains("`%s.ogg`" % id), "README names %s.ogg" % id)
		check(md.contains(VoiceLines.text("sunny", id)), "README has the words for " + id)
	check(md.contains("mono"), "format tips")


func test_pour_timeline() -> void:
	eq(PourScene.shot_at(0.0), "pour")
	var last := -1.0
	var seen: Array = []
	for e in PourScene.SHOTS:
		check(float(e[0]) > last, "shots in order")
		last = float(e[0])
		seen.append(e[1])
		eq(PourScene.shot_at(float(e[0]) + 0.01), e[1], "the shot at %s" % e[0])
		var cam: Array = PourScene.camera_for(String(e[1]), -1.0)
		check(cam.size() == 2 and (cam[0] as Vector3).distance_to(cam[1]) > 0.5, "%s: a camera that looks somewhere" % e[1])
	check(PourScene.T_END > last, "the scene ends after the last shot")
	check(seen.find("pour") < seen.find("drink"), "the pour before the drink")
	eq(PourScene.drink_weight(0.0), 0.0, "not drinking at the start")
	eq(PourScene.drink_weight(PourScene.T_SIP[0]), 0.0)
	eq(PourScene.drink_weight((PourScene.T_SIP[0] + PourScene.T_SIP[1]) * 0.5), 1.0, "glass up mid-drink")
	eq(PourScene.drink_weight(PourScene.T_SIP[1] + 0.1), 0.0, "down after")
	check(PourScene.T_PICK < PourScene.T_SIP[0], "picked up before it's drunk")
	check(PourScene.T_SIP[1] < PourScene.T_END, "drunk before the end")


## The menu's order signals (no wallet: the order is blocked before anything is sent).
func test_bar_menu_hides_only_on_an_order() -> void:
	var m := BarMenu.new()
	check(m.has_signal("order_started") and m.has_signal("order_failed") and m.has_signal("status_changed"), "the pub can follow an order")
	check(not m.is_busy(), "no order out")
	m.free()
