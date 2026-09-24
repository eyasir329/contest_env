# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: common.sh
# Shared helpers: logging, paths, configuration, allowlist parsing, state.
# Sourced by bin/cmanager; never executed directly.
# -----------------------------------------------------------------------------

# --- Paths (overridable through the environment, which the test-suite uses) --
CM_ETC_DIR="${CM_ETC_DIR:-/etc/contest-env}"
CM_STATE_DIR="${CM_STATE_DIR:-/var/lib/contest-env}"
CM_LOG_DIR="${CM_LOG_DIR:-/var/log/contest-env}"
CM_RUN_DIR="${CM_RUN_DIR:-/run/contest-env}"
CM_SYSTEMD_DIR="${CM_SYSTEMD_DIR:-/etc/systemd/system}"

CM_CONF_FILE="$CM_ETC_DIR/contest.conf"
CM_WHITELIST_FILE="$CM_ETC_DIR/whitelist.txt"
CM_SITES_DIR="$CM_ETC_DIR/sites"
CM_AI_DENYLIST_FILE="$CM_ETC_DIR/ai-denylist.txt"
CM_RISKY_FILE="$CM_ETC_DIR/risky-domains.txt"
CM_BLOCKED_APPS_FILE="$CM_ETC_DIR/blocked-apps.txt"

CM_RESTRICTED_MARK="$CM_STATE_DIR/restricted"      # contains the restricted user name
CM_APP_ACL_STATE="$CM_STATE_DIR/app-acl.list"      # paths we denied for the user
CM_SNAPSHOT_DIR="$CM_STATE_DIR/snapshots"

CM_NFT_TABLE="contest_env"
CM_NFT_FILE="$CM_STATE_DIR/firewall.nft"

# --- Logging -----------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _C_RESET=$'\e[0m' _C_BOLD=$'\e[1m' _C_RED=$'\e[31m' _C_GREEN=$'\e[32m'
  _C_YELLOW=$'\e[33m' _C_BLUE=$'\e[34m' _C_DIM=$'\e[2m'
else
  _C_RESET="" _C_BOLD="" _C_RED="" _C_GREEN="" _C_YELLOW="" _C_BLUE="" _C_DIM=""
fi

cm_header() { printf '\n%s== %s ==%s\n' "$_C_BOLD" "$*" "$_C_RESET"; }
cm_step()   { printf '%s→%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }
cm_ok()     { printf '%s✔%s %s\n' "$_C_GREEN" "$_C_RESET" "$*"; }
cm_warn()   { printf '%s!%s %s\n' "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
cm_err()    { printf '%s✘%s %s\n' "$_C_RED" "$_C_RESET" "$*" >&2; }
cm_dim()    { printf '%s%s%s\n' "$_C_DIM" "$*" "$_C_RESET"; }
cm_die()    { cm_err "$*"; exit 1; }

# Append an audit line (who did what, when) — best effort, root only.
cm_audit() {
  [[ $EUID -eq 0 ]] || return 0
  mkdir -p "$CM_LOG_DIR" 2>/dev/null || return 0
  printf '%s  %-8s %s\n' "$(date '+%F %T')" "${SUDO_USER:-root}" "$*" \
    >> "$CM_LOG_DIR/cmanager.log" 2>/dev/null || true
}

cm_require_root() {
  [[ $EUID -eq 0 ]] || cm_die "This command must be run as root (use: sudo cmanager $*)"
}

cm_have() { command -v "$1" >/dev/null 2>&1; }

# Ask a yes/no question; returns 0 for yes. Non-interactive => default answer.
cm_confirm() {
  local prompt="$1" default="${2:-n}" reply
  if [[ "${CM_ASSUME_YES:-0}" == 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then [[ "$default" == y ]]; return; fi
  read -r -p "$prompt [$([[ $default == y ]] && echo Y/n || echo y/N)] " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# --- Configuration -----------------------------------------------------------
# Defaults; /etc/contest-env/contest.conf overrides them.
cm_load_config() {
  CONTEST_USER="participant"
  PROXY_PORT=3128
  SNI_ENFORCE="auto"
  BLOCK_USB_STORAGE=1
  BLOCK_MTP=1
  BLOCK_OPTICAL_AND_MOUNTS=1
  BLOCK_BLUETOOTH=1
  BLOCK_AI_APPS=1
  DENY_DNS=1
  INSTALL_CHROME=1
  INSTALL_FIREFOX=1
  INSTALL_VSCODE=1
  INSTALL_SUBLIME=1
  INSTALL_CODEBLOCKS=1
  INSTALL_GEANY=1
  INSTALL_OFFLINE_DOCS=1
  EXTRA_PACKAGES=""
  VSCODE_EXTENSIONS="ms-vscode.cpptools ms-python.python redhat.java"
  DISABLE_AUTO_UPDATES=1
  # shellcheck source=/dev/null
  [[ -r "$CM_CONF_FILE" ]] && source "$CM_CONF_FILE"
  return 0
}

# Resolve the target user: explicit argument > config default.
cm_target_user() {
  local u="${1:-$CONTEST_USER}"
  [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || cm_die "Invalid user name: '$u'"
  printf '%s\n' "$u"
}

cm_require_user() {
  id "$1" >/dev/null 2>&1 || cm_die "User '$1' does not exist (run: sudo cmanager setup $1)"
  [[ "$(id -u "$1")" -ne 0 ]] || cm_die "Refusing to restrict root"
}

# --- Allowlist parsing -------------------------------------------------------
# Normalise one raw token (URL, domain, IP, CIDR) to its canonical form.
cm_normalize_entry() {
  local e="$1"
  e="${e,,}"                       # lower-case
  e="${e#http://}"; e="${e#https://}"
  # keep "/NN" on CIDR ranges, strip URL paths from everything else
  if [[ ! "$e" =~ ^[0-9a-f.:]+/[0-9]{1,3}$ ]]; then e="${e%%/*}"; fi
  e="${e#\*.}"; e="${e#.}"         # "*.x.com" / ".x.com" -> "x.com"
  e="${e#www.}"                    # www. is covered by subdomain matching
  # strip :port for domains and IPv4 (leave IPv6 alone)
  if [[ "$e" != *:*:* ]]; then e="${e%%:*}"; fi
  printf '%s\n' "$e"
}

cm_is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(/([0-9]|[12][0-9]|3[0-2]))?$ ]] || return 1
  local i; for i in 1 2 3 4; do (( BASH_REMATCH[i] <= 255 )) || return 1; done
}
cm_is_ipv6()   { [[ "$1" =~ ^[0-9a-f:]+:[0-9a-f:.]*(/([0-9]{1,3}))?$ ]]; }
cm_is_domain() { [[ "$1" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,63}|xn--[a-z0-9-]{1,59})$ ]]; }

# Print the effective allowlist, one "<kind> <value>" per line
# (kind = domain|ipv4|ipv6), expanding "@site" includes. Invalid lines are
# reported on stderr and skipped. Output is de-duplicated.
cm_expand_whitelist() {
  local file="${1:-$CM_WHITELIST_FILE}"
  [[ -r "$file" ]] || cm_die "Allowlist not found: $file"
  declare -A _seen_sites=()
  _cm_expand_file "$file" 0 | sort -u
}

_cm_expand_file() {
  local file="$1" depth="$2" line raw entry site
  (( depth <= 3 )) || { cm_warn "include depth exceeded in $file"; return 0; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    raw="${line%%#*}"                                   # strip comments
    raw="${raw//[[:space:]]/}"
    [[ -z "$raw" ]] && continue
    if [[ "$raw" == @* ]]; then
      site="${raw#@}"
      [[ "$site" =~ ^[a-z0-9_-]+$ ]] || { cm_warn "bad include '$raw' in $file"; continue; }
      [[ -n "${_seen_sites[$site]:-}" ]] && continue
      _seen_sites[$site]=1
      if [[ -r "$CM_SITES_DIR/$site.txt" ]]; then
        _cm_expand_file "$CM_SITES_DIR/$site.txt" $((depth + 1))
      else
        cm_warn "unknown site profile '@$site' (no $CM_SITES_DIR/$site.txt)"
      fi
      continue
    fi
    entry="$(cm_normalize_entry "$raw")"
    if   cm_is_ipv4 "$entry";   then echo "ipv4 $entry"
    elif cm_is_ipv6 "$entry";   then echo "ipv6 $entry"
    elif cm_is_domain "$entry"; then echo "domain $entry"
    else cm_warn "ignoring invalid allowlist entry '$raw' ($file)"
    fi
  done < "$file"
}

# Domains only, with redundant sub-domains removed (a.com covers x.a.com).
# Squid refuses overlapping dstdomain entries, so this matters.
cm_collapse_domains() {
  awk '{ print length($0) "\t" $0 }' | sort -n -k1,1 -k2,2 | cut -f2 | awk '
    {
      d = $0; covered = 0; n = split(d, p, ".")
      for (i = 2; i < n; i++) {
        parent = p[i]; for (j = i + 1; j <= n; j++) parent = parent "." p[j]
        if (parent in keep) { covered = 1; break }
      }
      if (!covered && !(d in keep)) { keep[d] = 1; print d }
    }' | sort
}

# Plain list readers for the simple one-item-per-line config files.
# cm_read_list lower-cases (domains); cm_read_list_raw keeps case (paths).
cm_read_list_raw() {
  [[ -r "$1" ]] || return 0
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | awk 'NF'
}
cm_read_list() { cm_read_list_raw "$1" | tr '[:upper:]' '[:lower:]'; }

# Same, plus the admin's own additions in "<name>.local.txt" (never
# overwritten by upgrades).
cm_read_list_merged() {
  cm_read_list "$1"
  cm_read_list "${1%.txt}.local.txt"
}

# Is DOMAIN equal to / a sub-domain of / a parent of any entry in FILE?
# Prints the matching entry. Used to warn about AI + "risky" domains.
cm_domain_overlaps() {
  local domain="$1" file="$2" d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    if [[ "$domain" == "$d" || "$domain" == *".$d" || "$d" == *".$domain" ]]; then
      echo "$d"; return 0
    fi
  done < <(cm_read_list_merged "$file")
  return 1
}

# --- State -------------------------------------------------------------------
cm_restricted_user() { [[ -r "$CM_RESTRICTED_MARK" ]] && head -n1 "$CM_RESTRICTED_MARK"; }
cm_is_restricted()   { [[ -s "$CM_RESTRICTED_MARK" ]]; }

cm_write_file() {  # cm_write_file PATH MODE  (content from stdin, atomic)
  local path="$1" mode="${2:-0644}" tmp
  mkdir -p "$(dirname "$path")"
  tmp="$(mktemp "${path}.XXXXXX")"
  cat > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

cm_systemd_available() { [[ -d /run/systemd/system ]]; }
