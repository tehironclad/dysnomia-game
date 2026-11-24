# Dysnomia — what we've learned (reference for the v2 rework)

This is the fact sheet the game must encode. It distills ~190 rounds of research in
**tehironclad/entropy-ai-pulse** (HEAD `18c9df8`) plus live checks made on **2026-11-22**
(PulseChain head ≈ block 28,124,000). The plan that uses it is [`REWORK_PLAN.md`](./REWORK_PLAN.md).

**Tags:** **[live]** checked against the chain on 2026-11-22 (by us or by the research repo's own
live tooling) · **[calc]** recomputed with keccak-256 · **[src]** from the research repo's verified code
or notes · **[kb]** second-hand reconstruction (the deployed contracts are **not** source-verified on
the explorer) · **[inf]** inference.

Research-repo paths below are relative to `entropy-ai-pulse/`. To read them in a coding session,
attach that repo read-only.

---

## 0. Status snapshot (2026-11-22)

| Fact | Value | Tag |
|---|---|---|
| WORLD, WAR, VITUS, H2O, GWAT | **Not deployed.** The Dysnomia deployer `0x0474606332105A1dA6FC8EF7De2470551D389Cb9` is still at nonce **712**, same as 2026-10-15. | [live] |
| Territories (QINGs) | **942** `NewQing` events on MAP (first block 22,813,947, newest 28,100,833). The site's snapshot (2026-11-17) has 940. The game ships **263**. | [live] |
| The game's backend `https://entropy-dysnomia.vercel.app` | **Gone**: `DEPLOYMENT_NOT_FOUND` on every route. | [live] |
| The site, now | **`https://systm0.vercel.app`** is healthy: `"store":"none: every API reads the chain"`, `redis:false`. | [live] |
| The game's Supabase project | Host does not resolve (NXDOMAIN). Realtime multiplayer and voice are dead. | [live] |
| Players | ~**55** YUE players (`data/players.json`, block 28,122,418); 28 "onboarded roster" players in Oct. | [src] |
| Identities | **21,255** LAUs, only ~1,650 distinct usernames (KEK ×9,424, "." ×4,720 …). | [src] |
| Chat volume | **8,201** Void messages; **22,764** room messages across 934 rooms (Shell City alone: 16,905). | [src] |
| Block time | ≈ 10.3 s | [src] |

**What this means for the game:** the territory-conquest layer is still latent. The off-chain
features the game was built around are all dead. The live game today is identity → reacting at
territories (bars) → rooms and chat, plus readiness for WORLD.

---

## 1. The real loop

```
Wallet ─▶ LAUFactory.New(name,symbol) ─▶ LAU.Username(≤12 chars) ─▶ CHO.Enter(LAU)        identity
       ─▶ SEI.Start(LAU,name,symbol) ─▶ CHOA.Play(LAU)                                    your YUE scoreboard
       ─▶ CHEON.Su(qing)  or  CHOA.Chat(qing,msg)                                         FUEL: bars grow
       ─▶ (four holdings in place) META.Beat(waat)                                       heartbeat, readiness
       ─▶ WORLD.Code(lat,lon,qing)   [NOT DEPLOYED]                                       code a map cell
       ─▶ WAR.Faa(qing,pos) → H2O + CO2; WORLD.Distribute → payouts; GWAT spawns          [NOT DEPLOYED]
```

- **Su = the primary live move** [live]. `CHEON.Su(qing)` adds `Omega_Q` to your `Hypobar[qing]` and
  `Omicron_p` to your `Epibar[qing]`. It returns `(Charge, Hypobar, Epibar)` and mints **+1 YUE** to
  your wallet. It does **not** need Join. CHEON hit its cap (91,700), so Su pays **0 CHEON**.
- **CHOA.Chat(qing, msg)** is the same reaction plus a room message. It **needs admission**, and it
  mints 1 of the room's own token *into the room*, not to you.
- **Players cannot call `YUE.React`**: it is owner-only (SEI and CHAN). Old docs that say "call
  YUE.React" are wrong.
- **AFFECTION "terraform" ops** (`Alpha/Beta/Pi/Rho/Generate/Upsilon`) are real and permissionless.
  They mint AFFECTION **into the AFFECTION contract's own reserve** and touch only AFFECTION and MATH.
  They **do not** change bars, Charge, range, or any territory [live]. This is the single biggest
  correction to the Feb 2026 spec, which assumed "AFFECTION = terraforming the territory".
- **Bars only grow.** No burn exists anywhere in Dysnomia [src]. No leaderboard or win condition
  consumes the bars yet, beyond (future) WORLD staking.

---

## 2. Addresses (chain 369). Each one was checked for contract code on 2026-11-22 [live]

| Contract | Address | Notes |
|---|---|---|
| VOID | `0x965B0d74591bF30327075A247C47dBf487dCff08` | |
| SIU | `0x43136735603D4060f226C279613A4dD97146937c` | |
| **LAUFactory** | `0xbA6CcD38992839aEE20D5bF9125b1d94190b091C` | The 21,255-LAU registry was crawled from it. ⚠ `0x8013Dd64…576B`, cited in old docs, has **no code**. |
| CHO (also the **Tethys** token) | `0xB6be11F0A788014C1F68C92F8D6CcC1AbF78F2aB` | `ZI.Tethys()` returns CHO |
| MAP | `0xD3a7A95012Edd46Ea115c693B74c5e524b3DdA75` | emits `NewQing` |
| HECKE | `0x29A924D9B0233026B9844f2aFeB202F1791D7593` | coordinates |
| CHAN | `0xe250bf9729076B14A8399794B61C72d0F4AeFcd8` | wallet → YUE |
| CHOA | `0x0f5a352fd4cA4850c2099C15B3600ff085B66197` | Play, Chat, Yuan |
| SEI | `0x3dC54d46e030C42979f33C9992348a990acb6067` | Start |
| CHEON | `0x3d23084cA3F40465553797b5138CFC456E61FB5D` | Su |
| META | `0xE77Bdae31b2219e032178d88504Cc0170a5b9B97` | Beat |
| RING | `0x1574c84Ec7fA78fC6C749e1d242dbde163675e72` | Eta, Phobos() |
| PANG | `0xEe25Ccd41671F3B67d660cf6532085586aec8457` | |
| ZI | `0xCbAdd3C3957Bd9D6C036863CB053FEccf3D53338` | |
| XIE | `0x4Df51741F2926525A21bF63E4769bA70633D2792` | Fornax() |
| XIA | `0x7f4a4DD4a6f233d2D82BE38b2F9fc0Fef46f25FA` | Charge, Fomalhaute() |
| MAI | `0xc48B0a4E79eF302c8Eb5be71F562d08fB8E6A3d8` | |
| QI | `0x4d9Ce396BE95dbc5F71808c38107eB7422FD9a03` | Eris() |
| AFFECTION | `0x24F0154C1dCe548AdF15da2098Fdd8B8A3B8151D` | supply ≈ 438M of a 1,111,111,111 cap (Oct 2026 reading) |
| **Fornax** (SHIO) | `0xF6C50fFE7efbDeE63A92E52A4D5E9afF7fb4A4D7` | one of the four holdings |
| **Fomalhaute** (SHIO) | `0x7aE73C498A308247BE73688c09c96B3fd06dDB84` | one of the four holdings; **also the Void chat log** (the game calls it `LOG_STORAGE`) |
| Eris | `0xE843765114992e18061498aeD708537cE9d924FA` | matters when held **by a territory** (sets Charge base) |
| **Phobos QING = "Zürich QING" (qZů)** | `0xb0Ba7D36B7F0505879179ecE7401F24eB653c6E1` | the Phobos holding is **this QING's own token**. Waat `0x0116ffdf05f579f35879129076ff12f3c18bc4a0b85bda626f6bf7f2fcb7fafc` |
| Zürich *asset* token | `0x583d1C1427308f7f96BFd3E0d7A3F9674D8BF8ec` | ⚠ The game's `ZUO_ADDRESS` points here, but this is **not** the Phobos holding and **not** a ZUO contract. |
| CROWS | `0x203e366A1821570b2f84Ff5ae8B3BdeB48Dc4fa1` | ≥ 25e18 → universal bouncer |
| WITHOUT | `0x173216Ed67eBF3E6767D86e8b3Ff32e0d64437bF` | any balance → banned (59 wallets) |
| NoNukes token / NoNukes QING | `0x174A0ad99c60c20D9B3D94c3095BC1fb9ddEFd62` / `0x4dd0371c02631bfd17ad10ab7c0e35a047ff2d20` | |
| MATH ("Xiao", atropaMath) | `0xB680F0cc810317933F234f67EB6A9E923407f05D` | shared RNG/math library |
| **Multicall3** | `0xca11bde05977b3631167028862be2a173976ca11` | use `aggregate3` for batched reads |
| WPLS | `0xa1077a294dde1b09bb078844df40758a5d0f9a27` | |
| Dysnomia deployer (EOA) | `0x0474606332105A1dA6FC8EF7De2470551D389Cb9` | its nonce moving past 712 is the WORLD launch signal. Its CREATE addresses are precomputed in `assets/data/deployer_creates.json` (nonce 132 → MAP checks out); the game's World watch reads code there |
| WORLD / WAR / GWAT / VITUS / H2O | **none** | Never ship a guessed address. Clients have already sent `Code()` to WITHOUT by mistake, and a "GWAT address" with no code was once published. |

Per-territory addresses (942 QINGs), LAUs and YUEs are discovered at runtime (§8).

---

## 3. Selectors, events, errors. Every selector below was recomputed [calc]

### Writes
| Call | Selector | Notes |
|---|---|---|
| `LAUFactory.New(string name, string symbol)` | `0x8c6dc5ec` | deploys your LAU |
| `LAU.Username(string)` | `0xc6bf2b65` | owner only, ≤ 12 chars |
| `CHO.Enter(address LAU)` | `0x37a2e752` | registers your Soul. Blocked for WITHOUT holders. |
| `SEI.Start(address LAU, string, string)` | `0x78519019` | deploys your YUE. Argument order is (address, name, symbol). |
| `CHOA.Play(address LAU)` | `0x74ff4718` | activates you; mints 1 YUE, which fixes `ZeroHoldings` |
| **`CHEON.Su(address qing)`** | `0x753a0c09` | → (Charge, Hypobar, Epibar) |
| `CHOA.Chat(address qing, string)` | `0xb340a780` | react + room message; needs admission. `QING.Chat(address LAU, string)` has the **same selector** (only the first argument differs). |
| `QING.Join(address LAU)` | `0x0764c80c` | needs an asset allowance **strictly greater** than the cover. Gives a 1-day admission keyed to the LAU. |
| `LAU.Chat(string)` | `0x21516fc4` | posts to the **Void** (global) log |
| `META.Beat(uint256 waat)` | `0xd5215e06` | takes a **Waat**, not an address → (Dione, Charge, Deimos, Yeo) |
| ERC-20 `approve(address,uint256)` / `transfer(address,uint256)` | `0x095ea7b3` / `0xa9059cbb` | moving holdings onto your LAU; Join allowance |
| AFFECTION `Alpha(uint64)` `Beta(uint64)` `Pi()` `Rho()` `Generate()` `Upsilon(uint64,bool)` | `0xe95b237f` `0x7ab0960d` `0x5c13dbf0` `0xa4566950` `0xd805b650` `0xdf4c7406` | reserve mints only (§1) |
| `LAU.Leave()` / `LAU.Void(bool,bool)` | `0xac8f5ead` / `0x414c3935` | Leave only writes a log line. **Void(true,true) is not a reset**: a live simulation kept the same Soul. |
| *(latent)* `WORLD.Code(int256,int256,address)` | `0x99790fb6` | not deployed |
| *(latent)* `WAR.Faa(address,uint256)` | `0xe24893a2` | not deployed |

### Reads (use `eth_call`)
| Call | Selector | Notes |
|---|---|---|
| `CHO.GetUserTokenAddress(address wallet)` → LAU | `0xe80c28bf` | |
| `CHAN.Yan(address wallet)` → YUE | `0x18025d89` | |
| `LAU.Username()` | `0xc584460d` | |
| `LAU.Saat(uint256 i)` | `0x088aee78` | **0 = Pole** (66,987,264,069,958 for *every* LAU), **1 = Soul**, **2 = Aura** = `uint160(wallet) % 953467954114363` |
| `YUE.Bar(address qing)` → (Hypobar, Epibar) | `0xc253aded` | raw integers |
| `QING.Waat()` / `Entropy()` / `Asset()` / `GWAT()` | `0xa138da0b` / `0x40c48dfa` / `0xdf42e80e` / `0x8dd6363c` | Entropy is fixed at creation |
| `QING.CoverCharge()` / `BouncerDivisor()` / `Admitted(address LAU)` | `0xfbe5a232` / `0x0aae7978` / `0xdfffcc74` | `Admitted` is always true when the cover is 0 |
| `HECKE.Compliment(uint256 waat)` → (int256 **lon**, int256 **lat**) | `0x3353268d` | ~240-bit integers (§6) |
| `MAP.GetMapQing(int256 lat, int256 lon)` | `0xb93ae85f` | ⚠ pass Compliment's words **swapped**: (word1, word0) |
| `MAP.GetQing(uint256)` / `MAP.Offset()` | `0x20bc1aa2` / `0x5261d74a` | Offset = 476,733,977,057,179 |
| `CHOA.Yuan(address token)` | `0xd6047e37` | needs `from` = wallet |
| `RING.Eta()` | `0x4209b07c` | needs `from` = wallet; used to diagnose readiness |
| ERC-20 `balanceOf` / `totalSupply` / `decimals` / `name` / `symbol` / `allowance` | `0x70a08231` / `0x18160ddd` / `0x313ce567` / `0x06fdde03` / `0x95d89b41` / `0xdd62ed3e` | `maxSupply()` `0xd5abeb01` is in **whole tokens** |
| Multicall3 `aggregate3((address,bool,bytes)[])` | `0x82ad56cb` | |

**`tx.origin` reads.** These must be `eth_call` with **`from` = the player's wallet**, or they revert
(e.g. `UserNotEntered`): CHOA.Yuan, CHO.GetUser/GetUserSoul, SEI.Chi, XIE.Power, XIA.Charge, ZI.Spin,
PANG.Push, RING.Eta, META.Beat, CHEON.Su. The game's `XIE.Power` read omits `from`; that is why it
reverted 12 out of 12 times.

### Events
| Event | topic0 | Emitter | Decode |
|---|---|---|---|
| **Room chat** `LogEvent(string Username, uint64 Soul, uint64 Aura, string LogLine)` | `0xb916a3aaef1d0f80cd78f5fca0067f557f3db4a63748929d2e5e8d0014549374` | each QING | Nothing is indexed; data words are [offset of Username, Soul, Aura, offset of LogLine]. **Accept only known QING emitters**, because anyone can emit a copy of this event. |
| **Void chat** `LogEvent(uint64 Soul, uint64 Aura, string)` | `0x6b81130c485ac9b98332fa40c2e57900867815b0fe1497e1a168caf930fc9c9d` | Fomalhaute `0x7aE7…DB84`, from block 21,000,000 | text is `"<Username> line"`, parse with `^<([^>]+)>\s*([\s\S]*)$` |
| **`NewQing(address QING, address Integrative, uint256 Waat)`** | `0x692bc76be0a4b0d71d90e36ee97b1f3c4141095ea3c22b01b9f620da2e4b5e2e` | MAP | all fields are in data. **One `eth_getLogs` from block 0 returns every territory (~4 s).** |
| ERC-20 `Transfer` | `0xddf252ad…` | | each Su emits a CHEON→YUE transfer of 0, then mints 1 YUE from 0x0 **to the YUE contract**, which transfers it **YUE → wallet** (verified 2026-11-23 on a live YUE: 317 mint/transfer pairs). Count reactions with Transfer(from = YUE, to = wallet) on the YUE. This is how players are discovered. |
| *(WORLD)* | — | | **WORLD will emit no claim events**, so claims must be indexed from `Code` calldata. |

### Errors (decode reverts with these) [calc]
`Panic(uint256)` `0x4e487b71` (0x12 = division by zero → **missing one of the four holdings**; 0x01 =
assert → e.g. a WITHOUT holder on Join/Enter) · `NotStarted(address)` `0x12efd467` (no YUE) ·
`ZeroHoldings(address)` `0x98aaa293` (the wallet holds 0 of its own YUE; `CHOA.Play` fixes it) ·
`OutOfRange(int256,int256,uint256)` `0x0efe67cb` · `UserNotEntered(address)` `0x647f6a38` ·
`SoulNotEntered(uint64)` `0xbba4853d` · `NotAdmitted(uint64)` `0xd466620a` · `Forbidden(address)`
`0xa59d7f4d` · `CoverChargeUnauthorized(address,uint256)` `0x694ecc8a` · `PayCover(address,uint256)`
`0xac73eb51` · `OwnableUnauthorizedAccount(address,address,address)` `0x0be6bab5` ·
`DysnomiaInsufficientBalance(address,address,address,address,address,uint256,uint256)` `0x3df42ef4` ·
`DysnomiaInsufficientAllowance(…same shape…)` `0x02e0f464`.

---

## 4. Formulas (what a Su, a Beat and a Code actually do)

Notation: `Bal_X(h)` is holder h's balance of token X in wei. `LAU` = CHO.GetUserTokenAddress(wallet),
`YUE` = CHAN.Yan(wallet). `E_Q` = QING.Entropy() (fixed). `E_p` = the player's entropy in CHO,
which is **rewritten on every CHO lookup**, so it moves within a single transaction.
**Yuan(X) = Bal_X(wallet) + 10·Bal_X(LAU) + 40·Bal_X(YUE)** [live].

- **Bar gain per Su or CHOA.Chat at Q** [live]:
  - `Omega_Q = ⌊Bal_Fornax(Q) / E_Q⌋` is added to **Hypobar[Q]**. It is the **same for every player**:
    anyone who sends Fornax *to the QING* raises it for everyone. That donation is owner-withdrawable;
    see GWAT below.
  - `Omicron_p = ⌊Bal_Fornax(LAU) / E_p⌋` is added to **Epibar[Q]**. It is personal and varies with
    the player's entropy.
- **Charge(Q)** = `modExp(QI(Q), MAI(Q), Bal_Fomalhaute(LAU))`, where `QI(Q) = ⌊Bal_Eris(Q)/E_Q⌋` and
  `MAI(Q) = ⌊Bal_Q(LAU)/E_p⌋` (Q's own token held on your LAU).
  - No Fomalhaute on the LAU → Charge 0.
  - None of Q's token on the LAU → Charge 1.
  - Q's token on the LAU but no Eris at Q → Charge 0.
  - Otherwise Charge is a pseudo-random value **below Bal_Fomalhaute(LAU)**.
- **META.Beat(W_T)** → (Dione, Charge, Deimos, Yeo):
  - **Dione** = Tethys held by T ÷ E_T. This is the VITUS paid per future capture, the same for everyone; ≈14 at Phobos.
  - **Deimos** = creator credit.
  - **Yeo** = range. `Yeo < Yuan(T)/Chao`, so **range comes from holding T's own token, best on the
    YUE (×40)**. Holding the Phobos token *on the LAU* shrinks range everywhere. Yeo = 0 means you can
    code the centre cell only. Observed: 0, 74, 423, 4.6e14, 4.7e17, 4.1e22. More Fornax does **not**
    mean more range.
- **The four holdings** [live]. Missing any one makes Beat, and therefore a future `WORLD.Code`, panic
  with `0x12`:
  1. **Fomalhaute on the LAU**: otherwise Chao = 0. On the wallet or YUE doesn't count.
  2. **Fornax on the LAU**, more than dust: otherwise Iota = 0.
  3. **Some Tethys**, anywhere.
  4. **Some qZů (Phobos QING token)**, anywhere.

  Safe thresholds used by the site: ≥ 0.001 of each, plus 1 wei. Fornax below 0.000375 fails in many
  blocks; Yuan(qZů) below 1001 wei never passes; a perfectly *round* qZů amount can fail.
- **Before the holdings, two gates**: `NotStarted` (no YUE) and `ZeroHoldings` (you hold 0 of your own YUE).
- **WORLD.Code(lat, lon, Cause)** *(latent)* [kb + review], step by step:
  1. Cause must be a real QING.
  2. Su(Cause) runs (+1 YUE, your bars grow).
  3. Beat runs (bars at Phobos grow).
  4. Range check: `|lat−qlat| ≤ Yeo` **and** `|lon−qlon| ≤ Yeo` (a square), otherwise `OutOfRange`.
  5. If Su's Charge == 0, the call **returns silently**: gas spent, nothing coded.
  6. **King of the hill:** if `Charge ≥ _world[lat][lon][Cause]`, the cell's value grows by **your
     total Hypobar at Cause**, **Dione** VITUS is minted to your YUE, and your creator credit grows by
     Deimos. Cell values only grow, so an empty cell falls to Charge 1 (first coder locks it cheaply).
- **WAR.Faa / GWAT** *(latent)*:
  - Faa needs an existing creator at the position, mints H2O to the YUE and accrues CO2; its output seeds GWAT spawns.
  - A spawned GWAT QING is named `"<user>'s <asset> GWAT"`, symbol 骨 (bone), and is **drain-locked forever**.
  - GWAT flag = `Waat % Offset ≠ 0`, so **every MAP-created QING today reads GWAT = false**: its
    owners can withdraw anything sent to it, including Fornax "pumps".

---

## 5. Rooms, identity and access rules [src/live]

- **Every QING is a venue / chat room** with its own ERC-20 token and asset. Anyone may *visit* (read)
  any territory; there is no gate on looking.
- **Cover charge** is priced in the room's asset token. Join needs `allowance > cover` and gives a
  **1-day** admission keyed to the **LAU**. Only **14 rooms** charge a cover (the AFFECTION room: 414 Ⓐ).
  For every other room `Admitted()` is already true.
- **Bouncers**: holding ≥ 25 CROWS (unless the room set NoCROWS), staff, the creator, ≥ supply/BouncerDivisor
  of the asset (default 32), or owning a Dysnomia asset. Bouncers can **only change settings** (cover,
  guest list, staff, divisor). **Join does not check bouncers.**
- **WITHOUT** is soulbound; any balance is a ban. It blocks `QING.Chat`, `CHO.Enter`, Join, the first
  `SEI.Start` and `Play` (Panic 0x01). It does **not** block `MAP.New` or `CHEON.Su`.
- **Names are not unique.** Authenticate by the sending LAU, never by display name. OG/imposter rules
  (`lib/name-registry.js`):
  - the sole holder of a name is its OG;
  - otherwise the first-created LAU is OG, and later LAUs from the same creator (same Aura) count as OG too;
  - names held by LAUs from ≥ 4 creators are generic (no badge);
  - compare names after NFKC normalization plus lookalike folding.
- **Identity** is the triple (Pole, Soul, Aura), read via `Saat(0/1/2)`. Pole is the same for every
  LAU, so **never derive visuals from Saat(0)** (the game's avatar height did).
- **The connected wallet is the identity root**: wallet → LAU → YUE. The game's second "lau_wallet",
  derived via `CHO.GetAddressBySoul(Saat1)`, must go.

---

## 6. Coordinates (never use floats for raw values)

- `Waat = CHO.Luo() × Offset`, ≈ 2.4–5.5e74.
- `Meridians(88) ≈ 3.94e74`; `Meridians(89) = 2·M88 + 1 ≈ 7.88e74`. `Compliment` panics above M89.
- **`HECKE.Compliment(W)` → (int256 lon, int256 lat)** [kb steps, live outputs]:
  ```
  assert W <= M[89]; m = first i with M[i] >= W; south = true
  if m == 89: south = false; W = M[89]-W; m = GetMeridian(W)
  lat = (W == M[88]) ? 0 : M[88]-W
  start = m>0 ? M[m-1] : 0; w = W-start; end = M[m]-start
  lon = (w < end/2) ? w : -(w - end/2)
  lat = lat/333; if south: lat = -lat
  ```
  |lat| ≤ ~1.18e72; |lon| up to ~3e72. These are ~240-bit integers: keep them as hex strings or
  big-int byte arrays. Encode int256 arguments as two's complement; decode a word as signed when ≥ 2^255.
- **Display projection** used by the whole site (`scripts/build-qing-registry.js:64-78`,
  `lib/chain-live.js:61`). Read both words **unsigned**, then:
  `lon° = (w0 mod 360,000,000)/1e6 − 180`, `lat° = (w1 mod 180,000,000)/1e6 − 90`.
  Compute the mod digit by digit over the hex string: `r = (r·16 + d) % m`, which fits in int64.
  All 940 registry entries use this.
- **Map adjacency is meaningless on-chain.** The projection is a modular hash. "Neighbouring
  territories" on the degree map share nothing. A WORLD range of ±Yeo **raw units** is microscopic at
  degree scale, so draw WORLD as a **local lattice around each territory's centre**, scaled to
  max(Yeo, largest claimed offset), as `world.html:421-437` does.
- **Borders use the raw plane, not the degree map** (2026-11-24). The raw words are a geometric
  function of the Waat (Compliment above has no hash), they key MAP's cells, and WORLD measures range
  in them. 942 territories fill ≈ ±1.18e72 (lat) × ±3.6e72 (lon); the median nearest-neighbour gap is
  ≈ 6.6e70 raw units, so ±1 cells are always empty and "adjacent cell" means nothing. The game's
  neighbour on each side (`scripts/world/border/neighbours.gd`) is the **nearest QING in that side's
  quarter** (N: Δlat > 0, |Δlat| ≥ |Δlon|; E: Δlon > 0, |Δlon| > |Δlat|; …) by WORLD's square
  distance, BigInt only. A quarter with no QING is the edge of the map. **[live]** RatKing's and
  Illinois's four neighbours each read back from `GetMapQing(lat_word, lon_word)` at block 28,135,981.
- **Argument order:**
  - `GetMapQing(lat, lon)` takes (word1, word0). **[live]** confirmed 2026-11-24 (above).
  - The site passes `Code(word0, word1, Q)` for the centre cell, flagged "confirm on first real Code".
    When WORLD deploys, simulate both orders once and keep the one that passes the range check.
- The game currently has **three disagreeing coordinate transforms**: HUD (low 64 bits, sign lost),
  world map, and neighbour scan. Replace all three with the one above.

---

## 7. WORLD-readiness model (port from `owner/power/world-ready.js` + `world-ready-ui.js`; public: `world.html`)

**Read sequence.** All reads are pinned to one block hash (EIP-1898 `blockHash` param); the RPC's
nodes can run a block or two apart.
1. CHO.GetUserTokenAddress(wallet), CHAN.Yan(wallet), eth_getCode.
2. Holdings: Fomalhaute, Fornax, Tethys and qZů `balanceOf` on wallet, LAU and YUE; CHOA.Yuan(qZů)
   and Yuan(Tethys) with from = wallet; LAU.Username; PLS balance; gas price.
3. **Code-order probe:** `Multicall3.aggregate3([CHEON.Su(Phobos), META.Beat(PHOBOS_WAAT)])` with
   from = wallet. This puts the player in `tx.origin` and a contract in `msg.sender`, as under WORLD.
4. A standalone Beat (to detect "fragile"), then `RING.Eta` to diagnose a failure: Chao = 0 means no
   Fomalhaute on the LAU; Iota = 0 means a missing, too-small or round Fornax/Tethys/qZů.
5. *(Optional)* Stability replay: re-run the probe at 20 earlier blocks with today's balances
   overridden. Balances sit at mapping slot 1: `key = keccak(abi.encode(holder, 1))`.
6. Range scan per territory: probe Beat for the 40 largest Yuan holdings of territory tokens.

**States, in order:**

| State | Condition | Show |
|---|---|---|
| `no-account` | no LAU in CHO | "Enter the Void" onboarding |
| `not-started` | LAU but no YUE (`NotStarted`) | call SEI.Start |
| `blocked` | `ZeroHoldings` 0x98aaa293 | call CHOA.Play (mints 1 YUE) |
| `not-ready` | Panic 0x12 | per-holding verdicts: ok / thin / low / **wrong place** (Fomalhaute or Fornax not on the LAU) / **round** / missing; qZů on the LAU above 3e13 wei → "shrinks range" |
| `fragile` | passes in Code order but standalone Beat fails, or some replayed blocks fail | "ready, fragile" |
| `ready` | probe passes | Dione (VITUS per Code), Yeo (0 = "centre cell only"), Su Charge (0 = "Code would do nothing"), Deimos |

Fix moves, each simulated first: ERC-20 transfers onto the LAU, `LAU.Withdraw` to pull qZů off it,
and 1-wei nudges to break a round number. Gas for Su + Beat ≈ 2.8M.

---

## 8. Data you can use

| Source | What | Notes |
|---|---|---|
| **Chain, `NewQing` logs** | every territory: address, Integrative (**= the asset token**, equals `QING.Asset()`; verified on the two newest), Waat, block | one call from block 0. Then per QING (Multicall3): Entropy, Asset, name, symbol, CoverCharge, BouncerDivisor, GWAT, Compliment |
| `https://systm0.vercel.app/data/qing-registry.json` | 940 territories (2026-11-17), fields: address, lau (**actually the asset token**), waat (decimal string), block, txHash, name, symbol, entropy, gwat, coverCharge, bouncerDivisor, totalSupply, creator, lat, lon, coordSource | good **seed snapshot**; catch up from its last block with NewQing logs |
| `…/data/players.json` | 55 `{yue, wallet, last}` (block 28,122,418) | seed list of real players |
| `…/data/room-snapshot.json` | per-room counts, people, top speakers, latest 300 lines | seed for rooms |
| `…/data/lau-names.json`, `name-claims.json` | named identities; OG claims | |
| `GET /api/qing-chat?qing=&limit≤200&after=&before=` | room messages (`ts` in unix **seconds**) | live chain behind a 10 s CDN cache |
| `GET /api/void-messages?limit≤500&before=&after=` (blocks) | Void messages | |
| `GET /api/d-entity?address=` | qing → bar totals + top 50 holders; wallet → LAU, YUE, Saat, bars per territory | 60 s |
| `GET /api/d-leaders?type=hypobar\|epibar&limit≤100` | global ladder | computed from every YUE × every QING, 5-min memo |
| `GET /api/d-stats[?qings]` | totals / per-territory bar totals | |
| `GET /api/world-watch` | `{status, deployed{WORLD,…}, deployer{nonce, nextCreateAddress}}` | **the launch signal** |
| `GET /api/world-claims[?qing=\|?wallet=]` | `world-not-deployed` until launch, then cells + leaderboard | |
| ⛔ `/api/player`, `/api/achievements`, `/api/leaderboard`, `/api/activity`, `/api/online-players`, `/api/presence`, `/api/flags`, `/api/alliance`, `/api/daily`, `/api/challenges` | Redis-backed, and **prod has no Redis** | they return empty data or drop writes. Five of them never matched the game's payloads anyway. **Do not use.** |
| ⛔ `/api/qing/{addr}` | memberCount is just token supply; powerScore is invented | not game truth |

Rules for the site API:
- CORS allows only the site's own origins, so a native build is fine and a web export is blocked.
- Treat the API as an **optional accelerator**: the game must work chain-direct, and the base URL must be configurable.

---

## 9. RPC rules (learned the hard way)

- **Node:** `https://rpc.pulsechain.com` (chain 369). It supports archive state, `eth_simulateV1` and
  `trace_*`. Third-party nodes were dropped.
- **Never send JSON-RPC batches**: the node runs them one call at a time (40 calls ≈ 43 s, versus
  ≈ 1.3 s as 8 parallel single requests). Use **Multicall3 `aggregate3`** (≈300 calls per chunk, ≤ 6
  chunks in flight) or ≤ 8 parallel single calls.
- **`eth_getLogs`:** 500k-block windows, ≤ 6 in flight, halve on range/size errors down to a 2k
  floor, and remember the smallest refused size.
- **Retries:** 4 tries, backoff `300·2^i` ms, 25 s timeout. A non-JSON (HTML) response is a failure.
- **Never cache an outage.** Do cache immutable data: bytecode, a QING's Waat/Entropy, past logs.
- **Pin multi-read snapshots to one block hash.**
- **Catch-up pattern that worked:**
  - ship a snapshot, then read only the newer tail live;
  - merge live data over the snapshot so the result is never worse than the snapshot;
  - make backfills idempotent by keying on (tx hash, log index).
- **Before signing:**
  - ensure chain 369: switch, or add the chain on error 4902;
  - handle 4001 (user rejected);
  - never report 369 when the switch failed (the game's wallet page does).
- **The wallet window** (2026-11-24, `tools/e2e_wallet.sh`): raise it *before* the page calls the wallet
  (the page waits ≤ 4 s for focus), never while the wallet's popup is open (a raise covers the popup).
  One linked window at a time; an old window (earlier token) reloads itself. A dropped link keeps the
  address; the page queues answers until it relinks. `chain_changed` must reach `Wallet.chain_id`, and a
  payment asks the wallet to switch. Brave Wallet can own `window.ethereum` while the player's wallet is an
  EIP-6963 extension. Send `eth_sendTransaction` as `{from, to, data, chainId:"0x171"[, value]}` with
  canonical hex quantities; let the wallet estimate gas. (Testing note: a Playwright `route.fulfill` page
  counts as public, so Chrome's Local Network Access blocks its socket to 127.0.0.1; real pages are fine.)

---

## 10. The truth contract (rules every game screen follows)

Distilled from the site's audit rounds. Each was a real bug there, so each is a rule here.

1. **Never fabricate on failure.** No demo, seed or "preview" values for anything chain-shaped:
   addresses, names, entropy, coordinates, balances, prices, counts, events. A "Preview" label is not
   disclosure. (The game's F9 debug presets must never ship in a release build.)
2. **Loading ≠ empty ≠ unavailable ≠ zero.** A failed read shows "—", never 0. A contract that didn't
   answer is named and left out of totals.
3. **Fallback values never overwrite real ones** (e.g. `.catch(()=>0)` printed "Cover Charge 0" over
   real values). Track whether the chain actually answered.
4. **A capped read is a floor**: show "N+" and say so. Totals come from the same filter as the rows.
5. **Rankings only from complete passes**; while a pass is running, show progress.
6. **Every number says where it came from**: source call, block, and freshness ("QING.Entropy() · block 28,124,253").
7. **Don't assert what you never read.** Check a contract with `eth_getCode`. Unknown ≠ not deployed.
   Never ship guessed addresses.
8. **Controls report only outcomes they actually achieved.** Simulate before signing. After sending,
   **verify the receipt from the chain yourself**; don't trust a message from the wallet page.
   A control that can't work is disabled with its requirement stated.
9. **Key everything by lower-cased address**, never by name or symbol.
10. **Reads need no wallet.** Anyone can look at anything.
11. **Every image is a real number** (§11): the same value always draws the same picture, and the game
    can say which number it drew and how.
12. **Unbuilt is shown as absent.** WORLD/WAR are shown honestly as "not deployed (deployer nonce 712,
    checked block N)", never faked.

---

## 11. Visual direction: **Deep Field** (owner sign-off 2026-11-19; now site-wide)

- **Brief:** "epic, hypnotic, mathematical, mysterious, and true to the code, while staying plain for newcomers."
- **Rule:** every image is a real number. "A world that computes itself. The numbers are the chain's;
  the drawing is ours."
- **Rejected** (don't drift back):
  - cosmic/nebula (approved in July, dropped in November);
  - amber observatory;
  - "too calm" field-guide/instrument/atlas looks;
  - D neon-psychedelic: "right path, too cheesy";
  - literal gold-leaf/scripture: "epic" meant *scale*;
  - invented decoration: "None of it corresponded to anything."
- **Palette** (`lib/styles/deep-field.css:17-21`):

  | Role | Value |
  |---|---|
  | black | `#030407` |
  | ink | `#e9edf4` |
  | muted | `#8e97a9` |
  | dim | `#5d6578` |
  | hairlines | `rgba(190,210,255,.13 / .22)` |
  | glass panel | `rgba(6,8,14,.74–.78)` |
  | single ice accent | `#a8e6ff` |
  | per-subject hue | default `#7fd3ff` |

- **Type:** Archivo (wide, 800, uppercase) for display, Inter for body, **JetBrains Mono for every chain value**.
- **Motifs:**
  - luminous Julia-set filaments on black, and an endless self-similar dive;
  - the Motzkin prime set monumental;
  - Rod and Cone drawn as **c and its mirror c̄**;
  - the real Solidity line as an epigraph, then plain words;
  - dark glass panels;
  - a HUD that names the number on screen;
  - "How is this drawn?"
- **Rarity tiers** (from entropy, `lib/deep-field.js`), roughly 2 / 6 / 17 / 30 / 45 %:
  - **Mythic** ≥ 416,911,265,256,012
  - **Legendary** ≥ 394,373,502,855,546
  - **Epic** ≥ 321,073,793,475,702
  - **Rare** ≥ 206,402,677,688,564
  - **Common**, else

  Colours conflict across files. Pick `lib/rarity.js`: Common `#9aa6c8`, Rare `#8fd0ff`, Epic
  `#b07bff`, Legendary `#ff8fd0`, Mythic `#ffd59a`. Deep Field also renders Legendary as *gilded* and
  Mythic as *prism*.
- **Territory → fractal** (`lib/deep-field.js:86-132`). This is a summary: **port from the source and
  verify against golden vectors**.
  - `n` = entropy (or the Aura for an identity), `a` = address, `P` = 953,467,954,114,363.
  - `mix(b,s)` = FNV-1a-32 over hex(b), seeded `2166136261^s`, prime 16777619, then murmur fmix.
    `unit = mix/2^32`.
  - `u = ((n·369) mod P)/P`, `pick = mix(a,1) % 10`, `depth = unit(n^a, 2)`.
  - c by pick:
    - pick < 6, **spiral near a p/q bulb**: `q = 2 + mix(n,5)%8`, p coprime to q, `θ = 2π(p/q + (u−.5)·.8/q²)`,
      `c = (1 − (.008+.11·depth²)/q)·(½cosθ − ¼cos2θ, ½sinθ − ¼sin2θ)`;
    - pick 6–7: c inside the period-2 bulb;
    - pick 8–9: c inside a period-3 bulb.
  - rotation = 2π·unit(a,3); hue = unit(n^(a>>7),4); style = [glow, duo, bands, ember][mix(a,12)%4].
  - Rarity raises the power D (z² → z³…z⁶ "star" sets for Epic/Legendary/Mythic).
  - colour = `.55 + .45·cos(2π(hue + {0,.33,.67}))`.
  - Uniqueness was tested over all territory pairs, but at 374 territories. **Re-run it at 942.**
- **Rendering** (`deep-field.js:184-231`):
  - iterate `z ← z^D + c`, `dz ← D·z^{D−1}·dz`, orbit trap `min|z|²`; bail out at `|z|² > 1e4`, ≤ 160 iterations.
  - inside the set: dark, tinted by the trap;
  - outside: distance estimate `de = .5|z|ln|z|/|dz|` gives a bright filament core `e^{−de/1.6px}` and a
    halo `e^{−de/22px}`, plus style bands from the smooth iteration `ν`.
  - The GLSL ports almost one-to-one to Godot shaders.
- **Relief** (the ground, `JuliaHeightfield` v2, 2026-11-24). Every landform is a function of the
  territory's Deep Field numbers (`relief_params`), never of the viewer:
  - inside the set: the plateau (22 m) rises into **terraced mesas** with distance from the coast
    (`1 − e^{−coast/mesa_w}`), plus a **dome over the orbit trap** s; a **summit crater** where s → 0
    (the orbit passes through the critical point). Mix by family: spiral = mesas, period bulbs =
    domes + deep craters, star (D > 2) = sharp peaks. Relief 10–22 m (+5 Legendary/Mythic), terrace
    step 2–3.5 m from (arms + turn) mod 4;
  - outside: the flank falls with the distance estimate in terraces, a crest on the boundary, and
    **canyons along the external rays** at angles j/rays turns. The angle is Böttcher's, branch-tracked
    (`Θ ← D·Θ + arg(1 + c/z^D)`, angle = Θ/D^n); the arg of the last iterate alone draws D^n combs;
  - the Core keeps a flat plain to 120 m (relief full from 190 m), so landmarks, towers and the fair
    have flat land; the outer 40 m of every border eases to 0 m, so neighbours meet level at the wall.
  - Heights 0–55 m, slope p95 30–35° (at 1 m), > 40° on 0.3–1.7 % of the ground. Previews: `preview_terrain.gd`
    writes `relief.png` (height-tinted hillshade, contour every 2 m).
- **Size** (2026-11-24, heightfield v4): the territory is **724 m square** (`JuliaHeightfield.SIZE_M`; was
  512 m: √2 × the edge, twice the area, per the owner). The Julia frame scales with the edge (the same set,
  drawn larger: `world_to_z` divides by the half-edge); every landform width (coast, falloff, crest, terrace,
  canyon, edge blend) stays in metres, so the larger set carries more highland at the same human scale. The
  chain → shape mapping (`DeepField` params, `relief_params`) did not change. Ground 725² (1 m, the
  collider's own spacing), mesh 363² (2 m); neighbours 181² (4 m). The escape pass runs on a few Threads,
  each with its own copy of the params (shared Dictionaries made the threads run in lockstep); ~8 s for a
  first visit on a loaded 4-core box, then the disk cache.
- **Layout** (`TerritoryLayout`): spots tuned on the 512 m map scale by `SCALE` = √2. The Core's cluster
  keeps its size; the fair prefers ≈158 m south and stays ≥ 110 m out, the skyline landmark ≈212 m north
  and ≥ 119 m out, footprints inside `BORDER_KEEP_M` (338 m). **Roads** (`TerritoryRoads`): a ring road
  round the Core (r 60 m), an avenue from the Room's door, and a road to each place's rim and to the middle
  of every border with a QING beyond it, routed by AStarGrid2D over the heights (cost grows with slope;
  later roads reuse earlier ones). The terrain shader draws them from a 512² distance texture (no draw
  calls); lamps are one MultiMesh pair (markers when Wild/Outpost, lit from Settlement). A new building
  adds itself to `territory_v2._road_places()`.
- **Identity art:** Aura = `uint160(addr) % P` drawn the same way. YI icon = a Rod/Cone Lissajous from SHA
  registers (`yi.html:193-374`).
- **Player creature gear from chain facts** (`lib/avatar.js`):
  - grey if no bars;
  - a spark at 3+ territories with bars, an orbit ring at 10+;
  - a halo when you lead a territory, a crown for ladder #1.
- **Sound** (`lib/cinema.js:403-503`):
  - root note from {98, 110, 116.54, 130.81, 146.83} Hz by `hash(number) % 5`;
  - pad on intervals 0/7/12/15, ±7 cents, through a 620 Hz low-pass and a 0.41 s delay;
  - bell chimes (sine f + 2.76f) in minor pentatonic.

---

## 12. Lore → world (curated; sources in `SOUL.md`, `SOUL-ATROPA.md`, `lore.html`, `lib/glossary-data.js`)

**In the project's own words:**
- "exploration is not about combat, it is about *presence*";
- "The game is a *viewport*… Let the math generate the terrain. Let the entropy shape the atmosphere.
  Let the transactions change the landscape";
- "Enter the Void. Get a Soul. Find a territory.";
- "Nothing is wiped clean… Entropy only increases. Your history is your substance";
- show WORLD and WAR as "*honestly absent*".

| Lore | What it is | In the world |
|---|---|---|
| **Eris & Dysnomia** | Eris's moon at the edge of the solar system; "lawlessness" | You stand on the moon; Eris fills the sky; the sun is just another star |
| **The Void** | where identity begins; the global, immutable chat board | The hub: a black chamber where you're born (onboarding) and where the Void's messages scroll on a monolith |
| **Rod & Cone** | paired SHAs that must mirror, or the transaction reverts | Twin pylons at every territory's core, drawn as **c** and **c̄** |
| **Motzkin prime** 953,467,954,114,363 | counts non-crossing chord diagrams; the modulus of identity | A monumental numeral in the Void; chord-circle geometry |
| **Fomalhaute, Fornax, Tethys, Phobos** | named bodies; exactly the **four holdings** | Four bodies in your sky that **light up when you truly hold them** (Fomalhaute and Fornax only when they're on your LAU) |
| **The cascade** QI→MAI→XIA→XIE→ZI→PANG→RING→META | "breath, pulse, gorge, discharge, seed, flank…"; the body map Sky/Tang/Soeng/Dan | The pulse path each Su travels through the core |
| **META.Beat** | "it either beats or it doesn't" | The heart; a heartbeat shockwave on success, a flatline when not ready |
| **GWAT 骨** | bone: drain-locked child territories | Bone pillars around a GWAT core (latent) |
| **CROWS / WITHOUT** | bouncer token / ban token | A crow companion only if you truly hold ≥ 25 CROWS; WITHOUT holders shown as shunned at doors |
| **DysnomiaTime** | 34 h day, 100 min hour, 34 s minute | The day/night clock, derived from **block time** so every player shares it |
| **Clockwork LAU bears** | Court of Nine Emotions; Hogan Bank teddy-bear citizens; `atropa/assets/teddy_bear.obj` | The avatar stays a bear: a clockwork LAU bear (not a film character) |

**Later and optional:**
- Nym: no address known, so it can't be wired yet.
- Folklore `.fkc` cartridges as arcade screens.
- The DEFCON alarm (emerald → ruby).
- The Federal Worker newcomer quest.
- The Vaesen biorhythm (23/28/33-day cycles).

**Caveats:**
- "The Dysnomia Machine" (the Greek video, 2026-11-21) is about the **off-chain TSFi2 Dysnomia VM**,
  not the on-chain game. Treat it as flavour at most.
- The "m‖x = m·x+b" triad identity in the glossary is **arithmetically false**; don't present it.
- The lore's "Limits of the Territory" asks an AI guide to drop possessive/"claim" language. In-game copy
  uses the contract's own verb: **Code** a cell.

---

## 13. Do not repeat (wrong claims that circulated)

1. **"AFFECTION ops terraform the territory."** They mint into AFFECTION's reserve only. "Terraform XP"
   was a site feature.
2. **"Players call YUE.React."** It is owner-only; players use Su or CHOA.Chat.
3. **Other wrong transaction claims:**
   - "Su pays CHEON": it is capped and pays 0.
   - "CHOA.Chat pays a token reward": the only reward is +1 YUE from Su or Play.
   - "Su needs Join": it doesn't.
4. **"More Fornax = more range"**, "Put Eris on your YUE": both false. Range comes from holding the
   territory's token.
5. **The game's `ZUO_ADDRESS` 0x583d…** is the Zürich *asset*. The Phobos holding is **qZů 0xb0Ba…**.
6. **`0x7ae7…` + topic `0x6b81…` is Void chat**, not room chat. Room chat is topic `0xb916…` from each QING.
7. **Wrong game selectors:** Cho `0x9d45c73f` → `0x6872fc3c`; GetQing `0xb6e9bf85` → `0x20bc1aa2`;
   GetMapQing `0x7326117b` → `0xb93ae85f`; CoverCharge `0xe64a6c99` → `0xfbe5a232`.
8. **`META.Beat` and the cascade take a Waat, not an address.**
9. **`LAU.Void(true,true)` is not a reset** (the Soul survived in simulation). `QING.owner()` returns the
   QING itself. `LAU.CurrentArea()` is always 0.
10. **"WITHOUT blocks MAP.New"** and **"Join checks the bouncer"**: both wrong.
11. **Compliment returns (lon, lat)**: don't pass it straight into GetMapQing. Don't use floats for raw
    coordinates. Don't treat the degree map as adjacency.
12. **LAUFactory `0x8013…`** has no code. **Never publish WORLD/WAR/GWAT addresses** before they exist.
13. **`0x98aaa293` is `ZeroHoldings`**, not an "unknown block".
14. **The registry's `lau` field is the asset token**, not a LAU.
15. **`AFFECTION.View()` returns 48 words**: the game's 50-word FAUNG parser always fails.
16. **"374 territories"** is stale: there are 942 and counting. Read the count from the chain.

## 14. Games in the rooms: the arcade, pool, Twenty-One, the fair (2026-11-23)

- **AFFECTION** reads `symbol() = "Ⓐ"`, `name() = "AFFECTION™"`, `decimals() = 18` [live]. A plain
  `transfer(QING, 1e18)` to a QING simulates fine [live, eth_call from the AFFECTION reserve].
- **Arcade fee:** 1 Ⓐ a play, `AFFECTION.transfer(QING, 1e18)` to the QING of the territory the
  cabinet stands in (the owner's choice: the territory's own balance). A credit counts only after
  `ArcadePay.verify_receipt` finds AFFECTION's `Transfer(wallet → QING, ≥ fee)` in the receipt read from
  the chain; the QING's balance is re-read at that block. Credits are a local ledger keyed by tx hash.
  Maria's `.fkc` game carts read no input, so they run free as attract screens and take no credits.
- **Pool and Twenty-One are room lines** (`CHOA.Chat(QING, text)`), replayed by every client:
  `🎱|🃏 challenge anyone|0x<wallet> [stake N Ⓐ]`, then `🎱|🃏 #<id> accept|decline|concede|forfeit|hit|stand`
  and `🎱 #<id> shot <dx> <dy> <power>`. The id is the challenge tx hash's first 8 hex digits.
  - **Who said it is `tx.from`** (eth_getTransactionByHash), never the display name.
  - **Pool is integer physics** (`PoolSim`: µm, 1/480 s ticks, `isqrt`), so every platform replays it identically.
  - **Cards:** each one is `SHA-256("<block hash>:<draw n>") mod cards left`; the block is the one holding the
    accept line (the deal) or the hit line.
  - **Idle games:** after `TableBook.TIMEOUT_BLOCKS` (8,640) without a move, the waiting player may claim the game.
- **Wagers are honour-bound** (no escrow contract exists). The loser owes the stake; `TableBook.settle`
  reads AFFECTION `Transfer(loser → winner)` logs after the game's last block and allocates them
  oldest debt first. ✓ paid / ⚠ unpaid is what everyone sees.
- **Sunny's Pub** replaces the arcade in TehSunFlowrScioety QING `0x2b78b345880807ac9be28c1309ab55d6fa8796de`.
- **Diving into a cabinet** (`scripts/arcade/dive/`, 2026-11-24). Using a cabinet runs `ArcadeDive`: the
  camera pushes into the screen (CRT bulge, scanlines), a light tunnel and a flash, and you land in the
  game's world; Esc reverses it and the arcade shows your score.
  - **The 2D game stays the source of truth.** An `ArcadeWorld` (Void Lanes, Entropy Drift, Bar Raiser)
    only reads its cabinet's `ArcadeGame` state every frame and stages it in 3D (own World3D in a
    SubViewport). Scores, lives, game_over and the unit tests are the 2D game's. A world may remap the
    keys to its camera (`ArcadeGame.input_remap`; scripted test input is never remapped).
  - **Entropy Drift's road is chain data:** `DriftTrack` = SHA-256(`QING.Entropy()` decimal `:` block
    hash). A paid run uses the block holding the credit's transfer (and seeds the field from the same
    bytes); the demo uses the latest block. No hash read → a flat road labelled "—", never a made-up one.
  - Cartridges, and V ("classic") in any game, show the cabinet's own 320×240 screen full-size in a CRT bezel.
  - The flow inside is unchanged: ArcadePay (simulate, sign, verify the receipt, re-read the QING), then
    a credit starts the run. **Scores are local** (`ArcadeScores`, `user://arcade_scores.cfg`, top 10
    per QING and cabinet): a game's score is self-reported, so a room line would prove nothing. Every
    entry carries its credit's tx hash and block, and the board says "on this computer (not on chain)".
- **Sitting at the tables** (`scripts/games/seat/`, 2026-11-24). Using the pool or card table sits you down
  in first person (`TableSeat`: a camera glide in, Esc glides out, the arcade dive's overlay style); `L`
  (`table_lobby`) opens the old TablePanel over the seat for challenge / accept / concede / pay.
  - **Pool** (`PoolSeat`): the eye behind the cue ball, the mouse turns the aim, holding `table_shoot`
    charges a ping-pong meter. `PoolAim` maps the aim angle to `dx, dy` = unit × 10000 and the charge to
    power 50–1000 in steps of 10: exactly the shot line's integers. The ghost line is `PoolSim.shoot` on
    a copy with the preview-only arguments `max_ticks` / `stop_after_contact` (defaults unchanged: a real
    shot always runs to rest), computed on a WorkerThreadPool task (10–50 ms of GDScript).
  - Your live game and your shot → the line is posted (TableBook.post) and the cue only strikes when the
    chain's line is read back and replayed; anyone's shot replays from behind the cue ball they struck.
    No live game of yours → **PRACTICE**, a local PoolSim, labelled "nothing is posted".
  - **Twenty-One** (`CardSeat`): two stools on the near arc, the shoe and a "DEALT BY THE CHAIN · block N"
    sign across (`m["deal_block"]`, the accept line's block), HIT / STAND plates on the felt (click or
    `table_hit` / `table_stand`), chips = whole Ⓐ of the stake (1–12). Practice is you vs the house
    (draws below 17), dealt by Duel21 from the **latest block's hash** read from the chain; no hash → no
    cards, "—".
- **Cabinet titles:** a backlit marquee topper (1.16 × 0.66 m, wider than the body) whose text
  `ArcadeCabinet.marquee_fit` sets on one or two lines (never wrapping off the panel), the name on the
  screen's bottom bezel, and a floating title + "1 Ⓐ a play · press E" over the nearest cabinet within 3.4 m.
- **The Affection Fair's mini games** (`scripts/world/funfair/`, 2026-11-24). The seven midway games
  (Test Your Affection, Entropy Toss, Regolith Ring Toss, Crystal Shy, Motzkin Prime Shooter, Waat Wheel,
  Saat Fortune Teller) play in first person at their stall: Use there → ticket → `MidwayPlay` (the
  `TableSeat` glide and overlay) → the stall's `MidwayStage` (`minigame/*_stage.gd`) stages the round in 3D.
  - **The rules are `MidwaySim`: pure, integers only** (mm, ticks at 60 Hz, 1/12000 turn, Bhaskara
    `isin`, xorshift32 seeded by `MidwayGame.seed_from_tx(ticket)`). The only input is a log of presses
    `[tick, ax, ay]`, aims quantised to [-640, 640]. `MidwaySim.replay(game, seed, log)` = the score, or -1
    for a log the game couldn't have taken. The 3D only reads the sim. Changing a rule changes old scores:
    bump `MidwaySim.VERSION` (lines carry `v2:` now; v1 lines show as unverified) and the recorded rounds in
    `tests/test_fair_minigames.gd`.
  - **v2 rules (2026-11-24, "make it fun")**, all in the sim: a streak of good results multiplies (×1, ×2, ×3…,
    capped per game; any other result ends it and scores ×1); every throw is harder than the last (faster
    meters, stronger drift and sliding rings, more sway, rails that speed up per crystal, shorter pop-ups,
    faster wheels); bonus targets (PERFECT swing 150, bullseye 150, the gold peg ×2, gold crystals 250,
    Mersenne primes 3/7/31 250, the 500 jackpot); the last throw(s) (Motzkin: the last 8 s) are a FRENZY ×2;
    `last_near` flags a near miss. Results stay up 32 ticks (was 50). Rounds: striker 5, entropy 5, regolith 6,
    crystal 8, motzkin 20 shots, waat 5, saat 7. **Saat is now Higher or Lower** (axes 1: aim < 0 = lower)
    with a deck from the ticket; it scores and posts like the others, and the fortune is still read.
    `MidwaySim.max_score` is the rules' bound (every throw perfect at full streak and frenzy); prizes are tiers
    of `MidwaySim.par` (the grand prize's score), not of the bound.
  - **Tickets say which stall** they bought: `AFFECTION.transfer(QING, 1 Ⓐ + k wei)`, k = `MidwaySim.code`
    (striker 1, entropy 2, regolith 3, crystal 4, motzkin 5, waat 6, saat 7); the screen still says 1 Ⓐ
    (`ArcadePay.transfer_to_qing(…, fee_wei)`, `verify_receipt` takes ≥ fee). Practice (no wallet) is labelled.
  - **Shared boards are room lines**: `🎪 <game> <score> <ticket tx> v1:<log>`; the log is per press the
    tick delta in base 36 then each aim + 640 as two base-36 digits, joined by "." (the longest possible, Motzkin's 15
    shots, is ~230 characters at v2's 20 shots; the room line limit is 280, checked by the tests). After a paid round `fair_post` (P) posts it with
    `TableBook.post` (one approval: CHOA.Chat, so it also adds Ω Hypobar to the QING). `FairBoard.read` scans
    the QING's room lines from `FairProgress.FROM_BLOCK` (28,136,000: the format can't be older) and keeps a
    line only if (a) the ticket's receipt has AFFECTION `Transfer(line's tx.from → this QING, 1 Ⓐ + this
    game's k)` and (b) the replay gives the claimed score; one ticket counts once (its first valid line).
    Others count as "unverified". Each stall shows its top 10 on a board on its side wall, and the result
    screen shows it next to this computer's board (`ArcadeScores`, `fair:<game>`).
  - **The Upsilon Rocket unlocks** for a wallet at a QING when the chain shows all seven k's:
    `eth_getLogs` on AFFECTION with topics `[Transfer, pad(wallet), pad(QING)]` from `FROM_BLOCK`
    (`FairProgress.refresh`, cached in `user://fair_progress.cfg` with the block read to; only the tail is read
    again, after every paid play). `RocketLights` by the booth lights a lamp per game; no wallet = the free
    preview, as before. Measured 2026-11-24: that two-topic filter over **the whole chain** (block 0 → head)
    answers in < 1 s when the pair has few transfers, but for a busy pair (hundreds of transfers a day) the
    node cuts the body off after ~10 s (HTTP 200, 23 bytes of JSON); scan from `FROM_BLOCK`, never block 0.
  - **Game feel** (`minigame/fair_fx.gd`, `fair_sfx.gd`, `fair_crowd.gd`): MidwayPlay watches the sim (presses,
    `last_tick`, the frenzy) and dresses each event: bursts, sparks, rising score pop-ups, a flash light, chase
    bulbs round the back wall (still / idle / win / grand), squash-and-stretch, camera shake (`Camera3D.h/v_offset`)
    and a hit-stop (the sim's ticks pause a beat: replay is unaffected). Sounds are synthesised into
    AudioStreamWAV on first use (no sample files). Onlookers (AmbientNPC, walked by FairCrowd) gather as the
    streak grows and dance on a good round; a prize of a moon or better (or a pennant with a streak of 3) gets a
    3.4 s celebration (wide shot, confetti, the prize spinning over the counter). A how-to card shows the first
    time per game on this computer (`user://fair_seen.cfg`). `MidwayAuto` is a skilled player for previews only.
  - **Prizes** (`fair_prizes.gd`): crystal trophy / toy Upsilon rocket / plush moon / pennant, one merged mesh
    each. Local keepsakes like ArcadeScores (`user://fair_prizes.cfg`, with the ticket tx); each stall's shelf
    shows today's stock (1/2/4/3, a sold-out tier gives the next one down) and "yours". Practice wins show the
    prize but keep nothing.
  - **Rides board and alight with a short walk/step** (RideBase: `step_seconds` at DoorWalk's pace, a small hop
    onto/off the seat, the Walk clip via `hold_clip`); `ride_finished` fires once the rider is down. A rider over
    30 m from the exit (back from the voyage) is set down directly; `paused` still skips seating.
  - Shots: `screenshot.gd -- --qing=<Grand Fair QING> --fair=<game>|rocket [--fair-phase=aim|play|hit|cheer|howto|result|board]
    [--fair-codes=1,2,3]` (practice, nothing paid or posted). `tools/probe_fair.gd [-- --wallet=0x…]` plays
    all seven through, replays each score and checks the rocket's lock from the chain.

---

## 15. Vehicles at the pad (2026-11-24)

- **Every territory has a vehicle pad** (`GarageSite`) near arrival: a terrace in the terrain's own material,
  placed like the fair (`find_site`: on land, flattest, clear of the Core's landmarks, the skyline ring and the fair).
- **Unlocks come only from state the game already read** (`VehicleUnlocks.gather`: Session's identity and bars
  pass, this territory's board). Not read yet → "…", read failed → "—"; neither counts as locked or open.

  | Vehicle | Opens when |
  |---|---|
  | Regolith Rover (6 wheels) | always, no wallet needed |
  | Hoverbike | a Hypobar anywhere (`YUE.Bar(QING)` > 0 at any territory) |
  | Crest Skimmer | a Hypobar here (`YUE.Bar(this QING)`, or a row on this board) |
  | Lander Hopper (VTOL) | bars at 3+ territories (the gear's spark rule, §11) |
  | Bar Crawler (tracks) | your tower is in this board's top 3 (known players; the skyline everyone sees) |

- **Rental:** E at a locked bay pays 1 Ⓐ to this QING through `ArcadePay` (simulate → sign → receipt Transfer
  check); that vehicle opens here for this session only (in memory, keyed wallet@QING:kind). The credit
  ArcadePay records is spent at once, so a rental is never also an arcade play.
- **Physics:** a yaw-only `CharacterBody3D` (capsule keel + box) on the terrain collider and every `Solid`;
  the feel (drift, hover cushion and glide, hops, fuel, springs) is pure functions in `VehicleSpecs`.
- **Sunny's bar menu** (`BarTab`, `BarMenu`; 2026-11-24): the drinks are the visitor's own calls. All six
  AFFECTION ops (`Pi() Rho() Generate() Alpha(uint64) Beta(uint64) Upsilon(uint64,bool)`) simulate fine from a
  player wallet [live, block ≈28,135,800; gas ≈ 50k–160k]; `Generate()` returns a uint256. Their reserve
  mints show in a receipt as AFFECTION `Transfer(0x0 → AFFECTION)` logs (other contracts mint 1 Ⓐ ones by the
  thousand: count only the logs in *your* receipt). After a pour the bar re-reads `YUE.Bar(QING)` at the
  receipt block − 1 and the receipt block and shows the measured change; for an AFFECTION op it is +0 (§1),
  and the menu says so. "The House Su" is `CHEON.Su(QING)`, the drink that does move bars. "Round for the
  house" is `ArcadePay.transfer_to_qing` (1 Ⓐ, receipt-verified, no arcade credit); the room cheers only after it.

## 16. The skyline landmark and base jumping (2026-11-24)

- **One landmark per developed QING** (`scripts/world/skyline/`, numbers in `LandmarkPlan`, pure). Class
  from the Development tier: Wild/Outpost **nothing** (moonscape); Settlement a sky inn (64–112 m);
  Town a grand hotel (128–232 m); City a twisted supertall (260–400 m + open crown); Capital a
  Burj-class Y-plan tower (440–600 m roof + a spire of 0.32 × roof). The height is the Hypobar
  total's log10 placed in the tier's band, in whole 4 m floors; bars only grow, so it only grows.
  RatKing (log10 ≈ 9.1 at block 28,135,887): Burj, 111 floors, roof 444 m, spire tip 586 m.
- **Site:** `LandmarkPlan.find_site` is the fair's search (round footprint fully on the plateau,
  flattest, clear of the Core, arcade, monolith, plinth, arrival, the skyline ring, the fair and the vehicle pad, 24 m inside the border fields),
  ≥ 119 m from the Core, preferring ≈212 m north. The plaza (r 30 m) and the landing ring (r 14 m, 90–220 m away) are terraces
  in the terrain's own material. The site does not depend on the tier, so it never moves.
- **Lit windows** follow Development energy (Epibar total); **signs** are the QING's name (registry
  snapshot of `name()`), the Hypobar total with its block, and the top Hypobar holder's
  `LAU.Username()` (via `CHO.GetUserTokenAddress`), omitted when it does not read.
- **Chain sense:** the glass lift is **free** (looking costs nothing). The jump from the sky deck is
  the act: a **1 Ⓐ jump ticket**, `AFFECTION.transfer(QING, 1e18)` through `ArcadePay.pay`
  (simulate → sign → receipt Transfer log verified → QING balance re-read), the credit spent at once.
  No wallet or no ticket: a **practice** jump, labelled, never recorded. A jump from **your own
  skyline tower** (its height is your Hypobar here) is free and scored. Any drop of ≥ 24 m becomes a
  (practice) jump.
- **Flight** (`JumpPhysics`, pure): the player's own gravity 3.2 m/s²; freefall terminal 30 m/s
  (44 head-down); wingsuit settles to 22 fwd / 6.8 sink (glide ≈ 3.2), dive and flare change it;
  canopy 8 / 3.0, flare (hold jump) 3 / 0.6 for 2.2 s. Wind is per territory (`String.hash` of the
  lower-cased address; 1.5–4.5 m/s with gusts). An edge wind turns you back at |x|,|z| > half the edge − 28 m (334 m).
  An automatic canopy fires below 30 m AGL in a fast freefall.
- **Score:** horizontal metres flown + ring points (≤ 3 m 1000, ≤ 8 m 600, ≤ 14 m 300, else
  200 − d), times the landing (stand-up 1.0, skid 0.6, impact 0.25). Bests are local
  (`user://basejump.cfg`).
- **Check it:** `tools/live_basejump.gd [-- --qing=0x…]` (headless, read-only, a practice jump) rides the
  lift, launches, opens the wingsuit and canopy and prints the score card; RatKing: lift 444 m in
  ~17 s, ~80 s of flight. Previews: `screenshot.gd -- --view=tower|deck|jump`.
- **Keys:** `wingsuit` (Q) and `parachute` (C) are input actions in `project.godot`, listed in
  `ControlsHelp.ACTIONS`.

## 17. QING chat from anywhere (2026-11-24)

- **What a room line does** [live]: `CHOA.Chat(qing, text)` is a reaction plus the line: Ω (`⌊Fornax(QING)/E_Q⌋`)
  goes to the speaker's Hypobar here, Omicron to their Epibar (§4), and the QING logs `LogEvent`. It needs
  admission (§5). After a post the game reads `YUE.Bar(QING)` at the receipt block − 1 and the block and shows
  the measured change.
- **Cost of one line** [live, Zürich, PulsePunk's wallet, block ≈ 28,136,975]: `eth_estimateGas` **≈ 848,000 gas**;
  at the node's gas price then (≈ 6.5·10¹⁴ wei) ≈ **550 PLS**. One wallet approval per transaction; a cover room
  also needs Join once a day (approve cover + 1 wei, then Join: 2 approvals, or 1 when the allowance suffices).
- **Batching works** [live]: CHOA keys the speaker on **tx.origin**, so `Multicall3.aggregate3` of several
  `CHOA.Chat` calls posts them all from one signature (a 3-line batch: ≈ 1,787,000 gas, ≈ 596k a line, vs 848k
  alone). A wallet with no YUE reverts the same through Multicall3 (`NotStarted`, masked as "Multicall3: call
  failed" when allowFailure is false, so simulate the batch with allowFailure true to decode each line).
  Players already do it: PulsePunk's tx `0x67c3…f258` sent 40 × (`QING.Join(LAU)` + `QING.Chat(LAU, "Anyone
  home?")`) to 40 rooms in one transaction (4.4 M gas). The chat bar sends one line at once; lines typed while it
  is being signed go together as one aggregate3 (allowFailure false: all post or none), max 5.
- **`eth_simulateV1` and `debug_traceCall` are not available** on `rpc.pulsechain.com` now (−32601, checked
  2026-11-24), despite §9. Simulate with `eth_call`/`eth_estimateGas`; the logs come from the receipt.
- **Site API** `/api/qing-chat` returns `{from, fromName, soul, text, txHash, block, logIndex, qingAddr}` (no Aura,
  so no ✓/⚠); `from` is the tx sender. The game paints with it first and replaces each line with the chain's copy;
  speakers' wallets come from `eth_getTransactionByHash` (tx.from), never from the API.
- **Rooms are quiet**: on 2026-11-24 the newest line in the busiest rooms (Zürich, Illinois, RatKing, Shell City,
  enter teh QING) was ~349,000 blocks (≈ 40 days) old. "Lines today" (8,400 blocks ≈ 24 h) is 0 everywhere, so the
  crown glow is at rest and no tower carries a top-speaker marker; both follow the lines when they come.
- **Free chat**: say lines go through the presence server (`Net.send_chat`) when it exists; they are tagged "say",
  carry no block and add nothing to the territory. Only room lines are chain truth.

## 18. Online play: the free game server (2026-11-24)

- **Where:** a headless Godot server on the owner's laptop, behind Tailscale Funnel or Cloudflare Tunnel
  (`docs/SERVER.md`), listening on 127.0.0.1. Launch: `server.bat`, `tools/server.sh`, or
  `godot --headless --path . res://scenes/net/game_server.tscn -- --port=8787` (`-- --server` also works).
- **Finding it:** Settings (F2 → Online & voice) or `GET <site>/api/game-server` → `{url}`
  (`https://` becomes `wss://`). No answer → single-player, one log line, quiet retries (5 s, then 20 s up
  to 5 min). Autoloads do no network on their own: `NetPresence` (added by the territory) starts `Net`
  20 frames after arrival, because the loading frames are long enough to time out a handshake.
- **Identity:** `personal_sign` (EIP-191) of `NetProto.login_message(server, nonce)` through the
  wallet relay (`wallet_bridge.personal_sign`, `Wallet.sign_message`). The server runs `ecrecover` in
  pure GDScript (`scripts/net/crypto/`: Keccak-256, secp256k1 10×26-bit limbs, about 105 ms) on a
  WorkerThreadPool task. It checks against ethers v6 goldens (`tests/golden/ecrecover.json`, made by
  `tools/golden/ecrecover.js`). After that, a 24 h session token. Guests see and hear but can't talk.
  Names are the client's LAU Username; the tag also shows the short verified wallet.
- **Wire:** NetProto (binary, little-endian). Presence is 19 B at 10 Hz, positions in int32 cm, yaw u16;
  the server relays changed states every 100 ms to the same room only. `NetInterp` draws 150 ms in the
  past on the sender's u16 clock. Voice is IMA-ADPCM, 16 kHz, 20 ms frames of 163 B, relayed within 40 m;
  the μ-law codec is the fallback.
- **API other features use:** `Net.send_chat(text)`, `Net.chat_received(wallet, name, text, world_pos)`,
  `Net.top(board, n)`, `Net.submit(board, entry)`. Offline, these return `{ok:false, error:"—"}`.
  Leaderboard verifiers plug in by board-id pattern (`Leaderboards.add_verifier`). `FairVerifier`
  checks the ticket receipt and replays if `MidwayGame.replay(game, seed, inputs)` exists. Without a
  verifier, a row is "unverified". No row is ever invented.
- **Chat UI:** the QING chat bar (§17, T; Tab switches to "say") calls `Net.send_chat`, and its feed shows
  `Net.chat_received` lines. Remote avatars register with `ChatFeed.register_speaker`, so `ChatLife` floats
  bubbles over them, for free lines and on-chain lines alike. `NetChatFeed` (on the HUD) shows only the
  server status, notices and the talking mark.
- **Keys:** `push_to_talk` (X) is an input action. The mic stays off until the player opts in.
  `audio/driver/enable_input=true`.
- **Check it:** `tools/net_selftest.gd` (35 checks, scripted clients with test keys) and `tools/net_bot.gd`
  (a remote player for screenshots: `screenshot.gd -- --net-url=ws://127.0.0.1:N`, no `--view`).

## 19. Exchanges: the Swap Hall (PulseX) and the YUE Exchange (2026-11-24)

- **PulseX addresses [live, block 28,136,888]** (each has code; each router's `factory()` returns its
  factory and `WPLS()` returns WPLS; `WETH()` reverts): V1 router `0x98bf93ebf5c380c0e6ae8e192a7e2ae08edacc02`
  → factory `0x1715a3e4a142d8b698131108995174f37aeba10d` (65,546 pairs); V2 router
  `0x165c3410fc91ef562c50559f7d2289febed552d9` → factory `0x29ea7545def87022badc76323f373ea1e707c523`
  (192,747 pairs). ⚠ The site's `api/prices.js` calls `0x1715…` "PulseX V2": it is **V1**.
  `read_board` re-checks `factory()`/`WPLS()` on every read and turns swaps off if they ever differ.
- **Router:** Uniswap-V2 function names (`swapExactETHForTokens`, `…ForETH`, `…SupportingFeeOnTransferTokens`,
  `getAmountsOut`). The fee is **0.29%**: `out = in·9971·rOut / (rIn·10000 + in·9971)`
  (`getAmountOut(1e6, 1e30, 1e30) = 997,099` on both). Reverts are `Error(string)`: `PulseXRouter: EXPIRED`,
  `PulseXRouter: INSUFFICIENT_OUTPUT_AMOUNT`, `PulseXLibrary: INSUFFICIENT_INPUT_AMOUNT`,
  `TransferHelper::transferFrom: transferFrom failed` (not approved / too little); no pair → a bare revert.
- **Pools [live, block 28,136,967]:** every Swap Hall token has a WPLS pool: AFFECTION (V2 ≈ 138.9M WPLS,
  V1 0.8M), Fornax (V2 only, 24.5M), Fomalhaute (V2 11.0M, V1 0.6M), Eris (V1 12.2M, V2 9.7M), Tethys/CHO
  (V1 5.2M, V2 3.7M), qZů (V2 6.2M), the Zürich asset (V2 11.0M), MATH, NoNukes, CROWS, VOID, CHEON (92k),
  SIU (4k: thin, 1,000 PLS moves it 20%). Of the 942 QING tokens only **5** have a pair (qILLINOIS, qZů, q⩜,
  q🈹, qSOLO); **714** of their assets do (mostly bridged tokens). None of the tested tokens takes a
  transfer fee: plain swaps simulate fine (the game still retries the FoT variant on `PulseX: K`).
- **Simulated from real wallets [live]:** 1,000 PLS → 38.25 Ⓐ from the owner `0x18f6…3111` (eth_call
  with `value`; Transfer pair → wallet); approve + 100 Ⓐ → 2,599 PLS from `0xb644…d465`, and approve + 10
  Zürich → 67.1 PLS from the owner, both with `trace_callMany` (state carried between the two calls;
  `eth_simulateV1` is **not** available on rpc.pulsechain.com today). Without the approval the sell
  reverts `TransferHelper::transferFrom`.
- **YUE exchange [live]:** `Hong(SpendAsset, QingAsset, Amount)` `0xb3bde122` buys, `Hung(QingAsset,
  ReceiveAsset, Amount)` `0x518945cd` sells. Cost = `Amount × Rate / 10^18` (every rated pair is 18/18
  decimals). The YUE calls `transferFrom(you → YUE)` for what you pay (so **approve the YUE you trade
  with**) and pays out of **its own stock**; what you pay stays in that YUE.
  - **Any YUE, anyone:** `GetAssetRate`/`IsValidAsset` read the same on every YUE (it is
    `QING.GetMarketRate(Asset())`, set by the QING's owners with `AddMarketRate`, only rising). The desk is
    whichever YUE holds what you want; the game picks the one with the most stock (yours on a tie).
  - **Rates:** only **14 of 942** QINGs have one for their asset (Illinois 0.1, MrStu 10, **Zürich 1e6 Zů per
    qZů**, enter teh 1, PP4000 35.2, HoneyPot 1e-11, …; `tools/live_yue_exchange.gd` prints all). **No QING's
    asset is itself a QING**, so the "walk up the hierarchy" in the knowledge base has nothing to walk today
    (the game reads one level up if that ever changes). RatKing (the only Burj) has **no rate**: its desk
    honestly says so and lists the territories that do.
  - **Stock:** of the 55 known YUEs, 4 hold Illinois stock, 8 hold qZů (12 qZů in `0x1058…3c5c`, 1,000 Zů in
    `0x4f94…f2d4`), 2 hold q🍯.
  - **Simulated [live]:** from the owner, approve + Hong 0.0001 qZů at YUE `0x1058…` (pays 100 Zů) and approve
    + Hung 0.0001 qZů into `0x4f94…` (gets 100 Zů) both **succeed** (trace_callMany); Illinois both ways too.
  - **Errors [calc + seen live]:** `InvalidPair(address,address)` `0xd9a764d9` (token not on the asset chain),
    `ExchangeRateNotFound(address,address)` `0x464460b9` (no rate), `ERC20InsufficientAllowance` `0xfb8f41b2`
    or `DysnomiaInsufficientAllowance` (approve first; plain OZ assets revert `ERC20: insufficient allowance`),
    `MarketRateNotFound(address)` `0x90b23441`, `OnlyGameTokens(address)` `0xd65928ec`; a non-QING as QingAsset
    reverts with no data.
- **In the game** (`scripts/world/exchange/`, panels in `scripts/ui/`):
  - **Swap Hall** (`SwapHall`): Wild = a surveyed lot whose two field terminals already trade; Outpost+ =
    the hall (curved glass front, wing roof, price pylon, ticker, quote wall, hanging board, swap counter).
    Site: `LandmarkPlan.find_site` from `0.3·SIZE_M` east, clear of the Core, skyline, fair, pad, tower
    plaza and landing ring. Boards are the reserves at one block, no wallet: the same for every viewer.
  - **YUE Exchange** (`YueFloor`): a glass sky lobby hung off the glass lift at ≈ roof/5 (16–96 m, whole
    floors; RatKing's Burj: 88 m), a stop of the existing lift (`Landmark.exchange_y`: E goes on up to the
    deck, Ctrl back down). Every tower class has one (Sky Inn … Burj); Wild/Outpost have no tower, so the
    Swap Hall's YUE counter (or the lot's terminal) is the desk.
  - Writes: approve (simulate → sign → receipt → allowance re-read ≥ amount) → swap / Hong / Hung
    (simulate from the wallet, with `value` for a buy → sign → receipt → Transfer / WPLS logs checked →
    balances, pool or desk re-read at the receipt block). Sells also measure the PLS received:
    balance(block) − balance(block−1) + gasUsed·effectiveGasPrice.
- **Check it:** `tools/live_swaps.gd [-- --wallet=0x… --qing=0x… --all]`, `tools/live_yue_exchange.gd
  [-- --wallet=0x… --qing=0x…,0x…]` (read-only). Previews: `--view=swap|swap_in|swap_panel|yue|yue_panel`.

---

## 20. The diegetic loop, the Heart, Core detail (2026-11-24)

- **Acts are derived, never invented.** `PlayLoop.acts(snapshot)` turns reads the game already makes into at most
  six things to do *here*, each naming its call: Su at the pylons (Ω; "your tower grows" when `floors_for(mine + Ω)`
  rises), Beat at the Heart (only when readiness is ready/fragile, else the diagnosis), the room (quiet = no line within
  one DysnomiaTime day ≈ 11,223 blocks; a covered room you are not admitted to = Join), crowns (pass #k in ≤ 25 Su; hold
  the lead), a neighbour beyond a field where `Session.bars` has nothing (Ω there from Fornax ÷ Entropy), dry wells
  (balanceOf(QING) = 0: a fact, no call offered: a donation is owner-withdrawable, GWAT = false). Unread → null → "—".
- **Goals:** next tier (`Development.next_threshold` − total, ⌈÷ Ω⌉ Su), your tower (floors and Su to the next floor,
  found by an exact BigInt search over `floors_for`), streak (PlayerRecord's YUE mint logs), territories with bars
  (avatar gear thresholds 3 and 10). Totals are floors (known players).
- **Measured on 2026-11-24 for `0x18f6…3111`** (`tools/live_acts.gd`): RatKing Ω 875,634, tower 12 floors, next
  floor in 340 Su, Beat ready, room quiet since block 27,787,864 (a "PulsePunk: Anyone home?" broadcast to many
  rooms); Illinois Ω 26, #5 → pass #4 in 2 Su, Settlement in 281 Su; MrStu Ω 66, no bars yet (first Su builds a
  1-floor tower), the west neighbour Noumenon has Ω 39,193. Most neighbours read Ω = 0.
- **Celebrations show only re-read numbers:** Su = YUE.Bar at the receipt's block minus the preview's; a room line =
  YUE.Bar at block − 1 → block; Beat = receipt status 1. Markers/tracker/steward text are personal UI; the territory's
  own look still depends only on territory state.
- **The Heart (owner: "the sphere and beam were cheesy")** is an armillary orrery: a faceted crystal with a light
  inside, one gimbal ring per tier (Wild 1 … Capital 6) tilted by arg(c) + k·golden angle, turning with the energy
  (Epibar total); it ticks on each new block read and beats (shock ring) on a confirmed Beat. The tier shaft is an
  additive shader (`light_shaft.gdshader`: brightest mid-silhouette, fades with height and at its edges), 14 + 10·tier m,
  280 m at Capital with a 48-light halo (one MultiMesh) instead of the gold torus.
- **Core detail** (`CoreDressing`): metal-plate paving r 22 m with kerb, inlaid light lines and 36 bollards (MultiMesh;
  gaps at the four roads), the Room's plinth band, cornice and door portal (Column_Astra, canopy, threshold, spot),
  stepped bases on the pylons/monolith/World plinth, metal well rims, tower podiums. Label3Ds on the Core have outlines.
