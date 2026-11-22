class_name Coords
extends RefCounted
## Territory coordinates. HECKE.Compliment(waat) returns two ~240-bit int256
## words (lon, lat). Raw words stay BigInt/hex; degrees exist only for drawing
## the Field map. See docs/LEARNINGS.md §6.
##
## IMPORTANT: map adjacency is meaningless on chain; the projection is a
## modular hash. Never infer relationships from degree distance.

const LON_MOD := 360000000
const LAT_MOD := 180000000


## Projects raw Compliment words (read UNSIGNED, as the site does) to degrees.
## Matches scripts/build-qing-registry.js and lib/chain-live.js in entropy-ai-pulse.
## Returns [lat, lon] as 64-bit floats (Vector2 would truncate to float32).
static func project(lon_word_hex: String, lat_word_hex: String) -> PackedFloat64Array:
	var lon := float(BigInt.mod_int(BigInt.from_hex(lon_word_hex), LON_MOD)) / 1e6 - 180.0
	var lat := float(BigInt.mod_int(BigInt.from_hex(lat_word_hex), LAT_MOD)) / 1e6 - 90.0
	return PackedFloat64Array([lat, lon])


## Unit-sphere position for a (lat, lon) pair in degrees (y up).
static func to_sphere(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
