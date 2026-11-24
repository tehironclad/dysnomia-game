extends SceneTree
## Builds the outfit recolour masks from the Quaternius outfit atlases (run once
## after changing the source textures; the PNGs are committed):
##   godot --headless --path . -s res://tools/outfit_masks.gd
## For each atlas (Peasant, Ranger) writes T_<name>_Mask.png next to it:
##   R = light cloth (cream shirts, white panels)   G = leather (straps, belts)
##   B = metal (buckles; from the ORM map's metallic channel)
##   A = fabric detail ÷ 2: the texel's luminance over the blurred luminance of
##       its own class, so folds and stitching survive any recolour.
## Everything not R/G/B is the garment's main cloth. outfit.gdshader reads it.

const DIR := "res://assets/characters/outfits/"
const SIZE := 1024
const BLUR := 64  # the blurred image's size (a ~16 texel neighbourhood at 1024)


func _initialize() -> void:
	for n in ["Peasant", "Ranger"]:
		_build(n)
	quit()


func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != SIZE:
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return img


static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x) if a < b else 1.0 - smoothstep(b, a, x)


func _classes(name: String, c: Color, orm: Color) -> Vector4:
	## Weights (light, leather, metal, cloth) of one texel.
	var metal := smoothstep(0.35, 0.65, orm.b)
	var light := 0.0
	var leather := 0.0
	if name == "Ranger":
		# Green cloth, brown leather, pale highlights.
		leather = _ss(0.16, 0.12, c.h) * smoothstep(0.25, 0.4, c.s)
		light = _ss(0.24, 0.14, c.s) * smoothstep(0.42, 0.6, c.v)
	else:
		# Peasant: cream linen over dark brown cloth (the leather reads as dark cloth).
		light = smoothstep(0.36, 0.48, c.v) * _ss(0.55, 0.4, c.s)
	light *= 1.0 - metal
	leather *= (1.0 - metal) * (1.0 - light)
	var cloth := maxf(0.0, 1.0 - light - leather - metal)
	return Vector4(light, leather, metal, cloth)


func _build(name: String) -> void:
	var base := _load(DIR + "T_%s_BaseColor.png" % name)
	var orm := _load(DIR + "T_%s_ORM.png" % name)
	var num := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBAF)
	var den := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBAF)
	var mask := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var lums := PackedFloat32Array()
	lums.resize(SIZE * SIZE)
	var ws: Array[Vector4] = []
	ws.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var c := base.get_pixel(x, y)
			var w := _classes(name, c, orm.get_pixel(x, y))
			var l := maxf(0.01, c.get_luminance())
			lums[y * SIZE + x] = l
			ws[y * SIZE + x] = w
			num.set_pixel(x, y, Color(l * w.x, l * w.y, l * w.z, l * w.w))
			den.set_pixel(x, y, Color(w.x, w.y, w.z, w.w))
	# Box-average by halving (exact 2×2 means), then back up smoothly.
	for img in [num, den]:
		var s := SIZE
		while s > BLUR:
			s /= 2
			img.resize(s, s, Image.INTERPOLATE_BILINEAR)
		img.resize(SIZE, SIZE, Image.INTERPOLATE_CUBIC)
	for y in SIZE:
		for x in SIZE:
			var w: Vector4 = ws[y * SIZE + x]
			var n := num.get_pixel(x, y)
			var d := den.get_pixel(x, y)
			var blur := 0.0
			var tw := 0.0
			for i in 4:
				if d[i] > 0.002:
					blur += w[i] * n[i] / d[i]
					tw += w[i]
			blur = blur / tw if tw > 0.0 else lums[y * SIZE + x]
			var detail := clampf(lums[y * SIZE + x] / maxf(blur, 0.01), 0.3, 1.95)
			mask.set_pixel(x, y, Color(w.x, w.y, w.z, detail * 0.5))
	var out := DIR + "T_%s_Mask.png" % name
	mask.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out)
