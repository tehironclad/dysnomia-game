# Security

Dysnomia handles wallet signing, so we take reports seriously.

**What the game never does:** ask for a seed phrase or private key, approve more than the exact
amount a move needs, sign text it didn't write itself, or take a payee address from chat, the
server or a web page. Every write is simulated first and checked against the mined receipt.
The full audit is [`docs/SECURITY_AUDIT.md`](docs/SECURITY_AUDIT.md) (rules in `docs/LEARNINGS.md` §22).

**Found something?** Please don't post exploit details in public chats or issues first. Open a
GitHub security advisory on this repository (Security → Report a vulnerability) with steps to
reproduce, and we'll answer there.

**Check your download:** builds are made by GitHub Actions (`.github/workflows/release.yml`) from a
commit in this repository. Each release lists its commit and SHA-256 on
https://enterdysnomia.com/download — only download from there.
