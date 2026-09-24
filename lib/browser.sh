# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: browser.sh
# Enterprise policies for Chromium-family browsers and Firefox.
#
#  * Baseline ("ai-off", permanent from 'setup' until uninstall):
#      built-in AI features off (Gemini, Help-me-write, Tab organiser,
#      DevTools AI, Firefox AI chatbot/sidebar, local AI models), no
#      extensions, no DNS-over-HTTPS / QUIC / ECH, no sync or sign-in.
#  * Contest ("proxy", only while restricted):
#      browser forced through the local allowlist proxy, no search engine.
# Policies are machine-wide and cannot be changed by the contest user.
# -----------------------------------------------------------------------------

# Chromium-family managed-policy directories (created only if the browser is present).
cm_chromium_policy_dirs() {
  local pair dir probe
  for pair in \
    "/etc/opt/chrome/policies/managed:/opt/google/chrome" \
    "/etc/chromium/policies/managed:/usr/lib/chromium" \
    "/etc/chromium-browser/policies/managed:/snap/chromium" \
    "/etc/brave/policies/managed:/opt/brave.com" \
    "/etc/opt/edge/policies/managed:/opt/microsoft/msedge"; do
    dir="${pair%%:*}"; probe="${pair#*:}"
    [[ -e "$probe" || -d "$dir" ]] && echo "$dir"
  done
  return 0
}

cm_firefox_policy_files() {
  echo "/etc/firefox/policies/policies.json"          # all Linux builds, incl. snap
  local d
  for d in /usr/lib/firefox/distribution /usr/lib/firefox-esr/distribution /opt/firefox/distribution; do
    [[ -d "$(dirname "$d")" ]] && echo "$d/policies.json"
  done
  return 0
}

# IP entries of the allowlist, for the proxy bypass list (direct, firewall-allowed).
_cm_bypass_ips() { cm_expand_whitelist | awk '$1=="ipv4"||$1=="ipv6"{print $2}'; }

_cm_chromium_ai_off_json() {
  cat <<'EOF'
{
  "GenAiDefaultSettings": 2,
  "GeminiSettings": 1,
  "GenAILocalFoundationalModelSettings": 1,
  "HelpMeWriteSettings": 2,
  "TabOrganizerSettings": 2,
  "TabCompareSettings": 2,
  "HistorySearchSettings": 2,
  "CreateThemesSettings": 2,
  "DevToolsGenAiSettings": 2,
  "AutofillPredictionSettings": 2,
  "LensOverlaySettings": 1,
  "LensRegionSearchEnabled": false,
  "LensDesktopNTPSearchEnabled": false,
  "BraveAIChatEnabled": false,
  "HubsSidebarEnabled": false,
  "ExtensionInstallBlocklist": ["*"],
  "BrowserSignin": 0,
  "SyncDisabled": true,
  "PasswordManagerEnabled": false,
  "MetricsReportingEnabled": false,
  "BackgroundModeEnabled": false,
  "DnsOverHttpsMode": "off",
  "BuiltInDnsClientEnabled": false,
  "EncryptedClientHelloEnabled": false,
  "QuicAllowed": false,
  "PromotionalTabsEnabled": false
}
EOF
}

_cm_chromium_proxy_json() {
  local bypass
  bypass="$(_cm_bypass_ips | paste -sd';' -)"
  cat <<EOF
{
  "ProxySettings": {
    "ProxyMode": "fixed_servers",
    "ProxyServer": "127.0.0.1:${PROXY_PORT}",
    "ProxyBypassList": "${bypass}"
  },
  "DefaultSearchProviderEnabled": false,
  "SearchSuggestEnabled": false,
  "AlternateErrorPagesEnabled": false,
  "WebRtcIPHandling": "disable_non_proxied_udp"
}
EOF
}

# Firefox reads ONE policies.json, so baseline and contest parts are merged here.
_cm_firefox_json() {
  local contest="$1" passthrough
  passthrough="$(_cm_bypass_ips | paste -sd, -)"
  cat <<'EOF'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableFirefoxAccounts": true,
    "PasswordManagerEnabled": false,
    "DNSOverHTTPS": { "Enabled": false, "Locked": true },
    "GenerativeAI": { "Enabled": false, "Chatbot": false, "LinkPreviews": false, "TabGroups": false, "Locked": true },
    "ExtensionSettings": { "*": { "installation_mode": "blocked" } },
EOF
  if [[ "$contest" == 1 ]]; then
    cat <<EOF
    "Proxy": {
      "Mode": "manual",
      "HTTPProxy": "127.0.0.1:${PROXY_PORT}",
      "UseHTTPProxyForAllProtocols": true,
      "Passthrough": "${passthrough}",
      "Locked": true
    },
    "SearchSuggestEnabled": false,
EOF
  fi
  cat <<EOF
    "Preferences": {
      "browser.ml.enable":                  { "Value": false, "Status": "locked" },
      "browser.ml.chat.enabled":            { "Value": false, "Status": "locked" },
      "browser.ml.chat.sidebar":            { "Value": false, "Status": "locked" },
      "browser.ml.chat.shortcuts":          { "Value": false, "Status": "locked" },
      "browser.ml.chat.page":               { "Value": false, "Status": "locked" },
      "browser.ml.linkPreview.enabled":     { "Value": false, "Status": "locked" },
      "browser.ml.pageAssist.enabled":      { "Value": false, "Status": "locked" },
      "browser.tabs.groups.smart.enabled":  { "Value": false, "Status": "locked" },
      "extensions.ml.enabled":              { "Value": false, "Status": "locked" },
      "network.trr.mode":                   { "Value": 5,     "Status": "locked" },
      "network.dns.echconfig.enabled":      { "Value": false, "Status": "locked" },
      "network.http.http3.enable":          { "Value": false, "Status": "locked" },
      "keyword.enabled":                    { "Value": $([[ "$contest" == 1 ]] && echo false || echo true), "Status": "locked" }
    }
  }
}
EOF
}

_cm_firefox_write() {
  local contest="$1" f
  while IFS= read -r f; do
    mkdir -p "$(dirname "$f")"
    # Keep a one-time copy of a policies.json that we did not write.
    if [[ -f "$f" && ! -f "$f.contest-env.orig" ]] && ! grep -q '"GenerativeAI"' "$f"; then
      cp -p "$f" "$f.contest-env.orig"
    fi
    _cm_firefox_json "$contest" | cm_write_file "$f" 0644
  done < <(cm_firefox_policy_files)
}

# Baseline: AI off. Safe to call repeatedly.
cm_browser_baseline_apply() {
  local d
  while IFS= read -r d; do
    _cm_chromium_ai_off_json | cm_write_file "$d/contest-env-ai-off.json" 0644
  done < <(cm_chromium_policy_dirs)
  # Keep the contest proxy part if we are currently restricted.
  if cm_is_restricted; then _cm_firefox_write 1; else _cm_firefox_write 0; fi
  cm_ok "Browser AI features disabled by policy (Chrome/Chromium/Brave/Edge/Firefox)"
}

cm_browser_contest_apply() {
  local d
  cm_browser_baseline_apply >/dev/null
  while IFS= read -r d; do
    _cm_chromium_proxy_json | cm_write_file "$d/contest-env-proxy.json" 0644
  done < <(cm_chromium_policy_dirs)
  _cm_firefox_write 1
  cm_ok "Browsers locked to the contest proxy (restart open browsers)"
}

cm_browser_contest_remove() {
  local d
  while IFS= read -r d; do rm -f "$d/contest-env-proxy.json"; done < <(cm_chromium_policy_dirs)
  _cm_firefox_write 0
}

# Uninstall: remove everything we wrote, restore any original Firefox policy.
cm_browser_purge() {
  local d f
  while IFS= read -r d; do rm -f "$d/contest-env-ai-off.json" "$d/contest-env-proxy.json"; done < <(cm_chromium_policy_dirs)
  while IFS= read -r f; do
    if [[ -f "$f.contest-env.orig" ]]; then mv -f "$f.contest-env.orig" "$f"
    else rm -f "$f"; fi
  done < <(cm_firefox_policy_files)
}
