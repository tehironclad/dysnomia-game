extends Control
## The front door (WP 3.3/4.x). Behind it, one real territory's Julia set,
## diving slowly. Choices: the Field, a territory, your wallet/identity, the
## Void (onboarding), settings. Plain for newcomers; everything is one click.

const SETTINGS := preload("res://scripts/ui/settings_menu.gd")

var _bg: DeepFieldView
var _search: LineEdit
var _status: Label
var _wallet_btn: Button
var _card: IdentityCard
var _onboarding: OnboardingPanel
var _guide: GuidePanel
var _opps: OpportunitiesPanel
var _settings: PanelContainer
var _bg_q: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	theme = DeepFieldTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = DeepFieldView.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.modulate = Color(1, 1, 1, 0.55)
	add_child(_bg)
	var all: Array = Registry.all()
	if not all.is_empty():
		_bg_q = all[randi() % all.size()]
		_bg.apply_params(DeepField.for_territory(_bg_q))
	var left := VBoxContainer.new()
	left.position = Vector2(56, 56)
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 44)
	title.text = "DYSNOMIA"
	left.add_child(title)
	var lede := Label.new()
	lede.theme_type_variation = "MutedLabel"
	lede.add_theme_font_size_override("font_size", 15)
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.text = "A viewport onto a living on-chain organism. Every territory is computed from its own numbers; every change you see was made by a real transaction."
	left.add_child(lede)
	var field := Button.new()
	field.text = "ENTER THE FIELD  ·  %d territories" % Registry.count()
	field.custom_minimum_size = Vector2(0, 44)
	field.pressed.connect(func(): Travel.field(get_tree()))
	left.add_child(field)
	var row := HBoxContainer.new()
	left.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "a territory: name, symbol, #n or 0x…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _go())
	row.add_child(_search)
	var go := Button.new()
	go.text = "Warp"
	go.pressed.connect(_go)
	row.add_child(go)
	var rnd := Button.new()
	rnd.text = "Random"
	rnd.pressed.connect(func(): Warp.to(get_tree(), Travel.random_address(get_tree())))
	row.add_child(rnd)
	_wallet_btn = Button.new()
	_wallet_btn.pressed.connect(_toggle_wallet)
	left.add_child(_wallet_btn)
	var void_btn := Button.new()
	void_btn.text = "ENTER THE VOID  ·  create your identity"
	void_btn.pressed.connect(func(): _onboarding.visible = not _onboarding.visible)
	left.add_child(void_btn)
	var opp_btn := Button.new()
	opp_btn.text = "OPPORTUNITIES · what pays now"
	opp_btn.pressed.connect(func(): _opps.toggle())
	left.add_child(opp_btn)
	var guide_btn := Button.new()
	guide_btn.text = "Guide · the acts"
	guide_btn.pressed.connect(func(): _guide.toggle())
	left.add_child(guide_btn)
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_toggle_settings)
	left.add_child(settings_btn)
	_status = Label.new()
	_status.theme_type_variation = "MonoLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-600, 56)
	right.custom_minimum_size = Vector2(540, 0)
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	_card = IdentityCard.new()
	right.add_child(_card)
	_onboarding = OnboardingPanel.new()
	_onboarding.visible = false
	right.add_child(_onboarding)
	_guide = GuidePanel.new()
	right.add_child(_guide)
	_opps = OpportunitiesPanel.new()
	right.add_child(_opps)
	Session.lead_changed.connect(func(lost, gained, block):
		var parts: PackedStringArray = []
		for a in lost:
			parts.append("lost the lead at %s" % String(Registry.get_territory(a).get("name", a)))
		for a in gained:
			parts.append("took the lead at %s" % String(Registry.get_territory(a).get("name", a)))
		_status.text = "Since you were last here (block %d): %s." % [block, "; ".join(parts)])
	var caption := Label.new()
	caption.theme_type_variation = "MutedLabel"
	caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	caption.position = Vector2(56, -40)
	caption.text = "Behind: %s, the Julia set of its Entropy and address." % String(_bg_q.get("name", "")) if not _bg_q.is_empty() else ""
	add_child(caption)
	Session.changed.connect(_update_wallet_button)
	Wallet.connected.connect(func(_a): _status.text = "")
	_update_wallet_button()
	if not Registry.catching_up:
		Registry.catch_up()
	World.start()


func _go() -> void:
	var addr := Travel.resolve(get_tree(), _search.text)
	if addr == "":
		_status.text = "No territory matches \"%s\"." % _search.text
		return
	Warp.to(get_tree(), addr)


func _toggle_wallet() -> void:
	if Session.wallet != "":
		Wallet.disconnect_wallet()
	elif Wallet.connect_wallet():
		_status.text = "A wallet window opened in your browser. Approve the connection there."
	else:
		_status.text = "Could not start the local wallet relay (ports %d+ busy?)." % Config.wallet_bridge_port


func _update_wallet_button() -> void:
	_wallet_btn.text = "Disconnect %s…%s" % [Session.wallet.left(6), Session.wallet.right(4)] if Session.wallet != "" else "CONNECT WALLET"


func _toggle_settings() -> void:
	if _settings == null:
		_settings = PanelContainer.new()
		_settings.set_script(SETTINGS)
		_settings.visible = false
		add_child(_settings)
		_settings.settings_closed.connect(func(): _settings.hide_menu())
	if _settings.visible:
		_settings.hide_menu()
	else:
		_settings.show_menu()


func _process(delta: float) -> void:
	if _bg_q.is_empty():
		return
	_t += delta
	var p: Dictionary = _bg.params
	_bg.set_view(Vector2.ZERO, float(p["extent"]) * (1.0 + 0.08 * sin(_t * 0.07)), float(p["rotation"]) + _t * 0.01)
