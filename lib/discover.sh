# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: discover.sh
# Find the extra hosts a contest site loads (CDNs, captcha, fonts...).
#
#   cmanager discover URL...   Load each URL in headless Chrome/Chromium,
#                              record every host it contacts (Chrome net-log)
#                              and classify it against the allowlist.
#   cmanager denied            During a mock contest: what did the proxy refuse?
#
# Nothing is added automatically: you review the list and 'cmanager add'
# what is legitimate. That review step is deliberate — auto-allowing
# whatever a page loads is how search engines and AI widgets slip in.
# -----------------------------------------------------------------------------

cm_find_chromium() {
  local b
  for b in google-chrome google-chrome-stable chromium chromium-browser; do
    cm_have "$b" && { command -v "$b"; return 0; }
  done
  return 1
}

# Is HOST covered by the current allowlist domains?
_cm_host_allowed() {
  local host="$1" d
  while IFS= read -r d; do
    [[ "$host" == "$d" || "$host" == *".$d" ]] && return 0
  done <<< "$_CM_ALLOWED_DOMAINS"
  return 1
}

cm_cmd_discover() {
  local browser tmp url host label hosts
  cm_require_root discover
  (( $# > 0 )) || cm_die "Usage: sudo cmanager discover https://contest.example.com/contest/123 ..."
  browser="$(cm_find_chromium)" || cm_die "Needs Google Chrome or Chromium (install with 'cmanager setup')"
  cm_is_restricted && cm_warn "Contest mode is ON: blocked hosts are still recorded, but hosts they would load next are not. Prefer running this with contest mode off."

  _CM_ALLOWED_DOMAINS="$(cm_expand_whitelist | awk '$1=="domain"{print $2}')"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  for url in "$@"; do
    [[ "$url" == http*://* ]] || url="https://$url"
    cm_step "Loading $url (up to 45 s)"
    rm -rf "$tmp/profile"
    timeout 45 "$browser" --headless=new --no-sandbox --disable-gpu --no-first-run \
      --user-data-dir="$tmp/profile" --log-net-log="$tmp/net-$RANDOM.json" \
      --virtual-time-budget=20000 --dump-dom "$url" >/dev/null 2>&1 || true
  done

  hosts="$(cat "$tmp"/net-*.json 2>/dev/null \
    | grep -oE '"(url|host|origin)":"[^"]+"' \
    | sed -E 's/^"[a-z]+":"//; s/"$//; s#^[a-z]+://##; s#[/?].*$##; s/:[0-9]+$//' \
    | tr '[:upper:]' '[:lower:]' | grep -E '^[a-z0-9.-]+\.[a-z]{2,}$' | sort -u)"
  [[ -n "$hosts" ]] || cm_die "No network activity recorded (is the machine online?)"

  cm_header "Hosts contacted"
  while IFS= read -r host; do
    if cm_domain_overlaps "$host" "$CM_AI_DENYLIST_FILE" >/dev/null; then
      label="$(_cm_no 'AI      ')  (always blocked)"
    elif _cm_host_allowed "$host"; then
      label="$(_cm_yes 'allowed ')"
    elif cm_domain_overlaps "$host" "$CM_RISKY_FILE" >/dev/null; then
      label="$(_cm_meh 'risky   ')  (search/code/social - think twice)"
    else
      label="$(_cm_meh 'NEW     ')  → sudo cmanager add $host"
    fi
    printf '  %s %s\n' "$label" "$host"
  done <<< "$hosts"
  echo
  echo "Tip: log in and open a problem + the submit page during a mock run, then check 'sudo cmanager denied'."
}

cm_cmd_denied() {
  cm_require_root denied
  cm_header "Refused by the proxy (most recent ${1:-5000} log lines)"
  local out; out="$(cm_proxy_denied "${1:-5000}")"
  if [[ -z "$out" ]]; then echo "  nothing refused"; else echo "$out"; fi
  echo
  echo "Legitimate ones (a CDN or captcha the contest site needs): sudo cmanager add HOST"
}
