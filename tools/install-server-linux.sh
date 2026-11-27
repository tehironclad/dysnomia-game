#!/usr/bin/env bash
# The game server as a service on a Linux box (docs/SERVER.md, "On a Linux
# box"): the pBank box (pls-portfolio deploy/box), including one in WSL2 on a
# Windows PC. Run it as the box's admin user, through sudo:
#
#   sudo bash install-server-linux.sh                  # install, or update and restart
#   sudo BRANCH=<branch> NAME=<server name> bash install-server-linux.sh
#
# Safe to run again: each step checks first. A re-run is also how it updates.
#
#   1. the `dysnomia-server` system user (never a login), /opt/dysnomia
#   2. a read-only deploy key for it (this repo is private): it prints the
#      PUBLIC key, waits while you add it in GitHub, checks it with git ls-remote
#   3. the checkout /opt/dysnomia/game, on BRANCH (master)
#   4. Godot 4.6.1 (headless; checked against the release's SHA512-SUMS.txt)
#   5. the project's import (the first one takes a while)
#   6. dysnomia-server.service, enabled and (re)started on 127.0.0.1:8787;
#      if the Entropy pulse node runs here, it is pointed at this server.
#      Its environment file /etc/dysnomia-server/env (SERVER_ARGS, and the Telegram
#      bridge's TELEGRAM_* settings) is kept across runs, root-only (mode 600).
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-tehironclad/dysnomia-game}"
REPO_URL="git@github.com:${REPO_SLUG}.git"
BRANCH="${BRANCH:-master}"
NAME="${NAME:-dysnomia}"
GODOT_VERSION=4.6.1
GODOT_ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
APP_USER=dysnomia-server
APP_HOME=/opt/dysnomia
GAME_DIR="$APP_HOME/game"
GODOT_DIR="$APP_HOME/godot"
ETC_DIR=/etc/dysnomia-server
UNIT=/etc/systemd/system/dysnomia-server.service
# GitHub's published Ed25519 host key (docs.github.com, "GitHub's SSH key fingerprints").
GITHUB_HOST_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'

step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\n!!  %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
as_app() { runuser -u "$APP_USER" -- env HOME="$APP_HOME" GIT_SSH_COMMAND="ssh -i $APP_HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=$APP_HOME/.ssh/known_hosts" "$@"; }

[ "$(id -u)" -eq 0 ] || die "run it through sudo: sudo bash $0"
[ "$(uname -m)" = x86_64 ] || die "this installs the x86_64 Godot; this machine is $(uname -m)"
for c in git ssh-keygen runuser curl sha512sum python3 systemctl; do command -v "$c" >/dev/null || die "$c is missing"; done
[[ "$NAME" =~ ^[A-Za-z0-9._-]{1,40}$ ]] || die "NAME: letters, digits, . _ - (up to 40)"

step "1/6  The $APP_USER user"
# Only ever a system account: if a person's login has this name (uid 1000+,
# a shell, sudo), running the server as it would hand the server their rights.
if id "$APP_USER" >/dev/null 2>&1 && [ "$(id -u "$APP_USER")" -ge 1000 ]; then
  die "'$APP_USER' is a login account here (uid $(id -u "$APP_USER")), not a service account; this script won't run the server as it"
fi
if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "$APP_HOME" --no-create-home --shell /usr/sbin/nologin "$APP_USER"
  note "created"
else
  note "exists"
fi
install -d -m 0750 -o "$APP_USER" -g "$APP_USER" "$APP_HOME" "$GODOT_DIR"
install -d -m 0700 -o "$APP_USER" -g "$APP_USER" "$APP_HOME/.ssh"
install -d -m 0755 "$ETC_DIR"

step "2/6  Read-only deploy key"
if [ ! -s "$APP_HOME/.ssh/id_ed25519" ]; then
  runuser -u "$APP_USER" -- ssh-keygen -q -t ed25519 -N '' -C "dysnomia-server@$(hostname)" -f "$APP_HOME/.ssh/id_ed25519"
  note "made a new key"
fi
printf '%s\n' "$GITHUB_HOST_KEY" >"$APP_HOME/.ssh/known_hosts"
chown "$APP_USER:$APP_USER" "$APP_HOME/.ssh/known_hosts"
until as_app git ls-remote "$REPO_URL" HEAD >/dev/null 2>&1; do
  printf '\n    Add this PUBLIC key in GitHub → %s → Settings → Deploy keys → Add deploy key\n' "$REPO_SLUG"
  printf '    (title: game server on %s; leave "Allow write access" OFF):\n\n' "$(hostname)"
  cat "$APP_HOME/.ssh/id_ed25519.pub"
  [ -t 0 ] || die "no terminal to wait on: add the key above, then run this again"
  read -r -p $'\n    Press Enter once it is added (q to stop): ' ans
  [ "$ans" = q ] && exit 0
done
note "the key can read $REPO_SLUG"

step "3/6  Checkout $GAME_DIR ($BRANCH)"
if [ ! -d "$GAME_DIR/.git" ]; then
  note "cloning (about 330 MB of assets)"
  as_app git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_URL" "$GAME_DIR"
  changed=yes
else
  as_app git -C "$GAME_DIR" fetch --quiet --depth 1 origin "$BRANCH"
  before="$(as_app git -C "$GAME_DIR" rev-parse HEAD)"
  as_app git -C "$GAME_DIR" checkout --quiet -B "$BRANCH" FETCH_HEAD
  after="$(as_app git -C "$GAME_DIR" rev-parse HEAD)"
  if [ "$before" = "$after" ]; then note "already at ${after:0:7}"; changed=no; else note "updated ${before:0:7} → ${after:0:7}"; changed=yes; fi
fi
[ -f "$GAME_DIR/scenes/net/game_server.tscn" ] || die "$GAME_DIR has no scenes/net/game_server.tscn on $BRANCH"

step "4/6  Godot $GODOT_VERSION (headless)"
if [ -x "$GODOT_DIR/godot" ] && "$GODOT_DIR/godot" --headless --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
  note "already installed"
else
  tmp="$(mktemp -d /var/tmp/godot.XXXXXX)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$GODOT_ZIP" "$GODOT_URL/$GODOT_ZIP"
  if curl -fsSL -o "$tmp/SHA512-SUMS.txt" "$GODOT_URL/SHA512-SUMS.txt"; then
    want="$(awk -v f="$GODOT_ZIP" '$2 == f || $2 == "*" f {print $1}' "$tmp/SHA512-SUMS.txt")"
    have="$(sha512sum "$tmp/$GODOT_ZIP" | cut -d' ' -f1)"
    if [ -z "$want" ] || [ "$want" != "$have" ]; then die "the Godot download does not match the release's SHA512-SUMS.txt"; fi
    note "SHA-512 matches the release's SHA512-SUMS.txt"
  else
    die "could not fetch the release's SHA512-SUMS.txt to check the download"
  fi
  python3 -m zipfile -e "$tmp/$GODOT_ZIP" "$tmp/x"
  install -m 0755 -o "$APP_USER" -g "$APP_USER" "$tmp/x/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT_DIR/godot"
  rm -rf "$tmp"; trap - EXIT
  note "installed $GODOT_DIR/godot"
  changed=yes
fi

step "5/6  Import the project"
if [ "$changed" = yes ] || [ ! -d "$GAME_DIR/.godot/imported" ]; then
  note "importing (the first time takes several minutes)"
  if ! as_app timeout 3600 "$GODOT_DIR/godot" --headless --path "$GAME_DIR" --import >/var/tmp/dysnomia-import.log 2>&1; then
    tail -n 20 /var/tmp/dysnomia-import.log >&2
    die "the import failed (full log: /var/tmp/dysnomia-import.log)"
  fi
  note "imported"
else
  note "nothing changed; skipped"
fi

step "6/6  dysnomia-server.service"
if [ ! -f "$ETC_DIR/env" ]; then
  printf '# Extra arguments for the game server (docs/SERVER.md, the options table).\nSERVER_ARGS=--name=%s\n' "$NAME" >"$ETC_DIR/env"
fi
# The Telegram bridge (docs/SERVER.md 5c) reads its settings from this same file. It is kept
# (never overwritten), outside git, readable by root only: systemd reads it before the server
# starts, and the service account itself can't. Placeholders are added once, commented out.
if ! grep -q 'TELEGRAM_BOT_TOKEN' "$ETC_DIR/env"; then
  printf '\n# Telegram bridge (docs/SERVER.md 5c). Fill these in here (never in git, never in a chat),\n# remove the "# ", then run this script again.\n# TELEGRAM_BOT_TOKEN=\n# TELEGRAM_CHAT_ID=\n# TELEGRAM_MUTE_IDS=\n' >>"$ETC_DIR/env"
fi
chown root:root "$ETC_DIR/env"
chmod 0600 "$ETC_DIR/env"
if grep -q '^TELEGRAM_BOT_TOKEN=..*' "$ETC_DIR/env"; then
  if grep -q '^TELEGRAM_CHAT_ID=..*' "$ETC_DIR/env"; then tg=on; else tg=discover; fi
else
  tg=off
fi
if ! cmp -s "$GAME_DIR/tools/dysnomia-server.service" "$UNIT"; then
  install -m 0644 "$GAME_DIR/tools/dysnomia-server.service" "$UNIT"
  systemctl daemon-reload
fi
systemctl enable --quiet dysnomia-server
systemctl restart dysnomia-server
up=no
for _ in $(seq 1 30); do
  if journalctl -u dysnomia-server -n 50 -o cat --no-pager 2>/dev/null | grep -q "listening on ws://127.0.0.1:8787"; then up=yes; break; fi
  sleep 2
done
if [ "$up" = yes ]; then note "listening on ws://127.0.0.1:8787"
else warn "no 'listening' line yet: journalctl -u dysnomia-server -n 50"; fi
# The Telegram bridge: say which state it is in (never the token itself).
case "$tg" in
  on)
    sleep 2
    if journalctl -u dysnomia-server -n 80 -o cat --no-pager 2>/dev/null | grep -q "Telegram bridge on"; then
      note "Telegram bridge: on (token and chat id set in $ETC_DIR/env)"
    else
      warn "Telegram bridge: set in $ETC_DIR/env but not on yet: journalctl -u dysnomia-server -n 50 | grep -i telegram"
    fi ;;
  discover)
    note "Telegram bridge: token set, no TELEGRAM_CHAT_ID yet. Write a line in your group, then:"
    note "  journalctl -u dysnomia-server -n 200 -o cat | grep 'sees chat'" ;;
  *) note "Telegram bridge: off (docs/SERVER.md 5c to turn it on)" ;;
esac

# The Entropy pulse node on the same box reads this server's live counts.
if [ -f /etc/pulse-node/env ] && ! grep -q '^PULSE_NODE_GAME_URL=' /etc/pulse-node/env; then
  sed -i '/^# PULSE_NODE_GAME_URL=/d' /etc/pulse-node/env
  printf 'PULSE_NODE_GAME_URL=ws://127.0.0.1:8787\n' >>/etc/pulse-node/env
  systemctl restart pulse-node 2>/dev/null || true
  note "the pulse node here now reads this server (PULSE_NODE_GAME_URL)"
fi

cat <<EOF

Done. The game server runs on 127.0.0.1:8787; its files are in /var/lib/dysnomia-server.
Next:
  1. Publish it: the box's install.sh stage g, with --game-host <name> (e.g. game.yourdomain).
  2. In the Entropy site's Vercel project: DYSNOMIA_GAME_SERVER_URL = wss://<that name>, then redeploy.
  3. Update later: run this script again (it re-imports only when something changed).
EOF
