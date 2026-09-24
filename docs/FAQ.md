# FAQ

### General

**What exactly is this?**
A command-line tool (`cmanager`) plus configuration that turns a Debian/Ubuntu
PC into a locked-down programming-contest machine: only the contest site is
reachable, no AI, no USB, and a clean account for every contestant. See the
[README](../README.md).

**Which Linux versions are supported?**
Ubuntu 22.04 / 24.04 and Debian 12+, desktop editions with systemd. Other
Debian-based systems (Linux Mint, Pop!_OS) will probably work but are not
tested.

**Windows? macOS?**
No. The blocking relies on Linux features (nftables, polkit, udev).

**Does it need Internet during the contest?**
Only if the contest is on an Internet judge. For an on-site DOMjudge, the lab
network alone is enough ([example 2](EXAMPLES.md#example-2--an-on-site-contest-with-domjudge-on-the-lan)).

**Is it free to use in my own university / club?**
Yes. It's shared on GitHub for other clubs to use. Please check with the
repository owner about a formal license if you plan to redistribute it.

### Security

**Can a contestant break out of it?**
Not without root access. Everything is enforced by root-owned rules; the
contest account has no `sudo`; and a guard repairs the rules every minute.
The things that still matter are physical: keep the admin password secret,
set a BIOS password and disable booting from USB, disable guest login, and
have proctors. The full list of known limits is in
[AUDIT.md](AUDIT.md#4-known-limits-be-honest-about-them).

**Why not just block ChatGPT's domain?**
There are hundreds of AI services and new ones every month. Default-deny
(allow only the contest site) is the only approach that keeps up. The AI
denylist is an extra safety net for allowlist mistakes.

**Does it read contestants' passwords or code?**
No. HTTPS is never decrypted; the proxy only sees the site *name*. The logs
contain host names and times, not page contents.

**What about AI on the contestant's phone or smartwatch?**
Out of scope for software. Collect devices at the door.

**What about an AI model that someone installed on the PC?**
Known runtimes and apps (ollama, LM Studio, GPT4All, llamafile, Jan, Cursor,
Windsurf, Zed, AI CLIs, …) are listed in `blocked-apps.txt`, and the
contest account may not run them. Add more in `blocked-apps.local.txt`
([example 10](EXAMPLES.md#example-10--block-an-extra-program)).
Contestants can't bring a model in: USB and downloads are blocked.

**Can contestants use VS Code's AI?**
No. `chat.disableAIFeatures` is set, Copilot is disabled, only the C++,
Python and Java extensions are allowed, and the Copilot servers are
unreachable anyway.

### Usage

**Does my admin account get restricted too?**
The *network firewall* applies only to the contest account, so your
terminal (ssh, apt, curl) works normally. But browser policies are
machine-wide: while contest mode is on, **every** account's browser uses the
contest proxy. Turn contest mode off to browse freely.

**Do I have to run `restrict` again after a reboot?**
No. Contest mode starts automatically at boot, before anyone can log in.

**Can I change the allowlist during the contest?**
Yes. `sudo cmanager add …` / `remove …` apply immediately, without
restarting anything or disconnecting anyone.

**Can contestants log in with Google?**
Not by default. See [PLATFORMS.md](PLATFORMS.md#contestants-who-normally-use-sign-in-with-google-three-options)
for the three options (the recommended one: set a normal password on the
judge account before contest day).

**How do I prepare 40 PCs?**
Install once on each PC, then control them all from your laptop with
[`examples/rollout.sh`](../examples/rollout.sh)
([example 8](EXAMPLES.md#example-8--roll-out-to-a-whole-lab)). Cloning a
prepared disk image also works; run `sudo cmanager verify` on each clone.

**Where is the log of what contestants tried to open?**
`/var/log/contest-env/proxy/access.log` (every request), summarised by
`sudo cmanager denied`. Admin actions are logged in
`/var/log/contest-env/cmanager.log` (`sudo cmanager logs`).

**Does `reset` delete the contestant's code?**
Yes, everything in their home folder that wasn't in the snapshot. Collect
any files you need (for example for plagiarism checks) before resetting.

**I upgraded from the old version (v1). What happens?**
`sudo ./install.sh` removes the old services and firewall chains and merges
your old allowlist into the new one. Then run `sudo cmanager setup` once.

### Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md). The three commands that
answer most questions:

```bash
sudo cmanager status
sudo cmanager verify
sudo cmanager denied
```
