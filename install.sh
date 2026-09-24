#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install.sh — install / upgrade contest-env (cmanager) on this machine.
#
#   sudo ./install.sh              install or upgrade
#
# Code     → /usr/local/lib/contest-env      (replaced on every upgrade)
# Command  → /usr/local/bin/cmanager
# Config   → /etc/contest-env                (your edits are never overwritten)
# State    → /var/lib/contest-env            (generated rules, snapshots)
# Logs     → /var/log/contest-env
#
# Upgrading from the old IP-based version is automatic: its services, iptables
# chains and udev/polkit files are removed and its allowlist is merged in.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREFIX=/usr/local/lib/contest-env
ETC=/etc/contest-env

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./install.sh" >&2; exit 1; }
(( BASH_VERSINFO[0] >= 4 )) || { echo "bash >= 4 required" >&2; exit 1; }
[[ -r /etc/debian_version ]] || echo "Warning: only Debian/Ubuntu are supported" >&2
[[ -d /run/systemd/system ]] || echo "Warning: systemd is not running — contest mode needs it" >&2

echo "== Installing contest-env from $SRC =="

# 1. Code (clean copy so removed files do not linger)
rm -rf "$PREFIX.new"
install -d -m 0755 "$PREFIX.new" "$PREFIX.new/bin" "$PREFIX.new/lib" "$PREFIX.new/systemd" "$PREFIX.new/docs"
install -m 0755 "$SRC/bin/cmanager" "$PREFIX.new/bin/cmanager"
install -m 0644 "$SRC"/lib/*.sh "$PREFIX.new/lib/"
install -m 0644 "$SRC"/systemd/* "$PREFIX.new/systemd/"
install -m 0644 "$SRC"/README.md "$PREFIX.new/"
install -m 0644 "$SRC"/docs/*.md "$PREFIX.new/docs/" 2>/dev/null || true
rm -rf "$PREFIX.old"; [[ -d "$PREFIX" ]] && mv "$PREFIX" "$PREFIX.old"
mv "$PREFIX.new" "$PREFIX"; rm -rf "$PREFIX.old"
ln -sfn "$PREFIX/bin/cmanager" /usr/local/bin/cmanager
echo "✔ Code installed to $PREFIX, command: cmanager"

# 2. Configuration
install -d -m 0755 "$ETC" "$ETC/sites"
for f in contest.conf whitelist.txt; do            # admin-owned: never overwrite
  if [[ -e "$ETC/$f" ]]; then
    cmp -s "$SRC/config/$f" "$ETC/$f" || install -m 0644 "$SRC/config/$f" "$ETC/$f.dist"
  else
    install -m 0644 "$SRC/config/$f" "$ETC/$f"
  fi
done
for f in ai-denylist.txt risky-domains.txt blocked-apps.txt; do   # shipped data: refreshed
  install -m 0644 "$SRC/config/$f" "$ETC/$f"
  [[ -e "$ETC/${f%.txt}.local.txt" ]] || printf '# Local additions to %s (kept across upgrades)\n' "$f" > "$ETC/${f%.txt}.local.txt"
done
install -m 0644 "$SRC"/config/sites/*.txt "$ETC/sites/"   # shipped profiles refreshed, custom ones kept
install -m 0644 "$SRC/config/logrotate.conf" /etc/logrotate.d/contest-env
echo "✔ Configuration in $ETC  (existing contest.conf / whitelist.txt kept; new defaults saved as *.dist)"

# 3. State / logs
install -d -m 0755 /var/lib/contest-env /var/log/contest-env

# 4. systemd units
if [[ -d /etc/systemd/system ]]; then
  install -m 0644 "$SRC"/systemd/* /etc/systemd/system/
  systemctl daemon-reload 2>/dev/null || true
  echo "✔ systemd units installed (enabled only while contest mode is on)"
fi

# 5. Previous IP-based version
/usr/local/bin/cmanager _legacy-cleanup || echo "Warning: legacy cleanup reported a problem" >&2

# 6. Apply fixes to an already-active contest mode after an upgrade
if [[ -s /var/lib/contest-env/restricted ]]; then
  echo "Contest mode is active — re-applying with the new version..."
  /usr/local/bin/cmanager restrict "$(head -n1 /var/lib/contest-env/restricted)"
fi

cat <<'EOF'

Installed. Next steps:
  sudo cmanager setup                  # software + contest account + snapshot (needs Internet)
  sudo nano /etc/contest-env/whitelist.txt   # or: sudo cmanager add @codeforces
  sudo cmanager restrict               # contest mode ON
  sudo cmanager verify                 # prove it
See README.md and docs/CONTEST-DAY.md.
EOF
