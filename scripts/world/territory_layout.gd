class_name TerritoryLayout
extends RefCounted
## Where things stand on a v2 territory, as numbers (metres, relative to the
## Core at the centre; north is −Z). Pure: every client places the same things
## in the same spots from the same terrain.
##
## The territory edge is JuliaHeightfield.SIZE_M (724 m since 2026-11-24, twice
## the old 512 m in area). Spots that were tuned on the 512 m map scale with
## SCALE, so the attractions spread out over the larger land; the Core's own
## cluster (Room, pylons, wells, arcade, monolith, plinth, skyline) keeps its size.
##
## A new building: find its spot with LandmarkPlan.find_site (round footprint on
## the plateau, flattest, clear of `avoid`), keep it inside BORDER_KEEP_M, add its
## footprint to the keep-outs of the sites placed after it, and pass it to
## TerritoryRoads as a destination so a road reaches its door.

const EDGE_M := JuliaHeightfield.SIZE_M
const HALF_M := EDGE_M * 0.5
const SCALE := EDGE_M / 512.0  ## the v1 edge: spots tuned on it scale by this (√2)
const BORDER_KEEP_M := HALF_M - 24.0  ## footprints stay inside |x|, |z| ≤ this (the force fields stand at HALF_M)
## The Core's own landmarks: Core, arcade, monolith, plinth, arrival.
const CORE_LANDMARKS := [Vector2(0, 0), Vector2(26, 18), Vector2(-26, 18), Vector2(0, -11.5), Vector2(0, 16)]
## Where the player arrives (in front of the Room's door, facing north).
const ARRIVAL := Vector2(0.0, 16.0)
const SITE_GRID_M := 16.0  ## site searches try centres on this grid


## Grid steps (each way from the Core) a site search needs to cover the land.
static func grid_steps(step: float = SITE_GRID_M, reach: float = BORDER_KEEP_M) -> int:
	return ceili(reach / step)


## True when a round footprint at `c` stays inside the border fields.
static func inside(c: Vector2, radius: float) -> bool:
	return maxf(absf(c.x), absf(c.y)) + radius <= BORDER_KEEP_M
