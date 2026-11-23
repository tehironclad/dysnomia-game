# Dysnomia

A viewport onto a living on-chain organism. Dysnomia renders the Dysnomia contracts on PulseChain (chain
369) as a world you can walk:
- every territory's ground is its own Julia set;
- every number carries its source and its block;
- every change you see was made by a real transaction.

It is built with **Godot 4.6** (GDScript). The specification is [`dysnomia-game-spec.md`](dysnomia-game-spec.md)
(v2). The verified facts are in [`docs/LEARNINGS.md`](docs/LEARNINGS.md).

## Play

1. Open the project in Godot 4.6 and press F5, or run a release build.
2. From the front door you can:
   - **Enter the Field** (all ~940 territories), or search for a territory and **Warp** to it;
   - **Connect wallet**, which opens a small page in your browser where your wallet signs;
   - **Enter the Void** to create your identity: Forge, Bind, Name, Wake, Play.
3. In a territory, walk to the Core. Each spot has its own move:

| Spot | Move |
|---|---|
| a pylon | Su |
| the door | the Room |
| the centre | Beat |
| the plinth | WORLD range |
| the monolith | the Void |

Every move previews from your wallet first. Nothing reports success until the chain does.

| Key | Action |
|---|---|
| WASD · Space · Shift · Ctrl | move · jump (triple) · sprint · crouch |
| Tab · Z | fly · first/third person |
| E | use (Su, Room, Beat, WORLD, Void) |
| H | how is this drawn? (sources and formulas) |
| M | the Field |
| G | Guide: the acts |
| F | flashlight |
| F1 · F3 · F10 | controls · performance overlay · settings |

F1 in game lists the same controls, read from the input map.

## Your avatar

You're a suited LAU in a GTA-style third-person view: the mouse orbits the camera, and your character
turns to face where it runs.

The body is a rigged human (Quaternius Universal Base Characters, CC0), animated with motion-captured
clips (Quaternius Universal Animation Library, CC0): idle, walk, jog, sprint, crouch, jump and a
swimming stroke for jetpack flight. It wears a dark armoured suit with trim in your identity colour.

The head comes from your LAU's own on-chain name and symbol. RatKing's symbol is 🐀👑, so RatKing is a rat
with a crown. Names and emoji for aliens, frogs/Pepe, dogs, cats, skulls, robots, hamsters, foxes, pigs,
apes and birds work the same way. Everyone else is the clockwork LAU bear.

You can also pick your own head on the identity card. That choice is stored on your machine only.

## What to do (press O)

The **Opportunities** board is read from the chain at one block.
- **Hot spots:** the territories where a Su pays Hypobar, ranked by Ω (only 27 of 942 today).
- **Within reach:** leads you can take, with the exact Su count and its gas cost in PLS.
- **Your crowns:** territories you lead, and how many Su a rival needs to pass you.
- **Build together:** how many Su lift a territory to its next tier.
- **Your record:** your streak of DysnomiaDays with a reaction, read from your YUE logs, plus how much of
  today is left.

When someone takes your lead, or you take theirs, you get an alert with the block.

## Territories grow

A territory builds up as people react there. All of this is chain state, so every visitor sees the same
city.
- **The tier comes from the Hypobar total.** Bars only ever grow, so a city never decays:

  | Tier | Hypobar total | What appears |
  |---|---|---|
  | Wild | none | bare regolith |
  | Outpost | any | a beacon |
  | Settlement | ≥ 10⁴ | landing pads |
  | Town | ≥ 10⁶ | city lights along the fractal coast |
  | City | ≥ 10⁸ | ring roads and an aurora |
  | Capital | ≥ 10⁹ | a light spire from the Heart |

- **Each player's bars there make their tower** in the skyline. The leader's is crowned.
- **The Epibar total lights the windows**, the city lights and the aurora.

`tools/live_development.gd` prints the real distribution. On 2026-11-23 it was 889 wild, 11 outposts,
9 settlements, 4 towns, 4 cities and 1 capital (RatKing).

## Places

- **A QING's hall.** Walk through the Room's door at the Core and you're inside: a sci-fi chamber built
  for that territory.
  - Its back wall is the board: the room's own on-chain lines, live.
  - Its Julia set is inlaid in the floor.
  - Holographic echoes of the latest speakers stand in front of the board.
  - Press T to speak. The door takes you back.
- **The Void.** The monolith takes you to an open space with a glass platform and a nebula sky. Void lines
  drift around you, the newest closest. Press T to speak; the portal takes you back.

## Without a wallet

Everything can be read without connecting: territories, bars, rooms, the Void, readiness. Only the writes
need a wallet.

## Truth contract

These rules are kept in short:
- No fabricated chain data. Loading, empty, unavailable and zero are different states, and a failed read
  shows "—".
- Every write runs simulate → sign → verify the receipt → re-read state.
- WORLD, WAR and GWAT are **not deployed** yet. The game watches the deployer and only says "live" once a
  wired WORLD is verified on chain.

For building, tests and tools, see [`docs/BUILDING.md`](docs/BUILDING.md).
