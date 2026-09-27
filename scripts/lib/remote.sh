#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# SSH transport to a VPS profile, with every connection detail read from the
# OS keychain. Callers must `trap d4a_remote_cleanup EXIT` so temporary key
# material is removed even on failure. Not meant to be executed directly;
# source common.sh, validate.sh and keychain.sh first.
set -euo pipefail

_d4a_remote_tmp=()
D4A_REMOTE_SSH=""
D4A_REMOTE_TARGET=""

d4a_remote_cleanup() {
  local f
  for f in "${_d4a_remote_tmp[@]:-}"; do
    [[ -n "$f" && -e "$f" ]] || continue
    if command -v shred >/dev/null 2>&1; then
      shred -u "$f" 2>/dev/null || rm -f "$f"
    else
      rm -f "$f"
    fi
  done
  unset SSHPASS
}

d4a_remote_open() {
  local profile="$1" host user port auth_method ssh_opts
  d4a_validate_profile_name "$profile"
  d4a_require_cmd ssh
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
  ssh_opts="-o UserKnownHostsFile=$D4A_KNOWN_HOSTS -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p $port"

  case "$auth_method" in
    key)
      local key_material key_file
      key_material="$(d4a_kc_get "$profile" vps_ssh_key)" \
        || d4a_die "no vps_ssh_key stored for profile '$profile'"
      key_file="$(mktemp "${TMPDIR:-/tmp}/d4a-key.XXXXXX")"
      _d4a_remote_tmp+=("$key_file")
      chmod 600 "$key_file"
      printf '%s\n' "$key_material" > "$key_file"
      D4A_REMOTE_SSH="ssh -i $key_file $ssh_opts"
      ;;
    password)
      d4a_require_cmd sshpass
      local pass
      pass="$(d4a_kc_get "$profile" vps_pass)" \
        || d4a_die "no vps_pass stored for profile '$profile'"
      export SSHPASS="$pass"
      D4A_REMOTE_SSH="sshpass -e ssh $ssh_opts"
      d4a_log "WARNING: password auth is weaker than a key; consider switching this profile to key-based auth"
      ;;
    *)
      d4a_die "unknown auth_method '$auth_method' for profile '$profile'"
      ;;
  esac
  D4A_REMOTE_TARGET="${user}@${host}"
}

d4a_remote_rsync() {
  local src="$1" dest="$2"
  shift 2
  d4a_require_cmd rsync
  rsync -az --delete-after "$@" -e "$D4A_REMOTE_SSH" -- "$src"/ "${D4A_REMOTE_TARGET}:${dest}/"
}

d4a_remote_run() {
  # shellcheck disable=SC2086  # D4A_REMOTE_SSH is a word list built only from validated values
  printf '%s\n' "$1" | $D4A_REMOTE_SSH "$D4A_REMOTE_TARGET" 'bash -s'
}

d4a_kv() {
  printf '%s\n' "$2" | awk -F= -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }'
}
