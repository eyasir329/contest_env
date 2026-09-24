# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: reset.sh
# Clean-home snapshots. 'snapshot' records the pristine home directory;
# 'reset' makes the home directory identical to it again (new files,
# browser profiles, shell history, dot-files: all gone) and removes the
# user's traces elsewhere (/tmp, cron, at, lingering sessions).
# Reset does NOT change contest mode: a restricted machine stays restricted.
# -----------------------------------------------------------------------------

cm_snapshot_path() { echo "$CM_SNAPSHOT_DIR/$1"; }

cm_snapshot_take() {
  local user="$1" home snap
  home="$(getent passwd "$user" | cut -d: -f6)"
  snap="$(cm_snapshot_path "$user")"
  [[ -d "$home" ]] || cm_die "Home directory of '$user' not found"
  cm_have rsync || cm_die "rsync is missing (apt-get install rsync, or run setup without --skip-packages)"
  install -d -m 0700 "$CM_SNAPSHOT_DIR"
  mkdir -p "$snap"
  rsync -aHAX --delete --numeric-ids "$home/" "$snap/"
  date '+%F %T' > "$CM_SNAPSHOT_DIR/$user.taken"
  cm_ok "Snapshot of $home saved ($(du -sh "$snap" 2>/dev/null | cut -f1)) → $snap"
}

cm_user_logged_in() { pgrep -u "$1" >/dev/null 2>&1; }

cm_cmd_reset() {
  local user="$1" force="${2:-0}" home snap
  cm_require_root reset
  cm_require_user "$user"
  home="$(getent passwd "$user" | cut -d: -f6)"
  snap="$(cm_snapshot_path "$user")"
  [[ -d "$snap" ]] || cm_die "No snapshot for '$user'. Create one on a clean account: sudo cmanager snapshot $user"

  if cm_user_logged_in "$user"; then
    if [[ "$force" == 1 ]]; then
      cm_step "Logging '$user' out"
      loginctl terminate-user "$user" 2>/dev/null || true
      sleep 2
      pkill -KILL -u "$user" 2>/dev/null || true
      sleep 1
    else
      cm_die "'$user' is logged in / has running processes. Log out first, or use: sudo cmanager reset --force"
    fi
  fi
  cm_audit "reset user=$user"

  cm_step "Restoring $home from snapshot ($(cat "$CM_SNAPSHOT_DIR/$user.taken" 2>/dev/null || echo 'unknown date'))"
  rsync -aHAX --delete --numeric-ids "$snap/" "$home/"

  cm_step "Removing the user's files outside home"
  find /tmp /var/tmp /dev/shm -xdev -user "$user" -delete 2>/dev/null || true
  crontab -r -u "$user" 2>/dev/null || true
  if cm_have atq; then
    atq 2>/dev/null | awk -v u="$user" '$NF==u{print $1}' | xargs -r atrm 2>/dev/null || true
  fi
  loginctl disable-linger "$user" 2>/dev/null || true
  rm -f "/var/spool/cron/crontabs/$user" "/var/mail/$user" 2>/dev/null || true

  # Re-apply per-user settings that live in the home directory.
  if cm_have code; then cm_vscode_configure "$user"; fi

  cm_ok "'$user' reset to the clean snapshot"
  if cm_is_restricted; then cm_ok "Contest mode is still ACTIVE for '$(cm_restricted_user)'"; fi
}
