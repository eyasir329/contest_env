# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: contest.sh
# Contest mode on/off, hot reload, allowlist editing and the self-healing
# guard. Order of 'restrict': proxy first (so allowed sites keep working),
# then the firewall (which makes the proxy the only way out), then devices,
# apps and browsers. 'unrestrict' is the exact reverse and never prompts.
# -----------------------------------------------------------------------------

CM_UNITS_BOOT=(contest-proxy.service contest-firewall.service contest-guard.timer)

cm_cmd_restrict() {
  local user="$1" prev
  cm_require_root restrict
  cm_require_user "$user"
  prev="$(cm_restricted_user || true)"
  if [[ -n "$prev" && "$prev" != "$user" ]]; then
    cm_die "Contest mode is active for '$prev'. Run 'sudo cmanager unrestrict $prev' first."
  fi
  cm_have nft || cm_die "nftables missing — run 'sudo cmanager setup' first"
  cm_squid_bin >/dev/null || cm_die "Squid missing — run 'sudo cmanager setup' first"
  [[ -r "$CM_WHITELIST_FILE" ]] || cm_die "Allowlist missing: $CM_WHITELIST_FILE"
  cm_systemd_available || cm_die "systemd is required"

  cm_audit "restrict user=$user"
  cm_header "Contest mode ON for '$user'"
  if cm_user_logged_in "$user"; then
    cm_warn "'$user' is logged in: open connections will break; restart the browser after this."
  fi

  cm_step "Allowlist"
  cm_expand_whitelist | awk '{printf "   %-7s %s\n", $1, $2}'

  cm_step "Proxy";      cm_proxy_render; cm_proxy_start
  cm_step "Firewall";   cm_fw_apply "$user"
  cm_step "Resolver";   cm_resolver_apply "$user"; cm_ok "No DNS for '$user' (proxy resolves names)"
  cm_step "Devices";    cm_media_apply "$user"; cm_bluetooth_apply
  cm_step "Programs";   cm_apps_apply "$user"; cm_ai_inventory_warnings
  cm_step "Accounts";   cm_groups_harden "$user"
  cm_step "Browsers";   cm_browser_contest_apply

  echo "$user" > "$CM_RESTRICTED_MARK"
  date '+%F %T' >> "$CM_RESTRICTED_MARK"
  systemctl daemon-reload
  systemctl enable "${CM_UNITS_BOOT[@]}" >/dev/null 2>&1 || cm_warn "Could not enable boot units"
  systemctl start contest-firewall.service contest-guard.timer >/dev/null 2>&1 || true

  cm_header "Contest mode is ON"
  echo "  User      : $user"
  echo "  Internet  : allowlist only, via 127.0.0.1:${PROXY_PORT}  ($CM_WHITELIST_FILE)"
  echo "  Survives  : reboots (systemd) and is self-healing (guard timer, every minute)"
  echo "  Next      : sudo cmanager verify     # proves it works, as '$user'"
}

cm_cmd_unrestrict() {
  local user="$1" cur
  cm_require_root unrestrict
  cur="$(cm_restricted_user || true)"
  [[ -n "$cur" && "$cur" != "$user" ]] && cm_warn "Contest mode was recorded for '$cur' — cleaning up '$cur'" && user="$cur"
  id "$user" >/dev/null 2>&1 || cm_die "User '$user' not found"

  cm_audit "unrestrict user=$user"
  cm_header "Contest mode OFF for '$user'"
  rm -f "$CM_RESTRICTED_MARK"
  systemctl disable --now contest-guard.timer contest-guard.service >/dev/null 2>&1 || true
  systemctl disable contest-firewall.service >/dev/null 2>&1 || true
  cm_fw_remove;                        cm_ok "Firewall removed"
  systemctl stop contest-firewall.service >/dev/null 2>&1 || true
  cm_proxy_stop;                       cm_ok "Proxy stopped"
  cm_browser_contest_remove;           cm_ok "Browser proxy policy removed (AI-off baseline stays)"
  cm_resolver_remove "$user";          cm_ok "Name resolution restored"
  cm_media_remove;                     cm_ok "USB storage / phones / optical / mounting allowed"
  cm_bluetooth_remove
  cm_apps_remove "$user";              cm_ok "Program blocks removed"
  echo
  cm_ok "Contest mode is OFF. The allowlist and snapshots were kept."
}

# Re-read the allowlist and apply it without touching anything else.
cm_cmd_reload() {
  local user
  cm_require_root reload
  cm_is_restricted || { cm_proxy_render >/dev/null; cm_ok "Allowlist is valid (contest mode is off — nothing to reload)"; return 0; }
  user="$(cm_restricted_user)"
  cm_audit "reload user=$user"
  cm_proxy_reload
  cm_fw_apply "$user"
  cm_browser_contest_apply >/dev/null
  cm_ok "New allowlist is live for '$user'"
}

# --- Allowlist editing ------------------------------------------------------
cm_cmd_add() {
  local force="$1"; shift
  local raw entry hit changed=0
  cm_require_root add
  (( $# > 0 )) || cm_die "Usage: sudo cmanager add [--force] DOMAIN|IP|CIDR|@site ..."
  for raw in "$@"; do
    if [[ "$raw" == @* ]]; then
      [[ "$raw" =~ ^@[a-z0-9_-]+$ ]] || { cm_err "Bad profile name '$raw'"; continue; }
      [[ -r "$CM_SITES_DIR/${raw#@}.txt" ]] || { cm_err "Unknown site profile '$raw' (see: cmanager sites)"; continue; }
      entry="$raw"
      # Enable a commented-out "#@site" line if present, else append.
      if grep -qxE "#[[:space:]]*${raw}[[:space:]]*" "$CM_WHITELIST_FILE"; then
        sed -i -E "s/^#[[:space:]]*${raw}[[:space:]]*$/${raw}/" "$CM_WHITELIST_FILE"
        cm_ok "Enabled $raw"; changed=1; continue
      fi
    else
      entry="$(cm_normalize_entry "$raw")"
      cm_is_domain "$entry" || cm_is_ipv4 "$entry" || cm_is_ipv6 "$entry" \
        || { cm_err "Not a domain, IP or CIDR: '$raw'"; continue; }
      if hit="$(cm_domain_overlaps "$entry" "$CM_AI_DENYLIST_FILE")"; then
        if [[ "$entry" == "$hit" || "$entry" == *".$hit" ]]; then
          cm_err "$entry is an AI service ($hit) — it is always blocked"; continue
        fi
        cm_warn "$entry contains AI service $hit — that part stays blocked"
      fi
      if hit="$(cm_domain_overlaps "$entry" "$CM_RISKY_FILE")" && [[ "$entry" == "$hit" || "$entry" == *".$hit" ]]; then
        if [[ "$force" != 1 ]]; then
          cm_err "$entry is on the risky list ($hit: search/code-sharing/messaging). Use --force if you are sure."
          continue
        fi
        cm_warn "Adding risky domain $entry (--force)"
      fi
    fi
    if cm_read_list "$CM_WHITELIST_FILE" | grep -qxF "$entry"; then
      cm_dim "  $entry already in the allowlist"; continue
    fi
    echo "$entry" >> "$CM_WHITELIST_FILE"
    cm_ok "Added $entry"; changed=1
  done
  (( changed )) || return 0
  cm_audit "add $*"
  if cm_is_restricted; then cm_cmd_reload; fi
}

cm_cmd_remove() {
  local raw entry changed=0
  cm_require_root remove
  (( $# > 0 )) || cm_die "Usage: sudo cmanager remove DOMAIN|IP|@site ..."
  for raw in "$@"; do
    if [[ "$raw" == @* ]]; then
      [[ "$raw" =~ ^@[a-z0-9_-]+$ ]] || { cm_err "Bad profile name '$raw'"; continue; }
      entry="$raw"
    else
      entry="$(cm_normalize_entry "$raw")"
    fi
    if grep -qxF "$entry" "$CM_WHITELIST_FILE"; then
      if [[ "$entry" == @* ]]; then   # keep the line, commented out, for easy re-enabling
        { sed "s|^${entry}\$|#${entry}|" "$CM_WHITELIST_FILE"; } | cm_write_file "$CM_WHITELIST_FILE" 0644
      else
        { grep -vxF "$entry" "$CM_WHITELIST_FILE" || true; } | cm_write_file "$CM_WHITELIST_FILE" 0644
      fi
      cm_ok "Removed $entry"; changed=1
    else
      cm_warn "$entry is not a line of $CM_WHITELIST_FILE (it may come from a @site profile)"
    fi
  done
  (( changed )) || return 0
  cm_audit "remove $*"
  if cm_is_restricted; then cm_cmd_reload; fi
}

cm_cmd_list() {
  echo "Allowlist file: $CM_WHITELIST_FILE"
  echo
  echo "Effective domains (each includes its sub-domains):"
  cm_expand_whitelist | awk '$1=="domain"{print $2}' | cm_collapse_domains | sed 's/^/  /'
  local ips; ips="$(cm_expand_whitelist | awk '$1!="domain"{print "  " $2}')"
  if [[ -n "$ips" ]]; then echo; echo "Direct IPs / ranges:"; echo "$ips"; fi
  echo
  echo "Always blocked: $(cm_read_list_merged "$CM_AI_DENYLIST_FILE" | wc -l) AI domains ($CM_AI_DENYLIST_FILE)"
}

cm_cmd_sites() {
  local f name desc state
  echo "Site profiles in $CM_SITES_DIR  (enable: sudo cmanager add @name)"
  echo
  for f in "$CM_SITES_DIR"/*.txt; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f" .txt)"
    desc="$(grep -m1 '^#' "$f" | sed 's/^#[[:space:]]*//')"
    if cm_read_list "$CM_WHITELIST_FILE" | grep -qxF "@$name"; then state="[on] "; else state="[   ]"; fi
    printf '  %s %-12s %s\n' "$state" "@$name" "$desc"
  done
}

# --- Guard (run every minute by contest-guard.timer) ------------------------
cm_cmd_guard() {
  local user
  cm_is_restricted || return 0
  user="$(cm_restricted_user)"
  cm_fw_ensure
  if ! cm_proxy_active; then
    systemctl restart "$CM_PROXY_UNIT" && cm_warn "Proxy was down — restarted"
  fi
  cm_resolver_socket_acl "$user"
  if [[ "$BLOCK_BLUETOOTH" == 1 ]] && cm_have rfkill; then rfkill block bluetooth 2>/dev/null || true; fi
  return 0
}
