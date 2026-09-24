# Troubleshooting

Start with:

```bash
sudo cmanager status
sudo cmanager verify
sudo cmanager denied
sudo cmanager logs
```

## A contest site loads, but looks broken or login fails

The site pulls something from a host that isn't allowed (a CDN, captcha or
fonts).

```bash
sudo cmanager denied                 # the hosts the proxy refused
sudo cmanager add static.example-cdn.com
```

Before contest day, run `sudo cmanager discover https://site/contest/123`
with contest mode **off** to see every host a page uses.

Never add `google.com`, `github.com` and similar just to "make it work". If
a site needs Google reCAPTCHA, ask the organisers whether a
`recaptcha.net`-based login or a pre-contest login is possible.

## Nothing loads at all for the contestant

| Check | Command |
|-------|---------|
| Proxy running? | `systemctl status contest-proxy` (the guard restarts it within 60 s) |
| Proxy config valid? | `sudo squid -k parse -f /var/lib/contest-env/squid/squid.conf` |
| Browser opened before `restrict`? | Close every browser window and reopen it |
| Browser policy present? | Chrome: `chrome://policy`; Firefox: `about:policies` |
| Allowlist empty? | `sudo cmanager list` |

## Admin's own browser is limited while contest mode is on

Expected: browser policies apply to the whole machine, so during contest
mode every account's browser goes through the contest proxy. The admin's
**terminal** is not restricted (the firewall applies to the contest user
only). Use `sudo cmanager unrestrict` to browse freely.

## `modprobe: … usb_storage is in use` during `restrict`

A USB disk was mounted. Unmount or unplug it. Once it is unplugged, it
cannot be used again.

## A USB keyboard, mouse or network adapter stopped working

Only interfaces of class 08 (mass storage) and 06 (still image / MTP) are
de-authorised. A device that shows up as mass storage (some keyboards with
built-in drivers) loses only that interface. If something important breaks,
set `BLOCK_USB_STORAGE=0` or `BLOCK_MTP=0` in `contest.conf` and run
`sudo cmanager restrict`. The kernel module block for USB storage stays in
place.

## Ubuntu 22.04: mounting still works

Make sure `/etc/polkit-1/localauthority/50-local.d/contest-env.pkla` exists
(`restrict` writes it when that directory exists), and log the contestant
out and in again.

## `verify` fails "local DNS blocked"

`getent hosts example.com` succeeded for the contest user. A caching daemon
(`nscd`, `dnsmasq`, `unbound`) answers on their behalf. Stop it during the
contest: `sudo systemctl stop nscd`.

## Firefox (snap) updated itself mid-contest

`setup` runs `snap refresh --hold`. On old snapd versions that doesn't work,
so run `sudo snap refresh --hold=72h firefox` before the contest.

## I edited `/var/lib/contest-env/...` by hand and it was overwritten

Those files are generated. Edit `/etc/contest-env/*` instead, then run
`sudo cmanager reload`.

## Remove everything

```bash
sudo ./uninstall.sh            # keeps config + snapshots
sudo ./uninstall.sh --purge    # removes them too
```
