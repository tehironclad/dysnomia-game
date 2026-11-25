# Security audit: players' wallets, signatures and the game server

**Date:** 2026-11-25 · **Branch:** `security` (local, not pushed) · **Base:** `d160b37`

The question: can anything in the game cost a player funds, leak something, or let someone else act as them?
Players connect real browser wallets holding real tokens on PulseChain (chain id 369). The game never holds a
private key; every write is signed in the player's own wallet. So the attack surface is everything that decides
**what the wallet is asked to sign**, **what the game believes was signed**, and **who the game believes the player
is** on the game server.

## Scope

| Area | Files read |
|---|---|
| Wallet bridge | `scripts/chain/wallet_bridge.gd`, `assets/web/wallet.html`, `scripts/core/wallet.gd`, `scripts/chain/wallet_diagnosis.gd` |
| Every write | every `Wallet.send` caller: `arcade_pay.gd`, `bar_tab.gd`, `table_book.gd`, `chat_controller.gd`, `chat_feed.gd`, `chat_outbox.gd`, `border_ring.gd`, `core_actions.gd`/`moves.gd`, `onboarding_panel.gd`, `lau_finder.gd`, `room_state.gd`, `swap_panel.gd`/`exchange_panel.gd`/`pulsex.gd`, `yue_panel.gd`/`yue_exchange.gd`, `invites.gd` |
| Signatures | `Wallet.sign_message`, `net.gd`, `net_client.gd`, `net_proto.gd`, `game_server.gd`, `wallet_diagnosis.gd`, the `--net-key` flag |
| Untrusted content | `chat_lines.gd`, `chat_panel.gd`, `chat_feed_panel.gd`, `qing_hall.gd`, `inspector.gd`, `net_client.gd`, `net_match.gd`, `player_registry.gd`, `site_api.gd` |
| Network | `rpc.gd`, `chain.gd`, `site_api.gd`, `net.gd`, the game server (`game_server.gd`, `server_main.gd`, `invite_book.gd`) |
| Local data and releases | every `user://` file, logs, `export_presets.cfg`, `.github/workflows/release.yml` |
| Vendored code | `wallet.html` (no external scripts, before or after) |

Out of scope: the contracts themselves, the site (`enterdysnomia.com`) and its pulse node, malware already running
as the player's user (it can do anything the player can, short of signing in their wallet).

## Findings

Severity is for a player with a real wallet. "Fixed in" is the commit on `security`.

| # | Sev. | Finding | Fixed in |
|---|---|---|---|
| F1 | **High** | **The game server chose the text the player signed.** `NetClient` signed whatever `login` string the server's welcome carried. A malicious server (its URL comes from Settings *or from the site's discovery endpoint*) could get the player's `personal_sign` on any text: another site's sign-in challenge (account takeover there), or **this** server's real login text relayed from a second connection, signing in to the real server as the player (chat as them, accept invites and stakes as them). | `128530f` |
| F2 | **High** | **DNS rebinding against the wallet bridge.** The local HTTP server served the token-bearing `wallet.html` to any `Host`. A website whose name re-resolves to 127.0.0.1 could read the page, take the session token and link to the game as *the* wallet window whenever none was linked (before the player opens it, or after it closes). It would then receive every transaction the game asks for, could answer with fake accounts, hashes and relayed chain reads, and could ask the player's wallet (injected into its page too) for an altered transaction at the exact moment the player expects a popup. | `df33f13` |
| F3 | Medium | **The mined transaction was not compared with the request.** After the receipt, `Wallet.send` checked only `from` and `status`. A wallet, extension or page that swapped a recipient or calldata was reported as success (`ArcadePay` and the swaps re-check their own logs; Su, Beat, Join, chat, LAU moves did not). | `a7d99c7` |
| F4 | Medium | **YUE desks came from a list the site could rewrite.** `Players.refresh_from_site` could add or overwrite any wallet's YUE, and the YUE exchange approves tokens to that address and calls it (`Hong`/`Hung`). A planted "YUE" with some stock would be picked and take the approved amount. | `2ca3b40` |
| F5 | Medium | **A dishonest game server could invent a wager debt.** Match records (players, stake, every `stake_ok`, `concede`) come from the server; `Invites.pay` paid `AFFECTION.transfer(winner, stake)` on that record alone, and the stake was not bounded on the client. The wallet still shows recipient and amount, but the game itself said "you owe". | `58d0b6f` |
| F6 | Medium | **Session tokens were not bound to a server.** The client re-sent its 24-hour token to whatever URL it connected to next (a server switched in Settings or by discovery), which could replay it at the original server as the player. The server also kept raw tokens in `tokens.json`. | `128530f` |
| F7 | Medium | **Release supply chain.** Actions were pinned by tag, the Godot editor and export templates were downloaded without checksum verification (a swapped download would backdoor every build, including the signing bridge), and the `workflow_dispatch` version and secrets were interpolated into shell scripts. | `da51100` |
| F8 | Low | No guard in the write pipeline against **unlimited approvals** or **arbitrary signatures**. Every approve the game builds today is exact (PulseX: the amount in; YUE: the amount paid; room door: cover + 1 wei), and the only signed texts were the sign-in and the wallet test, but nothing enforced it. | `a7d99c7` |
| F9 | Low | `--net-key=<key>` (a test key that signs the server sign-in) worked in release builds. A player told to "launch with your key" would put it in shell history and process lists. | `128530f` |
| F10 | Low | Wallet page: no CSP, could be framed by any site (clickjacking a second window into the link), a site that opened it kept a window handle, and it showed only the contract before a signature. | `df33f13`, `a7d99c7` |
| F11 | Low | A web page could open sockets to the bridge in a loop: each unauthenticated socket kept a 16 MiB buffer for 10 s. | `df33f13` |
| F12 | Low | Plain `http://` RPC and site addresses were accepted; a `ws://` server could be suggested by the site; HTTP answers were unbounded. | `a08cf07` |
| F13 | Low | Untrusted text: chain names kept direction overrides and zero-width characters and had no length cap (spoofing "Sunny", reversed addresses); the F1 inspector put chain strings into BBCode unescaped; server-sent names, chat and notices were not cleaned on the client. Chat lines were already escaped (`[` → `[lb]`), and no text anywhere turns into an address, a link or an action. | `a08cf07`, `128530f` |
| F14 | Low | `String.is_valid_hex_number` accepts a sign, so `"0x-…"` passed address, hash and quantity checks. | `a08cf07` |

Nothing critical was found: no private keys anywhere (none are stored, asked for or logged), every target address
of every write is a `Contracts` constant or read from the chain (the territory, LAU, YUE, QING asset), never from
chat, a server message or typed text, and the simulate → sign → receipt → re-read rule was already followed
everywhere.

## What was fixed

**`df33f13` Wallet bridge.** The page (and its token) is served only when `Host` is `localhost:PORT` or
`127.0.0.1:PORT` (anything else gets 403). Every answer carries a CSP (`frame-ancestors 'none'`, no plugins, no
`<base>`, no forms, `connect-src` limited to the game's socket and the two relay nodes), `X-Frame-Options: DENY`,
`nosniff`, `no-referrer` and `Cross-Origin-Opener-Policy: same-origin`. Requests are read to the end of their
headers (8 KiB, 5 s). At most 8 sockets may be waiting for their hello (5 s). The page shows each request's label
next to the wallet popup. `tools/e2e_wallet.sh` now attacks the bridge: a rebinding `Host`, and a cross-origin
page that fetches it, frames it and opens three sockets (a guessed token, a forged `connected`, no token); the game's
wallet must not change.

**`a7d99c7` Write pipeline.** Before anything reaches the wallet, `Wallet.send` refuses an `approve` or
`increaseAllowance` above 2^128 and any `setApprovalForAll`. After the receipt it reads the transaction back
(`eth_getTransactionByHash`): `from`, `to`, calldata and value must be exactly what was asked, and the receipt's
`to` must be the contract asked for; otherwise it stops at **verify** with "NOT the one the game asked you to
sign". `Wallet.sign_message` signs only texts starting with "Dysnomia game server sign-in" or "Dysnomia wallet
test (free, not a transaction)", at most 600 characters. The page shows the decoded call (contract name, function,
recipient or spender, amount). The e2e harness adds an unlimited approve, a foreign text to sign and a tampered
transaction (the mock wallet swaps the recipient); none get through.

**`128530f` Sign-in v2.** The client builds the text itself:

```
Dysnomia game server sign-in
Server: <name, one line, ≤ 40 chars>
Host: <the host the player connected to>
Nonce: <32 hex from the server>
Issued: <UTC>   Expires: <UTC + 10 min>
This signature is free. It is not a transaction: it approves nothing and moves nothing.
Sign it only in the Dysnomia game, to sign in to this server.
```

The server rebuilds it for the host the client names and accepts it only if that host is the WebSocket request's
`Host` (or a `--public-host`) and within 10 minutes; each attempt gets a fresh nonce. A relayed signature names the
malicious server's host and is refused. Tokens are stored as SHA-256 only and the client sends one back only to the
URL that issued it. Server-sent text is cleaned on the client. `--net-key` works only in debug (editor) builds.
`tools/net_selftest.gd` adds the relay, the relay without a host, an expired text, hashed tokens on disk and a
token dropped on a URL change.

**`2ca3b40` YUE desks.** Every listed YUE is checked with `CHAN.Yan(wallet)` at the desk's block; only confirmed
ones can be desks. The site can add players but never change a known player's YUE.

**`58d0b6f` Wagers.** Match records are shape-checked (wallets, names; a stake outside InviteBook's rule is no
stake). Confirming a stake is remembered on this computer (`user://wagers_agreed.cfg`), and `Invites.pay` pays only
when the winner and loser are the record's two players, the connected wallet lost, and this computer recorded that
wallet agreeing to exactly that stake.

**`da51100` Release workflow.** Actions pinned to commit SHAs; Godot and the templates verified against pinned
SHA-512 sums (the editor zip was re-downloaded and matched); inputs, outputs and secrets reach scripts as
environment variables; checkout keeps no token; the public base URL must be https.

**`a08cf07` Hygiene.** `Rpc.url_ok` (https, or http only to this computer) for the RPC and the site; discovered
servers must be `wss://`; response caps (RPC 32 MiB, site 8 MiB); clean names and lines (no direction overrides,
zero-width, BOM, C1; names ≤ 32 chars); the inspector escapes BBCode; strict hex everywhere.

Every commit passed `tools/check.sh`, `tools/boot_territory.gd` (no script errors), `tools/e2e_wallet.sh` and
`tools/net_selftest.gd`. Totals at the end: 414 unit tests, 50 e2e checks, 81 server checks.

## What remains (and why)

| # | Sev. | What | Why it stays |
|---|---|---|---|
| R1 | Low | **Release zips are checksummed but not signed.** `SHA256SUMS` and `latest.json` sit in the same bucket as the zips, so whoever can write the bucket can replace both. Windows codesigning is off; macOS is ad-hoc signed, not notarized. | Needs keys and accounts the owner must create: sign `SHA256SUMS` with minisign/cosign (key kept offline, public key published on the site and in the README), then Authenticode and notarization. |
| R2 | Low | When every direct RPC node fails, chain reads go through the wallet page (`relay_rpc`). The page is the authenticated one, and it fetches two fixed HTTPS nodes, but the game then trusts the browser's answer. | It is the fallback for players behind HTTPS-scanning antivirus; turning it off would break them. Only an attacker already inside that browser profile could lie, and the wallet still shows every transaction. |
| R3 | Low | A lying wallet or extension could answer a request with the hash of an **older identical** transaction; the game would report it as new. | No funds move. Arcade credits are deduplicated by transaction hash, and fair plays are checked against the transaction. A freshness check would need the e2e harness to forge block numbers too. |
| R4 | Low | The page's CSP still allows inline script (`'unsafe-inline'`). | Wallet extensions inject their provider as inline script; a nonce-only policy could break MetaMask/Rabby for real players. The page inserts no untrusted HTML (only `textContent`). |
| R5 | Info | Godot's `WebSocketPeer` doesn't expose the handshake's `Origin`, so the bridge socket can't check it. | The socket is useless without the 128-bit token, and only the Host-checked page carries it. |
| R6 | Info | Wagers stay honour-bound: a player who agreed to a stake on another computer is told to pay by hand. | That is the price of not trusting the server's record of who agreed. |
| R7 | Info | The game server's operator sees chat, wallets and rooms; logs keep wallets (public) but never tokens or signatures. | By design (`docs/SERVER.md`). |
| R8 | Info | Malware running as the player can read the page, its token and the game's memory. | Out of scope; it still can't sign: the wallet shows every transaction. |

## What players should know

- **The game never has your keys and never asks for them.** No screen, file or setting takes a private key or seed
  phrase. Anyone who asks for one is stealing.
- **Every payment is shown in your wallet before it happens.** The game checks it on the chain first, and the
  "Dysnomia Wallet Bridge" window now says in words what the game asked for: the contract, the function, who
  receives what and how much. If your wallet's popup shows something else, **reject it**.
- **The game only approves exact amounts.** It never asks for an "unlimited" approval. If you see one in a
  Dysnomia window, reject it.
- **The only messages the game asks you to sign** start with "Dysnomia game server sign-in" (free, to chat online;
  it names the server and expires in 10 minutes) or "Dysnomia wallet test". Never sign anything else from that
  window. Signing is free, but a signature can still be misused.
- **After each payment the game reads the transaction back from the chain.** If it says the transaction "is NOT
  the one the game asked you to sign", something on your computer (often a browser extension) changed it. Check your
  wallet's activity and don't sign again until you know why.
- **The wallet window only works at `http://localhost:<port>`** and only for the game that opened it. Close
  windows from old sessions; they reload themselves anyway.
- **Bets at the tables are honour-bound.** The game only offers to pay a stake you confirmed on this computer, to the
  other player of that game. Pay only what you agreed to.
- **Download the game only from the official link**, and compare the file's SHA-256 with `SHA256SUMS` next to it.
