extends TestCase
## The arcade dive: the high-score board (pure list logic), Entropy Drift's chain-derived track, the
## input remap a 3D world puts on its 2D game, and the catalog's dive-in worlds.

const H1 := "0x9f3a6c1e2b4d5f60718293a4b5c6d7e8f9a0b1c2d3e4f5061728394a5b6c7d8e"
const H2 := "0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"


func test_scores_insert_and_rank() -> void:
	var b: Array = []
	eq(ArcadeScores.insert(b, {"score": 100, "tx": "0x1"}, 3), 1, "first entry is #1")
	eq(ArcadeScores.insert(b, {"score": 300, "tx": "0x2"}, 3), 1, "a better score goes on top")
	eq(ArcadeScores.insert(b, {"score": 100, "tx": "0x3"}, 3), 3, "a tie ranks below the older entry")
	eq(b.map(func(e): return e["tx"]), ["0x2", "0x1", "0x3"])
	eq(ArcadeScores.insert(b, {"score": 50, "tx": "0x4"}, 3), 0, "off a full board")
	eq(b.size(), 3)
	eq(ArcadeScores.insert(b, {"score": 200, "tx": "0x5"}, 3), 2, "a middle score")
	eq(b.size(), 3, "the board keeps its size")
	eq(b[2]["tx"], "0x1", "the lowest fell off")
	eq(ArcadeScores.insert(b, {"score": 999, "tx": "0x5"}, 3), 2, "the same credit tx is never added twice")
	eq(ArcadeScores.rank_of(b, 250, 3), 2)
	eq(ArcadeScores.rank_of(b, 1, 3), 0)
	eq(ArcadeScores.rank_of([], 0, 3), 1)


func test_scores_text() -> void:
	eq(ArcadeScores.grouped(1234567), "1,234,567")
	eq(ArcadeScores.grouped(12), "12")
	eq(ArcadeScores.grouped(-1500), "-1,500")
	eq(ArcadeScores.short("0x1234567890abcdef1234567890abcdef12345678"), "0x1234…5678")
	var rows := ArcadeScores.lines([{"score": 12340, "wallet": "0x1234567890abcdef1234567890abcdef12345678", "block": 25000123}])
	eq(rows.size(), 1)
	check(rows[0].contains("12,340") and rows[0].contains("0x1234…5678") and rows[0].contains("25,000,123"), "a board row: " + rows[0])
	check(ArcadeScores.LABEL.contains("not on chain"), "the board says it is local")


func test_drift_track_from_chain_bytes() -> void:
	var a := DriftTrack.make("123456789", H1, 25000000)
	var b := DriftTrack.make("123456789", H1, 25000000)
	check(a.ok and b.ok, "a real hash makes a track")
	eq(a.bytes, b.bytes, "same entropy + hash → same track")
	eq(a.seed(), b.seed())
	# SHA-256("123456789:<hash>") straight from HashingContext.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("123456789:" + H1).to_utf8_buffer())
	eq(a.bytes, ctx.finish(), "bytes are SHA-256(entropy:hash)")
	var c := DriftTrack.make("123456789", H2, 25000001)
	check(c.bytes != a.bytes, "another block, another track")
	var d := DriftTrack.make("987654321", H1, 25000000)
	check(d.bytes != a.bytes, "another QING, another track")
	check(DriftTrack.make("123456789", H1.to_upper().replace("0X", "0x")).bytes == a.bytes, "hash case doesn't matter")
	check(a.source.contains("QING.Entropy()") and a.source.contains("25,000,000"), "the source names its inputs: " + a.source)
	var s := a.seed()
	check(s > 0 and s < (1 << 48), "a 48-bit seed")
	# Continuous: no jump at a segment boundary, and bounded.
	var mx := 0.0
	for i in 400:
		var x := i * 37.0
		mx = maxf(mx, absf(a.curve_at(x)))
		check(absf(a.curve_at(x + 0.5) - a.curve_at(x)) < 1e-5, "smooth at %f" % x)
	check(mx <= DriftTrack.MAX_CURVE + 1e-9 and mx > 0.0, "bends, within bounds")
	var seg := DriftTrack.SEG
	check(absf(a.curve_at(seg - 0.001) - a.curve_at(seg + 0.001)) < 1e-6, "continuous across segments")


func test_drift_track_never_invented() -> void:
	for bad in ["", "0x", "0x1234", "not a hash", H1.substr(0, 60)]:
		var t := DriftTrack.make("123456789", bad)
		check(not t.ok, "no track from '%s'" % bad)
		eq(t.seed(), 0)
		eq(t.curve_at(5000.0), 0.0, "flat")
		eq(t.hill_at(5000.0), 0.0, "level")
		check(t.source.contains("—"), "says it read nothing")
	check(not DriftTrack.make("", H1).ok, "no entropy, no track")


func test_input_remap() -> void:
	eq(ArcadeGame.remap_bits(ArcadeGame.IN_LEFT | ArcadeGame.IN_FIRE, {}), ArcadeGame.IN_LEFT | ArcadeGame.IN_FIRE, "no map: as is")
	var w = load("res://scripts/arcade/dive/entropy_drift_world.gd").new()
	var m: Dictionary = w.controls_remap()
	eq(ArcadeGame.remap_bits(ArcadeGame.IN_LEFT, m), ArcadeGame.IN_UP, "steer left = the field's up")
	eq(ArcadeGame.remap_bits(ArcadeGame.IN_RIGHT, m), ArcadeGame.IN_DOWN)
	eq(ArcadeGame.remap_bits(ArcadeGame.IN_UP, m), ArcadeGame.IN_RIGHT, "surge = further ahead")
	eq(ArcadeGame.remap_bits(ArcadeGame.IN_DOWN | ArcadeGame.IN_FIRE, m), ArcadeGame.IN_LEFT | ArcadeGame.IN_FIRE, "fire passes through")
	w.free()
	# A remap doesn't touch scripted (test) input: the 2D game stays deterministic.
	var g = load("res://scripts/arcade/entropy_drift.gd").new()
	g.input_remap = m
	g.start(5)
	g.scripted_input = ArcadeGame.IN_LEFT
	g.step(ArcadeGame.DT)
	eq(g.held, ArcadeGame.IN_LEFT)
	g.free()


func test_catalog_worlds() -> void:
	var n := 0
	for e in ArcadeCatalog.games():
		if not e.has("world"):
			check(e["kind"] == "cartridge", e["id"] + ": only cartridges dive into the classic screen")
			continue
		n += 1
		var s = load(e["world"])
		check(s is GDScript and s.can_instantiate(), e["id"] + " world loads")
		var w = s.new()
		check(w is ArcadeWorld, e["id"] + " world is an ArcadeWorld")
		check(w.controls_hint() != "", e["id"] + " says how to play in 3D")
		var rows: Array = w.controls_list()
		check(rows.size() >= 1, e["id"] + " lists its controls (GameHowto)")
		for r in rows:
			check(String(r[0]) != "" and not String(r[0]).contains("—"), "%s: a control with a bound key: %s" % [e["id"], str(r)])
		w.free()
	eq(n, 3, "the three original games each have a world")


## Each world builds and follows its game for a while, headless (no renderer needed): the attract
## demo, then a run to its end. Any script error shows in the run output.
func test_worlds_follow_their_games() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for e in ArcadeCatalog.GAMES:
		var g: ArcadeGame = load(e["script"]).new()
		var w: ArcadeWorld = load(e["world"]).new()
		root.add_child(g)
		root.add_child(w)
		w.bind(g, {"territory": {"name": "Test", "entropy": "123456789"}, "accent": Color.CYAN})
		check(w.camera != null and w.env != null, e["id"] + " has a camera and an environment")
		g.attract()
		for i in 600:
			g.step(ArcadeGame.DT)
			w._process(ArcadeGame.DT)
		var h: Dictionary = w.hud()
		check(not h.get("stats", PackedStringArray()).is_empty(), e["id"] + " hud stats")
		g.start(42)
		var n := 0
		while g.playing and n < 60 * 300:
			g.scripted_input = 0
			g.step(ArcadeGame.DT)
			w._process(ArcadeGame.DT)
			n += 1
		check(g.over, e["id"] + " run ended")
		w.unbind()
		eq(g.input_remap, {}, e["id"] + " unbind hands the keys back")
		w.free()
		g.free()
