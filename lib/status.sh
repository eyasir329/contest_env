# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: status.sh
# 'status' = what is configured;  'verify' = prove it, by running real
# connections AS the contest user and checking each one succeeds/fails as
# it should. Run 'verify' before every contest.
# -----------------------------------------------------------------------------

_cm_row() { printf '  %-22s %s\n' "$1" "$2"; }
_cm_yes() { printf '%s%s%s' "$_C_GREEN" "$1" "$_C_RESET"; }
_cm_no()  { printf '%s%s%s' "$_C_RED" "$1" "$_C_RESET"; }
_cm_meh() { printf '%s%s%s' "$_C_YELLOW" "$1" "$_C_RESET"; }

cm_cmd_status() {
  local user ruser since n
  user="$1"
  ruser="$(cm_restricted_user || true)"
  cm_header "contest-env status"
  if [[ -n "$ruser" ]]; then
    since="$(sed -n 2p "$CM_RESTRICTED_MARK" 2>/dev/null)"
    _cm_row "Contest mode" "$(_cm_yes ON) for '$ruser' (since ${since:-?})"
    user="$ruser"
  else
    _cm_row "Contest mode" "$(_cm_meh OFF)"
  fi
  if id "$user" >/dev/null 2>&1; then
    _cm_row "Contest user" "$user (uid $(id -u "$user"))"
  else
    _cm_row "Contest user" "$(_cm_no "'$user' does not exist")"
  fi

  if [[ $EUID -ne 0 ]]; then
    echo; cm_warn "Run with sudo for firewall/proxy details."; return 0
  fi

  if cm_fw_active; then _cm_row "Firewall (nftables)" "$(_cm_yes active)"
  else _cm_row "Firewall (nftables)" "$([[ -n $ruser ]] && _cm_no MISSING || echo inactive)"; fi

  if cm_proxy_active; then
    n="$(grep -c . "$CM_SQUID_DIR/allow-domains.acl" 2>/dev/null || echo 0)"
    _cm_row "Proxy (squid)" "$(_cm_yes active) on 127.0.0.1:${PROXY_PORT}, $n domain rule(s), SNI check $(if grep -q ssl-bump "$CM_SQUID_CONF" 2>/dev/null; then _cm_yes on; else _cm_meh off; fi)"
  else
    _cm_row "Proxy (squid)" "$([[ -n $ruser ]] && _cm_no DOWN || echo inactive)"
  fi
  _cm_row "Guard timer" "$(systemctl is-active contest-guard.timer 2>/dev/null || true)"
  _cm_row "USB storage" "$([[ -f $CM_MODPROBE_FILE ]] && _cm_yes blocked || echo allowed)"
  _cm_row "Phones (MTP/PTP)" "$([[ -f $CM_UDEV_FILE ]] && grep -q '"06"' "$CM_UDEV_FILE" && _cm_yes blocked || echo allowed)"
  _cm_row "Mounting / optical" "$([[ -f $CM_POLKIT_RULES || -f $CM_POLKIT_PKLA ]] && _cm_yes blocked || echo allowed)"
  _cm_row "DNS for user" "$([[ -f $CM_DBUS_POLICY ]] && _cm_yes blocked || echo allowed)"
  _cm_row "AI programs blocked" "$( [[ -s $CM_APP_ACL_STATE ]] && wc -l < "$CM_APP_ACL_STATE" || echo 0 ) path(s)"

  local d pol=""
  while IFS= read -r d; do
    [[ -f "$d/contest-env-ai-off.json" ]] && pol+="$(basename "$(dirname "$(dirname "$d")")")(ai-off$([[ -f "$d/contest-env-proxy.json" ]] && echo ",proxy")) "
  done < <(cm_chromium_policy_dirs)
  grep -qs '"GenerativeAI"' /etc/firefox/policies/policies.json && pol+="firefox(ai-off$(grep -qs '"Proxy"' /etc/firefox/policies/policies.json && echo ",proxy")) "
  _cm_row "Browser policies" "${pol:-$(_cm_no none)}"

  if [[ -f "$CM_SNAPSHOT_DIR/$user.taken" ]]; then
    _cm_row "Home snapshot" "$(cat "$CM_SNAPSHOT_DIR/$user.taken")"
  else
    _cm_row "Home snapshot" "$(_cm_meh none) (sudo cmanager snapshot $user)"
  fi

  local risky; risky="$(id "$user" >/dev/null 2>&1 && cm_user_risky_groups "$user")"
  [[ -n "$risky" ]] && cm_warn "'$user' is in privileged groups: $risky"
  if systemctl is-active --quiet nscd 2>/dev/null; then cm_warn "nscd is running: it resolves names for every user — stop it during contests"; fi
  cm_ai_inventory_warnings
  echo
  echo "Allowlist: $(cm_expand_whitelist 2>/dev/null | wc -l) effective entries (cmanager list)"
}

# --- verify -----------------------------------------------------------------
_cm_verify_fail=0
_cm_check() {  # _cm_check EXPECT(ok|fail) DESCRIPTION -- command...
  local expect="$1" desc="$2" rc=0; shift 3
  "$@" >/dev/null 2>&1 || rc=$?
  if { [[ "$expect" == ok && $rc -eq 0 ]] || [[ "$expect" == fail && $rc -ne 0 ]]; }; then
    printf '  %sPASS%s  %s\n' "$_C_GREEN" "$_C_RESET" "$desc"
  else
    printf '  %sFAIL%s  %s\n' "$_C_RED" "$_C_RESET" "$desc"
    _cm_verify_fail=1
  fi
}

# curl as the contest user; success = any HTTP response from the origin
# (-k: this tests the network path, not the site's certificate).
_cm_as_user_curl() {
  local user="$1"; shift
  runuser -u "$user" -- env -i PATH=/usr/bin:/bin HOME=/tmp \
    curl -sk -o /dev/null --max-time 12 -w '%{http_code}' "$@" | grep -qv '^000$'
}

cm_cmd_verify() {
  local user sample proxy="http://127.0.0.1:${PROXY_PORT}"
  cm_require_root verify
  cm_is_restricted || cm_die "Contest mode is off — run 'sudo cmanager restrict' first"
  user="$(cm_restricted_user)"
  cm_have curl || cm_die "curl is required for verify"
  sample="$(cm_read_list "$CM_WHITELIST_FILE" | grep -v '^@' | grep -vE '^[0-9.:/]+$' | head -n1 || true)"
  if [[ -z "$sample" ]]; then
    local site; site="$(cm_read_list "$CM_WHITELIST_FILE" | grep '^@' | head -n1 | tr -d @)"
    [[ -n "$site" ]] && sample="$(cm_read_list "$CM_SITES_DIR/$site.txt" | grep -v '^@' | head -n1)"
  fi

  cm_header "Verifying contest mode as '$user'"
  _cm_verify_fail=0
  _cm_check ok   "services: firewall table loaded"            -- cm_fw_active
  _cm_check ok   "services: proxy running"                    -- cm_proxy_active
  if [[ -n "$sample" ]]; then
    _cm_check ok "allowed site reachable via proxy (https://$sample)" -- _cm_as_user_curl "$user" -x "$proxy" "https://$sample/"
  fi
  _cm_check fail "other site blocked (https://example.com)"   -- _cm_as_user_curl "$user" -x "$proxy" https://example.com/
  _cm_check fail "search blocked (https://www.google.com)"    -- _cm_as_user_curl "$user" -x "$proxy" https://www.google.com/
  _cm_check fail "AI blocked (https://chatgpt.com)"           -- _cm_as_user_curl "$user" -x "$proxy" https://chatgpt.com/
  _cm_check fail "AI blocked (https://gemini.google.com)"     -- _cm_as_user_curl "$user" -x "$proxy" https://gemini.google.com/
  _cm_check fail "AI blocked (https://claude.ai)"             -- _cm_as_user_curl "$user" -x "$proxy" https://claude.ai/
  _cm_check fail "direct connection blocked (https://1.1.1.1)" -- _cm_as_user_curl "$user" --noproxy '*' https://1.1.1.1/
  _cm_check fail "public DNS blocked (8.8.8.8:53)"            -- runuser -u "$user" -- timeout 6 bash -c 'exec 3<>/dev/tcp/8.8.8.8/53'
  _cm_check fail "local DNS blocked (getent hosts example.com)" -- runuser -u "$user" -- timeout 8 getent hosts example.com
  if [[ "$BLOCK_USB_STORAGE" == 1 ]]; then
    _cm_check ok "USB storage driver refused"                 -- grep -q '^install usb_storage /bin/false' "$CM_MODPROBE_FILE"
  fi
  echo
  if (( _cm_verify_fail )); then
    cm_err "Some checks FAILED — do not start the contest on this machine yet."
    return 1
  fi
  cm_ok "All checks passed — this machine is contest-ready."
}
