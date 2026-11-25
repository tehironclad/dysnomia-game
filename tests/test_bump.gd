extends TestCase
## Bumping into things (BumpMath, Knockable's pose maths, NetBump): the
## collision impulse, how hard a bump is for a character, the reset rule, and
## the bump messages and the server's check. No network, no physics server.


func test_contact_impulse_conserves_momentum() -> void:
	var n := Vector3.RIGHT
	var j := BumpMath.contact_impulse(Vector3(10, 0, 0), Vector3.ZERO, n, 80.0, 20.0, 0.0)
	# Perfectly inelastic: both end at the common speed 80·10/100 = 8 m/s.
	near(j.x, 160.0, 1e-3, "impulse on the prop")
	near(j.x / 20.0, 8.0, 1e-4, "prop speed after")
	near(10.0 - j.x / 80.0, 8.0, 1e-4, "bumper speed after")
	var je := BumpMath.contact_impulse(Vector3(10, 0, 0), Vector3.ZERO, n, 80.0, 20.0, 1.0)
	near(je.x, 320.0, 1e-3, "elastic is twice the inelastic impulse")


func test_contact_impulse_zero_when_not_closing() -> void:
	eq(BumpMath.contact_impulse(Vector3(-3, 0, 0), Vector3.ZERO, Vector3.RIGHT, 80.0, 5.0), Vector3.ZERO, "moving away")
	eq(BumpMath.contact_impulse(Vector3(3, 0, 0), Vector3(5, 0, 0), Vector3.RIGHT, 80.0, 5.0), Vector3.ZERO, "prop already faster")
	eq(BumpMath.contact_impulse(Vector3(0, 0, 3), Vector3.ZERO, Vector3.RIGHT, 80.0, 5.0), Vector3.ZERO, "sliding past")
	eq(BumpMath.contact_impulse(Vector3(3, 0, 0), Vector3.ZERO, Vector3.RIGHT, 0.0, 5.0), Vector3.ZERO, "massless bumper")


func test_kick_is_capped() -> void:
	var n := Vector3.RIGHT
	var j := BumpMath.kick(Vector3(13, 0, 0), Vector3.ZERO, n, 80.0, 8.0, 6.5, 0.15, 0.0)
	near(j.x / 8.0, 6.5, 1e-4, "a sprint into a bin sends it at the cap")
	eq(BumpMath.kick(Vector3(13, 0, 0), Vector3(6.5, 0, 0), n, 80.0, 8.0, 6.5), Vector3.ZERO, "pushing it again adds nothing past the cap")
	var soft := BumpMath.kick(Vector3(2, 0, 0), Vector3.ZERO, n, 80.0, 40.0, 6.5, 0.0, 0.0)
	near(soft.x / 40.0, 80.0 * 2.0 / 120.0, 1e-4, "a slow push on a barrel: momentum shared")
	var hop := BumpMath.kick(Vector3(5, 0, 0), Vector3.ZERO, n, 80.0, 2.0, 6.5, 0.0, 0.2)
	near(hop.y, hop.x * 0.2, 1e-5, "a little upwards")
	var glance := BumpMath.kick(Vector3(0, 0, -10), Vector3.ZERO, Vector3(0.6, 0, -0.8), 80.0, 5.0, 6.5)
	check(glance.z < 0.0 and glance.x > 0.0, "a glancing blow goes between the heading and the normal")


func test_flat_normal() -> void:
	var n := BumpMath.flat_normal(Vector3(0, 5, 0), Vector3(3, 0, 4))
	near(n.x, 0.6, 1e-5)
	near(n.y, 0.0, 1e-6, "horizontal")
	near(n.z, 0.8, 1e-5)
	var f := BumpMath.flat_normal(Vector3.ONE, Vector3.ONE, Vector3(0, 3, -2))
	near(f.z, -1.0, 1e-5, "coincident: falls back to the motion")
	eq(BumpMath.flat_normal(Vector3.ONE, Vector3.ONE), Vector3.RIGHT, "coincident, no motion")


func test_reaction_levels() -> void:
	var walk := BumpMath.effective_speed(6.0, 80.0)
	var run := BumpMath.effective_speed(14.0, 80.0)
	eq(BumpMath.reaction(BumpMath.effective_speed(0.5, 80.0)), BumpMath.NONE, "standing next to someone")
	eq(BumpMath.reaction(walk), BumpMath.NUDGE, "walking into someone nudges")
	eq(BumpMath.reaction(run), BumpMath.FALL, "running into someone knocks them over")
	eq(BumpMath.reaction(run, false), BumpMath.STUMBLE, "seated or a player: never a fall")
	eq(BumpMath.reaction(BumpMath.effective_speed(9.0, 80.0)), BumpMath.STUMBLE, "a jog: a stumble")
	eq(BumpMath.reaction(BumpMath.effective_speed(5.0, 450.0)), BumpMath.FALL, "a rover at walking pace")
	near(BumpMath.effective_speed(-4.0, 80.0), 0.0, 1e-6, "moving apart is no bump")
	check(BumpMath.cooldown(BumpMath.FALL) > BumpMath.cooldown(BumpMath.STUMBLE), "a fall has the longest cooldown")
	eq(BumpMath.cooldown(BumpMath.NONE), 0.0)


func test_stagger_is_short() -> void:
	check(BumpMath.stagger_seconds(BumpMath.FALL) <= BumpMath.STAGGER_MAX_S, "after knocking someone over")
	eq(BumpMath.stagger_seconds(BumpMath.NONE, 50.0), 0.0, "a light prop: no stagger")
	near(BumpMath.stagger_seconds(BumpMath.NONE, 1e6), BumpMath.STAGGER_MAX_S, 1e-6, "capped")
	check(BumpMath.STAGGER_MAX_S <= 0.6, "the net bump promise: at most 0.6 s")


func test_spring_settles() -> void:
	var s := Vector2(0.0, 5.0)
	for i in 240:
		s = BumpMath.spring_step(s.x, s.y, 0.0, 70.0, 10.0, 1.0 / 60.0)
	near(s.x, 0.0, 1e-3, "back to rest after 4 s")
	near(s.y, 0.0, 1e-2)


func test_pulse() -> void:
	eq(BumpMath.pulse(-1.0, 2.0, 0.2, 0.2), 0.0)
	near(BumpMath.pulse(1.0, 2.0, 0.2, 0.2), 1.0, 1e-6, "held in the middle")
	eq(BumpMath.pulse(2.5, 2.0, 0.2, 0.2), 0.0)


func test_reset_rule() -> void:
	check(not BumpMath.may_reset(5.0, true, false, false), "too soon")
	check(BumpMath.may_reset(30.0, true, false, false), "later, out of view: home")
	check(not BumpMath.may_reset(30.0, true, true, false), "still being looked at")
	check(not BumpMath.may_reset(30.0, true, false, true), "its spot is in view: it would pop in")
	check(not BumpMath.may_reset(200.0, true, true, true), "never in front of you")
	check(BumpMath.may_reset(200.0, false, true, false), "long gone: home once its spot is out of view")
	check(BumpMath.may_reset(3.0, true, false, false, 2.0), "a shorter wait (probes)")


func test_touches() -> void:
	check(BumpMath.touches(Vector3.ZERO, 0.35, 1.8, Vector3(0.5, 0.4, 0), 0.2, 0.4), "beside a bin")
	check(not BumpMath.touches(Vector3.ZERO, 0.35, 1.8, Vector3(0.7, 0.4, 0), 0.2, 0.4), "just clear")
	check(not BumpMath.touches(Vector3(0, 3, 0), 0.35, 1.8, Vector3(0.2, 0.4, 0), 0.2, 0.4), "flying over it")
	check(BumpMath.touches(Vector3(0, 0.6, 0), 0.35, 1.8, Vector3(0.2, 0.4, 0), 0.2, 0.4), "flying low: feet at the top of it")
	check(not BumpMath.touches(Vector3(0, -3, 0), 0.35, 1.8, Vector3(0.2, 0.4, 0), 0.2, 0.4), "under it")


func test_dir_quantisation() -> void:
	for yaw in [0.0, 1.0, -2.0, 3.1, TAU - 0.01]:
		var back := BumpMath.dequant_dir(BumpMath.quant_dir(yaw))
		near(absf(wrapf(back - yaw, -PI, PI)), 0.0, TAU / 256.0, "yaw %s" % yaw)
	var d := Vector3(0.6, 0.0, -0.8)
	near(BumpMath.dir_of(BumpMath.yaw_of(d)).distance_to(d), 0.0, 1e-5, "dir ↔ yaw")
	near(BumpMath.dir_of(0.0).z, -1.0, 1e-6, "yaw 0 is forward (-Z)")


func test_knockable_pose_maths() -> void:
	var k := Knockable.new()
	k.center = Vector3(0, 0.5, 0)
	k.size = Vector3(0.6, 1.0, 0.6)
	k.home = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(2, 1.5, 2)), Vector3(3, 1, -2))
	var b := k.body_xf(k.home)
	near(b.origin.distance_to(Vector3(3, 1.75, -2)), 0.0, 1e-5, "the body sits at the shape's centre")
	near(absf(b.basis.determinant()), 1.0, 1e-5, "no scale on the body")
	var back := k.mesh_xf(b)
	near(back.origin.distance_to(k.home.origin), 0.0, 1e-5, "and back: the same origin")
	near((back.basis.x - k.home.basis.x).length() + (back.basis.y - k.home.basis.y).length(), 0.0, 1e-4, "and basis")
	var gs := k.global_size()
	near(gs.y, 1.5, 1e-5, "global height")
	near(gs.x, 1.2, 1e-5, "global width")
	k.update_bounds(k.home)
	near(k.half_h, 0.75, 1e-4, "half height upright")
	# Lying on its side: wide and low.
	var lying := Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(2, 1.5, 2)), Vector3.ZERO)
	k.update_bounds(lying)
	near(k.half_h, 0.6, 1e-4, "half height on its side")
	check(k.radius > 0.5, "longer on the ground")
	k.free()


func test_net_bump_roundtrip() -> void:
	var m := NetBump.bump_msg(513, 1.25, BumpMath.STUMBLE)
	eq(m.size(), 5, "C_BUMP is 5 bytes")
	check(NetProto.size_ok(m), "the server's size check takes it")
	check(not NetProto.size_ok(m.slice(0, 4)), "short refused")
	var d := NetBump.unpack_bump(m)
	eq(int(d["target"]), 513)
	eq(int(d["level"]), BumpMath.STUMBLE)
	near(float(d["dir"]), 1.25, TAU / 256.0, "direction")
	var r := NetBump.relay(7, d)
	eq(r.size(), 7, "S_BUMP is 7 bytes")
	var e := NetBump.unpack_relay(r)
	eq(int(e["from"]), 7)
	eq(int(e["target"]), 513)
	eq(int(e["level"]), BumpMath.STUMBLE)
	near(float(e["dir"]), 1.25, TAU / 256.0)


func test_net_bump_caps_and_refuses() -> void:
	eq(int(NetBump.unpack_bump(NetBump.bump_msg(2, 0.0, BumpMath.FALL))["level"]), BumpMath.STUMBLE, "no knock-downs over the net")
	var bad := NetBump.bump_msg(2, 0.0, BumpMath.STUMBLE)
	bad[4] = 9
	check(NetBump.unpack_bump(bad).is_empty(), "an unknown level is malformed")
	bad[4] = 0
	check(NetBump.unpack_bump(bad).is_empty(), "level NONE is malformed")
	check(NetBump.unpack_bump(PackedByteArray([NetBump.C_BUMP, 1, 2])).is_empty(), "truncated")
	check(NetBump.unpack_relay(PackedByteArray([NetBump.S_BUMP])).is_empty(), "truncated relay")
	check(not NetProto.MAX_SIZE.has(NetBump.C_BUMP), "its own number, apart from the core types")
	check(not NetProto.MAX_SIZE.has(NetBump.S_BUMP))


func test_net_bump_server_check() -> void:
	var a := Vector3(0, 0, 0)
	eq(NetBump.check(1, 2, true, true, a, Vector3(1.0, 0, 1.0), 99.0), "", "close, same room: relayed")
	eq(NetBump.check(1, 1, true, true, a, a, 99.0), "self")
	eq(NetBump.check(1, 2, false, true, a, a, 99.0), "not in the same room")
	eq(NetBump.check(1, 2, true, false, a, a, 99.0), "no position yet")
	eq(NetBump.check(1, 2, true, true, a, Vector3(10, 0, 0), 99.0), "too far apart")
	eq(NetBump.check(1, 2, true, true, a, a, 0.5), "cooldown", "no knock-down spam")
