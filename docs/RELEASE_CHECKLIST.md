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
- [ ] Version: the git tag (`v1.2.3`) is the version. `release.yml` writes it into `application/config/version`
      (absent in dev runs, so dev builds show "dev" and never check for updates). Strict `x.y.z` only.
- [ ] Windows icon: `release.yml` converts `icon.svg` to a 16/32/48/256 `.ico`
      (`installer/windows/make_icon.sh`, needs `librsvg2-bin` + `imagemagick`) and sets it on the Windows preset
      only, for the exe and the installer. The committed preset keeps `application/icon=""` so local exports
      work without it. `icon.svg` is still Godot's stock logo: replace it to give the game its own icon.

## Windows installer

`installer/windows/dysnomia.nsi` (NSIS 3, Modern UI 2, Unicode), built in CI on Linux after the Windows export:
`makensis -DVERSION=<V> -DSRC_DIR=<build/windows> -DICON=<ico> -DOUT_FILE=dist/Dysnomia-<V>-windows-setup.exe`.
Locally: `sudo apt-get install -y nsis`, then the same line (any dummy `Dysnomia.exe`/`Dysnomia.pck` proves it compiles).

- Per user, no admin prompt: `%LOCALAPPDATA%\Programs\Dysnomia` (`Dysnomia.exe`, `Dysnomia.pck`, `uninstall.exe`).
  Start Menu shortcut always; Desktop shortcut is a checkbox (on for a fresh install, kept as it was on an upgrade);
  "Launch Dysnomia" on the finish page.
- Add/Remove Programs under `HKCU\…\Uninstall\Dysnomia`: DisplayName, DisplayVersion, Publisher "Dysnomia",
  DisplayIcon, UninstallString, QuietUninstallString, InstallLocation, EstimatedSize, NoModify/NoRepair.
- Upgrade = run the newer installer: it finds the old folder from InstallLocation and replaces the two files.
  The uninstaller deletes exactly those files, its shortcuts and its key (no recursive delete).
- The player's data (`user://` = `%APPDATA%\Godot\app_userdata\Dysnomia`) is never touched by install,
  upgrade or uninstall.
- The workflow fails if the Windows export holds anything but `Dysnomia.exe` + `Dysnomia.pck` (the installer
  would miss it: add it to the `.nsi`).
- **Unsigned:** SmartScreen shows "Windows protected your PC" on first run (More info → Run anyway). Expected
  until release signing ([`SECURITY_AUDIT.md`](SECURITY_AUDIT.md)). Say so on the download page.

`latest.json` lists every file with its kind; the installer entry is
`{"platform":"windows","kind":"installer","name":"Dysnomia-<V>-windows-setup.exe","size":…,"sha256":…,"url":"<base>/releases/<V>/Dysnomia-<V>-windows-setup.exe"}`
and the zips carry `"kind":"zip"`. `SHA256SUMS` covers the zips and the installer.

## Update notice

The front door reads `GET https://enterdysnomia.com/api/download-manifest` once per launch (`UpdateCheck`:
HTTPS, 8 s timeout, 64 KB cap, no redirects, quiet on failure; skipped in dev builds and when the site
accelerator is off). When its strict `x.y.z` `version` is newer than this build's, a strip at the top right says
"Dysnomia x.y.z is out · Download · Later". Download opens the constant `https://enterdysnomia.com/download`,
never a URL from the manifest. Later hides it for that version (`settings.cfg` `[update] dismissed`).
The build's version shows in the front door's status strip (BUILD) and at the top of F2 settings.

- [ ] After publishing, start the previous release: the notice names the new version, Download opens the
      download page, Later hides it across a restart, and the next version shows it again.
- [ ] Preview: `screenshot.gd -- --update=9.9.9` (labelled PREVIEW).

## After building

- [ ] Each binary starts at the front door with the default RPC and no settings file.
- [ ] Windows installer on a clean Windows user: installs without an admin prompt, Start Menu (and Desktop if
      ticked) shortcuts start the game, it is listed in Apps & features with the version; installing the next
      version over it keeps settings and the Desktop choice; uninstalling leaves `%APPDATA%\Godot\app_userdata\Dysnomia`.
- [ ] The wallet relay starts and opens the browser page. The page carries the session token, and a
      page without it is refused.
- [ ] Publish SHA-256 checksums next to the binaries, and reproduce one build from the tag.
- [ ] Where the files live (`release.yml` input `host`): `r2` (the Cloudflare bucket) or `github` (a GitHub
      Release `v<version>` on this repo, made by the workflow; it refuses while the repo is private). `latest.json`
      always goes to R2, where the site's `/api/download-manifest` reads it; that API accepts links only under the
      bucket's `releases/<v>/` or this repo's `releases/download/v<v>/`, and the download page shows "Read the code"
      only for a GitHub-hosted release.
- [ ] Run the security checks in [`WALLET_TESTS.md`](WALLET_TESTS.md) (rebinding Host, framing, exact approvals,
      the sign-in text) with a real wallet. See [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) for what is still open
      (release signing).
- [ ] Bumping Godot: update `GODOT_SHA512` / `TEMPLATES_SHA512` in `release.yml` from the release's
      `SHA512-SUMS.txt`, and re-pin any action by its commit SHA.
