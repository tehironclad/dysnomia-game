# Dysnomia game — notes for Claude sessions

**Start here:**
- [`docs/REWORK_PLAN.md`](docs/REWORK_PLAN.md): the v2 plan. Phases and work packages, with a status
  board to tick as WPs land.
- [`docs/LEARNINGS.md`](docs/LEARNINGS.md): the facts. Addresses, selectors, formulas, coordinates, RPC
  rules, the truth contract, and the Deep Field visual rules.
- `dysnomia-game-spec.md` is the Feb 2026 spec. Its on-chain mechanics are partly wrong; LEARNINGS wins.

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
- Deep Field goldens: `node tools/golden/deepfield.js <entropy-ai-pulse>` reruns the site's real JS.
- **Screenshots (the user OK'd this route, 2026-11-22):**
  `VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 -s res://tools/screenshot.gd -- --out=<abs png> --scene=res://scenes/territory/territory_v2.tscn --view=aerial|ground`
  - It renders on the CPU (lavapipe) in about 20 s. Look at the PNG with the Read tool.
  - `--view=aerial|ground|core|sky|hud` gives a fixed camera. With no `--view` you see the player's own
    third-person camera.

**Research source:** `tehironclad/entropy-ai-pulse`. Attach it read-only when a WP says "port from …".
