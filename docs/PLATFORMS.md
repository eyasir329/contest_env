# Judges and logins: making login and submission work

This page answers: *"Can contestants log in to the judge and submit while
contest mode is on?"*

**Short answer:** yes, when they log in with **username/e-mail + password**
on a judge whose profile is enabled. **"Sign in with Google / GitHub /
Facebook" is blocked on purpose.** This page explains why and gives three
ways to handle it.

> The judges' websites change over time. Treat the tables below as a
> starting point and **always do one mock login + submission per judge in
> your lab** (see [Test it yourself](#test-it-yourself-10-minutes-per-judge)).

---

## How login and submission work through contest mode

- Logging in, reading problems, submitting and seeing verdicts are all
  ordinary HTTPS requests to the judge's own domain, for example
  `codeforces.com`. The profile allows that domain **and all its
  sub-domains**, so they work.
- Session cookies are stored in the browser as usual. Contest mode doesn't
  touch them, so contestants stay logged in when you turn contest mode on
  or off. **Only `cmanager reset` logs them out**, because it wipes the
  browser profile.
- Captchas:
  - **Cloudflare Turnstile** ("Verify you are human"): allowed (in `@common`).
  - **hCaptcha / Google reCAPTCHA**: *not* allowed. reCAPTCHA is served
    from `www.google.com`, the same host as Google Search and its AI mode.
    If a judge shows a Google captcha at login, use method B or C below.

## Login methods: what works

| Login method | During contest mode | Why |
|--------------|---------------------|-----|
| Username / e-mail + password on the judge | ✅ works | Only the judge's own domain is involved |
| "Sign in with **Google**" | ❌ blocked by default | Needs `accounts.google.com` and other Google hosts; `google.com` also serves Search (with AI answers) |
| "Sign in with **GitHub**" | ❌ blocked, keep it that way | `github.com` hosts GitHub Copilot chat and every public code repository |
| "Sign in with **Facebook** / LinkedIn" | ❌ blocked, keep it that way | Messaging and social feeds (Meta AI on Facebook) |
| Two-step verification by phone app/SMS | ⚠ usually impossible | Phones are not allowed in the room |

## Contestants who normally use "Sign in with Google": three options

### A. Recommended: give the judge account a normal password (no Google needed)

Almost every judge lets an account that was created with Google also set a
password. Ask contestants to do this **at home, before the contest day**:

1. Log in to the judge with Google as usual.
2. Open the account settings, or log out and use "Forgot password?" with the
   same e-mail address.
3. Set a password, then test logging in with **e-mail + password**.

In the lab they then log in with e-mail + password. Nothing about Google is
needed, and nothing is opened up. Put this in your contest announcement.

### B. A supervised login window *before* contest mode is switched on

For contestants who can't do A (or a judge that needs a Google captcha):

1. **Before** the contest starts, keep contest mode **off**
   (`sudo cmanager unrestrict`). Supervise the room.
2. Contestants log in to the judge (Google login, phone 2-step
   verification and captcha all work now), then leave their phones with the
   organisers.
3. Turn contest mode **on**: `sudo cmanager restrict` (or
   `./examples/rollout.sh lab.txt restrict` for the whole lab).
4. **Every contestant closes all browser windows and opens the browser
   again**, so nothing loaded during the window stays on screen. Proctors
   check this. The judge login survives, because cookies are kept.
5. `sudo cmanager verify` on every PC, then start the contest.

Do **not** run `cmanager reset` between the login window and the contest:
it would log everyone out.

### C. Allow Google sign-in hosts during the contest (not recommended)

This is possible with the existing `--force` option, but it's a deliberate
trade-off and isn't tested by this project:

```bash
sudo cmanager add --force accounts.google.com
# then do a mock login and look at what else was refused:
sudo cmanager denied
```

What stays true: every AI domain in `ai-denylist.txt` (including
`gemini.google.com`) stays blocked, and `www.google.com` (Search) stays
blocked unless you add it too. What you accept: contestants can reach their
Google account pages, and you depend on Google not moving features between
hosts. Prefer A or B.

---

## Per-judge notes

Profile = what to put in `whitelist.txt` (or `sudo cmanager add @name`).

### Codeforces

| | |
|---|---|
| Profile | `@codeforces` (codeforces.com, codeforces.org + `@common`) |
| Login | handle or e-mail + password |
| Captcha | Cloudflare "verify you are human" (allowed) |
| Submit | on codeforces.com (allowed); both file upload and pasting code work |
| Notes | Mirror sub-domains (for example `m1.codeforces.com`) are covered. Analytics hosts are refused; the site works without them. |

### AtCoder

| | |
|---|---|
| Profile | `@atcoder` (atcoder.jp incl. img.atcoder.jp + `@common`) |
| Login | username + password |
| Submit | on atcoder.jp |
| Notes | Statements use MathJax from cdnjs (in `@common`). |

### CodeChef

| | |
|---|---|
| Profile | `@codechef` (codechef.com incl. cdn.codechef.com + `@common`) |
| Login | username/e-mail + password, or social login (Google etc.: see options A–C) |
| Submit | on codechef.com (IDE and submit page) |
| Notes | Check the "My submissions" page during the mock run; some images come from other hosts, so run `cmanager denied`. |

### Virtual Judge (vjudge)

| | |
|---|---|
| Profile | `@vjudge`, plus the profiles of the origin judges whose problems are used |
| Login | vjudge username + password |
| Submit | on vjudge.net; vjudge normally forwards it to the origin judge with its own accounts |
| Notes | See [EXAMPLES.md, example 3](EXAMPLES.md#example-3--a-university-contest-on-vjudge). |

### Toph

| | |
|---|---|
| Profile | `@toph` (toph.co + `@common`) |
| Login | handle/e-mail + password (use option A if the account was made with a social login) |
| Submit | on toph.co |

### LightOJ

| | |
|---|---|
| Profile | `@lightoj` (lightoj.com + `@common`) |
| Login | e-mail + password; Google sign-in is offered, so see options A–C |

### LeetCode

| | |
|---|---|
| Profile | `@leetcode` (leetcode.com incl. assets.leetcode.com + `@common`) |
| Login | username/e-mail + password, or social login (Google, GitHub, …) |
| Notes | LeetCode's login page may use a Google captcha, so **option B** (log in before contest mode) is the reliable choice. |

### HackerRank

| | |
|---|---|
| Profile | `@hackerrank` (hackerrank.com, hrcdn.net + `@common`) |
| Login | e-mail + password, or social login |
| Notes | For HackerRank tests sent by e-mail invitation, the test link is on hackerrank.com (covered). |

### HackerEarth

| | |
|---|---|
| Profile | `@hackerearth` (hackerearth.com + `@common`) |
| Login | e-mail + password, or social login |

### CSES, SPOJ, UVa, Kattis

| Judge | Profile | Login |
|-------|---------|-------|
| CSES | `@cses` | username + password |
| SPOJ | `@spoj` | username + password |
| UVa Online Judge | `@uva` | username + password |
| Kattis | `@kattis` | e-mail + password (social login: options A–C) |

### DOMjudge / PC² on your own server

| | |
|---|---|
| Allowlist | the server's IP, e.g. `192.168.10.5` (any port works) |
| Login | the team account the judges hand out (on paper) |
| Submit | the web interface, or DOMjudge's `submit` command-line client |
| Notes | See [EXAMPLES.md, example 2](EXAMPLES.md#example-2--an-on-site-contest-with-domjudge-on-the-lan). |

---

## Test it yourself (10 minutes per judge)

Do this in the lab a few days before the contest, with contest mode **on**:

1. Log in to the PC as `participant`.
2. Open the judge, **log in** with a real account, open a contest or
   problem page, **submit** a solution (a wrong answer is fine) and wait for
   the verdict.
3. As admin, run `sudo cmanager denied`. For each refused host, decide:
   - analytics or ads (`google-analytics`, `googletagmanager`, `doubleclick`, `yandex` metrica, `facebook` pixel): **ignore**;
   - the site's own CDN, image or formula host: `sudo cmanager add <host>`;
   - search, code hosting, social or AI: **never add**.
4. Repeat step 2 until login, statement, submission and verdict all work.
5. Put the hosts you added in a custom profile (see
   [EXAMPLES.md, example 9](EXAMPLES.md#example-9--your-own-site-profile-for-an-event)),
   so the next contest (and other PCs) get them automatically.

If you fix a shipped profile, please send the change back to this
repository (see [CONTRIBUTING.md](../CONTRIBUTING.md)) so every lab benefits.
