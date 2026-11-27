# Contributing

Thanks for helping. Dysnomia is a fan-built, community project: not made, endorsed or run by the creator
of Dysnomia. It renders real PulseChain state, so the rules below exist to keep players' wallets safe and
every number honest.

## Before you start
1. Install [Godot 4.6.1](https://godotengine.org/download/archive/4.6.1-stable/) (standard, not .NET).
2. Read [`docs/LEARNINGS.md`](docs/LEARNINGS.md) (the verified chain facts: addresses, selectors, formulas)
   and [`docs/BUILDING.md`](docs/BUILDING.md) (every check and tool). [`CLAUDE.md`](CLAUDE.md) is a dense map
   of the codebase, written for AI coding sessions but useful to anyone.
3. Run the checks: `GODOT=godot tools/check.sh` (import, compile every script and shader, unit tests).
   Online play: `godot --headless --path . -s res://tools/net_selftest.gd`. Both run on every pull request.

## The rules (a pull request that breaks one won't be merged)
- **Never fabricate chain-shaped data.** Loading, empty, unavailable and zero are different states; a failed
  read shows "—". Every number shown carries its source and block.
- **Every write:** simulate (`eth_call` from the player's wallet) → sign → verify the mined receipt from the
  chain (the mined tx must equal the request) → re-read state.
- **Wallet safety** ([`docs/SECURITY_AUDIT.md`](docs/SECURITY_AUDIT.md)): exact approvals only; sign only the
  game's own texts; never take a payee address from chat, the server or a web page; never ask for a seed
  phrase or key.
- **Big integers never become floats.** No JSON-RPC batches (use Multicall3).
- **No hard-coded keys:** add an input action in `project.godot` and list it in `ControlsHelp.ACTIONS`.
- **No price literals:** prices live in `scripts/games/prices.gd`.
- **Assets:** only CC0 / OFL / compatible licences, credited in [`assets/CREDITS.md`](assets/CREDITS.md).

## Pull requests
- Keep each one focused; say what you changed and how you checked it (tests, a screenshot via
  `tools/screenshot.gd`, a live read-only tool).
- New behaviour gets a unit test in `tests/` when it has pure logic.
- Security problems: please don't open a public issue; see [`SECURITY.md`](SECURITY.md).

By contributing you agree that your code is released under the [MIT licence](LICENSE).
