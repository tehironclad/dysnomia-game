# Wallet test checklist (manual)

Signing needs a real browser wallet, so every write ships this checklist. Run it with two wallets:
**fresh** (no LAU) and **onboarded** (LAU, YUE, Play done). Every step must end on a chain-read
confirmation, not on the wallet's own "confirmed".

Before starting:
- The wallet must be on PulseChain (369). The relay page offers to switch it.
- Keep a little PLS for gas. A Su costs about 0.78M gas and a Beat about 2.3M.

## Phase 4: identity (front door → Enter the Void)

| # | Wallet | Do | Expect |
|---|---|---|---|
| 1 | fresh | Connect wallet | The browser page opens. The identity card shows the wallet, "— (none registered)" for the LAU, and readiness NO ACCOUNT. |
| 2 | fresh | Forge (name + symbol) | The stages go simulate → sign → pending → "confirmed in block N". The LAU address is picked from the receipt logs (`Type()=="LAU"`, `owner(wallet)`). |
| 3 | fresh | Bind, Name, Wake, Play, in order | Each step ticks only once the chain says so: CHO maps wallet → LAU, Username is set, the YUE exists, and there is no ZeroHoldings. |
| 4 | either | Reject a signature in the wallet | The status shows "Stopped at sign: …". Nothing is marked done. |
| 5 | onboarded | Reopen the game | The identity card shows LAU/YUE/Soul/Aura and the four holdings with their verdicts. |

## Phase 5: the live loop (in a territory)

| # | Wallet | Do | Expect |
|---|---|---|---|
| 1 | onboarded | Walk to a pylon, press E | The Su preview shows +Ω Hypobar, +ο Epibar, Charge with its note, +1 YUE, gas, and the block. |
| 2 | onboarded | Sign Su | Reaches 4/4. The final line reads the bar at the receipt block: "+X Hypobar" equals the preview's Ω, unless another Su landed in between. Sparks run up the pylons. Your column grows and flashes on the next block. |
| 3 | onboarded | Door (E): the Room | The door facts are shown and lines load with ✓/⚠ badges. At an open room you can post directly. |
| 4 | onboarded | Post a room line | The line is read back from the receipt block's logs and appears in the list and on the Room wall. CHOA.Chat also grows your bars. |
| 5 | onboarded | A covered room (e.g. AFFECTION, 414 Ⓐ) | Join shows 2 steps when the allowance ≤ cover: approve cover + 1 wei, then Join. Afterwards "Admitted … true at block N". With a too-low asset balance, the button is disabled and the reason is shown. |
| 6 | not ready | Centre of the Room (E): Beat | No transaction is offered. The diagnosis lists the four holdings with their verdicts. |
| 7 | ready | Beat | The preview shows Dione/Charge/Deimos/Yeo. After signing, the Heart swells and the ticker shows "YOUR BEAT · block N". |
| 8 | onboarded | The monolith (E): the Void | Fomalhaute lines load with badges. A posted line (LAU.Chat) is read back from the chain. |
| 9 | none | Any panel with no wallet connected | The preview needs a wallet. Ω (the same for everyone) is still shown, and nothing can be signed. |
| 10 | `--session` view | Any panel | Previews are simulated from that wallet, and the panel shows "View only". |

## Borders: crossing into a neighbouring QING

| # | Wallet | Do | Expect |
|---|---|---|---|
| 1 | none | Walk to a border field, press E | The panel names the neighbour, its Δlat/Δlon and the MAP check, and says a LAU is needed. "Join to cross" is disabled. You cannot walk through. |
| 2 | onboarded | A border whose neighbour has no cover | "QING.Admitted(your LAU) is true at block N (no cover…)". "Cross into …" warps you to the neighbour, arriving just inside its matching edge, facing in. |
| 3 | onboarded | A border whose neighbour charges a cover | Join shows its steps (approve cover + 1 wei, Join). After signing, it reads Admitted back: only then is Cross offered. Walking into that field afterwards also crosses. |
| 4 | onboarded | Reject the Join signature | "Stopped at sign: …"; the field stays closed. |
| 5 | either | The edge of the map (a side with no QING) | The prompt says so; nothing is drawn beyond the field. |
