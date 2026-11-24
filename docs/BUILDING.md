# Building, testing and tools

## Engine

Godot **4.6.1** (Forward+). On Linux:
`https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_linux.x86_64.zip`

## Checks (no network)

```bash
GODOT=/path/to/godot tools/check.sh
```

`check.sh` runs three steps:
1. imports the project;
2. compiles every script with the autoloads present (`tools/compile_check.gd`), and force-compiles every
   shader;
3. runs the unit tests (`tests/run.gd`).

The tests cover BigInt and the ABI, selectors against keccak goldens, projection and Deep Field params
against the site's real JS, heightfield hashes, readiness, chat parsing and badges, Su deltas, the Join
plan, the WORLD bytecode classifier, the CREATE table, acts, controls and sound, the arcade games and
the Folklore CPU, and the arcade dive (score board, Entropy Drift's chain track, each 3D world following
its game headlessly).

Per-script `--check-only` gives false "Identifier not found" errors for autoloads; don't use it. A script
that fails to parse makes `-s` tools hang, so run `check.sh` first.

## Read-only live tools (they never sign)

| Tool | What it does |
|---|---|
| `tools/live_smoke.gd` | chain reachability, sample territory facts, the deployer nonce |
| `tools/live_readiness.gd [-- --n=12 --wallet=0x…]` | identity and WORLD readiness for real players |
| `tools/live_moves.gd [-- --wallet=0x… --qing=0x…]` | Su and Beat previews, the door, room and Void lines, World watch |
| `tools/live_chat.gd [-- --qing=0x… --player=0x…]` | the HUD feed for a room; the chat bar with no wallet, a fake wallet and a real player read-only (each stops at its precondition); one-line and 3-line batch simulations and gas |
| `tools/boot_territory.gd` | loads a territory headlessly and prints the HUD card; should show no errors |
| `tools/update_snapshot.gd` | refreshes `assets/data/territories.json` from the chain |

Run each with `godot --headless --path . -s res://<tool>`.

## Pictures without a GPU

- `tools/preview_emblems.gd -- --out=<dir>` renders Deep Field pictures on the CPU.
- `tools/preview_terrain.gd -- --out=<dir>` renders heightfield previews and prints slope stats.
- Screenshots use Xvfb and lavapipe (CPU Vulkan), about 20 s each:

```bash
VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --resolution 1280x720 -s res://tools/screenshot.gd -- --out=/abs/shot.png \
  --scene=res://scenes/territory/territory_v2.tscn --view=hud \
  --session=0x… --open=su|room|beat|world|void --toggle=guide|help --quality=0
```

- `--view` sets the camera: `aerial`, `ground`, `core`, `sky`, `hud`, `fair` or `garage`.
- `--drive=<kind>` (no `--view`): gets into that pad vehicle if the viewed wallet's real unlocks allow it and
  holds the throttle (`--drive-s=N`, `--steer=left|right`).
- `--view` sets the camera: `aerial`, `ground`, `core`, `sky`, `hud`, `relief` (from the highest ground back over
  the terraces) or `border_n|e|s|w` (across that force field at the neighbouring QING).
- `--session` views a wallet read-only.
- `--open` opens a move's panel (preview only).
- `--dive=<catalog id>` (with `--scene=res://scenes/places/arcade_place.tscn`) dives into that cabinet:
  `--dive-phase=push|warp` holds the transition, `inside` (default) shows the attract demo full-screen,
  `menu` adds the cabinet menu; `--classic` shows the cabinet's own screen. Nothing is paid. Use
  `--frames=260` or so: the transition and the demo need time on lavapipe.

## Performance (WP 7.5)

`tools/perf.gd` samples the territory scene. Run it under Xvfb for render counts, or headless for script
cost:

```bash
godot --headless --path . -s res://tools/perf.gd -- --frames=300 [--disable=<node>]
```

The budgets are for a mid-range GPU at High:

| Measure | Budget | Measured (Illinois, `--view=core`) |
|---|---|---|
| draw calls | ≤ 900 | 92 (fixed camera), 180 (player view) |
| objects | ≤ 1,500 | 92 / 424 |
| primitives | ≤ 1.5 M | 0.16 M / 0.40 M |
| object growth per frame | ≤ 0.05 | 0.0 |
| script cost | — | ≈ 0.4 ms/frame |

With the borders (four fields, three or four neighbour grounds at 129²), RatKing, `perf.gd` default
camera, 500 frames: 164 draw calls, 520 objects, 0.30 M primitives, object growth 0.04 (a one-off:
the fair opening mid-sample; 200 frames read 0.12 for the same reason).

Script cost is measured headless: wall time minus the empty-scene floor (`--disable=.`).

`--scene=res://scenes/places/sunny_pub.tscn --qing=0x2b78…96de --view=room` samples Sunny's Pub (its widest
fixed view, the whole room with 8 regulars, echoes, arcade and pool): 546 draw calls, 773 objects, 0.37 M
primitives (2026-11-24). What keeps it there: the regulars and echoes are `HumanAvatar.civilian` (no armour or
jetpack: ~16 meshes, not 55), the bottles are lathed MultiMeshes (not Poly Haven bottles at 1.6 M triangles),
stools, sunflowers and trim are batched per material (`PubKit.Batch`).

Other performance measures in the build:
- Deep Field SubViewports (the pylon plates, the chest emblem) render at 4–6 Hz, not every frame.
- Heightfields and scores are cached under `user://cache`.
- No per-frame array copies in `_process`.

## Goldens

- `node tools/golden/gen.js <entropy-ai-pulse> <qing-registry.json>` writes the selectors and topics.
  Add `--snapshot` to also write the territory snapshot.
- `node tools/golden/deepfield.js <entropy-ai-pulse>` writes the Deep Field params from the site's JS.
- `node tools/golden/creates.js <entropy-ai-pulse> [from] [to]` writes the deployer's CREATE addresses
  for World watch. Nonce 132 reproduces MAP.

## Wallet flows

Signing needs a real browser wallet. Follow [`WALLET_TESTS.md`](WALLET_TESTS.md) with a fresh wallet and
an onboarded one.
