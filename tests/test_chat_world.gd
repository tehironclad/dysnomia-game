extends TestCase
## The room in the world with no network: the Steward's words about the Room, the speech bubble, the skyline's name tags.


func _line(block: int, name: String, text: String, soul: String = "1") -> Dictionary:
	return {"tx": "0x%x" % block, "log_index": 0, "block": block, "name": name, "text": text, "soul": soul, "aura": "", "badge": "", "source": "chain"}


func test_steward_speaks_of_the_room() -> void:
	var w := ActLoop.room_words(false, false, [], -1)
	check(w[0].contains("THE ROOM"), "the Room comes first")
	check(w[2].contains("still being read"), "loading is said, not zero")
	w = ActLoop.room_words(true, true, [], 100)
	check(w[2].contains("first word is still yours"))
	check(ActLoop.room_words(true, false, [], 100)[2].contains("—"), "unavailable is a dash")
	w = ActLoop.room_words(true, true, [_line(27787864, "PulsePunk", "Anyone home?")], 28136975)
	check(w[2].contains("≈ 42 d ago (block 27,787,864), PulsePunk: \"Anyone home?\""), w[2])
	var say := ChatLines.say_line("0xabc", "x", "free", 1)
	w = ActLoop.room_words(true, true, [_line(100, "A", "chain"), say], 104)
	check(w[2].contains("just now") and w[2].contains("A: \"chain\""), "say lines are not the room's last word")


func test_bubble_parts() -> void:
	var b := ChatLife.make_bubble(_line(28136975, "PulsePunk", "Anyone home?"))
	for n in ["Plate", "Edge", "Tail", "Name", "Line"]:
		check(b.get_node_or_null(n) != null, "bubble has %s" % n)
	check((b.get_node("Name") as Label3D).text.contains("block 28,136,975"), "a chain line carries its block")
	check((b.get_node("Line") as Label3D).position.y < (b.get_node("Name") as Label3D).position.y, "name above the line")
	var say := ChatLife.make_bubble(ChatLines.say_line("0xabc", "Rat", "free", 1))
	check((say.get_node("Name") as Label3D).text.contains("say · not on chain"))
	b.free()
	say.free()


func test_tower_tags_carry_numbers_only_on_the_podium() -> void:
	var hb := BigInt.from_decimal("75304524")
	var w := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	check(BarColumns.tower_label(0, w, hb, false).contains("Hypobar"), "#1 says its Hypobar")
	check(BarColumns.tower_label(2, w, hb, false).contains("floor"), "#3 too")
	eq(BarColumns.tower_label(6, w, hb, false), "#7 %s" % BarColumns.short(w), "the rest: rank and name only")
	check(BarColumns.tower_label(6, w, hb, true).ends_with("\nYOU"), "your own tower always says its numbers")


func test_room_tag_over_the_door() -> void:
	eq(ChatLife.room_tag(false, {}, [], -1), "THE ROOM", "not read yet: no count")
	eq(ChatLife.room_tag(true, {"count": 0}, [], 100), "THE ROOM · SILENT")
	eq(ChatLife.room_tag(true, {"count": 3, "floor": true}, [], 100), "THE ROOM · 3+ LINES TODAY")
	eq(ChatLife.room_tag(true, {"count": 1}, [], 100), "THE ROOM · 1 LINE TODAY")
	eq(ChatLife.room_tag(true, {"count": 0}, [_line(27787864, "P", "x")], 28136975), "THE ROOM · QUIET 42 D")


func test_hall_board_states_and_lines() -> void:
	var hall = load("res://scripts/places/qing_hall.gd")
	check(hall.board_bbcode([], false, false, -1).contains("Reading"), "loading")
	check(hall.board_bbcode([], true, false, 100).contains("—"), "unavailable")
	check(hall.board_bbcode([], true, true, 100).contains("No lines in this room yet"), "empty")
	var b: String = hall.board_bbcode([_line(27787864, "PulsePunk", "Anyone home, enteh?")], true, true, 28136975, "enteh")
	check(b.contains("PulsePunk") and b.contains("42 d · 27,787,864"), b)
	check(b.contains("[color=#ffd27a]Anyone home, enteh?"), "a line naming you is gold")
