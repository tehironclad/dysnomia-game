extends TestCase
## The HUD grid (HudLayout) and the identity strip, with no network.


func test_hud_corners_do_not_overlap() -> void:
	var s := HudLayout.slots(Vector2(1920, 1080))
	var keys: Array = s.keys()
	for i in keys.size():
		var a: Rect2 = s[keys[i]]
		check(a.position.x >= 0 and a.position.y >= 0 and a.end.x <= 1920 and a.end.y <= 1080, "%s is on screen" % keys[i])
		for j in range(i + 1, keys.size()):
			if [keys[i], keys[j]] in [["ticker", "banner"], ["banner", "ticker"]]:
				continue
			check(not a.intersects(s[keys[j]]), "%s and %s overlap" % [keys[i], keys[j]])
	eq(HudLayout.DOCK_W, int(ChatFeedPanel.WIDTH), "the dock is as wide as its slot")


func test_you_strip_text() -> void:
	eq(HudV2.you_text("", null)["name"], "VISITOR")
	var w := "0x18f621662d6a1f23700ea32d146b32195dc33111"
	eq(HudV2.you_text(w, null), {"name": "0x18f6…3111", "sub": "reading your identity…"})
	var ps := PlayerState.new()
	ps.ok = true
	check(HudV2.you_text(w, ps)["sub"].begins_with("no LAU yet"))


func test_history_opens_between_the_columns() -> void:
	var left := HudLayout.MARGIN + HudLayout.DOCK_W + HudLayout.GAP * 2
	check(left > HudLayout.MARGIN + HudLayout.COL_W, "right of the territory panel")
	check(left + ChatFeedPanel.HISTORY_W <= 1920 - HudLayout.MARGIN - HudLayout.COL_W, "left of the right column: the dock and the tracker stay readable")
