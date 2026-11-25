class_name HudLayout
extends RefCounted
## The HUD's grid, in design pixels (1920x1080; the window scales the canvas).
## Each corner has one job and keeps it in every scene:
##   top-left      WHERE YOU ARE: the territory card and its few facts; under
##                 it, WHO IS AROUND: the activity feed (ActivityFeed: online
##                 players' actions, a few fading lines, K folds it)
##   top-right     WHO YOU ARE: your face and name, the notification slot
##                 (NOTIFY_SLOT, at the very corner), the block clock; under
##                 it, WHAT TO DO HERE: the act tracker
##   bottom-left   THE ROOM: the QING's chat dock (and the bar, T)
##   bottom-right  THE KEYS: what the main keys do
## The middle stays the world's: the wallet chip and the ticker top-centre,
## celebrations under them, the prompt bottom-centre.

const MARGIN := DeepFieldTheme.MARGIN  # 24: from every screen edge
const GAP := 12  # between blocks in a column
const COL_W := 460  # the left and right columns
const DOCK_W := 540  # ChatFeedPanel.WIDTH
const DOCK_BOTTOM := 64  # the dock's bottom edge above the screen's (the key row is under it)
const KEYS_H := 32
const PROMPT_BOTTOM := 150
const TICKER_TOP := 64  # under the wallet chip
const TICKER_W := 760
const TICKER_ROWS := 3
const BANNER_TOP := 200
const NOTIFY_SLOT := "NotifySlot"

## How tall each block may grow before it would run into its neighbour.
const LEFT_MAX_H := 330  # the territory card
const ACTIVITY_MAX_H := 250  # the activity feed: a header and NetEvents.FEED_MAX lines
const RIGHT_MAX_H := 620
const DOCK_MAX_H := 380


## Pure: each block's rectangle on a `view`-sized canvas (for tests and tools).
static func slots(view: Vector2 = Vector2(1920, 1080)) -> Dictionary:
	var w := view.x
	var h := view.y
	return {
		"where": Rect2(MARGIN, MARGIN, COL_W, LEFT_MAX_H),
		"activity": Rect2(MARGIN, MARGIN + LEFT_MAX_H + GAP, COL_W, ACTIVITY_MAX_H),
		"who": Rect2(w - MARGIN - COL_W, MARGIN, COL_W, RIGHT_MAX_H),
		"ticker": Rect2((w - TICKER_W) * 0.5, TICKER_TOP, TICKER_W, 30.0 * TICKER_ROWS),
		"banner": Rect2((w - TICKER_W) * 0.5, BANNER_TOP, TICKER_W, 120),
		"room": Rect2(MARGIN, h - DOCK_BOTTOM - DOCK_MAX_H, DOCK_W, DOCK_MAX_H),
		"prompt": Rect2((w - TICKER_W) * 0.5, h - PROMPT_BOTTOM - 52, TICKER_W, 52),
		"keys": Rect2(w - MARGIN - 880, h - MARGIN - KEYS_H, 880, KEYS_H),
	}
