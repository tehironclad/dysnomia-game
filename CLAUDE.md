# Dysnomia game — notes for Claude sessions

**Start here:**
- [`docs/REWORK_PLAN.md`](docs/REWORK_PLAN.md): the v2 plan. Phases and work packages, with a status
  board to tick as WPs land.
- [`docs/LEARNINGS.md`](docs/LEARNINGS.md): the facts. Addresses, selectors, formulas, coordinates, RPC
  rules, the truth contract, and the Deep Field visual rules.
- `dysnomia-game-spec.md` is the v2 spec (2026-11-23); LEARNINGS still wins on facts.
- [`docs/BUILDING.md`](docs/BUILDING.md): checks, every tool, perf budgets. `docs/WALLET_TESTS.md`: the manual
  signing checklist. `docs/RELEASE_CHECKLIST.md`.

**Hard rules:**
- **Never fabricate chain-shaped data.** Loading, empty, unavailable and zero are different states; a
  failed read shows "—". Every number carries its source and block.
- **Every write goes:** simulate (`eth_call` with `from` = wallet) → sign → verify the receipt from the
  chain → re-read state. Never trust the wallet page's "confirmed".
- **`tx.origin` reads need `from` = wallet** (Su, Beat, Eta, Yuan, Power…). `META.Beat` takes a **Waat**.
- **Big integers never become floats.** Coordinates are ~240-bit int256.
- **No JSON-RPC batches** (the public node serialises them). Use Multicall3
  `0xca11bde05977b3631167028862be2a173976ca11`.
- **WORLD/WAR/GWAT/VITUS/H2O are not deployed.** Never hardcode guessed addresses.
- **Site API** (an optional accelerator only): `https://systm0.vercel.app`.
  `entropy-dysnomia.vercel.app` and the Supabase project are gone.
- **Territory visuals depend only on territory state**, never on the viewer.

**Verify:**
- Godot 4.6.1 is not installed. Download it into the scratchpad:
  `https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_linux.x86_64.zip`
- `GODOT=<path> tools/check.sh` runs three steps: import; `tools/compile_check.gd`, which compiles
  every script with the autoloads present; and `tests/run.gd`, the unit tests (no network).
  Per-script `--check-only` gives false "Identifier not found" errors for autoloads; don't use it.
- `godot --headless --path . -s res://tools/live_smoke.gd` runs read-only live chain checks. It also
  prints the deployer nonce, which is the WORLD launch signal.
- `godot --headless --path . -s res://tools/update_snapshot.gd` refreshes
  `assets/data/territories.json` from the chain.
- `node tools/golden/gen.js <entropy-ai-pulse> <qing-registry.json>` regenerates the test goldens.
- `godot --headless --path . -s res://tools/boot_territory.gd` loads a real territory from the chain
  (read-only), enters the world headlessly and prints the HUD territory card. It catches runtime
  errors, and should print none.
- `godot --headless --path . -s res://tools/preview_emblems.gd -- --out=<abs dir>` CPU-renders Deep
  Field pictures to PNG. You can view them without a GPU.
- `godot --headless --path . -s res://tools/preview_terrain.gd -- --out=<abs dir>` writes Julia-heightfield
  previews and prints slope stats per territory.
- If a headless run hangs with no output, a script probably failed to parse: run `tools/check.sh`
  first. A class that doesn't compile makes `-s` tools hang instead of erroring.
- In `-s` tool scripts, don't reference by name any class that uses autoloads (Chain, Registry…). At
  the tool's parse time the autoloads aren't registered yet, so it fails with "Identifier not found".
  Use `load("res://…").new()` inside a deferred function instead. Godot's stdout is buffered when piped:
  redirect to a file to see errors from killed runs.
- `godot --headless --path . -s res://tools/live_readiness.gd [-- --n=12]` prints identity + WORLD
  readiness for real players (read-only).
- `screenshot.gd -- --session=<wallet>` views any wallet's identity read-only. Nothing is signed.
  Add `--view=hud --open=su|room|beat|void` to render a move's panel (preview only).
- `godot --headless --path . -s res://tools/live_moves.gd [-- --wallet=0x… --qing=0x…]` runs the Phase 5
  previews against the chain (Su, Beat, door, room and Void lines, World watch). It is read-only.
- `tools/perf.gd` samples draw calls, objects, primitives and object growth (under Xvfb), or script cost
  (headless; `--disable=<node>` to profile).
- The avatar is `scripts/player/human_avatar.gd`: a Quaternius CC0 body plus animation library in
  `assets/characters/quaternius/` (same 65-bone rig, so the clips play directly). Creature heads go on
  `neck_01` while the `Head` bone is collapsed. Crow and flames: `avatar_extras.gd`.
- Places (`scripts/places/`): `qing_hall.gd` (the room, built from `assets/buildings/scifi`, Quaternius
  Modular Sci-Fi MegaKit, CC0, 4 m grid) and `void_place.gd`; both use `ChatController` (history, live tail,
  post, Join) and `SpeakerEchoes`. Render: `screenshot.gd -- --scene=res://scenes/places/qing_hall.tscn --qing=0x…`.
- Games (`scripts/games/`, LEARNINGS §14): `ArcadePay` (1 Ⓐ a play → the QING, receipt-verified),
  `TableBook` (pool and Twenty-One as room lines; signer = tx.from; honour-bound wagers checked by
  Transfer logs), `PoolSim`/`EightBall` (integer physics), `Duel21` (cards from block hashes). The arcade
  library is `scripts/arcade/` (ArcadeGame, three original games, the Folklore 6502 cart player,
  ArcadeCatalog). Places: `arcade_place.gd` (every territory, door `ArcadeFront` on the plaza) and
  `sunny_pub.gd` (TehSunFlowrScioety QING), both on `GamesPlace`.
- Vehicles (`scripts/vehicles/`, LEARNINGS §15): a pad per territory (`scripts/world/garage/garage_site.gd`), five
  vehicles (`MoonVehicle`, specs and pure physics in `VehicleSpecs`), unlocks from real state (`VehicleUnlocks`).
  V in/out, R upright. Shots: `--view=garage`, or `--drive=<kind> [--drive-s=N --steer=left] [--session=0x…]`.
- Development (`scripts/state/development.gd`): tier from the Hypobar total, energy from the Epibar
  total; skyline towers per player (`bar_columns.gd`, `tower.gdshader`), structures (`development_site.gd`),
  city lights/roads (terrain shader), aurora (sky shader). `tools/live_development.gd` measures every territory.
- Collision: `scripts/world/solid.gd` (`Solid.box/cylinder/wrap`). Solid: the Core's room walls (doorway
  open), pylons, skyline towers (resized with them), the monolith, the World plinth, development props.
  Walk-through on purpose: the Heart, beacon/spire (sky), well basins, landing pads, floor lamps.
- Automatic graphics (`Config.recommend/decide`): on first launch the GPU (name and type), cores and RAM pick
  the level and renderer; a software or old Intel GPU relaunches the game itself with
  `--rendering-method gl_compatibility` (an explicit `--rendering-method`/`--quality=` on the command line is
  respected). In play, 10 s frame-rate windows step the level down (<24 fps) or up (headroom; never past
  High). F2 has the "Adjust graphics automatically" box. Tools run with `-s` and headless runs skip all of this.
- Textures: `assets/textures/polyhaven` (CC0 moon regolith in the terrain shader; metal plates).
- `tools/avatar_sheet.gd -- --out=<png> --mode=heads|poses|closeup [--head=rat --acc=crown]` renders the
  avatar in a studio (needs Xvfb). Heads come from the LAU's Username/name/symbol (`AvatarHeads`).
- No hard-coded keys: add an input action in `project.godot` and list it in `ControlsHelp.ACTIONS`
  (a test checks every listed action is bound).
- Deep Field goldens: `node tools/golden/deepfield.js <entropy-ai-pulse>` reruns the site's real JS.
- **Screenshots (the user OK'd this route, 2026-11-22):**
  `VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 -s res://tools/screenshot.gd -- --out=<abs png> --scene=res://scenes/territory/territory_v2.tscn --view=aerial|ground`
  - It renders on the CPU (lavapipe) in about 20 s. Look at the PNG with the Read tool.
  - `--view=aerial|ground|core|sky|hud` gives a fixed camera. With no `--view` you see the player's own
    third-person camera.

**Research source:** `tehironclad/entropy-ai-pulse`. Attach it read-only when a WP says "port from …".
