# Configuration reference

All configuration lives in `/etc/contest-env/`. The repository's `config/`
folder holds the defaults that `install.sh` copies there.

## `contest.conf`

| Key | Default | Meaning |
|-----|---------|---------|
| `CONTEST_USER` | `participant` | Account used by contestants; the default for every command |
| `PROXY_PORT` | `3128` | Local proxy port (listens on 127.0.0.1 only) |
| `SNI_ENFORCE` | `auto` | Check the TLS SNI name too: `auto` (when Squid has OpenSSL), `yes` (require it), `no` |
| `DENY_DNS` | `1` | No DNS for the contest user (the proxy resolves). Turn off only for an on-site judge reached by host name that the proxy cannot resolve |
| `BLOCK_USB_STORAGE` | `1` | usb_storage/uas modules refused; USB class 08 interfaces de-authorised |
| `BLOCK_MTP` | `1` | Phones/cameras (MTP/PTP) de-authorised |
| `BLOCK_OPTICAL_AND_MOUNTS` | `1` | sr_mod refused; the contest user may not mount, change the network, or install packages (polkit) |
| `BLOCK_BLUETOOTH` | `1` | Bluetooth rfkill-blocked and stopped |
| `BLOCK_AI_APPS` | `1` | Deny execution of everything matched by `blocked-apps.txt` |
| `INSTALL_CHROME`, `INSTALL_FIREFOX`, `INSTALL_VSCODE`, `INSTALL_SUBLIME`, `INSTALL_CODEBLOCKS`, `INSTALL_GEANY` | `1` | What `setup` installs |
| `INSTALL_OFFLINE_DOCS` | `1` | `cppreference-doc-en-html` and `python3-doc` (read offline, no network needed) |
| `EXTRA_PACKAGES` | empty | More apt packages for `setup` |
| `VSCODE_EXTENSIONS` | cpptools, python, java | Installed for the contest user, and the only ones VS Code allows |
| `DISABLE_AUTO_UPDATES` | `1` | Stop apt timers, unattended-upgrades, and hold snap refreshes |

After changing it: `sudo cmanager restrict` (re-applies everything).

## `whitelist.txt`: the allowlist

```text
@codeforces          # a site profile from sites/codeforces.txt
atcoder.jp           # a domain: also allows every sub-domain (img.atcoder.jp, ...)
https://toph.co/p/x  # URLs are fine: reduced to toph.co
192.168.10.5         # an IP: reachable directly (on-site DOMjudge on any port)
10.10.0.0/24         # an IP range
```

- Keep it **short**: allow only the contest in progress.
- `sudo cmanager list` shows the effective result, `sudo cmanager reload` applies edits.
- `sudo cmanager add …` / `remove …` edit the file and apply it immediately.

## `sites/*.txt`: site profiles

Shipped: `codeforces`, `atcoder`, `codechef`, `vjudge`, `toph`, `lightoj`,
`hackerrank`, `hackerearth`, `leetcode`, `cses`, `spoj`, `uva`, `kattis`,
`docs` (cppreference, Python and Java docs), and `common` (captcha, fonts
and vetted JS CDNs, included by most profiles).

Same syntax as the allowlist, and profiles can include other profiles. Add
your own under a new name (for example `sites/iupc2026.txt`); upgrades only
refresh the shipped files.

## `ai-denylist.txt`: always blocked

AI chatbots, AI APIs and AI coding services. They are blocked **even when the
allowlist would allow them** (for example `google.com` still blocks
`gemini.google.com`). Put your own additions in `ai-denylist.local.txt`,
which upgrades keep.

## `risky-domains.txt`: `add` refuses these without `--force`

Search engines, code hosting, Q&A sites, messaging, pastebins and generic
user-content CDNs. They are not blocked on their own (default-deny already
does that); this list only protects against allowing them by accident.
`risky-domains.local.txt` is for your additions.

## `blocked-apps.txt`: programs the contest user may not run

One entry per line: a command name (looked up in `PATH`) or an absolute
path/glob such as `/opt/Cursor`. A directory entry blocks everything inside
it. While contest mode is on, each existing match gets the ACL
`user:<contest-user>:---`. Other users are unaffected. `blocked-apps.local.txt`
is for your additions.

## Environment variables

| Variable | Used by | Meaning |
|----------|---------|---------|
| `CONTEST_PASSWORD` | `setup` | Password for a newly created contest user (otherwise you are prompted) |
| `CM_ASSUME_YES=1` | all | Never prompt |
| `NO_COLOR=1` | all | Plain output |
