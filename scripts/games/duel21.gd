class_name Duel21
extends RefCounted
## Twenty-One, head to head, dealt by the chain. Every card comes from one
## 52-card deck, drawn with SHA-256(block hash : draw number) modulo the cards
## left, where the block is the one that holds the line asking for it: the
## deal comes from the accept line's block, each hit from its own line's
## block. Nobody knows a card before their line is mined.
##
## Player 0 (the challenger) acts first: hit until standing or bust; then
## player 1. Closer to 21 without going over wins; a tie is a push (no
## winner). Aces count 11 or 1. Everything is public: it's a race, not a bluff.

const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUITS := ["♠", "♥", "♦", "♣"]

var deck: Array = []
var hands := [[], []]
var turn := 0
var stood := [false, false]
var winner := -1  # -1 none yet, 2 = push
var draws := 0
var dealt := false


func _init() -> void:
	deck = range(52)


static func card_name(c: int) -> String:
	return RANKS[c % 13] + SUITS[c / 13]


static func total(hand: Array) -> int:
	var t := 0
	var aces := 0
	for c in hand:
		var r: int = c % 13
		if r == 0:
			aces += 1
			t += 11
		elif r >= 9:
			t += 10
		else:
			t += r + 1
	while t > 21 and aces > 0:
		t -= 10
		aces -= 1
	return t


func over() -> bool:
	return winner != -1


## One card for `player`, from `block_hash` (0x… 32 bytes) and the running draw count.
func _draw(player: int, block_hash: String) -> int:
	var h := ("%s:%d" % [block_hash.to_lower(), draws]).sha256_text()
	draws += 1
	var n := h.substr(0, 14).hex_to_int()  # 56 bits: always positive
	var c: int = deck[n % deck.size()]
	deck.erase(c)
	hands[player].append(c)
	return c


## Two cards each (0, 1, 0, 1) from the accept line's block.
func deal(block_hash: String) -> void:
	if dealt:
		return
	dealt = true
	for i in 4:
		_draw(i % 2, block_hash)


func hit(player: int, block_hash: String) -> Dictionary:
	if over() or not dealt or player != turn:
		return {"ok": false, "why": "not this player's turn"}
	var c := _draw(player, block_hash)
	if total(hands[player]) > 21:
		winner = 1 - player
		return {"ok": true, "card": c, "bust": true}
	return {"ok": true, "card": c, "bust": false}


func stand(player: int) -> Dictionary:
	if over() or not dealt or player != turn:
		return {"ok": false, "why": "not this player's turn"}
	stood[player] = true
	if player == 0:
		turn = 1
	else:
		var a := total(hands[0])
		var b := total(hands[1])
		winner = 2 if a == b else (0 if a > b else 1)
	return {"ok": true}
