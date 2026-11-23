class_name AttractionDirector
extends Node
## Glue between places you can spend AFFECTION (ride booths, the pub bar), the on-chain
## AffectionEconomy, and the AttractionUI. main.gd creates one and calls register_*().
##
##   booth/bar focus → UI card/menu → E or number key → economy.buy(item)
##   → purchase_pending (wallet prompt, mempool) → purchase_granted → ride.start_ride()
##   → economy.bar_report → "QING BARS" card with measured Hypobar/Epibar change.

signal ride_state_changed(riding: bool)

const BALANCE_REFRESH_SECONDS := 20.0

var _player: CharacterBody3D
var _ui: CanvasLayer
var _pub: Node3D
var _economy: Node

var _focus_ride: RideBase = null
var _at_bar: bool = false
var _active_ride: RideBase = null
var _purchases: Dictionary = {}     # purchase_id -> {"ride": RideBase|null, "item": Dictionary}
var _ride_modes: Dictionary = {}    # RideBase -> grant mode, for the end-of-ride message
var _tx_to_purchase: Dictionary = {}
var _last_balance_read: float = -999.0


func setup(player: CharacterBody3D, ui: CanvasLayer) -> void:
	_player = player
	_ui = ui
	_economy = ChainManager.economy
	_economy.purchase_pending.connect(_on_pending)
	_economy.purchase_granted.connect(_on_granted)
	_economy.purchase_failed.connect(_on_failed)
	_economy.bar_report.connect(_on_bar_report)
	_economy.balance_updated.connect(func(_d: String) -> void: _refresh_open_card())
	ChainManager.tx_sent.connect(_on_tx_sent)
	_ui.drink_chosen.connect(_order_drink)


func register_ride(ride: RideBase) -> void:
	ride.booth_focus.connect(_on_booth_focus)
	ride.ride_caption.connect(func(t: String) -> void: _ui.set_caption(t))
	ride.ride_finished.connect(_on_ride_finished)


func register_pub(pub: Node3D) -> void:
	_pub = pub
	if pub.has_signal("bar_focus"):
		pub.bar_focus.connect(_on_bar_focus)


func is_riding() -> bool:
	return _active_ride != null


# ─── Rides ──────────────────────────────────────────────────────────────

func _on_booth_focus(ride: RideBase, inside: bool) -> void:
	if inside:
		if _active_ride != null:
			return
		_focus_ride = ride
		_maybe_refresh_balance()
		_show_card(ride)
		_player.set_interact_handler(_on_interact)
	elif _focus_ride == ride:
		_focus_ride = null
		_ui.hide_ticket()
		_player.clear_interact_handler(_on_interact)


func _show_card(ride: RideBase) -> void:
	_ui.show_ticket(ride.item, _economy.describe_cost(ride.item), _economy.balance_display, _bars_line())


func _refresh_open_card() -> void:
	if _focus_ride and _ui.is_ticket_visible() and not _has_purchase_for(_focus_ride):
		_show_card(_focus_ride)


func _on_interact() -> void:
	if _focus_ride == null or _active_ride != null:
		return
	if _focus_ride.is_riding() or _has_purchase_for(_focus_ride):
		return
	var pid: int = _economy.buy(_focus_ride.item)
	_purchases[pid] = {"ride": _focus_ride, "item": _focus_ride.item}


func _on_ride_finished(ride: RideBase) -> void:
	if _active_ride != ride:
		return
	_active_ride = null
	ride_state_changed.emit(false)
	var mode: String = _ride_modes.get(ride, "")
	_ride_modes.erase(ride)
	match mode:
		"paid":
			_ui.toast("Thanks for riding! Your AFFECTION went to %s." % _economy.keeper_label(), AttractionUI.ACCENT, 5.0)
		"keeper":
			_ui.toast("Keeper's privilege — rides in your own QING are on the house.", AttractionUI.ACCENT, 4.0)
		"preview":
			_ui.toast("That was a preview ride. Connect a wallet (W) to pay the QING and make it count.", Color(1, 0.9, 0.6), 6.0)


# ─── Bar ────────────────────────────────────────────────────────────────

func _on_bar_focus(inside: bool) -> void:
	_at_bar = inside
	if inside:
		_maybe_refresh_balance()
		var footer := "Press a number to order.  "
		footer += ("Balance %s AFFECTION · %s" % [_economy.balance_display, _bars_line()]) if _economy.wallet_ready() \
			else "Connect a wallet (W) to order — drinks are your own AFFECTION calls."
		_ui.show_bar_menu("%s — Bar" % _economy.keeper_label(), AttractionCatalog.DRINKS, footer)
	else:
		_ui.hide_bar_menu()


func _order_drink(item: Dictionary) -> void:
	if not _at_bar:
		return
	if item.get("kind", "") == AttractionCatalog.KIND_TICKET and not _economy.wallet_ready() and not _economy.is_keeper():
		_ui.set_menu_status("A round for the house needs a wallet — press W to connect.", AttractionUI.BAD)
		return
	var pid: int = _economy.buy(item)
	_purchases[pid] = {"ride": null, "item": item}
	_ui.set_menu_status("Ordering %s…" % item.get("name", ""), AttractionUI.DIM)


# ─── Economy callbacks ──────────────────────────────────────────────────

func _on_pending(pid: int, item: Dictionary, tx_id: int) -> void:
	if not _purchases.has(pid):
		return
	_tx_to_purchase[tx_id] = pid
	var msg := "Approve %s in your wallet window…" % (
		"the %s ticket" % item.get("name", "") if item.get("kind", "") == AttractionCatalog.KIND_TICKET
		else "AFFECTION.%s" % str(item.get("op", "")).capitalize())
	_status_for(pid, msg, AttractionUI.DIM)


func _on_tx_sent(tx_id: int, _hash: String) -> void:
	if not _tx_to_purchase.has(tx_id):
		return
	var pid: int = _tx_to_purchase[tx_id]
	_tx_to_purchase.erase(tx_id)
	var p: Dictionary = _purchases.get(pid, {})
	if p.is_empty():
		return
	var msg := "Ticket broadcast — boarding as soon as the block confirms (~10 s)." if p["ride"] \
		else "Order sent — the bartender pours when the block confirms."
	_status_for(pid, msg, AttractionUI.PULSE)


func _on_granted(pid: int, item: Dictionary, mode: String) -> void:
	if not _purchases.has(pid):
		return
	var p: Dictionary = _purchases[pid]
	_purchases.erase(pid)
	var ride: RideBase = p["ride"]
	if ride:
		if _active_ride != null or ride.is_riding():
			return
		_ui.hide_ticket()
		_player.clear_interact_handler(_on_interact)
		_focus_ride = null
		_active_ride = ride
		_ride_modes[ride] = mode
		ride_state_changed.emit(true)
		ride.start_ride(_player)
		return
	# Bar order
	if item.get("id", "") == "house_round":
		if _pub and _pub.has_method("play_house_cheer"):
			_pub.play_house_cheer()
		_ui.set_menu_status("The whole bar cheers — %s AFFECTION to %s." % [item.get("price", "1"), _economy.keeper_label()], AttractionUI.OK)
	else:
		if _pub and _pub.has_method("play_drink_served"):
			_pub.play_drink_served(str(item.get("id", "")))
		_ui.set_menu_status("%s served. Reading your bars…" % item.get("name", ""), AttractionUI.OK)


func _on_failed(pid: int, _item: Dictionary, error: String) -> void:
	if not _purchases.has(pid):
		return
	_status_for(pid, error, AttractionUI.BAD)
	_purchases.erase(pid)


func _on_bar_report(report: Dictionary) -> void:
	_ui.show_bar_report(report, _economy.keeper_label())


# ─── Helpers ────────────────────────────────────────────────────────────

func _status_for(pid: int, text: String, color: Color) -> void:
	var p: Dictionary = _purchases.get(pid, {})
	if p.get("ride"):
		_ui.set_ticket_status(text, color)
	else:
		_ui.set_menu_status(text, color)


func _has_purchase_for(ride: RideBase) -> bool:
	for p in _purchases.values():
		if p["ride"] == ride:
			return true
	return false


func _bars_line() -> String:
	if not GameManager.has_territory_state:
		return "Your bars here: not read yet"
	return "Your bars here: HYPO %s · EPI %s" % [
		AttractionUI.format_big(GameManager.territory_hypobar),
		AttractionUI.format_big(GameManager.territory_epibar)]


func _maybe_refresh_balance() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_balance_read > BALANCE_REFRESH_SECONDS:
		_last_balance_read = now
		_economy.refresh_balance()
