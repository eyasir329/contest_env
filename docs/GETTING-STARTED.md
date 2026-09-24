# Getting started: your first contest PC, step by step

This guide takes one lab PC from "fresh Ubuntu" to "contest-ready". It shows
what to type and what you should see. It takes about 20 minutes, most of it
waiting for software downloads.

> **Terms used here**
> - **Admin account**: your own account with `sudo`. You type every command here as admin.
> - **Contest account**: the account contestants log into. By default it is called `participant`.
> - **Allowlist**: the list of websites contestants may open. Everything else is blocked.
> - **Contest mode**: the state in which all the blocking is active.

---

## Step 0: Check the PC

- Ubuntu 22.04 / 24.04 or Debian 12 or newer, desktop edition.
- You are logged in as an admin (`sudo` works).
- The PC has Internet access (needed now, to download software).

```bash
lsb_release -d        # e.g. "Description: Ubuntu 24.04.1 LTS"
sudo true && echo OK  # must print OK
```

## Step 1: Download and install `cmanager`

```bash
sudo apt-get install -y git
git clone https://github.com/eyasir329/contest_env.git
cd contest_env
sudo ./install.sh
```

Expected output (shortened):

```text
== Installing contest-env from /home/admin/contest_env ==
✔ Code installed to /usr/local/lib/contest-env, command: cmanager
✔ Configuration in /etc/contest-env  (existing contest.conf / whitelist.txt kept; new defaults saved as *.dist)
✔ systemd units installed (enabled only while contest mode is on)

Installed. Next steps:
  sudo cmanager setup
  ...
```

`install.sh` only copies files. It does not block anything yet. If an
older version of this project (v1) is installed, it is removed
automatically and its allowlist is carried over.

## Step 2: Install the software and create the contest account

```bash
sudo cmanager setup
```

This will:

1. install compilers and tools: `gcc`, `g++`, `clang`, `gdb`, `python3`, `pypy3`, Java (JDK), `valgrind`;
2. install editors: VS Code, Sublime Text, Code::Blocks, Geany, vim, neovim, nano;
3. install browsers: Google Chrome (on 64-bit PCs) and Firefox;
4. install offline documentation: cppreference (C/C++) and the Python docs;
5. install the tools contest mode needs (nftables firewall, Squid proxy);
6. create the account **`participant`** and **ask you for its password**. This is the password contestants will type, so choose something simple to say out loud;
7. turn off AI features in Chrome, Firefox and VS Code;
8. stop automatic updates (so nothing updates in the middle of a contest);
9. take a **snapshot** of the clean `participant` home folder.

Expected end of the output:

```text
== Home snapshot ==
✔ Snapshot of /home/participant saved (2.1M) → /var/lib/contest-env/snapshots/participant

== Done ==
✔ Lab PC is prepared for 'participant'.
Next: edit /etc/contest-env/whitelist.txt, then 'sudo cmanager restrict' and 'sudo cmanager verify'.
```

Lines starting with a yellow `!` are warnings, for example an optional
package that doesn't exist on your Ubuntu version. They are safe to
ignore. A red `✘` means something failed; read the message.

> **Tip: want a different account name?** Use `sudo cmanager setup contestant`, then set
> `CONTEST_USER="contestant"` in `/etc/contest-env/contest.conf` so every other command uses it too.

## Step 3: Try the contestant desktop (optional, recommended)

Log out, log in as `participant`, and check:

- VS Code / Code::Blocks can compile and run a "hello world" in C++.
- `python3`, `pypy3` and `java -version` work in a terminal.

Arrange the desktop the way every contestant should get it (dock icons,
keyboard layout, terminal font). Log out, log back in as admin and save
that as the new clean state:

```bash
sudo cmanager snapshot
```

## Step 4: Choose the allowed sites

See what profiles exist:

```bash
sudo cmanager sites
```

```text
Site profiles in /etc/contest-env/sites  (enable: sudo cmanager add @name)

  [   ] @atcoder     AtCoder
  [   ] @codechef    CodeChef
  [on]  @codeforces  Codeforces  (codeforces.com, polygon/assets/mirror sub-domains included)
  [   ] @common      Shared, low-risk dependencies used by many judges.
  ...
  [   ] @vjudge      Virtual Judge (vjudge.net) - many Bangladeshi university contests run here.
```

`[on]` means enabled. Codeforces is enabled by default. Change it for your contest:

```bash
sudo cmanager add @vjudge            # enable vjudge
sudo cmanager remove @codeforces     # disable Codeforces (the line is commented out, not deleted)
sudo cmanager add 192.168.10.5       # your own judge server on the LAN (DOMjudge, PC^2)
```

Or edit the file directly, then apply it:

```bash
sudo nano /etc/contest-env/whitelist.txt
sudo cmanager reload
```

Check the result:

```bash
sudo cmanager list
```

```text
Effective domains (each includes its sub-domains):
  cdnjs.cloudflare.com
  challenges.cloudflare.com
  ...
  vjudge.net

Direct IPs / ranges:
  192.168.10.5

Always blocked: 104 AI domains (/etc/contest-env/ai-denylist.txt)
```

Keep the list **as short as possible**: only what *this* contest needs.

## Step 5: Turn contest mode on

```bash
sudo cmanager restrict
```

```text
== Contest mode ON for 'participant' ==
→ Allowlist
   domain  vjudge.net
   ipv4    192.168.10.5
   ...
→ Proxy
✔ Proxy config: 8 domain rule(s), 1 IP rule(s), SNI enforcement ON
✔ Proxy listening on 127.0.0.1:3128
→ Firewall
✔ Firewall active: 'participant' may only reach loopback (proxy) + allowlisted IPs
→ Resolver
✔ No DNS for 'participant' (proxy resolves names)
→ Devices
✔ Removable media blocked (USB storage, phones/MTP, optical, mounting)
✔ Bluetooth off
→ Programs
✔ No AI/remote-access programs found on this machine
→ Accounts
→ Browsers
✔ Browsers locked to the contest proxy (restart open browsers)

== Contest mode is ON ==
  User      : participant
  Internet  : allowlist only, via 127.0.0.1:3128  (/etc/contest-env/whitelist.txt)
  Survives  : reboots (systemd) and is self-healing (guard timer, every minute)
  Next      : sudo cmanager verify     # proves it works, as 'participant'
```

## Step 6: Prove it works

```bash
sudo cmanager verify
```

```text
== Verifying contest mode as 'participant' ==
  PASS  services: firewall table loaded
  PASS  services: proxy running
  PASS  allowed site reachable via proxy (https://vjudge.net)
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

If any line says `FAIL`, don't use the PC yet. See
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Step 7: Do a mock contest as a contestant

Log in as `participant`, open the browser and:

1. open the contest site and **log in** with a real account;
2. open a problem, **submit** a solution, and see the verdict;
3. try `google.com` and `chatgpt.com`: neither should load.

If the contest site looks broken (no images, no formulas, the login button
does nothing), go back to the admin account and run:

```bash
sudo cmanager denied
```

```text
== Refused by the proxy (most recent 5000 log lines) ==
     12  www.google.com  (not allowed)
      4  static.somecdn.net  (not allowed)
```

Allow **only** what the site genuinely needs, such as a CDN or captcha
provider. Never allow search engines or code sites:

```bash
sudo cmanager add static.somecdn.net
```

## Step 8: Contest day and afterwards

```bash
sudo cmanager reset --force     # before each contestant: clean home folder
sudo cmanager verify            # every PC must say "All checks passed"
# ... contest ...
sudo cmanager unrestrict        # afterwards: everything back to normal
```

Contest mode survives reboots, so you can set it up the day before.

## Where next?

- Many PCs? The rollout script is in [EXAMPLES.md](EXAMPLES.md#example-8--roll-out-to-a-whole-lab).
- The printable contest-day checklist: [CONTEST-DAY.md](CONTEST-DAY.md).
- How each judge's login works (and Google login): [PLATFORMS.md](PLATFORMS.md).
