# Audit of v1 and the v2 re-plan

This document records why the repository was rewritten. It covers what v1
(`setup.sh`, `restrict.sh`, `unrestrict.sh`, `reset.sh`,
`discover-dependencies.sh`, `cmanager`, `install.sh`) did, what was wrong with
it, and what v2 does instead.

**Goal (unchanged):** on contest day a lab PC must let contestants reach
**only the contest site(s)**, with **no AI assistant of any kind** (web
chatbots, AI features built into browsers or editors, local LLMs), and must be
reset cleanly between contestants.

---

## 1. Findings, by severity

### Critical: the restrictions could be bypassed

| # | Finding | Why it matters |
|---|---------|----------------|
| C1 | **Allowlist by IP address.** Domains were resolved to IPs and those IPs were allowed in iptables. | Contest sites sit behind shared CDNs (Cloudflare, AWS, Google). Allowing a Cloudflare IP allows **every** site on that IP, including `chatgpt.com`, which is also on Cloudflare. A contestant can use `curl --resolve chatgpt.com:443:<allowed-ip>` or Chrome's `--host-resolver-rules` to reach it. |
| C2 | `discover-dependencies.sh` **always added `www.google.com`, `gstatic.com`** and others. | Allowing Google's front-end IPs opens Google Search (with AI Overviews) and, through shared IPs, Gemini. |
| C3 | **Unrestricted DNS** to the system resolver. | DNS tunnels work, and so do "LLM-over-DNS" services such as `dig @ch.at "question" TXT` via a resolver. |
| C4 | **No protection against AI in the browser or editor.** | Chrome's Gemini, "Help me write" and on-device model, Firefox's AI chatbot sidebar, VS Code Copilot Chat, and AI editors (Cursor, Windsurf, Zed) or local LLMs (ollama, LM Studio) were not addressed at all. Local LLMs need no network. |
| C5 | **The user argument was ignored.** `cmanager` exported `RESTRICT_USER` / `RESET_USER`, but the scripts read `$1`. | `cmanager restrict contestant` silently restricted `participant`. |
| C6 | **`reset` removed all restrictions** (it contained a full copy of unrestrict). | Resetting between contestants during a contest silently re-opened the Internet. |
| C7 | **`reset` leaked the previous contestant's data.** It used `rm -rf ~/*` (dot-files survive) and `rsync` without `--delete`. | `.bash_history`, browser profiles (`.mozilla`, `.config/google-chrome`) and saved logins survived. It then wiped `~/.config` and `~/.local/share`, which also destroyed the clean baseline it had just restored. |

### High: blocking that didn't work

| # | Finding |
|---|---------|
| H1 | The USB udev rule (`OWNER="root"` on the interface) does nothing. Only the module blacklist worked, and `uas` was not blocked. |
| H2 | Phones (MTP/PTP) are not USB mass storage, so file transfer from a phone was fully possible. DVD drives and SD readers were not handled. |
| H3 | Polkit rules were written only in JavaScript format. **Ubuntu 22.04 uses polkit 0.105, which ignores `.rules` files**, so the mount block did nothing there. |
| H4 | Firewall rules allowed `ESTABLISHED` traffic first, so connections opened before `restrict` stayed open. |
| H5 | IPs rotate, which is why v1 needed a 30-minute re-resolve timer. Between refreshes, sites broke (a new CDN IP) or stayed open (stale IPs). |
| H6 | `unrestrict` used `read -p` under `set -e`, so it failed without a terminal (for example over SSH scripts). It also ran `systemctl mask` on unit files it was about to delete. |
| H7 | `setup.sh` **deleted and re-created the user on every run** (losing files) and never ran `apt-get update`. It also installed unrelated or Ubuntu-only software (`hollywood`, `neofetch`, a GRUB-customizer PPA that breaks on Debian). It also disabled `apt-daily.service` instead of the timers that start it, so updates still ran. |
| H8 | `install.sh` overwrote the admin's allowlist on every reinstall. |

### Medium: usability and correctness

- `status` ran `iptables` as a non-root user and reported "inactive" even when restrictions were active.
- `remove DOMAIN` put the raw domain into a `sed` regular expression.
- Discovery used `tcpdump` + reverse DNS (which gives useless CDN hostnames) plus hard-coded tracker domains (`snap.licdn.com`).
- No verification step: nobody could prove a machine was contest-ready.
- No tests, no linting, and documentation that described features that didn't exist ("Squid + iptables").

---

## 2. The re-plan (v2 design decisions)

| Problem | v2 answer |
|---------|-----------|
| IP allowlists leak through CDNs (C1, C2, H5) | **Domain-based allowlist in a local proxy** (Squid on `127.0.0.1`). The contest user's firewall allows **only** loopback, so the proxy is the only way out. The proxy decides by host name, never by IP. |
| SNI/domain fronting through an allowed CONNECT | Squid **peeks at the TLS ClientHello** and checks the SNI name too, without decrypting anything. `CONNECT allowed.com` + SNI `chatgpt.com` is cut off. |
| DNS tunnels (C3) | The contest user gets **no DNS at all** (port 53/853 rejected, systemd-resolved's D-Bus and Varlink closed to that user). The proxy resolves names for them. |
| AI (C4) | Five independent layers. (1) Default-deny network. (2) An AI denylist that wins over any allowlist mistake. (3) Browser **enterprise policies** turn off Gemini, Help-me-write, the on-device model, DevTools AI, the Firefox AI chatbot and extensions. (4) VS Code `chat.disableAIFeatures` + an extension allowlist. (5) **Execution of AI editors / local LLM runtimes is denied** to the contest user via POSIX ACLs. |
| Wrong user (C5) | Every command takes an explicit user or `CONTEST_USER` from `contest.conf`, and the value is validated. |
| Reset (C6, C7) | `reset` only restores the home directory from a snapshot with `rsync --delete` and cleans `/tmp`, cron and at jobs. **Contest mode is untouched.** |
| Devices (H1–H3) | `install … /bin/false` for `usb_storage`, `uas` and `sr_mod`. A udev rule de-authorises USB interfaces of class 08 (storage) and 06 (MTP/PTP) plus MTP devices, so keyboards, mice and USB network adapters keep working. Polkit rules are written in **both** formats (JS + `.pkla`). Bluetooth is turned off. |
| Persistence | Firewall loaded by `contest-firewall.service` **before any login**. A proxy service, plus a **guard timer** that repairs a missing firewall table or a stopped proxy within a minute. |
| Firewall tech | **nftables**, one private table `inet contest_env` (IPv4 + IPv6), loaded atomically and removed in one command. It never touches ufw, Docker or other rules. |
| Proof | `cmanager verify` runs real connections **as the contest user** and prints PASS/FAIL. |
| Allowlist UX | Curated **site profiles** (`@codeforces`, `@atcoder`, `@vjudge`, …). `cmanager add` refuses AI domains and warns about risky ones (search, code hosting, messaging). Changes apply live with `reload`. |
| Discovery | Headless Chrome **net-log**, which gives the exact hosts a page loads, classified as allowed / NEW / risky / AI. Also `cmanager denied`, which shows what the proxy refused during a mock run. Nothing is auto-allowed. |
| Upgrades | `install.sh` removes the v1 services, iptables chains and udev/polkit files, and **merges the v1 allowlist** in. Admin-edited config is never overwritten. |
| Quality | `shellcheck`-clean, 53 unit tests (nft/squid validation when run as root), and GitHub Actions CI. |

## 3. File mapping v1 → v2

| v1 | v2 |
|----|----|
| `cmanager` | `bin/cmanager` (dispatcher) + `lib/*.sh` (one module per concern) |
| `setup.sh` | `lib/setup.sh` (`cmanager setup`) |
| `restrict.sh` + helper `update-contest-whitelist` | `lib/contest.sh`, `lib/firewall.sh`, `lib/proxy.sh`, `lib/lockdown.sh`, `lib/browser.sh` |
| `unrestrict.sh` | `cmanager unrestrict` (same modules, reversed) |
| `reset.sh` | `lib/reset.sh` (`cmanager snapshot`, `cmanager reset`) |
| `discover-dependencies.sh` | `lib/discover.sh` (`cmanager discover`, `cmanager denied`) |
| `whitelist.txt` | `config/whitelist.txt` + `config/sites/*.txt` |
| n/a | `config/ai-denylist.txt`, `config/risky-domains.txt`, `config/blocked-apps.txt` |
| n/a | `systemd/*`, `tests/run.sh`, `Makefile`, `.github/workflows/ci.yml`, `docs/*` |

## 4. Known limits (be honest about them)

- **Physical cheating** (phones, printed material, talking) is out of scope.
  Proctors are still needed.
- **Other local accounts** (admin) are not restricted. Keep their passwords
  away from contestants, and disable guest login.
- **Encrypted HTTP-level domain fronting** (SNI = an allowed site, `Host:` = a
  different site on the same CDN) cannot be seen without decrypting TLS. It
  needs custom tooling, and the major CDNs reject it. v2 does not decrypt
  traffic, on purpose.
- An allowed contest site that **itself** embeds an AI feature or lets users
  host arbitrary content is allowed, because it is on the list. Keep the
  allowlist minimal.
- AI apps installed as **snaps** cannot be blocked per-user. `status` and
  `restrict` warn about them, so remove them.
