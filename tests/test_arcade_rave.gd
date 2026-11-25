extends TestCase
## The rave arcade (2026-11-25): its style comes from the territory only, the synthesised track is
## deterministic and sane, and the hall's layout leaves the cabinets, the stage and the door clear.

const ILLINOIS := {"address": "0xd127839b83cbf537c29b7d268c135f745a0da2e8", "entropy": "123456789123456789", "name": "Illinois"}
const OTHER := {"address": "0x2b78b345880807ac9be28c1309ab55d6fa8796de", "entropy": "987654321987654321", "name": "Other"}


func test_style_from_the_territory_only() -> void:
	var a := RaveStyle.for_territory(ILLINOIS)
	eq(str(a), str(RaveStyle.for_territory(ILLINOIS)), "the same territory, the same party")
	var before := Session.wallet
	Session.wallet = "0x00000000000000000000000000000000000000aa"
	eq(str(a), str(RaveStyle.for_territory(ILLINOIS)), "whoever is looking")
	Session.wallet = before
	var b := RaveStyle.for_territory(OTHER)
	check(str(a) != str(b), "another territory parties differently")
	for s in [a, b, RaveStyle.for_territory({})]:
		check(int(s["bpm"]) >= 120 and int(s["bpm"]) <= 128, "a club tempo: %d" % int(s["bpm"]))
		check(int(s["root"]) >= 0 and int(s["root"]) < 12, "a key")
		eq((s["uv"] as Array).size(), 3)
		for c in s["uv"]:
			check((c as Color).v > 0.99 and (c as Color).s >= 0.7, "fluorescent paint: %s" % c)
		check(RaveStyle.FLOOR_PATTERNS.has(s["floor"]) and RaveStyle.WALL_PATTERNS.has(s["wall"]), "known patterns")
		check(int(s["lasers"]) >= 6 and int(s["lasers"]) <= 12, "6–12 lasers")
		check(AvatarHeads.KINDS.has(s["dj_head"]), "the DJ wears a real head")
	var crowd := RaveStyle.crowd(a, 10)
	eq(crowd.size(), 10)
	eq(str(crowd), str(RaveStyle.crowd(a, 10)), "the same crowd every visit")
	for p in crowd:
		check(AvatarHeads.KINDS.has(p["head"]) and Outfits.KINDS.has(p["outfit"]["kind"]), "real heads and outfits")


func test_track_shape() -> void:
	var sp := RaveTrack.spec({"bpm": 124, "root": 3, "groove": 2})
	eq(RaveTrack.bar_samples(sp), int(round(22050.0 * 60.0 / 124.0 * 4.0)))
	var keys := RaveTrack.keys_in_order()
	eq(keys.size(), 12, "12 distinct bars in the 16-bar cycle")
	eq(keys[0], "intro:0", "the first bar first")
	for bar in 32:
		check(keys.has(RaveTrack.bar_key(bar)), "bar %d has audio" % bar)
	eq(RaveTrack.section(4), "drop")
	eq(RaveTrack.section(12), "break")
	eq(RaveTrack.section(15), "build")
	eq(RaveTrack.section(16), "intro", "the cycle repeats")
	near(RaveTrack.hz({"root": 0}, 0, 0), 55.0, 0.001)
	near(RaveTrack.hz({"root": 0}, 12, 1), 220.0, 0.001)


static func _rms(f: PackedVector2Array, from: int, to: int) -> float:
	var s := 0.0
	for i in range(from, to):
		s += f[i].x * f[i].x + f[i].y * f[i].y
	return sqrt(s / maxf(1.0, (to - from) * 2.0))


func test_track_renders() -> void:
	var sp := RaveTrack.spec({"bpm": 126, "root": 5, "groove": 1})
	var kit := RaveTrack.make_kit(sp)
	var drop := RaveTrack.render(sp, "drop", 1, kit)
	eq(drop.size(), RaveTrack.bar_samples(sp))
	eq(drop, RaveTrack.render(sp, "drop", 1, RaveTrack.make_kit(sp)), "deterministic")
	var peak := 0.0
	for v in drop:
		peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
	check(peak <= 0.98 and peak > 0.3, "loud, never clipping: peak %.3f" % peak)
	var beat := RaveTrack.bar_samples(sp) / 4
	check(_rms(drop, 0, 600) > 2.0 * _rms(drop, beat - 900, beat - 300), "the kick lands on the beat")
	var brk := RaveTrack.render(sp, "break", 0, kit)
	check(_rms(brk, 0, 600) < _rms(drop, 0, 600) * 0.5, "the break drops the kick")
	check(_rms(brk, 0, brk.size()) > 0.01, "the break still plays (pad and arp)")
	check(RaveTrack.render(sp, "intro", 0, kit) != RaveTrack.render(sp, "intro", 2, kit), "chords differ")


func test_beat_clock_maths() -> void:
	var m := RaveMusic.new()
	m.sp = RaveTrack.spec({"bpm": 120})
	m.clock = 3.25
	near(m.beats(), 6.5, 0.0001)
	near(m.beat_phase(), 0.5, 0.0001)
	eq(m.bar(), 1)
	eq(m.section(), "intro")
	m.clock = 4.0 * 2.0 + 0.1  # bar 4 (2 s a bar at 120 BPM): the drop
	eq(m.section(), "drop")
	m.free()


func test_dance_on_the_beat() -> void:
	for bpm in [120.0, 124.0, 128.0]:
		var speed: float = RaveHall.dance_clip_speed(bpm)
		var lib := HumanAvatar.library()
		if not lib.has_animation("Dance"):
			continue
		var loop_s: float = lib.get_animation("Dance").length / speed
		var beats: float = loop_s / (60.0 / bpm)
		near(beats, round(beats), 0.001, "one Dance loop = a whole number of beats at %d BPM" % int(bpm))
		check(speed > 0.6 and speed < 1.6, "danced near its own pace (×%.2f)" % speed)


func test_hall_layout_is_clear() -> void:
	var hx := 12.0
	var hz := 10.0
	var lay := RaveHall.layout(hx, hz)
	var dance: Rect2 = lay["dance"]
	check(dance.position.y > float(lay["stage_z"]), "the dance floor is in front of the stage")
	check(dance.end.x < hx - 0.7 - 1.1 - 1.0 and dance.position.x > -(hx - 0.7 - 1.1 - 1.0), "the floor stops a metre short of the cabinets' play spots")
	check(dance.end.y < hz - 3.0, "the door lane and the tables stay free")
	check(absf((lay["dj"] as Vector3).z) < hz and (lay["dj"] as Vector3).z < float(lay["stage_z"]), "the DJ is on the stage")
