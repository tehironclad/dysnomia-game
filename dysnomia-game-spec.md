# Dysnomia: The Game — Specification v2

> v2, 2026-11-23. It replaces the February 2026 spec, whose on-chain mechanics were partly wrong. For
> example, AFFECTION calls do not terraform anything.
> - **Facts** (addresses, selectors, formulas, coordinates, RPC rules) live in [`docs/LEARNINGS.md`](docs/LEARNINGS.md).
>   Where this spec and LEARNINGS disagree, LEARNINGS wins.
> - **The plan and its status board** live in [`docs/REWORK_PLAN.md`](docs/REWORK_PLAN.md).

## 1. What it is

Dysnomia is a viewport onto a living on-chain organism on PulseChain (chain 369).

- Every territory (QING) is drawn from its own numbers.
- Every change you see was made by a real transaction.
- Every number on screen carries its source and its block.

It is a game built in **Godot 4.6** (Forward+, Jolt physics, GDScript), shipped as a standalone binary.
The source is open.

### Maria's architecture, as it stands on chain

| Phase | Meaning | Status |
|---|---|---|
| **Terra** | per-territory reactions build data on your identity | live |
| **Firma** | WORLD/WAR/GWAT: claiming cells, water, bone pillars | **written, not deployed** (deployer nonce 712) |
| **Life** | real-world data through YUE extensions | future |

The Terra reactions are Su and CHOA.Chat; the data they build is your bars.

**Design principle:** render contract state faithfully, and never invent it. Minimal code, correct by default.

## 2. The truth contract

1. **Never fabricate chain-shaped data.** Loading, empty, unavailable, zero and floor are different
   states. A failed read shows "—".
2. **Every number carries its source and block.** Press H, the Inspector, to see how anything on screen
   was computed.
3. **Every write goes simulate → sign → verify → re-read.**
   - The simulation is an `eth_call` from the wallet, and reverts are decoded.
   - The browser wallet only signs.
   - The game reads the receipt itself, and reports success only after re-reading state.
4. **`tx.origin` reads need `from` = the wallet.** That covers Su, Beat, Eta, Yuan, Power and others.
5. **Big integers never become floats.** Coordinates are about 240-bit int256 values.
6. **No JSON-RPC batches.** Use Multicall3 `aggregate3`.
7. **No guessed addresses.** WORLD-family contracts are found on chain (§6), never hardcoded.
8. **Territory visuals depend only on territory state.** Personal overlays (your range, the "YOU" tag)
   are opt-in and look like overlays.

## 3. The player's loop

| Where | What | Chain |
|---|---|---|
| **Front door** | the Field, territory search and warp, wallet, Enter the Void, Guide, settings | — |
| **Enter the Void** | Forge → Bind → Name → Wake → Play, each ticked only by a chain predicate | `LAUFactory.New`, `CHO.Enter`, `LAU.Username`, `SEI.Start`, `CHOA.Play` |
| **The Field** | the globe of all territories (rarity, heat, age); founding replay; warp | snapshot + `NewQing` catch-up |
| **A territory** | walk its Julia-set ground; the Core at its centre | `TerritoryState`, one Multicall per block |
| Pylons (Rod, Cone) | **Su**: preview exact bar deltas, Charge, +1 YUE, gas → sign → bar re-read at the receipt block | `CHEON.Su(QING)` |
| The Room's door | door facts; **Join** (approve cover + 1 wei, then Join, then Admitted verified); room lines; post | `QING.Join`, `CHOA.Chat`, `LogEvent 0xb916…` |
| Centre of the Room | **Beat**, gated by readiness (a not-ready wallet sees the four-holdings diagnosis instead) | `META.Beat(Waat)` |
| The plinth | **WORLD range preview**: Dione, Charge, Deimos, Yeo; the centre cell; the exact `Code(…)` call; button disabled with its evidence | latent |
| The monolith | **The Void**: one board for everyone | Fomalhaute `LogEvent 0x6b81…`, `LAU.Chat` |
| Columns behind the Room | the field of bars: one column per known player, crown on the leader | `YUE.Bar(QING)` |

Progression is the **acts** (Prologue, I Identity, II Territory, III Power, IV WORLD). The Guide (G)
shows them.
- Each level is complete only when the chain says so, or when a local flag was set after a
  chain-verified event.
- Each level carries its codex entry: the call, plain words, and where to do it.

## 4. Mechanics

These are summarised here; the formulas are in LEARNINGS §4–§6.

- **Su / CHOA.Chat at Q**:
  - Hypobar[Q] += Ω = ⌊Fornax(Q) / Entropy(Q)⌋. Ω is the same for everyone.
  - Epibar[Q] += ⌊Fornax(LAU) / entropy_p⌋.
  - Su mints +1 YUE. It doesn't need Join.
- **Charge(Q)** = modExp(QI, MAI, Fomalhaute(LAU)).
  - It is 0 without Fomalhaute on the LAU.
  - It is 1 without Q's token on the LAU.
- **Beat** needs four holdings: Fomalhaute and Fornax on the LAU, Tethys and qZů anywhere. With any one
  missing, it panics with 0x12.
- **Readiness** is the site's Code-order probe, `[CHEON.Su(Phobos), META.Beat(Phobos Waat)]` from the
  wallet. The result is one of: no-account, not-started, blocked, not-ready, fragile, ready.
- **Rooms**:
  - The cover is paid in the room's asset; Join needs allowance > cover.
  - Admission lasts one day and is keyed to the LAU.
  - WITHOUT bans the holder; ≥ 25 CROWS makes a universal bouncer.
- **Names are not unique.** A line's Aura (the speaking LAU's Saat(2)) authenticates it against the
  name's owner. The result shows as ✓ OG or ⚠ imposter.

## 5. Visuals: Deep Field

The site's `lib/deep-field.js` is ported exactly, with golden vectors from the real JS.
- **The ground:** each territory's ground is its own Julia set as a heightfield.
- **The sky:** stars seeded from the address; a Mandelbrot "you are here"; Eris at its true 3.57°; a
  faint sun at about 96 AU.
- **Time:** DysnomiaTime (34 h × 100 m × 34 s per day) from the block timestamp.
- **The Core:** Rod and Cone plates (c and its mirror c̄), the Room, the Heart, and three wells (Fornax,
  Eris, Tethys held by the territory).
- **Phenomena** carry their block numbers:
  - bar cascades;
  - room lines etched on the wall;
  - Void lines on the monolith;
  - a shooting star for each new territory;
  - the lattice lights up when WORLD goes live.
- **The avatar** is the clockwork LAU bear.
  - Its appearance comes from Soul and Aura.
  - Its gear comes from chain facts: grey without bars; a spark at 3+ territories with bars; a ring at
    10+; a halo while leading; a crown only when the site ladder confirms #1.
  - The crow appears only at ≥ 25 CROWS.
- **Sound:** each territory has a score rendered once from its own numbers; event cues are tied to
  chain events.

## 6. WORLD: latent → live

`World` watch checks whether WORLD has been deployed, using the chain only.
1. It reads the deployer's nonce.
2. It checks for code at the deployer's precomputed CREATE addresses.
3. It classifies any contract by its PUSH4 selectors.
4. A WORLD only counts if its `Cheon()`, `Meta()` and `Map()` return the real contracts.

Nothing reads "live" until then; the site's world-watch is only corroboration.

At launch, WP 6.3 runs. It:
- simulates both `Code` argument orders once;
- wires `Code`;
- indexes claims from calldata;
- adds cell pillars (king of the hill), VITUS, Faa/H2O and GWAT bone pillars.

## 7. Architecture

| Layer | Pieces |
|---|---|
| Chain | `BigInt` (base 2^24 limbs), `Abi`, `Contracts` (selectors keccak-verified), `Rpc` (≤ 8 in flight, retries), `Multicall`, `LogScanner` (windowed), `WalletBridge` (local HTTP+WS, session token) |
| Autoloads | `Config`, `Chain`, `Registry` (territories), `Players`, `Wallet`, `Session`, `World`, `Inspector`, `GameManager` |
| State | `Fact`, `TerritoryState`, `PlayerState`, `Readiness`, `RoomState`, `Moves`, `ChatLog`, `Acts`, `World` watch |
| Deep Field | `DeepField` (params), `JuliaHeightfield` (CPU, cached), `DeepFieldView` (shader), CPU reference renderer |
| World | `territory_v2` (zones and input), `TerritoryCore`, `BarColumns`, `WorldLattice`, `VoidMonolith`, `Phenomena`, `CoreActions`, `DeepFieldSky`, `DeepFieldTerrain` |
| UI | the front door, IdentityCard, OnboardingPanel, HudV2, TerritoryCard, ActionPanel, ChatPanel, GuidePanel, ControlsHelp, Settings |
| Audio | `TerritoryScore`, `Cues` (Music and SFX buses) |

## 8. Distribution

There are standalone builds for Windows, macOS and Linux. Debug presets are stripped (see
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)).
- The game needs only a PulseChain RPC.
- The site API is an optional accelerator.
- Signing happens in the player's own browser wallet, through the local relay page.
