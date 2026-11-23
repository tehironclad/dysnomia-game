class_name PubLayout
extends RefCounted
## Every position in the cantina, derived once from PubGenerator params so the shell,
## the furnishing and the patrons all agree. Local space: door faces +Z, floor top at FY.
##
##   back wall (-Z)  ─ back bar / bottles / menu ─────────── display screen ─
##                    bartender walkway                     game row 1 (0,1)
##                    BAR COUNTER  [order gap]
##   dartboard        stools                                game row 2 (2,3)
##                    high-tops
##   lounge sofa                                            arcade  jukebox
##   front wall (+Z)  window        DOOR        window
##   porch + awning + steps

const FY := 0.55          # Floor top above terrain (raised plinth; utility pipes run in beneath)
const T := 0.3            # Wall thickness
const DOOR_W := 2.4
const DOOR_H := 3.0
const PORCH_D := 3.4      # Porch depth in front of the front wall
const COUNTER_H := 1.08
const GAME_TABLE_SIZE := Vector3(1.8, 0.8, 1.05)

var p: Dictionary
var w: float   # Half interior width (x)
var d: float   # Half interior depth (z)
var h: float   # Wall (eave) height above floor
var eave: float
var roof_style: int
var roof_rise: float

# Openings: [centre, width, sill (above FY), top (above FY)]
var front_windows: Array = []
var left_windows: Array = []
var right_windows: Array = []

var bar_x0: float
var bar_x1: float
var bar_cx: float
var counter_z: float
var counter_front: float
var walkway_z: float
var back_counter_z: float
var order_x: float
var tap_x: float
var stools: Array[Vector3] = []
var sit_stools: Array[int] = []        # Stools with a seated patron
var occupied_stools: Array[int] = []   # Stool spots removed for a patron leaning on the bar
const PLATFORM_H := 0.28               # Duckboards behind the bar so the bartender reads over it

var game_tables: Array[Vector3] = []
var hightops: Array[Vector3] = []
var barrel_tables: Array[Vector3] = []
var lounges: Array[Vector3] = []       # Sofa-group centres (two sofas facing across a coffee table)
var booths: Array[float] = []          # Booth z-centres along the left wall
var booth_x: float
var dart_pos: Vector3
var dart_throw: Vector3
var jukebox_pos: Vector3
var arcade_pos: Vector3
var display_pos: Vector3


func _init(params: Dictionary) -> void:
	p = params
	w = params["room_width"] * 0.5
	d = params["room_depth"] * 0.5
	h = params["wall_height"]
	eave = FY + h
	roof_style = params["roof_style"]
	roof_rise = params["roof_rise"]

	front_windows = [[-w * 0.55, 2.4, 0.95, 2.6], [w * 0.5, 2.0, 0.95, 2.6]]
	var nl: int = 1 + int(params["window_count"]) % 2
	for i in nl:
		left_windows.append([lerpf(-d + 5.6, d - 1.2, (float(i) + 0.5) / float(nl)), 1.5, 1.15, 2.6])
	right_windows = [[-d + 2.4, 1.5, 1.15, 2.6], [-d + 5.6, 1.5, 1.15, 2.6]]

	bar_x0 = -w + 0.15
	bar_x1 = 0.4
	bar_cx = (bar_x0 + bar_x1) * 0.5
	counter_z = -d + 2.35
	counter_front = counter_z + 0.4
	walkway_z = -d + 1.4
	back_counter_z = -d + 0.45
	tap_x = bar_cx - 0.6
	order_x = bar_cx + 0.9
	var n_st: int = params["stool_count"]
	var x := bar_x0 + 0.7
	var spacing := 0.82
	while stools.size() < n_st and x < bar_x1 - 0.25:
		if absf(x - order_x) > 0.8:
			stools.append(Vector3(x, FY, counter_front + 0.38))
		x += spacing
	var ns := stools.size()
	if ns >= 2:
		sit_stools = [1, ns - 1]
	if ns >= 5:
		occupied_stools = [ns - 2]

	var xa := w - 1.55
	var xb := w - 4.3
	var z1 := -d + 2.4
	var z2 := -d + 5.6
	var spots := [Vector3(xb, FY, z1), Vector3(xa, FY, z1), Vector3(xb, FY, z2), Vector3(xa, FY, z2)]
	for i in clampi(params["game_table_count"], 2, 4):
		game_tables.append(spots[i])

	var ht := [Vector3(-1.9, FY, -d + 5.3), Vector3(0.9, FY, minf(d - 2.6, -d + 8.2)), Vector3(-4.3, FY, -d + 5.7)]
	for i in clampi(params["table_count"], 2, 3):
		hightops.append(ht[i])
	# An upturned keg table by the jukebox
	barrel_tables.append(Vector3(w - 1.4, FY, d - 2.6))

	# Two sofa groups along the front wall, either side of the door
	lounges.append(Vector3((2.45 + w - 3.6) * 0.5, FY, d - 1.65))
	lounges.append(Vector3((-w + 2.7 - 2.45) * 0.5, FY, d - 1.65))
	# Booth row on the left wall, from the darts to the front corner
	booth_x = -w + 0.72
	var zb0 := -d + 5.0
	var zb1 := d - 1.0
	var nb := int((zb1 - zb0) / 2.0)
	for i in nb:
		booths.append(zb0 + (zb1 - zb0 - float(nb) * 2.0) * 0.5 + 1.0 + float(i) * 2.0)

	dart_pos = Vector3(-w + 0.17, FY + 1.73, -d + 4.2)
	dart_throw = Vector3(-w + 2.55, FY, -d + 4.2)
	jukebox_pos = Vector3(w - 0.95, FY, d - 0.5)
	arcade_pos = Vector3(w - 2.3, FY, d - 0.55)
	display_pos = Vector3((xa + xb) * 0.5, FY + 3.05, -d + 0.17)


func roof_y(x: float) -> float:
	## Height of the outer roof surface at local x (matches roof_profile exactly).
	var ow := w + 0.5
	var base := eave - 0.12
	match roof_style:
		0:
			var t := clampf(x / ow, -1.0, 1.0)
			return base + (roof_rise + 0.12) * sqrt(maxf(0.0, 1.0 - t * t))
		1:
			return base + (roof_rise + 0.12) * (1.0 - absf(x) / ow)
		_:
			return base + (roof_rise + 0.24) * (clampf(x, -ow, ow) + ow) / (2.0 * ow)


func roof_profile() -> PackedVector2Array:
	## Outer roof cross-section (x, y), left eave → right eave, including overhang.
	var pts := PackedVector2Array()
	var ow := w + 0.5
	var steps := 24 if roof_style == 0 else 2
	if roof_style == 2:
		steps = 1
	for i in steps + 1:
		var x := -ow + 2.0 * ow * float(i) / float(steps)
		if roof_style == 0:
			x = cos(PI * (1.0 - float(i) / float(steps))) * ow
		pts.append(Vector2(x, roof_y(x)))
	return pts


func gable_poly() -> PackedVector2Array:
	## Wall area between the eave line and the roof, used to close the front/back ends.
	var pts := PackedVector2Array()
	var ex := w + T * 0.5
	pts.append(Vector2(-ex, eave))
	var prof := roof_profile()
	for v in prof:
		if absf(v.x) < ex:
			pts.append(Vector2(v.x, v.y - 0.04))
	if roof_y(ex) - 0.04 > eave + 0.01:
		pts.append(Vector2(ex, roof_y(ex) - 0.04))
	pts.append(Vector2(ex, eave))
	if roof_y(-ex) - 0.04 > eave + 0.01:
		pts.insert(1, Vector2(-ex, roof_y(-ex) - 0.04))
	return pts
