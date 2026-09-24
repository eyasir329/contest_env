# shellcheck shell=bash
# -----------------------------------------------------------------------------
# contest-env :: lockdown.sh
# Everything except the network: removable media, phones, optical drives,
# Bluetooth, name resolution side-channels and AI applications.
# Every "apply" function has a matching "remove" function.
# -----------------------------------------------------------------------------

CM_MODPROBE_FILE="/etc/modprobe.d/contest-env.conf"
CM_UDEV_FILE="/etc/udev/rules.d/99-contest-env-usb.rules"
CM_POLKIT_RULES="/etc/polkit-1/rules.d/05-contest-env.rules"
CM_POLKIT_PKLA="/etc/polkit-1/localauthority/50-local.d/contest-env.pkla"
CM_DBUS_POLICY="/etc/dbus-1/system.d/contest-env.conf"
CM_RESOLVED_VARLINK="/run/systemd/resolve/io.systemd.Resolve"

# Groups that give a desktop user extra power over hardware/system.
CM_RISKY_GROUPS="sudo admin wheel adm disk cdrom plugdev dialout lpadmin sambashare netdev lxd docker libvirt kvm bluetooth wireshark"

# --- Removable media ---------------------------------------------------------
cm_media_apply() {
  local user="$1"
  {
    echo "# contest-env: loaded only while contest mode is active"
    if [[ "$BLOCK_USB_STORAGE" == 1 ]]; then
      echo "install usb_storage /bin/false"
      echo "install uas /bin/false"
    fi
    if [[ "$BLOCK_OPTICAL_AND_MOUNTS" == 1 ]]; then
      echo "install sr_mod /bin/false"
    fi
  } | cm_write_file "$CM_MODPROBE_FILE" 0644
  local m
  for m in uas usb_storage sr_mod; do
    if grep -q "^install $m " "$CM_MODPROBE_FILE" && lsmod 2>/dev/null | grep -q "^$m "; then
      modprobe -r "$m" 2>/dev/null || cm_warn "Module $m is in use (a USB disk/DVD is mounted?) — unplug it; it will be refused after that"
    fi
  done

  if [[ "$BLOCK_USB_STORAGE" == 1 || "$BLOCK_MTP" == 1 ]]; then
    {
      echo "# contest-env: de-authorise data-carrying USB interfaces (keyboards/mice/network keep working)"
      [[ "$BLOCK_USB_STORAGE" == 1 ]] && \
        echo 'ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTR{bInterfaceClass}=="08", ATTR{authorized}="0"'
      if [[ "$BLOCK_MTP" == 1 ]]; then
        echo '# Still-image class = PTP / MTP (phones, cameras)'
        echo 'ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTR{bInterfaceClass}=="06", ATTR{authorized}="0"'
        echo '# Android MTP on a vendor-specific interface'
        echo 'ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTR{interface}=="MTP", ATTR{authorized}="0"'
        echo 'ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_MTP_DEVICE}=="1", ATTR{authorized}="0"'
      fi
    } | cm_write_file "$CM_UDEV_FILE" 0644
    if cm_have udevadm; then
      udevadm control --reload-rules 2>/dev/null || true
      udevadm trigger --action=add --subsystem-match=usb 2>/dev/null || true
    fi
  fi

  if [[ "$BLOCK_OPTICAL_AND_MOUNTS" == 1 ]]; then
    # polkit >= 0.106 (JavaScript rules): Debian 12+, Ubuntu 23.10+
    cm_write_file "$CM_POLKIT_RULES" 0644 <<EOF
// contest-env: the contest user may not mount media, change the network,
// install software or pair devices while contest mode is active.
polkit.addRule(function (action, subject) {
  if (subject.user !== "$user") return polkit.Result.NOT_HANDLED;
  var p = [ "org.freedesktop.udisks2.", "org.freedesktop.NetworkManager.",
            "org.freedesktop.packagekit.", "org.freedesktop.Flatpak.",
            "org.freedesktop.fwupd.", "org.freedesktop.ModemManager1.",
            "org.blueman." ];
  for (var i = 0; i < p.length; i++)
    if (action.id.indexOf(p[i]) === 0) return polkit.Result.NO;
  return polkit.Result.NOT_HANDLED;
});
EOF
    # polkit 0.105 (.pkla): Ubuntu 22.04 and older
    if [[ -d /etc/polkit-1/localauthority ]]; then
      cm_write_file "$CM_POLKIT_PKLA" 0644 <<EOF
[contest-env: no mounting, network changes, installs]
Identity=unix-user:$user
Action=org.freedesktop.udisks2.*;org.freedesktop.NetworkManager.*;org.freedesktop.packagekit.*;org.freedesktop.Flatpak.*;org.freedesktop.fwupd.*;org.freedesktop.ModemManager1.*;org.blueman.*
ResultAny=no
ResultInactive=no
ResultActive=no
EOF
    fi
  fi
  cm_ok "Removable media blocked (USB storage, phones/MTP, optical, mounting)"
}

cm_media_remove() {
  rm -f "$CM_MODPROBE_FILE" "$CM_UDEV_FILE" "$CM_POLKIT_RULES" "$CM_POLKIT_PKLA"
  if cm_have udevadm; then udevadm control --reload-rules 2>/dev/null || true; fi
  # Re-authorise anything that was de-authorised (replugging works too).
  local f
  for f in /sys/bus/usb/devices/*/authorized; do
    [[ -w "$f" && "$(cat "$f" 2>/dev/null)" == 0 ]] && echo 1 > "$f" 2>/dev/null
  done
  modprobe sr_mod 2>/dev/null || true
  return 0
}

# --- Bluetooth ---------------------------------------------------------------
cm_bluetooth_apply() {
  [[ "$BLOCK_BLUETOOTH" == 1 ]] || return 0
  if cm_have rfkill; then rfkill block bluetooth 2>/dev/null || true; fi
  systemctl stop bluetooth.service 2>/dev/null || true
  cm_ok "Bluetooth off"
}

cm_bluetooth_remove() {
  if cm_have rfkill; then rfkill unblock bluetooth 2>/dev/null || true; fi
  if systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
    systemctl start bluetooth.service 2>/dev/null || true
  fi
  return 0
}

# --- Name-resolution side channels ------------------------------------------
# The firewall blocks port 53, but glibc can also resolve through
# systemd-resolved over D-Bus or Varlink (resolved then does the query as a
# system user). Close both for the contest user.
cm_resolver_apply() {
  local user="$1"
  [[ "$DENY_DNS" == 1 ]] || return 0
  if [[ -d /etc/dbus-1/system.d ]]; then
    cm_write_file "$CM_DBUS_POLICY" 0644 <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<!-- contest-env: the contest user cannot ask systemd-resolved to resolve names -->
<busconfig>
  <policy user="$user">
    <deny send_destination="org.freedesktop.resolve1"/>
  </policy>
</busconfig>
EOF
    systemctl reload dbus.service 2>/dev/null || systemctl reload dbus-broker.service 2>/dev/null || true
  fi
  cm_resolver_socket_acl "$user"
}

# Re-applied by the guard timer, because resolved recreates the socket.
cm_resolver_socket_acl() {
  local user="$1"
  [[ "$DENY_DNS" == 1 && -S "$CM_RESOLVED_VARLINK" ]] || return 0
  cm_have setfacl || return 0
  getfacl -p "$CM_RESOLVED_VARLINK" 2>/dev/null | grep -q "^user:$user:---" \
    || setfacl -m "u:$user:---" "$CM_RESOLVED_VARLINK" 2>/dev/null || true
}

cm_resolver_remove() {
  local user="$1"
  if [[ -f "$CM_DBUS_POLICY" ]]; then
    rm -f "$CM_DBUS_POLICY"
    systemctl reload dbus.service 2>/dev/null || systemctl reload dbus-broker.service 2>/dev/null || true
  fi
  if [[ -S "$CM_RESOLVED_VARLINK" ]] && cm_have setfacl; then
    setfacl -x "u:$user" "$CM_RESOLVED_VARLINK" 2>/dev/null || true
  fi
  return 0
}

# --- AI / remote-access applications ----------------------------------------
# Print every existing path that blocked-apps.txt refers to (real paths).
cm_apps_targets() {
  local entry p cand
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" == /* ]]; then
      for p in $entry; do [[ -e "$p" ]] && readlink -f "$p"; done     # glob on purpose
    else
      for cand in "$(command -v "$entry" 2>/dev/null)" /usr/bin/"$entry" /usr/local/bin/"$entry" /opt/"$entry"/"$entry"; do
        [[ -n "$cand" && -e "$cand" ]] && readlink -f "$cand"
      done
    fi
  done < <(cm_read_list_raw "$CM_BLOCKED_APPS_FILE"; cm_read_list_raw "${CM_BLOCKED_APPS_FILE%.txt}.local.txt") | sort -u
}

cm_apps_apply() {
  local user="$1" t n=0
  [[ "$BLOCK_AI_APPS" == 1 ]] || return 0
  cm_have setfacl || { cm_warn "setfacl missing (install 'acl') — AI apps NOT blocked"; return 0; }
  touch "$CM_APP_ACL_STATE"; chmod 0600 "$CM_APP_ACL_STATE"
  while IFS= read -r t; do
    case "$t" in
      /usr/bin/snap|/snap/*) cm_warn "Snap app cannot be blocked per-user: $t (remove it: snap remove …)"; continue ;;
    esac
    if setfacl -m "u:$user:---" "$t" 2>/dev/null; then
      grep -qxF "$t" "$CM_APP_ACL_STATE" || echo "$t" >> "$CM_APP_ACL_STATE"
      n=$((n + 1))
    else
      cm_warn "Could not block $t (read-only filesystem?)"
    fi
  done < <(cm_apps_targets)
  if (( n > 0 )); then cm_ok "Blocked $n AI/remote-access program path(s) for '$user'"
  else cm_ok "No AI/remote-access programs found on this machine"; fi
}

cm_apps_remove() {
  local user="$1" t
  [[ -r "$CM_APP_ACL_STATE" ]] || return 0
  while IFS= read -r t; do
    [[ -e "$t" ]] && setfacl -x "u:$user" "$t" 2>/dev/null
  done < "$CM_APP_ACL_STATE"
  rm -f "$CM_APP_ACL_STATE"
  return 0
}

# --- Groups -----------------------------------------------------------------
cm_user_risky_groups() {
  local user="$1" g out=()
  for g in $(id -nG "$user"); do
    [[ " $CM_RISKY_GROUPS " == *" $g "* ]] && out+=("$g")
  done
  echo "${out[*]}"
}

cm_groups_harden() {
  local user="$1" g risky
  risky="$(cm_user_risky_groups "$user")"
  [[ -z "$risky" ]] && return 0
  for g in $risky; do gpasswd -d "$user" "$g" >/dev/null 2>&1 || true; done
  cm_ok "Removed '$user' from privileged groups: $risky (effective at next login)"
}

# Is anything AI-related installed that we cannot block per user?
cm_ai_inventory_warnings() {
  local s
  if cm_have snap; then
    s="$(snap list 2>/dev/null | awk 'NR>1{print $1}' | grep -iE 'cursor|windsurf|zed|ollama|lm-?studio|gpt4all|chatgpt|claude|copilot|jan|codeium|tabnine' || true)"
    [[ -n "$s" ]] && cm_warn "AI-related snaps installed (not blockable per user): $(echo "$s" | paste -sd' ' -)"
  fi
  if cm_have flatpak; then
    s="$(flatpak list --columns=application 2>/dev/null | grep -iE 'cursor|windsurf|zed|ollama|lmstudio|gpt4all|chatgpt|claude|alpaca|jan' || true)"
    [[ -n "$s" ]] && cm_warn "AI-related flatpaks installed: $(echo "$s" | paste -sd' ' -)"
  fi
  s="$(compgen -G '/opt/jetbrains*' || true)$(compgen -G '/opt/clion*' || true)$(compgen -G '/opt/idea*' || true)"
  [[ -n "$s" ]] && cm_warn "JetBrains IDE found — it ships an offline AI code-completion model; disable 'Full Line Code Completion' or remove it"
  return 0
}
