# Command reference

Every command is run as an admin with `sudo`. The general form is:

```text
sudo cmanager <command> [options] [arguments]
```

- `USER` is optional everywhere. It defaults to `CONTEST_USER` in
  `/etc/contest-env/contest.conf` (`participant` out of the box).
- Global options: `--force` / `-f`, `--yes` / `-y` (never ask questions),
  `--user NAME` / `-u NAME`, `--help`.
- Environment variables: `CONTEST_PASSWORD=…` (password for a new account
  created by `setup`), `NO_COLOR=1` (plain output), `CM_ASSUME_YES=1`.
- Exit code: `0` = success, non-zero = something failed (the message says what).
  Scripts can rely on this. For example, `verify` exits `1` if any check fails.

Contents: [setup](#setup) · [snapshot](#snapshot) · [restrict](#restrict) ·
[verify](#verify-alias-check) · [unrestrict](#unrestrict) · [reset](#reset) · [list](#list) ·
[sites](#sites) · [add](#add) · [remove](#remove) · [reload](#reload) ·
[denied](#denied) · [discover](#discover) · [status](#status) · [logs](#logs)

---

## Preparation

### `setup`

```text
sudo cmanager setup [USER] [--skip-packages]
```

One-time preparation of a PC. It needs Internet access, and contest mode must be off. It is safe to run again: nothing is deleted, and missing parts are added.

What it does, in order:

1. `apt-get update`, then installs the tools contest mode needs: `nftables`, `squid-openssl`, `acl`, `rsync`, `curl`, `openssl`.
2. Compilers and debuggers: `build-essential gcc g++ gdb make python3 default-jdk`, plus (if available) `clang pypy3 valgrind`.
3. Editors: `vim neovim nano xterm`, plus Code::Blocks and Geany (switch off in `contest.conf`).
4. Offline docs: `cppreference-doc-en-html`, `python3-doc`.
5. Firefox, Google Chrome (amd64 only), VS Code and Sublime Text (each can be switched off in `contest.conf`).
6. Stops apt/snap automatic updates.
7. Creates `USER` if it doesn't exist and asks for its password (or uses `CONTEST_PASSWORD`). Removes it from privileged groups (sudo, cdrom, plugdev, …).
8. VS Code settings for `USER`: AI off, extension allowlist. Installs the VS Code extensions from `VSCODE_EXTENSIONS`.
9. Browser policies: AI features and extensions off (for Chrome, Chromium, Brave, Edge and Firefox).
10. Takes the snapshot (see `snapshot`).

`--skip-packages` skips steps 1–5. Use it to re-create only the account, profile, policies and snapshot.

Example, unattended:

```bash
sudo CONTEST_PASSWORD='neupc2026' cmanager setup
```

### `snapshot`

```text
sudo cmanager snapshot [USER]
```

Saves the current home folder of `USER` as the clean state that `reset` restores. Run it after you have customised the contestant desktop (and logged that account out).

```text
✔ Snapshot of /home/participant saved (2.1M) → /var/lib/contest-env/snapshots/participant
```

### `discover`

```text
sudo cmanager discover URL [URL...]
```

Opens each URL in a hidden Chrome/Chromium window, records every host the page contacts, and labels each one. Best run with contest mode **off**, before the contest.

Illustrative output (the exact hosts depend on the site that day):

```text
$ sudo cmanager discover https://codeforces.com/problemset/problem/4/A
→ Loading https://codeforces.com/problemset/problem/4/A (up to 45 s)

== Hosts contacted ==
  allowed   codeforces.com
  allowed   codeforces.org
  allowed   cdnjs.cloudflare.com
  NEW       mc.yandex.ru  → sudo cmanager add mc.yandex.ru
  risky     www.google.com  (search/code/social - think twice)
  AI        gemini.google.com  (always blocked)
```

Nothing is added automatically. `NEW` hosts are often analytics or trackers that the page works fine without. Add a host only if the page is broken without it.

---

## Contest mode

### `restrict`

```text
sudo cmanager restrict [USER]
```

Turns **contest mode on** for `USER`. Running it again re-applies everything, for example after editing `contest.conf`. It refuses to run if contest mode is already on for a *different* user.

Order of work: proxy → firewall → DNS block → device blocks → Bluetooth → AI program blocks → group clean-up → browser proxy policy → boot services. Full sample output: [GETTING-STARTED.md, step 5](GETTING-STARTED.md#step-5-turn-contest-mode-on).

> If the contestant is logged in while you run it, their open connections break. Ask them to restart the browser.

### `verify` (alias: `check`)

```text
sudo cmanager verify
```

Runs real tests **as the contest user**. Exits with `1` if any check fails, so it works in scripts.

| Check | Expected |
|-------|----------|
| firewall table loaded, proxy running | PASS = running |
| first allowlisted site (e.g. codeforces.com) via proxy | reachable |
| `example.com`, `www.google.com` via proxy | blocked |
| `chatgpt.com`, `gemini.google.com`, `claude.ai` via proxy | blocked |
| `https://1.1.1.1` without proxy | blocked (firewall) |
| TCP to `8.8.8.8:53` | blocked (no DNS) |
| `getent hosts example.com` | fails (no name resolution) |
| USB storage driver | refused |

### `unrestrict`

```text
sudo cmanager unrestrict [USER]
```

Turns **contest mode off** and undoes everything `restrict` did (see the table in [HOW-IT-WORKS.md](HOW-IT-WORKS.md#what-restrict-changes-and-unrestrict-undoes)). It never asks questions, so it is safe in scripts. Your allowlist and snapshots are kept.

### `reset`

```text
sudo cmanager reset [USER] [--force]
```

Makes the home folder identical to the snapshot, and deletes the user's files in `/tmp`, `/var/tmp` and `/dev/shm`, plus their cron/at jobs. **Contest mode is not changed.**

- Without `--force` it refuses while the user is logged in.
- With `--force` it logs the user out first (unsaved work is lost).

```text
$ sudo cmanager reset --force
→ Logging 'participant' out
→ Restoring /home/participant from snapshot (2026-09-24 16:08:49)
→ Removing the user's files outside home
✔ 'participant' reset to the clean snapshot
✔ Contest mode is still ACTIVE for 'participant'
```

---

## The allowlist

### `list`

Shows what is allowed right now, with profiles expanded and duplicates removed.

```text
$ sudo cmanager list
Allowlist file: /etc/contest-env/whitelist.txt

Effective domains (each includes its sub-domains):
  ajax.googleapis.com
  cdn.mathjax.org
  cdnjs.cloudflare.com
  challenges.cloudflare.com
  code.jquery.com
  codeforces.com
  codeforces.org
  fonts.googleapis.com
  fonts.gstatic.com

Direct IPs / ranges:
  192.168.10.5

Always blocked: 104 AI domains (/etc/contest-env/ai-denylist.txt)
```

### `sites`

Lists the site profiles in `/etc/contest-env/sites/` and marks the enabled ones with `[on]`.

### `add`

```text
sudo cmanager add [--force] ENTRY [ENTRY...]
```

`ENTRY` can be:

| Form | Example | Meaning |
|------|---------|---------|
| profile | `@atcoder` | enable a site profile (un-comments `#@atcoder` if present) |
| domain | `toph.co` | that domain and all sub-domains |
| URL | `https://toph.co/c/some-contest` | reduced to `toph.co` |
| IP | `192.168.10.5` | direct access to that machine, any port |
| range | `10.10.0.0/24` | a whole subnet |

Safety rules:

```text
$ sudo cmanager add chatgpt.com
✘ chatgpt.com is an AI service (chatgpt.com) — it is always blocked

$ sudo cmanager add github.com
✘ github.com is on the risky list (github.com: search/code-sharing/messaging). Use --force if you are sure.

$ sudo cmanager add google.com --force
! google.com contains AI service gemini.google.com — that part stays blocked
! Adding risky domain google.com (--force)
```

When contest mode is on, the change is applied **immediately** (no restart and no dropped connections).

### `remove`

```text
sudo cmanager remove ENTRY [ENTRY...]
```

Removes a line from `whitelist.txt`. Profiles are commented out (`#@atcoder`), so `add @atcoder` brings them back. It only removes lines that are literally in `whitelist.txt`: a domain that comes from a profile can't be removed on its own. Remove the profile, or make your own profile.

### `reload`

Re-reads `whitelist.txt` after you edited it by hand and applies it (proxy, firewall and browser bypass list). With contest mode off, it only checks that the file is valid.

### `denied`

```text
sudo cmanager denied [N]
```

Lists the hosts the proxy refused in the last `N` log lines (default 5000), most frequent first. This is the fastest way to find what a broken contest page needs.

```text
== Refused by the proxy (most recent 5000 log lines) ==
     7  example.com  (not allowed)
     6  www.google.com  (not allowed)
     6  chatgpt.com  (not allowed)
     1  chatgpt.com  (TLS name mismatch via codeforces.com)
```

`TLS name mismatch` means someone tried the "tunnel to an allowed site, talk to another" trick (see [HOW-IT-WORKS.md](HOW-IT-WORKS.md#4-the-trick-tunnel-to-an-allowed-site-but-talk-to-chatgpt)).

---

## Information

### `status`

```text
$ sudo cmanager status
== contest-env status ==
  Contest mode           ON for 'participant' (since 2026-09-24 16:11:52)
  Contest user           participant (uid 1001)
  Firewall (nftables)    active
  Proxy (squid)          active on 127.0.0.1:3128, 10 domain rule(s), SNI check on
  Guard timer            active
  USB storage            blocked
  Phones (MTP/PTP)       blocked
  Mounting / optical     blocked
  DNS for user           blocked
  AI programs blocked    2 path(s)
  Browser policies       chrome(ai-off,proxy) firefox(ai-off,proxy)
  Home snapshot          2026-09-24 16:08:49

Allowlist: 11 effective entries (cmanager list)
```

Warnings appear below the table: for example, the user is still in a privileged group, `nscd` is running, or an AI app is installed as a snap (which can't be blocked per user). Without `sudo` it shows only the first two lines.

### `logs`

```text
sudo cmanager logs [N]
```

The last `N` (default 50) entries of the audit log, showing who ran which command and when:

```text
2026-09-24 16:08:49  admin    setup user=participant
2026-09-24 16:11:52  admin    restrict user=participant
2026-09-24 16:12:30  admin    add @atcoder
```

### `version`, `help`

Print the version / the built-in help.

---

## Files the commands read and write

| Path | Edited by you? | Purpose |
|------|----------------|---------|
| `/etc/contest-env/contest.conf` | yes | settings ([CONFIGURATION.md](CONFIGURATION.md)) |
| `/etc/contest-env/whitelist.txt` | yes (or via `add`/`remove`) | the allowlist |
| `/etc/contest-env/sites/*.txt` | add your own files | site profiles |
| `/etc/contest-env/*.local.txt` | yes | your additions to the AI / risky / blocked-apps lists |
| `/var/lib/contest-env/` | no | generated rules, snapshots, state |
| `/var/log/contest-env/proxy/access.log` | no | every proxy decision |
| `/var/log/contest-env/cmanager.log` | no | audit log |
