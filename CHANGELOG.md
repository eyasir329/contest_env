# Changelog

## 2.0.0 — full rewrite

Why: the v1 audit found that its restrictions could be bypassed (see
[docs/AUDIT.md](docs/AUDIT.md)).

### Added
- Domain-based allowlist enforced by a local Squid proxy with TLS SNI checks (no decryption).
- Per-user nftables firewall: the contest account can only reach the proxy and allowlisted judge IPs; no DNS.
- AI denylist that overrides the allowlist; browser policies disabling built-in AI (Chrome, Edge, Brave, Chromium, Firefox); VS Code AI off; execution blocks for AI editors and local LLM runtimes.
- Blocking of USB storage, phones (MTP/PTP), optical drives, mounting, and Bluetooth; polkit rules in both JS and `.pkla` formats.
- Site profiles (`@codeforces`, `@atcoder`, `@vjudge`, …) and live `add` / `remove` / `reload`.
- `verify` (real PASS/FAIL tests as the contest user), `status`, `denied`, `discover`, `logs`.
- Snapshot-based `reset` that no longer touches contest mode.
- Boot persistence and a self-healing guard timer.
- Automatic migration from v1 in `install.sh`; `uninstall.sh`.
- Tests, shellcheck, GitHub Actions CI.
- Documentation: getting started, how it works, commands, examples, platforms/logins, contest-day runbook, configuration, troubleshooting, FAQ; `examples/` folder with allowlists, a custom profile and a lab rollout script.

### Removed
- IP-based allowlisting and its 30-minute re-resolve timer.
- The tcpdump-based dependency discovery, which auto-allowed `www.google.com` and others.
- Unrelated packages from setup (`hollywood`, `neofetch`, GRUB customizer PPA).

### Changed
- Repository renamed from `NEUPC-PC-SETUP` to `contest_env`.
