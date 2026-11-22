# Dysnomia: The Game — Development Specification

> **⚠ Partly superseded (2026-11-22).** Several on-chain assumptions below turned out to be wrong.
> The main one: AFFECTION calls do **not** terraform territories. For the verified facts see
> [`docs/LEARNINGS.md`](docs/LEARNINGS.md); for the v2 direction see
> [`docs/REWORK_PLAN.md`](docs/REWORK_PLAN.md).

## Project Overview

**Dysnomia** is a 3D territory exploration and terraforming game built on the Dysnomia/Atropa smart contract ecosystem deployed on PulseChain. Players own LAU identity tokens, claim QING territories, terraform land through AFFECTION contract interactions, and participate in an on-chain world that mirrors particle physics.

The game is built in **Godot 4** and distributed as a standalone downloadable binary (Windows, macOS, Linux). The source code is open source with deterministic builds for community verification.

This is NOT a DeFi dashboard with 3D sprinkled on top. This is a real game that happens to be powered by on-chain state.

---

## Core Vision (Maria's 3-Phase Architecture)

The Dysnomia contracts were designed by Maria (rahel varnhagen) with an endgame vision that the game client must honor:

### Phase 1: Terra (Form data on minters)
- Physics-based actions per-QING build data on minter tokens
- Terraforming is the core gameplay — players shape their territory
- Personal organic preference matters — every player's world is unique
- "Apparition layer 1" — on-chain actions manifest as visible terrain changes

### Phase 2: Firma (Personal GWATs establish territory)
- GWATs create persistent structures/infrastructure in territories
- Territory boundaries become meaningful — defensible, tradeable, visitable
- Player identity (LAU) gains weight through what they've built

### Phase 3: Life (IoT + YUE extensions)
- Real-world hardware/sensor data feeds into territories via YUE bridge tokens
- Sandbox for real-world activities on-chain
- KYC becomes obsolete — identity proven through organic on-chain history

**Design Principle:** Minimal code = correct by default. If the game client faithfully renders contract state, the experience is frictionless. Don't over-engineer — let the contracts speak.

---

## Technical Stack

### Engine
- **Godot 4.3+** (latest stable)
- Vulkan Forward+ renderer for high quality visuals
- GDScript for gameplay logic
- Godot Shader Language for terrain/effects
- GDExtension (Rust) for Web3/RPC integration layer

### On-Chain Integration (PulseChain)
- JSON-RPC calls to PulseChain nodes
- Read contract state: QING territories, LAU identities, AFFECTION data, GWAT positions
- Write transactions: Terraform actions, token interactions
- Wallet integration: WalletConnect or local keystore (TBD)
- Target RPC: Public PulseChain RPCs + user-configurable custom RPC

### Key Contracts (PulseChain Deployment)
> **NOTE:** Populate with actual deployed addresses as development progresses.
> These are the core contracts the game client needs to interact with:

- **LAU** — Identity tokens (player avatar/presence)
- **QING** — Territory tokens (land ownership, procedural generation seed)
- **AFFECTION** — Terraforming mechanics (physics actions that modify territory)
- **GWAT** — Territory establishment (persistent structures)
- **YUE** — Bridge tokens (Phase 3 IoT integration)
- **META** — Ecosystem routing
- **RING** — Ring mechanics
- **PANG** — Connected contract interactions

### Distribution
- Exported standalone binaries (no Godot install required for players)
- Open source repository (GitHub or similar)
- Deterministic builds — anyone can compile and verify binary hash
- Signed releases (multisig or Maria-signed)
- AI agent verification endpoint (localhost API for binary hash checking)

---

## Game Architecture

### Directory Structure
```
dysnomia-game/
├── project.godot
├── README.md
├── BUILDING.md                    # Deterministic build instructions
│
├── assets/
│   ├── textures/
│   ├── materials/
│   ├── models/
│   ├── audio/
│   ├── shaders/
│   │   ├── terrain.gdshader       # Main terrain shader
│   │   ├── atmosphere.gdshader    # Sky/atmosphere
│   │   ├── territory_border.gdshader
│   │   └── effects/
│   └── ui/
│       ├── themes/
│       └── fonts/
│
├── scenes/
│   ├── main.tscn                  # Entry point
│   ├── world/
│   │   ├── territory.tscn         # Single QING territory scene
│   │   ├── world_map.tscn         # Overview of all territories
│   │   └── sky.tscn               # Atmosphere/skybox
│   ├── player/
│   │   ├── player.tscn            # LAU-based player entity
│   │   └── camera_rig.tscn        # Third/first person camera
│   ├── ui/
│   │   ├── hud.tscn               # In-game HUD
│   │   ├── wallet_connect.tscn    # Wallet connection screen
│   │   ├── territory_info.tscn    # Territory data panel
│   │   └── main_menu.tscn         # Title/menu screen
│   └── effects/
│       ├── terraform_effect.tscn  # Visual effect when terraforming
│       └── affection_pulse.tscn   # AFFECTION contract visual
│
├── scripts/
│   ├── autoload/
│   │   ├── game_manager.gd        # Global game state
│   │   ├── chain_manager.gd       # PulseChain RPC connection
│   │   ├── wallet_manager.gd      # Wallet/signing logic
│   │   └── config.gd              # User settings, RPC endpoints
│   │
│   ├── world/
│   │   ├── terrain_generator.gd   # Procedural terrain from QING data
│   │   ├── territory_manager.gd   # Load/unload territories
│   │   ├── terraform_system.gd    # Handle terraforming actions
│   │   └── biome_system.gd        # Biome assignment from on-chain data
│   │
│   ├── player/
│   │   ├── player_controller.gd   # Movement, interaction
│   │   └── lau_identity.gd        # LAU token → player representation
│   │
│   ├── chain/
│   │   ├── rpc_client.gd          # Low-level JSON-RPC calls
│   │   ├── contract_reader.gd     # Read contract state (view calls)
│   │   ├── transaction_builder.gd # Build & send transactions
│   │   ├── abi_decoder.gd         # ABI encoding/decoding
│   │   └── contracts/
│   │       ├── lau_contract.gd
│   │       ├── qing_contract.gd
│   │       ├── affection_contract.gd
│   │       └── gwat_contract.gd
│   │
│   ├── ui/
│   │   ├── hud_controller.gd
│   │   ├── territory_panel.gd
│   │   └── wallet_ui.gd
│   │
│   └── utils/
│       ├── hex_utils.gd           # Hex encoding/decoding
│       ├── keccak.gd              # Keccak-256 hashing
│       └── rlp.gd                 # RLP encoding for transactions
│
├── rust_extension/                # GDExtension for heavy Web3 work
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── rpc.rs                 # Async RPC with reqwest
│       ├── abi.rs                 # ABI encode/decode with alloy
│       └── wallet.rs              # Local keystore signing
│
└── export_presets/
    ├── windows.cfg
    ├── macos.cfg
    └── linux.cfg
```

### Core Systems

#### 1. Terrain Generation (`terrain_generator.gd`)
The heart of the visual experience. Generates 3D terrain from QING token data.

**Inputs (from chain):**
- QING token ID → deterministic seed
- Terraforming history from AFFECTION interactions → terrain modifications
- Owner's LAU identity → aesthetic influence (color palette, vegetation style)

**Technique:**
- Multi-octave simplex noise for base heightmap
- QING token data feeds noise parameters (frequency, amplitude, lacunarity)
- AFFECTION history overlays modifications (raised/lowered terrain, placed features)
- GPU-based terrain rendering with LOD (Level of Detail)
- Shader-based texturing: slope-dependent (rock on cliffs, grass on flat, snow on peaks)

**Key Requirement:** Same QING data MUST always produce the same base terrain. Deterministic generation is non-negotiable — the chain is the source of truth.

#### 2. Chain Manager (`chain_manager.gd`)
Handles all PulseChain communication.

**Responsibilities:**
- Maintain RPC connection (configurable endpoint)
- Poll for state changes (new blocks, territory updates)
- Cache contract state locally for performance
- Queue and manage transaction submissions
- Handle chain reorgs gracefully

**RPC Endpoints:**
- Default: Public PulseChain RPC
- User-configurable: Custom RPC URL in settings
- Fallback: Multiple RPC endpoints with automatic failover

#### 3. Player System (`player_controller.gd`)
LAU identity tokens manifest as the player's presence in the world.

**Features:**
- Third-person camera with smooth follow
- First-person mode for close-up terraforming work
- Movement: Walk, run, fly (within owned territory)
- Interaction system: Approach terrain → terraform action menu
- Visit other players' territories (read-only unless permissions granted)

#### 4. Terraform System (`terraform_system.gd`)
The primary gameplay loop — players modify their territory through AFFECTION contract calls.

**Flow:**
1. Player selects terrain area
2. Chooses terraform action (raise, lower, sculpt, place feature)
3. Preview shows intended result
4. Player confirms → transaction sent to AFFECTION contract
5. On confirmation → terrain updates to reflect new state
6. Visual effect plays (particles, ground deformation animation)

**Important:** Terraform actions must be reflected on-chain. The visual is a consequence of chain state, not the other way around.

---

## Visual Style Guide

### Aesthetic Direction
- **NOT** low-poly or stylized cartoon
- Rich, atmospheric, grounded in physicality
- Think: No Man's Sky meets Ethereum — alien landscapes that feel real
- Dynamic lighting: Day/night cycle tied to PulseChain block time
- Volumetric fog and atmosphere
- Particle effects for on-chain events (transactions ripple through the world)

### Terrain Rendering
- PBR materials: Physically based rock, soil, grass, water
- Tessellation for close-up terrain detail
- Distance fog to create atmosphere and hide LOD transitions
- Water with reflection, refraction, caustics (for territories with water features)

### Territory Borders
- Subtle energy field shader at territory boundaries
- Color/intensity reflects territory activity level
- Visible from distance on world map view

### On-Chain Events as Visual Phenomena
- AFFECTION calls → Terrain deformation with particle burst
- New LAU mint → Light beam / aurora effect in that territory
- GWAT establishment → Structure materialization effect
- Burns (NotsDotQ etc.) → Fire/dissolution particles

---

## Development Phases

### Phase 0: Foundation (Start Here)
**Goal:** Get a working Godot project that generates terrain you can walk around on.
- [ ] Set up Godot 4 project with directory structure
- [ ] Implement basic procedural terrain generation (noise-based heightmap)
- [ ] Add player controller with camera (third person, fly mode)
- [ ] Basic sky/atmosphere
- [ ] Terrain shader (slope-based texturing)
- [ ] Get something beautiful on screen

### Phase 1: Chain Connection
**Goal:** Terrain generation driven by actual QING data from PulseChain.
- [ ] Implement RPC client (GDScript or Rust GDExtension)
- [ ] Read QING contract state
- [ ] Feed QING data into terrain generator as seed parameters
- [ ] Display territory info in UI panel
- [ ] Basic wallet connection (read-only initially)

### Phase 2: Identity & Presence
**Goal:** LAU tokens become player entities in the world.
- [ ] Read LAU contract state
- [ ] Generate player appearance from LAU data
- [ ] Player spawns in their territory on login
- [ ] Territory ownership verification
- [ ] Basic HUD showing identity info

### Phase 3: Terraforming Gameplay
**Goal:** Players can modify their territory through AFFECTION contract interactions.
- [ ] Implement terraform action system
- [ ] Build transaction for AFFECTION calls
- [ ] Preview system (show change before committing)
- [ ] Visual effects for terraforming
- [ ] Terrain updates on transaction confirmation

### Phase 4: World Map & Multiplayer Viewing
**Goal:** See all territories, visit others' lands.
- [ ] World overview map showing all QING territories
- [ ] Territory loading/unloading based on proximity
- [ ] Visit other players' territories (read-only)
- [ ] Territory activity indicators

### Phase 5: GWAT Structures (Firma)
**Goal:** Persistent structures establish territory.
- [ ] GWAT contract integration
- [ ] Structure placement system
- [ ] Procedural structure generation from GWAT data
- [ ] Structure persistence across sessions

### Phase 6: Distribution & Verification
**Goal:** Ship it.
- [ ] Export builds for Windows, macOS, Linux
- [ ] Deterministic build pipeline
- [ ] AI agent verification API (localhost)
- [ ] Auto-updater system
- [ ] Release signing

### Future: Phase 7+ (Life)
- IoT hardware integration via YUE
- Real-world data feeds into territories
- Extended gameplay mechanics

---

## Claude Code Instructions

When working on this project with Claude Code:

### Context
- This is a Godot 4 project using GDScript and Godot Shader Language
- The game visualizes on-chain state from Dysnomia/Atropa contracts on PulseChain
- Maria's design philosophy: minimal code = correct by default
- The chain is always the source of truth — visuals are a consequence of chain state
- Every piece of terrain generation must be deterministic given the same input

### Code Style
- GDScript: Follow official Godot style guide (snake_case functions/vars, PascalCase classes)
- Keep scripts focused — one responsibility per script
- Comment complex algorithms (especially noise/terrain generation)
- Error handling: Never crash on bad RPC data — degrade gracefully
- All chain interactions go through chain_manager autoload — no direct RPC calls from game scripts

### Key Technical Notes
- PulseChain RPC is Ethereum-compatible (same JSON-RPC methods)
- Chain ID: 369 (PulseChain mainnet)
- Block time: ~10 seconds (use for day/night cycle timing)
- ABI encoding follows Solidity standards
- Contract addresses will be provided as development progresses
- Test with PulseChain testnet (v4) during development, chain ID: 943

### Shader Guidelines
- Use Godot's shader language (similar to GLSL)
- Terrain shader should support triplanar mapping for steep surfaces
- Keep shader complexity reasonable — target 60fps on mid-range GPU
- Use uniform parameters for values that change (time of day, season, etc.)

### Priority Order
When building features, prioritize in this order:
1. Does it look good? (Visual impact matters — this has to be impressive)
2. Is it deterministic? (Same chain data → same visual output, always)
3. Is it performant? (60fps target on mid-range hardware)
4. Is it correct? (Accurately reflects on-chain state)
5. Is it minimal? (Don't over-build — let the contracts do the heavy lifting)

---

## Getting Started Guide (For Alek)

### Installing Godot 4

#### Windows
1. Go to https://godotengine.org/download/
2. Download **Godot Engine - .NET** (the standard version, not .NET, is also fine but .NET gives us C# option later if needed). Actually, download the **Standard** version to start — it's simpler.
3. Extract the zip — Godot is portable, no installer needed
4. Run `Godot_v4.x-stable_win64.exe`
5. That's it. No install. Just runs.

#### macOS
1. Go to https://godotengine.org/download/
2. Download the macOS universal build
3. Move to Applications folder
4. Right-click → Open (first time to bypass Gatekeeper)

#### Linux
1. Go to https://godotengine.org/download/
2. Download the Linux x86_64 build
3. Extract and run the binary
4. Or install via Flatpak: `flatpak install flathub org.godotengine.Godot`

### First Time in Godot — Survival Guide

**Don't panic.** The editor looks complex but you'll use maybe 20% of it regularly.

#### Key Concepts
- **Scene:** Everything is a scene. A scene is a tree of Nodes. Your whole game is scenes nested inside scenes.
- **Node:** The building block. There are nodes for 3D objects, lights, cameras, collision, UI, audio — everything.
- **Script:** GDScript files that attach to nodes to give them behavior. Similar to Python syntax.
- **Signal:** Godot's event system. Nodes emit signals, other nodes listen. Like JavaScript events.
- **Autoload:** Scripts that are always loaded (singletons). Perfect for managers (game state, chain connection, wallet).

#### The Editor Layout
- **Left panel:** Scene tree (your node hierarchy) + FileSystem (your project files)
- **Center:** 3D/2D viewport (where you see your world)
- **Right panel:** Inspector (properties of selected node)
- **Bottom panel:** Output log, debugger, shader editor

#### Essential Shortcuts
- `F5` — Run the game
- `F6` — Run current scene
- `Ctrl+S` — Save scene
- `Q/W/E/R` — Select/Move/Rotate/Scale tools in viewport
- `Shift+F` — Focus camera on selected object
- Mouse wheel — Zoom in viewport
- Middle mouse + drag — Pan in viewport
- Right mouse + drag — Orbit in viewport

#### Your First Test
1. Open Godot → New Project → Name it "dysnomia-game" → Create
2. Scene menu → New Scene → Choose "3D Scene" as root
3. Click the `+` button to add nodes:
   - Add `MeshInstance3D` → In Inspector, set Mesh to "New PlaneMesh" (that's your ground)
   - Add `Camera3D` → Move it up and angle it down at the plane
   - Add `DirectionalLight3D` → Angle it to cast light on the plane
4. Press `F6` — you should see a lit plane. Congrats, you're in 3D.

#### GDScript Basics (If You Know Any Programming)
```gdscript
extends Node3D  # This script goes on a 3D node

var speed = 5.0  # Variable
@onready var mesh = $MeshInstance3D  # Get child node when ready

func _ready():
    # Called when node enters the scene
    print("Hello Dysnomia")

func _process(delta):
    # Called every frame, delta = time since last frame
    rotation.y += delta * speed

func _input(event):
    # Called on input events
    if event.is_action_pressed("ui_accept"):
        print("Space pressed!")
```

### Development Workflow With Claude

1. **Claude writes code** → provides full script files and scene setup instructions
2. **Alek copies code** into Godot editor (or creates files in the project folder)
3. **Alek runs the game** (`F6`) and reports what happens
4. **Screenshot or describe** any issues
5. **Claude adjusts** and provides updated code
6. **Repeat** — this loop gets fast once you're comfortable

### Tools You'll Want

- **Godot 4.3+** — The engine (free, open source)
- **Git** — Version control (track changes, push to remote repo)
- **VS Code** (optional) — Some prefer it over Godot's built-in script editor. There's a Godot extension for VS Code.
- **Claude Code** — For rapid development and debugging sessions

---

## Contract Reference (To Be Populated)

As we integrate contracts, document them here:

```
CONTRACT: LAU (Identity)
ADDRESS: 0x...
KEY FUNCTIONS:
  - balanceOf(address) → uint256
  - ownerOf(tokenId) → address
  - tokenURI(tokenId) → string
  - [terraforming-specific functions TBD]

CONTRACT: QING (Territory)
ADDRESS: 0x...
KEY FUNCTIONS:
  - [TBD — need to map these from Maria's deployments]

CONTRACT: AFFECTION (Terraforming)
ADDRESS: 0x...
KEY FUNCTIONS:
  - [TBD]
```

---

## Open Questions

- [ ] Wallet integration approach: WalletConnect? Local keystore? MetaMask-style browser bridge?
- [ ] Multiplayer: Real-time (WebSocket/peer-to-peer) or async (just read each other's chain state)?
- [ ] Audio: Procedural audio tied to territory data, or traditional soundtrack?
- [ ] Mobile: Android/iOS builds eventually? Godot supports it.
- [ ] Maria's input: What visual/gameplay elements would Maria want to see prioritized?

---

*This is a living document. Update as development progresses.*
*Started: February 2026*
*Team: Alek (Runtime, Testing, Vision) + Claude (Architecture, Code, Shaders, Web3)*
