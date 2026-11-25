class_name DeepFieldTheme
extends RefCounted
## Deep Field UI tokens (docs/LEARNINGS.md §11; the site's lib/styles/deep-field.css).
## Black glass panels with hairline borders, one ice accent, a per-subject hue,
## wide uppercase display type, Inter body, JetBrains Mono for every chain value.

const BLACK := Color("#030407")
const INK := Color("#e9edf4")
const MUTED := Color("#8e97a9")
const DIM := Color("#5d6578")
const ICE := Color("#a8e6ff")
const HAIRLINE := Color(190 / 255.0, 210 / 255.0, 1.0, 0.13)
const HAIRLINE_STRONG := Color(190 / 255.0, 210 / 255.0, 1.0, 0.22)
const PANEL := Color(6 / 255.0, 8 / 255.0, 14 / 255.0, 0.76)
const DEFAULT_HUE := Color("#7fd3ff")

## lib/rarity.js (the convention we use; other site files disagree).
const RARITY := {
	"Common": Color("#9aa6c8"), "Rare": Color("#8fd0ff"), "Epic": Color("#b07bff"),
	"Legendary": Color("#ff8fd0"), "Mythic": Color("#ffd59a"),
}

## Type scale, in design pixels. The project renders at 1920x1080 and the
## window scales the whole canvas (stretch mode canvas_items), so a 1280x720
## screen shows two thirds of these: FS_MIN 19 is ≈ 13 px there. Nothing on the
## HUD goes under FS_MIN; use these instead of loose numbers.
const FS_MIN := 19
const FS_CAPTION := 19  # small caps labels, sources, key hints
const FS_SMALL := 20  # secondary lines, chain values
const FS_BODY := 21  # body text, chat lines
const FS_LEAD := 23  # a line that leads (prompts, a dock header)
const FS_TITLE := 27  # panel titles
const FS_DISPLAY := 36  # banners
## Spacing unit: gaps are 1×, panel padding 2×, screen margins 3×.
const SPACE := 8
const MARGIN := 24

const FONT_DISPLAY_PATH := "res://assets/fonts/Archivo-Variable.ttf"
const FONT_BODY_PATH := "res://assets/fonts/Inter-Variable.ttf"
const FONT_MONO_PATH := "res://assets/fonts/JetBrainsMono-Variable.ttf"

static var _theme: Theme = null


static func _font(path: String, weight: int = 400, width: int = 100) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var base: FontFile = load(path)
	var v := FontVariation.new()
	v.base_font = base
	var coords := {}
	coords[TextServerManager.get_primary_interface().name_to_tag("wght")] = weight
	coords[TextServerManager.get_primary_interface().name_to_tag("wdth")] = width
	v.variation_opentype = coords
	# Territory names use every script on Earth (Javanese, CJK, emoji…):
	# fall back to the system's fonts for glyphs the bundled faces lack.
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Noto Sans", "Noto Sans CJK SC", "Noto Color Emoji", "DejaVu Sans", "sans-serif"])
	v.fallbacks = [sys]
	return v


static func display_font() -> Font:
	return _font(FONT_DISPLAY_PATH, 800, 125)


static func body_font() -> Font:
	return _font(FONT_BODY_PATH, 400)


static func mono_font() -> Font:
	return _font(FONT_MONO_PATH, 400)


## A font size no smaller than the floor (FS_MIN).
static func fs(px: int) -> int:
	return maxi(px, FS_MIN)


## A glass panel tinted by a subject's hue (a QING's emblem colour): a hairline
## in the hue, a stronger bar on the left edge.
static func accent_style(hue: Color, alpha: float = 0.8) -> StyleBoxFlat:
	var sb := panel_style(Color(hue, 0.42))
	sb.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, alpha)
	sb.border_width_left = 3
	sb.border_color = Color(hue, 0.55)
	return sb


## A small key chip ("T", "F2"): ice ground, black mono text.
static func key_chip(text: String, size: int = FS_CAPTION) -> Label:
	var k := Label.new()
	k.text = text
	k.add_theme_font_override("font", mono_font())
	k.add_theme_font_size_override("font_size", size)
	k.add_theme_color_override("font_color", BLACK)
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(ICE, 0.92)
	ks.set_corner_radius_all(4)
	ks.content_margin_left = 7
	ks.content_margin_right = 7
	ks.content_margin_top = 0
	ks.content_margin_bottom = 0
	k.add_theme_stylebox_override("normal", ks)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return k


static func panel_style(accent: Color = HAIRLINE_STRONG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## The shared Theme: assign to any top-level Control (theme = DeepFieldTheme.get_theme()).
static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = FS_SMALL
	for type in ["Label", "Button", "LineEdit", "RichTextLabel", "CheckBox", "OptionButton"]:
		t.set_color("font_color", type, INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("mono_font", "RichTextLabel", mono_font())
	t.set_font("bold_font", "RichTextLabel", _font(FONT_BODY_PATH, 650))
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var btn := panel_style(HAIRLINE_STRONG)
	btn.content_margin_top = 6
	btn.content_margin_bottom = 6
	var btn_hover := panel_style(ICE)
	btn_hover.content_margin_top = 6
	btn_hover.content_margin_bottom = 6
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_hover)
	t.set_stylebox("focus", "Button", btn_hover)
	t.set_color("font_hover_color", "Button", ICE)
	t.set_stylebox("normal", "LineEdit", btn)
	t.set_stylebox("focus", "LineEdit", btn_hover)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	# Type variations: DisplayLabel (wide uppercase headline), MonoLabel (chain values), MutedLabel.
	t.set_type_variation("DisplayLabel", "Label")
	t.set_font("font", "DisplayLabel", display_font())
	t.set_font_size("font_size", "DisplayLabel", 26)
	t.set_type_variation("MonoLabel", "Label")
	t.set_font("font", "MonoLabel", mono_font())
	t.set_font_size("font_size", "MonoLabel", FS_CAPTION)
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", MUTED)
	t.set_font_size("font_size", "MutedLabel", FS_CAPTION)
	_theme = t
	return t


static func rarity_color(tier: String) -> Color:
	return RARITY.get(tier, MUTED)
