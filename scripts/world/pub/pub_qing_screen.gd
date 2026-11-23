class_name PubQingScreen
extends Node3D
## The "QING POWER" wall screen: a live 2D dashboard rendered into a SubViewport —
## territory map with a radar sweep, a rolling CHARGE chart, Hypobar/Epibar meters and a
## news ticker — all fed from GameManager's territory state (deterministic demo feed offline).

const RES := Vector2i(768, 384)
const HISTORY := 64

var _vp: SubViewport
var _canvas: Control
var _quad: MeshInstance3D
var _font: Font
var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _accent := Color(0.3, 0.8, 1.0)
var _t := 0.0
var _redraw_t := 0.0
var _sample_t := 0.0
var _history: Array[float] = []
var _cells: Array = []            # [Vector2 centre, float height, bool owned]
var _ticker_x := 0.0
var _ticker := ""


func setup(size_m: Vector2, seed_value: int, accent: Color) -> void:
	_seed = seed_value
	_rng.seed = seed_value
	_accent = accent
	_font = ThemeDB.fallback_font
	_vp = SubViewport.new()
	_vp.size = RES
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_canvas = Control.new()
	_canvas.size = Vector2(RES)
	_canvas.draw.connect(_draw_screen)
	_vp.add_child(_canvas)

	var q := QuadMesh.new()
	q.size = size_m
	_quad = MeshInstance3D.new()
	_quad.mesh = q
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _vp.get_texture()
	m.albedo_color = Color(1.25, 1.25, 1.25)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_quad.material_override = m
	add_child(_quad)

	_build_map()
	for i in HISTORY:
		_history.append(_sample(float(i - HISTORY)))
	refresh()


func set_active(on: bool) -> void:
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)


func refresh() -> void:
	## Rebuild the ticker from the latest territory state (called on update_territory_state).
	var parts: Array[String] = []
	parts.append("%s  CHARGE %s" % [_qing_name(), _fmt(_charge())])
	parts.append("HYPOBAR %s" % _fmt(_hypo()))
	parts.append("EPIBAR %s" % _fmt(_epi()))
	parts.append("OMEGA %s" % _fmt(GameManager.territory_omega if GameManager.has_territory_state else 0))
	for d in AttractionCatalog.DRINKS:
		parts.append("%s — %s" % [String(d["name"]).to_upper(), AttractionCatalog.price_label(d).to_upper()])
	parts.append("ROUND FOR THE HOUSE = EVERYONE CHEERS")
	_ticker = "   |   ".join(parts) + "   |   "


func _process(delta: float) -> void:
	_t += delta
	_ticker_x -= delta * 70.0
	_sample_t += delta
	if _sample_t >= 0.8:
		_sample_t = 0.0
		_history.pop_front()
		_history.append(_sample(_t))
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.08
		_canvas.queue_redraw()


# ─── Data ──────────────────────────────────────────────────────────────────

func _live() -> bool:
	return GameManager.has_territory_state


func _charge() -> int:
	return GameManager.territory_charge if _live() else int(4.2e11 + 2.1e11 * sin(_t * 0.05 + float(_seed % 97)))


func _hypo() -> int:
	return GameManager.territory_hypobar if _live() else 1000 + (_seed % 7919)


func _epi() -> int:
	return GameManager.territory_epibar if _live() else 800 + (_seed % 5039)


func _power() -> float:
	return clampf(float(_charge()) / 1e12, 0.0, 1.0)


func _sample(t: float) -> float:
	# Real charge level with a little block-to-block jitter so the line breathes
	var base := _power()
	return clampf(base + 0.06 * sin(t * 0.9 + float(_seed % 13)) + 0.035 * sin(t * 2.7) + _rng.randf_range(-0.02, 0.02), 0.02, 0.98)


func _qing_name() -> String:
	var n := GameManager.territory_name.strip_edges()
	return n.to_upper() if not n.is_empty() else "LOCAL QING"


func _fmt(v: int) -> String:
	var f := float(absi(v))
	for u in [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]:
		if f >= u[0]:
			return "%.2f%s" % [f / u[0], u[1]]
	return str(v)


func _build_map() -> void:
	## Hex map of the QING and its neighbours, heights from the territory seed.
	var noise := FastNoiseLite.new()
	noise.seed = _seed
	noise.frequency = 0.18
	var r := 13.0
	for row in 12:
		for col in 14:
			var c := Vector2(24.0 + float(col) * r * 1.73 + (r * 0.87 if row % 2 == 1 else 0.0), 64.0 + float(row) * r * 1.5)
			if c.x > 360.0 or c.y > 324.0:
				continue
			var hgt := noise.get_noise_2d(float(col), float(row)) * 0.5 + 0.5
			var owned := Vector2(float(col) - 6.5, (float(row) - 5.5) * 1.2).length() < 3.6
			_cells.append([c, hgt, owned])


# ─── Drawing ───────────────────────────────────────────────────────────────

func _draw_screen() -> void:
	var cv := _canvas
	var W := float(RES.x)
	var H := float(RES.y)
	var cyan := Color(0.35, 0.85, 1.0)
	var dim := Color(0.25, 0.45, 0.6)
	cv.draw_rect(Rect2(0, 0, W, H), Color(0.015, 0.03, 0.05))
	# Header
	cv.draw_rect(Rect2(0, 0, W, 40), Color(0.04, 0.09, 0.14))
	cv.draw_string(_font, Vector2(14, 28), "QING POWER  ·  " + _qing_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, cyan)
	var live := _live()
	var blink := fmod(_t, 1.0) < 0.6
	cv.draw_circle(Vector2(W - 104, 20), 6.0, (Color(1.0, 0.25, 0.2) if live else Color(1.0, 0.7, 0.2)) * (1.0 if blink else 0.4))
	cv.draw_string(_font, Vector2(W - 92, 28), "LIVE" if live else "DEMO", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	# Territory map with pulsing border and radar sweep
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var hexr := 12.0
	for cell in _cells:
		var c: Vector2 = cell[0]
		var hgt: float = cell[1]
		var owned: bool = cell[2]
		var col := Color(0.08, 0.14, 0.2).lerp(Color(0.22, 0.42, 0.5), hgt)
		if owned:
			col = col.lerp(_accent, 0.35 + 0.25 * _power())
		cv.draw_colored_polygon(_hex(c, hexr), col)
		if owned:
			cv.draw_polyline(_hex(c, hexr, true), _accent.lerp(Color.WHITE, pulse * 0.4), 1.5)
	var mc := Vector2(190, 190)
	var sweep := _t * 1.4
	for k in 18:
		var a := sweep - float(k) * 0.035
		cv.draw_line(mc, mc + Vector2(cos(a), sin(a)) * 150.0, Color(cyan.r, cyan.g, cyan.b, 0.18 * (1.0 - float(k) / 18.0)), 2.0)
	for poi in [[Vector2(190, 190), "CANTINA"], [Vector2(120, 120), "MONUMENT"], [Vector2(260, 260), "FAIR"]]:
		var pp: Vector2 = poi[0]
		cv.draw_circle(pp, 4.0, Color(1.0, 0.85, 0.4))
		cv.draw_string(_font, pp + Vector2(7, 4), poi[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.7))
	cv.draw_rect(Rect2(8, 48, 360, 284), dim, false, 1.0)

	# Charge chart
	var cr := Rect2(384, 48, 376, 168)
	cv.draw_rect(cr, Color(0.02, 0.05, 0.08))
	for g in 5:
		var gy := cr.position.y + cr.size.y * float(g) / 4.0
		cv.draw_line(Vector2(cr.position.x, gy), Vector2(cr.end.x, gy), Color(0.1, 0.2, 0.28), 1.0)
	var pts := PackedVector2Array()
	var fill := PackedVector2Array([Vector2(cr.position.x, cr.end.y)])
	for i in _history.size():
		var p := Vector2(cr.position.x + cr.size.x * float(i) / float(HISTORY - 1),
			cr.end.y - 8.0 - (cr.size.y - 40.0) * _history[i])
		pts.append(p)
		fill.append(p)
	fill.append(Vector2(cr.end.x, cr.end.y))
	cv.draw_colored_polygon(fill, Color(_accent.r, _accent.g, _accent.b, 0.18))
	cv.draw_polyline(pts, _accent.lerp(Color.WHITE, 0.25), 2.5, true)
	cv.draw_circle(pts[pts.size() - 1], 4.0 + pulse * 2.0, Color.WHITE)
	cv.draw_string(_font, cr.position + Vector2(10, 24), "CHARGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, dim.lightened(0.4))
	cv.draw_string(_font, cr.position + Vector2(cr.size.x - 10, 28), _fmt(_charge()), HORIZONTAL_ALIGNMENT_RIGHT, cr.size.x - 100, 26, Color.WHITE)

	# Hypobar / Epibar meters
	var hy := float(_hypo())
	var ep := float(_epi())
	var tot := maxf(hy + ep, 1.0)
	var bars := [["HYPOBAR", hy / tot, Color(1.0, 0.45, 0.6), _hypo()], ["EPIBAR", ep / tot, Color(0.45, 1.0, 0.6), _epi()]]
	for i in 2:
		var by := 232.0 + float(i) * 48.0
		var b: Array = bars[i]
		cv.draw_string(_font, Vector2(384, by + 14), b[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, dim.lightened(0.5))
		cv.draw_rect(Rect2(480, by, 220, 18), Color(0.06, 0.1, 0.14))
		cv.draw_rect(Rect2(480, by, 220.0 * clampf(b[1], 0.03, 1.0), 18), b[2])
		cv.draw_string(_font, Vector2(760, by + 15), _fmt(b[3]), HORIZONTAL_ALIGNMENT_RIGHT, 56, 15, Color.WHITE)

	# Ticker
	cv.draw_rect(Rect2(0, H - 42, W, 42), Color(0.9, 0.55, 0.1))
	var tw := _font.get_string_size(_ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	if tw > 0.0 and _ticker_x < -tw:
		_ticker_x += tw
	cv.draw_string(_font, Vector2(_ticker_x, H - 14), _ticker + _ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.06, 0.03, 0.0))
	# Scanlines
	for y in range(0, int(H), 4):
		cv.draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.12), 1.0)


func _hex(c: Vector2, r: float, closed: bool = false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 6:
		var a := PI / 6.0 + float(k) * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	if closed:
		pts.append(pts[0])
	return pts
