## What changed

## How I checked it
- [ ] `GODOT=godot tools/check.sh` passes
- [ ] Online play touched? `tools/net_selftest.gd` passes
- [ ] Screenshot or live read-only tool output (if it changes what players see or read)

## Rules (CONTRIBUTING.md)
- [ ] No made-up chain data (failed reads show "—"; numbers carry source + block)
- [ ] Writes simulate → sign → verify receipt → re-read; exact approvals only
- [ ] No hard-coded keys or price literals; assets CC0/OFL and credited
