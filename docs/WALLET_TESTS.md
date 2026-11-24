# Wallet test checklist (manual)

Signing needs a real browser wallet, so every write ships this checklist. Run it with two wallets:
**fresh** (no LAU) and **onboarded** (LAU, YUE, Play done). Every step must end on a chain-read
confirmation, not on the wallet's own "confirmed".

Before starting:
- Run **Test my wallet** (below) first: if a step fails there, payments fail at the same step.
- The wallet must be on PulseChain (369). The relay page offers to switch it, and every payment asks again.
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

## Approval popups (regression check)

- [ ] With the game fullscreen, rent a vehicle and buy an arcade credit: the wallet window comes to the front and the wallet extension (Rabby/MetaMask) shows the approval without Alt+Tab. After signing or rejecting, the game comes back to the front.

## Test my wallet (Settings, F2) — find the failing step yourself

The wallet chip at the top of the screen always shows the state: `◌ WALLET · not connected`,
`● 0x18f6…3111 · PulseChain · wallet window linked`, or what is missing (window closed, wrong chain, no
wallet extension in that browser). Click it to connect or to bring the wallet window back. Under it, every
payment shows its stage, and a failure stays for 16 s as "✗ <what> — stopped at <stage>: <reason>". The
console prints the same lines with `[Pay]` (run the game from a terminal, or read `godot.log`).

1. Press **F2** → **Test my wallet…**. It runs at once (a wallet window may open); "Run the test" repeats it.
2. Read the steps top to bottom. Fix the **first ✗** and run it again:

| Step | ✗ means | Do |
|---|---|---|
| Local wallet relay | the game's local server didn't start | another program holds ports 38420+: change "Wallet relay port" in F2 |
| Wallet window linked | no "Dysnomia Wallet Bridge" window is talking to the game | close every old Dysnomia wallet window, click the wallet chip; allow the window if a firewall asks |
| Browser wallet in that window | the window opened in a browser without your wallet (e.g. Chrome while Rabby is in Brave) | F2 → "Wallet browser (.exe)": the path of the browser with your wallet, e.g. `C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe`; Apply; click the chip. With several wallets, pick yours with the "Use …" buttons in the window |
| Account connected | the wallet hasn't approved the page, or shows another account | click Connect wallet in the window and approve; switch to the account the game shows |
| Wallet on PulseChain (369) | the wallet is on another chain | a payment asks it to switch; or switch in the wallet now |
| Ⓐ in this wallet | under 1 Ⓐ in the wallet itself | Ⓐ on your LAU is moved over (LAU.Withdraw) when you pay; or send Ⓐ to the wallet |
| PLS for gas | not enough PLS for the transfer's gas | add PLS |
| A 1 Ⓐ ticket simulates | `AFFECTION.transfer(QING, 1 Ⓐ + 1 wei)` from your wallet reverts | the reason is shown (decoded revert) |
| Free signature round trip (optional box) | the wallet didn't sign, or the signature recovers to another address | approve the popup; if it never appears, the window step is the problem |

3. All ✓ but a payment still fails? Its stage tells where: *the chain check* (nothing was sent: the
   revert reason is shown), *the wallet window* (it didn't link within 45 s), *your wallet's approval*
   (rejected, or no answer in 300 s), *the chain receipt* (sent but not found, or reverted, or from
   another account), *checking the payment on the chain* (no AFFECTION Transfer(wallet → QING) in the
   receipt). Send the `[Pay]` lines with the report.

## Ⓐ payments (fair ticket, arcade credit, pad, sky deck, a round)

| # | Do | Expect |
|---|---|---|
| 1 | Fullscreen game, wallet on another chain: buy a fair ticket | "asking the wallet to switch to PulseChain" → the wallet asks to switch → the wallet window comes to the front *before* the approval popup opens, so the popup is on top. After signing, the game comes back. The chip shows "✓ … confirmed in block N". |
| 2 | Close the wallet window, then buy an arcade credit | "opening the wallet window…": it reopens, links, and the approval appears. The chip said "wallet window closed (click to reopen)" meanwhile; the wallet stays connected in the game. |
| 3 | Open the wallet window twice (click the chip while one is open) | The linked one is raised; a second window says another one is linked and closes itself. |
| 4 | Restart the game with the old wallet window still open | The old window reloads itself and links to the new game session. |
| 5 | Reject the approval | "✗ … stopped at your wallet's approval: rejected in the wallet". Nothing is credited. |
| 6 | While the approval is open, sleep/wake or wait 20 s | No popup is covered: the wallet window is raised again only while the game itself has the focus. |
