# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: setup.sh
# One-time (idempotent) preparation of a lab PC:
#   toolchains, editors, browsers, offline docs, the enforcement tools
#   (nftables, squid-openssl, acl), the contest account, baseline AI-off
#   policies, and a clean home snapshot used by 'reset'.
# Needs Internet access; run it BEFORE 'restrict'.
# -----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive
CM_APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

cm_os_id()   ( . /etc/os-release 2>/dev/null; echo "${ID:-unknown}" )
cm_arch()    { dpkg --print-architecture 2>/dev/null || uname -m; }

cm_apt_has() { apt-cache show "$1" >/dev/null 2>&1; }

cm_apt_install() {   # all-or-nothing
  apt-get install "${CM_APT_OPTS[@]}" "$@"
}

cm_apt_install_each() {   # best effort, one by one
  local p failed=()
  for p in "$@"; do
    if dpkg -s "$p" >/dev/null 2>&1; then continue; fi
    if cm_apt_has "$p" && apt-get install "${CM_APT_OPTS[@]}" "$p" >/dev/null 2>&1; then
      cm_dim "  installed $p"
    else
      failed+=("$p")
    fi
  done
  (( ${#failed[@]} == 0 )) || cm_warn "Not available / failed (skipped): ${failed[*]}"
  return 0
}

cm_download() {  # cm_download URL DEST
  curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
}

# --- Packages ---------------------------------------------------------------
cm_setup_packages() {
  cm_header "Packages"
  cm_step "apt-get update"
  apt-get update -q || cm_warn "apt-get update reported errors (continuing)"

  # Enforcement tooling first: without these 'restrict' cannot work.
  local squid_pkg=squid-openssl
  cm_apt_has squid-openssl || squid_pkg=squid
  cm_apt_install ca-certificates curl gnupg acl rsync nftables openssl "$squid_pkg" \
    || cm_die "Could not install the core packages (nftables/squid/acl)"
  [[ "$squid_pkg" == squid ]] && cm_warn "squid-openssl unavailable: SNI enforcement will be off"
  # We run our own proxy instance; the distribution's default one must not run.
  systemctl disable --now squid.service >/dev/null 2>&1 || true

  cm_step "Compilers, interpreters, debuggers"
  cm_apt_install build-essential gcc g++ gdb make python3 default-jdk \
    || cm_die "Could not install the compiler toolchain"
  cm_apt_install_each clang pypy3 valgrind

  cm_step "Editors and terminals"
  local editors=(vim neovim nano xterm)
  [[ "$INSTALL_CODEBLOCKS" == 1 ]] && editors+=(codeblocks)
  [[ "$INSTALL_GEANY" == 1 ]] && editors+=(geany)
  cm_apt_install_each "${editors[@]}"

  if [[ "$INSTALL_OFFLINE_DOCS" == 1 ]]; then
    cm_step "Offline documentation"
    cm_apt_install_each cppreference-doc-en-html python3-doc
  fi
  # shellcheck disable=SC2086
  [[ -n "${EXTRA_PACKAGES// }" ]] && cm_apt_install_each $EXTRA_PACKAGES

  [[ "$INSTALL_FIREFOX" == 1 ]] && cm_setup_firefox
  [[ "$INSTALL_CHROME"  == 1 ]] && cm_setup_chrome
  [[ "$INSTALL_VSCODE"  == 1 ]] && cm_setup_vscode
  [[ "$INSTALL_SUBLIME" == 1 ]] && cm_setup_sublime
  return 0
}

cm_setup_firefox() {
  cm_have firefox && { cm_dim "  Firefox already installed"; return 0; }
  cm_step "Firefox"
  if [[ "$(cm_os_id)" == debian ]]; then cm_apt_install_each firefox-esr
  else cm_apt_install_each firefox; fi
}

cm_setup_chrome() {
  cm_have google-chrome && { cm_dim "  Google Chrome already installed"; return 0; }
  [[ "$(cm_arch)" == amd64 ]] || { cm_warn "Google Chrome is amd64-only — skipped"; return 0; }
  cm_step "Google Chrome"
  local deb; deb="$(mktemp --suffix=.deb)"
  if cm_download "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" "$deb"; then
    chmod 0644 "$deb"
    cm_apt_install "$deb" >/dev/null || cm_warn "Google Chrome installation failed"
  else
    cm_warn "Could not download Google Chrome"
  fi
  rm -f "$deb"
}

cm_setup_vscode() {
  cm_have code && { cm_dim "  VS Code already installed"; return 0; }
  local arch vsarch deb
  arch="$(cm_arch)"
  case "$arch" in amd64) vsarch=x64 ;; arm64) vsarch=arm64 ;; armhf) vsarch=armhf ;;
    *) cm_warn "VS Code: unsupported architecture $arch — skipped"; return 0 ;; esac
  cm_step "Visual Studio Code"
  # Pre-answer the package's "add Microsoft repository?" question so it
  # does not create a second, conflicting apt source.
  echo "code code/add-microsoft-repo boolean true" | debconf-set-selections 2>/dev/null || true
  deb="$(mktemp --suffix=.deb)"
  if cm_download "https://update.code.visualstudio.com/latest/linux-deb-$vsarch/stable" "$deb"; then
    chmod 0644 "$deb"
    cm_apt_install "$deb" >/dev/null || cm_warn "VS Code installation failed"
  else
    cm_warn "Could not download VS Code"
  fi
  rm -f "$deb"
}

cm_setup_sublime() {
  cm_have subl && { cm_dim "  Sublime Text already installed"; return 0; }
  cm_step "Sublime Text"
  install -d -m 0755 /etc/apt/keyrings
  if cm_download https://download.sublimetext.com/sublimehq-pub.gpg /etc/apt/keyrings/sublimehq-pub.asc; then
    chmod 0644 /etc/apt/keyrings/sublimehq-pub.asc
    echo "deb [signed-by=/etc/apt/keyrings/sublimehq-pub.asc] https://download.sublimetext.com/ apt/stable/" \
      > /etc/apt/sources.list.d/sublime-text.list
    apt-get update -q >/dev/null 2>&1 || true
    cm_apt_install_each sublime-text
  else
    cm_warn "Could not download the Sublime Text signing key — skipped"
  fi
}

# --- Updates ----------------------------------------------------------------
cm_setup_disable_updates() {
  [[ "$DISABLE_AUTO_UPDATES" == 1 ]] || return 0
  cm_header "Automatic updates"
  local u
  for u in apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service; do
    systemctl disable --now "$u" >/dev/null 2>&1 || true
  done
  if cm_have snap; then
    snap refresh --hold >/dev/null 2>&1 \
      || cm_warn "Could not hold snap refreshes (old snapd) — Firefox may auto-update mid-contest"
  fi
  cm_ok "Background apt/snap updates disabled"
}

# --- Account ----------------------------------------------------------------
cm_setup_user() {
  local user="$1" password="${2:-}"
  cm_header "Contest account '$user'"
  if id "$user" >/dev/null 2>&1; then
    cm_ok "User '$user' exists (kept; use 'cmanager reset' to clean the home directory)"
  else
    useradd --create-home --shell /bin/bash --comment "Contest participant" "$user"
    cm_ok "Created user '$user'"
    if [[ -n "$password" ]]; then
      echo "$user:$password" | chpasswd
    elif [[ -t 0 ]]; then
      echo "Set the password contestants will use to log in as '$user':"
      passwd "$user"
    else
      cm_warn "No password set for '$user' (use: sudo passwd $user)"
    fi
  fi
  cm_groups_harden "$user"
  loginctl disable-linger "$user" >/dev/null 2>&1 || true
  chmod 0750 "$(getent passwd "$user" | cut -d: -f6)"
}

cm_setup_user_profile() {
  local user="$1" home group
  home="$(getent passwd "$user" | cut -d: -f6)"
  group="$(id -gn "$user")"
  cm_header "User profile"
  if cm_have code || [[ "$INSTALL_VSCODE" == 1 ]]; then
    cm_vscode_configure "$user"
    cm_vscode_install_extensions "$user"
    cm_ok "VS Code: AI features off, extension allowlist set"
  fi
  install -d -o "$user" -g "$group" "$home/contest"
  cm_ok "Workspace folder: $home/contest"
}

# --- Entry point ------------------------------------------------------------
cm_cmd_setup() {
  local user="$1" password="${2:-}" skip_packages="${3:-0}"
  cm_require_root setup
  [[ -r /etc/debian_version ]] || cm_die "Only Debian/Ubuntu (apt) systems are supported"
  if cm_is_restricted; then
    cm_die "Contest mode is active — run 'sudo cmanager unrestrict' first (setup needs Internet access)"
  fi
  cm_audit "setup user=$user"
  [[ "$skip_packages" == 1 ]] || cm_setup_packages
  cm_setup_disable_updates
  cm_setup_user "$user" "$password"
  cm_setup_user_profile "$user"
  cm_header "Browser policies"
  cm_browser_baseline_apply
  cm_header "Home snapshot"
  cm_snapshot_take "$user"
  cm_header "Done"
  cm_ok "Lab PC is prepared for '$user'."
  echo "Next: edit $CM_WHITELIST_FILE, then 'sudo cmanager restrict' and 'sudo cmanager verify'."
}
