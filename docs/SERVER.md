# The free game server (on your own laptop)

Online play (seeing other players, free text chat, push-to-talk voice, shared leaderboards) runs on
**your own laptop**. Nobody pays for hosting. A free **tunnel** gives the server a public `https://`
address and hides your laptop's IP: players connect to the tunnel, and the tunnel forwards to your
laptop.

Nothing here touches the chain. The server never signs anything and never holds keys. Players sign in
with a **free signature** (`personal_sign`, not a transaction), so the server knows which wallet they are.
With no server reachable, the game is single-player as before.

```
player's game ──wss://──▶ tunnel (Tailscale / Cloudflare) ──▶ your laptop: 127.0.0.1:8787 (game server)
```

## 1. Run the server (Windows)

1. Godot must be where `play.bat` expects it (`Downloads\Godot_v4.6.1-stable_win64.exe\`). If it is
   somewhere else, edit the `DIR` line at the top of `server.bat`.
2. Double-click **`server.bat`** in the game folder. A console window opens and shows:
   `Dysnomia game server 'dysnomia' listening on ws://127.0.0.1:8787`.
3. Leave the window open. If the server ever stops, the script restarts it after 5 seconds.

Options go after the file name, for example `server.bat --port=8787 --name=Sunny`:

| Option | Default | Meaning |
|---|---|---|
| `--port=N` | 8787 | local port (the tunnel points here) |
| `--name=…` | dysnomia | shown to players in the sign-in text |
| `--max-players=N` | 200 | connections in total |
| `--room-cap=N` | 64 | players in one territory |
| `--voice-radius=M` | 40 | metres within which voice is heard |
| `--public-host=…` | (none) | only if your tunnel rewrites the `Host` header: the public name(s) players use, comma-separated. A sign-in signed for any other host is refused |

**Firewall.** The server listens on `127.0.0.1` only, so nothing on your network can reach it directly. If
Windows asks whether Godot may use the network, you can click *Cancel*: the tunnel connects from
inside your laptop.

**Files** (Windows): `%APPDATA%\Godot\app_userdata\Dysnomia\server\`
- `server.log`: connections, sign-ins, chat lines, scores, and a stats line every 5 minutes. It rotates
  at 5 MB (`server.log.1`).
- `leaderboards.json`: the boards. Back it up if you care about them.
- `tokens.json`: sign-in sessions (valid 24 h), so players don't sign again on every reconnect. Only the
  SHA-256 of each token is stored, so a copy of this file can't sign anyone in.
- With the Telegram bridge (§5c): `telegram_history.json` (the last 50 lines, for players who join later),
  `telegram_prefs.json` (wallets that opted out of moments), `telegram_mute.txt` (yours to write: muted Telegram ids).
  The bot token is never written to any of them, nor to the log.

On Linux or macOS: `GODOT=/path/to/godot tools/server.sh --port=8787`.

### On a Linux box (the pBank box, or WSL2 on a Windows PC)

On the pBank box (pls-portfolio `deploy/box/`, including its Windows/WSL2 version), the server runs as
a systemd service:

```bash
sudo bash tools/install-server-linux.sh            # NAME=<server name> to set --name
```

It creates a `dysnomia-server` service account (never a login) and prints a **read-only deploy key** to add in GitHub (this repo is
private). It clones the repo to `/opt/dysnomia/game` and installs Godot 4.6.1, checked against the
release's `SHA512-SUMS.txt`. It imports the project and starts `dysnomia-server.service` on
`127.0.0.1:8787`, with its files in `/var/lib/dysnomia-server`. Extra options from the table above
go in `/etc/dysnomia-server/env` (`SERVER_ARGS=--name=… --room-cap=…`). If the Entropy pulse node
runs on the same box, it is pointed at this server. Running it again updates the checkout,
re-imports when something changed, and restarts the server.

The box publishes it: give pBank's `install.sh` stage g a `--game-host` name, and the URL is
`wss://<that name>`. On a Windows PC that goes through the box's Cloudflare Tunnel, so you skip
section 2 below. The box's nightly backup copies `/var/lib/dysnomia-server` (the leaderboards).

## 2. Make it reachable: pick a tunnel

### Option A (recommended): Tailscale Funnel

Free, and you get a **fixed** address `https://<machine>.<tailnet>.ts.net`. You don't need a domain,
and your IP stays hidden.

1. Install Tailscale for Windows from https://tailscale.com/download and sign in.
2. In the admin console (https://login.tailscale.com/admin), under **DNS**, turn on **MagicDNS** and
   **HTTPS Certificates**. The first `funnel` command also offers a link to enable Funnel for your tailnet.
3. Open **PowerShell** and run:
   ```powershell
   tailscale funnel --bg 8787
   ```
   It prints the public address, for example `https://my-laptop.tail1234.ts.net/`. `--bg` keeps it
   running in the background, and Tailscale remembers it across reboots.
4. Check it: `tailscale funnel status`. To stop: `tailscale funnel --https=443 off`.

The game's server URL is the same address with `wss://`: **`wss://my-laptop.tail1234.ts.net`**.

Funnel traffic goes through Tailscale's relays, which may limit bandwidth. Presence, chat and a few voices
fit easily.

### Option B: Cloudflare Tunnel

1. Install `cloudflared`: `winget install --id Cloudflare.cloudflared`.
2. **Quick tunnel** (no account): `cloudflared tunnel --url http://localhost:8787`. It prints
   `https://<random-words>.trycloudflare.com`. **The address changes every time you start it**, so you
   have to update it each time.
3. **Named tunnel** (a fixed address; needs a domain on Cloudflare):
   ```powershell
   cloudflared tunnel login
   cloudflared tunnel create dysnomia
   cloudflared tunnel route dns dysnomia game.yourdomain.com
   ```
   Then write `%USERPROFILE%\.cloudflared\config.yml`:
   ```yaml
   tunnel: dysnomia
   credentials-file: C:\Users\<you>\.cloudflared\<tunnel-id>.json
   ingress:
     - hostname: game.yourdomain.com
       service: http://localhost:8787
     - service: http_status:404
   ```
   Start it with `cloudflared tunnel run dysnomia`, or install it as a Windows service:
   `cloudflared service install`. The URL is `wss://game.yourdomain.com`.

WebSockets pass through both tunnels with no extra settings.

## 3. Tell the game where the server is

Either:
- **for everyone:** the site's `https://enterdysnomia.com/api/game-server` returns `{"url": "wss://…"}`.
  The game asks it when a player arrives in a territory. Set it to your tunnel address.
- **per player:** **F2 → Online & voice… → Game server**: paste `wss://…` and click Apply. Leave it blank
  to use the site's address.

## 4. Keep it running for hours

- Plug the laptop in. In **Settings → System → Power**, set *When plugged in, put my device to
  sleep after* to **Never**. Sleep stops the server and the tunnel.
- To start the server at log-on, open **Task Scheduler** and choose *Create Basic Task*. Set the
  trigger to *When I log on*, the action to *Start a program*, and the program to `server.bat`.
  Tailscale's `--bg` funnel and an installed `cloudflared` service come back by themselves.
- The server is built for long unattended runs. Every connection has bounded buffers, idle
  connections close after 75 s, sessions expire after 24 h, and the log rotates. The whole
  process restarts if it ever exits.
- To see what is happening, look at the log. Every 5 minutes it writes a `stats:` line with
  connections, rooms, chats, voice frames, bytes in and out, and how many messages were throttled or
  refused.

## 5. What players get

- **Presence.** Everyone in the same territory (QING) sees everyone else in real time. Name tags
  show the wallet's LAU Username **as each player's own game reads it from the chain** (`CHO.GetUserTokenAddress`
  → `LAU.Username()`, else the LAU's `name()`, read-only, Multicall3, cached; `LauNames`, `NetNames`) and always
  the short wallet the signature proved: "enteh · 0x18f6…3111". The name a player's game sends is only a
  claim and is never shown. No LAU, or the read failed: the short wallet alone. Guests show as "guest"
  (nobody can carry a name without signing). A LAU switch re-sends the profile; the others re-read the chain.
- **Inside places.** The arcade, Sunny's Pub and the QING room each have their own room, `<qing>/arcade`,
  `<qing>/pub`, `<qing>/hall` (the place's own coordinates); the Void is one room for everyone, `<VOID>/void`.
  Players in the same place see and hear each other, and "say" chat reaches that place. Leaving a place is not
  a new arrival in the territory.
- **Guests** (not signed in) can see and hear everyone, but can't chat or talk.
- **Sign-in** is automatic once a wallet is connected: the game first shows one line ("Sign in to the game
  server so others see your name: one free signature, not a transaction"), then the wallet asks for a free
  signature of a text that names your server, the host name the
  player connected to, a one-time code and a 10-minute expiry, and says it is not a transaction. If the
  player says no, they stay a guest and are not asked again (a *Sign in* button stays in F2 · Online and in
  the notification panel; the activity feed's header says so). A saved session token (24 h, kept per server
  URL and wallet in `user://net.cfg`) signs in on the next launch with no signature. Another wallet signs in
  again on a new connection. The
  **game builds that text itself** (the server only supplies the code and its time) and signs nothing else,
  so no server can get a player's signature on another text. The server checks it with `ecrecover`, and
  only for its own host name (the WebSocket's `Host`, or `--public-host`): a signature a malicious server
  collected for itself can't be replayed here. After that, a 24-hour session token means no more prompts;
  the game sends it back only to the server address that issued it.
- **Chat**: in the chat bar (T), press Tab to switch to **say**. It is free and not on chain. It shows in
  the chat feed and as a bubble over the speaker.
  You can mute players (F2 → Online & voice), and mutes are kept on that player's computer only.
- **Voice** (hold X): off until the player turns the mic on in F2 → Online & voice. It is
  positional: you hear people within 40 m, from where they stand.
- **Leaderboards**: `Net.top(board, n)` / `Net.submit(board, entry)`. Rows always come from signed-in
  wallets, and each row says how it was checked. Arcade rows are "unverified" (the game reported the
  score). Fair rows are checked against their ticket's receipt, and replayed once the fair games
  expose a replay hook. When the server is unreachable, boards show "—".

- **Game invites and wagers** (§8b): press **N** (or click the bell beside the wallet chip) for the
  notification panel. It lists who is signed in now, so you can invite them to pool or Twenty-One at the arcade of
  the territory you are in, with an optional stake in Ⓐ. The invitee sees the invite there (and a toast) and can
  accept or decline it; it expires after 90 s. Accepting walks both players through the arcade door and sits them
  down at the table. Both confirm the stake at the table (or play without it). Moves go through this server, not
  the chain, and both players' games replay them. A stake is honour-bound: the loser pays the winner with an
  AFFECTION transfer from their own wallet, and the game shows it ✓ paid only when the chain has that Transfer.
  With no server, the panel says that invites need it.
- **"Join me"**: the same list has *Pool*, *21* and *Join me* on every name. *Join me* asks that player to
  come to where you are (your territory, its QING room or its arcade/pub). Same book, limits and 90 s expiry
  as game invites. Accepting opens no game: their own game takes them there through the normal ways in (a
  warp to the QING, then that building's door; never a teleport).
- **The activity feed** (§8c): a few fading lines under the territory card, "enteh came online", "Bob entered
  the arcade", "enteh beat Bob at pool (2 Ⓐ stake, honour-bound)", with each player's face. Its header says who
  is online to invite ("2 others online · 2 to invite (N)"). K folds it; the notification panel keeps the history.

## 5b. Sharing with the site: the pulse node

The website has a companion server, the **pulse node** (entropy-ai-pulse: `pulse-node/`, `docs/PULSE_NODE.md`).
It runs the site's API on a spare laptop with its chain indexes warm, chat history and storage on disk,
and Vercel relaying to it. It reads this server's live numbers for the site:

- Same laptop: start it with `pulse-node.bat --game=ws://127.0.0.1:8787` and give it a second Funnel port:
  `tailscale funnel --bg --https=8443 8788`.
- Separate laptop: `--game=wss://<this laptop>.<tailnet>.ts.net`.

It connects as a guest (it never joins a room, so nobody sees it), sends `C_INFO` every 20 s and
`C_LB_TOP` when the site asks, and pings every 15 s. The site then shows `/api/game-live`: players and
signed-in counts per territory, and the boards. That is one extra connection. Players' game settings
(F2 → Chain → Site API) can point at the node's address as well as at the site.

## 5c. Telegram: bridge Sunny's Pub to the game

The game server can bridge **one Telegram group** (Sunny's Pub) both ways: the group's lines show in the game
(the chat dock's Telegram tab, 0; the TV in Sunny's Pub), signed-in players can write to the group from the chat
bar (T, then Tab to **TG**), and a short digest of real game moments (wins, #1 records, arrivals) goes to the group
at most every 2 minutes, with the download link. Only the server talks to Telegram; players never see the bot's
token. Nothing in it is on chain. With no token set, the bridge is off and the server says nothing about it.

**The token is a password.** Anyone who has it can post as your bot and read your group. Put it only in the
server's environment file below. Never paste it into a chat (not even with Claude), an issue, a commit or a
screenshot. If it ever leaks: @BotFather → `/revoke`, then put the new one in the file.

1. **Make the bot.** In Telegram, open **@BotFather** (the blue tick one) → `/newbot` → a name (e.g. "Sunny's Pub
   game") → a username ending in `bot`. BotFather answers with the token (`123456789:AA…`). Keep that message to
   yourself.
2. **Let it read the group.** Still in @BotFather: `/setprivacy` → pick your bot → **Disable**. (With privacy on, a
   bot only sees commands, so nothing would reach the game.)
3. **Add it to the group.** In Sunny's Pub: group info → Add members → your bot's username. It needs no admin
   rights to read and post. If the group restricts who may post, allow the bot to send messages.
4. **Put the token on the server.** On the box (the Linux service, §1 "On a Linux box"), edit the environment file
   the service reads. It is root-only (mode 600) and outside git; the installer creates and keeps it:
   ```bash
   sudo nano /etc/dysnomia-server/env
   ```
   Find the `# TELEGRAM_BOT_TOKEN=` line the installer added, remove the `# ` and paste the token after `=` (no
   quotes, no spaces). Leave `TELEGRAM_CHAT_ID` empty for now. Save, then rerun the installer, which restarts the
   server and says which state the bridge is in:
   ```bash
   sudo bash /opt/dysnomia/game/tools/install-server-linux.sh
   ```
5. **Find the group's chat id.** Write any line in Sunny's Pub. With a token and no chat id the server relays
   nothing; it only writes the chat ids its bot sees into its log:
   ```bash
   journalctl -u dysnomia-server -n 200 -o cat | grep "sees chat"
   ```
   It prints e.g. `this bot sees chat -1001234567890 (supergroup "Sunny's Pub")`. That number (with its minus sign)
   is the chat id. The token never appears in the log.
6. **Turn it on.** Back in `/etc/dysnomia-server/env`: `TELEGRAM_CHAT_ID=-1001234567890` (yours), save, and run
   the installer again. It prints `Telegram bridge: on`. From now on only that chat is bridged; any other chat the
   bot is added to is ignored.
7. **Moderation.** `TELEGRAM_MUTE_IDS=111,222` in the same file (Telegram user ids) keeps those people's lines out
   of the game; a restart applies it. Without a restart: one id per line in `/var/lib/dysnomia-server/telegram_mute.txt`
   (re-read every minute). Other bots' messages never reach the game. In the game each player can also mute people
   in F2 → Online & voice as before.

Windows laptop (`server.bat`): put `set TELEGRAM_BOT_TOKEN=…` and `set TELEGRAM_CHAT_ID=…` lines in a file
`server.local.bat` next to `server.bat` (git ignores it); `tools/server.sh` reads `server.local.env` the same way
(`TELEGRAM_BOT_TOKEN=…` lines; `chmod 600` it). Steps 1–3 and 5–7 are the same.

**What players get:**
- **Read** (everyone, guests too): the chat dock's **Telegram** tab (press **0**), with each line as
  "<name> · Telegram": a Telegram name is whatever its owner typed, never a LAU, and never gets a ✓. Players who
  wrote from the game show as "<their chain name> (in game)". Photos, stickers and so on show as "[photo]",
  "[sticker 🌻]"; an edit in Telegram replaces the line. The TV on the right wall of Sunny's Pub shows the latest lines.
  Players who join later get the last 50.
- **Write** (signed-in players only): in the chat bar, Tab cycles say → TG → post. The bot posts "<chain name> (in
  game): text" as plain text: links are defanged (`scam[.]com`, `[://]`), `@mentions` and `/commands` are broken
  up, markup is stripped. Limits: one line every 10 s and 30 an hour per wallet, 18 a minute for the whole group.
  A guest who picks TG sees the steps to sign in (one free signature), not a refusal.
- **Moments** (the digest): "enteh beat Bob at pool (2 Ⓐ stake, honour-bound)", "… set a new #1 on Void Lanes:
  4,200 ✓", "… walked into Sunny's Pub at …", one bot post at most every 2 minutes, each arrival at most once per 3 h,
  with "Open the game: https://enterdysnomia.com/download". Never about guests. A player can opt out in F2 →
  Online & voice ("Post my game moments to Sunny's Pub on Telegram", on by default); the server keeps the choice
  per wallet. A wager says "✓ paid" only when an event carries a verified payment; the server itself never does.

## 6. Limits (what protects your laptop)

| Limit | Value |
|---|---|
| connections | 200 total; 32 still handshaking; 8 per IP when not behind a tunnel |
| message size | presence exactly 19 B, ping 5 B, voice 5–700 B, chat ≤ 1 KiB, score ≤ 16 KiB; anything else is a strike |
| message content | every JSON field is read by type (`NetProto.str_of`/`int_of`): a wrong type is ignored or refused, never a script error |
| per connection | 120 messages/s, 48 KB/s (bursts to 96 KB), presence 15/s, voice 60 frames/s, chat 1/s (burst 4), scores 1 every 2 s |
| abuse | 20 malformed messages, or 400 throttled ones in 20 s, closes the connection |
| invites | signed-in wallets only; 1 every 5 s (bursts of 3, answers included); 3 waiting per wallet; 90 s to answer; 2 live games per wallet |
| game moves | signed-in players of that game only; 3/s (burst 8); known moves only (an unknown one is a strike); integer arguments within ±100,000; 600 moves a game; a game with no move for 30 min is abandoned |
| sign-in | 5 tries per connection; 4 signature checks a second for the whole server (each takes ~0.1 s, on a worker thread); more wait their turn (18 at once: all signed in within 3.2 s) |
| timeouts | handshake 15 s, idle 75 s (clients ping every 15 s) |
| Telegram (§5c) | writing: signed-in wallets only, 1 line / 10 s and 30 / hour per wallet, 18 / minute (1 / s) for the group, 8 waiting at most; the digest: 1 post / 2 min |

Behind a tunnel, every connection arrives from `127.0.0.1`, so per-IP caps can't tell players apart.
The per-connection token buckets do that work instead.

## 7. Capacity and bandwidth (laptop on home internet)

These numbers were measured in `tools/net_selftest.gd`. Payload is what the game sends. Add about 90 bytes
of overhead per packet for WebSocket, TLS, TCP/IP and the tunnel.

| Stream | Payload | With overhead |
|---|---|---|
| presence, one player up (10 Hz × 19 B) | ~180 B/s | ~1.1 KB/s ≈ 9 kbit/s |
| presence, down to one player, per other moving player | 200 B/s | +0.9 KB/s per tick header ≈ 10 kbit/s for the first, +1.6 kbit/s each after |
| voice, one talker up (IMA-ADPCM 16 kHz, 50 × 167 B) | 8.3 KB/s | ~13 KB/s ≈ 105 kbit/s |
| voice, to each listener in range | 8.4 KB/s | ~13 KB/s ≈ 105 kbit/s |

Your laptop's **upload** is the limit (home upload is often 10–40 Mbit/s). Some examples:
- 10 players in one territory: each receives about 2.8 KB/s of presence, so the laptop sends
  ≈ 28 KB/s ≈ **0.25 Mbit/s**.
- 30 players in one territory: ≈ 6.7 KB/s each, so ≈ **1.6 Mbit/s**. Presence grows with the
  square of the room size.
- Voice: each talker costs ≈ 0.1 Mbit/s per listener in range. 5 people talking with 6 listeners
  each come to ≈ **3 Mbit/s**.
- CPU: the relay is light. A sign-in costs ~0.1 s on a worker thread.

Measured with `tools/net_load.gd` (2026-11-26, 20 players walking in one territory at 10 Hz, 2 talking): one
listener receives ≈ 20 KB/s (presence 3.3 KB/s, voice 16.9 KB/s), sends 0.2 KB/s; the server sends 386 KB/s
(≈ 3.1 Mbit/s of payload) in all, at ~5–15 % of one core, memory flat (≈ 350 MB, most of it the project's
autoloads); a reconnect storm (all 20 drop and return, three times) leaves no ghost connections.

A typical laptop on 20 Mbit/s upload handles about **50–100 players** spread over territories, with a
handful talking at once. Lower `--voice-radius` or `--room-cap` if the upload saturates.

## 8. Protocol (for developers)

One WebSocket **binary** message is `[type u8][body]`, little-endian. The code is `scripts/net/net_proto.gd`.
- Presence: the client sends `C_STATE` = t u16 (sender ms) + x, y, z int32 cm + yaw u16 + flags u8 + anim u8 (19 B).
  Every 100 ms the server sends `S_STATES` = n u8 + n × (id u16 + the 18 bytes), changed players only.
  Receivers interpolate 150 ms in the past on the sender's clock (`NetInterp`).
- Voice: `C_VOICE` = seq u16 + codec u8 + frame. The server relays `S_VOICE` (id u16 first) to players in the
  same room within the radius. A frame is 20 ms at 16 kHz: IMA-ADPCM, 3-byte header + 160 B
  (`VoiceCodec`).
- Everything else is a small JSON body:
  - `S_WELCOME {id, nonce, issued, server, login, boot, voice_radius, features}` (`login` only for clients older than
    sign-in v2; `boot` is random per server run: a client that sees another one knows the server lost its invites
    and games, which live in memory only)
  - `C_AUTH {wallet, sig, host}` or `{token}`, answered by `S_AUTH {ok, wallet, token}` or `{ok: false,
    reason, nonce, issued}`
  - `C_JOIN {room, name, head, acc, body}`, which brings `S_PEER` / `S_PEER_LEAVE`. A room is a QING address, or
    `<qing>/<place>` (arcade, pub, hall; `<VOID>/void`). A client with a session token sends `C_AUTH {token}` before its
    `C_JOIN`, so the room meets it signed in.
  - `C_CHAT {text}`, relayed as `S_CHAT {id, wallet, name, text, pos}`
  - `C_LB_TOP` / `C_LB_SUBMIT`, answered by `S_LB`
  - `C_INFO {req}`, answered by `S_INFO {req, server, v, uptime_s, connections, players, signed_in, guests,
    rooms: [{room, players}], boards: [{board, rows}]}`. Guests may ask. It returns counts only. The welcome lists
    `"features": ["info"]`.
  - `S_NOTICE {code, text}`
  - The activity feed (§8c, its own message numbers like bumps; the welcome lists `"events"`): `C_PLACE` (41)
    `{place, room}`, `C_CLAIM` (42) `{claim, room}`, and `S_EVENT` (105) `{ev: {k, w, n, …}}`.
  - The Telegram bridge (§8d, its own numbers; the welcome lists `"telegram"` only when it is configured): `C_TG` (50)
    `{text}`, `C_TG_PREFS` (51) `{moments}`, `S_TG` (110) `{line}`, `S_TG_HISTORY` (111) `{lines}`, `S_TG_STATUS` (112).
  - Invites and head-to-head games (the welcome lists `"invites"` in `features`; §8b): `C_ONLINE {req}` →
    `S_ONLINE {req, ok, players: [{wallet, name, room, busy}]}`; `C_INVITE {to, game, stake, room, door}`;
    `C_ANSWER {id, answer: accept|decline|cancel}`; each change → `S_INVITE {invite}` to both wallets; an accept
    → `S_MATCH {match}` (the full record, log included); `C_MOVE {match, op, a}` → `S_MOVE {match, move: {seq, by,
    op, a, t}}` to both; `C_RESULT {match, winner, digest}`; anything refused → `S_REFUSED {what, error}`.
- Sign-in text: `NetProto.login_message(server, host, nonce, issued)` ("Dysnomia game server sign-in",
  server, host, nonce, issued and expiry in UTC, "not a transaction"), built by the client
  (`NetClient.login_for`) and rebuilt by the server. The nonce is new for each attempt and lives 10 minutes.
  `Wallet.sign_message` signs only texts that start with that title or the wallet test's.
- Run the checks: `godot --headless --path . -s res://tools/net_selftest.gd` (its own server; `-- --port=N` if 18787
  is taken), or add `-- --url=ws://127.0.0.1:8787` to test a running server. `tools/net_bot.gd` is a scripted remote
  player (`--wander=R`, `--talk=tone:440|wav:FILE`, `--record=FILE.wav` for voice measurements, `--stats`);
  `tools/net_load.gd -- --url=… --n=20 --talkers=2 --storm=3` is the load check.

## 8b. Invites and head-to-head games (for developers)

**What runs where.** The server keeps the invites (`InviteBook`, pure: `pending → accepted | declined | cancelled |
expired`) and, for each accepted invite, a match record: `{id ("n" + 7 hex), game, players [inviter, invitee],
names, stake, room (the QING), door ("arcade"), created, log, status, result}`. The inviter is player 0 (breaks,
acts first), as in TableBook. The server **only orders and stamps moves** (`seq`, `by` = the player index of the
signed-in wallet that sent it, `op`, integer `a`, `t` = its clock in ms). It checks who may move and which moves a
game takes, but never judges a move and never sees a wallet's money. On sign-in (also by token after a reconnect) it
sends the wallet its invites and games again, so the panel and the table resume.

**Replay on both machines** (`NetMatch`, pure). The same rules the room-line games use:
- pool: `shot [dx, dy, power]` into `EightBall`/`PoolSim` (integer physics), so both tables match to the micrometre;
- Twenty-One: `Duel21`, each card from a block hash. The block is **the first block whose timestamp is at least
  `NetMatch.CARD_MARGIN_S` (2 s) after the server stamped the move** that asks for it: the deal is the move that
  started the game, and a hit is the hit itself. Nobody can know that hash when the move is made, not even the server.
  Both machines read that block from the chain (`BlockClock.first_at`, read-only). This is fair as long as the
  server's clock is right. A clock running more than 2 s slow would let a hitter see the block first;
- common moves: `sit` (the other player gets "X sat down at your table"), `stake_ok` / `stake_no` (the stake is
  "confirm" until both confirm; `stake_no` from either plays it without the stake), `concede`, `claim` (the waiting
  player, after `NetMatch.IDLE_CLAIM_MS` = 10 min without a move).
When the replay ends a game, each machine sends `C_RESULT` with the winner and a fingerprint of its table
(`NetMatch.digest`). If both match, the server marks the game `over` and agreed. If they differ, it marks it
`disputed`, and nobody owes anything.
**A server restart** loses every invite and game (memory only). A client that reconnects and sees another `boot` in the
welcome (or, from an older server, "No such game." for its move) marks its live games abandoned, says so in the panel,
and the table lets the players go; nobody owes anything on them.

**Wagers** (`Wager`, pure; the `Invites` autoload does the reads). There is no escrow. The loser pays with
`TableBook.pay_debt` (`AFFECTION.transfer(winner, stake)` through the write pipeline: simulate, sign, then the
receipt's Transfer log is checked). A wager shows **✓ paid** only once `eth_getLogs` finds an AFFECTION
`Transfer(loser → winner)` at or after the game's end block (the first block at or after the final move's stamp),
allocated oldest debt first (`TableBook.allocate`). With no such log it shows **⚠ unpaid**, and when the read fails it
shows "—". The check repeats every 30 s for 10 minutes, then every 2 minutes, and again after a payment.

**Client side.** The `Invites` autoload holds this session's notifications (in memory, across scene changes),
mirrors invites, replays games and checks wagers. `NotificationPanel` (scripts/ui/notify/) is the bell and the
panel. The HUD and every place add it with one line. `GamesPlace._latest` gives your live game over the server
first, so `PoolSeat`/`CardSeat` draw it like a room-line game; their moves go to `Invites.send_move` instead of
`TableBook.post`.

**Adding a game** (arcade or fair head-to-heads): add its id (e.g. `"fair:striker"`) with its moves to
`InviteBook.GAMES`, its rules to `NetMatch.apply` (e.g. a `score` move checked by `MidwaySim.replay`), and a place
to sit. The server needs nothing else.

**Check it.** `tools/net_selftest.gd` (the invite, move, result and limit cases); `tools/net_bot.gd -- --invite=0x…
--game=pool|cards --stake=N --play` or `--accept --play` (two bots play a whole game; Twenty-One reads real blocks);
`tests/test_invites.gd`. Screenshots with a bot: `screenshot.gd -- --net-url=ws://127.0.0.1:N --net-key=<test key>
--session=<its wallet> --invite=panel|seated|play|result`. The test key only signs the free sign-in, and
`--net-key` works only in debug (editor) builds: a release build ignores it with a warning.

## 8c. The activity feed (for developers)

`scripts/net/net_events.gd` (`NetEvents`, pure: wire, cleaning, lines, the client's gate), `net_activity.gd`
(`NetActivity`, `Net.activity`: the session's lines and history), `scripts/ui/activity_feed.gd` (`ActivityFeed`, the
HUD's stack; HudLayout slot `"activity"`, top-left under the territory card), `lau_names.gd`/`net_names.gd` (names).

**What the server sends** (only facts it knows itself; never anything about the chain):

| `k` | when | to whom |
|---|---|---|
| `online` | a wallet's first connection signs in (not after a drop shorter than 20 s) | signed-in players |
| `offline` | its last connection has been gone 20 s | signed-in players |
| `arrive` | a signed-in player joins a QING room (not again for the same QING within 10 min) | signed-in players |
| `guest` | a guest joins a QING room (no wallet named) | that room |
| `place` | a signed-in player says they walked into `arcade`/`pub`/`hall`/`void` of a QING (`C_PLACE`, once per 2 min each) | that QING's room |
| `match` | an invite to a game was accepted | signed-in players |
| `join` | a "Join me" was accepted (`place` = where) | signed-in players |
| `result` | both machines' replays agreed on a game (never a disputed one); `push` for a draw | signed-in players |
| `record` | a board row took #1 (`verified` as the board checked it) | signed-in players |
| `claim` | a player claims a chain fact (`rocket`: every fair game paid at that QING), once an hour | signed-in players |
| `daily_record` | a replayed daily-challenge run took #1 on today's board `daily:<day>` (§8d; `game`, `score`, `verified`) | signed-in players |

Fields: `w`/`n` (the player's wallet and their game's claimed name), `w2`/`n2` (the other player), `room` (a QING),
`place`, `game`, `stake`, `board`, `score`, `verified`, `push`, `claim`, `t` (server unix time).
**Limits:** per subject (wallet, or "guest|room") 1 event / 5 s after a burst of 4 for the comings and goings
(games, results, records and joins have their own limits upstream); 5 / s for the whole server (burst 20); a
connection may send `C_PLACE`/`C_CLAIM` once every 5 s (burst 4); an unknown place or claim is a strike.

**What a client shows** (`NetActivity`): server events (cleaned again: the server is somebody's laptop), minus
your own comings and goings and places/guests of other QINGs (`NetEvents.relevant`). A `claim` is shown only once
this machine's chain read agrees (`FairProgress.refresh` + `played` for the rocket), else dropped. Plus this
machine's own chain reads (`add_local`, this player only): a 🎪 fair score line arriving in this QING's room once its
ticket receipt and replay check out (`FairBoard.verify`), a player's Hypobar here rising between two reads of the
territory (both blocks), a wager's AFFECTION Transfer log (✓ paid), and your invites sent/accepted. Names are the
chain's (`Net.names`); a line re-renders when a name is read. The gate drops a line repeated within 30 s and keeps the
feed to about one line a second (burst 6); lines fade after 8 s, at most 5 on screen, newest on top; the last 100 stay
for the notification panel's ONLINE ACTIVITY.

**Check it:** `tools/net_selftest.gd` (the events section, the result/record/join checks, the reconnect grace),
`tests/test_net_events.gd`, `tools/net_bot.gd -- --guest | --place=arcade | --claim=rocket | --join-me=0x… | --accept-join
| --start-delay=S --after-peer` (prints every event in the feed's words and each peer's tag as the game draws it).
Screenshot: a local server, bots, then `screenshot.gd -- --net-url=ws://127.0.0.1:N --net-key=<test key>
--session=<its wallet> --activity=4` (waits for 4 lines; debug builds: `--net-lau-of=<bot wallet>=<real wallet>` draws
a bot with a real wallet's LAU name, marked "(test)").

## 8d. The daily challenge (for developers)

One arcade game a UTC day, the same run for everyone (`DailyChallenge`, LEARNINGS §23). Its own message numbers
(`scripts/net/net_daily.gd`, `NetDaily`: C 55–59, S 115–119; 58, 59, 118, 119 are free for it). A client sends them only
when the welcome's `features` lists `"daily"`. The server side is `scripts/net/server/daily_server.gd` (`DailyServer`).

- `C_DAILY_START` (55) `{req, day}` → `S_DAILY_START` (115) `{req, ok, day, game, attempt, left, seed: {state, block,
  hash}, error}`. Signed-in wallets only, `day` must be today (UTC). The server must have read the day's seed block
  itself (`DailySeed`: the first block with timestamp ≥ 00:00 UTC, found by a search on block timestamps); if it can't,
  no scored tries (practice only). **The try is spent here**, not when a score arrives: 3 a day (`DailyBook`), so a
  player can't play many runs and send only the best one.
- `C_DAILY_SUBMIT` (56) `{req, day, attempt, score, log}` → `S_DAILY_RESULT` (116) `{req, ok, day, score, rank, best,
  verified, check, kept, error}`. `log` is the run's input log (`DailyChallenge.encode_log`: one byte of IN_* bits per
  60 Hz step, run-length + base64, ≤ 12,000 characters). The server **replays it** on the day's seed
  (`DailyReplay`, 1,500 steps a frame so a long run never stalls it; ≤ 72,000 steps; a queue of 16, one per wallet) and
  the replay's score is the score. Refused: a claimed score the replay doesn't give ("forged"), a log that runs on past
  the game's end, a try never started or already scored, a run longer than the time since its try started (+3 s), a
  day other than today (yesterday's runs are taken for 10 minutes after midnight). A good run goes on the board
  `daily:<day>` (Leaderboards rows: one per wallet, its best; tie → the earlier run), `verified: true`, `check:
  "verified: replayed on the day's seed (block N, S steps)"`. Taking #1 sends the event `daily_record` (§8c) to every
  signed-in player (the Telegram bridge can forward this kind).
- `C_DAILY_BOARD` (57) `{req, day, n}` → `S_DAILY_BOARD` (117) `{req, ok, day, game, seed, rows (top n ≤ 50), me:
  {signed, rank, score, used, streak, best_streak}, yesterday: {day, game, winner}, left_s}`. Guests may ask.
  `C_LB_TOP` reads `daily:<day>` too; a plain `C_LB_SUBMIT` to a daily board is refused (a verifier).
- **Reset:** the board is keyed by the UTC day, so 00:00 UTC starts a new one (and new tries). Boards older than 7
  days and tries older than 3 are dropped. The book (tries, each wallet's streak of days played) is `daily.json` in the
  server's data folder.
- **Limits:** `C_DAILY_*` one every 2 s per connection (burst 5; over it: "slow down", not a strike); a malformed day is
  a strike.
- **Trust:** the replay proves the score follows from the game's rules on the day's seed and that input log. It can't
  prove a person played it: the seed is public at 00:00 UTC, so a modified client could rehearse it offline or search
  for an input log. The 3-try limit binds honest clients.
- **Check it:** `tools/net_selftest.gd` (the daily block: the welcome, a guest refused, a try, a too-early run, a
  forged score refused by the replay, the true one verified #1, the event, the 4th try refused, a plain score refused,
  `C_LB_TOP`, the rate limit, the reset to tomorrow with yesterday's winner and streak 2; its seed block is a fixture
  so the test needs no network), `tests/test_daily.gd`, `tools/live_daily.gd` (finds today's block on the chain).

### Bumps (players running into each other)

Kept apart from the core types (`scripts/net/net_bump.gd`, numbers chosen away from the sequential ones):
- `C_BUMP` (40) = target id u16 + direction u8 (the push's yaw, 256 steps) + level u8 (5 B). A client sends it
  only when the welcome's `features` lists `"bump"` (the server adds `NetBump.FEATURES`), at most once a second
  per target.
- The server relays `S_BUMP` (104) = from u16 + target u16 + direction u8 + level u8 (7 B) to the room, except the
  sender, after checking both players are in the same room with positions, within 3.5 m of each other (their last
  `C_STATE`), the sender's bucket (1 a second, burst 3; over it is throttling, not a strike) and the target's 1.5 s
  cooldown. The level is capped at a stumble: nobody is knocked down over the network.
- Receivers: the bumped avatar stumbles; the bumped player staggers for at most 0.6 s (`BumpMath.STAGGER_MAX_S`).

## 8d. The Telegram bridge (for developers)

`scripts/net/telegram/`: `net_tg.gd` (`NetTg`, pure: wire, Telegram → game cleaning, labels, game → Telegram
neutralising, token masking, moment lines), `tg_rate.gd` (`TgRate`, sliding windows), `tg_digest.gd` (`TgDigest`,
the batch), `telegram_bridge.gd` (`TelegramBridge`, the server's Node: HTTPRequest long poll + send queue). The
server wires it in `game_server.gd` (`_start_telegram`, `_tg_*`); clients: `NetClient` (`tg_line`, `tg_history`,
`tg_status`, `send_tg`, `send_tg_prefs`), `Net` (`tg_lines`, `telegram_available`, `can_telegram`, `send_telegram`,
`tg_speaker`, `set_tg_moments`, `telegram_changed`), `ChatFeed` (mode `telegram`), `ChatBar`, `ChatFeedPanel` (the
Telegram tab), `PubTgScreen` (the pub's TV), `AccessGates` goal `telegram`.

**Messages** (its own numbers, like bumps and events; the welcome lists `"telegram"` only when the bridge is configured):
- `C_TG` (50) `{text}`: a signed-in player's line. Answered by `S_TG_STATUS` `{what: "send", ok, error, retry_s, code}`
  (`code: "guest"` for a guest) when refused; when Telegram took it, every client gets it back as an `S_TG` line.
- `C_TG_PREFS` (51) `{moments: bool}`: post my moments or not (signed-in only; kept in `<data>/telegram_prefs.json`);
  answered by `S_TG_STATUS {what: "prefs", ok, moments}`. Clients send it after each sign-in.
- `S_TG` (110) `{line}`, `S_TG_HISTORY` (111) `{lines}` (the last 50, right after the welcome), with a line
  `{id (Telegram message_id), src: tg|game|bot, from, text (≤ 280), ts, edited, wallet (game lines)}`. An edit
  re-sends the same `id`; clients replace it (`NetTg.merge`). Codes 52–54 and 113–114 are free for the bridge.

**Server side:** `getUpdates` (POST JSON `{offset, timeout: 25, allowed_updates: [message, edited_message]}`), one
at a time on its own HTTPRequest (never blocks a frame; back-off 5 s → 5 min on errors, 409/401 explained once in the
log); `sendMessage` `{chat_id, text, disable_web_page_preview, link_preview_options}` (no `parse_mode`), one at a time,
paced by the group's limit (18 / 60 s, 1 / s) and Telegram's own 429 `retry_after`. `max_redirects = 0`, and the base
URL and the token are shape-checked before any request (a malformed URL would make the engine print it, token and
all). Every log line goes through `NetTg.mask`. Config: environment only (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`,
`TELEGRAM_API_BASE`, `TELEGRAM_MUTE_IDS`); `GameServer.tg_env` overrides it in tests. A player's line waits up to 4 s
for the chain's name of its wallet (a server-side `LauNames`, read-only); then the short wallet. Moments: `_event`
hands every event that went out to `TelegramBridge.moment` (kinds `result`, `record`, `daily_record`, `join`, `arrive`,
`place`; never one with a guest or an opted-out wallet); `TgDigest` batches them (gather 15 s, gap 2 min, 6 lines,
arrive/place once per 3 h per player, stale after 30 min) and formats them only when it posts (names are read by then).

**Check it:** `godot --headless --path . -s res://tools/tg_selftest.gd` (its own servers and a mock Bot API,
`tools/tg_mock_api.gd`, on 127.0.0.1; ~75 checks: off when unset, discovery, the wrong chat, edits, placeholders,
cleaning, mutes and bots, guests refused, names, neutralising, plain text, per-wallet / group / 429 limits, opt-out,
the digest, history for late joiners, malformed input, and the token in no log line, message or Telegram text);
`tests/test_telegram.gd` (the pure rules). By hand / screenshots: `tools/tg_mock.gd` (a made-up group on
127.0.0.1:18790 with a test token), a server started with `TELEGRAM_BOT_TOKEN=<that test token>
TELEGRAM_CHAT_ID=-1001234567890 TELEGRAM_API_BASE=http://127.0.0.1:18790`, `tools/net_bot.gd -- --tg-say="…"`,
then `screenshot.gd -- --net-url=… [--net-key=<test key>] --tg=dock|history|bar|tv` (the pub: `--scene=res://scenes/places/sunny_pub.tscn --view=tv`).
