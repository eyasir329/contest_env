# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: editor.sh
# Code-editor defaults for the contest user: VS Code AI features off, only
# the allowlisted extensions may run, no telemetry / update / marketplace
# prompts. (Copilot & co. also cannot reach their servers - the firewall
# and proxy block them - this removes the UI and any local fallback.)
# -----------------------------------------------------------------------------

_cm_vscode_settings_json() {
  local ext allowed=""
  for ext in $VSCODE_EXTENSIONS ms-python.vscode-pylance ms-python.debugpy; do
    allowed+="${allowed:+, }\"${ext,,}\": true"
  done
  cat <<EOF
{
  "chat.disableAIFeatures": true,
  "chat.commandCenter.enabled": false,
  "chat.agent.enabled": false,
  "chat.mcp.enabled": false,
  "github.copilot.enable": { "*": false },
  "github.copilot.editor.enableAutoCompletions": false,
  "github.copilot.nextEditSuggestions.enabled": false,
  "inlineChat.enabled": false,
  "workbench.settings.enableNaturalLanguageSearch": false,
  "extensions.allowed": { ${allowed} },
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "extensions.ignoreRecommendations": true,
  "update.mode": "none",
  "telemetry.telemetryLevel": "off",
  "workbench.enableExperiments": false,
  "workbench.startupEditor": "none",
  "workbench.tips.enabled": false,
  "python.experiments.enabled": false,
  "redhat.telemetry.enabled": false,
  "security.workspace.trust.enabled": false
}
EOF
}

# Write (or merge into) ~/.config/Code/User/settings.json for USER.
cm_vscode_configure() {
  local user="$1" home dir file
  home="$(getent passwd "$user" | cut -d: -f6)"
  dir="$home/.config/Code/User"; file="$dir/settings.json"
  install -d -o "$user" -g "$(id -gn "$user")" "$home/.config" "$home/.config/Code" "$dir"
  if [[ -s "$file" ]] && cm_have python3; then
    # Merge: our keys win, the user's other keys are kept.
    _cm_vscode_settings_json | python3 -c '
import json, sys
ours = json.load(sys.stdin)
path = sys.argv[1]
try:
    with open(path) as f: cur = json.load(f)
except Exception:
    cur = {}
cur.update(ours)
with open(path, "w") as f: json.dump(cur, f, indent=2); f.write("\n")
' "$file"
  else
    _cm_vscode_settings_json > "$file"
  fi
  chown "$user:$(id -gn "$user")" "$file"
  chmod 0644 "$file"
}

cm_vscode_install_extensions() {
  local user="$1" ext code_bin
  code_bin="$(command -v code || true)"
  [[ -n "$code_bin" ]] || return 0
  for ext in $VSCODE_EXTENSIONS; do
    if runuser -u "$user" -- "$code_bin" --list-extensions 2>/dev/null | grep -qix "$ext"; then
      cm_dim "  VS Code extension $ext already installed"
    else
      cm_step "Installing VS Code extension $ext"
      timeout 180 runuser -u "$user" -- "$code_bin" --install-extension "$ext" --force >/dev/null 2>&1 \
        || cm_warn "Could not install VS Code extension $ext"
    fi
  done
}
