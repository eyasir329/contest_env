# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: legacy.sh
# Remove what the previous version of this repository (the IP-based
# "contest-manager") installed, and carry its allowlist over.
# Called by install.sh; safe to run when nothing legacy is present.
# -----------------------------------------------------------------------------

CM_LEGACY_ETC="/usr/local/etc/contest-restriction"

cm_legacy_present() {
  [[ -d /usr/local/share/contest-manager || -d "$CM_LEGACY_ETC" || -e /usr/local/bin/update-contest-whitelist ]] \
    || compgen -G '/etc/systemd/system/contest-restrict-*' >/dev/null
}

cm_legacy_cleanup() {
  cm_legacy_present || return 0
  cm_header "Removing the previous (IP-based) contest-manager"
  local unit rule chain backup="$CM_STATE_DIR/legacy-backup"

  for unit in /etc/systemd/system/contest-restrict-*.service /etc/systemd/system/contest-restrict-*.timer; do
    [[ -e "$unit" ]] || continue
    systemctl disable --now "$(basename "$unit")" >/dev/null 2>&1 || true
    rm -f "$unit"
  done
  systemctl daemon-reload 2>/dev/null || true

  local ipt
  for ipt in iptables ip6tables; do
    cm_have "$ipt" || continue
    # OUTPUT jumps into CONTEST_<USER>_OUT chains
    while IFS= read -r rule; do
      # shellcheck disable=SC2086
      "$ipt" ${rule/-A OUTPUT/-D OUTPUT} 2>/dev/null || true
    done < <("$ipt" -S OUTPUT 2>/dev/null | grep -E -- '-j CONTEST_[A-Z0-9_-]+_OUT' || true)
    while IFS= read -r chain; do
      "$ipt" -F "$chain" 2>/dev/null || true
      "$ipt" -X "$chain" 2>/dev/null || true
    done < <("$ipt" -S 2>/dev/null | awk '$1=="-N" && $2 ~ /^CONTEST_/ {print $2}')
  done

  rm -f /usr/local/bin/update-contest-whitelist \
        /etc/modprobe.d/contest-usb-storage-blacklist.conf \
        /etc/polkit-1/rules.d/99-contest-block-mount.rules \
        /etc/udev/rules.d/99-contest-block-usb.rules
  if cm_have udevadm; then udevadm control --reload-rules 2>/dev/null || true; fi

  if [[ -d "$CM_LEGACY_ETC" ]]; then
    mkdir -p "$backup"
    cp -a "$CM_LEGACY_ETC/." "$backup/" 2>/dev/null || true
    if [[ -s "$CM_LEGACY_ETC/whitelist.txt" ]]; then
      local current migrated d
      current="$(cm_read_list "$CM_WHITELIST_FILE")"
      migrated="$(cm_read_list "$CM_LEGACY_ETC/whitelist.txt" | while IFS= read -r d; do
          d="$(cm_normalize_entry "$d")"
          grep -qxF "$d" <<< "$current" || echo "$d"
        done)"
      if [[ -n "$migrated" ]]; then
        printf '\n# --- Migrated from the previous version (%s) ---\n%s\n' \
          "$CM_LEGACY_ETC/whitelist.txt" "$migrated" >> "$CM_WHITELIST_FILE"
      fi
    fi
    rm -rf "$CM_LEGACY_ETC"
    cm_ok "Old allowlist merged into $CM_WHITELIST_FILE (backup: $backup)"
  fi
  rm -rf /usr/local/share/contest-manager
  [[ -L /usr/local/bin/cmanager && "$(readlink /usr/local/bin/cmanager)" == /usr/local/share/contest-manager/* ]] \
    && rm -f /usr/local/bin/cmanager
  if compgen -G '/opt/*_backup/*_home' >/dev/null; then
    cm_warn "Old home backups remain in /opt/*_backup — delete them once you have a new snapshot (cmanager snapshot)"
  fi
  cm_ok "Previous version removed"
}
