extends Node
## Autoload "GameManager": small, cross-scene session flags only. Chain state
## lives in typed state objects (Registry, Players, Session, TerritoryState);
## nothing chain-shaped is stored here.

const MOTZKIN_PRIME: int = Contracts.MOTZKIN_PRIME

## The territory being visited (set by Travel.go).
var territory_address: String = ""
var territory_name: String = ""
var is_chain_sourced: bool = false
## A border crossing in progress (BorderRing): {address (destination), side
## (the border crossed out of), along (metres along it)}; read once on arrival.
var arrival: Dictionary = {}

## Player view modes.
var is_flying: bool = false
var is_first_person: bool = false

## Visual-only time fraction for systems that animate with the day; the sky's
## real time of day comes from DysnomiaTime (block timestamp).
var time_of_day: float = 0.35
var day_cycle_speed: float = 0.0

signal fly_mode_changed(is_flying: bool)
signal camera_mode_changed(is_first_person: bool)


func toggle_fly_mode() -> void:
	is_flying = not is_flying
	fly_mode_changed.emit(is_flying)


func toggle_camera_mode() -> void:
	is_first_person = not is_first_person
	camera_mode_changed.emit(is_first_person)
