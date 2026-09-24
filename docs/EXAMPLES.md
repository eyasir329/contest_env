# Examples: real situations, step by step

Each example is a complete recipe. The files it mentions are in the
[`examples/`](../examples/) folder of this repository. All commands are run
as an admin on the lab PC, unless the example says otherwise.

| # | Situation |
|---|-----------|
| 1 | [A Codeforces round in the lab](#example-1--a-codeforces-round-in-the-lab) |
| 2 | [An on-site contest with DOMjudge on the LAN](#example-2--an-on-site-contest-with-domjudge-on-the-lan) |
| 3 | [A university contest on vjudge](#example-3--a-university-contest-on-vjudge) |
| 4 | [Weekly club practice with several judges](#example-4--weekly-club-practice-with-several-judges) |
| 5 | [Allow the C++ / Python / Java reference](#example-5--allow-the-c--python--java-reference) |
| 6 | [The contest site looks broken mid-contest](#example-6--the-contest-site-looks-broken-mid-contest) |
| 7 | [Next contestant on the same PC](#example-7--next-contestant-on-the-same-pc) |
| 8 | [Roll out to a whole lab](#example-8--roll-out-to-a-whole-lab) |
| 9 | [Your own site profile for an event](#example-9--your-own-site-profile-for-an-event) |
| 10 | [Block an extra program](#example-10--block-an-extra-program) |
| 11 | [A lean ICPC-like machine](#example-11--a-lean-icpc-like-machine) |
| 12 | [Check a PC a contestant says is "broken"](#example-12--check-a-pc-a-contestant-says-is-broken) |
| 13 | [Undo everything](#example-13--undo-everything) |

---

## Example 1 — A Codeforces round in the lab

Club members take a rated Codeforces round together in the lab.

```bash
sudo cp examples/whitelist-codeforces-round.txt /etc/contest-env/whitelist.txt
sudo cmanager restrict
sudo cmanager verify
```

The allowlist contains a single line, `@codeforces`. It expands to
`codeforces.com`, `codeforces.org` and the shared captcha, font and MathJax
hosts (`cmanager list` shows the full result).

Contestants log in with their own Codeforces handle and password. See
[PLATFORMS.md](PLATFORMS.md#codeforces) for login notes.

After the round: `sudo cmanager unrestrict`.

## Example 2 — An on-site contest with DOMjudge on the LAN

An IUPC-style contest. The judge (DOMjudge) runs on `192.168.10.5`. The
contest PCs must reach **only** the judge, with no Internet at all.

```bash
sudo cp examples/whitelist-onsite-domjudge.txt /etc/contest-env/whitelist.txt
sudo nano /etc/contest-env/whitelist.txt    # put in your judge's real IP
sudo cmanager restrict
sudo cmanager verify
```

The file contains an IP address instead of a site profile:

```text
192.168.10.5       # DOMjudge web server
```

- Contestants type `http://192.168.10.5/` (or whatever port DOMjudge uses) in the browser.
- IP entries are reached **directly**, on any port. The browsers are told to bypass the proxy for them.
- DOMjudge's command-line `submit` client works too, since it talks straight to the IP.
- `verify` tests only Internet sites here. Open the judge page as `participant` to confirm it loads.

The judge's own machine should **not** have contest mode on.

## Example 3 — A university contest on vjudge

The contest is on `vjudge.net`, with problems taken from Codeforces and AtCoder.

```bash
sudo cp examples/whitelist-vjudge-university.txt /etc/contest-env/whitelist.txt
sudo cmanager restrict && sudo cmanager verify
```

```text
@vjudge
@codeforces        # statements embedded from Codeforces
@atcoder           # statements embedded from AtCoder
```

vjudge shows each problem as it appears on the original judge, so those
judges' pages and images must load too. vjudge normally submits for you
through its own accounts, so contestants need only a **vjudge** login.

Do a mock run: open one problem from each origin judge and look for
missing images with `sudo cmanager denied` (see example 6).

## Example 4 — Weekly club practice with several judges

The practice session is on multiple judges, with the language reference
allowed, but still no Google and no AI.

```bash
sudo cp examples/whitelist-practice-lab.txt /etc/contest-env/whitelist.txt
sudo cmanager restrict
```

```text
@codeforces
@atcoder
@codechef
@vjudge
@toph
@lightoj
@cses
@docs
```

You can switch a judge on or off at any time without restarting anything:

```bash
sudo cmanager add @leetcode
sudo cmanager remove @codechef
```

## Example 5 — Allow the C++ / Python / Java reference

**Best: offline.** `setup` already installed it. Contestants open these in the browser:

```text
file:///usr/share/cppreference/doc/html/en/index.html
file:///usr/share/doc/python3/html/index.html
```

No allowlist change is needed. Offline copies can't link to anything else.

**Online**, if your rules allow it:

```bash
sudo cmanager add @docs      # en.cppreference.com, docs.python.org, docs.oracle.com
```

## Example 6 — The contest site looks broken mid-contest

A contestant reports: "the problem statement has no formulas" or "the login
button does nothing". The site needs a host that isn't on the list.

```bash
sudo cmanager denied
```

```text
== Refused by the proxy (most recent 5000 log lines) ==
    31  www.google-analytics.com  (not allowed)
     9  cdn.example-mathjax.net  (not allowed)
     2  chatgpt.com  (not allowed)
```

How to read it:

- `www.google-analytics.com`: tracking. Pages work without it. **Don't add.**
- `cdn.example-mathjax.net`: sounds like the formula renderer. **Add it:**

  ```bash
  sudo cmanager add cdn.example-mathjax.net
  ```

  It works immediately. The contestant only needs to reload the page.
- `chatgpt.com`: someone tried. It stays blocked no matter what. (The
  proxy log records which PC and when, if the judges want to know.)

Next time, find these hosts **before** the contest with a mock run, or with
`sudo cmanager discover https://the-site/contest/123` while contest mode is
off.

## Example 7 — Next contestant on the same PC

Several groups use the same PCs one after another (for example a selection
contest held in shifts).

```bash
sudo cmanager reset --force
```

- Logs `participant` out if needed.
- Restores the clean home folder: the previous contestant's code, browser
  logins and history, and shell history are all gone.
- Contest mode stays **on**: nothing needs re-checking, but running
  `sudo cmanager verify` costs nothing.

## Example 8 — Roll out to a whole lab

You have 40 PCs. You install once on each (`install.sh` + `setup`), then
control them all from your laptop with [`examples/rollout.sh`](../examples/rollout.sh).

**One-time preparation on each PC:**

```bash
# on each lab PC, as admin
sudo ./install.sh && sudo cmanager setup
sudo visudo -f /etc/sudoers.d/cmanager
#   admin ALL=(root) NOPASSWD: /usr/local/bin/cmanager, \
#     /usr/bin/install -m 0644 /tmp/contest-whitelist.txt /etc/contest-env/whitelist.txt
```

**On your laptop:**

```bash
ssh-copy-id admin@192.168.10.101          # once per PC
cp examples/hosts.example.txt lab-a.txt   # list your PCs, one per line

./examples/rollout.sh lab-a.txt push examples/whitelist-codeforces-round.txt
./examples/rollout.sh lab-a.txt restrict
./examples/rollout.sh lab-a.txt verify
```

```text
===== admin@192.168.10.101 : verify =====
...
✔ All checks passed — this machine is contest-ready.

===== Summary: verify =====
OK     (39): admin@192.168.10.101 admin@192.168.10.102 ...
FAILED (1): admin@192.168.10.117
```

Go to the failed PC and run `sudo cmanager status` there.

After the contest: `./examples/rollout.sh lab-a.txt unrestrict`.

## Example 9 — Your own site profile for an event

Your IUPC has a registration site on the Internet, plus a judge and a print
server on the LAN. Put them in one profile so any admin can enable the whole
event with one word.

```bash
sudo cp examples/sites/my-iupc-2026.txt /etc/contest-env/sites/
sudo nano /etc/contest-env/sites/my-iupc-2026.txt      # your real hosts and IPs
sudo cmanager sites                                    # it appears in the list
sudo cmanager add @my-iupc-2026
```

```text
# My IUPC 2026 (example custom site profile)
iupc.example.edu            # registration / announcements page
192.168.10.5                # DOMjudge
192.168.10.6                # print server
@common                     # captcha, fonts, JS libraries (if the site uses them)
```

Upgrades (`install.sh`) never overwrite profiles whose names aren't shipped with the project.

## Example 10 — Block an extra program

You want to stop contestants from running a program that isn't on the
built-in list, for example a second browser or games.

```bash
sudo cp examples/blocked-apps.local.txt /etc/contest-env/blocked-apps.local.txt
sudo nano /etc/contest-env/blocked-apps.local.txt
sudo cmanager restrict                 # re-apply
```

As the contestant, the program then fails:

```text
$ opera
bash: /usr/bin/opera: Permission denied
```

Other accounts are unaffected. `unrestrict` removes exactly these blocks.

## Example 11 — A lean ICPC-like machine

You want only Firefox, Code::Blocks, Geany, vim and emacs: no Chrome, VS
Code or Sublime.

```bash
sudo cp examples/contest-minimal.conf /etc/contest-env/contest.conf
sudo cmanager setup
```

Set this up **before** the first `setup`. Software that is already
installed is not removed.

## Example 12 — Check a PC a contestant says is "broken"

```bash
sudo cmanager status      # is everything active?
sudo cmanager verify      # does it actually work, as the contestant?
sudo cmanager denied 500  # what was refused recently?
sudo cmanager logs        # did someone change something?
```

Common answers:

| You see | Meaning / fix |
|---------|---------------|
| `Proxy (squid) DOWN` | The guard restarts it within 60 s, or run `sudo systemctl restart contest-proxy` |
| `Firewall MISSING` | The guard reloads it within 60 s, or run `sudo cmanager restrict` |
| `verify`: allowed site FAIL | The site is down, the lab has no Internet, or the allowlist is wrong (`cmanager list`) |
| `denied` shows a CDN | See example 6 |
| Browser still shows old behaviour | The contestant must close all browser windows and reopen them |

## Example 13 — Undo everything

```bash
sudo cmanager unrestrict        # contest mode off
sudo ./uninstall.sh             # remove cmanager (keeps /etc/contest-env and snapshots)
sudo ./uninstall.sh --purge     # ...and remove those too
```

The installed software (compilers, editors, browsers) and the `participant`
account are left in place. Remove the account with `sudo deluser --remove-home participant`.
