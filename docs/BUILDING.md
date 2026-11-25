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
| `tools/net_selftest.gd [-- --url=ws://…]` | game server end to end with scripted clients (no chain; local only) |
| `tools/net_bot.gd -- --url=ws://…` | a scripted remote player (signs in with a test key, walks up, chats) |

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

With the borders (four fields, three or four neighbour grounds at 181²), RatKing, `perf.gd` default
camera, 500 frames: 164 draw calls, 520 objects, 0.30 M primitives, object growth 0.04 (a one-off:
the fair opening mid-sample; 200 frames read 0.12 for the same reason).

724 m territories (2026-11-24): the ground mesh is 363² (2 m, 0.26 M triangles, was 0.13 M) and each
neighbour ground 181² (4 m, 65 k triangles, was 33 k), so a view with all of it adds ≈ 0.26 M primitives
Roads cost no draw calls (the terrain shader reads a 512² distance texture); their lamps are one
MultiMesh pair (+2 draw calls). Measured on RatKing, 30 frames (2026-11-24):

| View | before (512 m) | after (724 m) |
|---|---|---|
| player camera | 376 draw calls, 787 objects, 0.36 M prims | 299, 793, 0.60 M |
| `--view=aerial` | 1,309 draw calls, 2,611 objects, 0.96 M prims (master with the fair games) | 1,302, 2,622, 1.15 M |
| headless wall time | 7.4 ms/frame | 7.2 ms/frame |

The aerial view (whole territory, grand fair, Burj) was already over the draw-call and object budgets
before the resize; the resize adds only primitives.

The diegetic loop and Core detail (2026-11-24, RatKing, lavapipe, 120 frames; master → this branch): `--view=core`
370 → 366 draw calls, 466 → 473 objects, 0.53 M → 0.51 M primitives; `--view=aerial` 1,425 → 1,416, 2,759 → 2,767,
1.17 M → 1.14 M (still over, as before). Repeated detail is MultiMesh (bollards, caps, light lines, joints, the
Capital halo); act beacons are at most six small meshes each.

Script cost is measured headless: wall time minus the empty-scene floor (`--disable=.`).

`--scene=res://scenes/places/sunny_pub.tscn --qing=0x2b78…96de --view=room` samples Sunny's Pub (its widest
fixed view, the whole room with 8 regulars, echoes, arcade and pool): 546 draw calls, 773 objects, 0.37 M
primitives (2026-11-24). What keeps it there: the regulars and echoes are `HumanAvatar.civilian` (no armour or
jetpack: ~16 meshes, not 55), the bottles are lathed MultiMeshes (not Poly Haven bottles at 1.6 M triangles),
stools, sunflowers and trim are batched per material (`PubKit.Batch`).

### Polish pass (2026-11-24): measured at a fixed quality

Earlier rows above were taken at whatever level `user://settings.cfg` held (usually Low: no sun shadows),
so they undercount High, where every shadow caster is drawn again per cascade. Measure with
`--quality=3` (the budgets' level) and `--quality=1`. RatKing (`--qing=0xe416…400b`), lavapipe, 60 frames,
master `854e2b1` → `polish-perf`; draw calls / objects / primitives:

| View | High, before | High, after | Low, before | Low, after |
|---|---|---|---|---|
| player camera | 974 / 1,797 / 1.88 M | 895 / 1,766 / 1.11 M | 360 / 972 / 0.59 M | 336 / 948 / 0.57 M |
| `--view=aerial` | 1,530 / 3,878 / 1.47 M | **880 / 1,347** / 1.15 M | 1,529 / 3,877 / 1.21 M | **491 / 706** / 0.95 M |
| `--view=fair` | 3,227 / 7,918 / 3.45 M | 1,388 / 2,616 / 1.69 M | 1,141 / 3,390 / 1.19 M | **875** / 1,653 / 1.12 M |
| Sunny's Pub `--view=room` | 821 / 1,162 / 0.55 M | 657 / 999 / 0.47 M | 604 / 939 / 0.40 M | 377 / 712 / 0.32 M |

Within budget now: the aerial view (both levels), the player camera and the pub. Still over: the fair seen
whole from 100 m (High, and its objects at Low): its rides (carousel, drop tower, wheel) are many moving
parts. What changed:
- `DetailCull` (`scripts/world/detail_cull.gd`, everything under the Core except the skyline towers and
  development): a screen-size visibility range per prop, end = K × its size (K 110/140/190/240/400 per
  level, ≈ 2.5–4 px), and a shadow LOD: props under 1.2 m cast no shadow, bigger ones only within
  SHADOW_K × size of the camera (20 at High: a 2 m prop 40 m, a 5 m wall 100 m).
- Sun shadows: High 120 m (was 260), Medium 90 m in 2 splits (was 160 m in 4). The ground's caster is a
  half-resolution proxy sunk 0.45 m (no acne); the full 0.26 M-triangle ground was ~1 M shadow primitives.
- Creature heads: one baked mesh each (`AvatarHeads.bake`: vertex colour + one shared shader, LODs),
  cached per kind, so every rat head is the same resource; was ~15 primitive meshes per head.
- Stage chase bulbs: one MultiMesh per frame of bulbs (was ~120 meshes per stall).
- Tried and dropped: merging each stall's static parts into one mesh. Objects fell ~7 % but draw calls
  rose, because Forward+ already batches identical mesh + material draws, and a merged mesh can't be culled
  part by part.
- `tools/perf_breakdown.gd [--by-shadow]` lists which subtrees the objects and sun casters come from.

### Fair far LOD (2026-11-25)

Same method (RatKing, lavapipe, 60 frames, `--quality=3` / `--quality=1`; Sunny's Pub at `0x2b78…96de`),
`7c5f4a0` → `fair-lod`, both measured in the same session; draw calls / objects / primitives:

| View | High, before | High, after | Low, before | Low, after |
|---|---|---|---|---|
| `--view=fair` | 1,351 / 2,644 / 1.72 M | **651 / 923 / 1.47 M** | 877 / 1,691 / 1.12 M | **466 / 615** / 0.98 M |
| `--view=aerial` | 882 / 1,384 / 1.15 M | 662 / 848 / 0.92 M | 494 / 743 / 0.95 M | 558 / 714 / 0.80 M |
| player camera | 899 / 1,812 / 1.15 M | 767 / **1,677** / 1.15 M | 397 / 1,044 / 0.60 M | 267 / 905 / 0.57 M |
| Sunny's Pub `--view=room` | 664 / 1,034 / 0.51 M | 664 / 1,034 / 0.51 M | 380 / 750 / 0.32 M | 380 / 750 / 0.32 M |

The fair seen whole is inside every High budget now. Still over: the player camera's objects at High (1,677;
the shadow pass is ~70 % of them: ~280 sun casters × ~3 cascades, mostly the Core's own props, the room,
the arcade front and the vehicles beside the spawn). At Low the aerial view draws ~60 more calls than
before (each stand-in is a few surfaces where DetailCull used to end the small parts one by one; still
well inside the budget). What changed:
- `FarProxy` (`scripts/world/far_proxy.gd`, Godot's HLOD): past `BEGIN_M` (36 m) a rigid group draws as one
  stand-in mesh and its parts hide (each part's `visibility_parent` is the stand-in, so they swap at the same
  distance). Groups: each ride's rigid parts (`RideBase._lod_groups()`: the frame, the carousel's turntable,
  the drop tower's car, the wheel and each gondola, the rocket's pad, lift, arm and rocket), the static fair
  in 24 m cells (stalls with their games' idle props, the arch, kiosks, lamps, rocks), each vehicle's hull
  and wheels, the Swap Hall. A stand-in is a child of its group, so the wheel still turns and gondolas
  still swing far away. Plain paints collapse into ONE surface per stand-in (`far_paint.gdshader`: albedo,
  clearcoat per vertex colour, roughness and metallic per UV2), plain glows into one more
  (`far_glow.gdshader`), triplanar textures one per texture set (tint as vertex colour); glass and model
  materials keep theirs; materials animated at runtime carry `FarProxy.KEEP_META`. Live, never merged:
  labels, particles, lights, bulbs and other coloured MultiMeshes, ShaderMaterial meshes (awnings, the
  rocket's hull), anything with its own range (prizes, NPCs), anything hidden at build time (flames, chutes),
  scripted nodes (effects, crowds, boards) and the group `lod_live` (the searchlight heads).
- Shadows: each stand-in has one shadow-only caster per tier (parts ≥ 1.8 m from 36 m, ≥ 4.8 m past 72 m,
  `lod_bias` 0.2). The first try, one caster with everything ≥ 1.2 m at full LOD, cost 0.56 M shadow triangles.
- Stand-ins get automatic LODs (`ImporterMesh.generate_lods`). They are built after load, a group per frame
  (`FarProxy.pump`, from DetailCull and the fair): the merge on the main thread (RatKing's grand fair: 52
  stand-ins from 1,914 parts, ~1.1 s of merging under lavapipe on a busy 4-core box, i.e. ~20 ms a frame for
  ~50 frames), the LODs on a WorkerThreadPool task (~1.5 s). Until a stand-in lands its group draws its parts.
- Festoon bulbs: a real-size sphere with LODs (`FairKit.bulb_mesh`). A MultiMesh picks the LOD for the mesh as
  modelled, so the old unit sphere scaled to 3 cm per instance never left LOD 0 (~0.3 M triangles at the fair view).
- Idle `FairFx` particle emitters are hidden (a CPUParticles3D draws its whole zero-scaled batch while idle:
  ~49 objects at the fair view). Fixed signs (`Label3D`, billboard off) end where their letters are ~3 px
  (`DetailCull.label_size`), not where their width is: the prize-shelf small print went at 24 m, not 120 m.
- The skyline's tower names don't pile up at mid range (`LabelDeclutter`, `scripts/world/label_declutter.gd`):
  each label's screen box (at the scale LegibleLabels gives it), shown in board order (#1 first) only where it
  doesn't overlap one already shown; the rest fade out and come back when there's room. Shot:
  `--view=skyline` (add `--no-declutter` for every label).
- Tools: `perf.gd --hide=<name part>` (what those nodes cost), `--no-far-proxy` (any scene, for A/B),
  `perf_breakdown.gd --merge-ids --list=<path part> [--by-tris | --list-casters]` and a ktris column; it now
  counts a part behind a stand-in as hidden. `--view=fair_near` frames the fair from its edge (near rides in
  full, the far side as stand-ins).
- `tools/probe_fair.gd` passes as before; its one failure ("a locked rocket sells no ticket and flies a free
  practice flight") fails the same on `7c5f4a0`.

Loading: a first visit's ground (≈ 8 s) is built on a thread during the warp with a progress card (real
progress from `JuliaHeightfield.progress_of`) and lore lines; the neighbours' grounds are cached in the
same wait, and the overlay holds over the new scene's first 12 frames, so its pipelines compile unseen.

Other performance measures in the build:
- Deep Field SubViewports (the pylon plates, the chest emblem) render at 4–6 Hz, not every frame.
- Heightfields and scores are cached under `user://cache`.
- No per-frame array copies in `_process`.

## Goldens

- `node tools/golden/gen.js <entropy-ai-pulse> <qing-registry.json>` writes the selectors and topics.
  Add `--snapshot` to also write the territory snapshot.
- `node tools/golden/deepfield.js <entropy-ai-pulse>` writes the Deep Field params from the site's JS.
- `node tools/golden/ecrecover.js <dir with node_modules/ethers>` writes the Keccak/ecrecover/personal_sign goldens.
- `node tools/golden/creates.js <entropy-ai-pulse> [from] [to]` writes the deployer's CREATE addresses
  for World watch. Nonce 132 reproduces MAP.

## Wallet flows

Signing needs a real browser wallet. Follow [`WALLET_TESTS.md`](WALLET_TESTS.md) with a fresh wallet and
an onboarded one.

`GODOT=godot tools/e2e_wallet.sh` runs the payment path end to end without one: Godot headless serves the
real `wallet.html` through the real `WalletBridge`; Chromium (Playwright) opens it with a mock EIP-1193
wallet (recorded requests, strict params) that answers `eth_sendTransaction` with a real past AFFECTION
transfer hash, so `wait_receipt`/`verify_receipt` read a real receipt. It drives a fair ticket, an arcade
credit, `personal_sign`, a rejection, a link dropped mid-signature, a simulation revert, the wallet test,
a scene change, a stale window (old token), a second window and a closed-then-reopened window. Needs
network to rpc.pulsechain.com; nothing is broadcast. `--keep` keeps the control dir (Godot log, results).

Avatars in outfits (2026-11-24, `perf.gd`, lavapipe): Sunny's Pub `--view=room` 512 draw calls, 833 objects,
0.37 M primitives; the full fair at `--qing=0xe416…400b --view=fair` (24 visitors + staff) 874 draw calls,
2,135 objects (over the 1,500 budget: most are the creature heads' primitive meshes, ~15 per avatar; the
outfit itself is one mesh of 3–4 surfaces with merged LODs), 0.94 M primitives.

The rave arcade (2026-11-25, `perf.gd --scene=res://scenes/places/arcade_place.tscn --quality=3`, lavapipe, 60
frames, Illinois): player camera 533 draw calls, 936 objects, 0.35 M primitives (before: 1,749 / 2,153 / 0.97 M,
over budget: ~1,400 of the draws were sun-shadow passes of the 13 cabinets); `--view=rave --rave-bar=5` (the whole
hall in the drop, 16 cabinets, DJ + 10 dancers, lasers) 484 / 920 / 0.29 M. Script cost of `RaveHall` ≈ 0.08 ms a
frame headless; the music is a worker-thread render (~0.5 s, once) and a buffer push per frame.

### Bumps: knockable props and characters (2026-11-25)

RatKing (`--qing=0xe416…400b`; Sunny's Pub at `0x2b78…96de`), lavapipe, 60 frames, `--quality=3`, `823f26b` → `bump`;
draw calls / objects / primitives:

| View | High, before | High, after |
|---|---|---|
| player camera | 287 / 1,081 / 0.58 M | 287 / 1,082 / 0.58 M |
| `--view=fair` | 494 / 730 / 0.98 M | 486 / 765 / 0.98 M |
| Sunny's Pub `--view=room` | 648 / 1,056 / 0.50 M | 688 / 1,098 / 0.51 M |

Object growth per frame 0.1 before and after (one "after" sample read 2.7; its repeat read 0.1). Headless script cost
7.44 ms/frame wall with `KnockWorld`, 7.39 without (`--disable=KnockWorld`). What it costs: at the fair the knockable
crates, bins and barrels stay out of the far stand-ins (`FarProxy.LIVE_GROUP`), +35 objects seen whole; in the pub
the stools left the material batches for one MultiMesh of their own (4 surfaces) and the loose drinks, candles and
the cue stand are their own nodes (+40 draw calls). Nothing has a body while nobody moves; a knocked prop has one
only while it moves (≤ 32).
