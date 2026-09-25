#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Deploy a fetched artifact directory to a VPS over SSH. All connection
# details are read from the OS keychain by profile name; nothing is read
# from disk, argv, or the environment except the profile name itself.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"
# shellcheck source=./lib/keychain.sh
source "$DIR/lib/keychain.sh"

usage() {
  cat <<'EOF'
Usage: deploy-vps.sh <profile> <source-dir> <remote-path>

Deploys <source-dir> to <remote-path> on the VPS identified by <profile>.
Host, user, port, and auth details come from the OS keychain — see the
vps-profiles skill to create a profile first.
EOF
}

_cleanup_files=()
_cleanup() {
  local f
  for f in "${_cleanup_files[@]:-}"; do
    [[ -n "$f" && -e "$f" ]] || continue
    if command -v shred >/dev/null 2>&1; then
      shred -u "$f" 2>/dev/null || rm -f "$f"
    else
      rm -f "$f"
    fi
  done
  unset SSHPASS
}
trap _cleanup EXIT

main() {
  [[ $# -eq 3 ]] || { usage; exit 2; }
  local profile="$1" src="$2" remote_path="$3"
  d4a_validate_profile_name "$profile"
  [[ -d "$src" ]] || d4a_die "source directory not found: $src"
  d4a_validate_remote_path "$remote_path"
  d4a_require_cmd rsync
  d4a_require_cmd ssh

  local host user port auth_method
  host="$(d4a_kc_get "$profile" vps_ip)" \
    || d4a_die "no vps_ip stored for profile '$profile' — create it with the vps-profiles skill"
  user="$(d4a_kc_get "$profile" vps_user)" \
    || d4a_die "no vps_user stored for profile '$profile'"
  port="$(d4a_kc_get "$profile" vps_port 2>/dev/null)" || port="22"
  auth_method="$(d4a_kc_get "$profile" auth_method)" \
    || d4a_die "no auth_method stored for profile '$profile'"

  d4a_validate_host "$host"
  d4a_validate_port "$port"

  mkdir -p "$D4A_HOME"
  chmod 700 "$D4A_HOME"
  touch "$D4A_KNOWN_HOSTS"
  chmod 600 "$D4A_KNOWN_HOSTS"

  local ssh_opts rsync_ssh
  ssh_opts="-o UserKnownHostsFile=$D4A_KNOWN_HOSTS -o StrictHostKeyChecking=accept-new -p $port"

  case "$auth_method" in
    key)
      local key_material key_file
      key_material="$(d4a_kc_get "$profile" vps_ssh_key)" \
        || d4a_die "no vps_ssh_key stored for profile '$profile'"
      key_file="$(mktemp "${TMPDIR:-/tmp}/d4a-key.XXXXXX")"
      _cleanup_files+=("$key_file")
      chmod 600 "$key_file"
      printf '%s\n' "$key_material" > "$key_file"
      rsync_ssh="ssh -i $key_file $ssh_opts"
      ;;
    password)
      d4a_require_cmd sshpass
      local pass
      pass="$(d4a_kc_get "$profile" vps_pass)" \
        || d4a_die "no vps_pass stored for profile '$profile'"
      export SSHPASS="$pass"
      rsync_ssh="sshpass -e ssh $ssh_opts"
      d4a_log "WARNING: password auth is weaker than a key; consider switching this profile to key-based auth"
      ;;
    *)
      d4a_die "unknown auth_method '$auth_method' for profile '$profile'"
      ;;
  esac

  d4a_log "deploying to ${user}@${host}:${remote_path} (profile: $profile)"
  rsync -az --delete-after -e "$rsync_ssh" -- "$src"/ "${user}@${host}:${remote_path}/"
  d4a_log "deploy complete"
}

main "$@"
