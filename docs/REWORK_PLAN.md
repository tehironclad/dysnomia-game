# Dysnomia v2 — rework plan ("Deep Field")

**Status:** draft for review. Confirm the decisions in §8, then start Phase 0. · **Written:** 2026-11-22
**Companion:** [`LEARNINGS.md`](./LEARNINGS.md) holds every fact this plan relies on: addresses,
selectors, formulas and rules. Coding sessions should read both.

---

## TL;DR

1. **The game's core verb is wrong.** "Terraform" (AFFECTION Alpha/Beta/Pi/Rho/Generate/Upsilon) only
   mints AFFECTION into AFFECTION's own reserve. It never touches a territory. The real live loop is:
   - **identity** (LAU → Soul → YUE);
   - **`CHEON.Su` / `CHOA.Chat` at a territory**, which grows your Hypobar/Epibar "bars" there;
   - **rooms** (cover charge, admission, on-chain chat);
   - **the Void** (global chat);
   - **`META.Beat`**, gated by four holdings.

   `WORLD.Code` (claiming map cells), `WAR.Faa` (water yield) and GWAT are **still not deployed**
   (deployer nonce 712, checked today).
2. **Almost everything off-chain is dead.**
   - The game's API host is gone. The site moved to `systm0.vercel.app` and dropped its database.
   - The Supabase project (multiplayer, voice) no longer resolves.
   - Achievements, XP, flags, alliances, dailies, emotes, leaderboard and multiplayer currently do nothing.
3. **Much of the chain layer is broken.**
   - 4 wrong selectors, a wrong "ZUO" address, the wrong chat event, reads missing `from`.
   - Big integers are truncated to 64 bits, three disagreeing coordinate transforms.
   - The territory list is 263 of **942**.
   - Most "chain-driven" visuals sit at zero, and the rest depend on *who is looking*.
4. **The world doesn't express the mission.**
   - Every territory has the same building layout.
   - The art mixes a Qing-dynasty tomb, a cantina, creatures, weapons and a "Ted-style" bear with a
     "Predator-style" laser, which is also an IP-likeness risk.
   - The owner has since signed off on **Deep Field**: *"epic, hypnotic, mathematical, mysterious, true
     to the code… every image is a real number."*
5. **The plan: rebuild the spine, salvage the best parts, cut the rest.** v2 is a **viewport onto the
   live organism**:
   - every territory's ground is computed from its own Julia set (its real entropy and address);
   - every change you see is caused by a real transaction;
   - every number says where it came from;
   - WORLD is shown as "honestly absent" until it deploys, with a full readiness preview so players
     are ready on day one.
6. **9 phases, ~40 work packages**, each sized for one coding session at **medium** or **high**
   effort. They deliver four milestones:
   - **M1 Viewport:** walk any of the 942 territories, no wallet;
   - **M2 Live loop:** onboarding, Su, rooms, chat, Beat;
   - **M3 WORLD-ready;**
   - **M4 v2.0.**

---

## 1. Why a rework: the Feb 2026 assumptions vs. what we know now

| The Feb spec / current game assumes | What is actually true (see LEARNINGS) |
|---|---|
| AFFECTION calls terraform a territory | They mint AFFECTION into its own reserve. No territory effect. |
| "Charge/power" drives the territory's look | `XIE.Power` reverts without `from` = wallet, and power ≡ 0. Charge is per-player and pseudo-random anyway. |
| Territory visuals come from the territory | They come from the **viewer's** YUE bars and wallet. Two players see different worlds. |
| Neighbouring territories border each other | Map coordinates are a modular hash; adjacency means nothing on-chain. |
| QING = a Qing-dynasty place | QING = a **venue / chat room** with a cover charge, bouncers and its own token. |
| 263 territories | 942 and counting (one `eth_getLogs` returns them all). |
| Off-chain API at entropy-dysnomia.vercel.app; Supabase realtime | Both gone. The site at systm0.vercel.app reads the chain directly (no DB). |
| XP, levels, achievements | The site deliberately removed off-chain levels and badges; the Redis behind them never existed in prod. |
| Combat, creatures, vehicles, minigames | "Exploration is not about combat, it is about *presence*." (SOUL.md) |
| Day/night "later tied to blocks" | Never was; it's a local timer, unsynced. |

---

## 2. The game today (audit summary)

This summarizes two code audits of this repo (the chain/gameplay/UI half and the world/graphics/player
half) run while planning; their findings are folded in here and in LEARNINGS. Engine: **Godot 4.6** (Forward+, Jolt), ~30.7K lines of GDScript, everything
procedural (no imported assets except the icon). **The project imports cleanly in Godot 4.6.1
headless** (verified).

**Works:**
- reading a QING's Waat/Entropy/name;
- `HECKE.Compliment`;
- NewQing logs;
- Void chat logs;
- the browser-wallet transaction path, which already simulates before sending;
- the player controller feel;
- the Eris sky shader;
- crater stamping and the regolith shader;
- the Beat effects;
- the force-field dissolve concept;
- photo mode.

**Broken:**
- **Wrong selectors and addresses:** CoverCharge, GetQing/ZUO, GetMapQing and Cho; the ZUO address.
- **Failing reads:** room chat (wrong event topic); `XIE.Power` (missing `from`); `AFFECTION.View`
  parser (48 vs 50 words).
- **Numbers and coordinates:** int256/uint256 parsing (64-bit clamp, sign lost); 3 coordinate transforms.
- **Navigation and joining:** the world-map travel hang (cache race); neighbour Join is unreachable.
- **Stale data:** the territory map is stale, and its refresh logic never runs.
- **Avatar and world-building:** avatar height derived from `Saat(0)`, which is identical for all
  LAUs; terrain rebuilt 6× at load; a 522K-triangle collider; 6 shaders sample in view space
  (textures slide); pub triggers never fire; crystals misplaced; visual/collision height mismatch.

**Dead (no backend):**
- achievements/XP/levels, leaderboard, activity, online players;
- presence/emotes, flags/guestbook, alliances, daily/challenges;
- multiplayer and voice.

**Structure:**
- `main.gd` (1,744 lines), `hud_controller.gd` (2,819) and `chain_manager.gd` (1,716) are god objects.
- `GameManager` is a flat global bag; the `/1e12` and `/1e15` scaling is copy-pasted 28 times.
- The local WebSocket wallet bridge has no authentication, and the game trusts any `tx_confirmed` message.

### Keep / rework / cut (file level)

| Area | Files | Verdict |
|---|---|---|
| Player movement | `player/player_controller.gd`, `camera_rig.gd` | **Keep.** Remove weapon/vehicle hooks; hide the model in first person. |
| Avatar | `player/player_model.gd`, `player_appearance.gd` | **Rework:** "clockwork LAU bear" (§3.5). Strip the brass knuckles, shoulder laser and "Ted"/"Predator" naming; Soul/Aura drive proportions instead of Pole. |
| Sky | `shaders/atmosphere.gdshader`, `world/sky.tscn` | **Rework.** Keep Eris and stars; drop clouds/scattering; render statically; fix the latitude sign. |
| Terrain | `world/terrain_generator.gd`, `biome_system.gd`, `shaders/terrain.gdshader` | **Replace** with a Julia heightfield + Deep Field shading. Salvage crater/regolith shader ideas for micro-detail. |
| Beat | `world/beat_station.gd` + Beat FX in `main.gd` | **Rework** into the Core's *Heart*. Keep the effects. |
| Force field | `world/force_field.gd`, `shaders/territory_border.gdshader` | **Rework** into the Room's admission door (world-space shader). |
| Territory core | `world/monument.gd`, `monument_generator.gd` | **Replace** with the Core (§3.4). |
| Neighbours | `world/territory_manager.gd` | **Replace.** Neighbour adjacency is cut (meaningless on-chain). |
| World map | `ui/world_map.gd` | **Replace** with the Field globe (§3.3). |
| Chain layer | `chain/chain_manager.gd`, `contract_reader.gd`, `rpc_client.gd`, `hex_utils.gd`, `autoload/game_manager.gd` | **Replace** (§4). |
| Wallet | `chain/wallet_bridge.gd`, `assets/web/wallet.html` | **Rework** into a thin, authenticated EIP-1193 relay: no CDN, no Supabase. |
| HUD | `ui/hud_controller.gd` | **Replace** with panel scenes bound to state (§4). |
| Menus | `ui/main_menu.gd`, `tutorial_system.gd`, `tutorial_arrow.gd` | **Replace** with boot → Void/Field, and chain-verified acts. |
| Keep as-is | `ui/settings_menu.gd`, `photo_mode.gd`, `screen_effects.gd` (flash/vignette only), `world/footprint_system.gd`, `addons/godot_console`, `debug/*` (dev builds only) | **Keep** |
| Dead backends | `chain/achievement_client.gd`, `alliance_client.gd`, `daily_challenges.gd`, `emote_client.gd`, `flag_client.gd`, `multiplayer/*`, `ui/daily_panel.gd`, `emote_wheel.gd`, `guestbook_panel.gd`, `achievement_toast.gd` (→ generic toast), `player/stat_tracker.gd` | **Cut** |
| Off-mission | `player/weapon_system.gd`, `vehicle.gd`, `world/creature*.gd`, `pub_*.gd`, `antenna_array.gd`, `landing_pad.gd`, `pipe_network.gd`, `crystal/rock/debris_scatter.gd`, `surface_detail.gd`, `vegetation_manager.gd`, `weather_system.gd`, `dust_*.gd`, `meteor_shower.gd` (reuse its streak for NewQing), `solar_flare.gd`, `static_discharge.gd`, `heat_shimmer.gd`, `minigames/*`, `ui/batch_terraform.gd` | **Cut** (decision D2) |
| Data | `assets/data/qing_map.json`, `qing_names.json` | **Replace** with `territories.json` (942+, self-updating) |
| Shaders | creature, atm_fog, minimap_mask, neon_sign, helmet_hud, heat_shimmer, pub_display, crystal, vegetation, vehicle, flag_cloth | **Cut** (most are unused or belong to cut systems) |

---

## 3. Design v2

### 3.1 North star

> **Dysnomia is a viewport onto a living on-chain organism.** You walk on ground computed from a
> territory's real numbers; everything that changes was changed by a real transaction; every number
> tells you where it came from; nothing is invented, and what isn't built yet is shown as absent.

Pillars:
1. **True to the chain:** the loop is the contracts' loop.
2. **Every image is a real number:** Deep Field, in 3D.
3. **Presence, not combat:** belonging and accumulation. "Entropy only increases. Your history is your substance."
4. **Plain for newcomers, dense for experts:** the Guide toggle (MAKEOVER's experience switch).

### 3.2 The loop in-game (verb → contract → what you see)

| Verb | Contract call | Where / how | What changes in the world |
|---|---|---|---|
| **Look** | reads only, no wallet | anywhere | everything is readable; "How is this drawn?" explains any visual |
| **Enter the Void** | `LAUFactory.New` → `LAU.Username` → `CHO.Enter` → `SEI.Start` → `CHOA.Play` | the Void hub, as 5 stations | your Soul/Aura emblem forms; your bear takes your colours |
| **Su** (react) | `CHEON.Su(qing)` | at a territory's Core | a cascade pulse runs QI→MAI→XIA→XIE→ZI→PANG→RING→META; your bar column grows; the territory's shared total grows (and may light its next band); +1 YUE |
| **Join** a room | `approve(asset, > cover)` + `QING.Join(LAU)` | the Room door (only 14 rooms charge) | the force-field door dissolves for 24 h |
| **Chat** in a room | `CHOA.Chat(qing, msg)` (needs admission) | inside the Room | your line appears etched in light; your bars grow (same reaction as Su) |
| **Speak to the Void** | `LAU.Chat(text)` | the Void monolith | your line joins the global scroll everyone sees |
| **Gather the four** | ERC-20 `transfer`s onto your LAU (Fomalhaute, Fornax), plus Tethys and qZů held anywhere | the Readiness panel / your sky | the four named bodies above you light up |
| **Beat** | `META.Beat(waat)` | the Core's Heart | heartbeat shockwave (existing FX); shows Dione/Charge/Deimos/Yeo; a flatline if not ready, with the reason |
| **Code a cell** *(latent)* | `WORLD.Code(lat, lon, qing)` | the WORLD lattice around the Core | today: a preview of your range square and the exact call; after launch: cell pillars and king-of-the-hill |
| **Draw water** *(latent)* | `WAR.Faa(qing, pos)` | your cells | H2O; the CO2 haze rises; GWAT bone pillars |
| *AFFECTION reactor* *(optional, D5)* | `Alpha/Beta/Pi/Rho/Generate/Upsilon` | a reactor in the Void | AFFECTION's reserve gauge (supply / 1.111B cap), labelled honestly: "doesn't change your bars or range" |

Every write follows the same path:
1. **precondition check** (from chain) →
2. **simulate** (`eth_call` with `from` = wallet; decode the result or revert through the error table) →
3. **sign** in the browser wallet →
4. **verify** the receipt from the chain →
5. **re-read** state →
6. **effect**.

Nothing celebrates before step 4.

### 3.3 World structure

```
 boot ──▶ THE VOID (hub)  ◀──────▶  THE FIELD (globe of Dysnomia)  ──warp──▶  A TERRITORY
          birth · Void chat · the four bodies    942 territories at their real          walkable; computed from
          · onboarding · (AFFECTION reactor)     coordinates; search · filter · replay   its numbers (§3.4)
```

- **The Void:** a black chamber under Eris. Newcomers start here ("I'm new"); returning players can
  skip to the Field ("I know Dysnomia"). It holds:
  - the monolith scrolling the real Void chat;
  - the Motzkin prime carved monumental;
  - five onboarding stations;
  - the four bodies overhead;
  - a portal to the Field.
- **The Field:** a globe of the moon Dysnomia, plotted with the site's projection (LEARNINGS §6).
  - Each territory is a point coloured by rarity, heat (log entropy) or age, with your territories glowing.
  - Hover shows the dossier card (the territory's fractal emblem + facts); "Warp" travels there.
  - Extras: search, filters (rarity, cover charge, GWAT, has my bars) and "watch it grow" (replays
    foundings in block order).
  - **No walking between territories**: adjacency isn't real, so travel is a warp (a dive into the
    destination's Julia set).
- **A territory:** a self-contained ~512 m world (§3.4).

### 3.4 Anatomy of a territory

Everything here is derived from the territory's own numbers. It is **viewer-independent**: two players
see the same world.

| Element | Driven by | Notes |
|---|---|---|
| **Ground** | the territory's Deep Field parameters: `c`, power `D`, rotation, extent, style (from `Entropy()` and the address) | Heightfield = the filled **Julia set of z ↦ z^D + c**: the interior is a high plateau with gentle orbit-trap relief; boundary filaments become ridges (distance estimate); the outside steps down in **terraces from the smooth escape bands**. Higher rarities (D = 3–6) give visibly D-fold symmetric land from the air (since f(ωz) = f(z) when ω^D = 1). |
| **Ground shading** | same parameters + palette/style (glow/duo/bands/ember/gilded/prism) | dark regolith with **luminous filaments** computed per-pixel in a world-space shader (crisp at any distance) |
| **Lit bands** | **total Hypobar at this territory** (sum over known players), shared and monotonic | one more escape band lights up per order of magnitude of the total. The world only brightens: "transactions change the landscape". The HUD shows "+X to the next band". |
| **The Core** (centre plateau) | `Entropy`, `Waat`, `c`, asset | **Rod & Cone pylons** showing `c` and its mirror `c̄`, with the real numbers inscribed in mono type. The **Room** sits between them; the **Heart** (Beat) above. |
| **Three wells** | `Bal_Fornax(Q)`, `Bal_Eris(Q)`, `Bal_Tethys(Q)` | Fornax = Hypobar yield per Su (Ω); Eris = Charge base (QI); Tethys = VITUS per future Code (Dione). Labelled. They move when anyone "pumps" the room. |
| **Field of bars** | `YUE.Bar(Q)` for every known player | one twin light column per player (Hypobar/Epibar, log height) with username, OG badge and Aura emblem. Crown on #1; your column highlighted with "N to pass ▲rival". A floor ("≥") if the player list is a snapshot. |
| **The Room** | `CoverCharge`, `Asset`, `Admitted(LAU)`, room `LogEvent`s | circular hall; force-field door if a cover applies; chat lines etched on the walls with speakers' Aura emblems |
| **WORLD lattice** | readiness probe (`Yeo`, `Dione`, `Charge`) for *your* wallet; later, claimed cells | a faint square lattice around the Core: centre cell marked, your range square drawn (log-scaled). Labelled **"WORLD not deployed — deployer nonce 712 @ block N"** until it is. |
| **Sky** | address (stars), `c` ("you are here" on a faint Mandelbrot in the sky), DysnomiaTime from **block timestamp** (day/night shared by all players) | Eris dominates; the sun is just another star; no clouds (airless moon) |
| **Aurora** | recent activity at this territory (bar deltas / room lines in the last ~24 h of blocks) | the only "weather", and it's real |

### 3.5 The player

- **Identity:** the connected wallet → `CHO.GetUserTokenAddress` → LAU → `CHAN.Yan` → YUE. Username,
  Soul, Aura via `Saat(1)`/`Saat(2)`; Pole = `Saat(0)` is the same for everyone. One identity root;
  the old `lau_wallet` derivation is removed.
- **Avatar: the clockwork LAU bear.** The lore has clockwork LAU bears (the Court of Nine Emotions)
  and teddy-bear citizens (Hogan Bank), so the bear stays, made original:
  - proportions and fur from **Soul/Aura**;
  - the **Aura fractal** as a chest emblem;
  - the **YI Rod/Cone Lissajous** sigil on the visor.
- **Gear is earned from chain facts only** (the site's `lib/avatar.js` rules):
  - greyed out with no bars;
  - a spark at 3+ territories with bars; an orbit ring at 10+;
  - a halo while you lead any territory; a crown for ladder #1;
  - a **crow companion only if you hold ≥ 25 CROWS** (you really are a universal bouncer).
- **Readiness** is a first-class state, shown as the four bodies in your sky and in a panel:
  no-account / not-started / blocked / not-ready (per-holding verdicts) / fragile / ready.
- **No health, weapons, damage, vehicles or creatures.** Flight is kept as a free camera
  ("observer"); jumping and climbing stay.

### 3.6 On-chain events as phenomena (all labelled with block numbers)

| Event (how we detect it) | Phenomenon |
|---|---|
| Bars changed at this territory (per-block Multicall of `YUE.Bar`) | a pulse from the Core along the cascade path; the column rises |
| A new territory founded anywhere (`NewQing` log) | a named shooting star crosses every sky |
| A room line here (`LogEvent` 0xb916…) | a new line etches itself on the Room wall |
| A Void line (`LogEvent` 0x6b81… on Fomalhaute) | a whisper and ticker in the Void (and optionally a faint caption anywhere) |
| Your Beat confirmed | heartbeat shockwave (existing FX) |
| WORLD deployed (deployer nonce > 712, confirmed) | the lattice ignites everywhere; the launch kit unlocks |

### 3.7 Progression: chain-verified acts

The tutorial, XP and achievements are replaced by acts patterned on the site's `/start`. **Each level
is complete only when the chain says so.**

| Act | Levels (done when…) |
|---|---|
| Prologue | **Arrive**: you looked around a territory (local) |
| I · Identity | **Forge** (your wallet has a LAU) · **Name** (Username set) · **Bind** (CHO maps wallet → LAU) |
| II · Territory | **Wake** (YUE exists) · **Play** (no ZeroHoldings) · **First Su** (Bar > 0 anywhere) · **Open a door** (Admitted at a covered room, or your first room line) |
| III · Power | **Gather the four** (all holdings ok) · **First Beat** (probe passes / a Beat transaction) · **Range** (Yeo > 0 at N territories) |
| IV · WORLD *(latent)* | unlocks at deploy: first Code, first water |

Each level has three parts:
1. **Code first:** the real Solidity line it is about;
2. **Plain words:** one sentence;
3. **Your move:** simulate, then sign.

Lore and Codex chapters count as done when watched (stored locally). There are no invented points.
Status is shown as facts, e.g. "Bars at 7 territories · rank 12 of ≥55".

### 3.8 Honest UI

- **Facts, not numbers.** Every displayed value is a `Fact {value, source, block, state}` where
  `state ∈ loading / ok / empty / unavailable / stale / floor`.
  - A failed read shows "—", never 0.
  - Hovering shows the source, e.g. `QING.Entropy() · block 28,124,253`.
- **"How is this drawn?" (H):** an inspector for whatever is on screen, giving inputs → formula → result.
  For example: "Ground: filled Julia set of z²+c, c = −0.7453+0.1127i from Entropy 3.21e14 × 369 mod P
  and 0xd127…; style *bands*; rarity Epic."
- **Guide toggle** ("I'm new" vs "I know Dysnomia"): explanatory strips and underlined jargon on or off.
  No content is hidden behind it.
- **Absent is absent.** WORLD/WAR panels exist but say "not deployed" with the evidence.

### 3.9 Look & sound

- **Deep Field in 3D:**
  - **Base palette:** black `#030407` ground, ink `#e9edf4`, one ice accent `#a8e6ff`, plus a per-territory hue.
  - **Light:** comes from the filaments (emissive), the Core and Eris.
  - **UI:** black glass panels with hairline borders; Archivo display, Inter body, JetBrains Mono for
    every chain value (all OFL-licensed fonts, bundled).
  - **Rarity colours:** from `lib/rarity.js`.
- **Sound:** each territory's **score is generated from its number**, as in the site's `cinema.js`:
  - the root note is chosen from 5 by hash;
  - a pad on intervals 0/7/12/15;
  - pentatonic bells;
  - pre-rendered once per territory, not synthesized per sample every frame.
  - Event cues: a Su chime, the Beat thump, a soft tick per new chat line.
- **Out:** neon cantina, tomb, generic sci-fi greebles, meteor/flare/storm randomness, and "Ted" or
  "Predator" homages.

---

## 4. Architecture v2

### 4.1 Layout

```
scripts/
  core/      config.gd (autoload Config) · events.gd (autoload Events: signal bus) · session.gd (autoload Session)
  chain/     rpc.gd · bigint.gd · abi.gd · contracts.gd · multicall.gd · logs.gd · reads.gd · tx.gd · bridge.gd · (keccak.gd)
  data/      territory_registry.gd (autoload Registry) · player_registry.gd · site_api.gd · cache.gd
  state/     fact.gd · territory_state.gd · player_state.gd · readiness.gd · world_status.gd
  deepfield/ deep_field.gd (params) · julia.gd (CPU reference + heightfield) · palette.gd
  world/     terrain/ · sky/ · core/ (rod_cone, room, heart, wells) · bars_field.gd · world_lattice.gd · phenomena.gd
  field/     globe.gd · dossier.gd · warp.gd
  void/      void_hub.gd · onboarding.gd · monolith.gd
  player/    player_controller.gd · camera_rig.gd · bear_model.gd · gear.gd
  ui/        theme/ · hud/ (one scene per panel) · fact_label.gd · inspector.gd · tx_drawer.gd · quest/ · codex/
  audio/     score.gd · sfx.gd
scenes/      boot.tscn · void/void.tscn · field/field.tscn · territory/territory.tscn · ui/*.tscn
tests/       run.gd · test_*.gd · golden/*.json · fixtures/*.json
tools/       golden/gen.mjs (Node; reads entropy-ai-pulse) · preview_terrain.gd · update_snapshots.gd
assets/      data/territories.json · data/players.json · fonts/ (+ OFL.txt) · shaders/ · web/wallet.html
```

### 4.2 Rules of the road

- **One-way data flow:** chain/data layers → **state objects** (signals) → world and UI. Nothing in
  `world/` or `ui/` calls RPC directly. The HUD holds no business logic.
- **Big integers never become floats.**
  - `bigint.gd` works on hex strings / `PackedByteArray`: add, sub, cmp, xor, shr, mod-small,
    two's complement.
  - Conversion to float happens only for *display scaling*, and only via `log10` helpers.
- **State is viewer-independent** for territories (`TerritoryState`) and personal for the player
  (`PlayerState`). Visual scaling lives in one place (`palette.gd`/`territory_state.gd`), not 28 copies.
- **Scenes are composed in `.tscn`**, not built from 28 `Node3D.new()` calls in `main.gd`.
- **Deterministic** where it matters:
  - terrain and params are computed with 64-bit doubles on the CPU, hash-tested against golden values;
  - GPU shaders only add visual detail.

### 4.3 Chain layer

- **`rpc.gd`:**
  - a pool of ≤ 8 concurrent `HTTPRequest`s; **no JSON-RPC batches**;
  - 4 retries (300·2^i ms backoff), 25 s timeout; non-JSON responses count as failures;
  - EIP-1898 block pinning for snapshots;
  - configurable endpoint list, default `rpc.pulsechain.com`.
- **`multicall.gd`:** `aggregate3` in chunks of ≤ 300 calls, ≤ 6 chunks in flight; per-call success flags.
- **`logs.gd`:** 500k-block windows, halving on refusal down to 2k; remembers the node's limit;
  cursor per (address, topic).
- **`contracts.gd`:** the only place addresses, selectors, topics and error selectors live (copied
  from LEARNINGS §2–3), with a test that recomputes them.
- **`tx.gd`:**
  1. build calldata (abi.gd);
  2. simulate (`eth_call` from = wallet, decode the revert);
  3. send via the bridge;
  4. poll the receipt itself, check `status`, expected logs and state deltas;
  5. emit the result.
- **`bridge.gd` + `wallet.html` v2:** the page becomes a **thin EIP-1193 relay** —
  `eth_requestAccounts`, `eth_chainId`, switch/add chain 369, `eth_sendTransaction{from,to,data,value}`.
  - Godot builds the calldata, so no ethers and no CDN are needed (vendor nothing).
  - A random **session token** goes in the URL, and the WebSocket hello must echo it; other clients are rejected.
  - Never report chain 369 unless the wallet actually reports it.
  - Supabase and WebRTC are removed.

### 4.4 Data & caching

- **Territories:**
  - ship `territories.json` (a snapshot converted from the site's `qing-registry.json`, with its block cursor);
  - at boot, fetch `NewQing` logs after the cursor and Multicall the new ones' fields + `Compliment`;
  - persist to `user://` and merge live over the snapshot, so the result is never worse than the snapshot.
- **Players:** ship `players.json` (55); refresh from `systm0.vercel.app/data/players.json` when
  reachable; add yourself. The board is labelled as a floor.
- **Site accelerator (`site_api.gd`):**
  - base URL configurable, default `https://systm0.vercel.app`;
  - used for: `qing-chat`, `void-messages`, `d-entity`, `d-leaders`, `d-stats`, `world-watch`;
  - strict schema checks; every feature works without it (slower);
  - never used for XP/levels.
- **Cache policy:** immutable data (Waat, Entropy, coordinates, past logs, heightfields) is cached on
  disk; live data (bars, balances, admission) is never cached across sessions; outages are never cached.

---

## 5. Phases & work packages

Effort tags are recommendations for the coding session: **[H]** high (protocol, math, architecture),
**[M]** medium (UI, content, cleanup). Plan for one work package (WP) per session; small [M] WPs can pair.

**Milestones:**
- **M1 Viewport** = Phases 0–3: any of the 942 territories, walkable, Deep Field look, the Field globe,
  no wallet needed. A shareable demo.
- **M2 Live loop** = Phases 4–5.
- **M3 WORLD-ready** = Phase 6.
- **M4 v2.0** = Phase 7. Phase 8 is optional.

### Phase 0 — Foundations: the truth layer **[H]**
| WP | Work | Acceptance |
|---|---|---|
| 0.1 | **Test harness.** `tests/run.gd` (headless runner, non-zero exit on failure), `tools/check.sh` (import + tests). `tools/golden/gen.mjs` generates `tests/golden/` from entropy-ai-pulse: deep-field params for all territories, projection for all, selector list. | `godot --headless --path . -s res://tests/run.gd` runs and reports |
| 0.2 | **`contracts.gd`** from LEARNINGS §2–3 (addresses, selectors, topics, errors); fix the 4 selector bugs, ZUO → qZů, LOG_STORAGE = Void chat. | every selector test passes |
| 0.3 | **`bigint.gd` + `abi.gd`**: hex big-int ops; int256 two's complement; ABI encode/decode (address, uint/int, bool, string, bytes, arrays, tuples incl. `aggregate3` results, revert data). Replace `HexUtils` int64 parsing everywhere. | unit tests incl. negative int256, 240-bit coordinates, revert decoding |
| 0.4 | **`rpc.gd`, `multicall.gd`, `logs.gd`** per §4.3; remove the batch path. | fixture tests; a live smoke reads 942+ `NewQing` logs |
| 0.5 | **`fact.gd` + `FactLabel`** (the six states, source tooltip). | unit tests; "—" for unavailable |
| 0.6 | **Territory registry:** snapshot + catch-up + Multicall fields + `Compliment` + projection; delete `qing_map.json` / `qing_names.json` and the old map logic. | ≥ 942 territories; lat/lon equal the site's for all 940 overlapping entries |
| 0.7 | **`site_api.gd`** (systm0) + **switch off every dead endpoint and Supabase** behind flags (code deleted in 7.2). Fix the travel-hang cache race. | `grep -r "entropy-dysnomia\|supabase"` → 0 hits outside docs; the game still boots and loads a territory |

### Phase 1 — Deep Field core **[H]**
| WP | Work | Acceptance |
|---|---|---|
| 1.1 | **`deep_field.gd`**: exact port of `lib/deep-field.js` params (FNV-1a over hex, murmur fmix, 160-bit XOR/shift/add, coprime pick, tiers, styles, D, colours, extent). | **matches golden for every territory + 50 identity Auras** (floats ≤ 1e-12) |
| 1.2 | **Fractal shaders** (`deep_field.gdshader`, canvas + spatial) porting the GLSL (DE filaments, trap, styles); `julia.gd` CPU reference renderer. | emblem PNGs (CPU reference) for 12 territories covering each rarity/style, reviewed |
| 1.3 | **UI theme**: Theme resource, OFL fonts (Archivo, Inter, JetBrains Mono) + licences, rarity palette, panel styles. | a sample HUD panel renders with the theme |
| 1.4 | **Inspector framework** ("How is this drawn?"): any node registers {inputs, formula, sources}. | the inspector lists the active explanations |

### Phase 2 — Territory world v2 (read-only) **[H]**
| WP | Work | Acceptance |
|---|---|---|
| 2.1 | **Julia heightfield**: CPU doubles on `WorkerThreadPool`; the mapping in §3.4 (interior plateau + trap relief, DE ridges, ν terraces, blur, slope clamp); cached in `user://`. `tools/preview_terrain.gd` writes heightmap/hillshade PNGs. | hash-stable across runs; all territories generate at 129² in a batch test; PNG previews reviewed |
| 2.2 | **Terrain render + collision**: `HeightMapShape3D`; chunked mesh with 2 LODs + skirts; world-space shader with GPU DE filaments + palette/style; one height source for visuals and physics. | no float/sink; no view-space sliding; < 300 draw calls for terrain |
| 2.3 | **Sky**: Eris (fixed latitude sign), deterministic stars, a "you are here" Mandelbrot layer rendered once, no per-frame sky re-render, **DysnomiaTime from block timestamp**. | everyone sees the same time of day for the same block |
| 2.4 | **The Core**: Rod/Cone pylons (c, c̄) with mono inscriptions, the Room shell + door (no transaction yet), the Heart, three wells. Proportions from numbers. | the inspector explains each piece |
| 2.5 | **`TerritoryState`** (shared): identity, reservoirs, bar totals over known players, room stats → lit bands, wells, aurora. No viewer inputs in territory visuals. | two different wallets see identical territories |
| 2.6 | **Cut the old world**: monument, pub, antenna, pad, pipes, scatter/decals, creatures, weather family, vegetation, weapons, vehicle; `main.gd` → `territory.tscn` composition. | headless import clean; tests green; nothing references deleted scripts |

### Phase 3 — The Field & travel **[M]**
| WP | Work | Acceptance |
|---|---|---|
| 3.1 | **Globe** (MultiMesh points at projected coordinates; rarity/heat/age colouring; search; filters; founding replay). | all ≥ 942 points; filters work |
| 3.2 | **Dossier + warp** (emblem shader + facts → Julia-dive transition → load). | any → any travel works, including back-to-back |
| 3.3 | **Boot flow**: `boot.tscn` → registry → Void or Field; "Return to Field" from anywhere (no transaction); remove Leave/Void-as-exit and neighbour adjacency. | first launch goes to the Void; later launches respect the choice |

### Phase 4 — Identity, wallet & readiness **[H]**
| WP | Work | Acceptance |
|---|---|---|
| 4.1 | **Bridge v2** (§4.3): authenticated relay, chain-369 enforcement, `tx.gd` simulate → send → verify. | unauthenticated WS clients rejected; a user's 4001 rejection handled; receipts verified independently |
| 4.2 | **`PlayerState`**: wallet → LAU → YUE, Username, Pole/Soul/Aura (correct labels), holdings on wallet/LAU/YUE, CROWS/WITHOUT, PLS, pinned to one block. | read-only smoke on `players.json` wallets |
| 4.3 | **Readiness**: port `world-ready.js` (Code-order probe via Multicall3, standalone Beat, `RING.Eta` diagnosis, per-holding verdicts) → Readiness panel + the four bodies in the sky. | fixture tests per state; live smoke shows plausible states |
| 4.4 | **Enter the Void**: the 5-step onboarding, resumable from chain state, each step simulated → signed → verified. | manual test on a fresh wallet (user-run checklist) |
| 4.5 | **Avatar v2**: the clockwork LAU bear; Aura emblem; YI sigil; gear from facts; crow iff ≥ 25 CROWS; first-person hides the model. | no "Ted"/"Predator"/weapon remnants; gear toggles from fixture facts |

### Phase 5 — The live loop **[H]**
| WP | Work | Acceptance |
|---|---|---|
| 5.1 | **Su at the Core**: preview (+Ω Hypobar, +ο Epibar, Charge class, +1 YUE, gas) → sign → verify (bars re-read) → cascade pulse. | a Su previews exactly and reports success only after the receipt + bar delta |
| 5.2 | **Field of bars**: per-territory board (Multicall `YUE.Bar` over known players), crown, rival gap, per-block polling → pulses. | floor labelling when the player list is a snapshot |
| 5.3 | **Rooms**: door facts (CoverCharge/Asset/Admitted); Join (approve > cover → Join → verify Admitted); door dissolve; history (logs, accelerator optional) + live tail; post via `CHOA.Chat` (needs admission); OG/imposter badges. | only known QING emitters accepted; no chat without admission (the reason is shown) |
| 5.4 | **The Void**: monolith + panel; history from Fomalhaute logs (≥ block 21M); post via `LAU.Chat`. | "<name> text" parsed; names authenticated by the sending LAU |
| 5.5 | **Beat at the Heart**: readiness-gated; preview shows (Dione, Charge, Deimos, Yeo); existing FX ported. | a not-ready wallet sees the diagnosis instead of a doomed transaction |
| 5.6 | **Phenomena** (§3.6) + optional AFFECTION reactor (D5). | each phenomenon carries its block number |

### Phase 6 — WORLD: latent → live **[M] now, [H] at launch**
| WP | Work | Acceptance |
|---|---|---|
| 6.1 | **World watch**: deployer nonce (chain) + `world-watch` (site), stored as a fact; an empty address config; launch alert. | nothing reads "live" unless verified on-chain |
| 6.2 | **Range preview**: per territory, your Yeo/Dione/Charge/Deimos; the WORLD lattice around the Core (log-scaled); centre cell; the exact `Code(…)` call; the button disabled with the evidence. | matches the site's `world.html` for sample wallets |
| 6.3 | **Launch kit** (run when deployed): the smoke test from WORLD_LAUNCH_REVIEW §10; wire `Code` (simulate both argument orders once); claims index from calldata (no events); cell pillars (banked Hypobar) + king-of-the-hill; VITUS; `Faa`/H2O/CO2; GWAT bone pillars. | the post-deploy smoke test passes |

### Phase 7 — Progression, sound, polish, docs **[M]**
| WP | Work | Acceptance |
|---|---|---|
| 7.1 | **Acts** (§3.7) replace the tutorial; Guide toggle; Codex entries (Solidity line + plain words). | every level's completion is a chain predicate or a local "watched" flag |
| 7.2 | **Delete the dead**: the achievement/XP/flags/alliance/daily/emote/multiplayer/minigame code and their UI. | no unreachable code; import + tests green |
| 7.3 | **Sound**: per-territory score from its number (pre-rendered), event cues. | no per-sample GDScript loops in `_process` |
| 7.4 | **Input & UX**: one input map (no hard-coded keys), consistent controls help, settings that actually apply (render distance, volumes). | key docs match the code |
| 7.5 | **Performance pass**: 60 fps target on a mid-range GPU at High; budgets for draw calls and lights; no per-frame allocations in hot paths. | measured with the monitor overlay |
| 7.6 | **Docs**: README, BUILDING, `dysnomia-game-spec.md` → v2, release checklist (debug presets stripped). | docs match the build |

### Phase 8 — Lore content (optional) **[M]**
- Court of Nine Emotions clearing (clockwork bears from the `atropa/assets/bionika` data).
- Folklore `.fkc` cartridge screens.
- DEFCON alarm (emerald → ruby).
- Federal Worker newcomer quest.
- A Nym hall (needs the contract address).

### Status board (coding sessions: tick these as WPs land)
```
P0  [x] 0.1 [x] 0.2 [x] 0.3 [x] 0.4 [x] 0.5 [x] 0.6 [x] 0.7      (2026-11-22)
P1  [x] 1.1 [x] 1.2 [x] 1.3 [x] 1.4                      (2026-11-22)
P2  [x] 2.1 [x] 2.2 [x] 2.3 [ ] 2.4 [ ] 2.5 [ ] 2.6
P3  [ ] 3.1 [ ] 3.2 [ ] 3.3                                   ── M1 Viewport
P4  [ ] 4.1 [ ] 4.2 [ ] 4.3 [ ] 4.4 [ ] 4.5
P5  [ ] 5.1 [ ] 5.2 [ ] 5.3 [ ] 5.4 [ ] 5.5 [ ] 5.6           ── M2 Live loop
P6  [ ] 6.1 [ ] 6.2 [ ] 6.3 (at launch)                       ── M3 WORLD-ready
P7  [ ] 7.1 [ ] 7.2 [ ] 7.3 [ ] 7.4 [ ] 7.5 [ ] 7.6           ── M4 v2.0
```

---

## 6. Verification

1. **Engine:** download Godot **4.6.1** (the project targets 4.6) into the session scratchpad:
   `https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_linux.x86_64.zip`.
2. **Import check:** `godot --headless --import --path .`. This was clean on 2026-11-22.
   - Don't rely on per-script `--check-only`: it reports false "Identifier not found" errors for autoload singletons.
3. **Tests:** `godot --headless --path . -s res://tests/run.gd`. Pure logic: bigint/ABI, selectors,
   projection vs golden, Deep Field params vs golden, readiness classification vs fixtures, heightfield hashes.
4. **Previews without a GPU:** `tools/preview_terrain.gd` writes heightmap/hillshade/emblem PNGs from the
   CPU reference, so terrain and art can be reviewed as images.
5. **Live read-only smoke (opt-in):** territory count, a sample of registry facts, readiness for a few
   public player wallets. It never sends transactions.
6. **Rendered screenshots:** Xvfb + lavapipe (CPU Vulkan) + `--write-movie` should work in the cloud
   container, but the permission system blocked it this session. Either the user allows it, or the
   user runs locally (F5) and shares screenshots. **Every visual WP ends with a screenshot review by one
   of those routes.**
7. **Wallet flows:** each phase that adds a write ships a short manual test checklist for the user
   (a fresh wallet and an onboarded wallet), because signing needs a real browser wallet.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Julia terrain turns out jagged or unwalkable | previews first (2.1); blur + slope clamp + terraces; fallback: keep Julia only in shading/filaments, with low-frequency relief derived from the same numbers |
| GDScript too slow for heightfields | `WorkerThreadPool`, on-disk cache, 257² default with 513² optional; a GPU readback path as plan B |
| Deep Field port drifts from the site (FNV over hex string formatting, 160-bit ops) | golden vectors generated by the real JS; tests over every territory |
| WORLD launch specifics are unknown (argument order, `tx.origin` path, guards) | simulate before any send; the launch kit is a separate WP run at deploy time |
| Public RPC throttling | Multicall3, ≤ 8 in flight, backoff, caching of immutable data, site accelerator |
| A tiny player base makes the world feel empty | history as presence: columns for everyone who ever reacted, room walls of past lines, founding replay, Void scroll |
| Scope | milestones are independently shippable; M1 needs no wallet at all |

---

## 8. Decisions needed (defaults in **bold**, used unless you say otherwise)

| # | Decision | Default | Alternative |
|---|---|---|---|
| D1 | Visual direction | **Deep Field in 3D** (fractal ground, black/ice palette, Eris sky) | keep lunar realism with Deep Field accents |
| D2 | Cut list (weapons, vehicle, creatures, minigames, pub/tomb/antenna/pad/pipes, weather events, vegetation) | **cut all** | keep some as off-chain fun, clearly labelled |
| D3 | Backend | **chain-direct + systm0 as an optional accelerator; no new game server** | revive a game backend (needs Redis/DB + wallet-signature auth) for XP/flags/alliances |
| D4 | Realtime multiplayer (Supabase is gone) | **drop for now; presence = chain history** | rebuild live presence later on a new service |
| D5 | AFFECTION ops | **keep as a small, honestly labelled reactor in the Void** | remove entirely |
| D6 | Avatar | **clockwork LAU bear** (original, lore-based) | the site's creature avatars (orb/crystal/ghost/…) |
| D7 | Platforms | **desktop native** (Win/macOS/Linux; the wallet runs through the system browser) | a web export later (needs CORS/CSP changes on the site + an in-page wallet) |

---

## 9. Later / out of scope for v2

- Nym (needs its address).
- Folklore cartridges.
- Mobile.
- `WORLD.Distribute` governance UI.
- Deterministic/signed release builds and the AI-agent verification endpoint (from the Feb spec).
- Re-hosting the old off-chain features.
