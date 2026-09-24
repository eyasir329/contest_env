#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Unit tests for contest-env. No root required; root-only checks (nft -c,
# squid -k parse) run automatically when possible and are skipped otherwise.
#
#   ./tests/run.sh          (or: make test)
# -----------------------------------------------------------------------------
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

export NO_COLOR=1
export CM_ETC_DIR="$TMP/etc" CM_STATE_DIR="$TMP/state" CM_LOG_DIR="$TMP/log"
mkdir -p "$CM_ETC_DIR" "$CM_STATE_DIR"
cp -r "$ROOT/config/." "$CM_ETC_DIR/"

# shellcheck source=/dev/null
for l in common firewall proxy lockdown browser editor setup reset contest status discover legacy; do
  source "$ROOT/lib/$l.sh"
done
cm_load_config

pass=0 fail=0 skip=0
ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }
skp()  { skip=$((skip + 1)); printf '  skip  %s\n' "$1"; }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
yes()  { if "${@:2}" >/dev/null; then ok "$1"; else bad "$1"; fi; }
no()   { if "${@:2}" >/dev/null; then bad "$1"; else ok "$1"; fi; }

echo "normalisation"
eq "URL with path"          "$(cm_normalize_entry 'https://www.Codeforces.com/contest/1')" "codeforces.com"
eq "wildcard"               "$(cm_normalize_entry '*.atcoder.jp')" "atcoder.jp"
eq "leading dot"            "$(cm_normalize_entry '.toph.co')" "toph.co"
eq "domain with port"       "$(cm_normalize_entry 'vjudge.net:443')" "vjudge.net"
eq "IPv4 with port"         "$(cm_normalize_entry '192.168.0.10:8080')" "192.168.0.10"
eq "CIDR kept"              "$(cm_normalize_entry '10.20.0.0/16')" "10.20.0.0/16"
eq "IPv6 kept"              "$(cm_normalize_entry 'fd00::1')" "fd00::1"

echo "validation"
yes "domain ok"             cm_is_domain codeforces.com
yes "idn ok"                cm_is_domain xn--80ak6aa92e.com
yes "new gTLD ok"           cm_is_domain notebooklm.google
no  "no TLD rejected"       cm_is_domain localhost
no  "underscore rejected"   cm_is_domain 'bad_domain.com'
yes "IPv4 ok"               cm_is_ipv4 192.168.1.1
yes "CIDR ok"               cm_is_ipv4 10.0.0.0/8
no  "IPv4 octet > 255"      cm_is_ipv4 300.1.1.1
no  "CIDR > 32"             cm_is_ipv4 10.0.0.0/33
yes "IPv6 ok"               cm_is_ipv6 2001:db8::/32

echo "allowlist expansion"
cat > "$CM_ETC_DIR/whitelist.txt" <<'EOF'
# comment
@codeforces
@codeforces          # duplicate include
https://atcoder.jp/contests/abc300   # URL form
192.168.0.10
10.20.0.0/16
not a domain!
@doesnotexist
EOF
out="$(cm_expand_whitelist 2>"$TMP/err")"
yes "profile expanded"       grep -qx 'domain codeforces.com' <<< "$out"
yes "nested @common expanded" grep -qx 'domain challenges.cloudflare.com' <<< "$out"
yes "URL normalised"         grep -qx 'domain atcoder.jp' <<< "$out"
yes "IP kept"                grep -qx 'ipv4 192.168.0.10' <<< "$out"
yes "CIDR kept"              grep -qx 'ipv4 10.20.0.0/16' <<< "$out"
eq  "no duplicates"          "$(sort <<< "$out" | uniq -d | wc -l)" "0"
yes "invalid line reported"  grep -q "invalid allowlist entry" "$TMP/err"
yes "unknown profile reported" grep -q "unknown site profile" "$TMP/err"

echo "domain collapsing"
eq "sub-domains dropped" "$(printf 'x.a.com\na.com\nb.com\ny.x.a.com\nab.com\n' | cm_collapse_domains | paste -sd' ')" "a.com ab.com b.com"

echo "AI / risky overlap"
yes "exact AI match"         cm_domain_overlaps chatgpt.com "$CM_AI_DENYLIST_FILE"
yes "AI sub-domain"          cm_domain_overlaps api.openai.com "$CM_AI_DENYLIST_FILE"
yes "parent of AI domain"    cm_domain_overlaps google.com "$CM_AI_DENYLIST_FILE"
no  "judge is not AI"        cm_domain_overlaps codeforces.com "$CM_AI_DENYLIST_FILE"
yes "github is risky"        cm_domain_overlaps gist.github.com "$CM_RISKY_FILE"

echo "shipped configuration"
bad_sites=""
for f in "$CM_ETC_DIR"/sites/*.txt; do
  while IFS= read -r d; do
    [[ "$d" == @* ]] && { [[ -r "$CM_ETC_DIR/sites/${d#@}.txt" ]] || bad_sites+=" $(basename "$f"):$d"; continue; }
    cm_is_domain "$d" || cm_is_ipv4 "$d" || bad_sites+=" $(basename "$f"):$d(invalid)"
    if hit="$(cm_domain_overlaps "$d" "$CM_AI_DENYLIST_FILE")"; then bad_sites+=" $(basename "$f"):$d(AI:$hit)"; fi
    if hit="$(cm_domain_overlaps "$d" "$CM_RISKY_FILE")" && [[ "$d" == "$hit" || "$d" == *".$hit" ]]; then
      bad_sites+=" $(basename "$f"):$d(risky:$hit)"
    fi
  done < <(cm_read_list "$f")
done
eq "site profiles are valid, AI-free and risk-free" "${bad_sites:-none}" "none"
bad_ai="$(cm_read_list "$CM_AI_DENYLIST_FILE" | while read -r d; do cm_is_domain "$d" || echo "$d"; done)"
eq "AI denylist entries are valid domains" "${bad_ai:-none}" "none"
cp "$ROOT/config/whitelist.txt" "$CM_ETC_DIR/whitelist.txt"
eq "default allowlist expands cleanly" "$(cm_expand_whitelist 2>&1 >/dev/null | wc -l)" "0"

for ex in "$ROOT"/examples/whitelist-*.txt; do
  eq "example $(basename "$ex") expands cleanly" "$(cm_expand_whitelist "$ex" 2>&1 >/dev/null | wc -l)" "0"
done
cp "$ROOT"/examples/sites/*.txt "$CM_ETC_DIR/sites/"
printf '@my-iupc-2026\n' > "$TMP/custom.txt"
eq "example custom profile expands cleanly" "$(cm_expand_whitelist "$TMP/custom.txt" 2>&1 >/dev/null | wc -l)" "0"
yes "example custom profile includes its judge IP" grep -qx 'ipv4 192.168.10.5' <<< "$(cm_expand_whitelist "$TMP/custom.txt" 2>/dev/null)"

echo "firewall ruleset"
printf '@codeforces\n192.168.0.10\n10.20.0.0/16\nfd00::/8\n' > "$CM_ETC_DIR/whitelist.txt"
fw="$(cm_fw_render "$(id -un)")"
yes "matches the user's uid"   grep -q "meta skuid $(id -u) jump contestant" <<< "$fw"
yes "IPv4 set populated"       grep -q "elements = { 10.20.0.0/16,192.168.0.10 }" <<< "$fw"
yes "IPv6 set populated"       grep -q "elements = { fd00::/8 }" <<< "$fw"
yes "DNS rejected"             grep -q "udp dport { 53, 853 }" <<< "$fw"
yes "default reject"           grep -q "reject with icmpx admin-prohibited" <<< "$fw"
printf '@codeforces\n' > "$CM_ETC_DIR/whitelist.txt"
fw_empty="$(cm_fw_render "$(id -un)")"
no  "no empty elements block"  grep -q "elements = {  }" <<< "$fw_empty"
if [[ $EUID -eq 0 ]] && command -v nft >/dev/null; then
  for r in "$fw" "$fw_empty"; do
    if nft -c -f - <<< "$r" >/dev/null 2>"$TMP/nft.err"; then ok "nft accepts ruleset"; else bad "nft accepts ruleset" "$(head -3 "$TMP/nft.err")"; fi
  done
else
  skp "nft -c (needs root + nftables)"
fi

echo "browser policies"
printf '@codeforces\n192.168.0.10\n' > "$CM_ETC_DIR/whitelist.txt"
if command -v python3 >/dev/null; then
  for gen in _cm_chromium_ai_off_json _cm_chromium_proxy_json "_cm_firefox_json 0" "_cm_firefox_json 1" _cm_vscode_settings_json; do
    if $gen | python3 -m json.tool >/dev/null 2>"$TMP/json.err"; then ok "valid JSON: $gen"; else bad "valid JSON: $gen" "$(head -2 "$TMP/json.err")"; fi
  done
  eq "Chrome bypass list = allowlisted IPs" "$(_cm_chromium_proxy_json | python3 -c 'import json,sys;print(json.load(sys.stdin)["ProxySettings"]["ProxyBypassList"])')" "192.168.0.10"
  eq "Firefox proxy only in contest mode" "$(_cm_firefox_json 0 | python3 -c 'import json,sys;print("Proxy" in json.load(sys.stdin)["policies"])')" "False"
else
  skp "JSON checks (python3 missing)"
fi

echo "proxy configuration"
if [[ $EUID -eq 0 ]] && cm_squid_bin >/dev/null && getent passwd proxy >/dev/null; then
  printf '@codeforces\n192.168.0.10\n' > "$CM_ETC_DIR/whitelist.txt"
  if (cm_proxy_render) >"$TMP/sq.out" 2>&1; then ok "squid -k parse accepts config"; else bad "squid -k parse accepts config" "$(tail -3 "$TMP/sq.out")"; fi
  yes "AI denylist checked first" bash -c "grep -n '^http_access' '$CM_SQUID_CONF' | head -1 | grep -q ai_deny"
  yes "no DNS before allowlist"   bash -c "awk '/^http_access/{print}' '$CM_SQUID_CONF' | awk '/!allow_dom/{a=NR} /to_localhost/{b=NR} END{exit !(a && b && a<b)}'"
  printf '192.168.0.10\n' > "$CM_ETC_DIR/whitelist.txt"
  if (cm_proxy_render) >"$TMP/sq.out" 2>&1; then ok "IP-only allowlist renders"; else bad "IP-only allowlist renders" "$(tail -3 "$TMP/sq.out")"; fi
else
  skp "squid config parse (needs root + squid)"
fi

echo
echo "passed: $pass   failed: $fail   skipped: $skip"
(( fail == 0 ))
