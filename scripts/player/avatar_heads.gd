class_name AvatarHeads
extends RefCounted
## Heads for the LAU avatar. Which head a player wears comes from their LAU's
## own on-chain text: LAU.Username(), name() and symbol(). RatKing's symbol is
## 🐀👑, so RatKing is a rat with a crown. Anyone whose text names no creature
## stays the clockwork LAU bear. A player may also pick a head for their own
## avatar; that choice is local (user://identity.cfg) and labelled as such.
##
## "human" keeps the body's own human head (nothing is built).
## Heads are built around a neck pivot: +Y up, +Z the face, origin at the neck.

const KINDS := ["bear", "human", "rat", "alien", "frog", "dog", "cat", "skull", "robot", "hamster", "fox", "pig", "ape", "bird"]
const ACCESSORIES := ["crown", "halo", "horns", "wizard"]
const LOCAL_PATH := "user://identity.cfg"

## kind → [words, emoji]. Words match whole tokens (letters only, lower case).
const RULES := {
	"rat": [["rat", "rats", "ratking", "ratqueen", "mouse", "mice", "rodent"], ["🐀", "🐁", "🐭"]],
	"alien": [["alien", "aliens", "ufo", "martian", "extraterrestrial", "xeno"], ["👽", "👾", "🛸"]],
	"frog": [["frog", "frogs", "pepe", "toad", "froggy"], ["🐸"]],
	"dog": [["dog", "dogs", "doge", "doggo", "shib", "shiba", "puppy", "pup", "woof"], ["🐶", "🐕", "🦮", "🐩"]],
	"cat": [["cat", "cats", "kitty", "kitten", "meow", "neko"], ["🐱", "🐈", "😺", "😸", "😼"]],
	"skull": [["skull", "skeleton", "bones", "reaper", "dead", "death"], ["☠", "💀"]],
	"robot": [["robot", "bot", "droid", "android", "cyborg", "mech"], ["🤖"]],
	"hamster": [["hamster", "guinea", "cavy", "gerbil"], ["🐹"]],
	"fox": [["fox", "foxy", "kitsune"], ["🦊"]],
	"pig": [["pig", "piggy", "hog", "swine", "pork", "oink"], ["🐷", "🐖", "🐽"]],
	"ape": [["ape", "apes", "monkey", "gorilla", "chimp", "kong"], ["🐵", "🐒", "🦍", "🙈"]],
	"bird": [["bird", "crow", "raven", "owl", "eagle", "hawk", "chick", "chicken", "duck", "parrot"], ["🐦", "🐣", "🐤", "🦉", "🦅", "🐔", "🦆", "🦜"]],
	"bear": [["bear", "teddy", "bears"], ["🐻", "🧸"]],
}
const ACCESSORY_RULES := {
	"crown": [["king", "queen", "royal", "crown", "emperor", "prince", "princess", "ratking", "ratqueen"], ["👑"]],
	"halo": [["angel", "saint", "holy", "zeus", "god"], ["😇"]],
	"horns": [["devil", "demon", "satan", "imp"], ["😈", "👿", "👹"]],
	"wizard": [["wizard", "mage", "sorcerer", "witch", "warlock"], ["🧙", "🔮"]],
}


static func _tokens(text: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("[a-z]+")
	for m in re.search_all(text.to_lower()):
		out[m.get_string()] = true
	return out


static func _matches(text: String, toks: Dictionary, rule: Array) -> bool:
	for w in rule[0]:
		if toks.has(w):
			return true
	for e in rule[1]:
		if text.contains(e):
			return true
	return false


## Pure: the head a LAU's on-chain text asks for ("bear" when it names none).
## The first creature named wins, in the order: username, name, symbol.
static func kind_for(username: String, lau_name: String, symbol: String) -> String:
	for part in [username, lau_name, symbol]:
		var toks := _tokens(part)
		for k in RULES:
			if k != "bear" and _matches(part, toks, RULES[k]):
				return k
	return "bear"


static func accessories_for(username: String, lau_name: String, symbol: String) -> Array:
	var text := "%s %s %s" % [username, lau_name, symbol]
	var toks := _tokens(text)
	var out: Array = []
	for a in ACCESSORY_RULES:
		if _matches(text, toks, ACCESSORY_RULES[a]):
			out.append(a)
	return out


## The local head choice for a wallet ("" = use the chain-derived one).
static func local_choice(wallet: String) -> String:
	var c := ConfigFile.new()
	c.load(LOCAL_PATH)
	return String(c.get_value("heads", wallet.to_lower(), ""))


static func set_local_choice(wallet: String, kind: String) -> void:
	var c := ConfigFile.new()
	c.load(LOCAL_PATH)
	c.set_value("heads", wallet.to_lower(), kind)
	c.save(LOCAL_PATH)


# --- Building ------------------------------------------------------------------------

static func _mat(c: Color, rough: float = 0.75, metal: float = 0.0, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


static func _sphere(parent: Node3D, r: float, m: Material, at: Vector3, sc: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.position = at
	mi.scale = sc
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, top: float, bottom: float, h: float, m: Material, at: Vector3, rot: Vector3 = Vector3.ZERO, sides: int = 16) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = at
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, m: Material, at: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = m
	mi.position = at
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


static func _eyes(p: Node3D, y: float, x: float, z: float, r: float, iris: Color = Color(0.02, 0.02, 0.03)) -> void:
	var white := _mat(Color(0.95, 0.95, 0.92), 0.25)
	var pupil := _mat(iris, 0.1, 0.2)
	var shine := _mat(Color.WHITE, 0.1, 0.0, 1.5)
	for sx in [-1.0, 1.0]:
		_sphere(p, r, white, Vector3(sx * x, y, z))
		_sphere(p, r * 0.6, pupil, Vector3(sx * x, y, z + r * 0.55))
		_sphere(p, r * 0.18, shine, Vector3(sx * x + r * 0.2, y + r * 0.25, z + r * 0.9))


static func _whiskers(p: Node3D, y: float, z: float, span: float) -> void:
	var w := _mat(Color(0.9, 0.9, 0.88), 0.4)
	for sx in [-1.0, 1.0]:
		for i in 3:
			_box(p, Vector3(span, 0.004, 0.004), w, Vector3(sx * span * 0.55, y + (i - 1) * 0.018, z), Vector3(0, sx * -8.0, sx * (i - 1) * 9.0))


## Builds a head of `kind` under a new Node3D, the face along +Z, the neck at
## the origin. `tint` nudges the fur/skin colour per identity.
static func build(kind: String, tint: Color = Color(0.5, 0.5, 0.5)) -> Node3D:
	var p := Node3D.new()
	p.name = "Head_" + kind
	match kind:
		"bear": _bear(p, tint)
		"rat": _rat(p, tint)
		"alien": _alien(p, tint)
		"frog": _frog(p, tint)
		"dog": _dog(p, tint)
		"cat": _cat(p, tint)
		"skull": _skull(p)
		"robot": _robot(p, tint)
		"hamster": _hamster(p)
		"fox": _fox(p)
		"pig": _pig(p)
		"ape": _ape(p)
		"bird": _bird(p, tint)
	return p


static func _bear(p: Node3D, tint: Color) -> void:
	var fur := _mat(Color(0.52, 0.36, 0.22).lerp(tint, 0.15), 0.95)
	var tan := _mat(Color(0.82, 0.68, 0.5), 0.9)
	_sphere(p, 0.21, fur, Vector3(0, 0.23, 0), Vector3(1.08, 0.92, 0.98))
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.075, fur, Vector3(sx * 0.17, 0.41, -0.03), Vector3(1.0, 1.0, 0.65))
		_sphere(p, 0.045, tan, Vector3(sx * 0.17, 0.41, 0.0), Vector3(1.0, 1.0, 0.4))
	_sphere(p, 0.1, tan, Vector3(0, 0.17, 0.15), Vector3(1.15, 0.85, 0.9))
	_sphere(p, 0.035, _mat(Color(0.05, 0.03, 0.03), 0.25), Vector3(0, 0.2, 0.245), Vector3(1.3, 0.85, 0.9))
	_box(p, Vector3(0.05, 0.006, 0.01), _mat(Color(0.12, 0.06, 0.05)), Vector3(0, 0.135, 0.235))
	_eyes(p, 0.28, 0.085, 0.17, 0.032, Color(0.12, 0.07, 0.03))


static func _rat(p: Node3D, tint: Color) -> void:
	var fur := _mat(Color(0.42, 0.40, 0.42).lerp(tint, 0.12), 0.9)
	var pink := _mat(Color(0.93, 0.62, 0.66), 0.6)
	_sphere(p, 0.2, fur, Vector3(0, 0.22, -0.01), Vector3(1.0, 0.92, 1.05))
	_cyl(p, 0.035, 0.15, 0.26, fur, Vector3(0, 0.17, 0.2), Vector3(90, 0, 0))  # the long snout
	_sphere(p, 0.035, pink, Vector3(0, 0.17, 0.335))
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.11, fur, Vector3(sx * 0.15, 0.4, -0.04), Vector3(1.0, 1.0, 0.32))
		_sphere(p, 0.08, pink, Vector3(sx * 0.15, 0.4, -0.015), Vector3(1.0, 1.0, 0.2))
	_eyes(p, 0.27, 0.085, 0.15, 0.03, Color(0.35, 0.02, 0.04))
	var tooth := _mat(Color(0.98, 0.95, 0.82), 0.3)
	_box(p, Vector3(0.022, 0.04, 0.012), tooth, Vector3(-0.012, 0.115, 0.29))
	_box(p, Vector3(0.022, 0.04, 0.012), tooth, Vector3(0.012, 0.115, 0.29))
	_whiskers(p, 0.17, 0.3, 0.16)


static func _alien(p: Node3D, tint: Color) -> void:
	var skin := _mat(Color(0.55, 0.78, 0.55).lerp(tint, 0.1), 0.45, 0.05)
	_sphere(p, 0.22, skin, Vector3(0, 0.3, 0), Vector3(1.0, 1.15, 1.0))  # the cranium
	_sphere(p, 0.085, skin, Vector3(0, 0.13, 0.05), Vector3(1.0, 1.1, 0.9))  # the narrow chin
	var eye := _mat(Color(0.01, 0.01, 0.02), 0.08, 0.3)
	for sx in [-1.0, 1.0]:
		var e := _sphere(p, 0.08, eye, Vector3(sx * 0.088, 0.25, 0.185), Vector3(1.0, 0.55, 0.42))
		e.rotation_degrees.z = sx * -30.0
		_sphere(p, 0.012, _mat(Color(0.8, 1.0, 0.9), 0.1, 0.0, 2.0), Vector3(sx * 0.075, 0.27, 0.218))
	_box(p, Vector3(0.045, 0.006, 0.01), _mat(Color(0.2, 0.3, 0.2)), Vector3(0, 0.1, 0.125))
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.008, _mat(Color(0.25, 0.4, 0.25)), Vector3(sx * 0.012, 0.165, 0.19))


static func _frog(p: Node3D, tint: Color) -> void:
	var skin := _mat(Color(0.33, 0.62, 0.22).lerp(tint, 0.08), 0.55)
	_sphere(p, 0.22, skin, Vector3(0, 0.2, 0.02), Vector3(1.25, 0.78, 1.05))
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.085, skin, Vector3(sx * 0.11, 0.34, 0.08))
	_eyes(p, 0.35, 0.11, 0.13, 0.06)
	var lip := _mat(Color(0.55, 0.32, 0.22), 0.5)
	var mouth := _cyl(p, 0.012, 0.012, 0.3, lip, Vector3(0, 0.15, 0.2), Vector3(0, 0, 90))
	mouth.scale = Vector3(1.0, 1.0, 1.4)
	_cyl(p, 0.012, 0.012, 0.26, lip, Vector3(0, 0.13, 0.19), Vector3(0, 0, 90))


static func _dog(p: Node3D, tint: Color) -> void:
	var fur := _mat(Color(0.72, 0.52, 0.28).lerp(tint, 0.1), 0.9)
	var light := _mat(Color(0.92, 0.84, 0.7), 0.9)
	_sphere(p, 0.2, fur, Vector3(0, 0.25, 0), Vector3(1.0, 0.95, 1.0))
	_box(p, Vector3(0.15, 0.11, 0.2), light, Vector3(0, 0.17, 0.17))
	_sphere(p, 0.035, _mat(Color(0.03, 0.03, 0.03), 0.2), Vector3(0, 0.215, 0.275), Vector3(1.3, 0.9, 1.0))
	_box(p, Vector3(0.05, 0.012, 0.07), _mat(Color(0.85, 0.35, 0.4), 0.4), Vector3(0, 0.11, 0.24), Vector3(20, 0, 0))
	for sx in [-1.0, 1.0]:
		var ear := _sphere(p, 0.09, _mat(Color(0.42, 0.28, 0.14), 0.9), Vector3(sx * 0.19, 0.24, -0.02), Vector3(0.45, 1.5, 0.8))
		ear.rotation_degrees.z = sx * 12.0
	_eyes(p, 0.3, 0.075, 0.16, 0.035)


static func _cat(p: Node3D, tint: Color) -> void:
	var fur := _mat(Color(0.55, 0.55, 0.58).lerp(tint, 0.18), 0.9)
	_sphere(p, 0.2, fur, Vector3(0, 0.24, 0), Vector3(1.08, 0.92, 1.0))
	for sx in [-1.0, 1.0]:
		var ear := _cyl(p, 0.0, 0.075, 0.15, fur, Vector3(sx * 0.12, 0.42, -0.01), Vector3(0, 0, sx * -18.0), 4)
		ear.scale = Vector3(1.0, 1.0, 0.5)
	_sphere(p, 0.07, _mat(Color(0.9, 0.88, 0.85), 0.9), Vector3(0, 0.17, 0.15), Vector3(1.3, 0.8, 0.8))
	_sphere(p, 0.02, _mat(Color(0.9, 0.45, 0.5), 0.4), Vector3(0, 0.2, 0.205))
	var eye := _mat(Color(0.55, 0.85, 0.25), 0.15, 0.0, 0.4)
	var slit := _mat(Color(0.01, 0.01, 0.01), 0.1)
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.04, eye, Vector3(sx * 0.075, 0.28, 0.165))
		_box(p, Vector3(0.008, 0.05, 0.01), slit, Vector3(sx * 0.075, 0.28, 0.203))
	_whiskers(p, 0.18, 0.2, 0.17)


static func _skull(p: Node3D) -> void:
	var bone := _mat(Color(0.9, 0.87, 0.78), 0.6)
	var dark := _mat(Color(0.02, 0.01, 0.01), 0.9)
	_sphere(p, 0.2, bone, Vector3(0, 0.27, 0), Vector3(1.0, 1.0, 1.08))
	_box(p, Vector3(0.2, 0.08, 0.16), bone, Vector3(0, 0.1, 0.07))
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.05, dark, Vector3(sx * 0.075, 0.26, 0.16), Vector3(1.0, 0.85, 0.6))
		_sphere(p, 0.012, _mat(Color(1.0, 0.25, 0.2), 0.1, 0.0, 3.0), Vector3(sx * 0.075, 0.26, 0.175))
	_sphere(p, 0.025, dark, Vector3(0, 0.19, 0.2), Vector3(0.8, 1.2, 0.6))
	for i in 6:
		_box(p, Vector3(0.022, 0.03, 0.01), bone, Vector3(-0.0625 + i * 0.025, 0.135, 0.152))


static func _robot(p: Node3D, tint: Color) -> void:
	var metal := _mat(Color(0.62, 0.65, 0.7), 0.3, 0.85)
	var accent := _mat(Color(0.3, 0.85, 1.0).lerp(tint, 0.3), 0.2, 0.0, 2.5)
	_box(p, Vector3(0.34, 0.3, 0.3), metal, Vector3(0, 0.24, 0))
	_box(p, Vector3(0.28, 0.06, 0.02), accent, Vector3(0, 0.28, 0.152))  # the visor strip
	_box(p, Vector3(0.18, 0.03, 0.02), _mat(Color(0.1, 0.1, 0.12), 0.5, 0.6), Vector3(0, 0.15, 0.152))
	for sx in [-1.0, 1.0]:
		_cyl(p, 0.04, 0.04, 0.04, metal, Vector3(sx * 0.19, 0.24, 0), Vector3(0, 0, 90))
	_cyl(p, 0.008, 0.008, 0.14, metal, Vector3(0.08, 0.45, 0))
	_sphere(p, 0.022, accent, Vector3(0.08, 0.53, 0))


static func _hamster(p: Node3D) -> void:
	var fur := _mat(Color(0.86, 0.58, 0.3), 0.95)
	var cream := _mat(Color(0.98, 0.92, 0.82), 0.95)
	_sphere(p, 0.21, fur, Vector3(0, 0.22, 0), Vector3(1.12, 0.95, 1.0))
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.1, cream, Vector3(sx * 0.11, 0.16, 0.1))  # stuffed cheeks
		_sphere(p, 0.055, fur, Vector3(sx * 0.13, 0.4, -0.02), Vector3(1.0, 1.0, 0.45))
	_sphere(p, 0.05, cream, Vector3(0, 0.18, 0.17))
	_sphere(p, 0.018, _mat(Color(0.9, 0.5, 0.55), 0.4), Vector3(0, 0.2, 0.215))
	_eyes(p, 0.27, 0.085, 0.165, 0.028)


static func _fox(p: Node3D) -> void:
	var fur := _mat(Color(0.88, 0.42, 0.12), 0.9)
	var white := _mat(Color(0.97, 0.95, 0.9), 0.9)
	var dark := _mat(Color(0.12, 0.08, 0.06), 0.9)
	_sphere(p, 0.19, fur, Vector3(0, 0.25, 0), Vector3(1.1, 0.95, 1.0))
	_cyl(p, 0.025, 0.11, 0.2, white, Vector3(0, 0.18, 0.18), Vector3(90, 0, 0))
	_sphere(p, 0.03, dark, Vector3(0, 0.18, 0.285))
	for sx in [-1.0, 1.0]:
		var ear := _cyl(p, 0.0, 0.08, 0.2, fur, Vector3(sx * 0.12, 0.45, -0.02), Vector3(0, 0, sx * -14.0), 4)
		ear.scale = Vector3(1.0, 1.0, 0.45)
		_cyl(p, 0.0, 0.03, 0.06, dark, Vector3(sx * 0.143, 0.53, -0.02), Vector3(0, 0, sx * -14.0), 4)
	_eyes(p, 0.29, 0.08, 0.15, 0.03, Color(0.4, 0.25, 0.02))


static func _pig(p: Node3D) -> void:
	var skin := _mat(Color(0.96, 0.7, 0.72), 0.6)
	var deep := _mat(Color(0.8, 0.45, 0.5), 0.5)
	_sphere(p, 0.21, skin, Vector3(0, 0.23, 0))
	_cyl(p, 0.07, 0.075, 0.07, skin, Vector3(0, 0.19, 0.2), Vector3(90, 0, 0))
	for sx in [-1.0, 1.0]:
		_cyl(p, 0.014, 0.014, 0.02, deep, Vector3(sx * 0.025, 0.19, 0.236), Vector3(90, 0, 0))
		var ear := _cyl(p, 0.0, 0.07, 0.13, skin, Vector3(sx * 0.15, 0.41, 0.02), Vector3(30, 0, sx * -30.0), 4)
		ear.scale = Vector3(1.0, 1.0, 0.4)
	_eyes(p, 0.29, 0.08, 0.17, 0.026)


static func _ape(p: Node3D) -> void:
	var fur := _mat(Color(0.2, 0.14, 0.1), 0.95)
	var face := _mat(Color(0.62, 0.48, 0.38), 0.8)
	_sphere(p, 0.21, fur, Vector3(0, 0.25, -0.02), Vector3(1.05, 1.0, 1.0))
	_sphere(p, 0.15, face, Vector3(0, 0.2, 0.08), Vector3(1.05, 1.0, 0.8))
	_box(p, Vector3(0.24, 0.035, 0.07), fur, Vector3(0, 0.31, 0.15))  # the brow ridge
	for sx in [-1.0, 1.0]:
		_sphere(p, 0.05, face, Vector3(sx * 0.21, 0.25, -0.01), Vector3(0.5, 1.0, 1.0))
		_sphere(p, 0.011, _mat(Color(0.1, 0.06, 0.05)), Vector3(sx * 0.018, 0.21, 0.2))
	_eyes(p, 0.27, 0.06, 0.17, 0.025, Color(0.2, 0.1, 0.03))
	_box(p, Vector3(0.09, 0.008, 0.01), _mat(Color(0.25, 0.12, 0.1)), Vector3(0, 0.13, 0.195))


static func _bird(p: Node3D, tint: Color) -> void:
	var feathers := _mat(Color(0.12, 0.12, 0.16).lerp(tint, 0.25), 0.7, 0.1)
	var beak := _mat(Color(0.98, 0.72, 0.15), 0.4)
	_sphere(p, 0.2, feathers, Vector3(0, 0.25, 0))
	_cyl(p, 0.0, 0.055, 0.14, beak, Vector3(0, 0.22, 0.24), Vector3(90, 0, 0), 4)
	for i in 3:
		var crest := _cyl(p, 0.0, 0.03, 0.14, feathers, Vector3(0, 0.46, -0.04 - i * 0.05), Vector3(-25.0 - i * 15.0, 0, 0), 4)
		crest.scale = Vector3(0.5, 1.0, 1.0)
	_eyes(p, 0.29, 0.09, 0.14, 0.035, Color(0.6, 0.35, 0.02))


## An accessory sitting on a head of height `top` (metres above the neck).
static func accessory(kind: String, top: float = 0.46) -> Node3D:
	var p := Node3D.new()
	p.name = "Acc_" + kind
	match kind:
		"crown":
			var gold := _mat(Color(1.0, 0.78, 0.2), 0.25, 0.9, 0.3)
			_cyl(p, 0.13, 0.12, 0.06, gold, Vector3(0, top, 0), Vector3.ZERO, 24)
			for i in 6:
				var a := TAU * i / 6.0
				_cyl(p, 0.0, 0.025, 0.08, gold, Vector3(cos(a) * 0.12, top + 0.07, sin(a) * 0.12), Vector3.ZERO, 4)
				_sphere(p, 0.013, _mat(Color(0.9, 0.1, 0.2), 0.1, 0.2, 1.0), Vector3(cos(a) * 0.125, top + 0.015, sin(a) * 0.125))
		"halo":
			var t := TorusMesh.new()
			t.inner_radius = 0.12
			t.outer_radius = 0.145
			var mi := MeshInstance3D.new()
			mi.mesh = t
			mi.material_override = _mat(Color(1.0, 0.95, 0.7), 0.2, 0.0, 3.0)
			mi.position = Vector3(0, top + 0.12, 0)
			p.add_child(mi)
		"horns":
			var red := _mat(Color(0.55, 0.05, 0.05), 0.4, 0.1)
			for sx in [-1.0, 1.0]:
				_cyl(p, 0.0, 0.035, 0.14, red, Vector3(sx * 0.1, top - 0.02, 0.02), Vector3(0, 0, sx * -25.0), 8)
		"wizard":
			var cloth := _mat(Color(0.18, 0.12, 0.45), 0.9)
			_cyl(p, 0.2, 0.2, 0.015, cloth, Vector3(0, top - 0.03, 0), Vector3.ZERO, 24)
			var cone := _cyl(p, 0.0, 0.13, 0.34, cloth, Vector3(0, top + 0.14, -0.02), Vector3(-10, 0, 0), 16)
			cone.scale = Vector3.ONE
			_sphere(p, 0.02, _mat(Color(1.0, 0.9, 0.4), 0.2, 0.0, 2.5), Vector3(0, top + 0.12, 0.08))
	return p
