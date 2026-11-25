extends TestCase


func test_fonts_are_bundled_not_fallback() -> void:
	for f in [DeepFieldTheme.display_font(), DeepFieldTheme.body_font(), DeepFieldTheme.mono_font()]:
		check(f is FontVariation, "expected a FontVariation over a bundled font, got fallback")
		if f is FontVariation:
			check(f.base_font is FontFile and f.base_font.data.size() > 100000, "font data loaded")


func test_theme_tokens() -> void:
	var t := DeepFieldTheme.get_theme()
	eq(t.get_color("font_color", "Label"), DeepFieldTheme.INK)
	check(t.get_font("font", "MonoLabel") is FontVariation, "MonoLabel uses the mono font")
	eq(DeepFieldTheme.rarity_color("Mythic"), Color("#ffd59a"))
	eq(DeepFieldTheme.BLACK.to_html(false), "030407")


func test_type_floor() -> void:
	var t := DeepFieldTheme.get_theme()
	check(t.default_font_size >= DeepFieldTheme.FS_MIN, "body text ≥ FS_MIN")
	for ty in ["MonoLabel", "MutedLabel", "DisplayLabel"]:
		check(t.get_font_size("font_size", ty) >= DeepFieldTheme.FS_MIN, "%s ≥ FS_MIN" % ty)
	check(DeepFieldTheme.FS_MIN * 720.0 / 1080.0 >= 12.5, "≈ 13 px on a 720p screen")
	eq(DeepFieldTheme.fs(11), DeepFieldTheme.FS_MIN)
	eq(DeepFieldTheme.fs(30), 30)
