extends TestCase
## Pool and Twenty-One in first person: the aim and the held power map exactly
## onto a shot line's integers (PoolSim's inputs), the aiming ghost is the real
## sim, the card table's seat layout, the practice house, and the arcade
## marquee layout. No network.

const A := "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B := "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const HASH1 := "0x1111111111111111111111111111111111111111111111111111111111111111"


func test_aim_vector_and_angle() -> void:
	eq(PoolAim.aim_vector(0.0), Vector2i(10000, 0), "0 points along the table's length (+x)")
	eq(PoolAim.aim_vector(PI * 0.5), Vector2i(0, 10000), "PI/2 points across (+y)")
	eq(PoolAim.aim_vector(PI), Vector2i(-10000, 0))
	for i in 24:
		var a := -PI + i * TAU / 24.0 + 0.013
		var v := PoolAim.aim_vector(a)
		near(PoolAim.angle_of(v), a, 0.0002, "angle round trip at %f" % a)
		var len := sqrt(float(v.x * v.x + v.y * v.y))
		near(len, 10000.0, 1.0, "a unit vector × 10000")
	near(PoolAim.angle_to(Vector2i(0, 0), Vector2i(5, 5)), PI * 0.25, 1e-6)
	var d := PoolAim.dir3(0.7)
	near(d.x, cos(0.7), 1e-6)
	near(d.z, sin(0.7), 1e-6, "sim y is the table's local Z")


func test_power_from_charge() -> void:
	eq(PoolAim.power_from_charge(0.0), PoolAim.MIN_POWER)
	eq(PoolAim.power_from_charge(1.0), PoolAim.MAX_POWER)
	eq(PoolAim.power_from_charge(-3.0), PoolAim.MIN_POWER, "clamped low")
	eq(PoolAim.power_from_charge(7.0), PoolAim.MAX_POWER, "clamped high")
	var last := 0
	for i in 101:
		var p := PoolAim.power_from_charge(i / 100.0)
		check(p >= last, "power never drops as the charge rises")
		check(p % PoolAim.POWER_STEP == 0, "power in steps of 10: %d" % p)
		check(p >= 1 and p <= 1000, "inside the line's 1–1000")
		near(PoolAim.charge_of(p), i / 100.0, 0.006, "the meter shows the power sent")
		last = p
	near(PoolAim.speed_mps(1000), 4.992, 0.001, "full power ≈ 5 m/s (PoolSim.VMAX)")


func test_charge_meter_ping_pongs() -> void:
	var t := PoolAim.CHARGE_TIME
	near(PoolAim.charge_at(0.0), 0.0, 1e-6)
	near(PoolAim.charge_at(t * 0.5), 0.5, 1e-6)
	near(PoolAim.charge_at(t), 1.0, 1e-6, "full at CHARGE_TIME")
	near(PoolAim.charge_at(t * 1.5), 0.5, 1e-6, "then falls back")
	near(PoolAim.charge_at(t * 2.0), 0.0, 1e-6)
	near(PoolAim.charge_at(t * 2.25), 0.25, 1e-6, "and rises again")


func test_shot_params_survive_the_line() -> void:
	# What the seat sends is exactly what every machine replays.
	for i in 16:
		var a := -PI + i * TAU / 16.0 + 0.05
		var c := i / 15.0
		var p := PoolAim.shot_params(a, c)
		var text := TableBook.shot_text("abcd1234", p["dx"], p["dy"], p["power"])
		var back := TableBook.parse(text)
		eq(back.get("op", ""), "shot", text)
		eq(back["dx"], p["dx"], "dx")
		eq(back["dy"], p["dy"], "dy")
		eq(back["power"], p["power"], "power")


func test_first_person_shot_replays_through_the_book() -> void:
	var book := TableBook.new("0xq")
	var id_tx := "0xfeed0001" + "0".repeat(56)
	book.ingest({"tx": id_tx, "log_index": 0, "block": 10, "from": A, "text": "🎱 challenge anyone", "name": "", "block_hash": ""})
	book.ingest({"tx": "0x02", "log_index": 0, "block": 11, "from": B, "text": "🎱 #feed0001 accept", "name": "", "block_hash": ""})
	var m: Dictionary = book.by_id["feed0001"]
	var snap: PackedInt64Array = m["game"].sim.snapshot()
	var a := PoolAim.default_angle(snap)
	var p := PoolAim.shot_params(a, 1.0)
	# The same shot on a local sim, as the seat's practice table would run it.
	var local := PoolSim.new()
	local.apply_snapshot(snap)
	var r := local.shoot(p["dx"], p["dy"], p["power"])
	book.ingest({"tx": "0x03", "log_index": 0, "block": 12, "from": A, "text": TableBook.shot_text("feed0001", p["dx"], p["dy"], p["power"]), "name": "", "block_hash": ""})
	eq(m["game"].shots, 1, "the challenger's first-person break counted")
	eq(m["last_shot"]["dx"], p["dx"])
	eq(m["last_shot"]["power"], p["power"])
	eq(m["game"].sim.digest(), local.digest(), "the replay is the same table as the local run")
	eq(r["first_contact"], 1, "aiming at the nearest ball hits the apex of the rack")


func test_ghost_is_the_real_sim() -> void:
	var sim := PoolSim.new()
	var snap := sim.snapshot()
	var a := PoolAim.default_angle(snap) + 0.01
	var p := PoolAim.shot_params(a, 0.6)
	var g := PoolAim.ghost(snap, p["dx"], p["dy"], p["power"])
	var full := PoolSim.new()
	full.apply_snapshot(snap)
	var r := full.shoot(p["dx"], p["dy"], p["power"], PoolAim.GHOST_EVERY)
	eq(g["target"], r["first_contact"], "the ghost's target is the shot's first contact")
	var path: Array = g["cue_path"]
	check(path.size() > 3, "a path to the contact")
	eq(path[0], Vector2i(snap[0], snap[1]), "the path starts at the cue ball")
	var frames: Array = r["frames"]
	for k in range(1, path.size()):
		var f: PackedInt64Array = frames[k - 1]
		eq(path[k], Vector2i(f[0], f[1]), "ghost point %d is the real run's frame" % k)
	check((g["target_path"] as Array).size() >= 2, "the struck ball's line")
	var c: Vector2i = g["contact_at"]
	var t := int(g["target"])
	var dx := c.x - snap[t * 3]
	var dy := c.y - snap[t * 3 + 1]
	check(dx * dx + dy * dy <= (2 * PoolSim.R + 40000) * (2 * PoolSim.R + 40000), "the ghost ball touches the target")
	# A miss along the rail: no target, a path that ends somewhere.
	var empty := PoolSim.new()
	for b in range(1, 16):
		empty.down[b] = 1
	var g2 := PoolAim.ghost(empty.snapshot(), 0, 10000, 300)
	eq(g2["target"], -1)
	check((g2["cue_path"] as Array).size() > 2, "the cue ball's run without a contact")
	eq(PoolAim.ghost(snap, 0, 0, 500)["target"], -1, "no aim, no ghost")


func test_sim_preview_stop_keeps_the_real_shot() -> void:
	var a := PoolSim.new()
	var b := PoolSim.new()
	var ra := a.shoot(1000, 7, 1000)
	var rb := b.shoot(1000, 7, 1000, 0, PoolSim.MAX_TICKS, -1)
	eq(a.digest(), b.digest(), "the defaults run to rest exactly as before")
	eq(ra["ticks"], rb["ticks"])
	var c := PoolSim.new()
	var rc := c.shoot(1000, 7, 1000, 0, PoolSim.MAX_TICKS, 50)
	eq(rc["first_contact"], ra["first_contact"])
	check(rc["ticks"] < ra["ticks"], "a preview stops soon after the contact")
	var d := PoolSim.new()
	var rd := d.shoot(1000, 7, 1000, 0, 10)
	eq(rd["ticks"], 10, "max_ticks caps a preview")


func test_table_local_mapping() -> void:
	var o := PoolAim.to_local(0, 0)
	near(o.x, -1.27, 1e-6)
	near(o.z, -0.635, 1e-6)
	near(o.y, PoolTable3D.BED + 0.0286, 1e-6, "on the cloth at the balls' centres")
	var e := PoolAim.to_local(PoolSim.W, PoolSim.H)
	near(e.x, 1.27, 1e-6)
	near(e.z, 0.635, 1e-6)
	var eye := PoolAim.eye_behind(Vector3.ZERO, 0.0, 0.6, 0.2)
	near(eye.x, -0.6, 1e-6, "the eye is behind the cue ball")
	near(eye.y, 0.2, 1e-6)


func test_card_seat_layout() -> void:
	for seat in 2:
		var dir := CardTable3D.seat_dir(seat)
		var eye := CardTable3D.seat_eye(seat)
		check(eye.origin.dot(dir) > 1.0, "seat %d's eye sits outside the rim" % seat)
		check((-eye.basis.z).dot(-dir) > 0.5, "seat %d looks at the table" % seat)
		var b := CardTable3D.seat_basis(seat)
		near(b.x.dot(Vector3.UP.cross(dir)), 1.0, 1e-5, "+X is the seated player's right")
		for n in range(2, 9):
			for k in n:
				var p := CardTable3D.card_spot(seat, k, n)
				check(Vector2(p.x, p.z).length() + 0.09 < 0.95, "card %d/%d on the felt" % [k, n])
				check(p.dot(dir) > 0.3, "in front of its seat")
				if k > 0:
					var q := CardTable3D.card_spot(seat, k - 1, n)
					check(Vector2(p.x - q.x, p.z - q.z).length() >= CardTable3D.CARD.x, "cards side by side, not on top of each other")
		# The plates: their centres answer, the middle of the table doesn't.
		var hit := b * Vector3(-0.15, CardTable3D.TOP, CardTable3D.BUTTON_R)
		var stand := b * Vector3(0.15, CardTable3D.TOP, CardTable3D.BUTTON_R)
		eq(CardTable3D.button_at(seat, hit), "hit")
		eq(CardTable3D.button_at(seat, stand), "stand")
		eq(CardTable3D.button_at(seat, Vector3(0, CardTable3D.TOP, 0)), "")
	check(CardTable3D.seat_dir(0).x > 0.0 and CardTable3D.seat_dir(1).x < 0.0, "two seats side by side on the near arc")


func test_practice_house_and_outcomes() -> void:
	check(CardSeat.house_hits([0, 4]), "A+5 = 16: the house draws")  # ace (11) + 5
	check(not CardSeat.house_hits([9, 6]), "10+7 = 17: the house stands")
	var d := Duel21.new()
	eq(CardSeat.outcome(d, 0), "", "not dealt, no outcome")
	d.deal(HASH1)
	d.stand(0)
	while CardSeat.house_hits(d.hands[1]) and not d.over():
		d.hit(1, HASH1)
	if not d.over():
		d.stand(1)
	check(d.over(), "the house finishes the hand")
	var o0 := CardSeat.outcome(d, 0)
	var o1 := CardSeat.outcome(d, 1)
	check(o0 in ["win", "lose", "push"])
	if o0 == "push":
		eq(o1, "push")
	else:
		check(o0 != o1, "one wins, the other loses")
	# Same block hash, same deal: practice is as reproducible as a live game.
	var e := Duel21.new()
	e.deal(HASH1)
	eq(e.hands[0], d.hands[0].slice(0, 2))


func test_chips_for_stake() -> void:
	eq(CardSeat.chips_for(BigInt.zero()), 0, "no stake, no chips")
	eq(CardSeat.chips_for(TableBook.stake_wei("5")), 5)
	eq(CardSeat.chips_for(TableBook.stake_wei("0.25")), 1, "a fraction still shows a chip")
	eq(CardSeat.chips_for(TableBook.stake_wei("1000")), 12, "the stack tops out")


func test_marquee_fits_its_panel() -> void:
	var font := DeepFieldTheme.display_font()
	var titles: Array = ["Bar Raiser", "Entropy Drift", "Void Lanes", "X", "Supercalifragilistic Expialidocious Machine"]
	for e in ArcadeCatalog.games():
		titles.append(String(e.get("title", "")))
	for t in titles:
		var f := ArcadeCabinet.marquee_fit(t, font, 96, ArcadeCabinet.MARQUEE_TEXT.x, ArcadeCabinet.MARQUEE_TEXT.y)
		check(int(f["lines"]) <= 2, "%s: at most two lines" % t)
		check(float(f["width_m"]) <= ArcadeCabinet.MARQUEE_TEXT.x + 1e-4, "%s fits the width (%.3f m)" % [t, f["width_m"]])
		check(float(f["height_m"]) <= ArcadeCabinet.MARQUEE_TEXT.y + 1e-4, "%s fits the height" % t)
		eq(String(f["text"]).replace("\n", " "), String(t).strip_edges().to_upper(), "%s: every word, in order" % t)
	var br := ArcadeCabinet.marquee_fit("Bar Raiser", font, 96, ArcadeCabinet.MARQUEE_TEXT.x, ArcadeCabinet.MARQUEE_TEXT.y)
	var one := ArcadeCabinet.marquee_fit("BarRaiser", font, 96, ArcadeCabinet.MARQUEE_TEXT.x, ArcadeCabinet.MARQUEE_TEXT.y)
	check(float(br["pixel_size"]) >= float(one["pixel_size"]), "splitting BAR / RAISER never makes the letters smaller")
	check(float(br["height_m"]) / int(br["lines"]) > 0.15, "letters big enough to read across the room: %s" % br)


func test_cabinet_near_label_text() -> void:
	var c := ArcadeCabinet.new()
	c.entry = {"id": "cart_x", "title": "Odometer", "kind": "cartridge"}
	var t := c.near_text()
	# One prompt (2026-11-25): the key is the HUD prompt's, shown with the title from the same reach.
	check(not t.contains("press"), "names no key of its own: " + t)
	check(t.contains("free"), "a cartridge is free: " + t)
	c.free()
