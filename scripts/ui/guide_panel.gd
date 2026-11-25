class_name GuidePanel
extends PanelContainer
## The Guide (WP 7.1): the acts, ticked only by chain predicates (or a local
## flag set after a chain-verified event). The current level is expanded with
## its codex entry: the call it is about, then plain words, then where to do it.

var _list: RichTextLabel


func _init() -> void:
	theme = DeepFieldTheme.get_theme()
	var sb := DeepFieldTheme.panel_style()
	sb.bg_color.a = 0.94
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(520, 0)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	add_child(col)
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = "GUIDE · the acts"
	col.add_child(title)
	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.fit_content = true
	_list.scroll_active = false
	_list.custom_minimum_size = Vector2(500, 0)
	_list.add_theme_font_override("normal_font", DeepFieldTheme.body_font())
	_list.add_theme_font_override("mono_font", DeepFieldTheme.mono_font())
	_list.add_theme_font_size_override("normal_font_size", DeepFieldTheme.FS_CAPTION)
	_list.add_theme_font_size_override("mono_font_size", DeepFieldTheme.FS_CAPTION)
	col.add_child(_list)


func _ready() -> void:
	Session.changed.connect(refresh)


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if not visible:
		return
	var flags := Acts.flags_for(Session.wallet)
	var done := Acts.evaluate(Session.player, Session.readiness, Session.bars, flags, Session.forged_lau != "")
	var cur := Acts.current(done)
	var act := ""
	var t := ""
	if Session.wallet == "":
		t += "[color=#ffd27a]No wallet connected: only the Prologue can be checked.[/color]\n"
	for l in Acts.LEVELS:
		if l["act"] != act:
			act = l["act"]
			t += "\n[color=#8e97a9]%s[/color]\n" % act.to_upper()
		var ok: bool = done.get(l["key"], false)
		var mark := "[color=#64e3a8]✓[/color]" if ok else ("[color=#a8e6ff]▸[/color]" if l["key"] == cur else "[color=#5d6578]○[/color]")
		t += "%s  %s\n" % [mark, l["title"] if l["key"] != cur else "[b]%s[/b]" % l["title"]]
		if l["key"] == cur:
			if l["code"] != "—":
				t += "    [code]%s[/code]\n" % l["code"]
			t += "    %s\n    [color=#8e97a9]%s[/color]\n" % [l["plain"], l["how"]]
	_list.text = t
