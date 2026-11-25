# Release checklist

## Before tagging

- [ ] `GODOT=… tools/check.sh` passes: everything imports, every script compiles, all shaders compile,
      all tests pass.
- [ ] `tools/live_smoke.gd` reaches the chain. Note the deployer nonce: if it is not 712, check World
      watch's evidence before release.
- [ ] `tools/live_readiness.gd` agrees with the site's readiness for a few known wallets.
- [ ] `tools/boot_territory.gd` prints the HUD card and no errors.
- [ ] Refresh the snapshot with `tools/update_snapshot.gd`, and `players.json` from the site, then commit.
- [ ] Regenerate `deployer_creates.json` if the deployer's nonce has moved near the table's end (`to`).
- [ ] Run the manual wallet checklist ([`WALLET_TESTS.md`](WALLET_TESTS.md)) with a fresh wallet and an
      onboarded one.
- [ ] Take screenshots of the front door, the Field, a territory (aerial, hud), and each move panel.

## Export presets

- [ ] Use release templates only. Turn off "Export With Debug", and don't ship debug presets.
- [ ] Platforms: Windows x86_64, macOS universal, Linux x86_64.
- [ ] Include `assets/web/wallet.html` and `assets/data/*.json`: add `*.json, *.html` to the
      non-resource export filter.
- [ ] No `user://` data is shipped. Caches (terrain, score) are rebuilt on the player's machine.
- [ ] Version: set `application/config/version` in `project.godot`, and use the same value for the git tag.

## After building

- [ ] Each binary starts at the front door with the default RPC and no settings file.
- [ ] The wallet relay starts and opens the browser page. The page carries the session token, and a
      page without it is refused.
- [ ] Publish SHA-256 checksums next to the binaries, and reproduce one build from the tag.
- [ ] Run the security checks in [`WALLET_TESTS.md`](WALLET_TESTS.md) (rebinding Host, framing, exact approvals,
      the sign-in text) with a real wallet. See [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) for what is still open
      (release signing).
- [ ] Bumping Godot: update `GODOT_SHA512` / `TEMPLATES_SHA512` in `release.yml` from the release's
      `SHA512-SUMS.txt`, and re-pin any action by its commit SHA.
