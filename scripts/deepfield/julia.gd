class_name Julia
extends RefCounted
## CPU reference renderer for Deep Field pictures: a line-for-line port of
## render() in lib/deep-field.js (distance-estimate filaments on black, styled
## per territory). Used for tests, previews and emblem textures. The GPU shader
## (assets/shaders/deep_field.gdshader) draws the same formula in real time.

const GOLD := [1.0, 0.78, 0.4]


## Returns RGB8 bytes (w*h*3). opts: max_iter, zoom, mirror (draw c̄), phase, style.
static func render_rgb(p: Dictionary, w: int, h: int, opts: Dictionary = {}) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h * 3)
	var max_iter: int = opts.get("max_iter", 160)
	var col: Array = p["color"]
	var col2: Array = p.get("color2", col)
	var mirror: bool = opts.get("mirror", false)
	var d: int = p.get("power", 2)
	var style: String = opts.get("style", p.get("style", "glow"))
	var ld := log(float(d))
	var ext: float = float(opts.get("zoom", 1.0)) * float(p["extent"])
	var s := ext * 2.0 / mini(w, h)
	var px := s
	var c: Array = p["c"]
	var cr0: float = c[0]
	var cr1: float = -c[1] if mirror else c[1]
	var ca := cos(float(p["rotation"]))
	var sa := sin(float(p["rotation"]))
	var ph: float = float(opts.get("phase", 0.0)) + float(p["hue"]) * TAU
	var hue: float = p["hue"]
	for y in h:
		for x in w:
			var ux := (x - w / 2.0) * s
			var uy := (y - h / 2.0) * s
			var zx := ux * ca - uy * sa
			var zy := ux * sa + uy * ca
			var dx := 1.0
			var dy := 0.0
			var i := 0
			var m := 0.0
			var trap := 1e9
			var trap_a := 0.0
			while i < max_iter:
				var px1 := 1.0
				var py1 := 0.0
				for e in range(1, d):
					var t1 := px1 * zx - py1 * zy
					py1 = px1 * zy + py1 * zx
					px1 = t1
				var ndx := d * (px1 * dx - py1 * dy)
				var ndy := d * (px1 * dy + py1 * dx)
				dx = ndx
				dy = ndy
				var nzx := px1 * zx - py1 * zy + cr0
				zy = px1 * zy + py1 * zx + cr1
				zx = nzx
				m = zx * zx + zy * zy
				if m < trap:
					trap = m
					trap_a = atan2(zy, zx)
				if m > 1e4:
					break
				i += 1
			var r := 0.0
			var g := 0.0
			var b := 0.0
			if i == max_iter:
				var v := 0.07 * exp(-trap * 3.0)
				if style == "ember":
					var q := exp(-sqrt(trap) * 4.0)
					r = col2[0] * (v + 0.5 * q)
					g = col2[1] * (v + 0.5 * q)
					b = col2[2] * (v + 0.5 * q)
				elif style == "prism":
					var hc := DeepField.color_of(hue + trap_a / TAU + sqrt(trap) * 1.5)
					var st := pow(maxf(0.0, cos(sqrt(trap) * 46.0)), 10.0) * 0.55 + 0.14 * exp(-trap * 3.0)
					r = hc[0] * st
					g = hc[1] * st
					b = hc[2] * st
				elif style == "gilded":
					var gq := 0.14 * exp(-trap * 2.0) + 0.42 * pow(maxf(0.0, cos(sqrt(trap) * 34.0)), 14.0)
					r = GOLD[0] * gq + col[0] * 0.05
					g = GOLD[1] * gq + col[1] * 0.05
					b = GOLD[2] * gq + col[2] * 0.05
				else:
					r = col[0] * v
					g = col[1] * v
					b = col[2] * v
			else:
				var rr := sqrt(m)
				var de := 0.5 * rr * log(rr) / sqrt(dx * dx + dy * dy)
				var core := exp(-de / (px * 1.6))
				var halo := exp(-de / (px * 22.0))
				var wm := core * 0.55
				var nu := i + 1 - log(log(rr)) / ld
				var A: Array = col
				var B: Array = col
				if style == "duo":
					B = col2
				elif style == "gilded":
					A = GOLD
					B = col
				elif style == "prism":
					A = DeepField.color_of(hue + nu * 0.05)
					B = DeepField.color_of(hue + nu * 0.05 + 0.18 + 0.06 * sin(atan2(zy, zx) * 2.0))
				var band := 1.0
				var hg := 0.0
				if style == "bands":
					band = 0.5 + 0.5 * cos(nu * 1.6 + ph)
					hg = halo * 0.22 + 0.42 * pow(band, 4.0) * exp(-de / (px * 140.0))
				elif style == "gilded":
					band = 0.5 + 0.5 * cos(nu * 2.4 + ph)
					hg = halo * 0.4 + 0.3 * pow(band, 3.0) * exp(-de / (px * 160.0)) + 0.05 * exp(-de / (px * 600.0))
				elif style == "prism":
					band = 0.5 + 0.5 * cos(nu * 1.25 + ph)
					hg = halo * 0.5 + 0.42 * pow(band, 2.0) * exp(-de / (px * 260.0)) + 0.1 * exp(-de / (px * 900.0))
				else:
					hg = halo * 0.3
				r = (A[0] * (1.0 - wm) + wm) * core + B[0] * hg
				g = (A[1] * (1.0 - wm) + wm) * core + B[1] * hg
				b = (A[2] * (1.0 - wm) + wm) * core + B[2] * hg
			var k := (y * w + x) * 3
			out[k] = _byte(r)
			out[k + 1] = _byte(g)
			out[k + 2] = _byte(b)
	return out


## Uint8ClampedArray semantics: clamp to [0, 255], round half to even.
static func _byte(v: float) -> int:
	var x := clampf(v * 255.0, 0.0, 255.0)
	if is_nan(x):
		return 0
	var f := floorf(x)
	var frac := x - f
	if frac > 0.5 or (frac == 0.5 and int(f) % 2 == 1):
		return int(f) + 1
	return int(f)


static func render_image(p: Dictionary, w: int, h: int, opts: Dictionary = {}) -> Image:
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, render_rgb(p, w, h, opts))
