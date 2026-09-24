# Contest-day runbook

A checklist for lab admins and the judge team. Print it.

## T-3 days: prepare every PC (Internet on)

```bash
git clone https://github.com/eyasir329/contest_env.git
cd contest_env
sudo ./install.sh
sudo cmanager setup                  # asks for the contestant password once
```

- [ ] `setup` finished without red `✘` lines (yellow `!` means an optional package was skipped).
- [ ] Log in as `participant` once. Check that Code::Blocks / VS Code / Sublime / Geany compile and run
      a C++ program, and that `python3`, `pypy3` and `java` work.
- [ ] Make any desktop tweaks you want every contestant to get (shortcuts, keyboard layout),
      log out, then run `sudo cmanager snapshot`.
- [ ] Guest login is disabled, and the admin password is known only to organisers.
- [ ] BIOS: boot from USB/DVD disabled, BIOS password set (otherwise a live USB bypasses everything).

## T-1 day: configure the allowlist and do a mock run

```bash
sudo cmanager sites                  # see available profiles
sudo nano /etc/contest-env/whitelist.txt
#   keep ONLY what this contest needs, e.g.
#     @codeforces           (online)
#     @vjudge               (vjudge contest)
#     192.168.10.5          (on-site DOMjudge)
sudo cmanager restrict
sudo cmanager verify                 # every line must be PASS
```

Mock run: log in as `participant`, then open the contest site, log in, open a
problem and submit a test solution. Then, as admin:

```bash
sudo cmanager denied                 # hosts the site tried to load but were refused
sudo cmanager add <legit-cdn-host>   # only if the site is broken without it
```

- [ ] Problem statements render (MathJax), login works, and submitting works.
- [ ] `https://chatgpt.com`, `https://google.com` and `https://github.com` do **not** load.
- [ ] The Chrome/Firefox side panels show no AI entry, and `chrome://policy` lists the contest-env policies.
- [ ] A USB stick plugged in does not appear. A phone connected over USB shows no files.
- [ ] Reboot one PC, then `sudo cmanager verify` still passes (persistence).

Copy the final allowlist to the other PCs:

```bash
scp /etc/contest-env/whitelist.txt admin@pc-02:/tmp/ && ssh admin@pc-02 \
  'sudo cp /tmp/whitelist.txt /etc/contest-env/ && sudo cmanager reload && sudo cmanager verify'
```

## Contest day

1. Leave contest mode **on** from the mock run (it survives reboots), or turn it on now: `sudo cmanager restrict`.
2. `sudo cmanager reset` on each PC, so every contestant starts from the snapshot.
3. `sudo cmanager verify` on each PC and look for `All checks passed`.
4. Contestants log in as `participant`.

If a problem shows up mid-contest:

| Symptom | Fix (as admin, no reboot needed) |
|---------|----------------------------------|
| Site partly broken (missing images or CSS) | `sudo cmanager denied`, then `sudo cmanager add <host>` |
| Judge moved to a new IP | `sudo cmanager add 192.168.10.6` |
| "Proxy refused" everywhere | `sudo cmanager status` (the guard restarts the proxy within 60 s); `sudo systemctl restart contest-proxy` |
| Contestant's browser still open from before `restrict` | Ask them to close and reopen it (policies load at start) |

## Between rounds / contestants

```bash
sudo cmanager reset --force          # logs the user out, restores the clean home
```

Contest mode stays on.

## After the contest

```bash
sudo cmanager unrestrict             # Internet, USB, Bluetooth back to normal
sudo cmanager reset --force          # optional: wipe contestant files
```

Keep `/var/log/contest-env/proxy/access.log` if the judges want to review
which sites each machine tried to reach (for plagiarism or dispute cases).
