#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Manage named VPS deploy profiles. All connection details and secrets
# live in the OS keychain; only profile names are recorded on disk.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"
# shellcheck source=./lib/keychain.sh
source "$DIR/lib/keychain.sh"
# shellcheck source=./lib/profiles.sh
source "$DIR/lib/profiles.sh"

usage() {
  cat <<'EOF'
Usage:
  vps-profile.sh list
  vps-profile.sh show <name>
  vps-profile.sh add <name> <host> <user> <port> key --key-file <path>
  vps-profile.sh add <name> <host> <user> <port> password
  vps-profile.sh remove <name>

"add" with "key" reads the private key from the given file itself — the
key content never appears on the command line. "add" with "password"
requires a real interactive terminal and refuses to run under a
non-interactive caller (such as an AI assistant's tool call), printing
this same instruction instead.
EOF
}

cmd_list() {
  local registry
  registry="$(d4a_profiles_registry)"
  if [[ ! -s "$registry" ]]; then
    d4a_log "no VPS profiles configured yet"
    return 0
  fi
  cat "$registry"
}

cmd_show() {
  local name="${1:-}" host user port auth_method
  [[ -n "$name" ]] || { usage; exit 2; }
  d4a_validate_profile_name "$name"
  d4a_profile_exists "$name" || d4a_die "no such profile: $name"
  host="$(d4a_kc_get "$name" vps_ip || echo '?')"
  user="$(d4a_kc_get "$name" vps_user || echo '?')"
  port="$(d4a_kc_get "$name" vps_port 2>/dev/null || echo 22)"
  auth_method="$(d4a_kc_get "$name" auth_method || echo '?')"
  printf 'profile: %s\n  host: %s\n  user: %s\n  port: %s\n  auth: %s\n' \
    "$name" "$host" "$user" "$port" "$auth_method"
}

cmd_add() {
  [[ $# -ge 5 ]] || { usage; exit 2; }
  local name="$1" host="$2" user="$3" port="$4" auth_method="$5"
  shift 5
  local key_file="" secret
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key-file) key_file="${2:-}"; shift 2 ;;
      *) d4a_die "unknown option: $1" ;;
    esac
  done

  d4a_validate_profile_name "$name"
  d4a_validate_host "$host"
  d4a_validate_port "$port"

  case "$auth_method" in
    key)
      [[ -n "$key_file" ]] || d4a_die "key auth requires --key-file <path-to-private-key>"
      [[ -f "$key_file" ]] || d4a_die "key file not found: $key_file"
      secret="$(cat "$key_file")"
      ;;
    password)
      if [[ -t 0 ]]; then
        read -r -s -p "VPS password for profile '$name' (input hidden): " secret
        echo >&2
      else
        d4a_die "password auth needs a real terminal — run this yourself, not through the assistant, so the password never appears in chat: $DIR/vps-profile.sh add $name $host $user $port password"
      fi
      ;;
    *)
      d4a_die "auth method must be 'key' or 'password', got: $auth_method"
      ;;
  esac
  [[ -n "$secret" ]] || d4a_die "empty secret; aborting"

  d4a_kc_set "$name" vps_ip "$host"
  d4a_kc_set "$name" vps_user "$user"
  d4a_kc_set "$name" vps_port "$port"
  d4a_kc_set "$name" auth_method "$auth_method"
  if [[ "$auth_method" == key ]]; then
    d4a_kc_set "$name" vps_ssh_key "$secret"
  else
    d4a_kc_set "$name" vps_pass "$secret"
  fi
  d4a_profile_add_name "$name"
  unset secret
  d4a_log "profile '$name' stored in the OS keychain"
}

cmd_remove() {
  local name="${1:-}"
  [[ -n "$name" ]] || { usage; exit 2; }
  d4a_validate_profile_name "$name"
  d4a_kc_delete "$name" vps_ip
  d4a_kc_delete "$name" vps_user
  d4a_kc_delete "$name" vps_port
  d4a_kc_delete "$name" auth_method
  d4a_kc_delete "$name" vps_ssh_key
  d4a_kc_delete "$name" vps_pass
  d4a_profile_remove_name "$name"
  d4a_log "profile '$name' removed"
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    list) cmd_list "$@" ;;
    show) cmd_show "$@" ;;
    add) cmd_add "$@" ;;
    remove) cmd_remove "$@" ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
