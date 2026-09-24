# contest_env: lock a Linux lab PC down for programming contests

> Built and maintained by the **Netrokona University Programming Club (NEUPC)**.
> The idea started from [MDPC](https://github.com/ShazidMashrafi/MDPC); this is a full rewrite (v2).

You run a programming contest in a computer lab. You want every contestant to be able to:

- ✅ open **the contest website** (Codeforces, AtCoder, vjudge, your own DOMjudge server, …), log in and submit;
- ✅ use normal programming tools (g++, Python, Java, VS Code, Code::Blocks, Sublime, Geany, vim).

And you want them **not** to be able to:

- ❌ open any other website (Google, GitHub, Stack Overflow, Facebook, …);
- ❌ use **any AI**: ChatGPT/Gemini/Claude websites, AI built into Chrome/Edge/Firefox, VS Code Copilot, AI editors like Cursor, or an AI model installed on the PC itself;
- ❌ copy files in or out with a USB stick, a phone, a DVD or Bluetooth;
- ❌ find anything the previous contestant left on the PC.

`contest_env` does all of that with a single command-line tool, **`cmanager`**, on Debian or Ubuntu PCs.

```text
$ sudo cmanager restrict        # contest mode ON
$ sudo cmanager verify          # prove it works
  PASS  allowed site reachable via proxy (https://codeforces.com)
  PASS  other site blocked (https://example.com)
  PASS  AI blocked (https://chatgpt.com)
  PASS  direct connection blocked (https://1.1.1.1)
  PASS  public DNS blocked (8.8.8.8:53)
  ...
✔ All checks passed — this machine is contest-ready.
$ sudo cmanager unrestrict      # contest mode OFF, everything back to normal
```

---

## Contents

- [What contestants experience](#what-contestants-experience)
- [5-minute quick start](#5-minute-quick-start)
- [The 4 ideas you need to know](#the-4-ideas-you-need-to-know)
- [Documentation map](#documentation-map)
- [Command cheat-sheet](#command-cheat-sheet)
- [Requirements](#requirements)
- [Repository layout](#repository-layout)
- [FAQ (short)](#faq-short)

---

## What contestants experience

They log in as the account **`participant`** (you choose its password) and see a normal desktop.

| They try to… | What happens |
|--------------|--------------|
| Open `codeforces.com` (on your list) | Works normally: log in, read problems, submit |
| Open `google.com`, `github.com`, `youtube.com` | The page does not load ("This site can't be reached") |
| Open `chatgpt.com`, `gemini.google.com`, `claude.ai` | Does not load, **even if you allowed a parent domain by mistake** |
| Click the Gemini / "AI" button in Chrome or the AI sidebar in Firefox | The feature is gone (switched off by browser policy) |
| Install a browser extension | Blocked by policy |
| Use Copilot / AI chat in VS Code | AI features are switched off, and they couldn't reach the servers anyway |
| Run `cursor`, `ollama`, `lm-studio` | `Permission denied` |
| `curl`, `pip install`, `ping 8.8.8.8` in a terminal | Fails: no network except the contest site through the browser proxy |
| Plug in a USB stick or a phone | Nothing shows up |
| Compile and run C++/Python/Java, use the debugger | Works normally, offline |
| Read the C++ / Python reference | Works offline (`file:///usr/share/cppreference/...`) |

The admin account is **not** restricted (only the terminal is fully free; see the FAQ).

---

## 5-minute quick start

Run this on **one** lab PC first. It needs Internet access and `sudo`.

```bash
# 1. Get the code and install the `cmanager` command
git clone https://github.com/eyasir329/contest_env.git
cd contest_env
sudo ./install.sh

# 2. Install compilers, editors and browsers, and create the contest account
#    (takes 5-15 minutes; asks you to choose the "participant" password)
sudo cmanager setup

# 3. Say which contest site is allowed (Codeforces is the default)
sudo cmanager sites                 # list available site profiles
sudo cmanager add @atcoder          # enable another one, if needed

# 4. Turn contest mode on and check it
sudo cmanager restrict
sudo cmanager verify

# 5. After the contest
sudo cmanager unrestrict
```

New to this? Follow **[docs/GETTING-STARTED.md](docs/GETTING-STARTED.md)**. It walks through every step and shows the output you should expect.

---

## The 4 ideas you need to know

**1. The allowlist.** A text file, `/etc/contest-env/whitelist.txt`, lists what contestants may open. Everything else is blocked. You rarely write domains yourself; you switch on ready-made **site profiles**:

```text
@codeforces        # codeforces.com + what its pages need (captcha, fonts, MathJax)
@vjudge
192.168.10.5       # your on-site DOMjudge server, by IP address
```

**2. Contest mode.** `sudo cmanager restrict` turns it on and `sudo cmanager unrestrict` turns it off. It survives reboots, and a background check repairs it every minute if something breaks.

**3. The snapshot.** `setup` saves a clean copy of the contestant's home folder. `sudo cmanager reset` puts it back between contestants: files, browser history, logins and shell history are all gone. Contest mode stays on.

**4. Verify, don't assume.** `sudo cmanager verify` makes real connections *as the contestant* and prints PASS/FAIL for each rule. Run it on every PC before the contest starts.

How it works inside (in plain language): **[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)**.

---

## Documentation map

| If you want to… | Read |
|-----------------|------|
| Set up your first PC, step by step | [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) |
| Copy a ready-made setup for your kind of contest | [docs/EXAMPLES.md](docs/EXAMPLES.md) and the [examples/](examples/) folder |
| Know what each command does and prints | [docs/COMMANDS.md](docs/COMMANDS.md) |
| Understand how the blocking works | [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) |
| Know how login and submission work on each judge (incl. Google login) | [docs/PLATFORMS.md](docs/PLATFORMS.md) |
| Run a real contest day (checklist to print) | [docs/CONTEST-DAY.md](docs/CONTEST-DAY.md) |
| Change settings, allowlist, profiles, blocked apps | [docs/CONFIGURATION.md](docs/CONFIGURATION.md) |
| Fix a problem | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) and [docs/FAQ.md](docs/FAQ.md) |
| Read the security design and threat model | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| See why v1 was rewritten, and the known limits | [docs/AUDIT.md](docs/AUDIT.md) |
| Contribute a site profile or a fix | [CONTRIBUTING.md](CONTRIBUTING.md) |

---

## Command cheat-sheet

| Command | Use it when |
|---------|-------------|
| `sudo cmanager setup` | Once per PC: installs software, creates `participant`, takes the snapshot |
| `sudo cmanager sites` / `list` | See which profiles exist / what is allowed right now |
| `sudo cmanager add @vjudge` / `add 192.168.10.5` | Allow a site profile / your judge server (applied immediately) |
| `sudo cmanager remove @vjudge` | Take it away again |
| `sudo cmanager restrict` | **Contest mode ON** |
| `sudo cmanager verify` | Prove the PC is ready (PASS/FAIL) |
| `sudo cmanager status` | See what is active |
| `sudo cmanager denied` | "The contest site looks broken": shows which hosts were refused |
| `sudo cmanager reset --force` | Next contestant: clean home folder |
| `sudo cmanager unrestrict` | **Contest mode OFF** |
| `sudo cmanager help` | Everything else |

Full reference with example output: [docs/COMMANDS.md](docs/COMMANDS.md).

---

## Requirements

- **OS:** Ubuntu 22.04 / 24.04 or Debian 12+ (desktop), with systemd.
- **Access:** an admin account with `sudo`. Contestants use a separate account.
- **Network:** Internet during `setup`. During the contest, only the allowed sites are reached.
- **Hardware:** anything that runs Ubuntu desktop. Google Chrome is installed only on 64-bit x86 (amd64); Firefox works everywhere.

## Repository layout

```text
contest_env/
├── README.md               ← you are here
├── install.sh              installs `cmanager` (and upgrades / migrates old versions)
├── uninstall.sh            removes it again
├── bin/cmanager            the command (reads its modules from lib/)
├── lib/                    one Bash module per job
│   ├── common.sh           settings, allowlist parsing, logging
│   ├── firewall.sh         nftables rules for the contest account
│   ├── proxy.sh            the Squid allowlist proxy
│   ├── lockdown.sh         USB / phone / DVD / Bluetooth / AI-app blocking
│   ├── browser.sh          Chrome + Firefox policies (AI off, proxy)
│   ├── editor.sh           VS Code settings (AI off)
│   ├── setup.sh            software installation + account creation
│   ├── reset.sh            snapshot / reset
│   ├── contest.sh          restrict / unrestrict / add / remove / reload
│   ├── status.sh           status / verify
│   ├── discover.sh         discover / denied
│   └── legacy.sh           removes the old v1 when upgrading
├── config/                 defaults, copied to /etc/contest-env/ on install
│   ├── contest.conf        settings (which user, what to block, what to install)
│   ├── whitelist.txt       the allowlist
│   ├── sites/*.txt         site profiles (@codeforces, @atcoder, …)
│   ├── ai-denylist.txt     AI services, always blocked
│   ├── risky-domains.txt   domains `add` refuses without --force
│   └── blocked-apps.txt    programs contestants may not run
├── systemd/                services that keep contest mode on after reboot
├── examples/               ready-to-copy allowlists, profile and rollout script
├── docs/                   all documentation
└── tests/run.sh            automated tests (`make test`)
```

## FAQ (short)

**Does it change anything for my admin account?**
Your terminal is never restricted. While contest mode is on, *browsers* on the PC (for every account) use the contest proxy, so your browser sees only the allowed sites too. Turn contest mode off to browse normally.

**Can a smart contestant turn it off?**
Not without root. The contestant account has no `sudo`, all rules are owned by root, and a watchdog repairs them within 60 seconds. Keep the admin password secret and lock the BIOS (no booting from USB).

**Can contestants log in with Google?**
Not by default: Google's domains are blocked because they also serve Search and Gemini. Recommended: ask contestants to set a normal password on their judge account before the contest. Details and the alternatives: [docs/PLATFORMS.md](docs/PLATFORMS.md).

**A contest site loads but looks broken.**
It needs an extra host (a CDN or captcha). Run `sudo cmanager denied`, then `sudo cmanager add <host>`. See [docs/EXAMPLES.md](docs/EXAMPLES.md#example-6--the-contest-site-looks-broken-mid-contest).

**Does it decrypt contestants' traffic?**
No. HTTPS is never decrypted; the proxy only reads the site *name*.

More: [docs/FAQ.md](docs/FAQ.md).

## Development

```bash
make lint   # shellcheck
make test   # unit tests (run as root to also validate the firewall and proxy config)
```

GitHub Actions runs both on every push. See [CONTRIBUTING.md](CONTRIBUTING.md).
