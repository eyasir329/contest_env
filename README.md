# NEUPC Contest Environment (`cmanager`)

> Netrokona University Programming Club: lab PC setup for programming contests.
> _Originally based on [MDPC](https://github.com/ShazidMashrafi/MDPC); rewritten as v2. See [docs/AUDIT.md](docs/AUDIT.md) for why._

`cmanager` turns a Debian/Ubuntu lab PC into a contest machine. The contest
account:

- **can open only the contest site(s)** you list. Everything else, including
  Google, GitHub, Stack Overflow and messaging, is unreachable;
- **cannot use any AI**: web chatbots, AI built into Chrome, Edge, Brave or
  Firefox, VS Code Copilot, AI editors (Cursor, Windsurf, Zed, …) and local
  LLMs (ollama, LM Studio, …);
- **cannot move data** with USB sticks, phones (MTP), DVDs, SD cards or Bluetooth;
- gets a **clean home directory** for every contestant;

and all of this **survives reboots, repairs itself, and can be verified** with one command.

```text
$ sudo cmanager verify
== Verifying contest mode as 'participant' ==
  PASS  services: firewall table loaded
  PASS  services: proxy running
  PASS  allowed site reachable via proxy (https://codeforces.com)
  PASS  other site blocked (https://example.com)
  PASS  search blocked (https://www.google.com)
  PASS  AI blocked (https://chatgpt.com)
  PASS  AI blocked (https://gemini.google.com)
  PASS  AI blocked (https://claude.ai)
  PASS  direct connection blocked (https://1.1.1.1)
  PASS  public DNS blocked (8.8.8.8:53)
  PASS  local DNS blocked (getent hosts example.com)
  PASS  USB storage driver refused

✔ All checks passed — this machine is contest-ready.
```

---

## How it works (one paragraph)

The contest user's traffic is filtered by a private **nftables** table. The
only destination it allows is `127.0.0.1`, plus any on-site judge IPs you
list. The contest user has no DNS. On `127.0.0.1:3128` runs a **Squid
allowlist proxy** that decides by **domain name**, never by IP (so shared CDN
addresses can't be abused). It also checks the **TLS SNI** of each HTTPS
connection without decrypting it (so an allowed host can't be used as a
front for a forbidden one). An **AI denylist** always wins over the
allowlist. Browsers and VS Code get **enterprise policies** that turn off
their AI features and extensions, and AI apps and local LLM runtimes get an
**execute-deny ACL** for the contest user. Details and the threat model are in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Debian 12+ or Ubuntu 22.04+ (desktop), with systemd
- root (sudo) access, and Internet access while running `setup`

## Quick start

```bash
git clone https://github.com/eyasir329/contest_env.git
cd contest_env
sudo ./install.sh                       # installs the `cmanager` command

sudo cmanager setup                     # toolchains, editors, browsers, docs,
                                        # contest account "participant", snapshot
sudo cmanager add @codeforces           # choose what is allowed (see: cmanager sites)
sudo cmanager restrict                  # contest mode ON
sudo cmanager verify                    # prove it

# between contestants
sudo cmanager reset --force             # clean home, contest mode stays ON
# after the contest
sudo cmanager unrestrict                # everything back to normal
```

For the full lab procedure (mock run, rollout to many PCs, contest-day
fixes), see **[docs/CONTEST-DAY.md](docs/CONTEST-DAY.md)**.

## Commands

| Command | What it does |
|---------|--------------|
| `setup [USER] [--skip-packages]` | Install compilers (gcc/g++, clang, python3, pypy3, JDK), debuggers, editors (VS Code, Sublime, Code::Blocks, Geany, vim/neovim), browsers (Chrome, Firefox) and offline docs (cppreference, Python). Create the contest account without admin groups, turn off AI in browsers and VS Code, stop background updates, and take the clean-home snapshot. |
| `snapshot [USER]` | Re-take the clean-home snapshot (after customising the desktop). |
| `restrict [USER]` | **Contest mode ON**: proxy, firewall, no DNS, USB/phone/DVD/Bluetooth blocked, AI programs blocked, browsers locked to the proxy. |
| `verify` | Real connection tests as the contest user, with PASS/FAIL. |
| `unrestrict [USER]` | **Contest mode OFF**: every change reverted. |
| `reset [USER] [--force]` | Restore the home directory from the snapshot and clean `/tmp`, cron and at jobs. `--force` logs the user out first. Contest mode is not changed. |
| `list` | The effective allowlist, with profiles expanded. |
| `sites` | Available site profiles and which are enabled. |
| `add [--force] ENTRY…` | Add a domain, IP, CIDR or `@profile`. Applied live. Refuses AI domains, and refuses risky domains unless `--force` is given. |
| `remove ENTRY…` | Remove an entry. Applied live. |
| `reload` | Apply hand edits of `whitelist.txt`. |
| `denied [N]` | Hosts the proxy refused, to find a missing CDN during a mock run. |
| `discover URL…` | Load pages in headless Chrome and list every host they use: allowed, NEW, risky or AI. |
| `status [USER]` | What is active right now. |
| `logs` | Audit log of cmanager actions. |

`USER` defaults to `CONTEST_USER` in `/etc/contest-env/contest.conf` (`participant`).

## The allowlist

`/etc/contest-env/whitelist.txt`:

```text
@codeforces          # curated profile: codeforces.com, codeforces.org, captcha, fonts, MathJax CDN
@vjudge
192.168.10.5         # on-site DOMjudge server (IP, any port)
```

Shipped profiles: `@codeforces @atcoder @codechef @vjudge @toph @lightoj
@hackerrank @hackerearth @leetcode @cses @spoj @uva @kattis @docs @common`.
A domain line allows that domain and all of its sub-domains. See
[docs/CONFIGURATION.md](docs/CONFIGURATION.md) for every option and list.

## What is blocked, and how

| Threat | Countermeasure |
|--------|----------------|
| Any non-allowlisted website | nftables default-deny for the contest user; the proxy's domain allowlist |
| AI chatbots and APIs | Default-deny, plus an `ai-denylist.txt` (100+ domains) that beats the allowlist |
| CDN IP sharing / SNI fronting | Decisions by name; the TLS SNI must be allowlisted too (peek, never decrypt) |
| DNS tunnels / "LLM over DNS" | No DNS for the contest user (port 53/853, plus the resolved D-Bus and Varlink paths) |
| Browser built-in AI | Chrome/Edge/Brave/Chromium and Firefox policies (Gemini, Help me write, on-device model, AI sidebar, DevTools AI, …), all extensions blocked |
| Editor AI | VS Code `chat.disableAIFeatures`, Copilot off, extension allowlist |
| AI editors and local LLMs | Execute-deny ACL for the contest user on `blocked-apps.txt` matches (Cursor, Windsurf, Zed, ollama, LM Studio, llamafile, GPT4All, AI CLIs, AnyDesk/TeamViewer, …) |
| VPN, proxy tools, tethering | Useless: every packet from the contest user is checked by the firewall, whatever the interface |
| USB sticks, phones, DVDs, SD cards | Kernel modules refused, USB interfaces de-authorised, mounting denied by polkit (both polkit formats) |
| Bluetooth transfers | rfkill + service stopped |
| Leftovers between contestants | `rsync --delete` from a snapshot, plus `/tmp`, cron and at cleanup |
| Someone turning it off | Only root can; units start before login; the guard timer repairs it every 60 s |

Known limits (physical cheating, other local accounts, encrypted HTTP-level
fronting) are listed honestly in [docs/AUDIT.md](docs/AUDIT.md#4-known-limits-be-honest-about-them).

## Repository layout

```text
bin/cmanager              command dispatcher
lib/*.sh                  one module per concern (firewall, proxy, lockdown, browser, …)
config/                   defaults copied to /etc/contest-env on install
  contest.conf            settings
  whitelist.txt           allowlist
  sites/*.txt             site profiles
  ai-denylist.txt         always-blocked AI services
  risky-domains.txt       domains `add` refuses without --force
  blocked-apps.txt        programs the contest user may not run
systemd/                  firewall, proxy and guard units
tests/run.sh              unit tests (make test)
docs/                     audit, architecture, contest-day runbook, configuration, troubleshooting
install.sh / uninstall.sh
```

## Development

```bash
make lint      # shellcheck
make test      # unit tests; run as root to also validate nft rules and squid config
```

CI (GitHub Actions) runs both on every push.

## Upgrading from v1

Run `sudo ./install.sh`. It removes the old `contest-restrict-*` services,
the iptables `CONTEST_*` chains and the old udev/polkit files, and merges
`/usr/local/etc/contest-restriction/whitelist.txt` into the new allowlist.
Old home backups in `/opt/*_backup` are left for you to delete after
`cmanager setup` / `cmanager snapshot`.

## License and credits

Built for NEUPC contests. The original idea comes from
[MDPC](https://github.com/ShazidMashrafi/MDPC).
