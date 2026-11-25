extends TestCase
## The chat dock with no network: mentions, ages, speaker
## colours, the dock's states, row opacity, the faces.


func _line(block: int, name: String, text: String, soul: String = "1") -> Dictionary:
	return {"tx": "0x%x" % block, "log_index": 0, "block": block, "name": name, "text": text, "soul": soul, "aura": "", "badge": "", "source": "chain"}


func test_mentions_match_whole_names_only() -> void:
	check(ChatLines.mentions("gm enteh, you up?", "enteh"))
	check(ChatLines.mentions("@Enteh look", "enteh"), "case and @ don't matter")
	check(ChatLines.mentions("ENTEH", "Enteh"))
	check(not ChatLines.mentions("enteher was here", "enteh"), "inside a longer word: no")
	check(not ChatLines.mentions("xenteh", "enteh"))
	check(ChatLines.mentions("x enteh_ no, but enteh! yes", "enteh"), "a later whole match counts")
	check(not ChatLines.mentions("a b c", "a"), "one-letter names never match")
	check(not ChatLines.mentions("anything", ""))
	check(ChatLines.mentions("hi RatKing.", "ratking"))


func test_age_from_blocks() -> void:
	eq(ChatLines.age_text(-1, 100), "—", "unknown block: no age")
	eq(ChatLines.age_text(100, -1), "—")
	eq(ChatLines.age_text(100, 104), "now")
	eq(ChatLines.age_text(100, 100 + 60), "10 min")
	eq(ChatLines.age_text(100, 100 + 8400 / 2), "12 h")
	eq(ChatLines.age_text(27787864, 28136975), "42 d", "the quiet rooms of 2026-11-24 (≈ 349k blocks)")


func test_speaker_colour_is_stable() -> void:
	var a := ChatLines.speaker_color(_line(1, "PulsePunk", "x", "7"))
	eq(ChatLines.speaker_color(_line(2, "pulsepunk", "y", "7")), a, "same name and soul, same colour")
	check(a.v > 0.9 and a.s < 0.5, "light enough to read on black glass")
	check(ChatLines.speaker_color(_line(1, "Zurich", "x", "8")) != a, "another speaker, another hue")


func test_dock_states_are_distinct() -> void:
	var r := "RatKing QING"
	eq(ChatFeedPanel.state_line(false, false, [], -1, true, r, false), "Reading the room's lines from the chain…")
	check(ChatFeedPanel.state_line(false, false, [], -1, true, r, false, false).contains("could not be read: —"), "a failed first read is not 'reading'")
	check(ChatFeedPanel.state_line(true, false, [], 100, false, r, false).begins_with("History unavailable: —"))
	check(ChatFeedPanel.state_line(true, true, [], 100, false, r, false).begins_with("No lines in the scanned range."))
	var ls := [_line(27787864, "PulsePunk", "Anyone home?")]
	var greet := ChatFeedPanel.state_line(true, true, ls, 28136975, true, r, true)
	check(greet.begins_with("You walk into RatKing QING's room."), greet)
	check(greet.contains("quiet for ≈ 42 d"), greet)
	var quiet := ChatFeedPanel.state_line(true, true, ls, 28136975, false, r, true)
	check(quiet.begins_with("Quiet for ≈ 42 d (last line at block 27,787,864)."), quiet)
	check(quiet.ends_with("Wake it: T"))
	check(ChatFeedPanel.state_line(true, true, ls, 28136975, false, r, false).ends_with("Anyone with a LAU can wake it."))
	eq(ChatFeedPanel.state_line(true, true, ls, 27787900, false, r, true), "", "talking: nothing to add")


func test_rows_fade_but_never_vanish() -> void:
	eq(ChatFeedPanel.row_alpha(0, true), 1.0)
	eq(ChatFeedPanel.row_alpha(9, true), 1.0, "a fresh line stays bright")
	check(ChatFeedPanel.row_alpha(0, false) > ChatFeedPanel.row_alpha(3, false), "older is dimmer")
	near(ChatFeedPanel.row_alpha(40, false), 0.55, 0.0001, "the floor")


func test_row_bbcode() -> void:
	var l := _line(5, "Pulse[Punk]", "gm [b]x[/b]")
	l["badge"] = "og"
	var s := ChatFeedPanel.row_bbcode(l, Color("#80c0ff"))
	check(s.begins_with("[b][color=#80c0ff]Pulse[lb]Punk][/color][/b] [color=#64e3a8]✓[/color]"), s)
	check(s.contains("gm [lb]b]x[lb]/b]"), "BBCode in a line is escaped")
	check(ChatFeedPanel.row_bbcode(l, Color.WHITE, true).contains("names you"))


func test_head_icon_stand_in() -> void:
	var img := HeadIcons.disc(Color.RED, 24)
	eq(img.get_width(), 24)
	check(img.get_pixel(12, 12).a > 0.4, "filled in the middle")
	eq(img.get_pixel(0, 0).a, 0.0, "clear in the corner")
	check(HeadIcons.texture("rat") == HeadIcons.texture("rat"), "one texture per kind, kept")
	check(HeadIcons.texture("no-such-kind") == HeadIcons.texture("bear"), "unknown kinds draw a bear (AvatarHeads' default)")
