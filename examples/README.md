# Examples

Ready-to-copy files. Each one is explained step by step in
[../docs/EXAMPLES.md](../docs/EXAMPLES.md).

| File | What it is | Where it goes |
|------|------------|---------------|
| [whitelist-codeforces-round.txt](whitelist-codeforces-round.txt) | Allowlist for a Codeforces round | `/etc/contest-env/whitelist.txt` |
| [whitelist-onsite-domjudge.txt](whitelist-onsite-domjudge.txt) | Allowlist for an on-site contest judged by DOMjudge on the LAN (no Internet at all) | `/etc/contest-env/whitelist.txt` |
| [whitelist-vjudge-university.txt](whitelist-vjudge-university.txt) | Allowlist for a vjudge contest with Codeforces/AtCoder problems | `/etc/contest-env/whitelist.txt` |
| [whitelist-practice-lab.txt](whitelist-practice-lab.txt) | Allowlist for club practice: several judges + language docs | `/etc/contest-env/whitelist.txt` |
| [sites/my-iupc-2026.txt](sites/my-iupc-2026.txt) | A custom site profile for your own event | `/etc/contest-env/sites/` |
| [contest-minimal.conf](contest-minimal.conf) | Settings for a lean ICPC-like machine (Firefox + Code::Blocks + Geany only) | `/etc/contest-env/contest.conf` |
| [blocked-apps.local.txt](blocked-apps.local.txt) | Your own additions to the "may not run" list | `/etc/contest-env/blocked-apps.local.txt` |
| [rollout.sh](rollout.sh) + [hosts.example.txt](hosts.example.txt) | Run cmanager on every PC of a lab over SSH | run from your laptop |

Using an allowlist example:

```bash
sudo cp examples/whitelist-codeforces-round.txt /etc/contest-env/whitelist.txt
sudo cmanager reload      # applies it now if contest mode is on, otherwise just validates it
sudo cmanager list        # shows the result
```
