# How it works, in plain language

This page explains what `cmanager restrict` actually changes on the PC and
follows a few real requests through the system. For the formal threat model
and file-by-file details, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## The picture

```
 Contestant's programs (Chrome, Firefox, VS Code, terminal, …)
                     │
                     │  every network packet from the "participant" account
                     ▼
  ┌──────────────────────────────────────────────┐
  │ 1. FIREWALL  (nftables, only for participant)│
  │    • DNS?                     → blocked      │
  │    • to 127.0.0.1 (this PC)?  → allowed      │
  │    • to an allowed judge IP?  → allowed      │
  │    • anything else?           → blocked      │
  └──────────────────────────────────────────────┘
                     │  so the only way out is…
                     ▼
  ┌──────────────────────────────────────────────┐
  │ 2. PROXY  (Squid on 127.0.0.1:3128)          │
  │    • AI site?                 → refused      │
  │    • on the allowlist?        → no → refused │
  │    • HTTPS: does the name inside the         │
  │      encrypted handshake match? → no → cut   │
  │    • yes → pass through, untouched           │
  └──────────────────────────────────────────────┘
                     │
                     ▼
               codeforces.com ✔
```

Around that core, four more locks:

| Lock | What it does |
|------|--------------|
| **3. Browser policies** | Chrome, Edge, Brave, Chromium and Firefox are told, by machine-wide policy files a normal user can't change: AI features off, extensions off, "use the contest proxy". |
| **4. Editor settings** | VS Code: AI chat/Copilot off, only the C++/Python/Java extensions allowed. |
| **5. Program blocks** | AI programs installed on the PC (Cursor, ollama, LM Studio, …) get a "participant may not run this" permission. |
| **6. Device blocks** | USB storage, phones (MTP), DVD drives and Bluetooth are switched off. The contest account may not mount disks or change network settings. |

And one safety net: a small **guard** runs every minute and puts things
back if the firewall or proxy disappeared (for example after a crash or
reboot).

---

## Why two layers (firewall + proxy)?

- The **firewall** is simple and strict, but it only understands IP
  addresses. Big websites share IP addresses: Codeforces, ChatGPT and
  millions of other sites can sit behind the same Cloudflare address. An
  IP-based allowlist would therefore also let ChatGPT through. (That was
  the main bug in v1 of this project.)
- The **proxy** understands website *names*, so it can say "yes to
  `codeforces.com`, no to `chatgpt.com`" even when both share an IP.

So the firewall's only job is to force everything through the proxy
("you may only talk to this PC"). The proxy then decides by name.

## Why is DNS blocked for contestants?

DNS is how a computer turns `codeforces.com` into an IP address. If
contestants could use DNS they could hide data inside DNS questions. There
are even services that answer AI questions over DNS. Contestants don't need
DNS: the browser hands the name to the proxy, and the proxy looks it up.

## Is my traffic decrypted?

No. For HTTPS the browser first says, unencrypted, "I want to talk to
`codeforces.com`" (the TLS *SNI* name). The proxy reads only that name,
compares it with the allowlist and then either passes the encrypted
connection through untouched or cuts it. Passwords and page contents are
never visible to the proxy.

---

## Five requests, followed through the system

These are real log lines from `/var/log/contest-env/proxy/access.log`
(the format is: time, client, result, method, target, SNI name).

### 1. Allowed site: `https://codeforces.com`

```text
NONE_NONE/200  CONNECT codeforces.com:443  sni=codeforces.com
TCP_TUNNEL/200 CONNECT codeforces.com:443  sni=codeforces.com
```

The browser asks the proxy for a tunnel to `codeforces.com`. The name is on
the allowlist, and the encrypted handshake also says `codeforces.com`, so
the tunnel is opened (`TCP_TUNNEL`). ✔

### 2. Not on the list: `https://www.google.com`

```text
TCP_DENIED/200 CONNECT www.google.com:443 sni=-
```

Refused immediately, before the proxy even looks up the IP address. The
browser shows "This site can't be reached".

### 3. AI site: `https://chatgpt.com`

```text
TCP_DENIED/200 CONNECT chatgpt.com:443 sni=-
```

Refused by the **AI denylist**. That list is checked *before* the allowlist,
so an admin mistake can't open it: even if `google.com` were allowed,
`gemini.google.com` would stay blocked.

### 4. The trick: "tunnel to an allowed site, but talk to ChatGPT"

A clever contestant runs:

```bash
curl -x http://127.0.0.1:3128 --connect-to chatgpt.com:443:codeforces.com:443 https://chatgpt.com
```

This asks for a tunnel to `codeforces.com` (allowed) but then asks for
`chatgpt.com` inside the handshake:

```text
NONE_NONE/200 CONNECT codeforces.com:443 sni=chatgpt.com
```

The proxy notices that the handshake name (`chatgpt.com`) is not allowed
and cuts the connection. `curl` fails with a TLS error. ✘

### 5. Going around the proxy: `curl --noproxy '*' https://1.1.1.1`

This never reaches the proxy. The **firewall** rejects the packet because
it isn't going to `127.0.0.1` or an allowed judge IP:

```text
curl: (7) Failed to connect to 1.1.1.1 port 443 …
```

The same happens to VPNs, SSH tunnels, `pip install`, Tor, and a browser
started with `--no-proxy-server`: they all fail. The design **fails
closed**.

---

## What `restrict` changes, and `unrestrict` undoes

| Area | Change while contest mode is on | Undone by `unrestrict`? |
|------|---------------------------------|-------------------------|
| Firewall | nftables table `inet contest_env` (only affects the contest account) | ✔ removed |
| Proxy | `contest-proxy.service` running on 127.0.0.1:3128 | ✔ stopped |
| DNS | Contest account can't use DNS | ✔ restored |
| USB/phones/DVD | Kernel modules refused, USB interfaces blocked, mounting denied | ✔ restored |
| Bluetooth | Switched off | ✔ switched on (if it was enabled) |
| AI programs | "participant may not run" permission on each one found | ✔ exactly those removed |
| Browsers | "use proxy 127.0.0.1:3128", no search engine | ✔ proxy policy removed |
| Browsers | AI features off, extensions off (set by `setup`) | ✘ stays on purpose (it's a contest PC) |
| Privileged groups | Contest account removed from sudo/cdrom/plugdev/… | ✘ stays removed |

## What happens on reboot

1. Early in boot, before anyone can log in, `contest-firewall.service`
   loads the saved firewall rules.
2. `contest-proxy.service` starts the proxy.
3. `contest-guard.timer` starts checking every minute.

All three only run while contest mode is on (the marker file
`/var/lib/contest-env/restricted` exists).

## What `reset` does

`/var/lib/contest-env/snapshots/participant/` holds the clean home folder
saved by `setup` (or `snapshot`). `reset` makes the real home folder
**identical** to it: new files are deleted, changed files are restored,
browser profiles and saved logins disappear. It also deletes the account's
files in `/tmp`, its cron/at jobs and background sessions. It does
**not** touch contest mode.
