class_name PlayerGear
extends Node3D
## Gear earned from chain facts only (the site's lib/avatar.js rules):
##   no bars anywhere      → the bear is drawn grey
##   bars at 3+ territories → an orbiting spark;  at 10+ → an orbit ring
##   leading any territory → a halo (a floor: among known players)
##   ladder rank 1         → a crown (only if the site's ladder confirms it)
## Plus the player's Aura fractal as a patch on the left arm (the chest carries
## every suit's Ⓐ), the head their LAU's name/symbol asks for (AvatarHeads) and
## the outfit their wallet draws (Outfits), or the ones they picked locally.

var _spark: MeshInstance3D
var _ring: MeshInstance3D
var _halo: MeshInstance3D
var _crown: MeshInstance3D
var _patch_tex: Texture2D  # the Aura fractal, worn as the left-arm patch
var _view: DeepFieldView
var _t := 0.0


static func _glow(c: Color, e: float = 2.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _ready() -> void:
	_spark = MeshInstance3D.new()
	var sp := SphereMesh.new()  # a faceted diamond, so it never reads as a bird
	sp.radius = 0.055
	sp.height = 0.16
	sp.radial_segments = 4
	sp.rings = 2
	_spark.mesh = sp
	_spark.material_override = _glow(DeepFieldTheme.ICE)
	add_child(_spark)
	_ring = MeshInstance3D.new()
	var tr := TorusMesh.new()
	tr.inner_radius = 0.62
	tr.outer_radius = 0.66
	_ring.mesh = tr
	_ring.material_override = _glow(DeepFieldTheme.ICE, 1.4)
	_ring.position.y = 1.0
	add_child(_ring)
	_halo = MeshInstance3D.new()
	var th := TorusMesh.new()
	th.inner_radius = 0.2
	th.outer_radius = 0.24
	_halo.mesh = th
	_halo.material_override = _glow(Color("#ffd27a"), 3.0)
	_halo.position.y = 2.0
	add_child(_halo)
	_crown = MeshInstance3D.new()
	var cr := CylinderMesh.new()
	cr.top_radius = 0.2
	cr.bottom_radius = 0.16
	cr.height = 0.12
	cr.radial_segments = 7
	_crown.mesh = cr
	_crown.material_override = _glow(Color("#ffd59a"), 3.0)
	_crown.position.y = 1.92
	add_child(_crown)
	# Aura emblem on the chest.
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	_view = DeepFieldView.new()
	_view.size = Vector2(128, 128)
	_view.max_iter = 100
	vp.add_child(_view)
	add_child(vp)
	DeepFieldView.throttle(vp, 4.0)
	_patch_tex = vp.get_texture()
	_apply(false, 0, false, false)
	Session.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var w := Session.wallet
	if w != "":
		_view.apply_params(DeepField.for_identity(w))
	_apply(Session.bars.size() > 0, Session.bars.size(), Session.leading.size() > 0, Session.ladder_rank == 1)
	var model := get_parent().get_node_or_null("PlayerModel")
	if model and model.has_method("set_arm_patch"):
		model.set_arm_patch(_patch_tex if w != "" else null)
	if model and Session.player != null:
		if Session.player.soul != "":
			model.apply_appearance(PlayerAppearance.from_identity(Session.player.soul, Session.player.aura))
		model.set_crow(Session.player.is_bouncer())
		# The head: the LAU's own on-chain text decides (🐀👑 RatKing → rat + crown),
		# unless the player picked one for themselves on this machine.
		var ps: PlayerState = Session.player
		if model.has_method("set_body"):
			model.set_body(AvatarHeads.local_body(w))
		# The outfit: from the wallet alone (what every viewer sees), unless the
		# player picked one for themselves on this machine (their own screen only).
		if model.has_method("wear_identity"):
			var own := Outfits.local_choice(w)
			if own != "":
				model.set_outfit(own, int(Outfits.for_identity(w)["seed"]))
			else:
				model.wear_identity(w)
		var pick := AvatarHeads.local_choice(w)
		model.set_head(pick if pick != "" else ps.head_kind(), AvatarHeads.accessories_for(ps.username, ps.lau_name, ps.lau_symbol))
		# No bars anywhere: the bear is drawn grey (no colour until it has acted).
		model.modulate_grey(Session.bars.is_empty())


func _apply(has_bars: bool, n: int, leads: bool, first: bool) -> void:
	_spark.visible = n >= 3
	_ring.visible = n >= 10
	_halo.visible = leads
	_crown.visible = first


func _process(delta: float) -> void:
	_t += delta
	if _spark.visible:
		_spark.position = Vector3(cos(_t * 1.6) * 0.7, 1.3 + 0.1 * sin(_t * 2.3), sin(_t * 1.6) * 0.7)
		_spark.rotation.y = _t * 3.0
	if _ring.visible:
		_ring.rotation = Vector3(0.4 * sin(_t * 0.3), _t * 0.5, 0.3)
