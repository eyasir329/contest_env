#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# uninstall.sh — remove contest-env from this machine.
#
#   sudo ./uninstall.sh            turn contest mode off, remove code, units,
#                                  browser policies; KEEP config + snapshots
#   sudo ./uninstall.sh --purge    also delete /etc/contest-env,
#                                  /var/lib/contest-env and /var/log/contest-env
#
# Installed software (compilers, editors, browsers) and the contest user
# account are left alone.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./uninstall.sh" >&2; exit 1; }
PURGE=0; [[ "${1:-}" == --purge ]] && PURGE=1
PREFIX=/usr/local/lib/contest-env

if [[ -x "$PREFIX/bin/cmanager" ]]; then
  if [[ -s /var/lib/contest-env/restricted ]]; then
    "$PREFIX/bin/cmanager" unrestrict "$(head -n1 /var/lib/contest-env/restricted)"
  fi
  # Remove the permanent (AI-off) browser policies as well.
  bash -c "source '$PREFIX/lib/common.sh'; source '$PREFIX/lib/browser.sh'; cm_load_config; cm_browser_purge" || true
fi

for u in contest-guard.timer contest-guard.service contest-firewall.service contest-proxy.service; do
  systemctl disable --now "$u" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/$u"
done
systemctl daemon-reload 2>/dev/null || true
nft delete table inet contest_env 2>/dev/null || true

[[ "$(readlink /usr/local/bin/cmanager 2>/dev/null)" == "$PREFIX/bin/cmanager" ]] && rm -f /usr/local/bin/cmanager
rm -rf "$PREFIX" /etc/logrotate.d/contest-env
echo "✔ contest-env removed"

if (( PURGE )); then
  rm -rf /etc/contest-env /var/lib/contest-env /var/log/contest-env
  echo "✔ Configuration, snapshots and logs deleted"
else
  echo "Kept: /etc/contest-env (config), /var/lib/contest-env (snapshots), /var/log/contest-env"
fi
