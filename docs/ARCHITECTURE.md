# Architecture and threat model

## Threat model

The contestant is a strong competitive programmer who is logged into the
contest account and has a terminal. They know tools such as `curl`, Chrome
command-line flags, DNS and VS Code. We assume they may try to:

1. open an AI chatbot or search engine in the browser,
2. use AI built into the browser (Gemini, Firefox AI sidebar, on-device models) or into the editor (Copilot, AI editors),
3. run a local LLM that needs no network,
4. reach a forbidden site through an allowed one (shared CDN IP, SNI/domain fronting, DNS tunnelling, a VPN, or another proxy),
5. bring data in or out (USB stick, phone via MTP, DVD, SD card, Bluetooth),
6. find leftovers from the previous contestant, or leave something for the next one.

Out of scope: physical attacks, root compromise (no sudo, no admin
password), and cheating that happens away from the machine.

## The layers

```
             contest user's processes (browser, curl, IDE, ...)
                               │
                               ▼
┌───────────────────────────────────────────────────────────────────────┐
│ nftables  table inet contest_env   (meta skuid = contest user only)    │
│   tcp/udp 53, 853  ────────────────────────────► REJECT (no DNS)       │
│   oif lo           ────────────────────────────► ACCEPT                │
│   allowlisted IPs (on-site judge) ─────────────► ACCEPT                │
│   everything else  ────────────────────────────► REJECT + log          │
└───────────────────────────────────────────────────────────────────────┘
                               │ 127.0.0.1:3128
                               ▼
┌───────────────────────────────────────────────────────────────────────┐
│ Squid  (runs as "proxy", which is not firewalled)                      │
│   1. AI denylist (dstdomain)       → refuse   (wins over the allowlist) │
│   2. not on allowlist (dstdomain)  → refuse   (before any DNS lookup)   │
│   3. resolves to loopback/link-local → refuse (DNS rebinding)           │
│   4. TLS: peek at ClientHello, SNI must be allowlisted and not AI       │
│      → splice (never decrypted) or terminate                            │
└───────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
                      the contest site only
```

Around the network path:

| Layer | Mechanism | Stops |
|-------|-----------|-------|
| Browser policy (baseline) | Chrome/Chromium/Brave/Edge `managed/*.json`, Firefox `policies.json` | Gemini, Help-me-write, Tab organiser, DevTools AI, the on-device model download, Firefox AI chatbot/sidebar/link previews, **all extensions**, DoH, QUIC, ECH, sync/sign-in |
| Browser policy (contest) | Fixed proxy `127.0.0.1:3128` (locked), no search provider | A browser that goes around the proxy (it would fail closed anyway) |
| Editor | VS Code user settings: `chat.disableAIFeatures`, Copilot off, `extensions.allowed` | Copilot Chat / agent UI, AI extensions |
| Program ACLs | `setfacl -m u:<user>:---` on AI editors, local LLM runtimes, AI CLIs and remote-desktop tools (`blocked-apps.txt`) | Offline AI (ollama, LM Studio, llamafile, …), Cursor, Windsurf, Zed, AnyDesk, … |
| Resolver | nft blocks :53; D-Bus policy denies `org.freedesktop.resolve1`; ACL on resolved's Varlink socket | DNS tunnels, "LLM over DNS" |
| Devices | modprobe `install … /bin/false` (usb_storage, uas, sr_mod); udev de-authorises USB interfaces of class 08/06 and MTP; polkit denies udisks/NetworkManager/PackageKit/Flatpak; Bluetooth off | USB sticks, phones, DVDs, SD cards, adding a VPN or installing software |
| Account | Removed from sudo/adm/plugdev/cdrom/disk/dialout/lxd/docker/…; no linger | Privilege escalation, raw device access, background jobs |
| Reset | `rsync --delete` from a snapshot + clean `/tmp`, `/var/tmp`, `/dev/shm`, cron, at | Leftovers between contestants |

### Why a proxy instead of IP rules

Contest sites are behind CDNs whose IP addresses are shared by millions of
domains. Allowing `codeforces.com`'s address can allow `chatgpt.com` too. A
proxy sees the *name* the client asks for. With TLS peeking it also sees the
name inside the TLS handshake, so the decision is per-domain.

Because the contest user can do no DNS and can only talk to loopback, a
browser that ignores the proxy settings simply gets no connection. **The
design fails closed.**

### Why no TLS interception

Squid could decrypt ("bump") HTTPS and filter by URL. That needs a custom CA
installed in every browser, it breaks certificate pinning, and it exposes
contestants' passwords to the proxy. Peek-and-splice gets domain-level
control without any of that.

### Persistence and self-healing

| Unit | When | Does |
|------|------|------|
| `contest-firewall.service` | boot, before `network-pre.target` and before any login | `nft -f /var/lib/contest-env/firewall.nft` |
| `contest-proxy.service` | boot, before user sessions | Squid with `/var/lib/contest-env/squid/squid.conf` |
| `contest-guard.timer` → `.service` | every 60 s | Re-loads a missing nft table, restarts a dead proxy, re-applies the resolver ACL, keeps Bluetooth off |

All three have `ConditionPathExists=/var/lib/contest-env/restricted`, so they
do nothing when contest mode is off, even if left enabled.

## Files on a machine

| Path | Content |
|------|---------|
| `/usr/local/lib/contest-env/` | code (`bin/cmanager`, `lib/*.sh`, units, docs) |
| `/usr/local/bin/cmanager` | symlink to the command |
| `/etc/contest-env/contest.conf` | settings (yours) |
| `/etc/contest-env/whitelist.txt` | allowlist (yours) |
| `/etc/contest-env/sites/*.txt` | site profiles (shipped; add your own with new names) |
| `/etc/contest-env/{ai-denylist,risky-domains,blocked-apps}.txt` | shipped lists (refreshed on upgrade) |
| `/etc/contest-env/*.local.txt` | your additions to those lists (kept) |
| `/var/lib/contest-env/restricted` | contest-mode marker (user + since) |
| `/var/lib/contest-env/firewall.nft` | generated ruleset |
| `/var/lib/contest-env/squid/` | generated proxy config + ACL files |
| `/var/lib/contest-env/snapshots/<user>/` | clean home snapshot |
| `/var/lib/contest-env/app-acl.list` | paths we ACL-blocked (for exact undo) |
| `/var/log/contest-env/proxy/access.log` | every proxy decision (with SNI) |
| `/var/log/contest-env/cmanager.log` | audit log: who ran what, when |
| `/etc/modprobe.d/contest-env.conf`, `/etc/udev/rules.d/99-contest-env-usb.rules`, `/etc/polkit-1/rules.d/05-contest-env.rules`, `/etc/polkit-1/localauthority/50-local.d/contest-env.pkla`, `/etc/dbus-1/system.d/contest-env.conf` | exist **only while contest mode is on** |
| `/etc/opt/chrome/policies/managed/contest-env-*.json` (and the Chromium/Brave/Edge equivalents), `/etc/firefox/policies/policies.json` | browser policies |

## Code layout

| File | Responsibility |
|------|----------------|
| `bin/cmanager` | argument parsing and dispatch |
| `lib/common.sh` | logging, config, allowlist parsing/normalisation, state |
| `lib/firewall.sh` | nftables ruleset render/apply/remove |
| `lib/proxy.sh` | Squid config render, service control, denied-log parser |
| `lib/lockdown.sh` | USB/MTP/optical/polkit, Bluetooth, resolver side-channels, program ACLs, groups |
| `lib/browser.sh` | Chromium-family + Firefox policies |
| `lib/editor.sh` | VS Code settings + extensions |
| `lib/setup.sh` | packages, account, profile |
| `lib/reset.sh` | snapshot + reset |
| `lib/contest.sh` | restrict / unrestrict / reload / add / remove / list / sites / guard |
| `lib/status.sh` | status + verify |
| `lib/discover.sh` | headless-Chrome discovery + denied report |
| `lib/legacy.sh` | removal of v1 |
