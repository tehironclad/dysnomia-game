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

**Firewall.** The server listens on `127.0.0.1` only, so nothing on your network can reach it directly. If
Windows asks whether Godot may use the network, you can click *Cancel*: the tunnel connects from
inside your laptop.

**Files** (Windows): `%APPDATA%\Godot\app_userdata\Dysnomia\server\`
- `server.log`: connections, sign-ins, chat lines, scores, and a stats line every 5 minutes. It rotates
  at 5 MB (`server.log.1`).
- `leaderboards.json`: the boards. Back it up if you care about them.
- `tokens.json`: sign-in sessions (valid 24 h), so players don't sign again on every reconnect.

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
  show the LAU Username and the short wallet; guests show as "guest".
- **Guests** (not signed in) can see and hear everyone, but can't chat or talk.
- **Sign-in** happens once. The first time a player with a connected wallet chats, or clicks *Sign in
  with wallet*, the wallet asks for a free signature of a text that names your server and a one-time
  code. The server checks it with `ecrecover`. After that, a 24-hour session token means no more
  prompts.
- **Chat**: in the chat bar (T), press Tab to switch to **say**. It is free and not on chain. It shows in
  the chat feed and as a bubble over the speaker.
  You can mute players (F2 → Online & voice), and mutes are kept on that player's computer only.
- **Voice** (hold X): off until the player turns the mic on in F2 → Online & voice. It is
  positional: you hear people within 40 m, from where they stand.
- **Leaderboards**: `Net.top(board, n)` / `Net.submit(board, entry)`. Rows always come from signed-in
  wallets, and each row says how it was checked. Arcade rows are "unverified" (the game reported the
  score). Fair rows are checked against their ticket's receipt, and replayed once the fair games
  expose a replay hook. When the server is unreachable, boards show "—".

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

## 6. Limits (what protects your laptop)

| Limit | Value |
|---|---|
| connections | 200 total; 32 still handshaking; 8 per IP when not behind a tunnel |
| message size | presence 19 B, voice ≤ 700 B, chat ≤ 1 KiB, score ≤ 16 KiB; anything else is refused |
| per connection | 120 messages/s, 48 KB/s (bursts to 96 KB), presence 15/s, voice 60 frames/s, chat 1/s (burst 4), scores 1 every 2 s |
| abuse | 20 malformed messages, or 400 throttled ones in 20 s, closes the connection |
| sign-in | 5 tries per connection; 4 signature checks a second for the whole server (each takes ~0.1 s, on a worker thread) |
| timeouts | handshake 15 s, idle 75 s (clients ping every 15 s) |

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
  - `S_WELCOME {id, nonce, server, login}`
  - `C_AUTH {wallet, sig}` or `{token}`, answered by `S_AUTH {ok, wallet, token}`
  - `C_JOIN {room, name, head, acc, body}`, which brings `S_PEER` / `S_PEER_LEAVE`
  - `C_CHAT {text}`, relayed as `S_CHAT {id, wallet, name, text, pos}`
  - `C_LB_TOP` / `C_LB_SUBMIT`, answered by `S_LB`
  - `C_INFO {req}`, answered by `S_INFO {req, server, v, uptime_s, connections, players, signed_in, guests,
    rooms: [{room, players}], boards: [{board, rows}]}`. Guests may ask. It returns counts only. The welcome lists
    `"features": ["info"]`.
  - `S_NOTICE {code, text}`
- Sign-in text: `NetProto.login_message(server, nonce)`. The nonce is new for each attempt.
- Run the checks: `godot --headless --path . -s res://tools/net_selftest.gd` (its own server), or add
  `-- --url=ws://127.0.0.1:8787` to test a running server. `tools/net_bot.gd` is a scripted remote player.
