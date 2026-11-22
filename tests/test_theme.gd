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
