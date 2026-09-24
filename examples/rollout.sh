#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# rollout.sh — run cmanager on every PC of a lab over SSH.
#
# Prerequisites (once):
#   * every PC has contest_env installed (sudo ./install.sh) and 'cmanager setup' done;
#   * you can SSH to each PC as an admin with a key (ssh-copy-id admin@pc-01);
#   * that admin may run cmanager (and copy the allowlist) without a password
#     prompt. On each PC, create /etc/sudoers.d/cmanager with 'sudo visudo -f':
#       admin ALL=(root) NOPASSWD: /usr/local/bin/cmanager, \
#         /usr/bin/install -m 0644 /tmp/contest-whitelist.txt /etc/contest-env/whitelist.txt
#
# Usage:
#   ./rollout.sh HOSTS_FILE push ALLOWLIST_FILE   copy an allowlist to every PC and apply it
#   ./rollout.sh HOSTS_FILE restrict              contest mode ON everywhere
#   ./rollout.sh HOSTS_FILE verify                run 'cmanager verify' everywhere
#   ./rollout.sh HOSTS_FILE reset                 clean home on every PC (logs users out!)
#   ./rollout.sh HOSTS_FILE unrestrict            contest mode OFF everywhere
#   ./rollout.sh HOSTS_FILE status
#
# HOSTS_FILE: one "user@host" (or "host") per line, '#' comments allowed:
#   admin@192.168.10.101
#   admin@192.168.10.102
#
# Example:
#   ./rollout.sh lab-a.txt push examples/whitelist-codeforces-round.txt
#   ./rollout.sh lab-a.txt restrict
#   ./rollout.sh lab-a.txt verify
# -----------------------------------------------------------------------------
set -uo pipefail

usage() { sed -n '3,/^# ---/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^---/d'; exit 1; }
[[ $# -ge 2 ]] || usage

hosts_file="$1" action="$2" allowlist="${3:-}"
[[ -r "$hosts_file" ]] || { echo "Cannot read hosts file: $hosts_file" >&2; exit 1; }
mapfile -t hosts < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$hosts_file" | awk 'NF')
(( ${#hosts[@]} > 0 )) || { echo "No hosts in $hosts_file" >&2; exit 1; }

case "$action" in
  push)
    [[ -r "$allowlist" ]] || { echo "Usage: $0 HOSTS_FILE push ALLOWLIST_FILE" >&2; exit 1; }
    remote_cmd='sudo install -m 0644 /tmp/contest-whitelist.txt /etc/contest-env/whitelist.txt && sudo cmanager reload' ;;
  restrict|unrestrict|verify|status) remote_cmd="sudo cmanager $action" ;;
  reset)  remote_cmd="sudo cmanager reset --force" ;;
  *) usage ;;
esac

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)
ok=() failed=()
for h in "${hosts[@]}"; do
  printf '\n===== %s : %s =====\n' "$h" "$action"
  if [[ "$action" == push ]] && ! scp -q "${SSH_OPTS[@]}" "$allowlist" "$h:/tmp/contest-whitelist.txt"; then
    failed+=("$h"); continue
  fi
  # shellcheck disable=SC2029  # remote_cmd is meant to expand locally
  if ssh "${SSH_OPTS[@]}" "$h" "NO_COLOR=1 $remote_cmd"; then ok+=("$h"); else failed+=("$h"); fi
done

printf '\n===== Summary: %s =====\n' "$action"
printf 'OK     (%d): %s\n' "${#ok[@]}" "${ok[*]:-}"
printf 'FAILED (%d): %s\n' "${#failed[@]}" "${failed[*]:-}"
(( ${#failed[@]} == 0 ))
