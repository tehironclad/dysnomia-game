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

The head comes from your LAU's own on-chain name and symbol. RatKing's symbol is 🐀👑, so RatKing is a rat
with a crown. Names and emoji for aliens, frogs/Pepe, dogs, cats, skulls, robots, hamsters, foxes, pigs,
apes and birds work the same way. Everyone else is the clockwork LAU bear.

You can also pick your own head on the identity card. That choice is stored on your machine only.

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
